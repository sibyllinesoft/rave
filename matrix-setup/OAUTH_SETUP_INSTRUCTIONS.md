# OAuth Integration Setup Instructions

## GitLab ↔ Matrix/Element Single Sign-On

This guide provides step-by-step instructions to set up OAuth integration between GitLab and Matrix/Element for single sign-on authentication.

## Prerequisites

- Docker and Docker Compose installed
- Basic understanding of OAuth2 flow
- Network access to GitLab instance (existing or new)
- Administrative access to GitLab instance

## Architecture Overview

```
┌─────────────┐    OAuth2 Flow    ┌──────────────┐
│   Element   │ ←────────────────→ │   Matrix     │
│ Web Client  │                  │   Synapse    │
└─────────────┘                  └──────────────┘
                                         │
                                         │ OIDC
                                         ▼
                                  ┌──────────────┐
                                  │   GitLab     │
                                  │ OAuth2 IdP   │
                                  └──────────────┘
```

## Step 1: Prepare Your Environment

### 1.1 Clone/Navigate to Matrix Setup Directory

```bash
cd /path/to/matrix-setup
```

### 1.2 Backup Existing Configuration

```bash
# Create backup directory
mkdir -p backups/$(date +%Y%m%d_%H%M%S)

# Backup current configurations (if they exist)
cp docker-compose.yml backups/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
cp element-config.json backups/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
cp data/homeserver.yaml backups/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true
```

### 1.3 Set Up Environment Variables

```bash
# Copy environment template
cp .env.oauth.example .env

# Edit the environment file
nano .env
```

**Configure these required variables:**
```bash
# GitLab Configuration
GITLAB_URL=http://localhost:8080  # Or your external GitLab URL
GITLAB_OAUTH_CLIENT_ID=           # Will be set after GitLab OAuth app creation
GITLAB_OAUTH_CLIENT_SECRET=       # Will be set after GitLab OAuth app creation

# Optional: Email configuration
SMTP_HOST=your-smtp-server.com
SMTP_PORT=587
SMTP_USER=your-email@domain.com
SMTP_PASS=your-email-password
SMTP_TLS=true
```

## Step 2: Start Initial Services

### 2.1 Start GitLab (if using bundled GitLab)

If you don't have an existing GitLab instance:

```bash
# Start GitLab service only
docker-compose -f docker-compose-oauth.yml up -d gitlab redis-gitlab

# Wait for GitLab to initialize (this takes 5-10 minutes)
echo "Waiting for GitLab to start..."
while ! curl -f http://localhost:8080/-/health 2>/dev/null; do
    echo -n "."
    sleep 10
done
echo -e "\nGitLab is ready!"
```

### 2.2 Access GitLab Admin Interface

1. **Open GitLab**: http://localhost:8080
2. **Login as root**: 
   - Username: `root`
   - Password: `gitlab_admin_password` (from .env file)

### 2.3 Create First User (Optional)

For testing, create a regular user account:
1. Go to **Admin Area** → **Users** → **New User**
2. Fill in user details
3. Set password and activate user

## Step 3: Configure GitLab OAuth2 Application

### 3.1 Create OAuth Application

1. **Navigate to**: GitLab Admin Area → **Applications**
2. **Click**: "New application"
3. **Configure application**:
   - **Name**: `Matrix/Element SSO`
   - **Redirect URI**: `http://localhost:8008/_synapse/client/oidc/callback`
   - **Scopes**: Check all of:
     - `openid`
     - `profile` 
     - `email`
     - `read_user`
   - **Confidential**: ✅ Yes (checked)

4. **Click**: "Save application"

### 3.2 Save OAuth Credentials

After creating the application, you'll see:
- **Application ID** (Client ID)
- **Secret** (Client Secret)

**Update your .env file:**
```bash
# Edit .env file
nano .env

# Add the credentials
GITLAB_OAUTH_CLIENT_ID=your_application_id_here
GITLAB_OAUTH_CLIENT_SECRET=your_secret_here
```

## Step 4: Configure Matrix/Element for OAuth

### 4.1 Run Automated Setup

```bash
# Run the setup script
./setup-oauth-integration.sh
```

The script will:
- Validate environment configuration
- Update configuration files
- Start all services
- Test OAuth endpoints

### 4.2 Manual Configuration (Alternative)

If you prefer manual configuration:

```bash
# Copy OAuth configurations
cp docker-compose-oauth.yml docker-compose.yml
cp element-config-oauth.json element-config.json
cp data/homeserver-oauth.yaml data/homeserver.yaml

# Start services
docker-compose --env-file .env up -d
```

## Step 5: Test OAuth Integration

### 5.1 Verify All Services Are Running

```bash
# Check service status
docker-compose ps

# All services should show "Up (healthy)"
```

### 5.2 Test OAuth Endpoints

```bash
# Run integration tests
./test-oauth-integration.sh
```

