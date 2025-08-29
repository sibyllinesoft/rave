# RAVE Development Platform - Services Overview

Your RAVE development environment now includes a complete integrated stack of development tools.

## 🚀 Single Command Startup

Start everything with one command:
```bash
./run.sh start
```

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
# Start all services
./run.sh start

# Stop all services  
./run.sh stop

# Check status
./run.sh status

# View logs
./run.sh logs

# Health check
./run.sh validate

# Manage Penpot specifically
./run.sh penpot status
./run.sh penpot logs
./run.sh penpot restart
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
- **Architecture**: See `docs/ARCHITECTURE.md` for system architecture details

## 🔧 Customization

Both services can be customized via their respective configuration files:
- **GitLab**: `gitlab-complete/docker-compose.yml` (GITLAB_OMNIBUS_CONFIG)
- **Penpot**: Environment variables in the same `docker-compose.yml`
- **Nginx**: Configuration files in `gitlab-complete/nginx/`

Your development environment is now a complete platform for both design and development work!