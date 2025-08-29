# OAuth Integration Architecture: GitLab ↔ Matrix/Element

## Overview
This document outlines the complete OAuth2 integration between GitLab (identity provider) and Matrix/Element (OAuth client) to enable single sign-on authentication.

## Architecture Components

### 1. GitLab OAuth2 Provider Configuration
- **Role**: Identity Provider (IdP)
- **OAuth2 Flow**: Authorization Code Grant with PKCE
- **Required Scopes**: `openid`, `profile`, `email`, `read_user`
- **Application Type**: Web Application

### 2. Matrix Synapse OAuth2 Client Configuration  
- **Role**: OAuth2 Client
- **Authentication Method**: OAuth2/OIDC with GitLab
- **User Provisioning**: Automatic user creation on first login
- **User Mapping**: GitLab username → Matrix user ID

### 3. Element Web Client Configuration
- **OAuth Login Flow**: Redirect to GitLab for authentication
- **Single Sign-On Experience**: Seamless login button
- **Fallback**: Local authentication disabled (OAuth only)

## OAuth2 Flow Diagram

```
┌─────────────┐    1. Login Request     ┌──────────────┐
│   Element   │ ────────────────────── │   Matrix     │
│ Web Client  │                        │   Synapse    │
└─────────────┘                        └──────────────┘
       │                                       │
       │ 2. Redirect to GitLab                 │
       │ (/oauth/authorize)                    │
       ▼                                       │
┌─────────────┐    3. User Login        ┌─────┴────────┐
│   GitLab    │ ◀──────────────────────── │   User      │
│   OAuth2    │                        │   Browser    │
│  Provider   │ ─────────────────────▶  └──────────────┘
└─────────────┘    4. Authorization              │
       │            Code                         │
       │                                        │
       │ 5. Exchange Code for Token             │
       │ (/oauth/token)                         │
       ▼                                        │
┌──────────────┐ ◀──────────────────────────────┘
│   Matrix     │    6. User Info + Token
│   Synapse    │    7. Create/Login User
└──────────────┘    8. Matrix Access Token
```

## Implementation Steps

### Phase 1: GitLab OAuth2 Application Setup

1. **Create OAuth Application in GitLab**:
   ```
   Name: Matrix/Element SSO
   Redirect URI: http://localhost:8008/_synapse/client/oidc/callback
   Scopes: openid, profile, email, read_user
   Application Type: Web Application
   ```

2. **Configure GitLab OAuth2 Settings**:
   - Enable OAuth2 provider
   - Set token expiration times
   - Configure allowed redirect URIs
   - Generate client credentials

### Phase 2: Matrix Synapse Configuration

1. **Update homeserver.yaml**:
   - Add OIDC provider configuration
   - Configure user mapping rules
   - Set up automatic user registration
   - Disable local password authentication

2. **User Management Configuration**:
   - Map GitLab username to Matrix user ID
   - Sync user profile information
   - Configure group-based access control

### Phase 3: Element Web Client Configuration

1. **Update element-config.json**:
   - Configure OAuth login method
   - Set GitLab as identity provider
   - Customize login UI/UX
   - Disable local registration forms

### Phase 4: Security and Access Control

1. **GitLab Group Integration**:
   - Map GitLab groups to Matrix rooms
   - Configure role-based access
   - Set up administrator privileges

2. **Security Hardening**:
   - Implement PKCE for public clients
   - Configure secure redirect URIs
   - Set appropriate token lifetimes
   - Enable audit logging

## Configuration Files

### GitLab OAuth Application Settings
```yaml
# GitLab Admin → Applications → New Application
name: "Matrix/Element SSO"
redirect_uri: "http://localhost:8008/_synapse/client/oidc/callback"
scopes: ["openid", "profile", "email", "read_user"]
confidential: true
```

### Matrix Synapse OIDC Configuration
```yaml
# homeserver.yaml additions
oidc_providers:
  - idp_id: gitlab
    idp_name: "GitLab"
    discover: false
    issuer: "http://your-gitlab-instance.com"
    authorization_endpoint: "http://your-gitlab-instance.com/oauth/authorize"
    token_endpoint: "http://your-gitlab-instance.com/oauth/token"
    userinfo_endpoint: "http://your-gitlab-instance.com/oauth/userinfo"
    client_id: "your-client-id"
    client_secret: "your-client-secret"
    scopes: ["openid", "profile", "email"]
    user_mapping_provider:
      config:
        localpart_template: "{{ user.preferred_username }}"
        display_name_template: "{{ user.name }}"
        email_template: "{{ user.email }}"
```

### Element Web OAuth Configuration
```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "http://localhost:8008",
      "server_name": "localhost"
    }
  },
  "sso_redirect_options": {
    "immediate": true
  },
  "disable_custom_urls": true,
  "disable_guests": true,
  "disable_3pid_login": true
}
```

## Access Control Strategy

### User Provisioning
1. **First Login**: Automatic user creation from GitLab profile
2. **Profile Sync**: Name, email, avatar from GitLab
3. **Group Mapping**: GitLab groups → Matrix room permissions

### Administrator Controls
1. **User Management**: Add/remove users in GitLab
2. **Access Control**: GitLab group membership
3. **Deactivation**: Disable GitLab account = Matrix access revoked

### Security Features
1. **Single Logout**: Logout from GitLab terminates Matrix session
2. **Token Refresh**: Automatic token renewal
3. **Audit Trail**: Authentication logs in both systems

## Testing Strategy

### Unit Tests
- OAuth flow validation
- User mapping correctness
- Token handling security

### Integration Tests
1. **Login Flow**: GitLab → Matrix → Element
2. **User Creation**: Automatic provisioning
3. **Permission Sync**: Group-based access
4. **Error Handling**: Invalid tokens, expired sessions

### Security Tests
1. **Token Security**: Prevent token leakage
2. **CSRF Protection**: State parameter validation
3. **Redirect URI Validation**: Prevent open redirects

## Monitoring and Logging

### Key Metrics
- Authentication success/failure rates
- Token refresh frequency
- User provisioning events
- Group sync operations

### Log Events
- OAuth authentication attempts
- User creation/updates
- Permission changes
- Error conditions

## Rollback Plan

### Quick Rollback
1. Disable OIDC in homeserver.yaml
2. Re-enable local authentication
3. Restart Synapse service

### Full Rollback
1. Remove OAuth configuration
2. Reset to password-based authentication
3. Manual user account management

## Maintenance Tasks

### Regular Operations
1. **Token Rotation**: Update client secrets
2. **User Sync**: Verify group memberships
3. **Security Updates**: Update OAuth libraries
4. **Monitoring**: Check authentication metrics

### Troubleshooting
1. **Login Failures**: Check OAuth configuration
2. **User Sync Issues**: Verify GitLab API access
3. **Permission Problems**: Audit group mappings

## Success Criteria

✅ **Functional Requirements**:
- Users can login to Element using GitLab credentials
- Single sign-on experience (no separate passwords)
- Automatic user provisioning and profile sync
- Group-based access control working

✅ **Security Requirements**:
- Secure OAuth2 implementation with proper scopes
- Token security and refresh mechanism
- Audit trail for all authentication events
- Protection against common OAuth vulnerabilities

✅ **Operational Requirements**:
- Administrator control through GitLab
- Monitoring and alerting for authentication issues
- Clear rollback procedure
- Documentation for ongoing maintenance