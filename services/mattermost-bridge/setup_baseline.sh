#!/usr/bin/env bash
# Configure baseline Mattermost resources (admin user, team, channel, slash command, tokens)
set -euo pipefail

PATH=/run/current-system/sw/bin:$PATH
CURL=/run/current-system/sw/bin/curl
JQ=/run/current-system/sw/bin/jq

if ! command -v "$CURL" >/dev/null 2>&1 || ! command -v "$JQ" >/dev/null 2>&1; then
    echo "curl and jq are required for Mattermost baseline setup" >&2
    exit 1
fi

BASE_URL="http://127.0.0.1:8065"
API_URL="$BASE_URL/api/v4"
COOKIE_DIR=$(mktemp -d)
COOKIE_FILE="$COOKIE_DIR/cookies.txt"
HEADERS_FILE="$COOKIE_DIR/headers.txt"
BODY_FILE="$COOKIE_DIR/body.json"
trap 'rm -rf "$COOKIE_DIR"' EXIT

: "${CHAT_BRIDGE_ADMIN_USERNAME:?CHAT_BRIDGE_ADMIN_USERNAME not set}"
: "${CHAT_BRIDGE_ADMIN_EMAIL:?CHAT_BRIDGE_ADMIN_EMAIL not set}"
: "${CHAT_BRIDGE_ADMIN_PASSWORD:?CHAT_BRIDGE_ADMIN_PASSWORD not set}"
: "${CHAT_BRIDGE_TOKEN_FILE:?CHAT_BRIDGE_TOKEN_FILE not set}"
: "${CHAT_BRIDGE_BOT_TOKEN_FILE:?CHAT_BRIDGE_BOT_TOKEN_FILE not set}"

TEAM_NAME=${CHAT_BRIDGE_TEAM:-rave}
TEAM_DISPLAY=${CHAT_BRIDGE_TEAM_DISPLAY:-"RAVE Ops"}
CHANNEL_NAME=${CHAT_BRIDGE_CHANNEL:-agent-control}
CHANNEL_DISPLAY=${CHAT_BRIDGE_CHANNEL_DISPLAY:-"Agent Control"}
COMMAND_TRIGGER=${CHAT_BRIDGE_TRIGGER:-rave}
COMMAND_DESCRIPTION=${CHAT_BRIDGE_COMMAND_DESCRIPTION:-"RAVE agent control commands"}
BRIDGE_URL=${CHAT_BRIDGE_URL:-"http://127.0.0.1:9100/webhook"}
COMMAND_HINT=${CHAT_BRIDGE_COMMAND_HINT:-"[command]"}
TOKEN_DESCRIPTION=${CHAT_BRIDGE_TOKEN_DESCRIPTION:-"RAVE Chat Bridge"}

wait_for_service() {
    for attempt in {1..60}; do
        if $CURL -sSf "$API_URL/system/ping" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "Mattermost API did not become ready" >&2
    return 1
}

ensure_admin_user() {
    local login_status payload create_status

    login_status=$($CURL -sk -o /dev/null -w '%{http_code}' \
        -H 'Content-Type: application/json' \
        -d "$(
            $JQ -n --arg login "$CHAT_BRIDGE_ADMIN_EMAIL" --arg pass "$CHAT_BRIDGE_ADMIN_PASSWORD" '{login_id: $login, password: $pass}'
        )" \
        "$API_URL/users/login")

    if [ "$login_status" -eq 200 ]; then
        return 0
    fi

    payload=$($JQ -n \
        --arg email "$CHAT_BRIDGE_ADMIN_EMAIL" \
        --arg username "$CHAT_BRIDGE_ADMIN_USERNAME" \
        --arg password "$CHAT_BRIDGE_ADMIN_PASSWORD" \
        '{email: $email, username: $username, password: $password, first_name: $username}')

    create_status=$($CURL -sk -o "$BODY_FILE" -w '%{http_code}' \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        "$API_URL/users")

    if [ "$create_status" -ne 201 ]; then
        local error_msg
        if ! error_msg=$($JQ -r '.message // .error // empty' "$BODY_FILE" 2>/dev/null); then
            error_msg=$(tr -d '\n' < "$BODY_FILE" 2>/dev/null || printf '')
        fi
        printf 'Failed to ensure Mattermost admin (%s): %s\n' \
            "$create_status" "$error_msg" >&2
        return 1
    fi

    return 0
}

login_admin() {
    local status
    status=$($CURL -sk -o "$BODY_FILE" -D "$HEADERS_FILE" -c "$COOKIE_FILE" \
        -H 'Content-Type: application/json' \
        -d "{\"login_id\":\"$CHAT_BRIDGE_ADMIN_USERNAME\",\"password\":\"$CHAT_BRIDGE_ADMIN_PASSWORD\"}" \
        "$API_URL/users/login" -w '%{http_code}')

    if [ "$status" -ne 200 ]; then
        return 1
    fi

    SESSION_TOKEN=$(grep -i '^Token:' "$HEADERS_FILE" | awk '{print $2}' | tr -d '\r')
    ADMIN_USER_ID=$($JQ -r '.id' "$BODY_FILE")
    if [ -z "${SESSION_TOKEN:-}" ] || [ -z "${ADMIN_USER_ID:-}" ]; then
        return 1
    fi
    return 0
}

