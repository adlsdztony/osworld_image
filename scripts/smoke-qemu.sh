#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="${1:-}"
SSH_USER="${2:-user}"
SSH_PASSWORD="${3:-${OSWORLD_SSH_PASSWORD:-}}"
OSWORLD_USER="${4:-$SSH_USER}"
SSH_PORT="${SSH_PORT:-2222}"
PID_FILE="$ROOT_DIR/build/qemu-smoke-${SSH_PORT}.pid"

if [ -z "$IMAGE_PATH" ]; then
  printf 'Usage: scripts/smoke-qemu.sh <qcow2_path> [ssh_user] [ssh_password] [osworld_user]\n' >&2
  exit 2
fi

if [ -z "$SSH_PASSWORD" ]; then
  printf 'Provide the VM SSH password as argument 3 or OSWORLD_SSH_PASSWORD.\n' >&2
  exit 2
fi

for bin in qemu-system-x86_64 ssh scp setsid; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command for QEMU smoke test: %s\n' "$bin" >&2
    exit 1
  }
done

mkdir -p "$ROOT_DIR/build"
rm -f "$PID_FILE"
ASKPASS_DIR="$(mktemp -d)"
ASKPASS="$ASKPASS_DIR/askpass.sh"
cat > "$ASKPASS" <<EOF
#!/usr/bin/env sh
printf '%s\n' '$SSH_PASSWORD'
EOF
chmod 0700 "$ASKPASS"

ssh_with_password() {
  SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=osworld:0 setsid ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=2 \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "$@"
}

scp_with_password() {
  SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY=osworld:0 setsid scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "$@"
}

cleanup() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
  fi
  rm -rf "$ASKPASS_DIR"
}
trap cleanup EXIT

qemu-system-x86_64 \
  -daemonize \
  -pidfile "$PID_FILE" \
  -m 8192 \
  -smp 4 \
  -enable-kvm \
  -cpu host \
  -drive "file=$IMAGE_PATH,if=virtio,format=qcow2" \
  -netdev "user,id=n1,hostfwd=tcp::$SSH_PORT-:22" \
  -device virtio-net-pci,netdev=n1 \
  -device virtio-vga \
  -display none

for _ in $(seq 1 120); do
  if ssh_with_password -p "$SSH_PORT" "$SSH_USER@127.0.0.1" true >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

scp_with_password -P "$SSH_PORT" "$ROOT_DIR/tests/smoke.sh" "$SSH_USER@127.0.0.1:/tmp/osworld-smoke.sh"

ssh_with_password -p "$SSH_PORT" "$SSH_USER@127.0.0.1" "sudo -S OSWORLD_USER='$OSWORLD_USER' bash /tmp/osworld-smoke.sh" <<<"$SSH_PASSWORD"

ssh_with_password -p "$SSH_PORT" "$SSH_USER@127.0.0.1" "sudo -S shutdown -h now" <<<"$SSH_PASSWORD" >/dev/null 2>&1 || true
