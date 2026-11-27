# SPDX-License-Identifier: Apache-2.0
"""Python mirror of the repair hints: `MGRepairHint.text(for:)` (scenes) and `MGMLReason.hint` (ML kit).

`marty-scene-validate --hints` prints the same text. `tools/tests/test_repair_hints.py` compares these tables
with the Swift sources and checks the outputs against the shared corpus (docs/fixtures/repair-hints/corpus.json),
which Swift tests assert too. A change to one side must be made on both, then `hint_corpus.py --write`.
"""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from grammar_doc import COMMON, KINDS  # noqa: E402

SCENE_HINTS = [
    ("json", "send one complete UTF-8 JSON object, at most 16384 raw bytes, without comments, trailing commas, NaN or Infinity"),
    ("input.too-large", "the file is over 16384 bytes; shorten text and remove items"),
    ("scene.object", "the top level must be one object such as {\"v\":1,\"items\":[...]}, not an array or a transport wrapper"),
    ("scene.number", "every number must be finite"),
    ("scene.depth", "nest at most 64 levels; real scenes nest 6 to 15"),
    ("scene.bytes", "compact JSON must fit 8192 bytes: shorten text, round numbers or remove items"),
    ("video2d.*", "opt-in layer2d video follows its own draft schema (docs/schemas/scene-2d-layer.draft.schema.json); fix the part the reason names"),
    ("scene.missing", "add \"v\": 1 at the top level"),
    ("scene.version", "set \"v\": 1"),
    ("scene.unknown.*", "remove unknown top-level keys; a scene allows v, title, dim, world, camera, items, steps, and template, params, hide, over for template scenes"),
    ("scene.dim", "dim is \"2d\" (the default) or \"3d\""),
    ("scene.items.required", "a scene without a template needs \"items\": a list of 1 to 24 items"),
    ("scene.*.without.template", "params, hide and over belong to template scenes only; remove them or add \"template\""),
    ("template.unknown", "built-in templates are bst and two_pointers; otherwise write the items yourself"),
    ("template.world", "a template scene takes its world from the template; remove \"world\""),
    ("template.build", "the template could not build a scene from these parameters; check them against its rules"),
    ("template.check", "bst values must be distinct; two_pointers vals must be sorted ascending"),
    ("template.params*", "params must be an object with only the template's parameters: bst takes values and find, two_pointers takes vals and target"),
    ("template.*.missing", "add the template parameter named in the reason"),
    ("template.*.integer", "this template parameter must be a whole number"),
    ("template.*", "check the template parameter named in the reason: its type, count and range (bst values: 1-15 distinct integers -999..999; two_pointers vals: 2-12 sorted integers)"),
    ("world*", "world is {\"w\": 2-100, \"h\": 2-100}; the default is 12 by 8"),
    ("items", "items must be a list"),
    ("items.count", "a scene has 1 to 24 items (a template scene 0 to 10 extra items)"),
    ("items.total", "at most 40 items after template expansion, and at least one"),
    ("item.kind", "each item needs \"k\": one of body, incline, line, vector, axes, plot, spring, pulley, rope, orbit, text, highlight, bars, path, array, node, edge, table, region"),
    ("item.id", "an id is 1-24 ASCII letters, digits or _, starting with a letter"),
    ("id.duplicate.*", "item ids must be unique; rename one of the two"),
    ("item.color", "color is one of force, normal, friction, gravity, tension, velocity, accel, energy, kinetic, potential, accent, muted, good, warn, blue, red, green, orange, purple, yellow, teal, white"),
    ("*.placeholder.*", "braces mark a template placeholder and this scene has no value with that name; remove the braces"),
    ("*.placeholder", "braces mark a template placeholder (ASCII letters and digits, up to 16); remove them from plain text"),
    ("*.brace", "unbalanced { or }; braces are template placeholders, so remove them from plain text"),
    ("item.label", "label: 1-40 characters of plain text only: no < or > (write the symbols ≤ ≥ → or words), no { } outside template placeholders, no URLs or code fences"),
    ("title", "title: 1-60 characters of plain text only: no < or > (write the symbols ≤ ≥ → or words), no { } outside template placeholders, no URLs or code fences"),
    ("3d.kind.*", "this kind is 2D only; in 3D use body, incline, line, vector, axes, orbit, text, highlight or path, or keep the scene 2D"),
    ("3d.text.code", "code text is 2D only; use plain text in 3D"),
    ("body.shape", "shape is \"box\" (the default) or \"ball\""),
    ("body.size", "size is 0.1 to half the world's larger side (box side or ball diameter)"),
    ("body.angle", "angle is -360 to 360 degrees, counter-clockwise"),
    ("body.move.t", "move.t is 0.3 to 10 seconds"),
    ("body.move*", "move is {\"to\": [x, y], \"t\": seconds}: a straight glide there and back, forever"),
    ("incline.base", "base is 0.5 to 1.25 times the world width"),
    ("incline.angle", "angle is 0 to 80 degrees; the slope rises from at (the bottom-left vertex) to the right"),
    ("line.style", "style is solid, dashed or ground"),
    ("vector.anchor", "give exactly one anchor: \"from\": [x, y] or \"on\": the id of a body or node"),
    ("vector.on", "on must name a body or node in this scene"),
    ("vector.dir", "dir is the 3D direction: in a \"dim\": \"3d\" scene remove angle and give [x, y, z], three numbers from -1 to 1 with length above 0.01; in 2D remove dir and use angle (degrees counter-clockwise: 0 right, 90 up, 270 down)"),
    ("vector.angle", "angle is -360 to 360 degrees counter-clockwise from +x: 0 right, 90 up, 180 left, 270 down"),
    ("vector.len", "len is 0 to the world's larger side, in world units"),
    ("plot.xr", "xr is [lo, hi] with lo < hi, both from -1e6 to 1e6"),
    ("plot.yr", "yr is [lo, hi] with lo < hi, both from -1e6 to 1e6"),
    ("plot.pts", "pts holds 2-64 data points, each [x, y] with both numbers from -1e6 to 1e6 (data units; points outside xr and yr are accepted and clipped)"),
    ("*.w", "w is 0.5 to 1.25 times the world's larger side"),
    ("*.h", "h is 0.5 to 1.25 times the world's larger side"),
    ("spring.coils", "coils is a whole number from 3 to 24"),
    ("pulley.r", "r is 0.05 to a quarter of the world's larger side"),
    ("orbit.r", "r is 0.1 to half the world's larger side"),
    ("rope.pts", "a rope has 2 to 6 points"),
    ("path.pts", "a path has 2 to 64 points"),
    ("region.pts", "a region has 3 to 64 points"),
    ("text.text", "text: 1-120 characters of plain text only: no < or > (write the symbols ≤ ≥ → or words), no { } outside template placeholders, no URLs or code fences; code-style text may use < and > in comparisons but not tags"),
    ("text.style", "style is label, callout, title or code"),
    ("highlight.target", "target must name another item in this scene, not the highlight itself"),
    ("highlight.cycle", "a chain of highlights must end at an item that is not a highlight"),
    ("bars.bars", "bars holds 1 to 6 bars"),
    ("bars.bar*", "each bar is {\"label\": text, \"value\": number} with an optional color"),
    ("bars.label", "a bar label is 1-16 characters of plain text"),
    ("bars.value", "a bar value is a finite number within -1e7..1e7"),
    ("bars.color", "a bar color is one of the item colors"),
    ("bars.unit", "unit is 1-8 characters of plain text"),
    ("array.vals", "vals holds 1 to 16 cells"),
    ("array.val", "a cell is 1-6 characters of text, or a number whose displayed text fits 6 characters"),
    ("array.cell", "cell is 0.3 to a quarter of the world's larger side"),
    ("array.ptrs", "ptrs holds at most 4 pointers"),
    ("array.ptr.i", "a pointer index is a whole number inside vals; when an edit shortens vals, edit ptrs first"),
    ("array.ptr.label", "a pointer label is 1-8 characters of plain text"),
    ("array.ptr*", "a pointer is {\"i\": index, \"label\": text}"),
    ("array.marked", "marked holds whole-number indices inside vals; when an edit shortens vals, edit marked first"),
    ("node.text", "node text is 1-8 characters of plain text"),
    ("node.r", "r is 0.2 to a sixth of the world's larger side"),
    ("edge.a", "a is the id of the edge's first node"),
    ("edge.b", "b is the id of the edge's second node"),
    ("edge.nodes", "an edge's a and b must name node items in this scene"),
    ("edge.self", "an edge joins two different nodes"),
    ("table.cells", "cells holds 1-8 rows of 1-6 cells, every row the same length"),
    ("table.cell", "a cell is up to 12 characters of plain text, an empty string, or a number below 1e6"),
    ("table.marked", "marked holds [row, column] pairs inside the table (row 0 is the first row)"),
    ("table.cw", "cw is 0.3 to a third of the world's larger side"),
    ("table.rh", "rh is 0.3 to a sixth of the world's larger side"),
    ("steps", "a scene has 1 to 8 steps"),
    ("step.say", "narration: 1-200 characters of plain text only: no < or > (write the symbols ≤ ≥ → or words), no { } outside template placeholders, no URLs or code fences"),
    ("step.show", "show lists at most 16 ids, each naming an item in this scene"),
    ("step.focus", "focus names one item in this scene"),
    ("step.do", "do holds 1 to 6 edits"),
    ("step*", "a step is {\"say\": text} with optional show, focus, cam and do"),
    ("camera.x", "camera x is 0 to the world width"),
    ("camera.y", "camera y is 0 to the world height"),
    ("camera.zoom", "zoom is 0.5 to 4"),
    ("camera*", "a camera has x, y, zoom, yaw (-180..180) and pitch (-89..89)"),
    ("edit.ref", "an edit's id must name an item in this scene"),
    ("edit.key.*", "that key is not a field of the edited item's kind"),
    ("edit.key", "an edit cannot change id or k"),
    ("edit*", "an edit is {\"id\": item id, \"key\": field, \"value\": new value}; the value replaces the whole field"),
    ("hide*", "hide lists at most 16 ids of the template's own items"),
    ("over*", "over lists at most 16 edits of the template's own items"),
    ("*.at", "a point is [x, y] ([x, y, z] in 3D) with x from -0.25·w to 1.25·w and y from -0.25·h to 1.25·h of the world"),
    ("*.from", "a point is [x, y] ([x, y, z] in 3D) with x from -0.25·w to 1.25·w and y from -0.25·h to 1.25·h of the world"),
    ("*.to", "a point is [x, y] ([x, y, z] in 3D) with x from -0.25·w to 1.25·w and y from -0.25·h to 1.25·h of the world"),
    ("*.pts", "a point is [x, y] ([x, y, z] in 3D) with x from -0.25·w to 1.25·w and y from -0.25·h to 1.25·h of the world"),
    ("*.dashed", "dashed is true or false"),
    ("*.header", "header is true or false"),
    ("*.dir", "dir is true or false"),
    ("*.xl", "an axis label is 1-40 characters of plain text"),
    ("*.yl", "an axis label is 1-40 characters of plain text"),
]

