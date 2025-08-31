# RAVE - Reproducible AI Virtual Environment

🚀 **Complete company development environments in minutes**

RAVE provides isolated, production-ready development VMs with GitLab, NATS JetStream, PostgreSQL, Redis, and pre-configured OAuth integration. Perfect for managing multiple company development environments with a single CLI.

## ✨ Quick Start

### Install RAVE CLI
```bash
cd cli && pip install -r requirements.txt
export PATH="$PATH:$(pwd)"
```

### Create Your First Company Environment
```bash
# Create company development environment
rave vm create acme-corp --keypair ~/.ssh/id_ed25519

# Start the VM
rave vm start acme-corp

# SSH into the environment
rave vm ssh acme-corp

# View service logs
rave vm logs acme-corp nginx --follow
```

### Add Users via GitLab OAuth
```bash
# Add developer
rave user add john@acme-corp.com --oauth-id 12345 --access developer --company acme-corp

# List company users
rave user list --company acme-corp
```

## 🏗️ Repository Structure

```
rave/
├── cli/                    # RAVE CLI (main interface)
│   ├── rave               # Main CLI executable
│   ├── vm_manager.py      # VM lifecycle management
│   ├── user_manager.py    # GitLab OAuth user management
│   └── oauth_manager.py   # OAuth integration status
├── nixos/                 # NixOS VM configurations
│   ├── configs/           # VM build configurations
│   │   ├── development.nix
│   │   ├── production.nix
│   │   └── demo.nix
│   └── modules/           # NixOS service modules
│       ├── services/      # GitLab, NATS, etc.
│       ├── security/      # SSL, certificates
│       └── foundation/    # Base system config
├── services/              # Service-specific configurations
├── docs/                  # Documentation and reports
├── scripts/               # Utility and test scripts
├── build-scripts/         # VM build automation
├── demo-scripts/          # Demo and example scripts
├── legacy-configs/        # Historical configurations
└── archive/               # Deprecated files
```

## 🖥️ Architecture

Each company VM includes:
- **GitLab** - Source control with CI/CD pipelines
- **NATS JetStream** - Event streaming and messaging
- **PostgreSQL** - Primary database
- **Redis** - Caching (default + GitLab instances)
- **nginx** - Reverse proxy with SSL termination
- **Penpot** - Design collaboration (OAuth via GitLab)
- **Element** - Matrix chat (OAuth via GitLab)

### Isolation
- **Port ranges**: Each company gets unique ports (8100+, 8110+, etc.)
- **SSH keys**: Baked-in keypair access per company
- **Data separation**: Isolated file systems and databases

## 📖 CLI Reference

### VM Management
```bash
rave vm create <company> --keypair <path>    # Create company VM
rave vm start <company>                      # Start VM
rave vm stop <company>                       # Stop VM
rave vm status [--all]                       # Show VM status
rave vm reset <company>                      # Reset to clean state
rave vm ssh <company>                        # SSH into VM
rave vm logs <company> [service] [options]   # View logs
```

### User Management
```bash
rave user add <email> --oauth-id <id> --access <level>  # Add user
rave user remove <email>                                # Remove user
rave user list [--company <name>]                       # List users
rave user config <email> --access <level>               # Change access
rave user show <email>                                   # Show details
```

### OAuth Status
```bash
rave oauth status [service]                  # Show OAuth integration status
```

## 🔧 Development

### Building VMs
```bash
nix build .#development    # Development VM
nix build .#production     # Production VM  
nix build .#demo          # Demo VM
```

### Testing
```bash
# Run VM tests
nix build .#tests.x86_64-linux.rave-vm

# Health checks
scripts/health_checks/
```

## 🚀 Use Cases

- **Agency/Consultancy**: Separate environments per client
- **Multi-tenant SaaS**: Isolated dev environments per customer
- **Team Management**: Department-specific development stacks
- **Training/Education**: Standardized learning environments
- **Demo/Sales**: Quickly spin up client demonstrations

## 🔐 Security

- Self-signed SSL certificates for development
- GitLab OAuth integration pre-configured
- SSH key-based authentication
- Isolated network namespaces
- Encrypted secrets management (production)

## 📚 Documentation

- [CLI Documentation](cli/README.md)
- [VM Architecture](docs/SERVICES-OVERVIEW.md)
- [Security Reports](docs/)
- [Legacy Documentation](docs/DEPLOYMENT-STATUS.md)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push branch: `git push origin feature/amazing-feature`
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Experience the org dev sysadmin superpower: Multi-tenant development environments in 30 seconds.** 🚀