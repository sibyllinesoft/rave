#!/bin/bash

# Start script for Rave container
set -e

echo "🎉 Starting Rave - AI Agent Management Container"

# Set up Claude Code configuration
echo "🔧 Setting up Claude Code..."

# Copy additional config if provided
if [ -f /opt/config/claude-config.json ]; then
    cp /opt/config/claude-config.json /root/.claude/config.json
fi

# Check if Claude Code needs authentication
echo "🔐 Checking Claude Code authentication..."
if ! claude-code --version >/dev/null 2>&1; then
    echo "⚠️  Claude Code needs authentication. Please run the following commands:"
    echo "   docker exec -it rave-agent-manager claude-code"
    echo "   This will start the OAuth flow in the container."
    echo ""
    echo "🔄 For now, continuing with other services..."
else
    echo "✅ Claude Code is authenticated and ready"
fi

# Set up Graphite
echo "📊 Initializing Graphite..."
gt --version || echo "Graphite installed successfully"

# Start Vibe Kanban
echo "📋 Starting Vibe Kanban..."
cd /opt/vibe-kanban

# Set up environment variables for Vibe Kanban
export NODE_ENV=production
export PORT=3000

# Start Vibe Kanban in the background
npm start &

# Wait for Vibe Kanban to be ready
echo "⏳ Waiting for Vibe Kanban to start..."
timeout 60 bash -c 'until curl -s http://localhost:3000 > /dev/null; do sleep 2; done' || {
    echo "❌ Vibe Kanban failed to start"
    exit 1
}

echo "✅ Vibe Kanban is running at http://localhost:7890"

# Set up MCP server for Vibe Kanban integration
echo "🔌 Setting up Vibe Kanban MCP integration..."
if [ -f /opt/config/mcp-config.json ]; then
    cp /opt/config/mcp-config.json /root/.claude/mcp.json
fi

# Note about Claude Code Studio
if [ "$START_STUDIO" = "true" ]; then
    echo "🎨 Claude Code Studio is available in ~/.claude"
    echo "   Studio features are integrated into Claude Code CLI"
    echo "   Use 'claude-code' command for full studio experience"
fi

echo "🚀 Rave container is ready!"
echo "📋 Vibe Kanban: http://localhost:7890"
echo "🤖 Claude Code CLI is available"
echo "📊 Graphite CLI is available"

# Keep the container running
tail -f /dev/null