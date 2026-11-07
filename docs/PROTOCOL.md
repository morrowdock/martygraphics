# Scene protocol v1

**Protocol version: 1. Package release: unversioned early preview.** This guide
describes public baseline `55c98121766c8a079006ee3106289ee97c30e7cd`; a wire `v: 1`
is not a package release tag or an API stability guarantee. Follow the
[release/install gates](DISTRIBUTION.md) before claiming a versioned remote install.

This is a serialization contract, not a model prompt. `MGParser` and `MGPatch`
are the authoritative validators. `MGGrammar.document()` exposes allowed/required
item keys, colors, limits, and the template registry directly from their tables;
it is a structural grammar inventory, not a complete JSON Schema validator.

A transport may wrap scenes as `{"type":"scene","scene":{...}}` and patches
as `{"type":"scenePatch","patch":{...}}`. Pass the inner object to the engine.

```json
{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}
```

[Copy the scene JSON](fixtures/v1/scene.json). The minimal scene and title patch
come from the already-public `MGGrammar` protocol examples; all fixtures are
synthetic, Apache-2.0, and contain no transport/provider configuration.

A scene requires `v: 1` and either a registered `template` with `params`, or an
`items` array. Optional fields include `title`, `dim` (`2d` / `3d`), `world`,
`camera`, and `steps`. Template scenes also support `hide` and `over`.
World coordinates point right/up, with the origin at bottom-left; 3D adds z
toward the viewer. The default world is 12 by 8.

