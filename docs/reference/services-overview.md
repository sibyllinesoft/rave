# RAVE Development Platform - Services Overview

Your RAVE development environment now includes a complete integrated stack of development tools.

## 🚀 Single Command Startup

The `cli/rave` tool is the single supported entry point for building and running the integrated stack.

```bash
# Build (or refresh) the QCOW image for the full environment
./cli/rave vm build-image --profile production

# Launch the VM locally with forwarded ports and secrets
./cli/rave vm launch-local --profile production --name local-stack
```

Once launched, use the remaining `rave vm …` commands to manage the VM by name (`local-stack` in this example).

## 📋 Integrated Services

### GitLab CE - Code Repository & CI/CD
- **URL**: http://localhost:8080
- **Default Admin**: root / ComplexPassword123!
- **SSH**: ssh://git@localhost:2222/username/repository.git
- **Features**: Git repositories, Issues, Merge Requests, CI/CD Pipelines

### Penpot - Design & Prototyping Tool
- **URL**: http://localhost:9001
- **First Time**: Create admin account on first visit
- **Features**: Real-time design collaboration, Prototyping, Design systems, Developer handoff

### Supporting Infrastructure
- **PostgreSQL 15**: Shared database for both GitLab and Penpot
- **Redis 7**: Caching and session management
- **Nginx**: Reverse proxy and load balancing

## 🛠️ Management Commands

```bash
# Build/update image (safe to run multiple times)
./cli/rave vm build-image --profile production

# Launch a disposable local VM
./cli/rave vm launch-local --profile production --name local-stack

# Manage an existing VM definition
./cli/rave vm start local-stack
./cli/rave vm stop local-stack
./cli/rave vm status local-stack
./cli/rave vm logs local-stack --service nginx --follow
./cli/rave vm ssh local-stack
```

To inspect a specific service such as Penpot:

```bash
./cli/rave vm logs local-stack --service penpot-backend --follow
```

## 🔗 Workflow Integration

### Design-to-Code Workflow
1. **Design** in Penpot (http://localhost:9001)
2. **Export** assets and specs from Penpot
3. **Commit** design assets to GitLab repositories
4. **Track** design tasks using GitLab Issues
5. **Review** design changes in GitLab Merge Requests

### Complete Development Cycle
1. **Plan** features in GitLab Issues
2. **Design** UI/UX in Penpot
3. **Code** in your IDE with GitLab integration
4. **Test** using GitLab CI/CD pipelines
5. **Deploy** via GitLab's deployment features
6. **Collaborate** using both platforms' real-time features

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   GitLab CE     │    │     Penpot      │
│   :8080         │    │     :9001       │
└─────────┬───────┘    └─────────┬───────┘
          │                      │
          └──────┬─────┬─────────┘
                 │     │
         ┌───────▼─────▼───────┐
         │      Nginx          │
         │  Reverse Proxy      │
         └─────────┬───────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
┌───▼───┐    ┌─────▼──┐    ┌─────▼──┐
│PostgreSQL   │ Redis  │    │ Docker │
│Database │    │ Cache  │    │Network │
└───────┘    └────────┘    └────────┘
```

## 🎯 Key Benefits

- **Single Stack**: One Docker Compose configuration
- **Shared Resources**: Efficient resource usage with shared PostgreSQL/Redis
- **Integrated Workflow**: Design and code in the same development environment
- **Version Control**: All design assets can be version controlled alongside code
- **Local Development**: Everything runs locally for fast iteration
- **Production Ready**: Same stack can be deployed to production

## 📚 Documentation

- **GitLab**: See existing GitLab documentation in the project
- **Penpot**: See `gitlab-complete/PENPOT-README.md` for detailed Penpot guide
- **Architecture**: See `docs/explanation/architecture.md` for system architecture details

## 🔧 Customization

Both services can be customized via their respective configuration files:
- **GitLab**: `gitlab-complete/docker-compose.yml` (GITLAB_OMNIBUS_CONFIG)
- **Penpot**: Environment variables in the same `docker-compose.yml`
- **Nginx**: Configuration files in `gitlab-complete/nginx/`

Your development environment is now a complete platform for both design and development work!
