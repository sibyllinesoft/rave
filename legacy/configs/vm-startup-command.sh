qemu-system-x86_64 \
  -drive file=rave-dev.qcow2,format=qcow2 \
  -m 4G \
  -smp 2 \
  -netdev user,id=net0,hostfwd=tcp::8081-:80,hostfwd=tcp::8889-:8080,hostfwd=tcp::2224-:22,hostfwd=tcp::8443-:443 \
  -device virtio-net-pci,netdev=net0 \
  -nographic
