#!/bin/bash

# Parse a face-auth PAM stack and decide whether it is safe to install.
# Safe means: faillock can lock the account, a failed gate skips face, face
# success does not refresh the password stamp, and a face miss still reaches
# the password. Anything else is rejected.

face_auth_kind() {
  local module="$1" args="$2" base
  base=${module##*/}
  case "$base" in
    pam_howdy.so) printf '%s\n' howdy ;;
    pam_unix.so) printf '%s\n' unix ;;
    pam_deny.so) printf '%s\n' deny ;;
    pam_faillock.so)
      case " $args " in
        *" preauth "*) printf '%s\n' preauth ;;
        *" authsucc "*) printf '%s\n' authsucc ;;
        *" authfail "*) printf '%s\n' authfail ;;
        *) printf '%s\n' faillock ;;
      esac
      ;;
    pam_exec.so)
      case "$args" in
        *face-auth-gate*) printf '%s\n' gate ;;
        *face-auth-stamp*) printf '%s\n' stamp ;;
        *) printf '%s\n' exec ;;
      esac
      ;;
    *) printf '%s\n' other ;;
  esac
}

# Map a control token and a SUCCESS/OTHER result to ok|done|bad|die|ignore|N.
face_auth_action() {
  local control="$1" code="$2" inner token key val success_act="" default_act=""
  case "$control" in
    required)
      [[ $code == SUCCESS ]] && printf '%s\n' ok || printf '%s\n' bad
      ;;
    requisite)
      [[ $code == SUCCESS ]] && printf '%s\n' ok || printf '%s\n' die
      ;;
    sufficient)
      [[ $code == SUCCESS ]] && printf '%s\n' "done" || printf '%s\n' "ignore"
      ;;
    optional)
      [[ $code == SUCCESS ]] && printf '%s\n' ok || printf '%s\n' ignore
      ;;
    \[*\])
      inner=${control#[}
      inner=${inner%]}
      for token in $inner; do
        key=${token%%=*}
        val=${token#*=}
        case "$key" in
          success) success_act=$val ;;
          default) default_act=$val ;;
        esac
      done
      [[ -n $default_act ]] || default_act=bad
      if [[ $code == SUCCESS ]]; then
        [[ -n $success_act ]] && printf '%s\n' "$success_act" || printf '%s\n' ok
      else
        printf '%s\n' "$default_act"
      fi
      ;;
    *)
      printf '%s\n' bad
      ;;
  esac
}

face_auth_outcome() {
  local scenario="$1" kind="$2"
  case "$kind" in
    preauth)
      [[ $scenario == preauth_locked ]] && printf '%s\n' FAIL || printf '%s\n' SUCCESS
      ;;
    gate)
      [[ $scenario == gate_deny_* ]] && printf '%s\n' FAIL || printf '%s\n' SUCCESS
      ;;
    howdy)
      [[ $scenario == face_ok ]] && printf '%s\n' SUCCESS || printf '%s\n' FAIL
      ;;
    authfail)
      printf '%s\n' IGNORE
      ;;
    unix)
      case "$scenario" in
        gate_deny_password_ok | face_fail_password_ok | face_ok) printf '%s\n' SUCCESS ;;
        *) printf '%s\n' FAIL ;;
      esac
      ;;
    stamp | authsucc)
      printf '%s\n' SUCCESS
      ;;
    *)
      printf '%s\n' FAIL
      ;;
  esac
}

