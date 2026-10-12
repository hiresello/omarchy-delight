#!/bin/bash

# Format, lint and test delightd (daemon/).

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../daemon"

cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
