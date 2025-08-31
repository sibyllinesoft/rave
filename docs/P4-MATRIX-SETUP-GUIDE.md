# P4 Matrix Service Setup Guide

## 🚀 Quick Start: Matrix Integration Setup

This guide walks through the final steps to complete the P4 Matrix service integration after the NixOS configuration has been deployed.

### Prerequisites
- P4 NixOS configuration deployed and services running
- GitLab accessible and administrative access available
- sops-nix secrets properly configured

## Step 1: Verify Base Services

```bash
# Check all P4 services are running
sudo systemctl status matrix-synapse gitlab nginx postgresql

# Run the comprehensive test suite
./test-p4-matrix.sh

# Check service logs if needed
sudo journalctl -u matrix-synapse -f
```

## Step 2: Configure GitLab OAuth Application

### 2.1 Access GitLab Admin Area
1. Navigate to: `https://rave.local:3002/gitlab/admin/applications`
2. Sign in with GitLab root credentials
3. Click "New Application"

### 2.2 Create Matrix OAuth Application
Fill in the application form:

- **Name**: `Matrix Synapse`
- **Redirect URI**: `https://rave.local:3002/matrix/_synapse/client/oidc/callback`
- **Scopes**: Select these checkboxes:
  - ☑️ `openid`
  - ☑️ `profile` 
  - ☑️ `email`
- **Confidential**: ☑️ Yes (checked)

### 2.3 Save OAuth Credentials
After creating the application:
1. Copy the **Application ID**
2. Copy the **Secret**
3. Keep these values secure - you'll need them in the next step

## Step 3: Update Secrets Configuration

### 3.1 Edit Secrets File
```bash
# Edit the encrypted secrets file
sops secrets.yaml
```

### 3.2 Update OAuth Values
Replace the placeholder values with your actual OAuth credentials:

```yaml
# Find this section and update with real values
gitlab:
  oauth-matrix-client-id: "your-actual-application-id-here"
  
oidc:
  matrix-client-secret: "your-actual-secret-here"
```

### 3.3 Generate Additional Matrix Secrets
```bash
# Generate a random shared secret for Matrix
openssl rand -hex 32

# Generate admin password
openssl rand -base64 32

# Generate app service token for P5
openssl rand -hex 64
```

Update these in `secrets.yaml`:
```yaml
matrix:
  shared-secret: "your-generated-shared-secret"
  admin-password: "your-generated-admin-password"
  app-service-token: "your-generated-app-service-token"

database:
  matrix-password: "your-generated-db-password"
```

## Step 4: Restart Services

```bash
# Restart Matrix Synapse to pick up new configuration
sudo systemctl restart matrix-synapse

# Restart nginx to ensure proxy configuration is current
sudo systemctl restart nginx

# Check service status
sudo systemctl status matrix-synapse nginx
```

## Step 5: Test OIDC Authentication

### 5.1 Access Element Web Client
1. Open: `https://rave.local:3002/element/`
2. Element should load with the RAVE Matrix configuration

### 5.2 Test GitLab SSO Login
1. Click "Sign In" in Element
2. You should see a "GitLab" button/option
3. Click "GitLab" to initiate OIDC flow
4. Should redirect to GitLab OAuth consent page
5. Grant permissions to Matrix
6. Should redirect back to Element with successful login

### 5.3 Verify User Creation
```bash
# Check if Matrix user was created
echo "SELECT name, creation_ts FROM users;" | sudo -u postgres psql synapse

# Check Matrix logs for OIDC activity
sudo journalctl -u matrix-synapse --since="5 minutes ago" | grep -i oidc
```

## Step 6: Create Admin User and Control Rooms

### 6.1 Create Matrix Admin User
```bash
# Register admin user directly (emergency access)
sudo -u matrix-synapse register_new_matrix_user \
  -c /etc/matrix-synapse/homeserver.yaml \
  -a  # -a flag makes user admin
```

### 6.2 Create Agent Control Rooms (via Element)
1. Log into Element as admin user
2. Create rooms for agent control:
   - `#agent-control:rave.local` - Main agent command room
   - `#agent-status:rave.local` - Agent status reporting
   - `#ci-cd-hooks:rave.local` - GitLab webhook integration
   - `#system-alerts:rave.local` - System monitoring alerts

