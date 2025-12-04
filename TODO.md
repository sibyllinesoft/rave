Based on the file dump provided, you have a "VM building tool" (Project **Rave**) that relies heavily on Shell scripts and NixOS configurations. Currently, the logic is scattered across the root directory and various subfolders, with hardcoded values (ports, passwords) duplicated across multiple files.

Here is a comprehensive plan to refactor this project to be modular, maintainable, and robust.

### 1. Reorganize Directory Structure

Move loose scripts from the root into a logical hierarchy. This separates "source" code from "configuration" and "documentation."

**Proposed Structure:**
```text
rave/
├── bin/                 # Entry point scripts (CLI wrappers)
│   └── rave             # Main entry point
├── config/              # Configuration files
│   ├── rave.env         # Shared environment variables (Ports, Passwords)
│   └── qemu-args.conf   # QEMU arguments
├── lib/                 # Shared shell functions
│   ├── utils.sh         # Logging, error handling
│   ├── network.sh       # Port checks, curl wrappers
│   └── ssh.sh           # SSH connection helpers
├── scripts/             # Task-specific scripts
│   ├── boot/            # Boot monitoring and startup
│   ├── setup/           # Installation scripts (Nix, Certs)
│   ├── health/          # Health checks
│   └── demo/            # Demo scenarios
└── infra/               # Existing NixOS infrastructure
```

---

### 2. Centralize Configuration (`config/rave.env`)

Stop hardcoding `8443`, `2224`, and `debug123` in every file. Create a single source of truth.

```bash
# config/rave.env

# VM Connectivity
export VM_HOST="localhost"
export VM_SSH_PORT="2224"
export VM_HTTP_PORT="8080"
export VM_HTTPS_PORT="8443"

# Credentials
export VM_USER="root"
export VM_PASS="debug123" # Consider using SSH keys instead of sshpass for prod

# Timeouts
export MAX_RETRIES=20
export SLEEP_INTERVAL=15

# URLs
export BASE_URL="https://${VM_HOST}:${VM_HTTPS_PORT}"
```

---

### 3. Create a Shared Library (`lib/`)

Extract common logic used in `check-gitlab-ready.sh`, `monitor-boot.sh`, and `fix-certificates.sh`. ✅ Implemented as `lib/utils.sh`, `lib/ssh.sh` and wired into the Bash CLI.

---

### 4. Refactor Specific Scripts

`monitor-boot`, `gitlab-ready`, and `fix-certificates` are now CLI subcommands (`rave vm-monitor`, `rave gitlab-ready`, `rave cert fix`). Legacy standalone scripts removed to keep functionality centralized.

---

### 5. Consolidate Health Checks

Unified runner is now `rave health`, which also invokes any `scripts/health_checks/*.sh` when present. Legacy wrapper removed.

---

### 6. QEMU Launch Cleanup

The script `final-rave-demo.sh` contained a very long QEMU command. This should be moved to a function or a variable to make it readable.

**`scripts/vm/start.sh`**
```bash
#!/bin/bash
source "$(dirname "$0")/../../config/rave.env"

# Kill existing
pkill -9 qemu-system-x86_64 2>/dev/null || true

# Port Forwarding Configuration
NET_OPTS="hostfwd=tcp:0.0.0.0:${VM_HTTP_PORT}-:8080"
NET_OPTS+=",hostfwd=tcp:0.0.0.0:${VM_HTTPS_PORT}-:8081"
NET_OPTS+=",hostfwd=tcp:0.0.0.0:${VM_SSH_PORT}-:22"

echo "🚀 Starting VM..."
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -smp 2 \
  -drive file=gitlab-https-debug.qcow2,format=qcow2 \
  -netdev user,id=net0,$NET_OPTS \
  -device virtio-net,netdev=net0 \
  -display none \
  -daemonize

echo "✅ VM process spawned. Run ./scripts/boot/monitor.sh to watch boot."
```

### 7. Remove the Bundle

The file you provided (`rave.html`) includes an 800KB JavaScript bundle at the bottom. This is likely a visualization tool (Scribe) used to *generate* the file you uploaded.
*   **Action:** Delete `infra/nixos/static/assets/index-CT1uqrYS.js` from your source control if it's a build artifact. Only keep the source code for your UI in `src/`.

### Summary of Benefits
1.  **Single Config:** Change the port in `rave.env` and it updates in health checks, boot monitors, and VM startup scripts instantly.
2.  **Dry Code:** SSH connection logic is defined once.
3.  **Safety:** `set -e` prevents scripts from cascading errors.
4.  **Readability:** New developers know exactly where to look (`config/` for settings, `scripts/` for logic).
