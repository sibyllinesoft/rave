# Simple vibe-kanban derivation using NPM with FHS compatibility
{ lib, stdenv, fetchurl, nodejs_20, pnpm, unzip, steam-run }:

stdenv.mkDerivation rec {
  pname = "vibe-kanban";
  version = "0.0.64";
  
  src = fetchurl {
    url = "https://registry.npmjs.org/vibe-kanban/-/vibe-kanban-${version}.tgz";
    sha512 = "arYw5Pv7tnxdPcX823Af1l9HyuX1inVm3S4etx9qp+WitCbkKev2HzPtx9XkpKXU4REEPbp+AL7y7h8KtNz8Vg==";
  };
  
  nativeBuildInputs = [ nodejs_20 pnpm unzip ];
  
  unpackPhase = ''
    mkdir -p source
    tar xzf $src -C source --strip-components=1
  '';
  
  buildPhase = ''
    cd source
    
    # Install dependencies
    export HOME=$TMPDIR
    pnpm config set store-dir $TMPDIR/pnpm
    pnpm install --frozen-lockfile
    
    # Build if needed
    if [ -f package.json ] && grep -q '"build"' package.json; then
      pnpm run build
    fi
    
    # Pre-extract the linux-x64 binary since Nix store is read-only
    echo "Pre-extracting linux-x64 binary..."
    cd dist/linux-x64
    ${unzip}/bin/unzip -qq vibe-kanban.zip
    chmod +x vibe-kanban
    cd ../..
  '';
  
  installPhase = ''
    mkdir -p $out/bin $out/lib/node_modules/vibe-kanban
    
    # Copy the package
    cp -r ./* $out/lib/node_modules/vibe-kanban/
    
    # Create executable wrapper that uses the CLI entry point
    cat > $out/bin/vibe-kanban <<EOF
#!/bin/bash
exec ${nodejs_20}/bin/node $out/lib/node_modules/vibe-kanban/bin/cli.js "\$@"
EOF
    chmod +x $out/bin/vibe-kanban
    
    # Patch the CLI script to use pre-extracted binary
    cat > $out/lib/node_modules/vibe-kanban/bin/cli.js <<'EOF'
#!/usr/bin/env node

const { spawn, execSync } = require("child_process");
const path = require("path");
const fs = require("fs");

// Since we're in Nix, we pre-extracted the linux-x64 binary
const platform = "linux";
const arch = "x64";

function getBinaryName(base) {
  return platform === "win32" ? base + ".exe" : base;
}

const platformDir = platform + "-" + arch;
const extractDir = path.join(__dirname, "..", "dist", platformDir);
const isMcpMode = process.argv.includes("--mcp");

if (isMcpMode) {
  const binName = getBinaryName("vibe-kanban-mcp");
  const binPath = path.join(extractDir, binName);
  
  if (!fs.existsSync(binPath)) {
    console.error("❌ " + binName + " not found at: " + binPath);
    process.exit(1);
  }
  
  const proc = spawn("${steam-run}/bin/steam-run", [binPath], { stdio: "inherit" });
  proc.on("exit", (c) => process.exit(c || 0));
  proc.on("error", (e) => {
    console.error("❌ MCP server error:", e.message);
    process.exit(1);
  });
  process.on("SIGINT", () => {
    console.error("\n🛑 Shutting down MCP server...");
    proc.kill("SIGINT");
  });
  process.on("SIGTERM", () => proc.kill("SIGTERM"));
} else {
  const binName = getBinaryName("vibe-kanban");
  const binPath = path.join(extractDir, binName);
  
  if (!fs.existsSync(binPath)) {
    console.error("❌ " + binName + " not found at: " + binPath);
    console.error("Expected path: " + binPath);
    console.error("Available files in " + extractDir + ":");
    try {
      console.error(fs.readdirSync(extractDir));
    } catch (e) {
      console.error("Directory not accessible");
    }
    process.exit(1);
  }
  
  console.log("🚀 Launching vibe-kanban with FHS compatibility...");
  execSync('${steam-run}/bin/steam-run "' + binPath + '"', { stdio: "inherit" });
}
EOF
  '';
  
  meta = with lib; {
    description = "A simple kanban board application";
    homepage = "https://github.com/BloopAI/vibe-kanban";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.linux;
  };
}