ML_HINTS = {
    "ml.optIn": "pass the explicit ML kit opt-in (--ml-kit)",
    "ml.bytes": "the file must be at most 16384 bytes",
    "ml.json": "send one bounded UTF-8 JSON object",
    "ml.object": "the document, each item and each candidate must be a JSON object",
    "ml.unknown": "remove keys this object does not have; the location names the object",
    "ml.version": "set \"v\": 1",
    "ml.kind": "set \"kind\": \"ml-explainer\"",
    "ml.title": "title: 1-64 characters of plain single-line text, no < > or URLs",
    "ml.items": "items holds 1 to 4 items",
    "ml.item.kind": "kind is visionPipeline, nextTokenProbabilities, meaningMap, pictureToNumbers, generationLoop, attention or agentLoop",
    "ml.item.id": "an id is 1-24 ASCII letters, digits or _, starting with a letter",
    "ml.item.id.duplicate": "item ids must be unique",
    "ml.vision.caption": "caption: 1-100 characters of plain single-line text (required)",
    "ml.vision.citation": "a citation is 1-120 characters of plain single-line text",
    "ml.vision.size": "imageSize is [width, height] and patchSize one edge, whole numbers from 1 to 8192",
    "ml.vision.patch.division": "patchSize must divide both image sides exactly",
    "ml.vision.patch.count": "the patch grid allows at most 128 columns, 128 rows and 4096 patches; use a bigger patch",
    "ml.vision.embeddingWidth": "embeddingWidth is a whole number from 1 to 65536",
    "ml.vision.label": "a projector or language model label is 1-32 characters of plain text",
    "ml.vision.stageFocus": "stageFocus is true or false",
    "ml.tokens": "a token list holds 1-12 strings of 1-16 characters of plain text",
    "ml.prob.candidates": "candidates holds 2-8 objects {\"token\", \"logit\"} with distinct tokens of 1-16 characters",
    "ml.prob.logit": "a logit is a finite number within -1000000..1000000",
    "ml.prob.temperature": "temperature is a number from 0.01 to 100",
    "ml.prob.topK": "topK is a whole number from 1 to the number of candidates",
    "ml.prob.topP": "topP is greater than 0 and at most 1",
    "ml.prob.sum": "the logits must give a valid distribution; keep them finite and within range",
    "ml.prob.chosen": "chosen must be a candidate token that keeps a positive probability after temperature, topK and topP",
    "ml.prob.sweep": "temperatures holds 2-4 distinct values from 0.01 to 100, without temperature, topK or topP",
    "ml.map.count": "a map holds 3 to 12 entries",
    "ml.map.word.duplicate": "map labels must be unique",
    "ml.map.coordinates": "give exactly one of points or vectors, finite numbers within 1e12, labels of 1-16 characters; vectorCitation only with vectors",
    "ml.map.vector.length": "a position is [x, y]; every vector has the same length, 3 to 32 numbers",
    "ml.map.cosine": "nearestNeighbors is true or false, and a zero vector cannot be linked",
    "ml.map.cluster": "cluster lists distinct labels that are on the map",
    "ml.picture.caption": "caption: 1-100 characters of plain single-line text (required)",
    "ml.picture.png": "imagePNG is base64 of one opaque 8-bit grayscale or RGB PNG",
    "ml.picture.png.colorMetadata": "remove the gAMA, iCCP, sRGB and cHRM chunks from the PNG",
    "ml.picture.size": "each PNG side is 1 to 64 pixels",
    "ml.picture.patch.division": "patchSize is a whole number from 1 to 64 that divides both PNG sides",
    "ml.picture.patch.selection": "highlight is a zero-based [column, row] inside the patch grid",
    "ml.picture.presentation": "presentation is both, grid or pixels",
    "ml.generation.count": "stepCount is a whole number from 1 to 8",
    "ml.generation.logits": "steps must hold exactly stepCount steps, each with 2-8 distinct candidates and finite logits",
    "ml.generation.selection": "selection is greedy (no seed) or sample with a seed from 0 to 4294967295",
    "ml.generation.chosen": "remove chosen or set it to the computed token; greedy picks the highest logit, ties to the earlier candidate",
    "ml.attention.grid": "the patch grid must hold 2 to 64 patches",
    "ml.attention.query": "query is a zero-based [column, row] inside the patch grid",
    "ml.attention.scores": "scores holds one finite number for every patch except the query, in row-major order",
    "ml.agent.states": "states are distinct names from plan, toolCall, toolResult, review, act, revise, stop; plan, toolCall, toolResult and act are required, and revise needs review",
    "ml.agent.review": "requiresReview is true or false, and true needs the review state",
    "ml.agent.stop": "add the terminal stop state",
    "ml.agent.budget": "stepBudget is a whole number from 1 to 32, at least 4 (5 with review) to reach stop",
    "ml.render.frame": "the frame index is outside the checked document",
    "ml.render.raster": "the frame could not be drawn; try a supported size",
    "ml.export.destination": "the destination must be a file URL",
    "ml.export.exists": "choose a new destination; existing files are never overwritten",
    "ml.export.png": "the PNG frame could not be written; check the destination",
}