### 6.3 Configure Room Settings
For each control room:
- Set room to "Private" (invite only)
- Enable end-to-end encryption
- Set proper power levels for admin control
- Add room description explaining purpose

## Step 7: Validation and Testing

### 7.1 Run Full Test Suite
```bash
# Run the comprehensive P4 test suite
./test-p4-matrix.sh

# Should show all tests passing
```

### 7.2 Test Matrix Functionality
1. **Element Interface**: Verify web client loads and functions
2. **User Authentication**: Test GitLab OIDC login flow
3. **Room Creation**: Create and manage rooms
4. **Message Sending**: Send messages between users
5. **File Uploads**: Test media upload functionality (up to 100MB)

### 7.3 Monitor System Health
```bash
# Check resource usage
sudo systemctl show matrix-synapse -p MemoryMax MemoryCurrentr

# Monitor metrics
curl -s https://rave.local:3002/matrix/_synapse/metrics | grep -E "(process_|synapse_)"

# Check Grafana dashboard
# Navigate to: https://rave.local:3002/grafana/
# Look for Matrix Synapse monitoring dashboard
```

## Step 8: Prepare for Phase P5

### 8.1 Document Configuration
```bash
# Create configuration backup
sudo cp /etc/matrix-synapse/homeserver.yaml /home/agent/matrix-config-backup.yaml

# Document OAuth app settings
cat > /home/agent/matrix-oauth-config.txt << 'EOF'
GitLab OAuth Application for Matrix:
- Name: Matrix Synapse
- Application ID: [recorded in secrets.yaml]
- Redirect URI: https://rave.local:3002/matrix/_synapse/client/oidc/callback
- Scopes: openid, profile, email
- Confidential: Yes

Access URLs:
- Element Client: https://rave.local:3002/element/
- Matrix API: https://rave.local:3002/matrix/
- Admin Interface: Element with admin user
EOF
```

### 8.2 Verify P5 Readiness
```bash
# Check appservice token is configured
grep -i "app.*service" /etc/matrix-synapse/homeserver.yaml

# Verify admin user exists
echo "SELECT name, admin FROM users WHERE admin=1;" | sudo -u postgres psql synapse

# Check control rooms are ready (should be created in Element)
echo "SELECT room_id, creator FROM rooms;" | sudo -u postgres psql synapse
```

## 🎉 P4 Matrix Integration Complete!

### ✅ Verification Checklist
- [ ] Matrix Synapse service running and healthy
- [ ] Element web client accessible and functional
- [ ] GitLab OAuth application created and configured
- [ ] OIDC authentication flow working end-to-end
- [ ] Matrix admin user created with proper privileges
- [ ] Agent control rooms created and configured
- [ ] System monitoring and metrics collection active
- [ ] All tests passing in test suite

### 🚀 Ready for Phase P5
With P4 complete, you now have:
- Secure Matrix communication platform
- GitLab OIDC authentication integration
- Admin controls for room and user management
- Monitoring and health checking
- Foundation for Matrix Appservice bridge (P5)

### 🔧 Administration Commands
```bash
# Start Matrix admin helper
~/matrix-admin.sh

# Start OAuth setup helper (if reconfiguration needed)
~/setup-matrix-oauth.sh

# View Matrix service status
systemctl status matrix-synapse

# View Matrix logs
journalctl -u matrix-synapse -f

# Access Element web client
curl -s https://rave.local:3002/element/
```

### 📞 Support Commands
```bash
# Test Matrix health
curl -s https://rave.local:3002/health/matrix

# Check database connectivity
sudo -u matrix-synapse psql -h /run/postgresql -d synapse -c 'SELECT 1;'

# Verify OIDC configuration
curl -s https://rave.local:3002/gitlab/.well-known/openid_configuration | jq .

# Monitor resource usage
htop -u matrix-synapse
```

---

**Phase P4 Matrix Integration**: ✅ **COMPLETE**
**Next Phase**: P5 Matrix Appservice Bridge for Agent Control