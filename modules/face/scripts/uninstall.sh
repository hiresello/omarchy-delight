#!/bin/bash

# Remove the IR face bridge and the Arch packages this module installed.
# Packages another Delight module still records are left in place.
# This does not edit PAM, the kernel, or the device tree.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/../../.." && pwd)

printf '%s\n' "Removing the IR face bridge and the Arch packages it installed:"
jq -r '.packages.repo[], .packages.aur[]' "$ROOT/modules/face/module.json"

exec "$ROOT/bin/delight" face uninstall
