# RAVE - Reproducible AI Virtual Environment

RAVE is a project to build and manage a complete, production-ready development environment for AI agents. The primary service is a self-hosted GitLab instance, fully configured for CI/CD and secure operation.

## 🚀 Quick Start

This project uses Docker Compose for a reliable, multi-service GitLab deployment.

**Prerequisites:**
- Docker
- Docker Compose (v2) or docker-compose (v1)

### 1. Start All Services

Use the master runner script to start the GitLab environment. The first startup will take 5-10 minutes to initialize the database and services.

```bash
./run.sh start
```

### 2. Access GitLab

- **Web Interface:** [http://localhost:8080](http://localhost:8080)
- **Username:** `root`
- **Password:** `ComplexPassword123!`

## 🛠️ Service Management

The `run.sh` script is the single entry point for managing the RAVE environment.

| Command | Description |
|---|---|
| `./run.sh start` | Start the GitLab stack. |
| `./run.sh stop` | Stop all services gracefully. |
| `./run.sh status` | View the status of all containers. |
| `./run.sh logs` | Tail the logs from all services. |
| `./run.sh restart` | Stop and then start the entire stack. |
| `./run.sh validate`| Run all health and validation checks. |

## 🏗️ Architecture

The GitLab service is orchestrated using Docker Compose and consists of four main containers:

1.  **GitLab CE:** The main GitLab application.
2.  **PostgreSQL:** The database for GitLab.
3.  **Redis:** In-memory cache and job queue.
4.  **Nginx:** A reverse proxy that handles incoming traffic and correctly manages redirects.

All configuration, scripts, and documentation for this setup can be found in the `gitlab-complete/` directory.

## ☁️ NixOS Infrastructure

This repository also contains NixOS configurations for building reproducible virtual machine images. For more details on the VM build system, see the `flake.nix` file and the configurations within the `nixos/` directory.

**Build a development VM:**
```bash
nix build .#development
```

## 📜 License

This project is under the Business Source License 1.1. Please see the `LICENSE` file for details.