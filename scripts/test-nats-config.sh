#!/usr/bin/env bash
# Test script to validate NATS JetStream configuration

set -euo pipefail

echo "🧪 Testing NATS JetStream Configuration..."
echo "=========================================="

# Test NATS module syntax
echo ""
echo "📋 Testing NATS Module Syntax..."
cd /home/nathan/Projects/rave

# Check NATS module syntax
if nix-instantiate --parse infra/nixos/modules/services/nats/default.nix > /dev/null 2>&1; then
    echo "✅ NATS module syntax is valid"
else
    echo "❌ NATS module has syntax errors"
    exit 1
fi

# Test configuration files syntax
echo ""
echo "📋 Testing Configuration File Syntax..."

if nix-instantiate --parse infra/nixos/configs/modular-development.nix > /dev/null 2>&1; then
    echo "✅ Development config syntax is valid"
else
    echo "❌ Development config has syntax errors"
    exit 1
fi

if nix-instantiate --parse infra/nixos/configs/modular-production.nix > /dev/null 2>&1; then
    echo "✅ Production config syntax is valid"
else
    echo "❌ Production config has syntax errors"
    exit 1
fi

# Test NATS module integration
echo ""
echo "📋 Testing NATS Module Integration..."

if nix-build test-nats-minimal.nix --no-out-link > /dev/null 2>&1; then
    echo "✅ NATS module integrates successfully with NixOS"
else
    echo "❌ NATS module integration failed"
    exit 1
fi

# Check if NATS package is available
echo ""
echo "📦 Testing NATS Package Availability..."
if nix-env -qa nats-server | grep -q nats-server; then
    echo "✅ NATS server package is available"
else
    echo "⚠️  NATS server package not found in current channel"
fi

if nix-env -qa natscli | grep -q natscli; then
    echo "✅ NATS CLI package is available"  
else
    echo "⚠️  NATS CLI package not found in current channel"
fi

echo ""
echo "🔧 NATS Configuration Summary:"
echo "=============================="
echo "Development Settings:"
echo "  • Server Name: rave-dev-nats"  
echo "  • Debug Logging: Enabled"
echo "  • Authentication: Disabled"
echo "  • JetStream Memory: 128MB"
echo "  • JetStream Storage: 512MB"
echo "  • Safe Mode: Disabled (more resources)"
echo ""
echo "Production Settings:"
echo "  • Server Name: rave-prod-nats"
echo "  • Debug Logging: Disabled"
echo "  • Authentication: Enabled (3 users: gitlab, matrix, monitoring)" 
echo "  • JetStream Memory: 512MB"
echo "  • JetStream Storage: 2GB"
echo "  • Safe Mode: Enabled (resource limits)"
echo "  • Max Connections: 100,000"
echo ""
echo "🎯 Integration Points:"
echo "  • Firewall: Ports 4222 (client) and 8222 (monitoring) opened"
echo "  • Nginx: /nats/ proxy to monitoring interface"
echo "  • Log Rotation: Daily rotation of NATS logs"  
echo "  • Health Checks: Automated health monitoring"
echo "  • Security: Systemd hardening enabled"
echo ""
echo "✅ NATS JetStream configuration validation complete!"
echo ""
echo "🚀 Next Steps:"
echo "  1. Build VM with: nix-build infra/nixos/configs/modular-development.nix"
echo "  2. Start VM and verify NATS is running: systemctl status nats"
echo "  3. Check NATS monitoring: curl http://rave.local/nats/healthz"
echo "  4. Test JetStream: nats stream create test-stream"