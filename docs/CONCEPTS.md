# Concepts

This page explains the parts of a MartyGraphics 2D scene: the scene itself, items, steps, templates, patches,
streams and limits. It is a short map. The full rules are in the [scene protocol](PROTOCOL.md), and the parser in
[`MGParser.swift`](../Sources/MartyGraphics/MGParser.swift) is the final authority.

MartyGraphics also reads other document types (3D assemblies, explainers, lessons and ML boards). They are listed
at the [end of this page](#other-document-types).

## The scene

A scene is one JSON object. It describes a board: what to draw and, optionally, the steps of a walkthrough.

```json
{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}
```

- `v` is the protocol version. It must be `1`.
- A scene has either an `items` list or a `template` with its `params` ([templates](#templates)).
- Optional keys: `title`, `dim` (`"2d"`, the default, or `"3d"`), `world`, `camera` and `steps`. Template scenes can
  also use `hide` and `over`.
- Keys are **closed**: an unknown key is refused, for example `scene.unknown.colour`.

**Coordinates.** The board uses world units, not pixels. The origin is at the bottom left; x points right and y points
up. The default world is 12 wide and 8 high. Set `"world": {"w": 16, "h": 8}` for a wider board; each side can be
2 to 100. A point may lie a little outside the world (up to a quarter of its size), but not further.

**The parser decides.** A host calls `MGParser.scene(data:)`. It returns either a checked `MGScene` or an `MGError`
whose `reason` names the broken rule. Nothing is drawn from a refused scene. A reason is a developer diagnostic;
show your own words to learners.

## Items

An item is one thing on the board. Every item has:

- `id`: 1 to 24 ASCII letters, digits or underscores, starting with a letter. Ids are unique in a scene. Steps,
  highlights, edges and patches refer to items by id.
- `k`: the kind of item.
- `color` (optional): one of the named colour roles below. There are no hex colours.

| Kind | Draws | Required keys |
| --- | --- | --- |
| `body` | A box or a ball; can glide to a target with `move` | `at` |
| `incline` | A ramp (a right triangle) | `at`, `base`, `angle` |
| `line` | A line: `solid`, `dashed` or `ground` | `from`, `to` |
| `vector` | An arrow from a point (`from`) or on an item (`on`) | `len`, `angle`, and `from` or `on` |
| `axes` | A pair of axes | `at`, `w`, `h` |
| `plot` | Supplied data points with axes | `at`, `w`, `h`, `xr`, `yr`, `pts` |
| `spring` | A coil spring | `from`, `to` |
| `pulley` | A pulley wheel | `at`, `r` |
| `rope` | A rope through up to 6 points | `pts` |
| `orbit` | A circular orbit | `at`, `r` |
| `text` | Text: `label`, `callout`, `title`, `code` or `math` style | `at`, `text` |
| `highlight` | A glow on another item | `target` |
| `bars` | A bar chart of up to 6 bars | `at`, `w`, `h`, `bars` |
| `path` | A line through up to 64 points | `pts` |
| `array` | A row of up to 16 cells, with pointers and marks | `at`, `vals` |
| `node` | A labelled circle (graph node) | `at`, `text` |
| `edge` | A link between two nodes, optionally directed | `a`, `b` |
| `table` | A grid of up to 8 rows and 6 columns | `at`, `cells` |
| `region` | A filled polygon of 3 to 64 points | `pts` |

Angles are in degrees, counter-clockwise from the positive x axis, so `-90` points down. A `vector` drawn `on` a body
follows that body and is drawn from its outline.

Colour roles: `accent`, `muted`, `good`, `warn`, `blue`, `red`, `green`, `orange`, `purple`, `yellow`, `teal`, `white`,
and the physics roles `force`, `normal`, `friction`, `gravity`, `tension`, `velocity`, `accel`, `energy`, `kinetic`,
`potential`.

In a 3D scene (`"dim": "3d"`), only `body`, `incline`, `line`, `vector`, `axes`, `orbit`, `text`, `highlight` and `path`
are allowed, and text cannot use the `code` style.

**Text rules.** Text is plain. It cannot contain links (`://`), code fences or control characters. Text outside the
`code` style cannot contain `<` or `>`. Braces are placeholders: in a plain scene, `{n}` is refused
(`step.say.placeholder.n`), because only templates fill placeholders.

## Steps

`steps` turns a board into a walkthrough of up to 8 steps. Each step has:

| Key | Meaning |
| --- | --- |
| `say` | Required. The narration for this step, up to 200 characters. |
| `show` | Item ids that first appear at this step. An item that no step lists is visible from the start. |
| `focus` | One item id to emphasise in this step. |
| `do` | Up to 6 edits: `{"id": "marker", "key": "target", "value": "queue"}` changes one key of one item. |
| `cam` | A camera for this step. |

Edits are cumulative: step 3 shows the board with the edits of steps 1, 2 and 3 applied. Every edit is checked as if
the changed item had been written that way, so an edit cannot break a rule that the scene itself must follow. An
arrow, highlight or edge whose item is hidden is hidden too. Recipes [2](COOKBOOK.md#2-reveal-a-diagram-step-by-step),
[3](COOKBOOK.md#3-move-a-highlight-through-a-flow) and [8](COOKBOOK.md#8-walk-an-array-beside-its-code) show `show` and `do`.

## Templates

A template builds the items and steps for you from a few parameters, and computes values the narration can quote.

```json
{"v": 1, "title": "Search for 8", "template": "bst", "params": {"values": [12, 5, 19, 2, 8], "find": 8}}
```

- **Built in:** `bst` (insert values into a binary search tree; optionally search for `find`) and `two_pointers`
  (a sorted array and a `target` sum).
- **Opt-in:** `shortest_path` from the graph pack. A host must call `try MGPacks.register(MGGraphPack.pack)` once
  before such a scene parses; until then it is refused with `template.unknown`. The `marty-scene-validate` tool does
  not register it.
- A template scene has no `world`. It can add up to 10 items of its own, change built items with up to 16 `over`
  edits, and hide up to 16 built items with `hide`. Its built walkthrough can have up to 48 steps.
- Hosts can register their own templates with `MGPacks.register`. Every item a template builds is checked again with
  the normal rules. See [template parameters](PROTOCOL.md#template-parameters-and-what-if-patches).

## Patches and revisions

A patch changes a scene that is already on screen:

```json
{"v":1,"rev":0,"ops":[{"op":"title","title":"A labeled marker"}]}
```

- Operations: `params`, `add`, `remove`, `set`, `steps`, `step`, `camera`, `title`, `dim`. A patch has 1 to 12
  operations. Its canonical JSON can be at most 4 KiB, and its raw input at most 8 KiB.
- A patch is **atomic**. The whole resulting scene is checked again. If anything fails, nothing changes and the old
  scene stays.
- `rev` is the scene revision the patch was built for. If a patch has a `rev`, it must equal the current revision; any
  other value, also a future one, is refused with `patch.stale`. With `requireRevision: true`, a patch without a
  `rev` is refused too. Read the current value from `controller.scene?.revision`, not from `controller.revision`.

In Swift, `MGSceneController.apply(patch:requireRevision:)` applies a patch to the scene on screen. It returns
`false` if the patch was refused for any reason, and the scene does not change. The
[tutorial](GETTING-STARTED.md#3-update-with-an-atomic-patch) has a complete host.

## Streams

A host can show a scene while its JSON is still arriving, for example from a model:

```swift
controller.beginStream()
controller.feed(chunk)          // repeat for each chunk of the scene JSON
let accepted = controller.endStream()
```

Previews during the stream are provisional. `endStream()` runs the full check; if it fails, the controller restores
the scene that was there before. Feed only the scene JSON itself, not a transport wrapper.

## Limits

Limits are part of the format. A document over a limit is refused, never trimmed. The values below come from
`MGLimits` in [`MGParser.swift`](../Sources/MartyGraphics/MGParser.swift).

| What | Limit |
| --- | --- |
| Scene size | 8 KiB of canonical JSON (the raw input may be up to 16 KiB before canonicalisation) |
| Patch size | 4 KiB of canonical JSON (the raw input may be up to 8 KiB), 1 to 12 operations |
| Items | 24 in a scene; a template can add up to 10 extras, 40 in total |
| Steps | 8 written steps; 48 built by a template; 6 edits and 16 shown ids per step |
| World | Each side 2 to 100; default 12 × 8 |
| Text | Title 60 characters, label 40, text item 120, step narration 200 |
| Points | Plot, path and region up to 64; rope up to 6 |
| Arrays | 16 cells, 4 pointers, 6 characters per cell |
| Bars | 6 bars, 16-character labels |
| Nodes | 8 characters of text |
| Tables | 8 rows × 6 columns, 12 characters per cell |
| Nesting | 64 levels of arrays and objects |

Why limits exist, and how to propose a change: [bounds are part of the contract](CAPABILITIES.md#bounds-are-part-of-the-contract).

## What a passing check means

A scene that parses is well formed, within its limits, and internally consistent: ids are unique, references point
to items of the right kind, highlight chains end, and every step edit keeps the scene valid. It does **not** mean the
words are true, the numbers in the narration are right, or the board is easy to read. A plot draws the points you
supply; it does not compute them. Arrow lengths are whatever the author typed.

## Other document types

| Document | What it is | Reference |
| --- | --- | --- |
| Assembly (3D solid) | Parts, joints and gear meshes; the engine solves motion and checks the meshes | [Solid 3D](SOLID-3D.md) |
| Explainer | One timeline of beats over a 2D board, a 3D solid, or both | [Explainers](EXPLAINER.md) |
| Lesson | Beat-by-beat statements with checks, learner controls and saved state | [Lessons](LESSONS.md) |
| ML explainer | Checked 2D boards about how AI models work (opt-in library) | [ML explainers](ML-EXPLAINER.md) |
| `layer2d` video | Experimental, opt-in programmatic 2D video inside a scene | [Scene protocol](PROTOCOL.md#experimental-opt-in-layer2d-programmatic-video) |

Each has its own refusal reasons: [reason catalog](REASONS.md).
