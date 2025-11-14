#!/bin/bash
# Test script for GitLab-Mattermost integration

set -euo pipefail

echo "🧪 Testing GitLab-Mattermost Integration"
echo "======================================="

HTTPS_PORT="${HTTPS_PORT:-8443}"
BASE_URL="https://localhost:${HTTPS_PORT}"
MATTERMOST_URL="${BASE_URL}/mattermost/"
GITLAB_URL="${BASE_URL}/gitlab/"

# Check if VM is running
if ! curl -s -f http://localhost:8889/ > /dev/null 2>&1; then
    echo "❌ VM is not accessible at localhost:8889"
    echo "Please start the VM first using: ./apps/cli/rave vm start <project-name>"
    exit 1
fi

echo "✅ VM is accessible"

# Test GitLab accessibility
echo "🦊 Testing GitLab..."
if curl -k -s -f "$GITLAB_URL" > /dev/null 2>&1; then
    echo "✅ GitLab is accessible at $GITLAB_URL"
else
    echo "⚠️  GitLab may still be starting up"
fi

# Test Mattermost accessibility  
echo "💬 Testing Mattermost..."
if curl -k -s -f "$MATTERMOST_URL" > /dev/null 2>&1; then
    echo "✅ Mattermost is accessible at $MATTERMOST_URL"
else
    echo "⚠️  Mattermost may still be starting up"
fi

# Test CI bridge service status via SSH
echo "🔗 Testing CI Bridge Service..."
if command -v sshpass > /dev/null 2>&1; then
    bridge_status=$(sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224 \
        "systemctl is-active gitlab-mattermost-ci-bridge.service" 2>/dev/null || echo "unknown")
    
    case $bridge_status in
        "active")
            echo "✅ CI Bridge service is active"
            ;;
        "inactive"|"failed")
            echo "⚠️  CI Bridge service status: $bridge_status"
            echo "Check logs with: sshpass -p 'debug123' ssh root@localhost -p 2224 'journalctl -u gitlab-mattermost-ci-bridge.service'"
            ;;
        *)
            echo "❓ CI Bridge service status: $bridge_status"
            ;;
    esac
else
    echo "⚠️  sshpass not available, cannot check CI bridge service status"
fi

# Test webhook integration file
echo "📊 Checking integration results..."
if command -v sshpass > /dev/null 2>&1; then
    if sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224 \
        "test -f /var/lib/rave/gitlab-mattermost-ci.json" 2>/dev/null; then
        echo "✅ Integration configuration file found"
        
        # Show integration summary
        integration_summary=$(sshpass -p 'debug123' ssh -o "StrictHostKeyChecking=no" root@localhost -p 2224 \
            "cat /var/lib/rave/gitlab-mattermost-ci.json" 2>/dev/null || echo "{}")
        
        if [ "$integration_summary" != "{}" ]; then
            echo "📋 Integration Summary:"
            echo "$integration_summary" | python3 -m json.tool 2>/dev/null || echo "$integration_summary"
        fi
    else
        echo "⚠️  Integration configuration file not found (may still be setting up)"
    fi
fi

echo ""
echo "🎯 Integration Test Complete!"
echo ""
echo "💡 To test the integration:"
echo "1. Visit GitLab: $GITLAB_URL"  
echo "2. Visit Mattermost: $MATTERMOST_URL"
echo "3. Sign into Mattermost using GitLab OAuth"
echo "4. Check the 'builds' channel for CI notifications"
echo "5. Create a project in GitLab and push commits to trigger CI"
