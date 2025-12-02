#!/bin/bash
# Simulate an Authentik webhook notification for testing

AUTH_MANAGER_URL="${AUTH_MANAGER_URL:-http://localhost:8088}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-test-webhook-secret}"

# Example: User created event
send_user_created() {
    local email="${1:-testuser@example.com}"
    local username="${2:-testuser}"
    local name="${3:-Test User}"

    curl -X POST "${AUTH_MANAGER_URL}/webhook/authentik" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${WEBHOOK_SECRET}" \
        -d @- <<EOF
{
    "event": {
        "action": "model_created",
        "app": "authentik_core",
        "model_name": "user",
        "context": {
            "pk": 123,
            "email": "${email}",
            "username": "${username}",
            "name": "${name}"
        },
        "user": {
            "pk": 123,
            "email": "${email}",
            "username": "${username}",
            "name": "${name}"
        },
        "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    },
    "severity": "notice"
}
EOF
    echo ""
}

# Example: User login event
send_user_login() {
    local email="${1:-testuser@example.com}"
    local username="${2:-testuser}"

    curl -X POST "${AUTH_MANAGER_URL}/webhook/authentik" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${WEBHOOK_SECRET}" \
        -d @- <<EOF
{
    "event": {
        "action": "login",
        "app": "authentik_events",
        "model_name": "user",
        "context": {},
        "user": {
            "pk": 123,
            "email": "${email}",
            "username": "${username}",
            "name": "Test User"
        },
        "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    },
    "severity": "notice",
    "event_user_email": "${email}",
    "event_user_username": "${username}"
}
EOF
    echo ""
}

# Manual sync via API
send_manual_sync() {
    local email="${1:-testuser@example.com}"
    local name="${2:-Test User}"
    local username="${3:-testuser}"

    curl -X POST "${AUTH_MANAGER_URL}/api/v1/sync" \
        -H "Content-Type: application/json" \
        -d @- <<EOF
{
    "email": "${email}",
    "name": "${name}",
    "username": "${username}"
}
EOF
    echo ""
}

# Check health
check_health() {
    curl -s "${AUTH_MANAGER_URL}/healthz" | jq .
}

# List shadow users
list_users() {
    curl -s "${AUTH_MANAGER_URL}/api/v1/shadow-users" | jq .
}

# Main
case "${1:-help}" in
    create)
        send_user_created "${2}" "${3}" "${4}"
        ;;
    login)
        send_user_login "${2}" "${3}"
        ;;
    sync)
        send_manual_sync "${2}" "${3}" "${4}"
        ;;
    health)
        check_health
        ;;
    users)
        list_users
        ;;
    *)
        echo "Usage: $0 {create|login|sync|health|users} [email] [username] [name]"
        echo ""
        echo "Commands:"
        echo "  create [email] [username] [name]  - Simulate user creation webhook"
        echo "  login [email] [username]          - Simulate user login webhook"
        echo "  sync [email] [name] [username]    - Trigger manual sync"
        echo "  health                            - Check auth-manager health"
        echo "  users                             - List shadow users"
        echo ""
        echo "Environment variables:"
        echo "  AUTH_MANAGER_URL  - Auth manager base URL (default: http://localhost:8088)"
        echo "  WEBHOOK_SECRET    - Webhook secret for authorization (default: test-webhook-secret)"
        exit 1
        ;;
esac
