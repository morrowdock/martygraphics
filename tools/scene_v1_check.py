# SPDX-License-Identifier: Apache-2.0
"""Offline preflight for the draft MartyGraphics core scene v1 schema."""

import argparse
import json
import math
import os
from pathlib import Path
import re
import stat
import unicodedata

try:
    from tools import mg_expr
except ImportError:  # run as tools/scene_v1_check.py
    import mg_expr

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "docs/schemas/scene-v1.draft.schema.json").read_text(encoding="utf-8"))
ENVELOPE = {
    "required": SCHEMA["required"],
    "additionalProperties": SCHEMA["additionalProperties"],
    "properties": {key: rule if key in ("v", "dim") else {} for key, rule in SCHEMA["properties"].items()},
}
SCENE_BYTES = 8192
INPUT_BYTES = 2 * SCENE_BYTES
MIN_PLOT_SPAN = 1e-6
KNOWN_TEMPLATES = {"bst", "two_pointers"}
PACK_TEMPLATES = {"graphs": {"shortest_path"}}


class Invalid(ValueError):
    """A draft diagnostic in the corresponding Swift reason family."""


class ShapeError(ValueError):
    def __init__(self, path, keyword, keys=()):
        self.path = path
        self.keyword = keyword
        self.keys = keys


def number(value):
    return type(value) in (int, float)


def json_equal(left, right):
    return left == right and (type(left) is type(right) or number(left) and number(right))


def shape(value, rule, path=()):
    """Evaluate the schema keywords used by this repository's draft."""
    if rule is False:
        raise ShapeError(path, "false")
    if rule is True:
        return
    if "$ref" in rule:
        shape(value, SCHEMA["$defs"][rule["$ref"].removeprefix("#/$defs/")], path)
    types = {
        "object": lambda: isinstance(value, dict),
        "array": lambda: isinstance(value, list),
        "string": lambda: isinstance(value, str),
        "number": lambda: number(value),
        "integer": lambda: number(value),
        "boolean": lambda: isinstance(value, bool),
    }
    if "type" in rule and not types[rule["type"]]():
        raise ShapeError(path, "type")
    if "const" in rule and not json_equal(value, rule["const"]):
        raise ShapeError(path, "const")
    if "enum" in rule and not any(json_equal(value, entry) for entry in rule["enum"]):
        raise ShapeError(path, "enum")

    if isinstance(value, dict):
        properties = rule.get("properties", {})
        missing = sorted(set(rule.get("required", ())) - value.keys())
        if missing:
            raise ShapeError(path, "required", missing)
        unknown = sorted(value.keys() - properties.keys())
        if rule.get("additionalProperties") is False and unknown:
            raise ShapeError(path, "additionalProperties", unknown)
        for key, child in properties.items():
            if key in value:
                shape(value[key], child, (*path, key))
    if isinstance(value, (list, str)):
        low, high = ("minItems", "maxItems") if isinstance(value, list) else ("minLength", "maxLength")
        if len(value) < rule.get(low, 0) or len(value) > rule.get(high, math.inf):
            raise ShapeError(path, "length")
    if isinstance(value, list):
        prefix = rule.get("prefixItems", ())
        for index, entry in enumerate(value):
            shape(entry, prefix[index] if index < len(prefix) else rule.get("items", True), (*path, index))
    if isinstance(value, str) and "pattern" in rule:
        pattern = rule["pattern"]
        if pattern.endswith("$"):
            pattern = pattern[:-1] + r"\Z"
        if not re.search(pattern, value):
            raise ShapeError(path, "pattern")
    if number(value) and (
        value < rule.get("minimum", -math.inf) or value > rule.get("maximum", math.inf)
        or value <= rule.get("exclusiveMinimum", -math.inf) or value >= rule.get("exclusiveMaximum", math.inf)
    ):
        raise ShapeError(path, "range")
    if rule.get("type") == "integer" and int(value) != value:
        raise ShapeError(path, "integer")

    # Selecting the item branch by its required discriminator preserves its field diagnostic.
    if rule is SCHEMA["$defs"]["item"]:
        kind = value.get("k") if isinstance(value, dict) else None
        if not isinstance(kind, str) or {"$ref": f"#/$defs/{kind}"} not in rule["oneOf"]:
            raise ShapeError((*path, "k"), "enum")
        shape(value, SCHEMA["$defs"][kind], path)
        return
    for child in rule.get("allOf", ()):
        shape(value, child, path)
    if "anyOf" in rule and not any(matches(value, child) for child in rule["anyOf"]):
        raise ShapeError(path, "anyOf")
    if "oneOf" in rule and sum(matches(value, child) for child in rule["oneOf"]) != 1:
        raise ShapeError(path, "oneOf")
    if "not" in rule and matches(value, rule["not"]):
        raise ShapeError(path, "not")
    if "if" in rule:
        branch = "then" if matches(value, rule["if"]) else "else"
        shape(value, rule.get(branch, True), path)


