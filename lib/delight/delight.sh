#!/bin/bash

# Omarchy Delight shared helpers. Source this file, not the individual parts:
#   source "$DELIGHT_ROOT/lib/delight/delight.sh"
# Changing anything here is a contract change (see docs/contracts.md).

[[ -n ${DELIGHT_LIB_LOADED:-} ]] && return 0
DELIGHT_LIB_LOADED=1

DELIGHT_ROOT=${DELIGHT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}
export DELIGHT_ROOT

DELIGHT_LIB_DIR="$DELIGHT_ROOT/lib/delight"
for delight_part in core state run pkg ufw unit status config notify hw qr blocks plugin module touchpoints; do
  # shellcheck source=/dev/null
  source "$DELIGHT_LIB_DIR/$delight_part.sh"
done
unset delight_part
