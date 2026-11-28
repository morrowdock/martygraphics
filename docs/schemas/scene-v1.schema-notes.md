# Core scene v1 draft schema

[Protocol](../PROTOCOL.md) · [JSON Schema 2020-12 draft](scene-v1.draft.schema.json) · [Python checker](../../tools/scene_v1_check.py)

Run `python tools/scene_v1_check.py path/to/scene.json` from the repository root.
The checker uses Python's standard library and evaluates the keywords used in
this schema. Exit codes are 0 for a draft pass, 1 for a refused scene, 2 for
invalid command usage and 3 for an unreadable path. The output identifies
template scenes that still require Swift expansion.

The draft describes a standalone scene object. Statement envelopes, patches,
lessons, explainer documents and opt-in programmatic video have their own
protocols. Swift's `MGParser.scene(data:)` is the authority for acceptance.
The Swift CLI calls that parser after bounding the raw input: see
[`SceneValidator.maximumInputBytes` and `SceneValidator.check(data:)`](../../tools/SceneValidator/Sources/SceneValidatorCore/SceneValidator.swift).

## Swift sources for the constraints

| Schema or preflight constraint | Swift source |
| --- | --- |
| Version, closed root keys and 2D default / 3D option | [`MGGrammar.version`](../../Sources/MartyGraphics/MGGrammar.swift), [`MGParser.topKeys` and the version and `dim` checks in `MGParser.parseScene`](../../Sources/MartyGraphics/MGParser.swift) |
| Template scene requires params and excludes world. Literal scenes require items and exclude params, hide and over. | [The `template` branch of `MGParser.parseScene`](../../Sources/MartyGraphics/MGParser.swift) |
| World keys and 2–100 dimensions. Default world is 12 by 8. | [`MGLimits.worldRange` and the `world` checks in `MGParser.parseScene`](../../Sources/MartyGraphics/MGParser.swift) |
| 1–24 literal items, up to 10 template extras, up to 16 hide entries or overrides each, up to 40 resolved items with at least one remaining, 1–8 supplied steps, up to 48 generated steps | [`MGLimits` (`items`, `templateExtras`, `hide`, `overrides`, `resolvedItems`, `steps`, `templateSteps`) and the item, `hide`, `over` and `steps` checks in `MGParser.parseScene`](../../Sources/MartyGraphics/MGParser.swift) |
| Title length 60; step text length 200; closed steps with up to 16 show IDs and 1–6 edits; focus ID | [`MGLimits` (`title`, `say`, `showPerStep`, `stepEdits`), the title check in `MGParser.parseScene` and `MGParser.step(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Camera keys, nonnegative x/y bounded by world dimensions, zoom, yaw and pitch | [`MGParser.camera(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Closed edits with ID, key and value; id and k are immutable; value is revalidated against the target kind | [`MGParser.edit(_:)` and `MGParser.apply(_:to:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Every kind's allowed and required fields; common ID, color and optional per-kind label (40 scalars) | [`MGParser.allowedKeys(_:)`, `MGParser.required(_:)`, the start of `MGParser.item(_:_:)` and `MGLimits.label`](../../Sources/MartyGraphics/MGParser.swift) |
| Color enum, 22 kinds, nine 3D kinds, and 3D exclusion of code style | [`MGColorRole`, `MGKind` and `MGKind.in3D`](../../Sources/MartyGraphics/MGModel.swift), [the `3d.kind` check in `MGParser.parseScene` and the `text` case of `MGParser.item(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Body shape, size, angle, closed move and duration; incline base and angle; line style | [The `body`, `incline` and `line` cases of `MGParser.item(_:_:)` and `MGLimits.bodyMoveTime`](../../Sources/MartyGraphics/MGParser.swift) |
| Vector anchor and direction choices, length and dashed flag; unit component bounds and nonzero threshold | [The `vector` case of `MGParser.item(_:_:)` and `MGParser.vector3(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Axes and plot dimensions and axis labels; plot point counts and ordered data ranges | [`MGLimits.points`, the `axes` and `plot` cases of `MGParser.item(_:_:)`, `MGParser.dataPoint(_:_:)` and `MGParser.range(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Spring coil integer, pulley/orbit radii, rope/path point counts and path dashed flag | [`MGLimits` (`points`, `ropePoints`, `springCoils`) and the `spring`, `pulley`, `rope`/`path` and `orbit` cases of `MGParser.item(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Text style and length 120; highlight target ID; bars count, dimensions, closed bar entry, value, label and unit | [`MGLimits` (`text`, `bars`, `barLabel`) and the `text`, `highlight` and `bars` cases of `MGParser.item(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Array cell alternatives, indices and sizing; node text/radius; edge endpoints and boolean direction | [`MGLimits` (`cells`, `cellText`, `pointers`, `nodeText`) and the `array`, `node` and `edge` cases of `MGParser.item(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Table row/column limits, nonempty rectangular rows, cell alternatives including empty strings, dimensions, header and marked row/column indices; region point count and dashed flag | [`MGLimits` (`tableRows`, `tableCols`, `tableCellText`, `points`) and the `table` and `region` cases of `MGParser.item(_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| `func` and `field` keys, ranges, expression length 80, parameters within ±1000, period 0.5–20 seconds, shade, mark, `func` readouts (1–3 of `value`, `slope`, `area`), grid size and style; at most six graph checks per scene (each graph item, and each step or `over` edit of one; a `func` with readouts, and each edit of it that can change one, count two); scene and step `alt` (200 scalars) | [`MGReadout`](../../Sources/MartyGraphics/MGReadout.swift), [`MGLimits` (`exprLength` to `fieldRows`, `readoutWeight`), the `items.expr` count and `alt` check in `MGParser.parseScene`, `MGParser.exprWeight`, `MGParser.editWeight`, `MGParser.readoutGraphs`, the `alt` check in `MGParser.step(_:_:)`, the `function` and `field` cases of `MGParser.item(_:_:)`, `MGParser.graphRange(_:_:)`, `MGParser.graphParameters(_:_:_:)` and `MGParser.expression(_:_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| `curve` keys and ranges, exactly one form (`x` and `y`, or `r`), `theta` ends within ±1000 with a span of 0.001–100, `mark` inside the `theta` range, expressions in `theta`; a curve, and each step or `over` edit of it, counts two of the six graph checks (the schema cannot express the form rule, the span or the weight; tools/mg_expr.py checks them) | [`MGLimits` (`curveIntervals` to `curveTolerance`), the `items.expr` count in `MGParser.parseScene`, `MGParser.exprWeight`, `MGParser.editWeight`, `MGParser.curveGraphs` and the `curve` case of `MGParser.item(_:_:)`](../../Sources/MartyGraphics/MGParser.swift), [`MGGraph.curveWindow(_:_:w:h:)` and `MGGraph.checkCurve(_:_:)`](../../Sources/MartyGraphics/MGPlanarCurve.swift) |
| `sliders`: 1–3 closed sliders (`param` a, b or c, `min` and `max` within ±1000, `step` above 0 dividing the range into at most 100 steps, `default` exactly the value of a stop, every stop a distinct value and label whose label reads back as exactly the value the engine gets, both ends included, `label` of 40 scalars without placeholders); one per parameter; every `func` that sets the parameter must set the default; no `field` or step edit may set it; no driven `func` lists `readouts`; at most 6 slider-graph pairs; both ends of the range pass the item rules | [`MGLimits` (`sliders`, `sliderSteps`, `sliderBindings`) and the `sliders` check in `MGParser.parseScene`](../../Sources/MartyGraphics/MGParser.swift), [`MGParser.sliders(_:items:steps:_:)` and `MGSlider`](../../Sources/MartyGraphics/MGSliders.swift) |
| Closed keys, finite numbers, ASCII IDs of length 1–24, point arity and world-relative bounds | [`MGParser.closed(_:required:optional:_:)`, `MGParser.num(_:_:_:)`, `MGParser.identifier(_:_:)` and `MGParser.point(_:_:_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Plain text, code markup, scalar count and placeholders | [`MGParser.text(_:_:_:_:code:multiline:)`, `MGParser.looksLikeMarkup(_:)` and `MGParser.fill(_:_:_:env:)`](../../Sources/MartyGraphics/MGParser.swift) |
| UTF-8, depth 64, raw limit 16 KiB, canonical limit 8 KiB | [`MGLimits.sceneBytes` and `MGLimits.depth`, `MGParser.scene(data:)` and the entry check in `MGParser.parseScene`](../../Sources/MartyGraphics/MGParser.swift), [`MGJSON.dataRefusal`, `MGJSON.textNesting` and `MGJSON.checkEntry`](../../Sources/MartyGraphics/MGModel.swift) |
| Unique item IDs, focus and show resolution, valid vector/edge/highlight targets and acyclic highlight chains, including after cumulative step edits | [The `id.duplicate` check in `MGParser.parseScene`, `MGParser.checkReferences(items:steps:_:)` and `MGParser.checkItemReferences(_:)`](../../Sources/MartyGraphics/MGParser.swift) |
| Template parameter object keys, types, ranges and shape for the two built-ins and the opt-in graph example | [`MGTemplate.validate(_:)`, `MGTemplate.records`, `MGTemplates.bst` and `MGTemplates.twoPointers`](../../Sources/MartyGraphics/MGTemplates.swift), [`MGGraphPack.shortestPath` and `MGGraphPack.graph(_:)`](../../Sources/MartyGraphics/MGGraphPack.swift) |

## What the draft pass covers

JSON Schema validates wire shapes and static bounds. It cannot directly
compare arbitrary instance values or execute Swift. Coordinate, camera and
size bounds that depend on the world use the broadest possible numeric range
in the schema. The Python checker tightens them for literal scenes. It also
checks resolved IDs, highlight cycles, cumulative literal edits, range
ordering with a minimum plot span of `1e-6` on each axis, cell shape and indexing,
displayed number length, and text rules. Line feeds are allowed in text items
and step narration. For literal scenes, `func`, `field` and `curve` items are checked with
[tools/mg_expr.py](../../tools/mg_expr.py), the offline mirror of the expression,
sampling and drawing rules. The mirror also computes each `func` item's readouts
first, so the checker accepts a `{<id>.<readout>}` placeholder the scene computes in
any text, refuses one it does not (`<text>.placeholder.readout`) and refuses a literal
step edit that changes a readout (`func.readouts.edit`). In a template scene they get
the schema check only, because the world is known only after Swift expands the
template, and readout placeholders are left to Swift like other placeholders. Each
slider's own rules (grid, default, label) run in every scene; the binding and
end-of-range rules run for literal scenes only (`check_sliders` in
[tools/mg_expr.py](../../tools/mg_expr.py)), for the same reason.

The checker measures compact UTF-8 JSON against 8 KiB and measures raw input
against 16 KiB. Whole-number decimal values use integer spelling for the
Python size check. Apple's JSONSerialization can spell other numbers differently,
so compare borderline canonical sizes with Swift. Python's Unicode
whitespace and markup decisions and numeric formatting can also differ from
Foundation. Cumulative edits replay against authored JSON, so differences in
Swift wire normalization and defaults can affect acceptance. The Python tests
pin the reviewed single-rule diagnostics to Swift source. Other diagnostics
can still differ. For example, Swift can report `template.at.gap` or
`template.at.crossing` during graph layout checks beyond Python preflight.
The first reported reason can also differ when an input violates several
rules. Swift reports a missing BST list as `template.values`. The
`.missing` suffix applies to required scalar and record parameters such as
`template.n.missing` and `template.edges.missing`. The schema uses a portable
`$` ID anchor. Python uses `\Z` for strict end-of-string matching.

Template input gets structural validation, selected parameter checks and
checks for references and cycles among explicit items. The draft checker
recognizes Swift's two built-ins by default. Use `--pack graphs` for
`shortest_path` scenes from Showcase, which registers that pack. Swift must
still expand templates, check their dimension-specific output, world and
layout, fill placeholders, apply hide
and overrides, and validate generated items and steps. Registered custom
packs require the host that registered them.

## Fixture accounting and native follow-up

The valid corpus is six standalone protocol fixtures and seven Showcase
scenes. The two `shortest_path` inputs require `--pack graphs`. Four inputs
name templates and pass draft preflight with expansion deferred when their
pack is enabled. The lesson, patches and NDJSON in the fixture directory use
separate entry points. The two protocol negatives retain their original expected
reasons in [ProtocolFixtureTests](../../Tests/MartyGraphicsTests/ProtocolFixtureTests.swift).

The [math-label fixture](../fixtures/v1/math-label.scene.json) covers the
precomposed operator. The decomposed companion remains pending under the
defensive-only verification scope.

The [ported case manifest](../fixtures/v1/invalid/swift-cases.json) contains
16 distinct invalid core inputs from [SceneValidatorTests](../../tools/SceneValidator/Tests/SceneValidatorCoreTests/SceneValidatorTests.swift).
It covers malformed JSON (`testMalformedJSONIsInvalid`), reason codes
(`testParserReasonCodesAreReportedUnchanged`), item rules
(`testTableRegionAndCodeScenesUseTheParserRules`), raw bytes
(`testByteLimitMatchesParser`), missing version
(`testMultipleFilesKeepOrderAndExitPrecedence` and
`testPathsWithSpacesAndControlCharacters`), bad version
(`testJSONReportIsStableAndParsable`), and executable bad JSON
(`testExecutableExitStatuses`). Repeated inputs are counted
once. Malformed and padding-heavy inputs are reconstructed byte-for-byte
from JSON recipes to preserve repository JSON hygiene. The two protocol
negatives also run, giving 18 negative checks including the repeated
unknown-key input.

All 16 core invalid inputs are portable as data. Five other invalid inputs
exercise the separate ML explainer protocol ([`MLKitValidatorTests`](../../tools/SceneValidator/Tests/SceneValidatorCoreTests/MLKitValidatorTests.swift))
and were excluded. Filesystem refusals, symlinks, permissions, command-line
formatting and closed descriptors check the Swift CLI harness outside the
scene corpus.

See the [Swift and Python parity evidence](evidence/scene-v1/SWIFT-PARITY.md).
On a Mac, run the [Swift CLI suite](../../tools/SceneValidator/README.md)
and compare the original byte inputs and reasons against the draft checker.
Register the graph pack when running `shortest_path` scenes through the
parser, as Showcase does. Compare near-limit UTF-8 and numeric scenes on
both platforms before relying on Python's size result as a gate.
The Python checker requires UTF-8 without a leading BOM and unique object
keys. Compare those acceptance rules with Swift before treating them as engine
requirements. The Python textual nesting check follows
Swift's preflight ([`MGJSON.dataRefusal` and `MGJSON.textNesting`](../../Sources/MartyGraphics/MGModel.swift)) before
decoding, including inputs deeper than 1,000 levels. A native comparison at
that depth remains pending.

The [schema drift test](../../Tests/MartyGraphicsTests/SceneV1SchemaDriftTests.swift)
compares version, scene keys, colors and item fields with `MGGrammar.document()`.
Run `swift test --filter SceneV1SchemaDriftTests` on a Mac.
