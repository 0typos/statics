#!/usr/bin/env bash

# CPython's ssl and hashlib refuse an OpenSSL built without threads, which
# the shared one is on 32-bit targets (dependencies.sh). There, build the
# libraries a second time, threaded, into a tree only python sees.
build_python_openssl() { # prefix
    local prefix=$1
    mkdir openssl-threads
    cp -a "$SOURCES_DIR/openssl/." openssl-threads/
    (
        cd openssl-threads || exit
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./Configure \
            "linux-generic$TARGET_BITS" \
            no-asm no-docs no-module no-shared no-tests no-apps \
            --prefix="$prefix" \
            --libdir=lib \
            --openssldir=/etc/ssl \
            "$STATIC_CFLAGS" \
            "$STATIC_LDFLAGS"
        run_make build_libs
        make -s install_dev
        # Threaded libcrypto asks __atomic_is_lock_free whether a 64-bit
        # atomic needs its own lock, and Zig's compiler-rt has every
        # __atomic_* routine but that one. On these 32-bit targets the
        # honest answer is "word-sized and smaller only"; libcrypto then
        # takes its lock for anything wider.
        cat > atomic-is-lock-free.c <<'STUB'
#include <stdbool.h>
#include <stddef.h>
/* Clang will not compile a definition under the builtin's own name. */
bool statics_atomic_is_lock_free(size_t size, const volatile void *object)
    __asm__("__atomic_is_lock_free");
bool statics_atomic_is_lock_free(size_t size, const volatile void *object)
{
    (void)object;
    return size <= sizeof(void *);
}
STUB
        # shellcheck disable=SC2086  # flag list
        "$CC" $STATIC_CFLAGS -c atomic-is-lock-free.c
        "$AR" r "$prefix/lib/libcrypto.a" atomic-is-lock-free.o
        "$RANLIB" "$prefix/lib/libcrypto.a"
    )
}

