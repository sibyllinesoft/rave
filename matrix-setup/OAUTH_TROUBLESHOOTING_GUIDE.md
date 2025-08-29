# OAuth Integration Troubleshooting Guide

## Quick Diagnosis Commands

```bash
# Test OAuth integration status
./test-oauth-integration.sh

# Check service health
docker-compose ps

# View Synapse logs
docker-compose logs synapse

# View GitLab logs
docker-compose logs gitlab

# Check environment configuration
source .env && env | grep GITLAB
```

## Common Issues and Solutions

### 1. GitLab OAuth Application Not Found

**Symptoms:**
- "OAuth application not found" error in Synapse logs
- Login redirects fail with 400/404 errors

**Solution:**
1. Verify GitLab OAuth application exists:
   ```bash
   curl -s "${GITLAB_URL}/admin/applications" | grep -i matrix
   ```

2. Check OAuth application configuration:
   - **Name**: Matrix/Element SSO
   - **Redirect URI**: `http://localhost:8008/_synapse/client/oidc/callback`
   - **Scopes**: `openid`, `profile`, `email`, `read_user`
   - **Confidential**: Yes

3. Verify environment variables:
   ```bash
   echo "Client ID: $GITLAB_OAUTH_CLIENT_ID"
   echo "Client Secret: $GITLAB_OAUTH_CLIENT_SECRET"
   ```

### 2. Invalid Redirect URI

**Symptoms:**
- "redirect_uri mismatch" error
- OAuth callback fails

**Diagnosis:**
```bash
# Check configured redirect URIs in GitLab
curl -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" \
     "${GITLAB_URL}/api/v4/applications"
```

**Solution:**
1. Update GitLab OAuth application redirect URI to exactly:
   ```
   http://localhost:8008/_synapse/client/oidc/callback
   ```

2. Ensure no trailing slashes or extra characters

3. For production, use HTTPS:
   ```
   https://your-matrix-domain.com/_synapse/client/oidc/callback
   ```

### 3. SSL/TLS Certificate Issues

**Symptoms:**
- "certificate verification failed" errors
- Connection timeouts to GitLab

**For Development (HTTP):**
```yaml
# In homeserver-oauth.yaml
oidc_providers:
  - idp_id: gitlab
    issuer: "http://localhost:8080"  # Use HTTP for local development
```

**For Production (HTTPS):**
```yaml
# In homeserver-oauth.yaml
oidc_providers:
  - idp_id: gitlab
    issuer: "https://your-gitlab-domain.com"
```

### 4. User Mapping Issues

**Symptoms:**
- Users created with incorrect usernames
- Profile information not syncing

**Debug User Mapping:**
```bash
# Check Synapse logs for user creation
docker-compose logs synapse | grep -i "creating user\|user mapping"

# Verify user template in homeserver.yaml
grep -A 10 "localpart_template" data/homeserver.yaml
```

**Common Mapping Fixes:**
```yaml
user_mapping_provider:
  config:
    # Ensure usernames are valid (lowercase, alphanumeric + _-.)
    localpart_template: "{{ user.username | lower | regex_replace('[^a-z0-9._=-]', '_') }}"
    
    # Handle missing display names
    display_name_template: "{{ user.name or user.username }}"
    
    # Ensure email is provided
    email_template: "{{ user.email }}"
```

### 5. Token Validation Failures

**Symptoms:**
- "Invalid token" errors
- Users can't access Matrix after login

**Debug Token Issues:**
```bash
# Check GitLab token endpoint
curl -v "${GITLAB_URL}/oauth/token"

# Verify OIDC configuration
curl -v "${GITLAB_URL}/.well-known/openid_configuration"
```

**Solution:**
1. Verify GitLab OIDC is enabled:
   ```ruby
   # In GitLab Rails console
   Gitlab::Auth::OAuth::Provider.enabled?('oidc')
   ```

2. Check token scopes in GitLab OAuth app

3. Verify Synapse can reach GitLab:
   ```bash
   docker-compose exec synapse curl -v "${GITLAB_URL}/oauth/userinfo"
   ```

### 6. Docker Network Issues

**Symptoms:**
- Services can't communicate
- "Connection refused" errors

**Debug Network:**
```bash
# Check Docker network
docker network inspect matrix-setup_matrix-network

# Test connectivity between services
docker-compose exec synapse ping gitlab
docker-compose exec synapse curl -v http://gitlab/-/health
```

**Solution:**
```yaml
# Ensure all services use same network
networks:
  matrix-network:
    driver: bridge
```

### 7. GitLab Not Ready

**Symptoms:**
- GitLab returns 502/503 errors
- OAuth endpoints not responding

**Check GitLab Status:**
```bash
# Wait for GitLab to be fully ready
curl -f "${GITLAB_URL}/-/health"
curl -f "${GITLAB_URL}/-/readiness"

# Check GitLab logs
docker-compose logs gitlab | grep -i "gitlab.*ready"
```

**Solution:**
- GitLab can take 5-10 minutes to fully start
- Wait for health check to pass before configuring OAuth

### 8. Element Configuration Issues

**Symptoms:**
- No OAuth login button appears
- Element shows password login form

