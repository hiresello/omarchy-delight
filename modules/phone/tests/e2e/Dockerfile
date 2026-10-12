FROM archlinux:latest

RUN pacman -Syu --noconfirm --needed \
    coreutils dbus diffutils iproute2 jq kdeconnect mako python-jsonschema sway swaybg \
    wl-clipboard xorg-xwayland

COPY modules/phone/tests/e2e/peer-init /usr/local/bin/peer-init
COPY modules/phone/tests/e2e/peer-exec /usr/local/bin/peer-exec
COPY modules/phone/tests/e2e/clipboard-poll /usr/local/bin/clipboard-poll
COPY modules/phone/tests/e2e/notification-stub /usr/local/bin/omarchy-notification-send
RUN chmod +x /usr/local/bin/peer-init /usr/local/bin/peer-exec \
    /usr/local/bin/clipboard-poll /usr/local/bin/omarchy-notification-send

ENTRYPOINT ["/usr/local/bin/peer-init"]