def matches(value, rule):
    try:
        shape(value, rule)
    except ShapeError:
        return False
    return True


def reason_keys(keys):
    return ",".join(key if re.fullmatch(r"[A-Za-z0-9_]{1,24}", key) else "?" for key in keys[:4])


def closed_reason(name, error):
    if error.keyword == "required":
        return name + ".missing"
    if error.keyword == "additionalProperties":
        return name + ".unknown." + reason_keys(error.keys)
    return name


def parameter_reason(scene, path, error):
    if len(path) == 1:
        if error.keyword == "additionalProperties":
            return "template.params.unknown"
        if error.keyword != "required":
            return "template.params"
        name = error.keys[0]
        suffix = "" if name in ("values", "vals") else ".missing"
        return f"template.{name}{suffix}"

    name = path[1]
    reason = f"template.{name}"
    if scene.get("template") == "shortest_path" and name in ("edges", "at"):
        if len(path) == 2 and error.keyword == "length":
            return reason + ".count"
        if len(path) == 3 or error.keyword == "false":
            return reason + ".arity"
        if len(path) == 4:
            fields = ("a", "b", "w") if name == "edges" else ("x", "y")
            reason += "." + fields[path[3]]
    if error.keyword == "integer":
        reason += ".integer"
    return reason


def shape_reason(scene, error):
    path = error.path
    if not path:
        if error.keyword == "additionalProperties":
            return "scene.unknown." + reason_keys(error.keys)
        if error.keyword == "required":
            return {"v": "scene.missing", "items": "scene.items.required", "params": "template.params"}[error.keys[0]]
    field = path[0]
    if field == "v":
        return "scene.version"
    if field == "params":
        return parameter_reason(scene, path, error)
    if field in ("dim", "template"):
        return {"dim": "scene.dim", "template": "template.unknown"}[field]
    if field == "items" and len(path) > 1:
        item = scene["items"][path[1]]
        if isinstance(item, dict) and isinstance(item.get("k"), str):
            kind = item["k"]
            if path[2:] == ("k",) and {"$ref": f"#/$defs/{kind}"} in SCHEMA["$defs"]["item"]["oneOf"]:
                return f"3d.kind.{kind}"
            if len(path) == 2 and kind == "vector":
                if error.keyword == "oneOf":
                    if ("from" in item) == ("on" in item):
                        return "vector.anchor"
                    return "vector.dir" if "dir" in item else "vector.angle"
                if error.keyword == "not":
                    return "vector.dir"
            if len(path) == 2 and error.keyword == "not" and kind == "text":
                return "3d.text.code"
            if len(path) > 2 and path[2] != "k":
                key = path[2]
                if kind == "array" and key == "vals" and len(path) > 3:
                    return "array.val"
                if kind == "table" and key == "cells" and len(path) > 4:
                    return "table.cell"
                if (kind, key) in (("bars", "bars"), ("array", "ptrs")) and len(path) > 3:
                    entry = "bars.bar" if kind == "bars" else "array.ptr"
                    if len(path) == 4:
                        return closed_reason(entry, error)
                    prefix = "bars" if kind == "bars" else entry
                    return f"{prefix}.{path[4]}"
                return f"item.{key}" if key in ("id", "color", "label") else f"{kind}.{key}"
            if len(path) == 2 and error.keyword in ("required", "additionalProperties"):
                return closed_reason(f"item.{kind}", error)
        return "item.kind"
    if field == "items" and error.keyword == "length":
        return "items.count"
    if field == "world" and len(path) == 1:
        return closed_reason("world", error)
    if path[:1] == ("over",) and len(path) == 3 and path[-1] == "key":
        return "edit.key"
    if field == "steps" and len(path) > 2:
        if len(path) == 5 and path[2] == "do" and path[-1] == "key":
            return "edit.key"
        return f"step.{path[2]}"
    return ".".join(part for part in path if isinstance(part, str))


