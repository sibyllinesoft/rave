# OAuth Integration for GitLab ↔ Matrix/Element

## 🎯 Overview

This repository contains a complete OAuth integration solution for enabling single sign-on between GitLab and Matrix/Element. Users can authenticate to Element using their GitLab credentials, with centralized access control through GitLab.

## 🏗️ Architecture

```
┌─────────────┐    1. OAuth Login    ┌──────────────┐
│   Element   │ ────────────────────→ │   Matrix     │
│ Web Client  │                     │   Synapse    │
└─────────────┘                     └──────────────┘
       │                                     │
       │ 2. Redirect to GitLab               │ 3. OIDC Auth
       ▼                                     ▼
┌─────────────┐    4. User Login     ┌──────────────┐
│   GitLab    │ ←────────────────────→ │    User     │
│ OAuth2 IdP  │    5. Grant Access   │   Browser    │
└─────────────┘                     └──────────────┘
```

## ✨ Features

- **Single Sign-On**: Users login to Element with GitLab credentials
- **Automatic User Provisioning**: Users created automatically on first login
- **Profile Synchronization**: Name, email, and avatar sync from GitLab
- **Centralized Access Control**: Manage access through GitLab groups
- **Security**: OAuth2/OIDC implementation with proper scopes
- **Easy Setup**: Automated configuration scripts
- **Comprehensive Monitoring**: Logging and health checks

## 🚀 Quick Start

### 1. Prerequisites

- Docker and Docker Compose
- Administrative access to GitLab instance

### 2. Basic Setup

```bash
# 1. Configure environment
cp .env.oauth.example .env
nano .env  # Add your GitLab URL and OAuth credentials

# 2. Run automated setup
./setup-oauth-integration.sh

# 3. Create GitLab OAuth application (follow prompts)

# 4. Test the integration
./test-oauth-integration.sh
```

### 3. Access Applications

- **Element**: http://localhost:8009
- **GitLab**: http://localhost:8080 (if using bundled GitLab)
- **Matrix API**: http://localhost:8008

## 📁 File Structure

```
matrix-setup/
├── OAUTH_INTEGRATION_ARCHITECTURE.md  # Detailed architecture documentation
├── OAUTH_SETUP_INSTRUCTIONS.md        # Step-by-step setup guide
├── OAUTH_TROUBLESHOOTING_GUIDE.md     # Common issues and solutions
├── setup-oauth-integration.sh         # Automated setup script
├── test-oauth-integration.sh          # Integration testing script
├── rollback-oauth.sh                  # Rollback to previous configuration
├── docker-compose-oauth.yml           # OAuth-enabled Docker Compose
├── element-config-oauth.json          # OAuth-enabled Element configuration
├── data/homeserver-oauth.yaml         # OAuth-enabled Synapse configuration
└── .env.oauth.example                 # Environment variables template
```

## 🔧 Configuration Files

### GitLab OAuth Application Settings
```yaml
Name: Matrix/Element SSO
Redirect URI: http://localhost:8008/_synapse/client/oidc/callback
Scopes: openid, profile, email, read_user
Confidential: Yes
```

### Key Environment Variables
```bash
GITLAB_URL=http://localhost:8080
GITLAB_OAUTH_CLIENT_ID=your_client_id
GITLAB_OAUTH_CLIENT_SECRET=your_client_secret
```

## 🛠️ Advanced Configuration

### Access Control via GitLab Groups

Restrict access to specific GitLab groups:

```yaml
# In homeserver-oauth.yaml
oidc_providers:
  - idp_id: gitlab
    attribute_requirements:
      - attribute: "groups"
        value: "matrix-users"
```

### Automatic Room Joining

Auto-join users to rooms:

```yaml
auto_join_rooms:
  - "#general:localhost"
  - "#announcements:localhost"
```

### Custom User Mapping

Advanced user mapping rules:

```yaml
user_mapping_provider:
  config:
    localpart_template: "{{ user.username | lower | regex_replace('[^a-z0-9._=-]', '_') }}"
    display_name_template: "{{ user.name or user.username }}"
    email_template: "{{ user.email }}"
```

## 🔍 Monitoring & Troubleshooting

### Health Checks

```bash
# Quick health check
./test-oauth-integration.sh

# Service status
docker-compose ps

# View logs
docker-compose logs synapse
docker-compose logs gitlab
```

