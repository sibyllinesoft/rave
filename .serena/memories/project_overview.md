# RAVE - Reproducible AI Virtual Environment Project Overview

## Purpose
Building deterministic, reproducible AI agent sandbox VMs using NixOS Flakes with integrated Claude Code ecosystem tools. This provides a standardized development environment for AI agents with consistent configuration and tooling.

## Tech Stack
- **Build System**: NixOS Flakes for deterministic builds
- **VM Generation**: nixos-generators (supports qcow2, VirtualBox, VMware, ISO, raw)
- **Base OS**: NixOS 24.11
- **Services**: systemd service orchestration
- **Web Proxy**: Nginx for service routing
- **Runtime**: Node.js 20, Python 3, Rust toolchain
- **Desktop**: XFCE4 with auto-login
- **Browser**: Chromium (default)

## Core Services
- **Vibe Kanban**: Project management (port 3000)
- **Claude Code Router**: AI router (port 3456, mapped to 3001)
- **Nginx Proxy**: Unified access (port 3002)
- **SSH**: Remote access (default port 22)

## Current Security Issues (CRITICAL)
- Password authentication enabled on SSH
- Root login potentially accessible  
- No firewall enabled (disabled for development)
- Default passwords used ("agent" user password)
- No fail2ban or intrusion prevention
- No SSH key management
- Sudo without password enabled
- No security monitoring

## Key Configuration Files
- `simple-ai-config.nix`: Main production config (default for qemu builds)
- `ai-sandbox-config.nix`: Development config (for other formats)
- `flake.nix`: Build system definition
- `vibe-kanban-simple.nix`: Custom package derivation