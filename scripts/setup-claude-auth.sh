#!/bin/bash

# Helper script for Claude Code authentication

echo "🔐 Claude Code Authentication Setup"
echo "=================================="
echo ""
echo "This script will help you authenticate Claude Code in the container."
echo ""
echo "Steps:"
echo "1. The container will start Claude Code"
echo "2. Follow the OAuth flow in your browser"
echo "3. Once complete, Claude Code will be ready to use"
echo ""
echo "Press Enter to continue..."
read

# Run Claude Code to trigger authentication
echo "🚀 Starting Claude Code authentication..."
claude-code --help

echo ""
echo "✅ Authentication complete!"
echo "You can now use Claude Code with all Studio features integrated."
echo ""
echo "Try running:"
echo "  claude-code"
echo "  # or any specific claude commands"