def text_rules(value, reason, template, *, code=False, multiline=False):
    if not value.strip() or "://" in value or "\x60\x60\x60" in value:
        raise Invalid(reason)
    if any(unicodedata.category(char) in ("Cc", "Cf", "Zl", "Zp")
           and not (multiline and char == "\n") for char in value):
        raise Invalid(reason)
    if code:
        for index, char in enumerate(value[:-1]):
            next_char = value[index + 1]
            if char == "<" and (next_char.isalpha() or next_char in "/!?") and ">" in value[index + 2:]:
                raise Invalid(reason)
    elif "<" in value or ">" in value:
        raise Invalid(reason)
    name = None
    for char in value:
        if name is not None:
            if char == "}":
                if not template:
                    raise Invalid(f"{reason}.placeholder.{name}")
                name = None
            elif char.isascii() and char.isalnum() and len(name) < 16:
                name += char
            else:
                raise Invalid(reason + ".placeholder")
        elif char == "{":
            name = ""
        elif char == "}":
            raise Invalid(reason + ".brace")
    if name is not None:
        raise Invalid(reason + ".brace")


def cell_text(value, limit, reason, template, allow_empty=False):
    if isinstance(value, str):
        if value or not allow_empty:
            text_rules(value, reason, template)
        return
    magnitude = abs(value)
    digits = 0 if magnitude >= 100 else 1 if magnitude >= 10 else 2
    shown = f"{value:.{digits}f}"
    if "." in shown:
        shown = shown.rstrip("0").rstrip(".")
    if shown != "-0" and len(shown) > limit:
        raise Invalid(reason)


def spatial(point, dimensions, reason):
    width, height = dimensions
    bounds = [(-.25 * width, 1.25 * width), (-.25 * height, 1.25 * height), (-max(dimensions), max(dimensions))]
    if any(not low <= coordinate <= high for coordinate, (low, high) in zip(point, bounds)):
        raise Invalid(reason)


def camera_rules(camera, dimensions):
    if dimensions:
        for axis, limit in zip(("x", "y"), dimensions):
            if axis in camera and camera[axis] > limit:
                raise Invalid(f"camera.{axis}")


def item_rules(item, dimensions, template):
    kind = item["k"]
    if "label" in item:
        text_rules(item["label"], "item.label", template)
    for key in ("xl", "yl", "unit", "text"):
        if key in item:
            multiline = kind == "text" and key == "text"
            text_rules(item[key], f"{kind}.{key}", template,
                       code=multiline and item.get("style") == "code", multiline=multiline)

    if dimensions:
        span = max(dimensions)
        for key in ("at", "from", "to"):
            if key in item:
                spatial(item[key], dimensions, f"{kind}.{key}")
        if "move" in item:
            spatial(item["move"]["to"], dimensions, "body.move.to")
        if kind in ("rope", "path", "region"):
            for point in item["pts"]:
                spatial(point, dimensions, f"{kind}.pts")
        upper = {
            "body": {"size": span / 2},
            "incline": {"base": 1.25 * dimensions[0]},
            "vector": {"len": span},
            "axes": {"w": 1.25 * span, "h": 1.25 * span},
            "plot": {"w": 1.25 * span, "h": 1.25 * span},
            "bars": {"w": 1.25 * span, "h": 1.25 * span},
            "pulley": {"r": span / 4},
            "orbit": {"r": span / 2},
            "node": {"r": span / 6},
            "array": {"cell": span / 4},
            "table": {"cw": span / 3, "rh": span / 6},
            "func": {"w": 1.25 * span, "h": 1.25 * span},
            "field": {"w": 1.25 * span, "h": 1.25 * span},
        }
        for key, limit in upper.get(kind, {}).items():
            if key in item and item[key] > limit:
                raise Invalid(f"{kind}.{key}")
        if kind in ("func", "field"):
            # The sampling, expression and drawing rules mirrored in tools/mg_expr.py. A template scene's world
            # is known only after Swift expands it, so these rules run for literal scenes only.
            try:
                mg_expr.check_graph_item(item, dimensions)
            except mg_expr.Refusal as refusal:
                raise Invalid(refusal.reason) from refusal

    if kind == "vector" and "dir" in item and math.hypot(*item["dir"]) <= .01:
        raise Invalid("vector.dir")
    if kind == "edge" and item["a"] == item["b"]:
        raise Invalid("edge.self")
    if kind == "plot":
        for key in ("xr", "yr"):
            low, high = item[key]
            if high - low < MIN_PLOT_SPAN:
                raise Invalid(f"plot.{key}")
    if kind == "bars":
        for bar in item["bars"]:
            text_rules(bar["label"], "bars.label", template)
    if kind == "array":
        for cell in item["vals"]:
            cell_text(cell, 6, "array.val", template)
        for pointer in item.get("ptrs", ()):
            if pointer["i"] >= len(item["vals"]):
                raise Invalid("array.ptr.i")
            text_rules(pointer["label"], "array.ptr.label", template)
        if any(index >= len(item["vals"]) for index in item.get("marked", ())):
            raise Invalid("array.marked")
    if kind == "table":
        rows = item["cells"]
        columns = len(rows[0])
        for row in rows:
            if len(row) != columns:
                raise Invalid("table.cells")
            for cell in row:
                cell_text(cell, 12, "table.cell", template, allow_empty=True)
        marked = item.get("marked", ())
        if len(marked) > len(rows) * columns or any(r >= len(rows) or c >= columns for r, c in marked):
            raise Invalid("table.marked")


