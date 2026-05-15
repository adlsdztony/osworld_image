#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_QCOW2="${SOURCE_QCOW2:-$ROOT_DIR/downloads/qemu/Ubuntu.qcow2}"
ROOT_PARTITION="${ROOT_PARTITION:-/dev/sda3}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/docker-base}"
ROOTFS_TAR="${ROOTFS_TAR:-$BUILD_DIR/rootfs.tar}"
EXPORT_QCOW2="${EXPORT_QCOW2:-$BUILD_DIR/rootfs-export-source.qcow2}"
RAW_TAG="${RAW_TAG:-osworld-rootfs-raw:latest}"
BUILD_TAG="${BUILD_TAG:-osworld-base-xfce:build}"
IMAGE_TAG="${IMAGE_TAG:-osworld-base-xfce:latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
STAMP_FILE="$BUILD_DIR/rootfs.stamp"
RAW_STAMP_FILE="$BUILD_DIR/raw-image.stamp"

for bin in docker guestfish qemu-img stat; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$bin" >&2
    exit 1
  }
done

if [ ! -f "$SOURCE_QCOW2" ]; then
  printf 'Source qcow2 not found: %s\n' "$SOURCE_QCOW2" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

source_stamp="$(realpath "$SOURCE_QCOW2") $ROOT_PARTITION $(stat -c '%s %Y' "$SOURCE_QCOW2")"
if [ "${FORCE_EXPORT:-0}" = "1" ] || [ ! -s "$ROOTFS_TAR" ] || [ ! -f "$STAMP_FILE" ] || [ "$(cat "$STAMP_FILE")" != "$source_stamp" ]; then
  tmp_tar="$ROOTFS_TAR.tmp"
  rm -f "$tmp_tar" "$EXPORT_QCOW2"
  printf 'Creating writable qcow2 overlay for fsck and export: %s\n' "$EXPORT_QCOW2"
  qemu-img create -f qcow2 -F qcow2 -b "$(realpath "$SOURCE_QCOW2")" "$EXPORT_QCOW2" >/dev/null
  printf 'Exporting %s %s to %s\n' "$EXPORT_QCOW2" "$ROOT_PARTITION" "$ROOTFS_TAR"
  guestfish -a "$EXPORT_QCOW2" <<EOF
run
e2fsck-f $ROOT_PARTITION
mount $ROOT_PARTITION /
rm-f /swapfile
rm-f /etc/resolv.conf
write /etc/resolv.conf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n"
rm-f /etc/machine-id
write /etc/machine-id ""
rm-f /var/lib/dbus/machine-id
rm-rf /tmp
mkdir /tmp
chmod 1023 /tmp
tar-out / $tmp_tar
EOF
  mv "$tmp_tar" "$ROOTFS_TAR"
  printf '%s\n' "$source_stamp" > "$STAMP_FILE"
else
  printf 'Reusing exported rootfs: %s\n' "$ROOTFS_TAR"
fi

if [ "${FORCE_IMPORT:-0}" = "1" ] || ! docker image inspect "$RAW_TAG" >/dev/null 2>&1 || [ ! -f "$RAW_STAMP_FILE" ] || [ "$(cat "$RAW_STAMP_FILE")" != "$source_stamp" ]; then
  printf 'Importing raw rootfs image as %s\n' "$RAW_TAG"
  docker import "$ROOTFS_TAR" "$RAW_TAG" >/dev/null
  printf '%s\n' "$source_stamp" > "$RAW_STAMP_FILE"
else
  printf 'Reusing raw Docker image: %s\n' "$RAW_TAG"
fi

printf 'Building temporary Docker base image %s from %s\n' "$BUILD_TAG" "$RAW_TAG"
docker build \
  --platform "$PLATFORM" \
  --build-arg "BASE_IMAGE=$RAW_TAG" \
  -t "$BUILD_TAG" \
  -f "$ROOT_DIR/docker/base/Dockerfile" \
  "$ROOT_DIR/docker/base"

if [ "${FLATTEN_IMAGE:-1}" = "1" ]; then
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
