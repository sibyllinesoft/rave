#!/bin/bash
# RAVE Phase P6: GitLab API Integration Script
# Posts sandbox access information to merge request comments

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_VERSION="v4"
GITLAB_URL="${CI_SERVER_URL:-https://gitlab.com}"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_info() {
    log "INFO: $*"
}

log_error() {
    log "ERROR: $*"
}

log_warn() {
    log "WARN: $*"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Post sandbox VM access information to GitLab merge request.

OPTIONS:
    --project-id ID         GitLab project ID (required)
    --mr-iid IID            Merge request internal ID (required)
    --sandbox-info FILE     JSON file with sandbox information (required)
    --gitlab-url URL        GitLab URL (default: $GITLAB_URL)
    --token TOKEN           GitLab access token (default: from environment)
    --help                  Show this help message

EXAMPLES:
    $0 --project-id 123 --mr-iid 45 --sandbox-info sandbox.json
    $0 --project-id 123 --mr-iid 45 --sandbox-info sandbox.json --gitlab-url https://gitlab.example.com

ENVIRONMENT VARIABLES:
    GITLAB_ACCESS_TOKEN     GitLab access token for API calls
    CI_SERVER_URL          GitLab server URL (when running in CI)
    CI_API_V4_URL          GitLab API v4 URL (when running in CI)
    
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --mr-iid)
                MR_IID="$2"
                shift 2
                ;;
            --sandbox-info)
                SANDBOX_INFO_FILE="$2"
                shift 2
                ;;
            --gitlab-url)
                GITLAB_URL="$2"
                shift 2
                ;;
            --token)
                GITLAB_ACCESS_TOKEN="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required (--project-id)"
        usage
        exit 1
    fi
    
    if [[ -z "${MR_IID:-}" ]]; then
        log_error "Merge request IID is required (--mr-iid)"
        usage
        exit 1
    fi
    
    if [[ -z "${SANDBOX_INFO_FILE:-}" ]]; then
        log_error "Sandbox info file is required (--sandbox-info)"
        usage
        exit 1
    fi
    
    if [[ ! -f "$SANDBOX_INFO_FILE" ]]; then
        log_error "Sandbox info file not found: $SANDBOX_INFO_FILE"
        exit 1
    fi
    
    # Set default token from environment
    GITLAB_ACCESS_TOKEN=${GITLAB_ACCESS_TOKEN:-${CI_JOB_TOKEN:-}}
    
    if [[ -z "$GITLAB_ACCESS_TOKEN" ]]; then
        log_error "GitLab access token is required (GITLAB_ACCESS_TOKEN environment variable or --token)"
        exit 1
    fi
    
    # Set API URL
    if [[ -n "${CI_API_V4_URL:-}" ]]; then
        API_URL="$CI_API_V4_URL"
    else
        API_URL="$GITLAB_URL/api/$API_VERSION"
    fi
}

# Load sandbox information
load_sandbox_info() {
    log_info "Loading sandbox information from: $SANDBOX_INFO_FILE"
    
    if ! SANDBOX_INFO=$(cat "$SANDBOX_INFO_FILE"); then
        log_error "Failed to read sandbox info file"
        exit 1
    fi
    
    # Validate JSON format
    if ! echo "$SANDBOX_INFO" | jq . >/dev/null 2>&1; then
        log_error "Invalid JSON in sandbox info file"
        exit 1
    fi
    
    # Extract key information
    VM_NAME=$(echo "$SANDBOX_INFO" | jq -r '.vm_name // "Unknown"')
    SSH_HOST=$(echo "$SANDBOX_INFO" | jq -r '.ssh_host // "Unknown"')
    SSH_PORT=$(echo "$SANDBOX_INFO" | jq -r '.ssh_port // "2200"')
    WEB_URL=$(echo "$SANDBOX_INFO" | jq -r '.web_url // "Unknown"')
    COMMIT_SHA=$(echo "$SANDBOX_INFO" | jq -r '.commit // "Unknown"')
    BRANCH_NAME=$(echo "$SANDBOX_INFO" | jq -r '.branch_name // "Unknown"')
    CREATED_AT=$(echo "$SANDBOX_INFO" | jq -r '.created_at // "Unknown"')
    EXPIRES_AT=$(echo "$SANDBOX_INFO" | jq -r '.expires_at // "Unknown"')
    
    log_info "Sandbox VM: $VM_NAME"
    log_info "SSH Access: $SSH_HOST:$SSH_PORT"
    log_info "Web Access: $WEB_URL"
}

