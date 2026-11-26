# SPDX-License-Identifier: Apache-2.0
"""Offline preflight for the draft MartyGraphics core scene v1 schema."""

import argparse
import json
import math
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "docs/schemas/scene-v1.draft.schema.json").read_text(encoding="utf-8"))
SCENE_BYTES = 8192
INPUT_BYTES = 2 * SCENE_BYTES
KNOWN_TEMPLATES = {"bst", "two_pointers", "shortest_path"}


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
        "integer": lambda: number(value) and int(value) == value,
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
    if isinstance(value, str) and "pattern" in rule and not re.search(rule["pattern"], value):
        raise ShapeError(path, "pattern")
    if number(value) and (
        value < rule.get("minimum", -math.inf) or value > rule.get("maximum", math.inf)
        or value <= rule.get("exclusiveMinimum", -math.inf) or value >= rule.get("exclusiveMaximum", math.inf)
    ):
        raise ShapeError(path, "range")

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


def shape_reason(scene, error):
    path = error.path
    if not path:
        if error.keyword == "additionalProperties":
            return "scene.unknown." + ",".join(error.keys)
        if error.keyword == "required":
            return {"v": "scene.missing", "items": "scene.items.required", "params": "template.params"}[error.keys[0]]
        if "template" in scene:
            return "template.world"
        key = next(key for key in ("params", "hide", "over") if key in scene)
        return f"scene.{key}.without.template"
    field = path[0]
    if field == "v":
        return "scene.version"
    if field == "params":
        if len(path) > 1:
            return f"template.{path[1]}"
        if error.keyword == "additionalProperties":
            return "template.params.unknown"
        if error.keyword == "required":
            return f"template.{error.keys[0]}.missing"
        return "template.params"
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
                    return "vector.anchor" if ("from" in item) == ("on" in item) else "vector.dir"
                if error.keyword == "not":
                    return "vector.dir"
            if len(path) == 2 and error.keyword == "not" and kind == "text":
                return "3d.text.code"
            if len(path) > 2 and path[2] != "k":
                key = path[2]
                return f"item.{key}" if key in ("id", "color", "label") else f"{kind}.{key}"
            if len(path) == 2 and error.keyword in ("required", "additionalProperties"):
                suffix = "missing" if error.keyword == "required" else "unknown." + ",".join(error.keys)
                return f"item.{kind}.{suffix}"
        return "item.kind"
    if field == "items" and error.keyword == "length":
        return "items.count"
    if field == "steps" and len(path) > 2:
        return f"step.{path[2]}"
    return ".".join(part for part in path if isinstance(part, str))


def text_rules(value, reason, template, code=False):
    if not value.strip() or "://" in value or "\x60\x60\x60" in value:
        raise Invalid(reason)
    if any(unicodedata.category(char) in ("Cc", "Cf") and char != "\n" for char in value):
        raise Invalid(reason)
    if code:
        for index, char in enumerate(value[:-1]):
            next_char = value[index + 1]
            if char == "<" and (next_char.isalpha() or next_char in "/!?") and ">" in value[index + 2:]:
                raise Invalid(reason)
    elif "<" in value or ">" in value:
        raise Invalid(reason)
    remainder = re.sub(r"\{[A-Za-z0-9]{1,16}\}", "", value)
    if "{" in remainder or "}" in remainder:
        raise Invalid(reason + ".brace")
    if not template and remainder != value:
        raise Invalid(reason + ".placeholder")


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
            text_rules(item[key], f"{kind}.{key}", template, item.get("style") == "code")

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
        }
        for key, limit in upper.get(kind, {}).items():
            if key in item and item[key] > limit:
                raise Invalid(f"{kind}.{key}")

    if kind == "vector" and "dir" in item and math.hypot(*item["dir"]) <= .01:
        raise Invalid("vector.dir")
    if kind == "edge" and item["a"] == item["b"]:
        raise Invalid("edge.self")
    if kind == "plot":
        for key in ("xr", "yr"):
            if item[key][0] >= item[key][1]:
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
    for item in scene.get("items", ()):
        item_rules(item, dimensions, template)
        if item["id"] in items:
            raise Invalid("id.duplicate." + item["id"])
        items[item["id"]] = item
    if "title" in scene:
        text_rules(scene["title"], "title", template)
    camera_rules(scene.get("camera", {}), dimensions)
    references(items, template)
    for step in scene.get("steps", ()):
        text_rules(step["say"], "step.say", template)
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
                raise Invalid("edit.key." + key)
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


def check(data):
    """Check UTF-8 scene bytes. Return the template name if expansion is deferred."""
    if len(data) > INPUT_BYTES:
        raise Invalid("input.too-large")

    def refuse_constant(_):
        raise Invalid("json")

    try:
        scene = json.loads(data.decode("utf-8-sig"), parse_constant=refuse_constant)
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Invalid("json") from error
    if not isinstance(scene, (dict, list)):
        raise Invalid("json")
    if isinstance(scene, list):
        raise Invalid("scene.object")
    pending = [(scene, 0)]
    while pending:
        value, depth = pending.pop()
        if isinstance(value, (list, dict)):
            if depth >= 64:
                raise Invalid("scene.depth")
            children = value.values() if isinstance(value, dict) else value
            pending.extend((child, depth + 1) for child in children)
        elif isinstance(value, float) and not math.isfinite(value):
            raise Invalid("scene.number")
    try:
        canonical = json.dumps(scene, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    except UnicodeError as error:
        raise Invalid("json") from error
    if len(canonical) > SCENE_BYTES:
        raise Invalid("scene.bytes")
    try:
        shape(scene, SCHEMA)
    except ShapeError as error:
        raise Invalid(shape_reason(scene, error)) from error
    template = scene.get("template")
    if template is not None and template not in KNOWN_TEMPLATES:
        raise Invalid("template.unknown")
    if template:
        template_rules(template, scene["params"], scene.get("dim", "2d"))
    scene_rules(scene)
    return template


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="path to a UTF-8 scene JSON file")
    path = parser.parse_args().path
    try:
        if not path.is_file():
            raise OSError("expected a regular file")
        with path.open("rb") as stream:
            template = check(stream.read(INPUT_BYTES + 1))
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
