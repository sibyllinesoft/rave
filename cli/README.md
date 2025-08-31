# RAVE CLI

Comprehensive CLI for managing RAVE (Reproducible AI Virtual Environment) company development environments.

## Features

- **VM Management**: Create, start, stop, reset company development VMs
- **User Management**: Add/remove users via GitLab OAuth integration  
- **SSH & Logging**: Direct access to VMs and service logs
- **Pre-configured Services**: GitLab, NATS, PostgreSQL, Redis, nginx with SSL
- **OAuth Integration**: Penpot and Element pre-configured with GitLab OAuth

## Installation

```bash
cd /home/nathan/Projects/rave/cli
pip install -r requirements.txt
```

Add to PATH:
```bash
export PATH="$PATH:/home/nathan/Projects/rave/cli"
```

## Quick Start

```bash
# Create a company development environment
rave vm create acme-corp --keypair ~/.ssh/id_ed25519

# Start the VM
rave vm start acme-corp

# Check status
rave vm status acme-corp

# SSH into VM
rave vm ssh acme-corp

# View logs
rave vm logs acme-corp nginx --follow

# Add users
rave user add john@acme-corp.com --oauth-id 12345 --access developer --company acme-corp

# List users
rave user list --company acme-corp
```

## Commands

### VM Management
- `rave vm create <company> --keypair <path>` - Create company VM
- `rave vm start <company>` - Start VM
- `rave vm stop <company>` - Stop VM  
- `rave vm status [company] [--all]` - Show VM status
- `rave vm reset <company>` - Reset VM to clean state
- `rave vm ssh <company>` - SSH into VM
- `rave vm logs <company> [service] [options]` - View service logs

### User Management
- `rave user add <email> --oauth-id <id> --access <level>` - Add user
- `rave user remove <email>` - Remove user
- `rave user list [--company <name>]` - List users
- `rave user config <email> --access <level>` - Change user access
- `rave user show <email>` - Show user details

### OAuth Status
- `rave oauth status [service]` - Show OAuth configuration status

## Architecture

Each company VM includes:
- **GitLab** (port offset + 80/443) with OAuth provider
- **NATS JetStream** (internal) for event streaming
- **PostgreSQL** (internal) for data storage
- **Redis** (internal) for caching
- **nginx** (reverse proxy) with SSL certificates
- **Penpot** (pre-configured with GitLab OAuth)
- **Element** (pre-configured with GitLab OAuth)

VMs are isolated by port ranges starting from 8100, incrementing by 10 per company.

## Configuration

CLI configuration stored in `~/.config/rave/`:
- `config.json` - Global settings
- `vms/` - VM configurations
- `users.json` - User database

## Development

The CLI integrates with the existing RAVE NixOS configuration system, building VMs using `nix build .#development`.