# Load auth lines from a PAM file into PAM_CONTROL/MODULE/ARGS and AUTH_AT.
# Bracket controls contain spaces ([success=1 default=bad]). Rejoin them.
face_auth_split_line() {
  local line="$1"
  local -a fields
  read -r -a fields <<<"$line"
  SPLIT_TYPE=${fields[0]:-}
  SPLIT_CONTROL=""
  SPLIT_MODULE=""
  SPLIT_ARGS=""
  [[ -n $SPLIT_TYPE ]] || return 1
  local idx=1 token
  token=${fields[1]:-}
  case "$token" in
    "["*"]")
      SPLIT_CONTROL=$token
      idx=2
      ;;
    "["*)
      SPLIT_CONTROL=$token
      idx=2
      while [[ ${SPLIT_CONTROL: -1} != "]" && $idx -lt ${#fields[@]} ]]; do
        SPLIT_CONTROL+=" ${fields[$idx]}"
        idx=$((idx + 1))
      done
      ;;
    *)
      SPLIT_CONTROL=$token
      idx=2
      ;;
  esac
  SPLIT_MODULE=${fields[$idx]:-}
  if ((idx + 1 < ${#fields[@]})); then
    SPLIT_ARGS="${fields[*]:$((idx + 1))}"
  fi
}

face_auth_load_auth() {
  local file="$1" line
  PAM_CONTROL=()
  PAM_MODULE=()
  PAM_ARGS=()
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line//$'\r'/}
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    face_auth_split_line "$line" || continue
    [[ $SPLIT_TYPE == auth ]] || continue
    PAM_CONTROL+=("$SPLIT_CONTROL")
    PAM_MODULE+=("$SPLIT_MODULE")
    PAM_ARGS+=("$SPLIT_ARGS")
  done <"$file"
}

face_auth_note_reached() {
  case "$1" in
    howdy) SIM_HOWDY=1 ;;
    unix) SIM_UNIX=1 ;;
    stamp) SIM_STAMP=1 ;;
    authsucc) SIM_AUTHSUCC=1 ;;
  esac
}

# Simulate one scenario. Sets SIM_RESULT and the SIM_* reached flags.
face_auth_simulate() {
  local scenario="$1" i=0 n kind code action skip
  n=${#PAM_MODULE[@]}
  SIM_RESULT=die
  SIM_HOWDY=0
  SIM_UNIX=0
  SIM_STAMP=0
  SIM_AUTHSUCC=0
  local impression=undef
  while ((i < n)); do
    kind=$(face_auth_kind "${PAM_MODULE[$i]}" "${PAM_ARGS[$i]:-}")
    face_auth_note_reached "$kind"
    code=$(face_auth_outcome "$scenario" "$kind")
    if [[ $code == SUCCESS ]]; then
      action=$(face_auth_action "${PAM_CONTROL[$i]}" SUCCESS)
    else
      action=$(face_auth_action "${PAM_CONTROL[$i]}" OTHER)
    fi
    case "$action" in
      ok)
        [[ $impression == undef ]] && impression=positive
        i=$((i + 1))
        ;;
      done)
        [[ $impression == undef || $impression == positive ]] && impression=positive
        if [[ $impression == positive ]]; then
          SIM_RESULT=success
          return 0
        fi
        i=$((i + 1))
        ;;
      bad)
        impression=negative
        i=$((i + 1))
        ;;
      die)
        SIM_RESULT=die
        return 0
        ;;
      ignore)
        i=$((i + 1))
        ;;
      *[!0-9]* | "")
        SIM_RESULT=die
        return 0
        ;;
      *)
        skip=$action
        i=$((i + 1))
        while ((skip > 0)); do
          if ((i >= n)); then
            SIM_RESULT=die
            return 0
          fi
          skip=$((skip - 1))
          i=$((i + 1))
        done
        ;;
    esac
  done
  if [[ $impression == positive ]]; then
    SIM_RESULT=success
  else
    SIM_RESULT=die
  fi
}

face_auth_expect_scenario() {
  local name="$1" want_result="$2" want_howdy="$3" want_unix="$4" want_stamp="$5" want_authsucc="$6"
  face_auth_simulate "$name"
  if [[ $SIM_RESULT != "$want_result" || $SIM_HOWDY != "$want_howdy" || $SIM_UNIX != "$want_unix" || $SIM_STAMP != "$want_stamp" || $SIM_AUTHSUCC != "$want_authsucc" ]]; then
    printf 'scenario: %s result=%s howdy=%s unix=%s stamp=%s authsucc=%s\n' \
      "$name" "$SIM_RESULT" "$SIM_HOWDY" "$SIM_UNIX" "$SIM_STAMP" "$SIM_AUTHSUCC" >&2
    return 1
  fi
}

