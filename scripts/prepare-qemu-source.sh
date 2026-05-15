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
  mkdir -p "$SSH_DEB_DIR"
  cat > "$SSH_DEB_DIR/SHA256SUMS" <<'EOF'
36ae97d42dd34f6ae15e31758a6dbad4a4ade898acfd3e3cb9fd9332744d0cee  openssh-client_8.9p1-3ubuntu0.15_amd64.deb
37a796b558f93bd2a0950794f3b477d602f908f239096c06fba10930391dc698  openssh-sftp-server_8.9p1-3ubuntu0.15_amd64.deb
6b4f534348c282f0d77e27ba8d68e505b82fba60fc1296afc492f32ac51b131f  openssh-server_8.9p1-3ubuntu0.15_amd64.deb
e67643b4f7af2e3f908da9140dcd3d3cdcd64dc6b2529bc63a907bf9c881ea8c  ncurses-term_6.3-2ubuntu0.1_all.deb
245ebcce7417b587f06c38dbdc103e445334b93766aaa05594dd5ba09be142f7  ssh-import-id_5.11-0ubuntu1_all.deb
EOF

  local urls=(
    "http://security.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-client_8.9p1-3ubuntu0.15_amd64.deb"
    "http://security.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-sftp-server_8.9p1-3ubuntu0.15_amd64.deb"
    "http://security.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-server_8.9p1-3ubuntu0.15_amd64.deb"
    "http://security.ubuntu.com/ubuntu/pool/main/n/ncurses/ncurses-term_6.3-2ubuntu0.1_all.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/s/ssh-import-id/ssh-import-id_5.11-0ubuntu1_all.deb"
  )

  local url file
  for url in "${urls[@]}"; do
    file="$SSH_DEB_DIR/${url##*/}"
    if [ ! -f "$file" ]; then
      curl --location --fail --retry 3 "$url" -o "$file"
    fi
  done

  (cd "$SSH_DEB_DIR" && sha256sum -c SHA256SUMS)
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
