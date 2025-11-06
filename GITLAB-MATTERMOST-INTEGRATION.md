# GitLab-Mattermost Integration

This document describes the automated GitLab-Mattermost integration implemented in RAVE.

## Overview

The RAVE VM automatically configures GitLab and Mattermost to work together, providing:

1. **Single Sign-On (SSO)**: Users can sign into Mattermost using their GitLab credentials
2. **CI/CD Notifications**: Automatic notifications in Mattermost when GitLab CI pipelines run
3. **Automated Setup**: No manual configuration required - everything is set up automatically

## Features

### Authentication Integration
- GitLab OAuth provider configured for Mattermost
- Users can sign in to Mattermost using GitLab accounts
- Automatic user linking and account creation

### CI/CD Monitoring
- Dedicated "builds" channel created automatically in Mattermost
- Real-time notifications for:
  - ✅ Pipeline success/failure
  - 🏗️ Job failures (individual build steps)
  - 📦 Deployment events
  - 🔄 Merge request events
  - 🏷️ Tag/release events
- All GitLab projects automatically configured for notifications

### Automatic Configuration
- `gitlab-mattermost-ci-bridge` service handles all setup
- Creates Mattermost team and channels
- Configures webhook integrations
- Sets up OAuth applications
- Runs automatically on VM startup

## Architecture

```
GitLab (localhost:18221/gitlab/)
    ↓ OAuth Provider
Mattermost (localhost:18231/mattermost/)
    ↓ Incoming Webhooks
"builds" Channel
    ↓ Notifications
CI/CD Events, MRs, Deployments
```

## Services

### Core Services
- **GitLab**: Git repository management, CI/CD pipelines
- **Mattermost**: Team chat and notifications
- **PostgreSQL**: Shared database for both services
- **Redis**: Caching and session storage

### Integration Services
- **gitlab-mattermost-oauth**: Sets up OAuth application in GitLab
- **gitlab-mattermost-ci-bridge**: Configures channels and webhooks

## Configuration

The integration is configured via environment variables in the bridge service:

```bash
MATTERMOST_BASE_URL=http://127.0.0.1:8065
MATTERMOST_SITE_URL=https://localhost:18231/mattermost
MATTERMOST_TEAM_NAME=rave
MATTERMOST_TEAM_DISPLAY_NAME=RAVE
MATTERMOST_CHANNEL_NAME=builds
MATTERMOST_CHANNEL_DISPLAY_NAME=Builds
GITLAB_API_BASE_URL=http://127.0.0.1:8123/api/v4
```

## URLs

- **GitLab**: https://localhost:18221/gitlab/
- **Mattermost**: https://localhost:18231/mattermost/
- **Main Dashboard**: https://localhost:18221/

## Testing the Integration

1. **Start the VM**:
   ```bash
   ./cli/rave vm start your-project
   ```

2. **Access GitLab**: 
   - Visit https://localhost:18221/gitlab/
   - Sign in with root/admin123456

3. **Access Mattermost**:
   - Visit https://localhost:18231/mattermost/
   - Click "GitLab" to sign in with OAuth

4. **Test CI Notifications**:
   - Create a project in GitLab
   - Add a `.gitlab-ci.yml` file
   - Push a commit to trigger CI
   - Check the "builds" channel in Mattermost

## Notification Types

The integration sends notifications for:

| Event Type | Description | Channel |
|------------|-------------|---------|
| Pipeline Success | ✅ CI pipeline completed successfully | #builds |
| Pipeline Failure | ❌ CI pipeline failed | #builds |
| Job Failure | 🚨 Individual job in pipeline failed | #builds |
| Merge Request | 🔄 MR opened, updated, or merged | #builds |
| Tag/Release | 🏷️ New tag or release created | #builds |
| Deployment | 📦 Application deployed | #builds |

## Troubleshooting

### Check Service Status
```bash
# SSH into VM
sshpass -p 'debug123' ssh root@localhost -p 2224

# Check integration service
systemctl status gitlab-mattermost-ci-bridge.service

# View integration logs
journalctl -u gitlab-mattermost-ci-bridge.service -f

# Check configuration file
cat /var/lib/rave/gitlab-mattermost-ci.json
```

### Manual Test Script
Run the integration test script:
```bash
./test-integration.sh
```

### Common Issues

1. **Services Starting Up**: Both GitLab and Mattermost take 2-3 minutes to fully start
2. **OAuth Issues**: Ensure both services are fully running before testing OAuth
3. **Webhook Failures**: Check that the "builds" channel exists in Mattermost

## Security

- OAuth client secrets managed via SOPS encryption
- TLS verification disabled for local development (localhost certificates)
- Admin credentials stored securely
- API tokens with minimal required permissions

## Development

To modify the integration:

1. Edit `nixos/configs/complete-production.nix`
2. Update the `ensureGitlabMattermostCiScript` Python script
3. Rebuild VM: `nix build`
4. Test integration: `./test-integration.sh`

## API Endpoints

The integration uses these API endpoints:

### Mattermost API
- `/api/v4/users/login` - Authentication
- `/api/v4/teams` - Team management
- `/api/v4/channels` - Channel management  
- `/api/v4/hooks/incoming` - Webhook configuration

### GitLab API
- `/api/v4/projects` - Project listing
- `/projects/{id}/services/mattermost` - Mattermost integration setup
- `/oauth/applications` - OAuth app management

## Future Enhancements

Potential improvements:
- Custom notification templates
- Channel routing based on project/branch
- Integration with GitLab Issues
- Slash commands in Mattermost
- Deploy button integration