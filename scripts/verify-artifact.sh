#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  scripts/verify-artifact.sh local [osworld_user]
  scripts/verify-artifact.sh ssh <host> <ssh_user> [port] [osworld_user]
  scripts/verify-artifact.sh qemu <qcow2_path> [ssh_user] [ssh_password] [osworld_user]
  scripts/verify-artifact.sh aws <ami_id> [osworld_user]
EOF
}

mode="${1:-}"
case "$mode" in
  local)
    osworld_user="${2:-user}"
    OSWORLD_USER="$osworld_user" bash "$ROOT_DIR/tests/smoke.sh"
    ;;
  ssh)
    host="${2:-}"
    ssh_user="${3:-}"
    port="${4:-22}"
    osworld_user="${5:-user}"
    if [ -z "$host" ] || [ -z "$ssh_user" ]; then
      usage
      exit 2
    fi
    scp -P "$port" "$ROOT_DIR/tests/smoke.sh" "$ssh_user@$host:/tmp/osworld-smoke.sh"
    ssh -p "$port" "$ssh_user@$host" "sudo OSWORLD_USER='$osworld_user' bash /tmp/osworld-smoke.sh"
    ;;
  qemu)
    shift
    exec "$ROOT_DIR/scripts/smoke-qemu.sh" "$@"
    ;;
  aws)
    shift
    exec "$ROOT_DIR/scripts/smoke-aws.sh" "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
