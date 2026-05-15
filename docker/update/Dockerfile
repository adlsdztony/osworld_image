# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=osworld-base-xfce:latest
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ARG OSWORLD_USER=user
ARG PROVISION_CACHE_BUST=manual

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    DISPLAY=:0 \
    XDG_SESSION_TYPE=x11 \
    GDK_BACKEND=x11 \
    SCREEN_GEOMETRY=1920x1080x24 \
    OSWORLD_USER=${OSWORLD_USER} \
    OSWORLD_SERVER_HOST=0.0.0.0 \
    OSWORLD_SERVER_PORT=5000 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY docker/update/finalize-docker-update /usr/local/sbin/finalize-docker-update
COPY docker/base/osworld-docker-entrypoint /usr/local/bin/osworld-docker-entrypoint
COPY docker/base/start-osworld-server /usr/local/bin/start-osworld-server
COPY docker/base/supervisord.conf /etc/supervisor/supervisord.conf

RUN chmod 0755 \
      /usr/local/sbin/finalize-docker-update \
      /usr/local/bin/osworld-docker-entrypoint \
      /usr/local/bin/start-osworld-server \
    && printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && install -d -m 1777 /tmp /var/tmp /tmp/.X11-unix /tmp/.ICE-unix

RUN --mount=type=bind,source=ansible,target=/mnt/osworld-provision/ansible,readonly \
    --mount=type=bind,source=ansible.cfg,target=/mnt/osworld-provision/ansible.cfg,readonly \
    --mount=type=bind,source=downloads/wps_fonts,target=/mnt/osworld-provision/downloads/wps_fonts,readonly \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    printf 'Provision cache key: %s\n' "$PROVISION_CACHE_BUST" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ansible \
    && ANSIBLE_CONFIG=/mnt/osworld-provision/ansible.cfg \
       ansible-playbook \
         -i localhost, \
         -c local \
         /mnt/osworld-provision/ansible/playbook.yml \
         --extra-vars "osworld_user=${OSWORLD_USER} target_platform=docker" \
    && /usr/local/sbin/finalize-docker-update \
    && apt-get purge -y --auto-remove ansible \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 5000 5900 6080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/osworld-docker-entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
