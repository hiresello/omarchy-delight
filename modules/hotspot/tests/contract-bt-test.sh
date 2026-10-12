#!/bin/bash

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/test-lib"

hotspot_test_init
hotspot_nm_fixture
hotspot_bt_fixture
ok "hotspot module passes the contract with Bluetooth sysfs and module stubs" \
  "$DELIGHT_TEST_REPO/tests/contract/check-module" "$DELIGHT_TEST_REPO" hotspot

done_testing
