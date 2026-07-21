{
  description = "Buzz — self-hostable workspace for humans and agents (built from source)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        # Pin to the commit behind desktop release v0.4.22 / current main.
        rev = "e9188c03f6c2460983a3dac0fa7702b468838e62";
        version = "0.4.22";

        src = pkgs.fetchFromGitHub {
          owner = "block";
          repo = "buzz";
          inherit rev;
          hash = "sha256-MDroR4oo4F2INwMA60cZnZWsyv9fyp9Dy3i2nopf/0U=";
        };

        rustPlatform = pkgs.rustPlatform;

        # Native inputs shared by rust builds. Mostly rustls, but several
        # crates (aws-lc-sys, iroh, tonic/OTLP) still need the usual toolchain.
        rustNativeBuildInputs = with pkgs; [
          pkg-config
          protobuf
          cmake
          perl
          git
        ];

        rustBuildInputs = with pkgs; [
          openssl
        ];

        # Local copy of upstream Cargo.lock (avoids IFD from fetchFromGitHub).
        # Git deps (aws-creds fork + mesh-llm test-only tree): allowBuiltinFetchGit
        # is pure when the lockfile pins full commit SHAs.
        cargoLockCommon = {
          lockFile = ./Cargo.lock;
          allowBuiltinFetchGit = true;
        };

        # ---- Rust server binaries (matches the public Dockerfile) ----
        buzz-server = rustPlatform.buildRustPackage {
          pname = "buzz-server";
          inherit version src;

          cargoLock = cargoLockCommon;

          nativeBuildInputs = rustNativeBuildInputs ++ [ pkgs.makeWrapper ];
          buildInputs = rustBuildInputs;

          # mesh-llm is only a buzz-relay *dev*-dependency (integration tests).
          # We still vendor it via the lockfile; do not run those tests here.
          doCheck = false;

          cargoBuildFlags = [
            "-p"
            "buzz-relay"
            "--bin"
            "buzz-relay"
            "-p"
            "buzz-admin"
            "--bin"
            "buzz-admin"
            "-p"
            "buzz-pair-relay"
            "--bin"
            "buzz-pair-relay"
          ];

          # cargo install only does one package cleanly; install all three.
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            local releaseDir
            releaseDir="$(find target -type f -name buzz-relay -path '*/release/buzz-relay' | head -n1 | xargs dirname)"
            install -Dm755 "$releaseDir/buzz-relay" $out/bin/buzz-relay
            install -Dm755 "$releaseDir/buzz-admin" $out/bin/buzz-admin
            install -Dm755 "$releaseDir/buzz-pair-relay" $out/bin/buzz-pair-relay
            runHook postInstall
          '';

          meta = {
            description = "Buzz relay server, admin CLI, and pairing relay";
            homepage = "https://github.com/block/buzz";
            license = lib.licenses.asl20;
            mainProgram = "buzz-relay";
            platforms = lib.platforms.linux ++ lib.platforms.darwin;
          };
        };

        # Agent-first CLI (JSON in / JSON out).
        buzz-cli = rustPlatform.buildRustPackage {
          pname = "buzz-cli";
          inherit version src;

          cargoLock = cargoLockCommon;

          nativeBuildInputs = rustNativeBuildInputs;
          buildInputs = rustBuildInputs;

          doCheck = false;

          cargoBuildFlags = [
            "-p"
            "buzz-cli"
            "--bin"
            "buzz"
          ];

          cargoInstallFlags = [
            "-p"
            "buzz-cli"
            "--bin"
            "buzz"
          ];

          meta = {
            description = "Buzz agent-first CLI";
            homepage = "https://github.com/block/buzz";
            license = lib.licenses.asl20;
            mainProgram = "buzz";
            platforms = lib.platforms.linux ++ lib.platforms.darwin;
          };
        };

        # ACP harness + related agent tooling.
        buzz-tools = rustPlatform.buildRustPackage {
          pname = "buzz-tools";
          inherit version src;

          cargoLock = cargoLockCommon;

          nativeBuildInputs = rustNativeBuildInputs;
          buildInputs = rustBuildInputs;

          doCheck = false;

          cargoBuildFlags = [
            "-p"
            "buzz-acp"
            "--bin"
            "buzz-acp"
            "-p"
            "buzz-agent"
            "--bin"
            "buzz-agent"
            "-p"
            "buzz-push-gateway"
            "--bin"
            "buzz-push-gateway"
            "-p"
            "buzz-dev-mcp"
          ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            local releaseDir
            releaseDir="$(find target -type f -name buzz-acp -path '*/release/buzz-acp' | head -n1 | xargs dirname)"
            for b in buzz-acp buzz-agent buzz-push-gateway buzz-dev-mcp; do
              if [ -f "$releaseDir/$b" ]; then
                install -Dm755 "$releaseDir/$b" "$out/bin/$b"
              fi
            done
            runHook postInstall
          '';

          meta = {
            description = "Buzz agent tooling (ACP harness, agent, push gateway, dev MCP)";
            homepage = "https://github.com/block/buzz";
            license = lib.licenses.asl20;
            platforms = lib.platforms.linux ++ lib.platforms.darwin;
          };
        };

        # ---- Web + admin-web static bundles (pnpm + vite) ----
        pnpm = pkgs.pnpm_11;
        nodejs = pkgs.nodejs_24;

        buzz-web = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "buzz-web";
          inherit version src;

          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (finalAttrs) pname version src;
            inherit pnpm;
            fetcherVersion = 3;
            # Mirror the Dockerfile: only the browser UIs, not desktop/Tauri.
            pnpmWorkspaces = [
              "buzz-web"
              "buzz-admin-web"
            ];
            # Placeholder — filled after first build failure.
            hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };

          nativeBuildInputs = [
            nodejs
            pnpm
            pkgs.pnpmConfigHook
          ];

          # Keep install scoped like the Docker web-builder stage.
          pnpmInstallFlags = [
            "--filter=buzz-web"
            "--filter=buzz-admin-web"
          ];

          buildPhase = ''
            runHook preBuild
            pnpm -C web build
            pnpm -C admin-web build
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/buzz
            cp -r web/dist $out/share/buzz/web
            cp -r admin-web/dist $out/share/buzz/admin-web
            runHook postInstall
          '';

          meta = {
            description = "Buzz web and admin-web static assets";
            homepage = "https://github.com/block/buzz";
            license = lib.licenses.asl20;
            platforms = lib.platforms.all;
          };
        });

        # Full self-host package: binaries + web UI, with sensible defaults.
        buzz = pkgs.stdenvNoCC.mkDerivation {
          pname = "buzz";
          inherit version;

          dontUnpack = true;
          dontBuild = true;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/share/buzz
            cp -a ${buzz-server}/bin/. $out/bin/
            cp -a ${buzz-web}/share/buzz/. $out/share/buzz/

            wrapProgram $out/bin/buzz-relay \
              --prefix PATH : ${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.cacert
                ]
              } \
              --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              --set-default BUZZ_WEB_DIR "$out/share/buzz/web" \
              --set-default BUZZ_ADMIN_WEB_DIR "$out/share/buzz/admin-web"
            runHook postInstall
          '';

          meta = {
            description = "Buzz relay with bundled web UI (build-from-source)";
            homepage = "https://github.com/block/buzz";
            license = lib.licenses.asl20;
            mainProgram = "buzz-relay";
            platforms = lib.platforms.linux ++ lib.platforms.darwin;
          };
        };
      in
      {
        packages = {
          default = buzz;
          buzz = buzz;
          server = buzz-server;
          cli = buzz-cli;
          tools = buzz-tools;
          web = buzz-web;
        };

        apps = {
          default = {
            type = "app";
            program = "${buzz}/bin/buzz-relay";
          };
          buzz-relay = {
            type = "app";
            program = "${buzz}/bin/buzz-relay";
          };
          buzz = {
            type = "app";
            program = "${buzz-cli}/bin/buzz";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            rustc
            cargo
            rustfmt
            clippy
            pkg-config
            openssl
            protobuf
            cmake
            perl
            git
            nodejs_24
            pnpm_11
            just
            sqlx-cli
            docker-compose
          ];

          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

          shellHook = ''
            echo "Buzz dev shell"
            echo "  rustc:  $(rustc --version)"
            echo "  node:   $(node --version)"
            echo "  pnpm:   $(pnpm --version)"
            echo
            echo "Packages from this flake:"
            echo "  nix build .#          # relay + web UI"
            echo "  nix build .#server    # rust binaries only"
            echo "  nix build .#cli       # buzz CLI"
            echo "  nix build .#tools     # acp/agent/push-gateway"
            echo "  nix build .#web       # static web assets"
            echo
            echo "Upstream quick start still needs Postgres + Redis (see docker-compose.yml)."
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