def matches(pattern, text):
    """`*` matches any run of characters (also an empty one); the same algorithm as the Swift side."""
    i = j = 0
    star, mark = -1, 0
    while j < len(text):
        if i < len(pattern) and pattern[i] != "*" and pattern[i] == text[j]:
            i += 1
            j += 1
        elif i < len(pattern) and pattern[i] == "*":
            star, mark = i, j
            i += 1
        elif star >= 0:
            i = star + 1
            mark += 1
            j = mark
        else:
            return False
    while i < len(pattern) and pattern[i] == "*":
        i += 1
    return i == len(pattern)


def scene_hint(reason):
    """MGRepairHint.text(for:): the item missing/unknown hints come from the kind tables, then the first pattern."""
    parts = reason.split(".")
    kinds = {name: (extra, required) for name, extra, required in KINDS}
    if len(parts) >= 3 and parts[0] == "item" and parts[1] in kinds:
        extra, required = kinds[parts[1]]
        if len(parts) == 3 and parts[2] == "missing":
            return f"a {parts[1]} needs " + ", ".join(sorted(set(required) | {"id", "k"}))
        if parts[2] == "unknown":
            return f"remove unknown keys; a {parts[1]} allows " + ", ".join(sorted(set(COMMON) | set(extra)))
    for pattern, hint in SCENE_HINTS:
        if matches(pattern, reason):
            return hint
    return None


def ml_hint(reason):
    """MGMLReason.hint, or an empty string for a reason the kit does not define."""
    return ML_HINTS.get(reason, "")
