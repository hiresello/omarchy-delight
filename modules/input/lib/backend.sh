#!/bin/bash

# Backend selection for the input module (sourced by bin/delight-input and by
# modules/input/tests/backend-test.sh; needs delight_hw_portal from
# lib/delight/delight.sh).

# input_select_backend <share|receive> <auto|deskflow|lan-mouse>
# Prints {"role","backend","override","inputCapture","remoteDesktop","reason"}.
input_select_backend() {
  local role="${1:-}" override="${2:-auto}"
  local input_capture=false remote_desktop=false backend reason=null

  case "$role" in
    share | receive) ;;
    *)
      echo "input_select_backend: invalid role '$role' (share|receive)" >&2
      return 64
      ;;
  esac
  case "$override" in
    auto | deskflow | lan-mouse) ;;
    *)
      echo "input_select_backend: invalid backend '$override' (auto|deskflow|lan-mouse)" >&2
      return 64
      ;;
  esac

  if delight_hw_portal org.freedesktop.portal.InputCapture; then
    input_capture=true
  fi
  if delight_hw_portal org.freedesktop.portal.RemoteDesktop; then
    remote_desktop=true
  fi

  if [[ $override != "auto" ]]; then
    backend=$override
    if [[ $backend == "deskflow" && $role == "share" && $input_capture == "false" ]]; then
      reason="forced deskflow without the InputCapture portal; sharing will not work"
    elif [[ $backend == "deskflow" && $role == "receive" && $remote_desktop == "false" ]]; then
      reason="forced deskflow without the RemoteDesktop portal; receiving will not work"
    fi
  elif [[ $role == "share" ]]; then
    if [[ $input_capture == "true" ]]; then
      backend=deskflow
    else
      backend=lan-mouse
      reason="InputCapture portal not available; using Lan Mouse"
    fi
  else
    if [[ $remote_desktop == "true" ]]; then
      backend=deskflow
    else
      backend=lan-mouse
      reason="xdg-desktop-portal-hyprland has no RemoteDesktop portal; receiving via Lan Mouse"
    fi
  fi

  local forced=false
  if [[ $override != "auto" ]]; then
    forced=true
  fi
  jq -cn --arg role "$role" --arg backend "$backend" --arg reason "$reason" \
    --argjson override "$forced" \
    --argjson ic "$input_capture" --argjson rd "$remote_desktop" \
    '{role:$role, backend:$backend, override:$override, inputCapture:$ic, remoteDesktop:$rd,
      reason:(if $reason == "null" then null else $reason end)}'
}
