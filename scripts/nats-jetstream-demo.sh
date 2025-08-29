#!/usr/bin/env bash
# NATS JetStream demonstration and testing script

set -euo pipefail

echo "🌊 NATS JetStream Demo & Testing"
echo "================================="

NATS_SERVER="${NATS_SERVER:-localhost:4222}"
NATS_USER="${NATS_USER:-}"
NATS_PASSWORD="${NATS_PASSWORD:-}"

# Build auth flags
AUTH_FLAGS=""
if [[ -n "$NATS_USER" && -n "$NATS_PASSWORD" ]]; then
    AUTH_FLAGS="--user=$NATS_USER --password=$NATS_PASSWORD"
fi

echo "📡 NATS Server: $NATS_SERVER"
echo "🔐 Authentication: ${NATS_USER:+$NATS_USER}${NATS_USER:+/***}${NATS_USER:-none}"
echo ""

# Check NATS connectivity
echo "🔍 Testing NATS Connection..."
if nats --server="$NATS_SERVER" $AUTH_FLAGS server info > /dev/null 2>&1; then
    echo "✅ NATS server is accessible"
else
    echo "❌ Cannot connect to NATS server"
    echo "💡 Make sure NATS is running and accessible at $NATS_SERVER"
    exit 1
fi

# Show server information
echo ""
echo "📊 NATS Server Information:"
nats --server="$NATS_SERVER" $AUTH_FLAGS server info

# Check JetStream status
echo ""
echo "🌊 JetStream Status:"
if nats --server="$NATS_SERVER" $AUTH_FLAGS stream ls > /dev/null 2>&1; then
    echo "✅ JetStream is enabled and accessible"
    nats --server="$NATS_SERVER" $AUTH_FLAGS stream ls
else
    echo "❌ JetStream is not accessible or not enabled"
    exit 1
fi

# Create a demo stream
STREAM_NAME="demo-stream"
echo ""
echo "🚰 Creating Demo Stream: $STREAM_NAME"

if nats --server="$NATS_SERVER" $AUTH_FLAGS stream create "$STREAM_NAME" \
    --subjects="demo.*" \
    --storage=file \
    --max-msgs=1000 \
    --max-age=1h \
    --replicas=1 > /dev/null 2>&1; then
    echo "✅ Demo stream created successfully"
else
    echo "ℹ️  Demo stream may already exist, continuing..."
fi

# Show stream information
echo ""
echo "📋 Stream Information:"
nats --server="$NATS_SERVER" $AUTH_FLAGS stream info "$STREAM_NAME"

# Publish test messages
echo ""
echo "📤 Publishing Test Messages..."
for i in {1..5}; do
    MESSAGE="Test message $i at $(date)"
    echo "Publishing: $MESSAGE"
    echo "$MESSAGE" | nats --server="$NATS_SERVER" $AUTH_FLAGS pub "demo.test" --stdin
    sleep 0.5
done

# Show updated stream stats
echo ""
echo "📈 Updated Stream Stats:"
nats --server="$NATS_SERVER" $AUTH_FLAGS stream info "$STREAM_NAME" | grep -E "(Messages|Bytes|First|Last)"

# Create a consumer and read messages
CONSUMER_NAME="demo-consumer"
echo ""
echo "📥 Creating Consumer: $CONSUMER_NAME"

if nats --server="$NATS_SERVER" $AUTH_FLAGS consumer create "$STREAM_NAME" "$CONSUMER_NAME" \
    --filter="demo.*" \
    --replay=instant \
    --deliver=all \
    --ack=explicit > /dev/null 2>&1; then
    echo "✅ Consumer created successfully"
else
    echo "ℹ️  Consumer may already exist, continuing..."
fi

# Read messages
echo ""
echo "📖 Reading Messages from Consumer:"
nats --server="$NATS_SERVER" $AUTH_FLAGS consumer next "$STREAM_NAME" "$CONSUMER_NAME" --count=5

# Show JetStream account info
echo ""
echo "💾 JetStream Account Usage:"
nats --server="$NATS_SERVER" $AUTH_FLAGS account info

echo ""
echo "🧹 Cleanup Demo Stream..."
nats --server="$NATS_SERVER" $AUTH_FLAGS stream delete "$STREAM_NAME" --force > /dev/null 2>&1 || true
echo "✅ Demo stream cleaned up"

echo ""
echo "🎉 NATS JetStream Demo Complete!"
echo ""
echo "💡 Usage Examples:"
echo "  • Development (no auth): NATS_SERVER=rave-dev:4222 $0"
echo "  • Production (with auth): NATS_SERVER=rave-prod:4222 NATS_USER=monitoring NATS_PASSWORD=secret $0"
echo ""
echo "📚 JetStream Commands:"
echo "  • List streams: nats stream ls"
echo "  • Create stream: nats stream create my-stream --subjects='my.*'"
echo "  • Publish message: echo 'Hello' | nats pub my.subject --stdin"  
echo "  • Create consumer: nats consumer create my-stream my-consumer"
echo "  • Read messages: nats consumer next my-stream my-consumer"