# Generate comment content
generate_comment() {
    log_info "Generating merge request comment..."
    
    # Format expiration time
    local expires_formatted="Unknown"
    if [[ "$EXPIRES_AT" != "Unknown" ]]; then
        expires_formatted=$(date -d "$EXPIRES_AT" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$EXPIRES_AT")
    fi
    
    # Generate comment markdown
    cat << EOF
🚀 **Sandbox Environment Ready**

Your merge request has been deployed to an isolated sandbox environment for testing!

## 📋 Access Information

| Service | Access Method | Details |
|---------|---------------|---------|
| **SSH Access** | \`ssh -p $SSH_PORT agent@$SSH_HOST\` | Direct terminal access |
| **Web Interface** | [$WEB_URL]($WEB_URL) | Full RAVE application |
| **Vibe Kanban** | [$WEB_URL]($WEB_URL) | Project management |
| **Grafana** | [$WEB_URL/grafana/]($WEB_URL/grafana/) | Monitoring dashboards |
| **Claude Code Router** | [$WEB_URL/ccr-ui/]($WEB_URL/ccr-ui/) | AI agent interface |

## 🔧 Environment Details

- **VM Name**: \`$VM_NAME\`
- **Branch**: \`$BRANCH_NAME\`
- **Commit**: \`$(echo "$COMMIT_SHA" | cut -c1-8)\`
- **Created**: $CREATED_AT
- **Expires**: $expires_formatted

## 🧪 Testing Instructions

1. **SSH Access**: Use the SSH command above to connect directly to the sandbox
2. **Web Testing**: Click the web interface link to test the full application
3. **API Testing**: All APIs are available at the base URL
4. **Log Monitoring**: Check Grafana dashboards for system metrics

## 🛡️ Security Notes

- This sandbox is isolated and temporary
- No production data is accessible
- All changes are contained within this environment
- Automatic cleanup occurs after 2 hours

## 🔄 Automated Features

- ✅ **Health Checks**: Basic service health validated
- ✅ **Resource Limits**: 4GB RAM, 2 CPU cores
- ✅ **Network Isolation**: Sandboxed networking
- ✅ **Auto Cleanup**: Scheduled in 2 hours

## 🆘 Troubleshooting

If you encounter issues:

1. **SSH Connection Failed**: Wait 1-2 minutes for VM boot completion
2. **Web Interface 502**: Services may still be starting, retry in 30 seconds  
3. **Timeout Errors**: VM might be under heavy load, try again
4. **Need Help**: Contact the platform team or comment on this MR

---

*🤖 This sandbox was automatically created by GitLab CI/CD Pipeline*  
*Environment will be automatically cleaned up at $expires_formatted*
EOF
}

# Post comment to GitLab
post_comment() {
    log_info "Posting comment to merge request $MR_IID in project $PROJECT_ID..."
    
    local comment_body
    comment_body=$(generate_comment)
    
    # Prepare API request
    local api_url="$API_URL/projects/$PROJECT_ID/merge_requests/$MR_IID/notes"
    local temp_file
    temp_file=$(mktemp)
    
    # Create JSON payload
    jq -n \
        --arg body "$comment_body" \
        '{body: $body}' > "$temp_file"
    
    # Make API request
    local response
    local http_code
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "@$temp_file" \
        "$api_url")
    
    # Extract HTTP status code
    http_code=$(echo "$response" | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
    response_body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]{3}$//')
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Check response
    if [[ "$http_code" -eq 201 ]]; then
        log_info "✅ Comment posted successfully"
        
        # Extract comment details
        local comment_id
        local comment_url
        comment_id=$(echo "$response_body" | jq -r '.id // "unknown"' 2>/dev/null || echo "unknown")
        comment_url=$(echo "$response_body" | jq -r '.web_url // ""' 2>/dev/null || echo "")
        
        log_info "Comment ID: $comment_id"
        if [[ -n "$comment_url" ]]; then
            log_info "Comment URL: $comment_url"
        fi
        
        return 0
    else
        log_error "❌ Failed to post comment (HTTP $http_code)"
        log_error "API URL: $api_url"
        log_error "Response: $response_body"
        return 1
    fi
}

# Check GitLab API connectivity
check_gitlab_api() {
    log_info "Checking GitLab API connectivity..."
    
    local api_url="$API_URL/projects/$PROJECT_ID"
    local response
    local http_code
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" \
        "$api_url")
    
    http_code=$(echo "$response" | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
    
    if [[ "$http_code" -eq 200 ]]; then
        log_info "✅ GitLab API connectivity verified"
        return 0
    else
        log_error "❌ GitLab API connectivity failed (HTTP $http_code)"
        log_error "API URL: $api_url"
        return 1
    fi
}

# Check if MR exists
check_mr_exists() {
    log_info "Verifying merge request exists..."
    
    local api_url="$API_URL/projects/$PROJECT_ID/merge_requests/$MR_IID"
    local response
    local http_code
    
    response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" \
        "$api_url")
    
    http_code=$(echo "$response" | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
    
    if [[ "$http_code" -eq 200 ]]; then
        log_info "✅ Merge request found"
        
        # Extract MR details for logging
        local mr_title
        local mr_author
        mr_title=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]{3}$//' | jq -r '.title // "Unknown"' 2>/dev/null || echo "Unknown")
        mr_author=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]{3}$//' | jq -r '.author.name // "Unknown"' 2>/dev/null || echo "Unknown")
        
        log_info "MR Title: $mr_title"
        log_info "MR Author: $mr_author"
        return 0
    else
        log_error "❌ Merge request not found (HTTP $http_code)"
        log_error "API URL: $api_url"
        return 1
    fi
}

# Add error notification
post_error_comment() {
    local error_message="$1"
    
    log_warn "Posting error notification to merge request..."
    
    local comment_body
    comment_body=$(cat << EOF
🚨 **Sandbox Environment Error**

There was an issue setting up the sandbox environment for this merge request.

**Error Details:**
\`\`\`
$error_message
\`\`\`

**What to do:**
1. Check the pipeline logs for more details
2. Retry the pipeline if this was a temporary issue  
3. Contact the platform team if the issue persists

---
*🤖 Automated error notification from GitLab CI/CD Pipeline*
EOF
)
    
    local temp_file
    temp_file=$(mktemp)
    
    jq -n --arg body "$comment_body" '{body: $body}' > "$temp_file"
    
    curl -s \
        -X POST \
        -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "@$temp_file" \
        "$API_URL/projects/$PROJECT_ID/merge_requests/$MR_IID/notes" \
        >/dev/null 2>&1 || true
    
    rm -f "$temp_file"
}

# Main execution
main() {
    log_info "📝 RAVE P6: GitLab API Integration Script"
    log_info "======================================="
    
    # Parse arguments
    parse_args "$@"
    
    # Setup error handling
    trap 'post_error_comment "Script execution failed"; exit 1' ERR
    
    # Validate environment
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    # Execute workflow
    load_sandbox_info
    check_gitlab_api
    check_mr_exists
    
    if post_comment; then
        log_info "🎉 Successfully posted sandbox access information to MR"
    else
        log_error "❌ Failed to post comment to merge request"
        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi