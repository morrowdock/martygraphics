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
text, highlight, bars, path, array, node, edge. The model types expose their
geometry. In 3D the supported subset is body, incline, line, vector, axes,
orbit, text, highlight, path.

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

Packs use `MGPack`, `MGTemplate`, `MGTemplateBuild`, and `MGFixtures.Demo`.
`MGPacks.validate` reports invalid identifiers, duplicate names, missing template
fixtures, invalid fixture scenes, and broken example references. `register` is
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
| Extend templates | `MGTemplate`, `MGPack`, `MGPacks.validate` / `register` | Validate bounded output and fixtures; registration is atomic. |

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
| `json`, `patch.json` | Input decoding, malformed JSON or raw input headroom exceeded | Send a complete, bounded inner object; do not feed a transport envelope to the parser. |
| `scene.version` | `v` differs from 1 | Negotiate/support the protocol version before sending scenes. |
| `scene.unknown.<keys>` | Closed root object has unsupported keys | Remove unsupported fields; [negative fixture](fixtures/v1/unknown-key.scene.json). |
| `scene.bytes`, `patch.object`, `items.count`, `steps` | Canonical object or collection violates bounds | Reduce authored content; `patch.object` also covers a non-object patch. |
| `template.unknown`, `template.params` | Missing/unregistered template or invalid parameter object | Use the registered public templates and their declared parameters. |
| `vector.on`, `edge.nodes`, `highlight.target` | Reference is absent, has the wrong kind, or highlights itself | Fix references before applying the scene. |
| `highlight.cycle` | An indirect highlight chain loops | Make the chain terminate; [negative fixture](fixtures/v1/highlight-cycle.scene.json). |
| `patch.stale`, `patch.rev` | Revision mismatches or is invalid | Rebase the intended change on the current scene revision; do not retry stale content blindly. |
| `patch.op.<name>`, `patch.set.ref`, `patch.step.range` | Unsupported operation, missing set target or absent scene step | Correct the operation/target/index, then validate the entire patch again. |

The [protocol fixture test](../Tests/MartyGraphicsTests/ProtocolFixtureTests.swift)
checks the linked JSON, exact selected error reasons, successful title edit and
stale-patch rejection. Its candidate execution receipt must accompany review;
the original release's tests alone do not clear newly added fixtures.

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
| Collections | Array 16 cells / 4 pointers / 6-character cell text; 6 bars / 16-character bar labels; 8-character node text |

Preserve bounds and rollback. Expansions need an actual use case, boundary/failure
tests and measurements; see the [limits rationale](CAPABILITIES.md#bounds-are-part-of-the-contract).

| Target | Declaration / evidence |
| --- | --- |
| macOS | Declared macOS 14+, Swift tools 6.0, Swift language mode 5. Public native receipt: macOS 26.6.2 arm64, Apple Swift 6.3.3, build + 23 tests + showcase verify/export at pinned capture source. New tests need a new receipt. |
| iOS / iPadOS | Package declares iOS 17+; SwiftUI/SceneKit renderer. No physical iOS-device or accessibility acceptance is established by the Mac export receipt. |
| Windows / Linux / browser | This Apple-framework package is unsupported there. Portable-core/browser implementation is planned-not-started; no architecture rewrite or cross-platform delivery is selected. |

The [public-versus-app matrix](CAPABILITIES.md) distinguishes engine primitives
from hosted services, app content and browser recreations. SceneKit 3D has a
bounded primitive subset; these 2D fixtures are not 3D quality evidence.
