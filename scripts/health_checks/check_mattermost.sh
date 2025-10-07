#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://localhost:8443/mattermost"
BRIDGE_HEALTH="http://127.0.0.1:9100/health"

function check_bridge() {
    if curl -sf "$BRIDGE_HEALTH" >/dev/null; then
        echo "✅ Chat bridge healthy"
    else
        echo "❌ Chat bridge unhealthy"
        return 1
    fi
}

function check_mattermost_http() {
    if curl -sk "$BASE_URL" >/dev/null; then
        echo "✅ Mattermost HTTP reachable"
    else
        echo "❌ Mattermost HTTP not reachable"
        return 1
    fi
}

function check_mattermost_service() {
    if systemctl is-active --quiet mattermost; then
        echo "✅ Mattermost service active"
    else
        echo "❌ Mattermost service inactive"
        return 1
    fi
}

function check_chat_bridge_service() {
    if systemctl is-active --quiet rave-chat-bridge; then
        echo "✅ Chat bridge service active"
    else
        echo "❌ Chat bridge service inactive"
        return 1
    fi
}

function check_baseline_assets() {
    local token_file="/etc/rave/mattermost-bridge/outgoing_token"
    local bot_token_file="/etc/rave/mattermost-bridge/bot_token"
    if [[ -s "$token_file" && -s "$bot_token_file" ]]; then
        echo "✅ Bridge tokens present"
    else
        echo "❌ Bridge tokens missing (baseline setup incomplete)"
        return 1
    fi
}

check_bridge
check_mattermost_http
check_mattermost_service
check_chat_bridge_service
check_baseline_assets
