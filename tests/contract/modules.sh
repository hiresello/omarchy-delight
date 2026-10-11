#!/bin/bash

# Contract tests for every module, plus templates/module copied unchanged to
# modules/example.

# shellcheck source=../lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tap.sh"

sandbox
root=$(repo_copy)
rm -rf "$root/modules/example"
cp -r "$root/templates/module" "$root/modules/example"

status=0
for manifest in "$root"/modules/*/module.json; do
  id=$(basename -- "$(dirname -- "$manifest")")
  echo "# module $id"
  bash "$root/tests/contract/check-module" "$root" "$id" | sed 's/^/    /'
  ((PIPESTATUS[0] == 0)) || status=1
done

ok "every module passes its contract test" test "$status" -eq 0
ok "delight dev new-module scaffolds a module" "$root/bin/delight" dev new-module scaffold-check
is "scaffolded module.json has the new id" "$(jq -r .id "$root/modules/scaffold-check/module.json")" "scaffold-check"
ok "scaffolded entry point is renamed" test -x "$root/modules/scaffold-check/bin/delight-scaffold-check"
ok "scaffolded module passes its contract test" bash "$root/tests/contract/check-module" "$root" scaffold-check
not_ok "new-module refuses an existing id" "$root/bin/delight" dev new-module scaffold-check
not_ok "new-module refuses a bad id" "$root/bin/delight" dev new-module Bad_Id

done_testing