# Validate PAM text for one allowed service. Policy JSON is the second arg.
# Prints a short reason on failure.
face_auth_validate_pam_file() {
  local file="$1" policy="$2" service="$3"
  local line deny interval unlock
  deny=$(jq -r '.deny' <<<"$policy")
  interval=$(jq -r '.fail_interval' <<<"$policy")
  unlock=$(jq -r '.unlock_time' <<<"$policy")

  case "$service" in
    hyprlock | sudo) ;;
    *)
      printf 'forbidden-service: %s\n' "$service" >&2
      return 1
      ;;
  esac
  if [[ $(jq -r --arg s "$service" '.scope[$s]' <<<"$policy") != true ]]; then
    printf 'scope: %s is not enabled\n' "$service" >&2
    return 1
  fi

  if grep -E -q 'nullok|pam_permit|even_deny_root|workaround=(native|input|native-input)' "$file"; then
    grep -E -o 'nullok|pam_permit|even_deny_root|workaround=(native|input|native-input)' "$file" | head -n 1 | sed 's/^/forbidden: /' >&2
    return 1
  fi
  if grep -E -q '^[[:space:]]*-?(auth|account|password|session)[[:space:]]+(include|substack)[[:space:]]' "$file"; then
    printf 'forbidden: include\n' >&2
    return 1
  fi

  face_auth_load_auth "$file"
  local -a want_kind=(preauth gate howdy authfail unix authfail stamp authsucc deny)
  local -a want_control=(
    "[success=ok default=die]"
    "[success=ignore default=2]"
    "[success=4 default=ignore]"
    "[default=ignore]"
    "[success=1 default=bad]"
    "[default=die]"
    "[default=ignore]"
    "sufficient"
    "required"
  )
  local i kind
  if [[ ${#PAM_MODULE[@]} -ne ${#want_kind[@]} ]]; then
    printf 'shape: auth-count %s\n' "${#PAM_MODULE[@]}" >&2
    return 1
  fi
  for i in "${!want_kind[@]}"; do
    kind=$(face_auth_kind "${PAM_MODULE[$i]}" "${PAM_ARGS[$i]:-}")
    if [[ $kind != "${want_kind[$i]}" || ${PAM_CONTROL[$i]} != "${want_control[$i]}" ]]; then
      printf 'shape: line %s kind=%s control=%s\n' "$i" "$kind" "${PAM_CONTROL[$i]}" >&2
      return 1
    fi
  done

  local fail_args="silent deny=${deny} fail_interval=${interval} unlock_time=${unlock}"
  for i in 0 3 5 7; do
    [[ ${PAM_ARGS[$i]} == *"$fail_args"* ]] || {
      printf 'faillock: line %s args=%s\n' "$i" "${PAM_ARGS[$i]}" >&2
      return 1
    }
  done
  [[ ${PAM_MODULE[1]} == *pam_exec.so && ${PAM_ARGS[1]} == *"face-auth-gate ${service}" ]] || {
    printf 'shape: gate-service\n' >&2
    return 1
  }
  [[ ${PAM_ARGS[2]} != *workaround=* ]] || {
    printf 'forbidden: workaround\n' >&2
    return 1
  }
  [[ ${PAM_ARGS[4]} == "try_first_pass" ]] || {
    printf 'shape: unix-args\n' >&2
    return 1
  }

  if ! grep -E -q '^account[[:space:]]+required[[:space:]]+pam_unix\.so([[:space:]]|$)' "$file" \
    || ! grep -E -q '^account[[:space:]]+required[[:space:]]+pam_faillock\.so([[:space:]]|$)' "$file" \
    || ! grep -E -q '^password[[:space:]]+required[[:space:]]+pam_unix\.so[[:space:]]+sha512[[:space:]]+shadow[[:space:]]*$' "$file" \
    || ! grep -E -q '^session[[:space:]]+required[[:space:]]+pam_unix\.so([[:space:]]|$)' "$file"; then
    printf 'shape: account-password-session\n' >&2
    return 1
  fi
  if grep -E '^session[[:space:]]+' "$file" | grep -E -q -v '^session[[:space:]]+required[[:space:]]+pam_unix\.so([[:space:]]|$)'; then
    printf 'shape: extra-session\n' >&2
    return 1
  fi

  face_auth_expect_scenario preauth_locked die 0 0 0 0 || return 1
  face_auth_expect_scenario gate_deny_password_ok success 0 1 1 1 || return 1
  face_auth_expect_scenario gate_deny_password_bad die 0 1 0 0 || return 1
  face_auth_expect_scenario face_ok success 1 0 0 1 || return 1
  face_auth_expect_scenario face_fail_password_ok success 1 1 1 1 || return 1
  face_auth_expect_scenario face_fail_password_bad die 1 1 0 0 || return 1
}
