# SPDX-License-Identifier: Apache-2.0
"""Run the draft scene v1 preflight (tools/scene_v1_check.py on feat/scene-v1-json-schema) over many inputs.

Usage: python -I python_checker_driver.py CHECKER_PY MANIFEST_JSON
The manifest lists {"name", "file", "packs"} entries; one JSON object per input is printed to stdout.
"""

import importlib.util
import json
import sys


def main():
    checker_path, manifest_path = sys.argv[1:3]
    spec = importlib.util.spec_from_file_location("scene_v1_check", checker_path)
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    with open(manifest_path, encoding="utf-8") as stream:
        manifest = json.load(stream)
    results = {}
    for entry in manifest:
        with open(entry["file"], "rb") as stream:
            # The CLI reads INPUT_BYTES + 1 bytes at most; read the same way.
            data = stream.read(checker.INPUT_BYTES + 1)
        try:
            template = checker.check(data, packs=tuple(entry["packs"]))
            results[entry["name"]] = {"status": "pass-deferred" if template else "pass", "template": template}
        except checker.Invalid as error:
            results[entry["name"]] = {"status": "fail", "reason": str(error)}
    json.dump(results, sys.stdout, sort_keys=True)


if __name__ == "__main__":
    main()
