{ ... }:
{
  perSystem = { pkgs, ... }: {
    devShells = {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          python3
          python3Packages.click
          qemu
          nix
          go_1_24
        ];
        shellHook = ''
          unset GOROOT
          if [ -z "''${GOPATH:-}" ] || [ "''${GOPATH}" = "$HOME/go" ]; then
            export GOPATH="$(pwd)/.gopath"
          fi
          mkdir -p "$GOPATH"
          export PATH="$PATH:$(pwd)/src/apps/cli"
          echo "🚀 RAVE Development Environment"
          echo "CLI available at: $(pwd)/src/apps/cli/rave"
          go version 2>/dev/null || true
        '';
      };
    };
  };
}
