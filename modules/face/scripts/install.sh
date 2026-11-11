#!/bin/bash

# Install the Arch packages for the IR face bridge and the Delight module.
# Repo packages come from module.json; howdy-next comes from the AUR.
# This does not edit PAM, the kernel, or the device tree.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/../../.." && pwd)

printf '%s\n' "Installing Arch packages for the IR face bridge:"
jq -r '.packages.repo[], .packages.aur[]' "$ROOT/modules/face/module.json"

exec "$ROOT/bin/delight" face install
