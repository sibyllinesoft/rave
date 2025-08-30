#!/bin/bash

# Send login sequence to VM via QEMU monitor
echo "Login attempt to RAVE VM..."

# Login as root (no password needed typically in NixOS live systems)
echo "sendkey ret" | nc -w 1 -U /tmp/qemu-p6.sock
sleep 1
echo "type root" | nc -w 1 -U /tmp/qemu-p6.sock  
sleep 1
echo "sendkey ret" | nc -w 1 -U /tmp/qemu-p6.sock
sleep 2

# Check systemctl status
echo "type systemctl status nginx" | nc -w 1 -U /tmp/qemu-p6.sock
sleep 1
echo "sendkey ret" | nc -w 1 -U /tmp/qemu-p6.sock
sleep 3

echo "Commands sent to VM. Check VM console for results."