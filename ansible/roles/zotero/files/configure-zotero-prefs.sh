#!/usr/bin/env bash
set -euo pipefail

user_name="$1"
user_home="$2"
profile_root="$user_home/.zotero/zotero"
profiles_ini="$profile_root/profiles.ini"

mkdir -p "$profile_root"

if [ ! -f "$profiles_ini" ]; then
  cat > "$profiles_ini" <<'EOF'
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=default
IsRelative=1
Path=osworld.default
Default=1
EOF
fi

mapfile -t relative_profiles < <(awk -F= '/^Path=/ {print $2}' "$profiles_ini" | sed '/^$/d')

if [ "${#relative_profiles[@]}" -eq 0 ]; then
  relative_profiles=("osworld.default")
fi

for profile in "${relative_profiles[@]}"; do
  case "$profile" in
    /*) profile_dir="$profile" ;;
    *) profile_dir="$profile_root/$profile" ;;
  esac
  mkdir -p "$profile_dir"
  for pref_file in "$profile_dir/prefs.js" "$profile_dir/user.js"; do
    touch "$pref_file"
    grep -vE 'extensions\.zotero\.httpServer\.(localAPI\.)?enabled' "$pref_file" > "$pref_file.tmp" || true
    cat >> "$pref_file.tmp" <<'EOF'
user_pref("extensions.zotero.httpServer.enabled", true);
user_pref("extensions.zotero.httpServer.localAPI.enabled", true);
EOF
    mv "$pref_file.tmp" "$pref_file"
  done
done

chown -R "$user_name:$user_name" "$user_home/.zotero"