def references(items, template):
    for item in items.values():
        kind = item["k"]
        if kind == "vector" and "on" in item:
            target = items.get(item["on"])
            if (target is None and not template) or (target and target["k"] not in ("body", "node")):
                raise Invalid("vector.on")
        if kind == "edge":
            for key in ("a", "b"):
                target = items.get(item[key])
                if (target is None and not template) or (target and target["k"] != "node"):
                    raise Invalid("edge.nodes")
        if kind == "highlight" and (
            item["target"] == item["id"] or (item["target"] not in items and not template)
        ):
            raise Invalid("highlight.target")
    for identifier in items:
        visited = set()
        current = identifier
        while current in items and items[current]["k"] == "highlight":
            if current in visited:
                raise Invalid("highlight.cycle")
            visited.add(current)
            current = items[current]["target"]


def template_rules(name, params, dimension):
    if name == "bst" and len(set(params["values"])) != len(params["values"]):
        raise Invalid("template.check")
    if name == "two_pointers" and params["vals"] != sorted(params["vals"]):
        raise Invalid("template.check")
    if name != "shortest_path":
        return
    n = params["n"]
    for key in ("source", "target"):
        if params.get(key, 0) >= n:
            raise Invalid(f"template.{key}.range")
    pairs = set()
    for a, b, _ in params["edges"]:
        if a >= n or b >= n:
            raise Invalid("template.edges.node")
        if a == b:
            raise Invalid("template.edges.loop")
        pair = (min(a, b), max(a, b))
        if pair in pairs:
            raise Invalid("template.edges.duplicate")
        pairs.add(pair)
    if params.get("at") and len(params["at"]) != n:
        raise Invalid("template.at.count")
    if dimension == "3d":
        raise Invalid("template.build")


def scene_rules(scene):
    template = scene.get("template")
    world = scene.get("world", {"w": 12, "h": 8})
    dimensions = None if template else (world["w"], world["h"])
    items = {}
    graphs = [item for item in scene.get("items", ()) if item["k"] in ("func", "field")]
    # Each graph item counts once and each step edit of one once more (Swift `MGLimits.exprItems`).
    if len(graphs) + mg_expr.graph_edits(scene, {item["id"] for item in graphs}) > mg_expr.EXPR_ITEMS:
        raise Invalid("items.expr")
    for item in scene.get("items", ()):
        item_rules(item, dimensions, template)
        if item["id"] in items:
            raise Invalid("id.duplicate." + item["id"])
        items[item["id"]] = item
    if "title" in scene:
        text_rules(scene["title"], "title", template)
    if "alt" in scene:
        text_rules(scene["alt"], "alt", template)
    camera_rules(scene.get("camera", {}), dimensions)
    references(items, template)
    for step in scene.get("steps", ()):
        text_rules(step["say"], "step.say", template, multiline=True)
        if "alt" in step:
            text_rules(step["alt"], "step.alt", template)
        camera_rules(step.get("cam", {}), dimensions)
        for ref in step.get("show", ()):
            if ref not in items and not template:
                raise Invalid("step.show")
        if "focus" in step and step["focus"] not in items and not template:
            raise Invalid("step.focus")
        for edit in step.get("do", ()):
            identifier, key = edit["id"], edit["key"]
            if identifier not in items:
                if template:
                    continue
                raise Invalid("edit.ref")
            current = items[identifier]
            if key not in SCHEMA["$defs"][current["k"]]["properties"]:
                raise Invalid("edit.key." + reason_keys((key,)))
            updated = {**current, key: edit["value"]}
            if current["k"] == "vector" and key in ("on", "from"):
                updated.pop("from" if key == "on" else "on", None)
            try:
                # Recheck the changed item in the dimensional branch of the scene schema.
                shape({"v": 1, "dim": scene.get("dim", "2d"), "items": [updated]}, SCHEMA)
            except ShapeError as error:
                raise Invalid(shape_reason({"dim": scene.get("dim"), "items": [updated]}, error)) from error
            item_rules(updated, dimensions, template)
            items[identifier] = updated
            references(items, template)