api_get() {
    $CURL -sk -b "$COOKIE_FILE" -H "Authorization: Bearer $SESSION_TOKEN" "$1"
}

api_post() {
    $CURL -sk -b "$COOKIE_FILE" -H "Authorization: Bearer $SESSION_TOKEN" -H 'Content-Type: application/json' -d "$2" "$1"
}

api_post_status() {
    $CURL -sk -o "$BODY_FILE" -w '%{http_code}' -b "$COOKIE_FILE" -H "Authorization: Bearer $SESSION_TOKEN" -H 'Content-Type: application/json' -d "$2" "$1"
}

ensure_team() {
    TEAM_ID=$(api_get "$API_URL/teams/name/$TEAM_NAME" | $JQ -r '.id // empty')
    if [ -z "$TEAM_ID" ]; then
        TEAM_ID=$(api_post "$API_URL/teams" "{\"name\":\"$TEAM_NAME\",\"display_name\":\"$TEAM_DISPLAY\",\"type\":\"O\"}" | $JQ -r '.id')
    fi
    # Ensure admin is member
    api_post "$API_URL/teams/$TEAM_ID/members" "{\"team_id\":\"$TEAM_ID\",\"user_id\":\"$ADMIN_USER_ID\"}" >/dev/null 2>&1 || true
}

ensure_channel() {
    CHANNEL_ID=$(api_get "$API_URL/teams/$TEAM_ID/channels/name/$CHANNEL_NAME" | $JQ -r '.id // empty')
    if [ -z "$CHANNEL_ID" ]; then
        CHANNEL_ID=$(api_post "$API_URL/channels" "{\"team_id\":\"$TEAM_ID\",\"name\":\"$CHANNEL_NAME\",\"display_name\":\"$CHANNEL_DISPLAY\",\"type\":\"O\"}" | $JQ -r '.id')
    fi
    api_post "$API_URL/channels/$CHANNEL_ID/members" "{\"user_id\":\"$ADMIN_USER_ID\"}" >/dev/null 2>&1 || true
}

ensure_command() {
    local commands command existing
    commands=$(api_get "$API_URL/commands?team_id=$TEAM_ID")
    existing=$(echo "$commands" | $JQ -r ".[] | select(.trigger == \"$COMMAND_TRIGGER\") | .id" | head -n1)
    if [ -n "$existing" ]; then
        COMMAND_ID="$existing"
        COMMAND_TOKEN=$(api_get "$API_URL/commands/$COMMAND_ID" | $JQ -r '.token // empty')
    else
        local payload status
        payload="{\"team_id\":\"$TEAM_ID\",\"method\":\"P\",\"trigger\":\"$COMMAND_TRIGGER\",\"display_name\":\"RAVE Chat Bridge\",\"description\":\"$COMMAND_DESCRIPTION\",\"auto_complete\":true,\"auto_complete_desc\":\"$COMMAND_DESCRIPTION\",\"auto_complete_hint\":\"$COMMAND_HINT\",\"url\":\"$BRIDGE_URL\"}"
        status=$(api_post_status "$API_URL/commands" "$payload")
        if [ "$status" -ne 201 ] && [ "$status" -ne 200 ]; then
            echo "Failed to create slash command ($status)" >&2
            COMMAND_TOKEN=""
            return 1
        fi
        COMMAND_TOKEN=$($JQ -r '.token // empty' "$BODY_FILE")
    fi
    if [ -z "$COMMAND_TOKEN" ]; then
        echo "Unable to determine slash command token" >&2
        return 1
    fi
    printf '%s' "$COMMAND_TOKEN" > "$CHAT_BRIDGE_TOKEN_FILE"
    chown rave-bridge:rave-bridge "$CHAT_BRIDGE_TOKEN_FILE"
    chmod 600 "$CHAT_BRIDGE_TOKEN_FILE"
}

ensure_bot_token() {
    if [ -s "$CHAT_BRIDGE_BOT_TOKEN_FILE" ]; then
        return 0
    fi
    local tokens existing
    tokens=$(api_get "$API_URL/users/$ADMIN_USER_ID/tokens")
    existing=$(echo "$tokens" | $JQ -r ".[] | select(.description == \"$TOKEN_DESCRIPTION\") | .token" | head -n1)
    if [ -z "$existing" ]; then
        existing=$(api_post "$API_URL/users/$ADMIN_USER_ID/tokens" "{\"description\":\"$TOKEN_DESCRIPTION\"}" | $JQ -r '.token')
    fi
    printf '%s' "$existing" > "$CHAT_BRIDGE_BOT_TOKEN_FILE"
    chown rave-bridge:rave-bridge "$CHAT_BRIDGE_BOT_TOKEN_FILE"
    chmod 600 "$CHAT_BRIDGE_BOT_TOKEN_FILE"
}

wait_for_service
ensure_admin_user
if ! login_admin; then
    echo "Unable to login to Mattermost with provided admin credentials" >&2
    exit 1
fi
ensure_team
ensure_channel
ensure_command
ensure_bot_token
