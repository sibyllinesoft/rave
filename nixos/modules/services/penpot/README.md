# Penpot Service Module

This module provides a complete Penpot design tool setup with PostgreSQL and Redis backends, integrated with GitLab OAuth for authentication.

## Features

- **Complete Penpot Stack**: Frontend, Backend, and Export services
- **GitLab OAuth Integration**: Single sign-on with GitLab
- **Self-signed SSL**: Development-ready HTTPS configuration
- **Nginx Reverse Proxy**: Proper routing at `/penpot/` path
- **Database & Cache**: PostgreSQL and Redis backends
- **Docker-based**: Uses official Penpot Docker images
- **Resource Management**: Memory and CPU limits configured
- **CORS Support**: Proper cross-origin headers for web app
- **Health Monitoring**: Health check endpoints

## Configuration

### Basic Setup

```nix
services.rave.penpot = {
  enable = true;
  host = "rave.local";
  useSecrets = false;  # For development
  
  oidc = {
    enable = true;
    gitlabUrl = "https://rave.local/gitlab";
    clientId = "penpot";
  };
};
```

### GitLab OAuth Setup

To enable GitLab authentication for Penpot:

1. **Access GitLab Admin Area**:
   - Go to `https://rave.local/gitlab/admin/applications`
   - Login with root credentials

2. **Create OAuth Application**:
   - **Name**: `Penpot`
   - **Redirect URI**: `https://rave.local/penpot/api/auth/oauth/gitlab/callback`
   - **Scopes**: Check `openid`, `profile`, `email`
   - **Confidential**: Yes

3. **Configure Secrets** (if using secrets):
   ```nix
   sops.secrets."oidc/penpot-client-secret" = {
     sopsFile = ../secrets.yaml;
     owner = "root";
     group = "root";
     mode = "0400";
   };
   ```

4. **Development Mode** (plaintext secrets):
   The module defaults to `"development-penpot-oidc-secret"` when `useSecrets = false`.

## Service Architecture

```
nginx (port 443) 
├── /penpot/ → Frontend (port 3449)
├── /penpot/api/ → Backend (port 6060)
├── /penpot/export/ → Exporter (port 6061)
├── /penpot/assets/ → Backend (port 6060)
└── /health/penpot → Health check
```

## Database Configuration

The module automatically:
- Creates PostgreSQL database named `penpot`
- Creates PostgreSQL user `penpot` with ownership
- Sets up Redis instance on port 6380
- Configures connection pooling and optimization

## Docker Integration

Penpot runs as Docker containers with:
- **Network**: `penpot-network` (bridge mode)
- **Volumes**: `penpot-assets` for persistent file storage
- **Resource Limits**: 2GB memory, 1 CPU core
- **Health Checks**: Built-in container health monitoring

## Security Features

### CORS Configuration
- Restricts origins to `https://rave.local`
- Handles preflight OPTIONS requests
- Supports credentials for authenticated requests

### Content Security
- Large file upload support (500MB for exports)
- Request buffering disabled for streaming
- Timeouts configured for long-running operations

### Rate Limiting
- API calls: 30 requests/second
- File uploads: 5 requests/second
- Burst handling with no delay

## Monitoring & Health

### Health Check Endpoint
- **URL**: `https://rave.local/health/penpot`
- **Method**: Proxies to Penpot profile API
- **Responses**: 
  - `200 OK`: "Penpot: OK"
  - `503 Service Unavailable`: "Penpot: Unavailable"

### Service Management
```bash
# Check service status
systemctl status penpot

# View logs
journalctl -u penpot -f

# Restart service
systemctl restart penpot

# Check Docker containers
docker ps | grep penpot
```

## Troubleshooting

### Container Issues
```bash
# Check container logs
docker logs penpot-frontend
docker logs penpot-backend
docker logs penpot-exporter

# Recreate containers
systemctl restart penpot
```

### Database Connectivity
```bash
# Test PostgreSQL connection
sudo -u postgres psql -d penpot -c "SELECT 1;"

# Test Redis connection
redis-cli -p 6380 ping
```

### OAuth Issues
1. Verify GitLab application configuration
2. Check redirect URI matches exactly
3. Ensure client secret is correctly configured
4. Review GitLab logs for OAuth errors

### Network Connectivity
```bash
# Test internal services
curl http://localhost:3449  # Frontend
curl http://localhost:6060/api/rpc/command/get-profile  # Backend
curl http://localhost:6061/export/  # Exporter

# Test through nginx
curl -k https://rave.local/penpot/
curl -k https://rave.local/health/penpot
```

## File Structure

```
nixos/modules/services/penpot/
├── default.nix    # Main Penpot service configuration
├── nginx.nix      # Nginx reverse proxy setup
└── README.md      # This documentation
```

## Integration

This module integrates with:
- **GitLab Module**: OAuth authentication
- **Certificate Module**: SSL/TLS certificates
- **Foundation Modules**: Base system configuration

## Resource Usage

- **Memory**: ~2GB (1GB backend, 512MB frontend, 256MB Redis, 256MB exporter)
- **Disk**: ~1GB for Docker images + user data
- **CPU**: 1-2 cores under normal load
- **Network**: Ports 3449, 6060, 6061, 6380

## Development Notes

- Telemetry is disabled for privacy
- SMTP is configured but non-functional (for email verification)
- File storage uses Docker volumes for persistence
- All containers use `--rm` flag for clean shutdowns