Expected output:
```
✅ GitLab is accessible
✅ OAuth discovery works
✅ Synapse is healthy
✅ Element is accessible
✅ OIDC callback endpoint ready
```

### 5.3 Test User Login Flow

1. **Open Element**: http://localhost:8009
2. **Click**: "Continue with GitLab" button
3. **Redirected to GitLab**: Login with GitLab credentials
4. **Grant permissions**: Authorize Matrix application
5. **Redirected back**: Should be logged into Element

## Step 6: Verify Integration

### 6.1 Check User Creation

```bash
# View Synapse logs for user creation
docker-compose logs synapse | grep -i "creating user"

# Check database for new users
docker-compose exec postgres-matrix psql -U synapse -d synapse -c \
  "SELECT name, creation_ts FROM users ORDER BY creation_ts DESC LIMIT 5;"
```

### 6.2 Test User Profile Sync

1. **Update GitLab profile**: Change name or email in GitLab
2. **Logout and login**: In Element
3. **Verify sync**: Profile changes should appear in Element

## Step 7: Configure Access Control (Optional)

### 7.1 GitLab Group-Based Access

To restrict Matrix access to specific GitLab groups:

1. **Create GitLab group**: e.g., "matrix-users"
2. **Add users to group**
3. **Update homeserver.yaml**:
   ```yaml
   oidc_providers:
     - idp_id: gitlab
       # ... existing config
       attribute_requirements:
         - attribute: "groups"
           value: "matrix-users"
   ```

### 7.2 Auto-Join Rooms

Configure users to automatically join specific rooms:

```yaml
# In homeserver.yaml
auto_join_rooms:
  - "#general:localhost"
  - "#announcements:localhost"
```

## Step 8: Production Hardening

### 8.1 Security Configuration

1. **Disable local authentication**:
   ```yaml
   # In homeserver.yaml
   password_config:
     enabled: false
   enable_registration: false
   ```

2. **Configure HTTPS** (production):
   - Use reverse proxy (nginx/traefik)
   - Update OAuth redirect URI to HTTPS
   - Update GitLab and Element configs for HTTPS

### 8.2 Monitoring Setup

```bash
# Set up log rotation
cat > /etc/logrotate.d/matrix-oauth << 'EOF'
/path/to/matrix-setup/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    copytruncate
}
EOF

# Create monitoring script
./create-monitoring-script.sh
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| OAuth button doesn't appear | Check Element configuration and restart |
| Invalid redirect URI | Verify exact callback URL in GitLab app |
| User creation fails | Check user mapping configuration |
| SSL/TLS errors | Use HTTP for development, HTTPS for production |

### Debug Commands

```bash
# Check service logs
docker-compose logs synapse
docker-compose logs gitlab
docker-compose logs element

# Test OAuth endpoints
curl -f "${GITLAB_URL}/.well-known/openid_configuration"
curl -f "http://localhost:8008/health"

# Check configuration
./test-oauth-integration.sh
```

### Get Help

1. **Review logs**: Check service logs for error messages
2. **Run diagnostics**: `./test-oauth-integration.sh`
3. **Check troubleshooting guide**: `OAUTH_TROUBLESHOOTING_GUIDE.md`
4. **Rollback if needed**: `./rollback-oauth.sh`

## Maintenance

### Regular Tasks

1. **Update OAuth tokens**: Rotate client secrets periodically
2. **Monitor logs**: Check for authentication failures
3. **User management**: Add/remove users in GitLab
4. **Backup configuration**: Regular backups of OAuth settings

### Updates

When updating services:
1. Backup current configuration
2. Update Docker images
3. Test OAuth flow after updates
4. Monitor logs for issues

## Success Criteria Checklist

- ✅ GitLab OAuth application created and configured
- ✅ Matrix Synapse configured for OIDC authentication
- ✅ Element web client shows OAuth login option
- ✅ Users can login with GitLab credentials
- ✅ User profiles sync from GitLab to Matrix
- ✅ Local password authentication disabled
- ✅ Access control through GitLab groups working
- ✅ Monitoring and logging configured
- ✅ Backup and rollback procedures tested

## Next Steps

After successful OAuth integration:

1. **User Training**: Educate users on new login process
2. **Group Management**: Set up GitLab groups for access control
3. **Room Configuration**: Create and configure Matrix rooms
4. **Integration**: Consider additional GitLab/Matrix integrations
5. **Documentation**: Document your specific configuration

---

## Quick Reference

### Key URLs
- **GitLab**: http://localhost:8080
- **Element**: http://localhost:8009
- **Matrix API**: http://localhost:8008

### Key Files
- **Environment**: `.env`
- **Matrix Config**: `data/homeserver.yaml`
- **Element Config**: `element-config.json`
- **Docker Compose**: `docker-compose.yml`

### Key Commands
```bash
# Start services
docker-compose up -d

# Test integration
./test-oauth-integration.sh

# View logs
docker-compose logs synapse

# Rollback
./rollback-oauth.sh
```