#!/bin/bash
# VM Service Monitoring Script
# Tests all VM services externally and reports status

echo "=== VM Service Monitoring - $(date) ==="
echo "VM PID: $(pgrep -f qemu-system.*development-vm-with-nats || echo 'VM NOT RUNNING')"
echo

# Test NATS Services
echo "=== NATS Service Tests ==="
echo -n "NATS Client Port (4222): "
if echo | timeout 2 telnet localhost 4222 >/dev/null 2>&1; then
    echo "✓ CONNECTED"
else
    echo "✗ CONNECTION REFUSED/TIMEOUT"
fi

echo -n "NATS Monitoring (8222): "
if timeout 3 curl -s http://localhost:8222/healthz >/dev/null 2>&1; then
    echo "✓ HEALTHY"
else
    if timeout 3 curl -s http://localhost:8222/ >/dev/null 2>&1; then
        echo "⚠ RESPONDING (but not ready)"
    else
        echo "✗ NOT RESPONDING"
    fi
fi

# Test GitLab Service
echo
echo "=== GitLab Service Tests ==="
echo -n "GitLab Web (8081): "
if timeout 3 curl -s -I http://localhost:8081 >/dev/null 2>&1; then
    echo "✓ RESPONDING"
else
    echo "✗ NOT RESPONDING"
fi

echo -n "GitLab Alt Port (8889): "
if timeout 3 curl -s -I http://localhost:8889 >/dev/null 2>&1; then
    echo "✓ RESPONDING"
else
    echo "✗ NOT RESPONDING"
fi

# Test SSH Access
echo
echo "=== SSH Access Test ==="
echo -n "SSH (2224): "
if timeout 5 sshpass -p 'agent' ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -p 2224 root@localhost 'echo SSH_SUCCESS' 2>/dev/null | grep -q SSH_SUCCESS; then
    echo "✓ SSH ACCESS WORKING"
else
    echo "✗ SSH ACCESS FAILED"
fi

echo
echo "=== Port Status ==="
netstat -tulnp | grep -E "(8081|8889|4222|8222|2224)" | while read line; do
    echo "  $line"
done

echo
echo "=== Next Check: $(date -d '+30 seconds') ==="