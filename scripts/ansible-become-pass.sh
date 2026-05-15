#!/usr/bin/env sh
set -eu

if [ -z "${OSWORLD_SUDO_PASSWORD:-}" ]; then
  exit 1
fi

printf '%s\n' "$OSWORLD_SUDO_PASSWORD"

