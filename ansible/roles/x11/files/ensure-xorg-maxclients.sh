#!/usr/bin/env bash
set -euo pipefail

target="${1:-/etc/X11/xorg.conf}"
mkdir -p "$(dirname "$target")"
touch "$target"
tmp="$(mktemp)"

awk '
BEGIN {
  in_serverflags = 0
  found_serverflags = 0
  saw_maxclients = 0
}
tolower($0) ~ /^[[:space:]]*section[[:space:]]+"serverflags"/ {
  in_serverflags = 1
  found_serverflags = 1
  saw_maxclients = 0
  print
  next
}
in_serverflags && tolower($0) ~ /^[[:space:]]*option[[:space:]]+"maxclients"/ {
  print "    Option \"MaxClients\" \"2048\""
  saw_maxclients = 1
  next
}
in_serverflags && tolower($0) ~ /^[[:space:]]*endsection/ {
  if (!saw_maxclients) {
    print "    Option \"MaxClients\" \"2048\""
  }
  in_serverflags = 0
  print
  next
}
{ print }
END {
  if (!found_serverflags) {
    print ""
    print "Section \"ServerFlags\""
    print "    Option \"MaxClients\" \"2048\""
    print "EndSection"
  }
}
' "$target" > "$tmp"

cat "$tmp" > "$target"
rm -f "$tmp"

