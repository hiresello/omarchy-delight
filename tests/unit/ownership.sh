#!/bin/bash

# ci/check-ownership.sh

# shellcheck source=../lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tap.sh"

check() {
  printf '%s\n' "${@:3}" | "$DELIGHT_TEST_REPO/ci/check-ownership.sh" "$1" "$2"
}

ok "non-track branches are unrestricted" check devin/x '[]' lib/delight/core.sh
ok "track may change its own module" check track/airplay '[]' modules/airplay/module.json modules/airplay/bin/delight-airplay
not_ok "track may not change another module" check track/airplay '[]' modules/share/module.json
not_ok "track may not change shared code" check track/airplay '[]' lib/delight/core.sh
ok "contract-change label allows shared code" check track/airplay '["contract-change"]' lib/delight/core.sh
ok "ui owns the Control Center and design doc" check track/ui '[]' plugins/control-center/ControlCenterPanel.qml qml/Delight/Tile.qml docs/design.md
ok "vm owns its workflow" check track/vm '[]' .github/workflows/vm.yml vm/run.sh
not_ok "unknown tracks fail" check track/nope '[]' x
not_ok "modules/share2 is not owned by share" check track/share '[]' modules/share2/x

done_testing
