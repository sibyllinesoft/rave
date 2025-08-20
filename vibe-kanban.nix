# Proper Nix derivation for vibe-kanban
{ lib, rustPlatform, fetchFromGitHub, pkg-config, openssl, pnpm, nodejs_20 }:

rustPlatform.buildRustPackage rec {
  pname = "vibe-kanban";
  version = "0.0.64";
  
  src = fetchFromGitHub {
    owner = "thewh1teagle";
    repo = "vibe-kanban";
    rev = "v${version}";
    sha256 = lib.fakeSha256; # This will fail with the correct hash to use
  };
  
  cargoHash = lib.fakeSha256; # This will fail with the correct hash to use
  
  nativeBuildInputs = [ pkg-config pnpm nodejs_20 ];
  buildInputs = [ openssl ];
  
  # Build the web frontend first
  preBuild = ''
    echo "Building frontend..."
    export HOME=$TMPDIR
    pnpm config set store-dir $TMPDIR/pnpm
    pnpm install --frozen-lockfile
    pnpm run build
  '';
  
  # Make sure the frontend build is included
  postInstall = ''
    mkdir -p $out/share/vibe-kanban
    cp -r dist/* $out/share/vibe-kanban/ 2>/dev/null || true
  '';
  
  meta = with lib; {
    description = "A simple kanban board application";
    homepage = "https://github.com/thewh1teagle/vibe-kanban";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.linux;
  };
}