**Debug Element Config:**
```bash
# Check Element configuration
curl -s http://localhost:8009/config.json | jq '.'

# Verify SSO configuration
curl -s http://localhost:8009/config.json | jq '.sso_redirect_options'
```

**Fix Element Config:**
```json
{
  "sso_redirect_options": {
    "immediate": false,
    "on_welcome_page": true
  },
  "disable_3pid_login": true,
  "disable_custom_urls": true
}
```

## Advanced Debugging

### Enable Debug Logging

**In homeserver.yaml:**
```yaml
# Add to log configuration
loggers:
  synapse.handlers.oidc:
    level: DEBUG
  synapse.api.auth.internal:
    level: DEBUG
```

**Restart with debug logging:**
```bash
docker-compose restart synapse
```

### OAuth Flow Testing

**Manual OAuth Flow Test:**
```bash
# 1. Get authorization URL
GITLAB_URL="http://localhost:8080"
CLIENT_ID="your_client_id"
REDIRECT_URI="http://localhost:8008/_synapse/client/oidc/callback"

AUTH_URL="${GITLAB_URL}/oauth/authorize?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&response_type=code&scope=openid%20profile%20email"

echo "Visit: $AUTH_URL"

# 2. After getting code from callback, exchange for token
CODE="authorization_code_from_callback"
curl -X POST "${GITLAB_URL}/oauth/token" \
  -d "grant_type=authorization_code" \
  -d "code=${CODE}" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "redirect_uri=${REDIRECT_URI}"
```

### Database Inspection

**Check Matrix users:**
```bash
# Connect to Matrix database
docker-compose exec postgres-matrix psql -U synapse -d synapse

# List users
SELECT name, creation_ts, admin, deactivated FROM users;

# Check OAuth mappings
SELECT * FROM external_ids WHERE auth_provider = 'oidc';
```

## Performance Monitoring

### Key Metrics to Monitor

```bash
# OAuth authentication success rate
docker-compose logs synapse | grep -c "successful.*oidc"

# Failed authentication attempts
docker-compose logs synapse | grep -c "failed.*oidc"

# User creation events
docker-compose logs synapse | grep -c "creating user.*oidc"

# Token refresh events
docker-compose logs synapse | grep -c "refresh.*token"
```

### Health Check Script

```bash
#!/bin/bash
# oauth-health-check.sh

echo "OAuth Integration Health Check"
echo "=============================="

# Service health
echo "1. Service Status:"
docker-compose ps --format "table {{.Service}}\t{{.Status}}"

# OAuth endpoints
echo -e "\n2. OAuth Endpoints:"
curl -s -o /dev/null -w "GitLab Health: %{http_code}\n" "${GITLAB_URL}/-/health"
curl -s -o /dev/null -w "Matrix Health: %{http_code}\n" "http://localhost:8008/health"
curl -s -o /dev/null -w "Element Health: %{http_code}\n" "http://localhost:8009"

# Authentication metrics
echo -e "\n3. Authentication Stats (last 24h):"
since=$(date -d "24 hours ago" +"%Y-%m-%d %H:%M:%S")
docker-compose logs synapse --since="24h" | grep -c "successful.*oidc" | \
  xargs echo "Successful logins:"
docker-compose logs synapse --since="24h" | grep -c "failed.*oidc" | \
  xargs echo "Failed logins:"
```

## Rollback Procedures

### Quick Rollback

```bash
# Use automated rollback script
./rollback-oauth.sh
```

### Manual Rollback

```bash
# 1. Stop services
docker-compose down

# 2. Restore configurations
cp backups/latest/docker-compose.yml ./
cp backups/latest/element-config.json ./
cp backups/latest/homeserver.yaml data/

# 3. Restart with original config
docker-compose up -d
```

### Emergency Rollback (If Matrix is broken)

```bash
# 1. Stop everything
docker-compose down

# 2. Reset to basic auth only
cat > data/homeserver.yaml << 'EOF'
server_name: "localhost"
enable_registration: true
password_config:
  enabled: true
# ... minimal config
EOF

# 3. Start only essential services
docker-compose up -d postgres-matrix synapse element
```

## Getting Help

### Log Collection for Support

```bash
# Collect all relevant logs
mkdir -p oauth-debug-$(date +%Y%m%d)
docker-compose logs synapse > oauth-debug-$(date +%Y%m%d)/synapse.log
docker-compose logs gitlab > oauth-debug-$(date +%Y%m%d)/gitlab.log
docker-compose ps > oauth-debug-$(date +%Y%m%d)/services.txt
cp .env oauth-debug-$(date +%Y%m%d)/env.txt
cp data/homeserver.yaml oauth-debug-$(date +%Y%m%d)/
cp element-config.json oauth-debug-$(date +%Y%m%d)/
```

### Useful Resources

- **Matrix Synapse OIDC Docs**: https://matrix-org.github.io/synapse/latest/openid.html
- **GitLab OAuth2 Docs**: https://docs.gitlab.com/ee/api/oauth2.html
- **OAuth2 RFC**: https://tools.ietf.org/html/rfc6749
- **Element Configuration**: https://github.com/vector-im/element-web/blob/develop/docs/config.md