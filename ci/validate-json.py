#!/usr/bin/env python3
"""Validate Delight JSON against its schemas (CI-only; the runtime never needs Python).

  ci/validate-json.py                      validate every fixture, manifest and default in the repo
  ci/validate-json.py --schema S FILE...   validate FILEs against schema S
"""

import json
import pathlib
import sys

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schema"


def registry():
    resources = []
    for path in SCHEMA_DIR.glob("*.schema.json"):
        schema = json.loads(path.read_text())
        resource = Resource.from_contents(schema)
        resources.append((schema["$id"], resource))
        resources.append((path.name, resource))
    return Registry().with_resources(resources)


REGISTRY = registry()


def errors(schema_path, data_path):
    schema = json.loads(pathlib.Path(schema_path).read_text())
    Draft202012Validator.check_schema(schema)
    try:
        data = json.loads(pathlib.Path(data_path).read_text())
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"]
    validator = Draft202012Validator(schema, registry=REGISTRY, format_checker=Draft202012Validator.FORMAT_CHECKER)
    return [f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}" for e in validator.iter_errors(data)]


def check(schema, path, expect_valid=True):
    found = errors(schema, path)
    rel = pathlib.Path(path).resolve()
    try:
        rel = rel.relative_to(ROOT)
    except ValueError:
        pass
    if expect_valid and found:
        print(f"FAIL {rel}:\n  " + "\n  ".join(found))
        return False
    if not expect_valid and not found:
        print(f"FAIL {rel}: expected to be invalid against {pathlib.Path(schema).name}")
        return False
    print(f"ok   {rel}")
    return True


def validate_repo():
    ok = True
    for schema in sorted(SCHEMA_DIR.glob("*.schema.json")):
        name = schema.name.removesuffix(".schema.json")
        fixtures = SCHEMA_DIR / "fixtures" / name
        valid = sorted((fixtures / "valid").glob("*.json"))
        invalid = sorted((fixtures / "invalid").glob("*.json"))
        if not valid or not invalid:
            print(f"FAIL schema/{schema.name}: needs valid and invalid fixtures in schema/fixtures/{name}/")
            ok = False
        ok &= all([check(schema, f) for f in valid])
        ok &= all([check(schema, f, expect_valid=False) for f in invalid])
    module_schema = SCHEMA_DIR / "module.schema.json"
    manifests = sorted(ROOT.glob("modules/*/module.json")) + [ROOT / "templates/module/module.json"]
    ok &= all([check(module_schema, m) for m in manifests])
    for path in sorted(ROOT.rglob("*.json")):
        if ".git" in path.parts:
            continue
        try:
            json.loads(path.read_text())
        except json.JSONDecodeError as e:
            print(f"FAIL {path.relative_to(ROOT)}: invalid JSON: {e}")
            ok = False
    return ok


def main(argv):
    if len(argv) >= 3 and argv[0] == "--schema":
        return 0 if all([check(argv[1], f) for f in argv[2:]]) else 1
    if argv:
        print(__doc__)
        return 64
    return 0 if validate_repo() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