Kinds: body, incline, line, vector, axes, plot, spring, pulley, rope, orbit,
text, highlight, bars, path, array, node, edge, table, region. The model types
expose their geometry. In 3D the supported subset is body, incline, line,
vector, axes, orbit, text, highlight, path. Text styles are `label` (default),
`callout`, `title` and `code`. See [tables, regions and code text](#tables-regions-and-code-text)
for the newest additions.

The engine rejects unknown keys, broken references, invalid parameter ranges,
invalid text, duplicate identifiers, and unsupported kinds. Limits include
8 KiB canonical scene JSON, 4 KiB patches, 24 full-scene items, 10 template
extras, 40 resolved items, and 8 wire-authored steps (up to 48 template-built steps). Limits apply to canonical JSON; the
input decoder allows up to twice the scene byte limit before canonicalization.

```json
{"v":1,"rev":0,"ops":[{"op":"title","title":"Synthetic dot"}]}
```

[Copy the patch JSON](fixtures/v1/title.patch.json). For a freshly parsed scene,
this changes the title and advances revision 0 to 1. Applying it a second time
fails with `patch.stale`. A controller stamps revisions; always read its current
`scene.revision` instead of assuming it is zero.

Patch operations: params, add, remove, set, steps, step, camera, title, dim.
A patch revalidates the entire resulting scene. Supply the current `rev` and
use `requireRevision: true` when applying updates from untrusted transports;
stale revisions are rejected. A direct engine caller can omit the revision
when performing a trusted local edit. Failed patches preserve the old value.

`MGStreamParser` offers provisional previews while receiving scene JSON;
`finish()` performs strict final validation. `MGSceneController` restores the
previous scene if final validation fails.

Packs use `MGPack`, `MGTemplate`, `MGTemplateBuild`, `MGFixtures.Demo` and,
optionally, `MGFixtures.PatchDemo` follow-up patches and fail-safe cases.
`MGPacks.validate` reports invalid identifiers, duplicate names, missing template
fixtures, invalid fixture scenes, broken example references, patches that do not
apply to their fixture (`patchInvalid`) and fail-safe cases that parse
(`invalidAccepted`). `register` is
atomic and serializes concurrent registrations. Every template-built item,
world, title, step, and camera is revalidated with the wire rules. Optional
`MGFewShot` records are reference metadata; the built-in public pack provides
no model instructions or generation examples.

Highlight chains must terminate at a non-highlight item. Cycles, self-targets,
and missing targets are rejected, including after each cumulative step edit.
Layout also resolves chains iteratively with a visited set to protect callers
that construct items directly without parsing.

The built-in templates are `bst` and `two_pointers`. Mechanics drawing
primitives and standard math helpers remain available; mechanics walkthrough
templates are not included.

## Tables, regions and code text

These are additive, unreleased changes to the unversioned preview. Wire `v: 1`
is unchanged and every scene that parsed before parses to the same result. All
three are 2D only: in a 3D scene `table` and `region` fail with
`3d.kind.table` / `3d.kind.region`, and `code` text fails with `3d.text.code`
(also when a `dim` patch or a step edit would bring it into 3D). Plain 3D text
is unchanged.

```json
{"id":"grid","k":"table","at":[8.5,5.5],"cells":[["key","value"],["a",1]],"header":true,"marked":[[1,1]]}
```

- `table`: required `at` (centre) and `cells`, 1–8 rows (`MGLimits.tableRows`)
  of 1–6 cells (`tableCols`), every row the same length. A cell is a string of
  at most 12 characters (`tableCellText`) with the plain-text rules, an empty
  string, or a number below 10⁶ in magnitude whose displayed text also fits 12
  characters. Optional `header` (bool: the first row is tinted), `cw` cell width
  0.3 to world span / 3 (default 1.6, capped to that range), `rh` row height 0.3 to
  span / 6 (default 0.7, capped), `marked` (a list of `[row, column]` integer
  pairs, at most rows × columns entries), `label`, `color` (default `accent`). Reasons:
  `table.cells` (shape or count), `table.cell` (a cell value), `table.marked`,
  `table.cw`, `table.rh`, `table.header`. Rows draw on in order.
- `region`: required `pts`, 3–64 points (`MGLimits.points`), drawn as a filled,
  closed polygon. Optional `dashed`, `label`, `color` (default `accent`).
  Reason: `region.pts`.
- Text style `code`: drawn monospaced and left-aligned at `at`, so stacked lines
  read as a listing. Leading spaces are kept (only surrounding newlines are
  trimmed) and `<` / `>` are allowed unless the text looks like a markup tag
  (`<` followed by a letter, `/`, `!` or `?` with a later `>`). Code fences,
  URLs, control characters and whitespace-only text are refused (`text.text`).
  Braces are still placeholders, as in all text. Other styles keep the strict
  rule: no `<` or `>` at all.

[Copy the scene JSON](fixtures/v1/table-region-code.scene.json); it equals the
built-in `cells` fixture.

## Template parameters and what-if patches

Record-list parameters and the opt-in `shortest_path` template are unreleased
additions to the unversioned preview. Wire `v: 1` is unchanged: every shape
below is ordinary JSON inside the existing `params` object.

| Shape | Declaration | Wire form | Absent key |
| --- | --- | --- | --- |
| Number | `MGParamSpec(name:unit:range:integer:)` | finite number in range | `template.<p>.missing` |
| Optional number | same, with `defaultValue` (`.infinity` = optional) | finite number in range | default used |
| Number list | same, with `count` | array of numbers | `template.<p>` |
| Number list with default | same, with `count` and `listDefault` | array of numbers | default used |
| Record list | `MGParamSpec.records(_:count:fields:)` | array of arrays, one number per field, in field order | empty when `count` starts at 0, otherwise `template.<p>.missing` |

Numbers must be JSON numbers: a JSON boolean or string is rejected, never
coerced, so a 0/1 flag such as `shortest_path`'s `directed` must be `0` or `1`
(`true` gives `template.directed`). Values are range-checked inclusively and
rejected, never clamped. A record list reports `template.<p>.count`,
`.arity`, `.<field>` (type or range) or `.<field>.integer`. Number lists keep
their existing absent-key rule; only record lists treat absence as empty.
`MGParamSpec.isRecordList` distinguishes the two list shapes, because record
specs also set `count`.

A `listDefault` must fit the list's `count`, `range` and `integer` rule and is
only allowed on a number list; pack validation refuses any other default
(`MGPackError.badParamSpec`), and a template parsed without registration rejects
it lazily as `template.<p>.default`. `MGParamSpec.doc` shows a default as
`=[1,2]` and says `numbers` for a non-integer list.

Record-list declarations are checked when a pack is validated or registered
(`MGPackError.badParamSpec`): `count` within 0…`MGLimits.records` (32),
1…`MGLimits.recordFields` (6) fields with unique lowercase identifier
names that are not reason suffixes (`arity`, `count`, `integer`, `missing`,
`spec`), finite ranges, and a parameter name used once. A template parsed
without registration checks individual record declarations lazily as
`template.<p>.spec`; duplicate parameter names are checked only at registration.
`MGGrammar.document()` lists a `records` shape (`name`, `count`, per-field
`name`/`range`/`integer`) only for templates that declare record lists, so the
default document is unchanged. Cross-field rules are not in the grammar.

A template may give a specific cross-field rejection: its `reject` closure
returns a suffix such as `edges.loop`, reported as `template.edges.loop`
(lowercase dotted words, at most 48 characters; anything else becomes
`template.check`). `check` still reports the generic `template.check`.

A template's `make` may also throw. A thrown `MGError` whose reason is
`template.<suffix>`, with a suffix that follows the `reject` rule (lowercase
dotted words, at most 48 characters), is reported as is. Any other thrown
reason (another prefix, free or long text) and any other error, like a nil
result, is reported as `template.build`, so a template cannot report a reason
of another family such as `scene.version`.

### Raw templates (free-form params)

`MGTemplate(name:summary:paramsDoc:sample:compile:)` declares a template whose
`params` object is free-form JSON: strings, nested lists and objects that the
numeric shapes above cannot express. The engine checks only that every number
is finite (`template.params.number`), the nesting (at most `MGLimits.depth`,
64 levels, else `template.params.depth`) and the size (at most
`MGLimits.rawParamsBytes`, 4 KiB canonical, else `template.params.bytes`) and
passes the whole object to `compile`, which validates it and throws an
`MGError("template.<suffix>")` or returns nil to reject (same thrown-reason
rule as above). Everything it builds gets the wire checks.
Prefer declared parameters (including record lists) when the values are
numbers: they are validated before your code runs and appear in the grammar.
`paramsDoc` is a one-line schema for host documentation; `sample` is a params
object that should compile; `isRaw` tells the two template forms apart, and
`MGGrammar.document()` adds `rawParams` (`doc`, `maxBytes`) only for raw
templates, and `listDefaults` (parameter name → default list) only for
templates that declare a number-list default. A `params` patch merges top-level keys of a raw template's object
shallowly, exactly as below.

### Host access and unregistered templates

`MGPacks.builtIn` and `MGPacks.all` list the compiled-in and the registered
packs. `MGTemplate.validate(_:)`, `compile(_:is3D:)`, `paramsDoc` and `sample`
are public so a host can check example parameters (for example, before quoting
a sample in its own documentation). `compile` runs `validate` first, so it never
runs template code on unchecked params; its output is unchecked until the
parser re-validates it. `MGParser.scene(data:extraTemplates:)` (and the `object:` and
`json:` forms) and `MGScene.applying(_:extraTemplates:)` parse and patch with
templates that are not registered, for example to check a pack before
`MGPacks.register`. A registered template with the same name wins; extras are
never registered. `MGPatch(ops:baseRevision:)` builds a patch in code (for
example, a host slider); `applying` checks it with the `parse` rules (1–12
operations, finite numbers, each operation's keys, the 4 KiB bound) before it
re-validates the whole scene.

JSON has no NaN or infinity, so an `MGJSON` value built in code that holds one
is refused before it is measured or encoded: `scene.number` from
`MGParser.scene(json:)`, `patch.number` from `MGPatch.parse(json:)` and from
`applying` a code-built patch, and `template.params.number` from a raw
template. `MGJSON.isEncodable` reports this; `canonicalByteCount` is `Int.max`
for such a value, so no byte bound treats it as small.

JSON nests at most `MGLimits.depth` = 64 levels (arrays and objects on one
path; `[[1]]` is 2) at every entry point. Real scenes and patches nest 6 to 15
levels. The system JSON parser and encoder, `MGJSON(any:)`, and Swift's `==`,
hashing and freeing of nested values all recurse once per level. At 64 levels
the deepest of them (a sorted-key encode of nested objects) uses less than half
of a 512 KiB thread stack (iOS secondary threads) and about a fifth of the
1 MiB iOS main-thread stack; a few hundred nested objects can overflow them.
So every entry point counts the nesting first, without recursion: on JSON
`Data` before the system parser (`scene(data:)`, `MGPatch.parse(data:)`, the
stream parser), and on a value built in code before anything reads, compares or
encodes it.

JSON `Data` must be UTF-8. The system parser also reads UTF-16 and UTF-32
(without a byte order mark), which the nesting counter cannot read. So every
`Data` entry point refuses bytes that are not valid UTF-8, or that hold a raw
NUL byte (valid UTF-8 JSON never does; UTF-16 and UTF-32 JSON always does),
with its `json` reason (`json`, `patch.json`) before the parser runs. A deeper value is `scene.depth`, `patch.depth` or
`template.params.depth`. For a value built in code the reasons come in this
order: `.number`, `.depth`, then the byte bound. `canonicalData` and
`canonicalByteCount` never encode a deeper value (`Int.max`), and
`MGJSON(any:)` returns nil for one. Do not compare, hash or convert
(`MGJSON.any`) a deeper value yourself; give it to an entry point, which
refuses it. Lessons and [Solid 3D](SOLID-3D.md) use the same cap (see
[lessons](LESSONS.md)).

The `params` patch operation merges **shallowly**, one top-level key at a time:

- A key that is not sent keeps its previous value.
- A sent list or record list **replaces the whole list**; there is no
  per-element edit. To change one link's weight, send every link.
- `null` is not a deletion. It is rejected (`template.<p>`) like any other
  wrong type, and the previous scene stays.
- A key cannot be removed once set. An optional record list is cleared by
  sending `[]` when its count allows 0. An optional number (for example
  `target`) cannot be cleared by a patch; send a fresh scene.
- The whole scene is rebuilt and revalidated, including author `title`, `over`,
  `hide` and wire `steps`. If any of them no longer fits the recomputed scene,
  the patch is refused whole.

### Opt-in graph pack: `shortest_path`

`MGGraphPack` is not built in. A host that wants it calls
`try MGPacks.register(MGGraphPack.pack)` once per process (a second call throws
`duplicatePack`); until then the template is `template.unknown`.

```json
{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,2],[1,2,2],[0,2,4]],"target":2}}
```

[Copy the scene JSON](fixtures/v1/shortest-path.scene.json). After registration
it narrates "A shortest path 0→2 costs 4. 2 routes tie at 4; the one found first
is shown." The [whole-list edges patch](fixtures/v1/shortest-path-edges.patch.json)
makes 0→1→2 the only route at 3; the [null patch](fixtures/v1/shortest-path-null.patch.json)
is refused with `template.target`.

The standalone `marty-scene-validate` CLI does not register this opt-in pack,
so it rejects these scenes. Validate them in a host that explicitly registers
`MGGraphPack.pack`; the examples are not CLI-supported fixtures.

- `n` 2–8 nodes; `edges` 1–16 records `[a, b, w]` with integer `w` 0–99;
  optional `source` (default 0), `target`, `directed` (0/1) and `at`
  (none, or exactly one `[x, y]` per node, x 0.5–11.5, y 2–7.5).
- One edge per unordered node pair, also when directed, so anti-parallel arcs
  (a→b 3 and b→a 7) are not expressible. This is bounded directed shortest
  paths, not general directed-graph support.
- Specific rejections: `template.edges.node` (index ≥ `n`), `.edges.loop`,
  `.edges.duplicate`, `.source.range`, `.target.range`, `.target.integer`,
  `.at.count`, `.at.gap` (authored nodes closer than 1.2), `.at.crossing` (an
  edge within 0.6 of a node that is not one of its endpoints, so it would read
  as two links). Geometry comparisons allow 1e-9 for decimal representation.
  3D scenes are refused (`template.build`).
- Item ids are semantic: node `n<i>`, the distance array `dist`, an undirected
  link `e<min>_<max>` and a directed arc `d<tail>_<head>`. Reordering records
  (or swapping an undirected link's endpoints) keeps ids, `over`/`hide`
  entries and step references on the same link. Removing a link, reversing an
  arc or toggling `directed` changes the id, so an `over`/`hide` entry naming
  the old link is refused (`over.ref` / `hide.ref`), never moved. There is no
  patch operation to clear these entries: load a fresh scene to remove them
  before changing that link's identity.
- Hiding a template item that the walkthrough edits is refused by the existing
  step-edit reference check; this pre-existing engine behavior is unchanged
  here. Prefer a `params` what-if to hiding links.
- Computed placeholders: `{n}`, `{m}`, `{reached}` always; `{cost}` and
  `{routes}` (number of shortest simple paths, with no repeated node) only
  when a target is set and reachable. Author text that uses `{cost}` or
  `{routes}` makes a disconnecting what-if fail with `title.placeholder.cost`
  (or the field that quotes it), and the previous scene stays.
- Narration discloses equal-cost relaxations into unsettled nodes as "ties …,
  earlier route kept". It does not enumerate ties into already-settled nodes.
  Summaries separately count shortest simple paths, including alternatives
  through zero-weight arcs into settled nodes. When several paths share the
  shortest cost the summary says "A shortest path … N routes tie" instead of
  "The shortest path". A target equal to the source is narrated as a
  zero-cost path to itself. A tree-only summary also discloses alternative
  shortest simple paths, without treating zero-weight cyclic walks as
  additional paths.
- Not accepted: dense automatic layouts (with an even `n`, diameter chords
  share one midpoint, so weight labels can overlap; pass `at`), colour-only edge
  state, accessibility, and frame cost of per-frame step-edit replay.

## Swift API at a glance

| Task | Public entry point | Contract |
| --- | --- | --- |
| Parse a full scene | `MGParser.scene(data:)` → `Result<MGScene, MGError>` | Validate before rendering; failure supplies a developer diagnostic. |
| Inspect structure | `MGGrammar.document()` → `[String: Any]` | Derived keys, kinds, colors, templates and selected bounds; semantic checks remain in the parser. |
| Parse/apply an edit | `MGPatch.parse(data:)`, `scene.applying(_:)` | Atomic validated replacement; preserve the old scene on failure. |
| Host live updates | `MGSceneController`, `apply(patch:requireRevision:)` | Main-actor owner; require the current scene revision for untrusted updates. Controller returns success/failure, not an error-code payload. |
| Receive chunks | `MGStreamParser.feed(_:)` / `finish()`; controller stream methods | Previews are provisional; final strict validation decides acceptance. |
| Present native UI | `MartyGraphicsView(scene:)` / `(controller:)` | SwiftUI host supplies lifecycle, controls and text alternatives. |
| Draw deterministic frames | `MGTimeline.items` / `frame`, `MGViewport`, `MGCanvasRenderer` | See the complete [native exporter](../Examples/Showcase/Sources/MartyShowcase/Showcase.swift). |
| Extend templates | `MGTemplate`, `MGPack`, `MGPacks.validate` / `register` | Validate bounded output, fixtures, patches and fail-safe cases; registration is atomic. |
| Check a pack before registering | `MGParser.scene(data:extraTemplates:)`, `scene.applying(_:extraTemplates:)` | Extras are used for one call only; a registered name wins. |
| Build a patch in code | `MGPatch(ops:baseRevision:)` | `applying` checks it with the `parse` rules, then re-validates the whole scene. |

Copyable parse/patch flow (in a host that imports Foundation and MartyGraphics):

```swift
let scene = try MGParser.scene(data: sceneData).get()
let patch = try MGPatch.parse(data: patchData).get()
switch scene.applying(patch) {
case .success(let updated):
    // Present updated; its scene revision has advanced.
    print(updated.title)
case .failure(let error):
    // Keep scene. Map diagnostics to your own safe user-facing message.
    print(error.reason)
}
```

Load `sceneData` and `patchData` from the two linked UTF-8 JSON files. For actor
ownership, streaming and the native view, continue in the [tutorial](GETTING-STARTED.md).

## Developer error reasons

`MGError.reason` is a developer/test diagnostic, not learner-facing copy. This is
a selected v1 reference, not an exhaustive stable error enumeration; dynamic
suffixes can identify the rejected key or ID. Match only what your integration
has tested, and handle an unknown reason by keeping the previous valid scene.

| Reason / family | Trigger | Recovery |
| --- | --- | --- |
| `json`, `patch.json` | Input decoding, malformed JSON, `Data` that is not UTF-8 (for example UTF-16), or raw input headroom exceeded | Send a complete, bounded inner object; do not feed a transport envelope to the parser. |
| `scene.version` | `v` differs from 1 | Negotiate/support the protocol version before sending scenes. |
| `scene.unknown.<keys>` | Closed root object has unsupported keys | Remove unsupported fields; [negative fixture](fixtures/v1/unknown-key.scene.json). |
| `scene.bytes`, `patch.object`, `items.count`, `steps` | Canonical object or collection violates bounds | Reduce authored content; `patch.object` also covers a non-object patch. |
| `template.unknown`, `template.params` | Missing/unregistered template or invalid parameter object | Use the registered public templates and their declared parameters. |
| `template.<p>`, `template.<p>.missing` / `.count` / `.arity` / `.<field>` / `.integer` | A parameter has the wrong type (including `null`), is absent, or a value or record is out of its declared shape | Send the declared shape; see [template parameters](#template-parameters-and-what-if-patches). |
| `template.<p>.spec`, `template.<p>.default`, `template.check`, `template.<rule>` | Out-of-contract record declaration or list default, generic cross-field failure, or a template's specific cross-field reason | Fix the pack declaration, or correct the named parameters. |
| `template.params.bytes`, `template.build` | A raw template's params object is over 4 KiB, or a template returned nil, threw a non-`MGError` error or threw a reason outside `template.<suffix>` | Send a smaller object; check the template's own documentation. |
| `scene.number`, `patch.number`, `template.params.number` | A value built in code holds NaN or an infinity | Send finite numbers. |
| `scene.depth`, `patch.depth`, `template.params.depth` | JSON text or a value built in code nests deeper than `MGLimits.depth` (64 levels) | Send a flatter value; real scenes and patches nest 6 to 15 levels. |
| `3d.text.code` | `code` text in a 3D scene | Use plain text in 3D, or keep the scene 2D. |
| `table.cells`, `table.cell`, `table.marked`, `region.pts` | A table shape, cell or mark, or a region's points, is out of bounds | See [tables, regions and code text](#tables-regions-and-code-text). |
| `vector.on`, `edge.nodes`, `highlight.target` | Reference is absent, has the wrong kind, or highlights itself | Fix references before applying the scene. |
| `highlight.cycle` | An indirect highlight chain loops | Make the chain terminate; [negative fixture](fixtures/v1/highlight-cycle.scene.json). |
| `patch.stale`, `patch.rev` | Revision mismatches or is invalid | Rebase the intended change on the current scene revision; do not retry stale content blindly. |
| `patch.op.<name>`, `patch.<op>.missing`, `patch.set.ref`, `patch.step.range` | Unsupported operation, missing operation key, missing set target or absent scene step | Correct the operation/target/index, then validate the entire patch again. |

The [protocol fixture test](../Tests/MartyGraphicsTests/ProtocolFixtureTests.swift)
checks the linked JSON, exact selected error reasons, successful title edit and
stale-patch rejection. It passed in the actual 24-test Mac run at
`e1367c946171584044bacf5649ec7f816ecb72ae` (2026-11-04, macOS 26.6.2 arm64,
Apple Swift 6.3.3; dump-package/valid JSON, build and test all exit 0).
That local-package result is not remote-install, release or device acceptance.
Later documentation-only changes can reuse it only with unchanged Swift/package/
test/fixture bytes; retain the original execution SHA rather than relabeling a build.

## Bounds and platforms

The [validator constants](../Sources/MartyGraphics/MGParser.swift) are authoritative.
Byte limits apply to canonical JSON; raw decoder headroom is twice the byte bound.

| Surface | Current bound |
| --- | --- |
| Scene / patch | 8 KiB / 4 KiB canonical UTF-8 JSON; patches have 1–12 operations |
| Items | 24 full-scene wire items; 10 template extras; 40 resolved total |
| Steps | 8 wire-authored; 48 template-built; 6 edits and 16 shown IDs per wire step |
| World | Width and height each 2…100; default 12 × 8 |
| Text lengths | Title 60, label 40, text 120, narration 200 |
| Geometry | Plot/path points up to 64; rope points up to 6 |
| Collections | Array 16 cells / 4 pointers / cells up to 6 characters (a number counts its displayed text, so `-123456` is refused); 6 bars / 16-character bar labels; 8-character node text; table 8 rows × 6 columns / cells up to 12 characters; region 3–64 points |
| Raw template params | 4 KiB canonical `params` object |
| Nesting (arrays and objects on one path) | 64 levels (`MGLimits.depth`); lessons 59 per statement |

Preserve bounds and rollback. Expansions need an actual use case, boundary/failure
tests and measurements; see the [limits rationale](CAPABILITIES.md#bounds-are-part-of-the-contract).

| Target | Declaration / evidence |
| --- | --- |
| macOS | Declared macOS 14+, Swift tools 6.0, Swift language mode 5. The capture receipt records 95 tests plus showcase export at its capture source; the separate local-package run at `e1367c9` passed 24 tests, including the new protocol fixtures. Neither establishes interactive or device acceptance. |
| iOS / iPadOS | Package declares iOS 17+; SwiftUI/SceneKit renderer. No physical iOS-device or accessibility acceptance is established by the Mac export receipt. |
| Windows / Linux / browser | This Apple-framework package is unsupported there. Portable-core/browser implementation is planned-not-started; no architecture rewrite or cross-platform delivery is selected. |

The [public-versus-app matrix](CAPABILITIES.md) distinguishes engine primitives
from hosted services, app content and browser recreations. SceneKit 3D has a
bounded primitive subset; these 2D fixtures are not 3D quality evidence.
