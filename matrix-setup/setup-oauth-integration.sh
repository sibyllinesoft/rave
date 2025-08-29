#!/bin/bash

# OAuth Integration Setup Script for GitLab ↔ Matrix/Element
# This script automates the setup of OAuth integration between GitLab and Matrix

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DIR="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"

print_header() {
    echo -e "${BLUE}"
    echo "=================================="
    echo "  OAuth Integration Setup"
    echo "  GitLab ↔ Matrix/Element"
    echo "=================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    local deps=("docker" "docker-compose" "curl" "jq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Please install missing dependencies before continuing."
        exit 1
    fi
    
    print_info "All dependencies found."
}

create_backup() {
    print_step "Creating backup of existing configuration..."
    
    mkdir -p "$BACKUP_DIR"
    
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        cp "$SCRIPT_DIR/docker-compose.yml" "$BACKUP_DIR/"
    fi
    
    if [[ -f "$SCRIPT_DIR/element-config.json" ]]; then
        cp "$SCRIPT_DIR/element-config.json" "$BACKUP_DIR/"
    fi
    
    if [[ -f "$SCRIPT_DIR/data/homeserver.yaml" ]]; then
        cp "$SCRIPT_DIR/data/homeserver.yaml" "$BACKUP_DIR/"
    fi
    
    print_info "Backup created at: $BACKUP_DIR"
}

setup_environment() {
    print_step "Setting up environment configuration..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "${SCRIPT_DIR}/.env.oauth.example" ]]; then
            cp "${SCRIPT_DIR}/.env.oauth.example" "$ENV_FILE"
            print_info "Created .env file from example template."
        else
            print_error ".env.oauth.example file not found!"
            exit 1
        fi
    fi
    
    print_warning "Please edit $ENV_FILE to configure your GitLab OAuth settings."
    print_info "Required variables:"
    echo "  - GITLAB_URL (your GitLab instance URL)"
    echo "  - GITLAB_OAUTH_CLIENT_ID (from GitLab OAuth app)"
    echo "  - GITLAB_OAUTH_CLIENT_SECRET (from GitLab OAuth app)"
    
    read -p "Press Enter after configuring the .env file..."
}

validate_environment() {
    print_step "Validating environment configuration..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error ".env file not found!"
        exit 1
    fi
    
    source "$ENV_FILE"
    
    local required_vars=("GITLAB_URL" "GITLAB_OAUTH_CLIENT_ID" "GITLAB_OAUTH_CLIENT_SECRET")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables: ${missing_vars[*]}"
        print_info "Please configure these variables in $ENV_FILE"
        exit 1
    fi
    
    print_info "Environment configuration is valid."
}

setup_oauth_configs() {
    print_step "Setting up OAuth configuration files..."
    
    # Copy OAuth-enabled configurations
    if [[ -f "${SCRIPT_DIR}/docker-compose-oauth.yml" ]]; then
        cp "${SCRIPT_DIR}/docker-compose-oauth.yml" "${SCRIPT_DIR}/docker-compose.yml"
        print_info "Updated docker-compose.yml with OAuth configuration."
    fi
    
    if [[ -f "${SCRIPT_DIR}/element-config-oauth.json" ]]; then
        cp "${SCRIPT_DIR}/element-config-oauth.json" "${SCRIPT_DIR}/element-config.json"
        print_info "Updated element-config.json with OAuth configuration."
    fi
    
    if [[ -f "${SCRIPT_DIR}/data/homeserver-oauth.yaml" ]]; then
        cp "${SCRIPT_DIR}/data/homeserver-oauth.yaml" "${SCRIPT_DIR}/data/homeserver.yaml"
        print_info "Updated homeserver.yaml with OAuth configuration."
    fi
}

start_services() {
    print_step "Starting services with OAuth configuration..."
    
    print_info "This may take several minutes for GitLab to initialize..."
    
    # Start services
    docker-compose --env-file "$ENV_FILE" up -d
    
    print_info "Services started. Waiting for health checks..."
    
    # Wait for services to be healthy
    local max_wait=600  # 10 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if docker-compose ps | grep -q "Up (healthy)"; then
            print_info "Services are healthy!"
            break
        fi
        
        echo -n "."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        print_warning "Services may still be starting. Check with: docker-compose ps"
    fi
}

