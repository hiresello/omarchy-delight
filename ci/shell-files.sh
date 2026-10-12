#!/bin/bash

# Print every Bash file in the repo, one per line.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

{
  find . -path ./.git -prune -o -type f \( -name '*.sh' -o -path './bin/*' -o -path '*/modules/*/bin/*' -o -path './templates/module/bin/*' -path './vm/*' -o -path './tests/contract/*' -o -name run -o -name _stub \) -print
  echo ./install.sh
  echo ./uninstall.sh
} | sed 's|^\./||' | sort -u | while IFS= read -r f; do
  head -1 "$f" | grep -q '^#!.*bash' && echo "$f"
done
