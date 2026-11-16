{
  description = "statics — hermetic build environment (pinned Zig toolchain + host tools)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # The two host architectures the project's Zig toolchain ships for; the
      # cross target is chosen per-build with ARCH, not per-host.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEach = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forEach (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;

          # Single source of truth: the same pinned Zig and Go the container
          # fetches. Parse their sources.lock records (name|version|sha256|url)
          # so the dev shell and docker/Dockerfile can never drift apart.
          hostSuffix = if system == "aarch64-linux" then "aarch64" else "x86_64";
          lockLines = lib.splitString "\n" (builtins.readFile ./sources.lock);
          lockRecord = name:
            let line = lib.findFirst (l: lib.hasPrefix "${name}|" l) null lockLines;
            in if line == null
              then throw "no ${name} record in sources.lock"
              else lib.splitString "|" line;
          zigFields = lockRecord "zig-${hostSuffix}";
          zigVersion = builtins.elemAt zigFields 1;
          goFields = lockRecord "go-${hostSuffix}";
          goVersion = builtins.elemAt goFields 1;

          zigTarball = pkgs.fetchurl {
            url = builtins.elemAt zigFields 3;
            sha256 = builtins.elemAt zigFields 2;
          };
          goTarball = pkgs.fetchurl {
            url = builtins.elemAt goFields 3;
            sha256 = builtins.elemAt goFields 2;
          };

          zig = pkgs.runCommand "zig-${zigVersion}"
            { nativeBuildInputs = [ pkgs.gnutar pkgs.xz ]; }
            ''
              mkdir -p "$out/bin"
              tar -xJf ${zigTarball} -C "$out/bin" --strip-components=1
              # The launcher scripts under scripts/toolchain/ invoke `zig`.
              test -x "$out/bin/zig"
            '';

          go = pkgs.runCommand "go-${goVersion}"
            { nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ]; }
            ''
              mkdir -p "$out"
              tar -xzf ${goTarball} -C "$out" --strip-components=1
              test -x "$out/bin/go"
            '';
        in
        {
          default = pkgs.mkShell {
            # Host tools mirror docker/Dockerfile's apt set so a local build
            # matches CI; versions are pinned by flake.lock.
            packages = [
              zig
              go
              pkgs.bashInteractive
              pkgs.gnumake
              pkgs.autoconf
              pkgs.automake
              pkgs.libtool
              pkgs.cmake
              pkgs.meson
              pkgs.ninja
              pkgs.pkg-config
              pkgs.gcc
              pkgs.binutils
              pkgs.flex
              pkgs.bison
              pkgs.perl
              pkgs.python3
              pkgs.jq
              pkgs.curl
              pkgs.cacert
              pkgs.file
              pkgs.patch
              pkgs.xz
              pkgs.bzip2
              pkgs.gzip
              pkgs.gnutar
              pkgs.gnused
              pkgs.gawk
              pkgs.coreutils
              pkgs.shellcheck
            ];

            shellHook = ''
              export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              export GOTOOLCHAIN=local
              echo "statics dev shell — Zig ${zigVersion}, Go ${goVersion} (pinned via sources.lock)"
              echo "  fetch sources : scripts/fetch-sources.sh --archives .cache --extract .src --bundle .archives"
              echo "                  scripts/fetch-go-modules.sh .src .archives/go-modules"
              echo "  build one arch: SOURCES_DIR=.src BUILD_DIR=.build scripts/build.sh x86_64 out"
              echo "  validate      : scripts/validate.sh"
            '';
          };
        });
    };
}