### Common Issues

| Issue | Quick Fix |
|-------|-----------|
| No OAuth button in Element | Check `element-config-oauth.json` |
| Invalid redirect URI | Verify callback URL in GitLab OAuth app |
| User creation fails | Check user mapping in `homeserver-oauth.yaml` |
| GitLab not accessible | Wait for GitLab startup (5-10 minutes) |

### Debug Mode

Enable detailed logging:

```yaml
# In homeserver-oauth.yaml
loggers:
  synapse.handlers.oidc:
    level: DEBUG
```

## 🚨 Security Considerations

### Development vs Production

**Development (HTTP)**:
- Uses HTTP for local testing
- Self-signed certificates acceptable
- Default passwords for GitLab

**Production (HTTPS)**:
- Requires HTTPS for OAuth security
- Valid SSL certificates required
- Strong passwords and secrets
- Rate limiting enabled

### Security Checklist

- ✅ Use HTTPS in production
- ✅ Strong client secrets
- ✅ Proper OAuth scopes
- ✅ Regular secret rotation
- ✅ Monitor authentication logs
- ✅ Disable local password auth
- ✅ Configure rate limiting

## 📈 Performance & Scaling

### Resource Requirements

**Minimum (Development)**:
- 4GB RAM
- 2 CPU cores
- 20GB disk space

**Recommended (Production)**:
- 8GB+ RAM
- 4+ CPU cores
- 100GB+ disk space
- SSD storage

### Scaling Considerations

- **Database**: Use external PostgreSQL for production
- **GitLab**: Consider GitLab.com or dedicated instance
- **Load Balancing**: Use reverse proxy for multiple Synapse instances
- **Caching**: Redis for session caching

## 🔄 Maintenance

### Regular Tasks

```bash
# Update OAuth tokens quarterly
# Monitor authentication metrics
# Review access logs monthly
# Test backup/restore procedures
# Update Docker images regularly
```

### Backup Procedures

```bash
# Backup configuration
mkdir -p backups/$(date +%Y%m%d)
cp .env backups/$(date +%Y%m%d)/
cp data/homeserver.yaml backups/$(date +%Y%m%d)/
cp element-config.json backups/$(date +%Y%m%d)/

# Backup database
docker-compose exec postgres-matrix pg_dump -U synapse synapse > \
  backups/$(date +%Y%m%d)/matrix_database.sql
```

## 📚 Additional Resources

### Documentation
- [OAuth Integration Architecture](OAUTH_INTEGRATION_ARCHITECTURE.md)
- [Setup Instructions](OAUTH_SETUP_INSTRUCTIONS.md)  
- [Troubleshooting Guide](OAUTH_TROUBLESHOOTING_GUIDE.md)

### External References
- [Matrix Synapse OIDC Documentation](https://matrix-org.github.io/synapse/latest/openid.html)
- [GitLab OAuth2 API Documentation](https://docs.gitlab.com/ee/api/oauth2.html)
- [Element Configuration Guide](https://github.com/vector-im/element-web/blob/develop/docs/config.md)

## 🤝 Support

### Getting Help

1. **Check troubleshooting guide**: `OAUTH_TROUBLESHOOTING_GUIDE.md`
2. **Run diagnostics**: `./test-oauth-integration.sh`
3. **Review logs**: `docker-compose logs synapse`
4. **Test rollback**: `./rollback-oauth.sh`

### Contributing

Contributions welcome! Please:
1. Test changes with the integration scripts
2. Update documentation as needed
3. Follow security best practices
4. Test both development and production scenarios

## 📄 License

This configuration is provided as-is for educational and development purposes. Ensure compliance with your organization's security policies before production use.

---

## 🎯 Success Criteria

After setup completion, you should have:

- ✅ **Single Sign-On**: Users can login to Element with GitLab credentials
- ✅ **No Password Management**: Users don't manage separate Matrix passwords  
- ✅ **Centralized Access**: Administrators control access through GitLab
- ✅ **Automatic Provisioning**: Users created automatically on first login
- ✅ **Profile Sync**: User information synchronized from GitLab
- ✅ **Secure Implementation**: OAuth2/OIDC with proper security measures

**Ready to get started? Follow the [Setup Instructions](OAUTH_SETUP_INSTRUCTIONS.md)!**