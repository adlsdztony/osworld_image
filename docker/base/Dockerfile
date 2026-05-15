ARG BASE_IMAGE=osworld-rootfs-raw:latest
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    DISPLAY=:0 \
    XDG_SESSION_TYPE=x11 \
    GDK_BACKEND=x11 \
    SCREEN_GEOMETRY=1920x1080x24 \
    OSWORLD_USER=user \
    OSWORLD_SERVER_HOST=0.0.0.0 \
    OSWORLD_SERVER_PORT=5000 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && chmod 1777 /tmp /var/tmp \
    && rm -f /etc/machine-id /var/lib/dbus/machine-id \
    && touch /etc/machine-id

RUN remove_packages=( \
      ubuntu-desktop ubuntu-desktop-minimal ubuntu-session \
      gdm3 gnome-shell gnome-session gnome-session-bin gnome-session-common \
      gnome-control-center gnome-initial-setup gnome-settings-daemon \
      gnome-software gnome-software-plugin-snap gnome-terminal mutter nautilus \
      gnome-calendar gnome-characters gnome-clocks gnome-contacts \
      gnome-font-viewer gnome-logs gnome-maps gnome-music gnome-photos \
      gnome-screenshot cheese eog evince rhythmbox simple-scan totem yelp \
      apport-gtk network-manager-gnome software-properties-gtk update-manager \
      snap-store firefox snapd flatpak xdg-desktop-portal-gnome \
      ubuntu-advantage-desktop-daemon ubuntu-release-upgrader-gtk \
      open-vm-tools open-vm-tools-desktop cloud-init \
    ) \
    && apt-get update \
    && installed=() \
    && for pkg in "${remove_packages[@]}"; do \
         if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then \
           installed+=("$pkg"); \
         fi; \
       done \
    && if ((${#installed[@]})); then \
         apt-get purge -y --auto-remove "${installed[@]}"; \
       fi \
    && apt-get install -y --no-install-recommends \
      adwaita-icon-theme \
      at-spi2-core \
      ca-certificates \
      curl \
      dbus \
      dbus-user-session \
      dbus-x11 \
      desktop-file-utils \
      fonts-dejavu \
      hicolor-icon-theme \
      iproute2 \
      locales \
      mesa-utils \
      net-tools \
      novnc \
      procps \
      pulseaudio \
      scrot \
      shared-mime-info \
      sudo \
      supervisor \
      thunar \
      tini \
      websockify \
      wmctrl \
      x11-utils \
      x11vnc \
      xauth \
      xfce4-panel \
      xfce4-session \
      xfce4-settings \
      xfce4-terminal \
      xfconf \
      xfdesktop4 \
      xfwm4 \
      xvfb \
      xdg-utils \
    && locale-gen en_US.UTF-8 \
    && apt-get autoremove -y --purge \
    && apt-get clean \
    && rm -rf \
      /boot/* \
      /lib/modules/* \
      /snap \
      /var/lib/apt/lists/* \
      /var/lib/snapd \
      /tmp/* \
      /var/tmp/*

COPY osworld-docker-entrypoint /usr/local/bin/osworld-docker-entrypoint
COPY start-osworld-server /usr/local/bin/start-osworld-server
COPY start-xfce-session /usr/local/bin/start-xfce-session
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY google-chrome-docker-wrapper /usr/local/share/osworld/google-chrome-docker-wrapper
COPY code-docker-wrapper /usr/local/share/osworld/code-docker-wrapper
COPY osworld-server-xfce.patch /usr/local/share/osworld/osworld-server-xfce.patch

RUN chmod 0755 \
      /usr/local/bin/osworld-docker-entrypoint \
      /usr/local/bin/start-osworld-server \
      /usr/local/bin/start-xfce-session \
      /usr/local/share/osworld/google-chrome-docker-wrapper \
      /usr/local/share/osworld/code-docker-wrapper \
    && if [ -f /home/user/server/main.py ]; then \
         patch -d / -p0 < /usr/local/share/osworld/osworld-server-xfce.patch; \
       fi \
    && if [ -x /opt/google/chrome/google-chrome ] && [ ! -e /opt/google/chrome/google-chrome.real ]; then \
         mv /opt/google/chrome/google-chrome /opt/google/chrome/google-chrome.real; \
         install -m 0755 /usr/local/share/osworld/google-chrome-docker-wrapper /opt/google/chrome/google-chrome; \
       fi \
    && if [ -x /usr/share/code/bin/code ]; then \
         rm -f /usr/bin/code; \
         install -m 0755 /usr/local/share/osworld/code-docker-wrapper /usr/bin/code; \
       fi \
    && if [ -f /usr/share/applications/code.desktop ]; then \
         sed -i 's#^Exec=/usr/share/code/code #Exec=/usr/bin/code #' /usr/share/applications/code.desktop; \
       fi \
    && if [ -f /usr/share/applications/code-url-handler.desktop ]; then \
         sed -i 's#^Exec=/usr/share/code/code #Exec=/usr/bin/code #' /usr/share/applications/code-url-handler.desktop; \
       fi \
    && if command -v google-chrome-stable >/dev/null 2>&1; then \
         update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/google-chrome-stable 200; \
         update-alternatives --set x-www-browser /usr/bin/google-chrome-stable; \
         update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/bin/google-chrome-stable 200; \
         update-alternatives --set gnome-www-browser /usr/bin/google-chrome-stable; \
         install -d -m 0755 /etc/xdg; \
         printf '[Default Applications]\ntext/html=google-chrome.desktop\nx-scheme-handler/http=google-chrome.desktop\nx-scheme-handler/https=google-chrome.desktop\nx-scheme-handler/about=google-chrome.desktop\nx-scheme-handler/unknown=google-chrome.desktop\n' > /etc/xdg/mimeapps.list; \
         browser_user="${OSWORLD_USER:-user}"; \
         if id "$browser_user" >/dev/null 2>&1; then \
           browser_home="$(getent passwd "$browser_user" | awk -F: '{print $6}')"; \
           browser_uid="$(id -u "$browser_user")"; \
           browser_gid="$(id -g "$browser_user")"; \
           install -d -m 0700 -o "$browser_uid" -g "$browser_gid" "$browser_home/.config"; \
           install -d -m 0755 -o "$browser_uid" -g "$browser_gid" "$browser_home/.local" "$browser_home/.local/share" "$browser_home/.local/share/applications"; \
           sudo -u "$browser_user" env HOME="$browser_home" XDG_CONFIG_HOME="$browser_home/.config" XDG_DATA_HOME="$browser_home/.local/share" \
             xdg-mime default google-chrome.desktop text/html x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about x-scheme-handler/unknown; \
           sudo -u "$browser_user" env HOME="$browser_home" XDG_CONFIG_HOME="$browser_home/.config" XDG_DATA_HOME="$browser_home/.local/share" XDG_CURRENT_DESKTOP=XFCE \
             xdg-settings set default-web-browser google-chrome.desktop || true; \
         fi; \
       fi \
    && { update-desktop-database /usr/share/applications || true; } \
    && install -d -m 0755 /var/log/supervisor /run/dbus \
    && install -d -m 1777 /tmp/.X11-unix \
    && find /var/log -type f -exec truncate -s 0 {} + \
    && rm -rf \
      /root/.cache \
      /home/*/.cache \
      /usr/local/share/osworld/google-chrome-docker-wrapper \
      /usr/local/share/osworld/code-docker-wrapper \
      /usr/local/share/osworld/osworld-server-xfce.patch \
      /var/cache/apt/* \
      /var/lib/cloud \
      /var/log/journal \
      /var/tmp/* \
    && rm -f \
      /etc/ssh/ssh_host_* \
      /var/lib/dbus/machine-id \
      /run/dbus/pid \
    && touch /var/lib/dbus/machine-id

EXPOSE 5000 5900 6080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/osworld-docker-entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
