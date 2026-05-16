#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$ROOT_DIR/downloads}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"

VMWARE_URL="${VMWARE_URL:-https://huggingface.co/datasets/xlangai/ubuntu_osworld/resolve/main/Ubuntu-x86.zip}"
QEMU_URL="${QEMU_URL:-https://huggingface.co/datasets/xlangai/ubuntu_osworld/resolve/main/Ubuntu.qcow2.zip}"
WINDOWS_QEMU_URL="${WINDOWS_QEMU_URL:-https://huggingface.co/datasets/xlangai/windows_osworld/resolve/main/Windows-10-x64.qcow2.zip}"

mkdir -p "$DOWNLOAD_DIR/vmware" "$DOWNLOAD_DIR/qemu" "$DOWNLOAD_DIR/windows" "$BUILD_DIR"

download_once() {
  local url="$1"
  local dest="$2"
  if [ -f "$dest" ]; then
    printf 'Using existing %s\n' "$dest"
    return
  fi
  curl -L --fail --retry 3 --continue-at - "$url" -o "$dest"
}

download_once "$VMWARE_URL" "$DOWNLOAD_DIR/vmware/Ubuntu-x86.zip"
download_once "$QEMU_URL" "$DOWNLOAD_DIR/qemu/Ubuntu.qcow2.zip"
download_once "$WINDOWS_QEMU_URL" "$DOWNLOAD_DIR/windows/Windows-10-x64.qcow2.zip"
"$ROOT_DIR/scripts/download-wps-fonts.sh"

unzip -o "$DOWNLOAD_DIR/vmware/Ubuntu-x86.zip" -d "$DOWNLOAD_DIR/vmware"
unzip -o "$DOWNLOAD_DIR/qemu/Ubuntu.qcow2.zip" -d "$DOWNLOAD_DIR/qemu"
unzip -o "$DOWNLOAD_DIR/windows/Windows-10-x64.qcow2.zip" -d "$DOWNLOAD_DIR/windows"

unzip -l "$DOWNLOAD_DIR/vmware/Ubuntu-x86.zip" > "$BUILD_DIR/vmware-archive-contents.txt"
unzip -l "$DOWNLOAD_DIR/qemu/Ubuntu.qcow2.zip" > "$BUILD_DIR/qemu-archive-contents.txt"
unzip -l "$DOWNLOAD_DIR/windows/Windows-10-x64.qcow2.zip" > "$BUILD_DIR/windows-qemu-archive-contents.txt"

vmx_path="$(find "$DOWNLOAD_DIR/vmware" -type f -name '*.vmx' | sort | head -n 1)"
qcow2_path="$(find "$DOWNLOAD_DIR/qemu" -type f -name '*.qcow2' | sort | head -n 1)"
windows_qcow2_path="$(find "$DOWNLOAD_DIR/windows" -type f -name '*.qcow2' | sort | head -n 1)"

if [ -z "$vmx_path" ]; then
  printf 'No .vmx file found under %s\n' "$DOWNLOAD_DIR/vmware" >&2
  exit 1
fi

if [ -z "$qcow2_path" ]; then
  printf 'No .qcow2 file found under %s\n' "$DOWNLOAD_DIR/qemu" >&2
  exit 1
fi

if [ -z "$windows_qcow2_path" ]; then
  printf 'No Windows .qcow2 file found under %s\n' "$DOWNLOAD_DIR/windows" >&2
  exit 1
fi

qcow2_sha256="$(sha256sum "$qcow2_path" | awk '{print $1}')"
windows_qcow2_sha256="$(sha256sum "$windows_qcow2_path" | awk '{print $1}')"

cat > "$ROOT_DIR/packer/base-images.auto.pkrvars.hcl" <<EOF
vmware_source_vmx = "$vmx_path"
qemu_source_qcow2 = "$qcow2_path"
qemu_source_qcow2_checksum = "sha256:$qcow2_sha256"
windows_source_qcow2 = "$windows_qcow2_path"
windows_source_qcow2_checksum = "sha256:$windows_qcow2_sha256"
EOF

printf 'VMware VMX: %s\n' "$vmx_path"
printf 'QEMU qcow2: %s\n' "$qcow2_path"
printf 'QEMU sha256: %s\n' "$qcow2_sha256"
printf 'Windows QEMU qcow2: %s\n' "$windows_qcow2_path"
printf 'Windows QEMU sha256: %s\n' "$windows_qcow2_sha256"
printf 'Wrote ignored Packer vars: %s\n' "$ROOT_DIR/packer/base-images.auto.pkrvars.hcl"