def check_depth(source):
    """Mirror Swift's UTF-8 text preflight before the JSON decoder recurses."""
    if "\x00" in source:
        raise Invalid("json")
    depth = 0
    in_string = escaped = False
    for char in source:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char in "{[":
            depth += 1
            if depth > 64:
                raise Invalid("scene.depth")
        elif char in "}]":
            depth -= 1


def unique_object(pairs):
    obj = dict(pairs)
    if len(obj) != len(pairs):
        raise Invalid("json")
    return obj


def scene_float(token):
    value = float(token)
    return int(value) if value.is_integer() else value


def check(data, *, packs=()):
    """Check UTF-8 scene bytes. Return the template name if expansion is deferred."""
    if len(data) > INPUT_BYTES:
        raise Invalid("input.too-large")

    def refuse_constant(_):
        raise Invalid("json")

    try:
        source = data.decode("utf-8")
    except UnicodeError as error:
        raise Invalid("json") from error
    check_depth(source)
    try:
        scene = json.loads(source, parse_constant=refuse_constant,
                           object_pairs_hook=unique_object, parse_float=scene_float)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Invalid("json") from error
    if not isinstance(scene, (dict, list)):
        raise Invalid("json")
    if isinstance(scene, list):
        raise Invalid("scene.object")
    pending = [scene]
    while pending:
        value = pending.pop()
        if isinstance(value, (list, dict)):
            pending.extend(value.values() if isinstance(value, dict) else value)
        elif isinstance(value, float) and not math.isfinite(value):
            raise Invalid("scene.number")
    try:
        canonical = json.dumps(scene, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    except UnicodeError as error:
        raise Invalid("json") from error
    if len(canonical) > SCENE_BYTES:
        raise Invalid("scene.bytes")
    # Check the root envelope before the registry, as Swift does.
    try:
        shape(scene, ENVELOPE)
    except ShapeError as error:
        raise Invalid(shape_reason(scene, error)) from error
    template = scene.get("template")
    if "template" in scene:
        known_templates = KNOWN_TEMPLATES.union(*(PACK_TEMPLATES[pack] for pack in packs))
        if not isinstance(template, str) or template not in known_templates:
            raise Invalid("template.unknown")
        if "world" in scene:
            raise Invalid("template.world")
    else:
        for key in ("params", "hide", "over"):
            if key in scene:
                raise Invalid(f"scene.{key}.without.template")
    try:
        shape(scene, SCHEMA)
    except ShapeError as error:
        raise Invalid(shape_reason(scene, error)) from error
    if template:
        template_rules(template, scene["params"], scene.get("dim", "2d"))
    scene_rules(scene)
    return template


def open_input(path, flags):
    return os.open(path, flags | getattr(os, "O_NONBLOCK", 0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="path to a UTF-8 scene JSON file")
    parser.add_argument("--pack", action="append", choices=PACK_TEMPLATES, default=[],
                        help="enable templates from an opt-in pack")
    args = parser.parse_args()
    path = args.path
    try:
        with open(path, "rb", opener=open_input) as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise OSError("expected a regular file")
            template = check(stream.read(INPUT_BYTES + 1), packs=args.pack)
    except OSError as error:
        print(f"{str(path)!a}: unreadable: {str(error)!a}")
        return 3
    except Invalid as error:
        print(f"{str(path)!a}: FAIL (draft): {str(error)!a}")
        return 1
    scope = f"; {template} expansion requires Swift" if template else ""
    print(f"{str(path)!a}: PASS (draft preflight{scope})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
