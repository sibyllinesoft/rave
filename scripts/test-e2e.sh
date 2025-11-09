#!/usr/bin/env bash
# Run CLI unit tests plus the VM integration suite.
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="development"
KEEP_VM="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --keep-vm)
      KEEP_VM="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
python3 -m unittest \
  tests.python.test_vm_manager \
  tests.python.test_platform_utils \
  tests.python.test_secrets_flow \
  tests.python.test_cli_secrets
if [[ "$KEEP_VM" == "true" ]]; then
  python3 test_vm_integration.py --profile "$PROFILE" --keep-vm
else
  python3 test_vm_integration.py --profile "$PROFILE"
fi
