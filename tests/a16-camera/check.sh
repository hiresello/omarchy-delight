#!/usr/bin/env bash

# The series, the manifest, and the patch files agree.
# Does not download or compile a kernel.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
DIR=$ROOT/kernel/a16-camera

python3 - "$DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text())
series = []
for raw in (root / "series").read_text().splitlines():
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    parts = line.split()
    path = root / parts[0]
    if not path.is_file():
        raise SystemExit(f"series entry missing: {parts[0]}")
    if "diff --git " not in path.read_text(errors="replace"):
        raise SystemExit(f"not a diff: {parts[0]}")
    series.append(parts[0])
    if len(parts) > 1 and parts[1] != "board":
        raise SystemExit(f"unknown series tag: {parts[1]}")

applied = [item["file"] for item in manifest["patches"]]
if applied != series:
    raise SystemExit("manifest apply order does not match series")

for group in ("patches", "not_applied", "optional"):
    for item in manifest[group]:
        path = root / item["file"]
        if not path.is_file():
            raise SystemExit(f"manifest file missing: {item['file']}")
        for key in ("source_url", "author", "version", "review_status", "apply"):
            if not str(item.get(key, "")).strip():
                raise SystemExit(f"{item['file']} missing {key}")

not_applied = {item["file"] for item in manifest["not_applied"]}
if not_applied & set(series):
    raise SystemExit("a not-applied patch is in the default series")

optional = {item["file"] for item in manifest["optional"]}
if optional & set(series):
    raise SystemExit("an optional patch is in the default series")

base = manifest["base"]
if base["tarball_sha256"] not in (root / "build.sh").read_text():
    raise SystemExit("build.sh sha256 does not match the manifest")
if "87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953" not in (root / "PKGBUILD").read_text():
    raise SystemExit("PKGBUILD sha256 does not match")
print(f"a16 camera recipe: {len(series)} patches, manifest matches series")
PY
