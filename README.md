# 🎉 Rave - AI Agent Management Container

**Rave** is a containerized environment for managing AI agents with integrated Kanban workflow management through Vibe Kanban. It provides a unified platform combining Claude Code, Graphite CLI, and visual project management.

## Features

- 🤖 **Claude Code CLI** - Advanced AI-powered development assistance
- 🎨 **Claude Code Studio** - Visual development environment (optional)
- 📊 **Graphite CLI** - Git workflow optimization
- 📋 **Vibe Kanban** - Visual project management and task tracking
- 🔌 **MCP Integration** - Seamless connection between Claude and Kanban boards
- 🐳 **Docker Ready** - Easy deployment and management

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Claude Code subscription (for OAuth authentication)

### Setup

1. **Clone the repository:**
   ```bash
   git clone <your-repo-url> rave
   cd rave
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env if you want to modify default settings
   ```

3. **Start the container:**
   ```bash
   docker-compose up -d
   ```

4. **Authenticate Claude Code (Required):**
   ```bash
   # Connect to the container for OAuth authentication
   docker exec -it rave-agent-manager claude-code
   # Follow the OAuth flow in your browser
   # Once authenticated, Claude Code will work in the container
   ```

5. **Access Vibe Kanban:**
   Open http://localhost:7890 in your browser

### Services

- **Vibe Kanban**: http://localhost:7890
- **Claude Code CLI**: Available inside container with Studio features
- **Claude Code Studio**: Integrated into CLI (no separate web interface)

## Usage

### Using Claude Code with Kanban Integration

The container includes a custom MCP server that connects Claude Code to your Vibe Kanban boards:

```bash
# Enter the container
docker exec -it rave-agent-manager bash

# Use Claude Code with Kanban integration
claude-code
```

Available Kanban commands through Claude:
- View all boards
- Get specific board details
- Create new cards
- Update existing cards
- Move cards between lists
- Delete cards

### Available Tools

Inside the container, you have access to:

- `claude-code` - AI development assistant
- `gt` - Graphite CLI for Git workflows
- `node` / `npm` / `bun` - JavaScript development tools
- Access to Vibe Kanban at http://localhost:3000

### Working with Projects

Mount your project directory for development:

```bash
# In docker-compose.yml, uncomment or modify:
volumes:
  - ./your-project:/workspace/project
```

### MCP Configuration

The Vibe Kanban MCP server provides these tools:

- `get_boards` - List all Kanban boards
- `get_board` - Get specific board details
- `create_card` - Create new task cards
- `update_card` - Modify existing cards
- `delete_card` - Remove cards

## Configuration

### Environment Variables

- `START_STUDIO` - Set to `true` to show Claude Code Studio features info
- `VIBE_KANBAN_PORT` - Port for Vibe Kanban (default: 7890)
- `VIBE_KANBAN_API_KEY` - Optional API key for Vibe Kanban

**Note**: Claude Code uses OAuth authentication through the browser, not API keys.

### Custom Configuration

Modify configuration files in the `config/` directory:

- `claude-config.json` - Claude Code settings
- `mcp-config.json` - MCP server configuration

## Development

### Building the Image

```bash
docker build -t rave:latest .
```

### Development Mode

For development with live changes:

```bash
docker-compose -f docker-compose.dev.yml up
```

### Logs

View container logs:

```bash
docker-compose logs -f rave
```

## Troubleshooting

### Common Issues

1. **Container won't start:**
   - Check if ports 7890/3001 are available
   - Check Docker daemon is running
   - Verify .env file is properly configured

2. **Claude Code not working:**
   - Ensure you've completed OAuth authentication
   - Run: `docker exec -it rave-agent-manager claude-code`
   - Check network connectivity for OAuth flow
   - Review container logs

3. **Vibe Kanban not accessible:**
   - Wait for full container startup (check logs)
   - Verify port mapping in docker-compose.yml
   - Check firewall settings

### Health Check

The container includes a health check for Vibe Kanban:

```bash
docker-compose ps
```

Look for "healthy" status.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test in a clean environment
5. Submit a pull request

## License

This project is open source. See the LICENSE file for details.

## Architecture

```
┌─────────────────────────────────────────┐
│               Rave Container            │
├─────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────────┐  │
│  │ Claude Code │  │  Vibe Kanban     │  │
│  │     CLI     │  │   (Port 3000)    │  │
│  └─────────────┘  └──────────────────┘  │
│  ┌─────────────┐  ┌──────────────────┐  │
│  │ Graphite    │  │ Claude Code      │  │
│  │    CLI      │  │  Studio (3001)   │  │
│  └─────────────┘  └──────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │        MCP Integration              │  │
│  │   (Claude ↔ Vibe Kanban)          │  │
│  └─────────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

The container creates a unified environment where AI agents can manage and interact with visual project boards, enabling seamless workflow between development tasks and project tracking.