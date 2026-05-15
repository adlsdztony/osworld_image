#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-osworld-xfce}"
EXPECTED_SERVER_COMMIT="${EXPECTED_SERVER_COMMIT:-a6979eaf85ce22c281119d2b60e1f25da6dd68ec}"

docker exec "$CONTAINER_NAME" bash -lc '
  set -euo pipefail

  expected_server_commit="'"$EXPECTED_SERVER_COMMIT"'"

  fail() {
    printf "FAIL: %s\n" "$*" >&2
    exit 1
  }

  marker="/home/${OSWORLD_USER:-user}/server/.osworld-server-commit"
  test -f "$marker" || fail "OSWorld server commit marker missing"
  test "$(cat "$marker")" = "$expected_server_commit" || fail "OSWorld server commit marker mismatch"

  dpkg-query -W -f="\${Version}\n" obsidian | grep -q "1.10.6" || fail "Obsidian version mismatch"
  dpkg-query -W -f="\${Version}\n" xmind-vana | grep -q "26.1.3145" || fail "XMind version mismatch"
  dpkg-query -W -f="\${Version}\n" wps-office | grep -q "11.1.0.11723" || fail "WPS version mismatch"

  if dpkg-query -W -f="\${Status}" snapd 2>/dev/null | grep -q "install ok installed"; then
    fail "snapd should not be installed in the Docker update image"
  fi

  for required in blender zotero reaper shotcut labplot musescore; do
    command -v "$required" >/dev/null 2>&1 || fail "$required is missing from PATH"
  done

  test "$(basename "$(readlink /proc/1/exe)")" = tini || fail "PID 1 is not tini"
  supervisorctl status
  pgrep -x Xvfb >/dev/null || fail "Xvfb is not running"
  pgrep -f xfce4-session >/dev/null || fail "XFCE session is not running"
  xdpyinfo -display "${DISPLAY:-:0}" >/dev/null || fail "DISPLAY is not usable"

  server_running=0
  for _ in $(seq 1 30); do
    if supervisorctl status osworld-server | grep -q RUNNING; then
      server_running=1
      break
    fi
    sleep 1
  done
  test "$server_running" = "1" || fail "osworld-server is not running"

  screenshot_file="$(mktemp)"
  screenshot_ok=0
  for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:5000/screenshot -o "$screenshot_file"; then
      screenshot_ok=1
      break
    fi
    sleep 1
  done
  test "$screenshot_ok" = "1" || fail "screenshot endpoint failed"
  head -c 8 "$screenshot_file" | od -An -tx1 | tr -d " \n" | grep -qi "^89504e470d0a1a0a$" \
    || fail "screenshot endpoint did not return a PNG"
  rm -f "$screenshot_file"

  user_name="${OSWORLD_USER:-user}"
  user_home="$(getent passwd "$user_name" | awk -F: "{print \$6}")"
  user_id="$(id -u "$user_name")"
  user_env=(
    HOME="$user_home"
    USER="$user_name"
    LOGNAME="$user_name"
    DISPLAY="${DISPLAY:-:0}"
    XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
    GDK_BACKEND="${GDK_BACKEND:-x11}"
    XDG_RUNTIME_DIR="/run/user/$user_id"
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus"
  )

  launch_as_user() {
    sudo -u "$user_name" env "${user_env[@]}" "$@"
  }

  launch_as_user xdg-settings get default-web-browser | grep -qx "google-chrome.desktop" \
    || fail "Chrome is not the default browser"

  printf "Docker update smoke checks passed\n"
'
