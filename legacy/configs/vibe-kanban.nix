# Proper Nix derivation for vibe-kanban
{ lib, rustPlatform, fetchFromGitHub, pkg-config, openssl, pnpm, nodejs_20 }:

rustPlatform.buildRustPackage rec {
  pname = "vibe-kanban";
  version = "0.0.64-20250819174325";
  
  src = fetchFromGitHub {
    owner = "BloopAI";
    repo = "vibe-kanban";
    rev = "v${version}";
    sha256 = "sha256-EUAyLy1vX8ihpFz7MR8xJYw4AfTbrop42hBBWAGLWLg=";
  };
  
  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder for now
  
  # Use workspace building mode
  cargoBuildFlags = [ "--workspace" ];
  cargoTestFlags = [ "--workspace" ];
  
  nativeBuildInputs = [ pkg-config pnpm nodejs_20 ];
  buildInputs = [ openssl ];
  
  # Generate Cargo.lock if missing (common for workspaces)
  cargoPatches = [];
  
  # Build the web frontend first
  preBuild = ''
    echo "Building frontend..."
    cd frontend
    export HOME=$TMPDIR
    pnpm config set store-dir $TMPDIR/pnpm
    pnpm install --frozen-lockfile
    pnpm run build
    cd ..
  '';
  
  # Install the server binary
  postInstall = ''
    # The main binary should be 'server'
    mkdir -p $out/bin
    cp -f $out/bin/server $out/bin/vibe-kanban || true
    
    # Include frontend build if it exists
    if [ -d frontend/dist ]; then
      mkdir -p $out/share/vibe-kanban
      cp -r frontend/dist/* $out/share/vibe-kanban/ 2>/dev/null || true
    fi
  '';
  
  meta = with lib; {
    description = "A simple kanban board application";
    homepage = "https://github.com/BloopAI/vibe-kanban";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.linux;
  };
}