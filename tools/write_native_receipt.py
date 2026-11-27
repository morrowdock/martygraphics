# SPDX-License-Identifier: Apache-2.0
"""Run the native checks of docs/VERIFY-ON-MAC.md for every package of a clean checkout and write the v1 native
receipt {"source", "packages": [{"path", "exit"}]} to a new path outside the checkout.

The packages come from validate_local.native_packages, the same discovery that checks receipt reuse. Each package
records the exit code of its first failing command, or 0 when all its commands pass. Exits non-zero when any
package failed."""

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("validate_local_for_native_receipt", Path(__file__).with_name("validate_local.py"))
validate_local = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate_local)


def run_package(commands, root, run):
    """The exit code of the first command that fails, or 0. A command that cannot start counts as 127."""
    for command in commands:
        try:
            code = run(command, cwd=root).returncode
        except OSError as error:
            print("Cannot run %s: %s" % (command[0], error), file=sys.stderr)
            code = 127
        if code != 0:
            return code
    return 0


def checkout_state(root):
    head = validate_local.git("rev-parse", "HEAD", cwd=root).decode().strip()
    return head, validate_local.git("status", "--porcelain", "--untracked-files=all", cwd=root).strip()


def main(argv=None, root=None, run=subprocess.run):
    root = Path(root or ROOT).resolve()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="NEW absolute JSON path outside the checkout")
    args = parser.parse_args(argv)
    if not args.receipt.is_absolute():
        parser.error("Give the native receipt as an absolute path")
    receipt_path = args.receipt.resolve()
    if receipt_path.is_relative_to(root) or receipt_path.exists():
        parser.error("Native receipt must be a new path outside the checkout")
    head, dirty = checkout_state(root)
    if dirty:
        parser.error("Checkout must be clean, including untracked files")
    commands = validate_local.head_scope(head, root)
    packages = []
    for package, package_commands in commands.items():
        print("== %s: %s" % (package, " && ".join(" ".join(c) for c in package_commands)), flush=True)
        packages.append({"path": package, "exit": run_package(package_commands, root, run)})
    if checkout_state(root) != (head, b""):
        parser.error("The native checks changed the checkout (HEAD or `git status --porcelain`); no receipt written")
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    with receipt_path.open("x", encoding="utf-8") as stream:
        json.dump({"source": head, "packages": packages}, stream, indent=2)
        stream.write("\n")
    failed = [p["path"] for p in packages if p["exit"] != 0]
    print("Native receipt:", receipt_path)
    if failed:
        print("Failed packages:", ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
