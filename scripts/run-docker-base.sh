#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-osworld-base-xfce:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-osworld-base-xfce}"
OSWORLD_PORT="${OSWORLD_PORT:-5000}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
TAILSCALE_IP="${TAILSCALE_IP:-100.66.66.45}"

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

docker run -d \
  --name "$CONTAINER_NAME" \
  --shm-size=2g \
  -p "$OSWORLD_PORT:5000" \
  -p "$VNC_PORT:5900" \
  -p "$NOVNC_PORT:6080" \
  "$IMAGE_TAG" >/dev/null

printf 'Container: %s\n' "$CONTAINER_NAME"
printf 'OSWorld server: http://%s:%s\n' "$TAILSCALE_IP" "$OSWORLD_PORT"
printf 'noVNC desktop: http://%s:%s/vnc.html\n' "$TAILSCALE_IP" "$NOVNC_PORT"
printf 'VNC: %s:%s\n' "$TAILSCALE_IP" "$VNC_PORT"
