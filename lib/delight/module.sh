#!/bin/bash

# Default implementation of the module verb contract (docs/contracts.md).
# A module's bin/delight-<id> sets DELIGHT_MODULE_ID, optionally defines
# module_<verb> functions to override or extend a default, then calls:
#   delight_module_main "$@"

delight_module_usage() {
  cat <<USAGE
Usage: delight-$DELIGHT_MODULE_ID <verb>

  install | uninstall | enable | disable | toggle | status [--json] | doctor
USAGE
}

delight_module_enabled() {
  [[ $(delight_config_get "$DELIGHT_MODULE_ID" enabled 2>/dev/null) == "true" ]]
}

delight_module_units() {
  delight_module_field "$DELIGHT_MODULE_ID" '.units[]?'
}

delight_module_default_install() {
  local id="$DELIGHT_MODULE_ID" dir unit rule
  dir=$(delight_module_dir "$id")
  delight_state_init "$id"
  mapfile -t repo < <(delight_module_field "$id" '.packages.repo[]?')
  mapfile -t aur < <(delight_module_field "$id" '.packages.aur[]?')
  ((${#repo[@]} == 0)) || delight_pkg_add "$id" repo "${repo[@]}"
  ((${#aur[@]} == 0)) || delight_pkg_add "$id" aur "${aur[@]}"
  while IFS= read -r unit; do
    [[ -n $unit ]] || continue
    delight_unit_install "$id" "$dir/systemd/$unit"
  done < <(delight_module_units)
  delight_systemd_reload
  while IFS= read -r rule; do
    [[ -n $rule ]] || continue
    delight_ufw_allow "$id" "$(jq -r '.proto' <<<"$rule")" "$(jq -r '.ports' <<<"$rule")"
  done < <(delight_module_field "$id" '.firewall[]? | tojson')
  if [[ $(delight_module_field "$id" '.plugin // empty') != "" ]]; then
    delight_plugin_install "$id" "$dir/$(delight_module_field "$id" '.plugin')"
  fi
}

delight_module_default_uninstall() {
  local id="$DELIGHT_MODULE_ID"
  delight_plugin_remove_all "$id"
  delight_unit_remove "$id"
  delight_ufw_revoke "$id"
  delight_file_remove_all "$id"
  delight_pkg_remove "$id"
  delight_status_clear "$id"
  delight_config_unset_module "$id"
  delight_state_clear "$id"
}

delight_module_default_enable() {
  mapfile -t units < <(delight_module_units)
  delight_config_set "$DELIGHT_MODULE_ID" enabled true
  ((${#units[@]} == 0)) || delight_unit_start "${units[@]}"
}

delight_module_default_disable() {
  mapfile -t units < <(delight_module_units)
  delight_config_set "$DELIGHT_MODULE_ID" enabled false
  ((${#units[@]} == 0)) || delight_unit_stop "${units[@]}"
}

delight_module_default_status() {
  local id="$DELIGHT_MODULE_ID" name icon
  name=$(delight_module_field "$id" '.name')
  icon=$(delight_module_field "$id" '.icon')
  if ! delight_is_installed "$id"; then
    delight_status_json --id "$id" --state needs-setup --title "$name" --subtitle "Not installed" --icon "$icon" \
      --actions "$(jq -cn --arg id "$id" '[{label:"Install",command:["delight",$id,"install"]}]')"
  elif delight_module_enabled; then
    delight_status_json --id "$id" --state on --title "$name" --subtitle "On" --icon "$icon"
  else
    delight_status_json --id "$id" --state off --title "$name" --subtitle "Off" --icon "$icon"
  fi
}

# Exit codes: 0 ok, 1 fixable, 2 unsupported, 3 needs user action.
delight_module_default_doctor() {
  local id="$DELIGHT_MODULE_ID" pkg rc=0
  while IFS= read -r pkg; do
    [[ -n $pkg ]] || continue
    if ! delight_pkg_present "$pkg"; then
      echo "missing package: $pkg (run: delight $id install)"
      rc=1
    fi
  done < <(delight_module_field "$id" '.packages.repo[]?, .packages.aur[]?')
  ((rc == 0)) && echo "ok"
  return "$rc"
}

delight_module_call() {
  local verb="$1"
  shift
  if declare -F "module_$verb" >/dev/null; then
    "module_$verb" "$@"
  elif declare -F "delight_module_default_$verb" >/dev/null; then
    "delight_module_default_$verb" "$@"
  else
    delight_die "delight-$DELIGHT_MODULE_ID: unknown verb '$verb'" 64
  fi
}

delight_module_publish() {
  local json
  json=$(delight_module_call status) || return 0
  delight_status_write "$DELIGHT_MODULE_ID" "$json"
}

delight_module_main() {
  [[ -n ${DELIGHT_MODULE_ID:-} ]] || delight_die "DELIGHT_MODULE_ID is not set"
  local verb="${1:-}"
  shift || true
  case "$verb" in
    install)
      delight_module_call install "$@"
      delight_touchpoints_sync
      delight_module_publish
      ;;
    uninstall)
      delight_is_installed "$DELIGHT_MODULE_ID" || return 0
      delight_module_call disable >/dev/null 2>&1 || true
      delight_module_call uninstall "$@"
      delight_touchpoints_sync
      ;;
    enable | disable)
      delight_module_call "$verb" "$@"
      delight_module_publish
      ;;
    toggle)
      if delight_module_enabled; then
        delight_module_main disable
      else
        delight_module_main enable
      fi
      ;;
    status)
      if [[ ${1:-} == "--json" ]]; then
        delight_module_call status || delight_status_json --id "$DELIGHT_MODULE_ID" --state error \
          --title "$DELIGHT_MODULE_ID" --icon "" --reason "status failed"
        return 0
      fi
      delight_module_call status | jq -r '"\(.id): \(.state)\(if .subtitle != "" then " — " + .subtitle else "" end)\(if .reason then " (" + .reason + ")" else "" end)"'
      ;;
    doctor)
      delight_module_call doctor "$@"
      ;;
    "" | help | -h | --help)
      delight_module_usage
      ;;
    *)
      delight_module_call "$verb" "$@"
      ;;
  esac
}
