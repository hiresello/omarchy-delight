#!/bin/bash

# Run the CI job locally in archlinux:latest (needs Docker).

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

docker run --rm -v "$PWD:/src:ro" archlinux:latest bash -euc '
  pacman -Syu --noconfirm --needed bash jq git shellcheck shfmt qt6-declarative quickshell \
    python python-jsonschema util-linux diffutils findutils sudo >/dev/null
  git clone -q --depth 1 https://github.com/omacom/omarchy.git /tmp/omarchy
  useradd -m tester
  cp -r /src /work && chown -R tester /work && cd /work
  ci/lint-shell.sh
  ci/lint-qml.sh /tmp/omarchy
  ci/validate-json.py
  ci/validate-plugins.sh /tmp/omarchy
  sudo -u tester env PATH="$PATH" tests/run
'
