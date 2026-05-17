#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_IMAGE="${BASE_IMAGE:-osworld-base-xfce:latest}"
BUILD_TAG="${BUILD_TAG:-osworld-xfce:build}"
IMAGE_TAG="${IMAGE_TAG:-osworld-xfce:latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
OSWORLD_USER="${OSWORLD_USER:-user}"
FLATTEN_IMAGE="${FLATTEN_IMAGE:-0}"

for bin in docker; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$bin" >&2
    exit 1
  }
done

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  printf 'Base image not found: %s\n' "$BASE_IMAGE" >&2
  printf 'Build it first with scripts/build-docker-base.sh or set BASE_IMAGE.\n' >&2
  exit 1
fi

"$ROOT_DIR/scripts/download-wps-fonts.sh"

PROVISION_CACHE_BUST="${PROVISION_CACHE_BUST:-$(
  {
    find "$ROOT_DIR/ansible" -type f -print0
    if [ -d "$ROOT_DIR/downloads/provision" ]; then
      find "$ROOT_DIR/downloads/provision" -type f -print0
    fi
    if [ -d "$ROOT_DIR/downloads/osworld_server" ]; then
      find "$ROOT_DIR/downloads/osworld_server" -type f -print0
    fi
    printf '%s\0' \
      "$ROOT_DIR/ansible.cfg" \
      "$ROOT_DIR/downloads/wps_fonts/wps_symbol_fonts.zip"
  } | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}'
)}"

printf 'Building Docker update image %s from %s\n' "$BUILD_TAG" "$BASE_IMAGE"
DOCKER_BUILDKIT=1 docker build \
  --platform "$PLATFORM" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "OSWORLD_USER=$OSWORLD_USER" \
  --build-arg "PROVISION_CACHE_BUST=$PROVISION_CACHE_BUST" \
  -t "$BUILD_TAG" \
  -f "$ROOT_DIR/docker/update/Dockerfile" \
  "$ROOT_DIR"

if [ "$FLATTEN_IMAGE" = "1" ]; then
  container_id=""
  cleanup_container() {
    if [ -n "$container_id" ]; then
      docker rm "$container_id" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_container EXIT

  printf 'Flattening %s into final image %s\n' "$BUILD_TAG" "$IMAGE_TAG"
  container_id="$(docker create "$BUILD_TAG")"
  docker export "$container_id" | docker import \
    --change 'ENV DEBIAN_FRONTEND=noninteractive container=docker DISPLAY=:0 XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 SCREEN_GEOMETRY=1920x1080x24 OSWORLD_USER=user OSWORLD_SERVER_HOST=0.0.0.0 OSWORLD_SERVER_PORT=5000 LANG=C.UTF-8 LC_ALL=C.UTF-8' \
    --change 'EXPOSE 5000' \
    --change 'EXPOSE 5900' \
    --change 'EXPOSE 6080' \
    --change 'ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/osworld-docker-entrypoint"]' \
    --change 'CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]' \
    - "$IMAGE_TAG" >/dev/null
  docker rm "$container_id" >/dev/null
  container_id=""
else
  docker tag "$BUILD_TAG" "$IMAGE_TAG"
fi

printf 'Built Docker image: %s\n' "$IMAGE_TAG"
