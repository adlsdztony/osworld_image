#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-$ROOT_DIR/downloads}"
WPS_FONT_URL="${WPS_FONT_URL:-https://gitee.com/owlman/wps_fonts/repository/archive/89beda2cf241c4524a5926bf13c92bdc8a73e9d0.zip}"
WPS_SYMBOL_SHA256="${WPS_SYMBOL_SHA256:-01e965dc81167ae816b3bbd7076986bf2fb64a2c456a077df677f8882dabcbe2}"
WPS_DIR="$DOWNLOAD_DIR/wps_fonts"
WRAPPER_ZIP="$WPS_DIR/wps_fonts-89beda2cf241c4524a5926bf13c92bdc8a73e9d0.zip"
SYMBOL_ZIP="$WPS_DIR/wps_symbol_fonts.zip"

mkdir -p "$WPS_DIR"

verify_symbol_zip() {
  local path="$1"
  [ -f "$path" ] || return 1
  local actual
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [ "$actual" = "$WPS_SYMBOL_SHA256" ]
}

if verify_symbol_zip "$SYMBOL_ZIP"; then
  printf 'Using existing %s\n' "$SYMBOL_ZIP"
  exit 0
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

curl \
  --location \
  --fail \
  --retry 3 \
  --connect-timeout 20 \
  --max-time 300 \
  "$WPS_FONT_URL" \
  -o "$WRAPPER_ZIP"

unzip -q "$WRAPPER_ZIP" -d "$tmp_dir"
found_zip="$(find "$tmp_dir" -type f -name 'wps_symbol_fonts.zip' | sort | head -n 1)"

if [ -z "$found_zip" ]; then
  printf 'No wps_symbol_fonts.zip found in %s\n' "$WRAPPER_ZIP" >&2
  exit 1
fi

cp "$found_zip" "$SYMBOL_ZIP"

if ! verify_symbol_zip "$SYMBOL_ZIP"; then
  actual="$(sha256sum "$SYMBOL_ZIP" | awk '{print $1}')"
  printf 'WPS symbol font checksum expected %s, got %s\n' "$WPS_SYMBOL_SHA256" "$actual" >&2
  exit 1
fi

printf 'WPS symbol fonts: %s\n' "$SYMBOL_ZIP"
