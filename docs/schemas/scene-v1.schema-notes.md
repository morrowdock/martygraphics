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
The Swift CLI calls that parser after bounding the raw input. [Validator lines
13–14 and 150–161](../../tools/SceneValidator/Sources/SceneValidatorCore/SceneValidator.swift#L150).

## Swift sources for the constraints

| Schema or preflight constraint | Swift source |
| --- | --- |
| Version, closed root keys and 2D default / 3D option | [Grammar lines 6–20](../../Sources/MartyGraphics/MGGrammar.swift#L6), [parser line 79](../../Sources/MartyGraphics/MGParser.swift#L79), [parser lines 121–129](../../Sources/MartyGraphics/MGParser.swift#L121) |
| Template scene requires params and excludes world. Literal scenes require items and exclude params, hide and over. | [Parser lines 131–155](../../Sources/MartyGraphics/MGParser.swift#L131) |
| World keys and 2–100 dimensions. Default world is 12 by 8. | [Parser line 13](../../Sources/MartyGraphics/MGParser.swift#L13), [parser lines 151–157](../../Sources/MartyGraphics/MGParser.swift#L151) |
| 1–24 literal items, up to 10 template extras, up to 16 hide entries or overrides each, up to 40 resolved items with at least one remaining, 1–8 supplied steps, up to 48 generated steps | [Parser limits lines 6–12](../../Sources/MartyGraphics/MGParser.swift#L6), [parser lines 146–185](../../Sources/MartyGraphics/MGParser.swift#L146), [parser lines 195–205](../../Sources/MartyGraphics/MGParser.swift#L195) |
| Title length 60; step text length 200; closed steps with up to 16 show IDs and 1–6 edits; focus ID | [Parser limits lines 8–11](../../Sources/MartyGraphics/MGParser.swift#L8), [parser line 200](../../Sources/MartyGraphics/MGParser.swift#L200), [parser lines 273–286](../../Sources/MartyGraphics/MGParser.swift#L273) |
| Camera keys, nonnegative x/y bounded by world dimensions, zoom, yaw and pitch | [Parser lines 290–299](../../Sources/MartyGraphics/MGParser.swift#L290) |
| Closed edits with ID, key and value; id and k are immutable; value is revalidated against the target kind | [Parser lines 302–318](../../Sources/MartyGraphics/MGParser.swift#L302) |
| Every kind's allowed and required fields; common ID, color and optional per-kind label (40 scalars) | [Parser lines 323–368](../../Sources/MartyGraphics/MGParser.swift#L323), [parser lines 385–399](../../Sources/MartyGraphics/MGParser.swift#L385), [limits line 11](../../Sources/MartyGraphics/MGParser.swift#L11) |
| Color enum, 19 kinds, nine 3D kinds, and 3D exclusion of code style | [Model lines 24–36](../../Sources/MartyGraphics/MGModel.swift#L24), [parser line 204](../../Sources/MartyGraphics/MGParser.swift#L204), [parser lines 461–475](../../Sources/MartyGraphics/MGParser.swift#L461) |
| Body shape, size, angle, closed move and duration; incline base and angle; line style | [Parser lines 401–423](../../Sources/MartyGraphics/MGParser.swift#L401) |
| Vector anchor and direction choices, length and dashed flag; unit component bounds and nonzero threshold | [Parser lines 424–437](../../Sources/MartyGraphics/MGParser.swift#L424), [parser lines 601–605](../../Sources/MartyGraphics/MGParser.swift#L601) |
| Axes and plot dimensions and axis labels; plot point counts and ordered data ranges | [Parser limits line 12](../../Sources/MartyGraphics/MGParser.swift#L12), [parser lines 438–447](../../Sources/MartyGraphics/MGParser.swift#L438), [parser lines 607–615](../../Sources/MartyGraphics/MGParser.swift#L607) |
| Spring coil integer, pulley/orbit radii, rope/path point counts and path dashed flag | [Parser limits line 12](../../Sources/MartyGraphics/MGParser.swift#L12), [parser lines 448–460](../../Sources/MartyGraphics/MGParser.swift#L448) |
| Text style and length 120; highlight target ID; bars count, dimensions, closed bar entry, value, label and unit | [Parser limits lines 11–12](../../Sources/MartyGraphics/MGParser.swift#L11), [parser lines 461–489](../../Sources/MartyGraphics/MGParser.swift#L461) |
| Array cell alternatives, indices and sizing; node text/radius; edge endpoints and boolean direction | [Parser limits line 12](../../Sources/MartyGraphics/MGParser.swift#L12), [parser lines 490–531](../../Sources/MartyGraphics/MGParser.swift#L490) |
| Table row/column limits, nonempty rectangular rows, cell alternatives including empty strings, dimensions, header and marked row/column indices; region point count and dashed flag | [Parser limits lines 12 and 28–29](../../Sources/MartyGraphics/MGParser.swift#L12), [parser lines 532–572](../../Sources/MartyGraphics/MGParser.swift#L532) |
| Closed keys, finite numbers, ASCII IDs of length 1–24, point arity and world-relative bounds | [Parser lines 579–599](../../Sources/MartyGraphics/MGParser.swift#L579) |
| Plain text, code markup, scalar count and placeholders | [Parser lines 618–671](../../Sources/MartyGraphics/MGParser.swift#L618) |
| UTF-8, depth 64, raw limit 16 KiB, canonical limit 8 KiB | [Parser limits lines 5–27](../../Sources/MartyGraphics/MGParser.swift#L5), [parser lines 81–86 and 121–125](../../Sources/MartyGraphics/MGParser.swift#L81), [model lines 250–293 and 343–347](../../Sources/MartyGraphics/MGModel.swift#L250) |
| Unique item IDs, focus and show resolution, valid vector/edge/highlight targets and acyclic highlight chains, including after cumulative step edits | [Parser line 168](../../Sources/MartyGraphics/MGParser.swift#L168), [parser lines 233–269](../../Sources/MartyGraphics/MGParser.swift#L233) |
| Template parameter object keys, types, ranges and shape for the two built-ins and the opt-in graph example | [Template lines 218–264](../../Sources/MartyGraphics/MGTemplates.swift#L218), [BST lines 316–338](../../Sources/MartyGraphics/MGTemplates.swift#L316), [two pointers lines 373–378](../../Sources/MartyGraphics/MGTemplates.swift#L373), [graph pack lines 4–6, 28–57 and 89–128](../../Sources/MartyGraphics/MGGraphPack.swift#L28) |

## What the draft pass covers

JSON Schema validates wire shapes and static bounds. It cannot directly
compare arbitrary instance values or execute Swift. Coordinate, camera and
size bounds that depend on the world use the broadest possible numeric range
in the schema. The Python checker tightens them for literal scenes. It also
checks resolved IDs, highlight cycles, cumulative literal edits, range
ordering with a minimum plot span of `1e-6` on each axis, cell shape and indexing,
displayed number length, and text rules. Line feeds are allowed in text items
and step narration.

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

The valid corpus is four standalone protocol fixtures and seven Showcase
scenes. The two `shortest_path` inputs require `--pack graphs`. Four inputs
name templates and pass draft preflight with expansion deferred when their
pack is enabled. The lesson, patches and NDJSON in the fixture directory use
separate entry points. The two protocol negatives retain their original expected
reasons in [ProtocolFixtureTests](../../Tests/MartyGraphicsTests/ProtocolFixtureTests.swift).

The [ported case manifest](../fixtures/v1/invalid/swift-cases.json) contains
16 distinct invalid core inputs from [SceneValidatorTests](../../tools/SceneValidator/Tests/SceneValidatorCoreTests/SceneValidatorTests.swift#L62).
It covers malformed JSON (lines 62–71), reason codes (75–94), item rules
(110–120), raw bytes (123–137), missing version (248–275), bad version
(279–289), and executable bad JSON (322–331). Repeated inputs are counted
once. Malformed and padding-heavy inputs are reconstructed byte-for-byte
from JSON recipes to preserve repository JSON hygiene. The two protocol
negatives also run, giving 18 negative checks including the repeated
unknown-key input.

All 16 core invalid inputs are portable as data. Five other invalid inputs
exercise [the separate ML explainer protocol](../../tools/SceneValidator/Tests/SceneValidatorCoreTests/MLKitValidatorTests.swift#L29)
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
[Swift's preflight](../../Sources/MartyGraphics/MGModel.swift#L250) before
decoding, including inputs deeper than 1,000 levels. A native comparison at
that depth remains pending.

The [schema drift test](../../Tests/MartyGraphicsTests/SceneV1SchemaDriftTests.swift)
compares version, scene keys, colors and item fields with `MGGrammar.document()`.
Run `swift test --filter SceneV1SchemaDriftTests` on a Mac.