build_python() {
    echo "==> building python"
    (
        cd "$WORK_DIR/python" || exit
        # Configure insists on a build interpreter of the same X.Y to freeze
        # modules and generate sysconfig data; the Dockerfile's build-python
        # stage compiles it natively from this same source.
        local build_python=${STATICS_BUILD_PYTHON:-/opt/build-python/python}
        [[ -x $build_python ]] || {
            echo "no build python at $build_python (set STATICS_BUILD_PYTHON)" >&2
            exit 1
        }
        local version series
        version=$(source_version python)
        series=${version%.*}

        local openssl=$DEPS_PREFIX
        if [[ $TARGET_BITS == 32 ]]; then
            openssl=$PWD/openssl-install
            # Not `|| exit`: that would switch errexit off inside it.
            build_python_openssl "$openssl"
        fi

        # What configure's run-time probes find on Linux with musl; a cross
        # build would otherwise assume the worst (FNV instead of SipHash for
        # str hashes, no computed gotos, broken sem_getvalue and tzset).
        # Nothing needs aligned access: the one consumer of that answer is
        # the choice of str hash, and SipHash reads through memcpy.
        # pentium2 has no SSE2, so doubles round on the x87; wchar_t is
        # unsigned on ARM.
        local x87=no wchar_signed=yes
        case $STATICS_ARCH in
            i686) x87=yes ;;
            aarch64 | armv6-hardfloat | armv7-hardfloat | armv7-softfloat) wchar_signed=no ;;
        esac

        local expat=$WORK_DIR/expat/install sqlite=$WORK_DIR/sqlite
        # Every extension module is compiled in (MODULE_BUILDTYPE=static): a
        # static program cannot dlopen. zlib, bz2, lzma, zstd, sqlite3, ssl
        # and hashlib (OpenSSL), and pyexpat link the kit's own libraries,
        # named here so configure neither asks pkg-config nor finds the
        # builder's. Not built: ctypes (libffi), the _decimal accelerator
        # (libmpdec; decimal falls back to pure Python), readline and
        # curses (the REPL is pure Python), tkinter, dbm, and the uuid
        # helper. No pip: ensurepip is left out.
        CC="$CC" AR="$AR" RANLIB="$RANLIB" ./configure \
            --build="$(cc -dumpmachine)" \
            --host="$AUTOCONF_HOST" \
            --prefix=/usr \
            --with-build-python="$build_python" \
            --disable-shared \
            --without-ensurepip \
            --disable-test-modules \
            --enable-ipv6 \
            --with-computed-gotos \
            --with-system-expat \
            --with-openssl="$openssl" \
            --with-openssl-rpath=no \
            --with-pkg-config=no \
            --without-readline \
            MODULE_BUILDTYPE=static \
            ac_cv_file__dev_ptmx=yes \
            ac_cv_file__dev_ptc=no \
            ac_cv_buggy_getaddrinfo=no \
            ac_cv_aligned_required=no \
            ac_cv_x87_double_rounding="$x87" \
            ac_cv_wchar_t_signed="$wchar_signed" \
            ac_cv_broken_sem_getvalue=no \
            ac_cv_working_tzset=yes \
            ac_cv_pthread_is_default=yes \
            ac_cv_pthread_system_supported=yes \
            ZLIB_CFLAGS="-I$COMPRESSION_PREFIX/include" \
            ZLIB_LIBS="-L$COMPRESSION_PREFIX/lib -lz" \
            BZIP2_CFLAGS="-I$COMPRESSION_PREFIX/include" \
            BZIP2_LIBS="-L$COMPRESSION_PREFIX/lib -lbz2" \
            LIBLZMA_CFLAGS="-I$COMPRESSION_PREFIX/include" \
            LIBLZMA_LIBS="-L$COMPRESSION_PREFIX/lib -llzma" \
            LIBZSTD_CFLAGS="-I$COMPRESSION_PREFIX/include" \
            LIBZSTD_LIBS="-L$COMPRESSION_PREFIX/lib -lzstd" \
            LIBSQLITE3_CFLAGS="-I$sqlite" \
            LIBSQLITE3_LIBS="-L$sqlite -lsqlite3" \
            LIBEXPAT_CFLAGS="-I$expat/include" \
            LIBEXPAT_LDFLAGS="-L$expat/lib -lexpat" \
            CFLAGS="$STATIC_CFLAGS -Wno-date-time" \
            LDFLAGS="$STATIC_LDFLAGS"
        # configure drops a module whose library probe fails and carries on;
        # a python3 without one of these is not what the kit documents.
        local module
        for module in _ssl _hashlib zlib _bz2 _lzma _zstd _sqlite3 pyexpat; do
            grep -q "^MODULE_${module^^}_STATE=yes\$" Makefile || {
                echo "python: configure did not enable $module" >&2
                sed -n '/OpenSSL provides required/,/^configure:.*result:/p' config.log |
                    grep -v '^| ' | tail -n 40 >&2
                exit 1
            }
        done
        run_make python pybuilddir.txt
        install_component_binary python python python3

        # The standard library as one zip beside the executable, where
        # CPython looks for it unprompted (lib/pythonXY.zip).
        # An empty lib-dynload is what CPython takes as proof that it found
        # its platform directory; without one it warns at every start.
        local destination
        destination=$(archive_dir python) || exit
        echo "Empty on purpose: every extension module is built into python3." \
            > lib-dynload-README
        install -D -m 0644 lib-dynload-README \
            "$destination/lib/python$series/lib-dynload/README"
        local sysconfigdata
        sysconfigdata=$(echo "$(cat pybuilddir.txt)"/_sysconfigdata_*.py)
        # It records the build: keep the builder's own triple out, the one
        # value that differs between an amd64 and an arm64 builder
        # (x86_64-pc-linux-gnu, or x86_64-linux-gnu as --build; never the
        # target's, which ends in musl).
        sed -i -E "s/$(uname -m)(-[a-z]+)?-linux-gnu/build-linux-gnu/g" "$sysconfigdata"
        grep -q "$(uname -m)-[a-z-]*linux-gnu" "$sysconfigdata" && {
            echo "python: the builder's triple is still in $sysconfigdata" >&2
            exit 1
        }
        # Bytecode beside each source, compiled by the build python (the
        # same X.Y, so the same format): a zip has nowhere to cache it, and
        # compiling http.client and ssl on each start takes seconds on a
        # slow target. Unchecked hash-based files carry no timestamp. -s and
        # -p make tracebacks name pythonXY.zip/NAME.py rather than Lib/NAME.py.
        # One process, never -j: parallel compiles changed the bytes.
        cp "$sysconfigdata" Lib/
        "$build_python" -m compileall -q -b --invalidation-mode unchecked-hash \
            -s Lib -p "python${series/./}.zip" \
            -x '/(test|tests|idlelib|tkinter|turtledemo|ensurepip|site-packages)/' Lib >/dev/null
        python3 "$REPO_ROOT/scripts/python-stdlib-zip.py" Lib \
            "$destination/lib/python${series/./}.zip"
        chmod 0644 "$destination/lib/python${series/./}.zip"
    )
}
