#!/bin/bash

# Run shellcheck and shfmt over every Bash file.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

mapfile -t files < <(ci/shell-files.sh)
echo "linting ${#files[@]} shell files"
shellcheck -x -P SCRIPTDIR -s bash "${files[@]}"
shfmt -d -i 2 -ci -bn "${files[@]}"
