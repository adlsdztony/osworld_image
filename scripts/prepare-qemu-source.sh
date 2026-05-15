#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_QCOW2="${1:-$ROOT_DIR/downloads/qemu/Ubuntu.qcow2}"
PREPARED_QCOW2="${2:-$ROOT_DIR/downloads/qemu/Ubuntu-ssh.qcow2}"
VARS_FILE="$ROOT_DIR/packer/zz-qemu-prepared.auto.pkrvars.hcl"
SSH_DEB_DIR="$ROOT_DIR/downloads/qemu/ssh-debs"

for bin in apt-get dpkg-deb qemu-img virt-customize sha256sum; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$bin" >&2
    exit 1
  }
done

if [ ! -f "$SOURCE_QCOW2" ]; then
  printf 'QEMU source qcow2 not found: %s\n' "$SOURCE_QCOW2" >&2
  exit 1
fi

mkdir -p "$(dirname "$PREPARED_QCOW2")"
rm -f "$PREPARED_QCOW2"

prepare_libguestfs_kernel() {
  local kernel_version="${LIBGUESTFS_KERNEL_VERSION:-$(uname -r)}"
  local module_dir="/lib/modules/$kernel_version"
  local kernel_file="/boot/vmlinuz-$kernel_version"

  if [ -r "$kernel_file" ]; then
    return
  fi

  local kernel_cache="$ROOT_DIR/downloads/libguestfs-kernel/$kernel_version"
  local extracted_kernel="$kernel_cache/vmlinuz-$kernel_version"
  mkdir -p "$kernel_cache"

  if [ ! -r "$extracted_kernel" ]; then
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    (
      cd "$tmp_dir"
      apt-get download "linux-image-$kernel_version"
      dpkg-deb -x "linux-image-$kernel_version"_*.deb "$tmp_dir/extract"
      cp "$tmp_dir/extract/boot/vmlinuz-$kernel_version" "$extracted_kernel"
    )
    rm -rf "$tmp_dir"
  fi

  if [ ! -d "$module_dir" ]; then
    printf 'Kernel module directory not found: %s\n' "$module_dir" >&2
    exit 1
  fi

  export SUPERMIN_KERNEL="$extracted_kernel"
  export SUPERMIN_MODULES="$module_dir"
  export SUPERMIN_KERNEL_VERSION="$kernel_version"
}

download_ssh_debs() {
  SSH_DEB_DIR="$SSH_DEB_DIR" "$ROOT_DIR/scripts/download-qemu-ssh-debs.sh"
}

prepare_libguestfs_kernel
download_ssh_debs
qemu-img convert -O qcow2 "$SOURCE_QCOW2" "$PREPARED_QCOW2"

virt-customize \
  -a "$PREPARED_QCOW2" \
  --copy-in "$SSH_DEB_DIR:/tmp" \
  --run-command 'DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/ssh-debs/*.deb' \
  --run-command 'install -d -m 0755 /etc/ssh/sshd_config.d' \
  --write '/etc/ssh/sshd_config.d/99-osworld-password.conf:PasswordAuthentication yes
PubkeyAuthentication yes
' \
  --run-command 'systemctl enable ssh'

prepared_sha256="$(sha256sum "$PREPARED_QCOW2" | awk '{print $1}')"

cat > "$VARS_FILE" <<EOF
qemu_source_qcow2 = "$PREPARED_QCOW2"
qemu_source_qcow2_checksum = "sha256:$prepared_sha256"
EOF

printf 'Prepared QEMU source: %s\n' "$PREPARED_QCOW2"
printf 'Prepared QEMU sha256: %s\n' "$prepared_sha256"
printf 'Wrote ignored Packer vars: %s\n' "$VARS_FILE"
