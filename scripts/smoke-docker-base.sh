#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-osworld-base-xfce}"

docker exec "$CONTAINER_NAME" bash -lc '
  set -euo pipefail

  fail() {
    printf "FAIL: %s\n" "$*" >&2
    exit 1
  }

  dpkg-query -W -f="\${Status}\n" xfce4-session supervisor x11vnc novnc tini >/dev/null
  for removed in gdm3 gnome-shell snapd; do
    if dpkg-query -W -f="\${Status}" "$removed" 2>/dev/null | grep -q "install ok installed"; then
      fail "$removed should not be installed in the Docker base image"
    fi
  done

  test "$(basename "$(readlink /proc/1/exe)")" = tini || fail "PID 1 is not tini"
  supervisorctl status
  pgrep -x Xvfb >/dev/null || fail "Xvfb is not running"
  pgrep -f xfce4-session >/dev/null || fail "XFCE session is not running"
  xdpyinfo -display "${DISPLAY:-:0}" >/dev/null || fail "DISPLAY is not usable"
  ss -ltn | grep -q ":5900" && ss -ltn | grep -q ":6080" \
    || fail "VNC/noVNC ports are not listening"

  server_running=0
  for _ in $(seq 1 30); do
    if supervisorctl status osworld-server | grep -q RUNNING; then
      server_running=1
      break
    fi
    sleep 1
  done

  if [ "$server_running" = "1" ]; then
    ss -ltn | grep -q ":5000" \
      || fail "osworld-server process is running but port 5000 is not listening"
    screenshot_file="$(mktemp)"
    screenshot_ok=0
    for _ in $(seq 1 30); do
      if curl -fsS http://127.0.0.1:5000/screenshot -o "$screenshot_file"; then
        screenshot_ok=1
        break
      fi
      sleep 1
    done
    test "$screenshot_ok" = "1" || fail "osworld-server screenshot endpoint failed"
    head -c 8 "$screenshot_file" | od -An -tx1 | tr -d " \n" | grep -qi "^89504e470d0a1a0a$" \
      || fail "osworld-server screenshot endpoint did not return a PNG"
    rm -f "$screenshot_file"
  fi

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
  for mime_type in text/html x-scheme-handler/http x-scheme-handler/https; do
    launch_as_user xdg-mime query default "$mime_type" | grep -qx "google-chrome.desktop" \
      || fail "Chrome is not the default handler for $mime_type"
  done

  wait_for_window() {
    local pattern="$1"
    local log_file="$2"
    for _ in $(seq 1 30); do
      if launch_as_user wmctrl -l | grep -Eq "$pattern"; then
        return 0
      fi
      sleep 1
    done
    if [ -s "$log_file" ]; then
      sed -n "1,160p" "$log_file" >&2
    fi
    return 1
  }

  if [ "$server_running" = "1" ]; then
    wallpaper_file="$(mktemp)"
    curl -fsS -X POST http://127.0.0.1:5000/wallpaper -o "$wallpaper_file" \
      || fail "osworld-server wallpaper endpoint failed"
    head -c 8 "$wallpaper_file" | od -An -tx1 | tr -d " \n" | grep -qi "^89504e470d0a1a0a$" \
      || fail "osworld-server wallpaper endpoint did not return a PNG"
    rm -f "$wallpaper_file"

    curl -fsS -X POST http://127.0.0.1:5000/setup/change_wallpaper \
      -H "Content-Type: application/json" \
      -d "{\"path\":\"/usr/share/backgrounds/xfce/xfce-verticals.png\"}" \
      | grep -q "Wallpaper changed successfully" \
      || fail "osworld-server change_wallpaper endpoint failed"

    if command -v xfce4-terminal >/dev/null 2>&1; then
      launch_as_user pkill -x xfce4-terminal >/dev/null 2>&1 || true
      launch_as_user bash -lc "xfce4-terminal --title osworld-terminal-smoke --command \"sh -c \\\"printf osworld-terminal-smoke; sleep 60\\\"\" >/tmp/osworld-smoke-terminal.log 2>&1 &"
      wait_for_window "osworld-terminal-smoke" /tmp/osworld-smoke-terminal.log \
        || fail "XFCE Terminal did not open a window"
      launch_as_user wmctrl -a osworld-terminal-smoke >/dev/null 2>&1 || true
      terminal_output="$(mktemp)"
      terminal_ok=0
      for _ in $(seq 1 30); do
        if curl -fsS http://127.0.0.1:5000/terminal -o "$terminal_output" \
          && grep -q "osworld-terminal-smoke" "$terminal_output"; then
          terminal_ok=1
          break
        fi
        sleep 1
      done
      if [ "$terminal_ok" != "1" ]; then
        cat "$terminal_output" >&2 || true
        fail "osworld-server terminal endpoint did not read XFCE Terminal output"
      fi
      rm -f "$terminal_output"
      launch_as_user pkill -x xfce4-terminal >/dev/null 2>&1 || true
    fi
  fi

  if command -v google-chrome-stable >/dev/null 2>&1; then
    launch_as_user pkill -f "/opt/google/chrome/chrome" >/dev/null 2>&1 || true
    launch_as_user bash -lc "google-chrome-stable --new-window about:blank >/tmp/osworld-smoke-chrome.log 2>&1 &"
    wait_for_window "Google Chrome" /tmp/osworld-smoke-chrome.log \
      || fail "Google Chrome did not open a window"
    launch_as_user pkill -f "/opt/google/chrome/chrome" >/dev/null 2>&1 || true
  fi

  if command -v code >/dev/null 2>&1; then
    launch_as_user pkill -f "/usr/share/code/code" >/dev/null 2>&1 || true
    launch_as_user bash -lc "code --new-window >/tmp/osworld-smoke-code.log 2>&1 &"
    wait_for_window "Visual Studio Code" /tmp/osworld-smoke-code.log \
      || fail "Visual Studio Code did not open a window"
    launch_as_user pkill -f "/usr/share/code/code" >/dev/null 2>&1 || true
  fi

  printf "Docker base smoke checks passed\n"
'
