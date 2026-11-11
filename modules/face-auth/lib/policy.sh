#!/bin/bash

# Face-auth policy. A complete policy object in, a canonical object or an
# error out. Out-of-range values are rejected. Nothing here weakens a limit
# to make a bad policy fit.

# face_auth_policy_normalize reads one JSON object on stdin, writes a
# canonical object to stdout, and returns non-zero after printing
# "policy: <reason>" when the object is not acceptable.
face_auth_policy_normalize() {
  local raw
  raw=$(cat)
  jq -c '
    def intin(lo; hi):
      type == "number" and (isinfinite | not) and floor == . and . >= lo and . <= hi;
    def fail(msg): error("policy: " + msg);
    if type != "object" then fail("not-object") else . end
    | del(.enabled)
    | (keys - ["schema","scope","sudo_cache_seconds","suspend_max_seconds","deny","fail_interval","unlock_time","allow_unencrypted_models","device_path"]) as $extra
    | if $extra != [] then fail("unknown") else . end
    | if .schema != 1 then fail("schema") else . end
    | if (.scope | type) != "object" then fail("scope") else . end
    | ((.scope | keys) - ["hyprlock","sudo"]) as $scope_extra
    | if $scope_extra != [] then fail("scope-service") else . end
    | if (.scope.hyprlock | type) != "boolean" then fail("hyprlock") else . end
    | if (.scope.sudo | type) != "boolean" then fail("sudo") else . end
    | if (.sudo_cache_seconds | intin(1; 900) | not) then fail("sudo-cache") else . end
    | if (.suspend_max_seconds | intin(0; 86400) | not) then fail("suspend") else . end
    | if (.deny | intin(3; 10) | not) then fail("deny") else . end
    | if (.fail_interval | intin(60; 86400) | not) then fail("fail-interval") else . end
    | if (.unlock_time | intin(60; 86400) | not) then fail("unlock-time") else . end
    | if (.allow_unencrypted_models | type) != "boolean" then fail("unencrypted-flag") else . end
    | if (.device_path | type) != "string" then fail("device-path") else . end
    | if (.device_path != "" and ((.device_path | test("^/dev/v4l/by-(path|id)/[^[:space:]]+$")) | not)) then fail("device-path") else . end
    | if (.device_path | contains("..")) then fail("device-path") else . end
    | {
        schema: 1,
        scope: {hyprlock: .scope.hyprlock, sudo: .scope.sudo},
        sudo_cache_seconds: .sudo_cache_seconds,
        suspend_max_seconds: .suspend_max_seconds,
        deny: .deny,
        fail_interval: .fail_interval,
        unlock_time: .unlock_time,
        allow_unencrypted_models: .allow_unencrypted_models,
        device_path: .device_path
      }
  ' <<<"$raw"
}

# Merge defaults (a file) with an overlay object. `enabled` is not a policy field.
face_auth_policy_merge() {
  local defaults="$1" overlay="$2"
  jq -ce --argjson over "$overlay" '
    del(.enabled) as $d
    | ($over | del(.enabled)) as $o
    | ($d * $o)
    | .scope = (($d.scope // {}) * ($o.scope // {}))
  ' "$defaults"
}
