# SPDX-License-Identifier: Apache-2.0
"""Print the structural grammar that `MGGrammar.document()` returns, mirrored from the Swift tables.

This host has no Swift toolchain, so the eval's baseline guidance uses this mirror. The tables below copy
`MGParser.topKeys`, `MGParser.allowedKeys(_:)`, `MGParser.required(_:)`, `MGKind.allCases`,
`MGColorRole.allCases`, the built-in templates and `MGLimits` at main 5e4952e. `test_grammar_doc` checks the
kind tables against the copied scene v1 draft schema.
"""

import json
import sys

TOP_KEYS = ["v", "template", "params", "title", "dim", "world", "items", "steps", "camera", "hide", "over"]
COMMON = ["id", "k", "color"]
KINDS = [
    ("body", ["at", "shape", "size", "angle", "label", "move"], ["at"]),
    ("incline", ["at", "base", "angle", "label"], ["at", "base", "angle"]),
    ("line", ["from", "to", "style"], ["from", "to"]),
    ("vector", ["from", "on", "angle", "dir", "len", "label", "dashed"], ["len"]),
    ("axes", ["at", "w", "h", "xl", "yl"], ["at", "w", "h"]),
    ("plot", ["at", "w", "h", "xr", "yr", "pts", "xl", "yl", "label"], ["at", "w", "h", "xr", "yr", "pts"]),
    ("spring", ["from", "to", "coils", "label"], ["from", "to"]),
    ("pulley", ["at", "r"], ["at", "r"]),
    ("rope", ["pts"], ["pts"]),
    ("orbit", ["at", "r", "label"], ["at", "r"]),
    ("text", ["at", "text", "style"], ["at", "text"]),
    ("highlight", ["target", "label"], ["target"]),
    ("bars", ["at", "w", "h", "bars", "unit", "label"], ["at", "w", "h", "bars"]),
    ("path", ["pts", "dashed"], ["pts"]),
    ("array", ["at", "vals", "cell", "ptrs", "marked", "label"], ["at", "vals"]),
    ("node", ["at", "text", "r"], ["at", "text"]),
    ("edge", ["a", "b", "dir", "label"], ["a", "b"]),
    ("table", ["at", "cells", "header", "cw", "rh", "marked", "label"], ["at", "cells"]),
    ("region", ["pts", "dashed", "label"], ["pts"]),
]
COLORS = ["force", "normal", "friction", "gravity", "tension", "velocity", "accel", "energy", "kinetic", "potential",
          "accent", "muted", "good", "warn", "blue", "red", "green", "orange", "purple", "yellow", "teal", "white"]
TEMPLATES = [{"name": "bst", "parameters": ["values", "find"]},
             {"name": "two_pointers", "parameters": ["vals", "target"]}]
LIMITS = {"sceneBytes": 8192, "patchBytes": 4096, "items": 24, "steps": 8, "templateSteps": 48}


def document():
    return {
        "version": 1,
        "sceneKeys": sorted(TOP_KEYS),
        "kinds": [{"name": name, "allowedKeys": sorted(set(COMMON) | set(extra)),
                   "requiredKeys": sorted(set(required) | {"id", "k"})} for name, extra, required in KINDS],
        "colors": COLORS,
        "templates": TEMPLATES,
        "limits": LIMITS,
    }


if __name__ == "__main__":
    json.dump(document(), sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
