#!/bin/bash

# Hardware and session capability checks. Each returns 0 when present.
# DELIGHT_SYSFS overrides /sys for tests.

delight_hw_bluetooth() {
  compgen -G "${DELIGHT_SYSFS:-/sys}/class/bluetooth/hci*" >/dev/null
}

delight_hw_wifi_monitor() {
  delight_has_cmd iw || return 1
  iw list 2>/dev/null | grep -Eq '^[[:space:]]+\* monitor$'
}

delight_hw_kmod_loadable() {
  [[ -d ${DELIGHT_SYSFS:-/sys}/module/$1 ]] && return 0
  modinfo -n -- "$1" >/dev/null 2>&1
}

delight_hw_hyprland() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl version >/dev/null 2>&1
}

# delight_hw_portal org.freedesktop.portal.InputCapture
delight_hw_portal() {
  busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop 2>/dev/null \
    | grep -q "^$1[[:space:]]"
}

delight_hw_omarchy() {
  [[ -d ${OMARCHY_PATH:-/usr/share/omarchy} ]] && delight_has_cmd omarchy
}