test_oauth_endpoints() {
    print_step "Testing OAuth endpoints..."
    
    source "$ENV_FILE"
    
    # Test GitLab OAuth discovery
    print_info "Testing GitLab OAuth discovery endpoint..."
    if curl -s -f "${GITLAB_URL}/.well-known/openid_configuration" > /dev/null; then
        print_info "✅ GitLab OAuth discovery endpoint is accessible"
    else
        print_warning "⚠️  GitLab OAuth discovery endpoint not accessible (may still be starting)"
    fi
    
    # Test Matrix health
    print_info "Testing Matrix Synapse health..."
    if curl -s -f "http://localhost:8008/health" > /dev/null; then
        print_info "✅ Matrix Synapse is healthy"
    else
        print_warning "⚠️  Matrix Synapse not responding"
    fi
    
    # Test Element
    print_info "Testing Element web client..."
    if curl -s -f "http://localhost:8009" > /dev/null; then
        print_info "✅ Element web client is accessible"
    else
        print_warning "⚠️  Element web client not accessible"
    fi
}

show_next_steps() {
    source "$ENV_FILE"
    
    print_step "Setup completed! Next steps:"
    echo ""
    echo -e "${GREEN}1. GitLab OAuth Application Setup:${NC}"
    echo "   - Open: ${GITLAB_URL}/admin/applications"
    echo "   - Create new application with:"
    echo "     Name: Matrix/Element SSO"
    echo "     Redirect URI: http://localhost:8008/_synapse/client/oidc/callback"
    echo "     Scopes: openid, profile, email, read_user"
    echo "   - Update .env with the client ID and secret"
    echo ""
    echo -e "${GREEN}2. Access URLs:${NC}"
    echo "   - GitLab: ${GITLAB_URL}"
    echo "   - Element: http://localhost:8009"
    echo "   - Matrix API: http://localhost:8008"
    echo ""
    echo -e "${GREEN}3. Test OAuth Login:${NC}"
    echo "   - Open Element at http://localhost:8009"
    echo "   - Click 'Continue with GitLab'"
    echo "   - Login with GitLab credentials"
    echo ""
    echo -e "${GREEN}4. Troubleshooting:${NC}"
    echo "   - Check logs: docker-compose logs synapse"
    echo "   - Verify config: ./test-oauth-integration.sh"
    echo "   - Rollback: ./rollback-oauth.sh"
}

create_helper_scripts() {
    print_step "Creating helper scripts..."
    
    # Test script
    cat > "${SCRIPT_DIR}/test-oauth-integration.sh" << 'EOF'
#!/bin/bash
# OAuth Integration Test Script

source .env 2>/dev/null || { echo "Error: .env file not found"; exit 1; }

echo "Testing OAuth Integration..."
echo "=========================="

echo "1. Testing GitLab accessibility..."
curl -s -f "${GITLAB_URL}/health" && echo "✅ GitLab is accessible" || echo "❌ GitLab not accessible"

echo "2. Testing OAuth discovery..."
curl -s -f "${GITLAB_URL}/.well-known/openid_configuration" && echo "✅ OAuth discovery works" || echo "❌ OAuth discovery failed"

echo "3. Testing Matrix Synapse..."
curl -s -f "http://localhost:8008/health" && echo "✅ Synapse is healthy" || echo "❌ Synapse not responding"

echo "4. Testing Element..."
curl -s -f "http://localhost:8009" && echo "✅ Element is accessible" || echo "❌ Element not accessible"

echo "5. Testing OIDC endpoint..."
curl -s -f "http://localhost:8008/_synapse/client/oidc/callback" && echo "✅ OIDC callback endpoint ready" || echo "❌ OIDC endpoint not ready"

echo "Test completed!"
EOF

    chmod +x "${SCRIPT_DIR}/test-oauth-integration.sh"
    
    # Rollback script
    cat > "${SCRIPT_DIR}/rollback-oauth.sh" << EOF
#!/bin/bash
# Rollback OAuth Integration

LATEST_BACKUP=\$(find backups -name "2*" -type d | sort | tail -1)

if [[ -z "\$LATEST_BACKUP" ]]; then
    echo "No backups found!"
    exit 1
fi

echo "Rolling back to backup: \$LATEST_BACKUP"

docker-compose down
cp "\$LATEST_BACKUP"/* ./ 2>/dev/null || true
cp "\$LATEST_BACKUP"/homeserver.yaml data/ 2>/dev/null || true
docker-compose up -d

echo "Rollback completed!"
EOF

    chmod +x "${SCRIPT_DIR}/rollback-oauth.sh"
    
    print_info "Helper scripts created: test-oauth-integration.sh, rollback-oauth.sh"
}

main() {
    print_header
    
    check_dependencies
    create_backup
    setup_environment
    validate_environment
    setup_oauth_configs
    create_helper_scripts
    start_services
    test_oauth_endpoints
    show_next_steps
    
    echo ""
    print_info "OAuth integration setup completed successfully!"
    print_warning "Remember to configure the GitLab OAuth application before testing login."
}

# Handle script interruption
trap 'print_error "Script interrupted. You may need to run: docker-compose down"; exit 1' INT

main "$@"