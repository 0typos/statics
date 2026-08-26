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

          # Single source of truth: the same pinned Zig the container fetches.
          # Parse its sources.lock record (name|version|sha256|url) so the dev
          # shell and docker/Dockerfile can never drift apart.
          zigHost = if system == "aarch64-linux" then "zig-aarch64" else "zig-x86_64";
          lockLines = lib.splitString "\n" (builtins.readFile ./sources.lock);
          zigLine = lib.findFirst (l: lib.hasPrefix "${zigHost}|" l) null lockLines;
          zigFields =
            if zigLine == null
            then throw "no ${zigHost} record in sources.lock"
            else lib.splitString "|" zigLine;
          zigVersion = builtins.elemAt zigFields 1;
          zigSha256 = builtins.elemAt zigFields 2;
          zigUrl = builtins.elemAt zigFields 3;

          zigTarball = pkgs.fetchurl {
            url = zigUrl;
            sha256 = zigSha256;
          };

          zig = pkgs.runCommand "zig-${zigVersion}"
            { nativeBuildInputs = [ pkgs.gnutar pkgs.xz ]; }
            ''
              mkdir -p "$out/bin"
              tar -xJf ${zigTarball} -C "$out/bin" --strip-components=1
              # The launcher scripts under scripts/toolchain/ invoke `zig`.
              test -x "$out/bin/zig"
            '';
        in
        {
          default = pkgs.mkShell {
            # Host tools mirror docker/Dockerfile's apt set so a local build
            # matches CI; versions are pinned by flake.lock.
            packages = [
              zig
              pkgs.bashInteractive
              pkgs.gnumake
              pkgs.autoconf
              pkgs.automake
              pkgs.libtool
              pkgs.cmake
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
              echo "statics dev shell — Zig ${zigVersion} (pinned via sources.lock)"
              echo "  fetch sources : scripts/fetch-sources.sh --archives .cache --extract .src --bundle .archives"
              echo "  build one arch: SOURCES_DIR=.src BUILD_DIR=.build scripts/build.sh x86_64 out"
              echo "  validate      : scripts/validate.sh"
            '';
          };
        });
    };
}
