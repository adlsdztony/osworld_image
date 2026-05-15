#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$ROOT_DIR/downloads}"
SSH_DEB_DIR="${SSH_DEB_DIR:-$DOWNLOAD_DIR/qemu/ssh-debs}"
DOWNLOAD_MAX_TIME="${DOWNLOAD_MAX_TIME:-300}"

for bin in curl sha256sum; do
  command -v "$bin" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$bin" >&2
    exit 1
  }
done

mkdir -p "$SSH_DEB_DIR"

cat > "$SSH_DEB_DIR/SHA256SUMS" <<'EOF'
36ae97d42dd34f6ae15e31758a6dbad4a4ade898acfd3e3cb9fd9332744d0cee  openssh-client_8.9p1-3ubuntu0.15_amd64.deb
37a796b558f93bd2a0950794f3b477d602f908f239096c06fba10930391dc698  openssh-sftp-server_8.9p1-3ubuntu0.15_amd64.deb
6b4f534348c282f0d77e27ba8d68e505b82fba60fc1296afc492f32ac51b131f  openssh-server_8.9p1-3ubuntu0.15_amd64.deb
e67643b4f7af2e3f908da9140dcd3d3cdcd64dc6b2529bc63a907bf9c881ea8c  ncurses-term_6.3-2ubuntu0.1_all.deb
245ebcce7417b587f06c38dbdc103e445334b93766aaa05594dd5ba09be142f7  ssh-import-id_5.11-0ubuntu1_all.deb
EOF

verify_sha256() {
  local checksum="$1"
  local path="$2"
  local expected="${checksum#sha256:}"
  local actual

  [ -f "$path" ] || return 1
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [ "$actual" = "$expected" ]
}

download_checked() {
  local url="$1"
  local checksum="$2"
  local dest="$3"
  local tmp="$dest.part"
  local curl_args=(
    --location
    --fail
    --retry 3
    --connect-timeout 20
    --max-time "$DOWNLOAD_MAX_TIME"
  )

  if verify_sha256 "$checksum" "$dest"; then
    printf 'Using existing %s\n' "$dest"
    return
  fi

  rm -f "$tmp"
  printf 'Downloading %s\n' "$dest"
  curl "${curl_args[@]}" "$url" -o "$tmp"

  if ! verify_sha256 "$checksum" "$tmp"; then
    actual="$(sha256sum "$tmp" | awk '{print $1}')"
    printf 'Checksum mismatch for %s: expected %s, got %s\n' "$dest" "${checksum#sha256:}" "$actual" >&2
    rm -f "$tmp"
    exit 1
  fi

  mv "$tmp" "$dest"
}

download_checked \
  "http://security.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-client_8.9p1-3ubuntu0.15_amd64.deb" \
  "sha256:36ae97d42dd34f6ae15e31758a6dbad4a4ade898acfd3e3cb9fd9332744d0cee" \
  "$SSH_DEB_DIR/openssh-client_8.9p1-3ubuntu0.15_amd64.deb"

download_checked \
  "http://security.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-sftp-server_8.9p1-3ubuntu0.15_amd64.deb" \
  "sha256:37a796b558f93bd2a0950794f3b477d602f908f239096c06fba10930391dc698" \
  "$SSH_DEB_DIR/openssh-sftp-server_8.9p1-3ubuntu0.15_amd64.deb"

download_checked \
  "http://security.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-server_8.9p1-3ubuntu0.15_amd64.deb" \
  "sha256:6b4f534348c282f0d77e27ba8d68e505b82fba60fc1296afc492f32ac51b131f" \
  "$SSH_DEB_DIR/openssh-server_8.9p1-3ubuntu0.15_amd64.deb"

download_checked \
  "http://security.ubuntu.com/ubuntu/pool/main/n/ncurses/ncurses-term_6.3-2ubuntu0.1_all.deb" \
  "sha256:e67643b4f7af2e3f908da9140dcd3d3cdcd64dc6b2529bc63a907bf9c881ea8c" \
  "$SSH_DEB_DIR/ncurses-term_6.3-2ubuntu0.1_all.deb"

download_checked \
  "http://archive.ubuntu.com/ubuntu/pool/main/s/ssh-import-id/ssh-import-id_5.11-0ubuntu1_all.deb" \
  "sha256:245ebcce7417b587f06c38dbdc103e445334b93766aaa05594dd5ba09be142f7" \
  "$SSH_DEB_DIR/ssh-import-id_5.11-0ubuntu1_all.deb"

(cd "$SSH_DEB_DIR" && sha256sum -c SHA256SUMS)
