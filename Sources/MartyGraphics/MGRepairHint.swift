// SPDX-License-Identifier: Apache-2.0
import Foundation

/// One-line fix hints for scene refusal reasons, for the repair message an author (a person, an agent or a model in
/// a host app) reads after `MGParser` refuses a scene. The reason token stays the authority: a hint only suggests a
/// fix, and an unknown reason has no hint. `marty-scene-validate --hints` prints these. Patterns are matched in order
/// and `*` stands for any run of characters. The Python mirror in `evals/dev-authoring/tools/hints.py` must match this
/// table; both are checked against the shared corpus `docs/fixtures/repair-hints/corpus.json` (`RepairHintCorpusTests`
/// and `tools/tests/test_repair_hints.py`).
public enum MGRepairHint {
    public static func text(for reason: String) -> String? {
        let parts = reason.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3, parts[0] == "item", let kind = MGKind(rawValue: parts[1]) {
            if parts.count == 3, parts[2] == "missing" {
                return "a \(kind.rawValue) needs " + MGParser.required(kind).union(["id", "k"]).sorted().joined(separator: ", ")
            }
            if parts[2] == "unknown" {
                return "remove unknown keys; a \(kind.rawValue) allows " + MGParser.allowedKeys(kind).sorted().joined(separator: ", ")
            }
        }
        for (pattern, hint) in table where matches(pattern, reason) { return hint }
        return nil
    }

    /// `*` matches any run of characters (also an empty one); every other character matches itself.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern), t = Array(text)
        var i = 0, j = 0, star = -1, mark = 0
        while j < t.count {
            if i < p.count, p[i] != "*", p[i] == t[j] { i += 1; j += 1 }
            else if i < p.count, p[i] == "*" { star = i; mark = j; i += 1 }
            else if star >= 0 { i = star + 1; mark += 1; j = mark }
            else { return false }
        }
        while i < p.count, p[i] == "*" { i += 1 }
        return i == p.count
    }

    static let plainText = "plain text only: no < or > (write the symbols ≤ ≥ → or words), no { } outside template placeholders, no URLs or code fences"
    static let pointShape = "a point is [x, y] ([x, y, z] in 3D) with x from -0.25·w to 1.25·w and y from -0.25·h to 1.25·h of the world"

    static let table: [(String, String)] = [
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
        ("template.motion", "the template built invalid motion; fix the template: slide travel, orbit and oscillate period and projectile visual are 0.3 to 10 seconds, hold is 0 to 10 seconds, projectile flight is above 0, and every other motion number is finite"),
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
        ("item.label", "label: 1-40 characters of \(plainText)"),
        ("title", "title: 1-60 characters of \(plainText)"),
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
        ("text.text", "text: 1-120 characters of \(plainText); code-style text may use < and > in comparisons but not tags"),
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
        ("step.say", "narration: 1-200 characters of \(plainText)"),
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
        ("*.at", "\(pointShape)"),
        ("*.from", "\(pointShape)"),
        ("*.to", "\(pointShape)"),
        ("*.pts", "\(pointShape)"),
        ("*.dashed", "dashed is true or false"),
        ("*.header", "header is true or false"),
        ("*.dir", "dir is true or false"),
        ("*.xl", "an axis label is 1-40 characters of plain text"),
        ("*.yl", "an axis label is 1-40 characters of plain text"),
    ]
}
