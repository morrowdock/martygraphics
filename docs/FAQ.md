# FAQ

Short answers, with links to the page that has the details.

## What is MartyGraphics?

A Swift package that draws teaching visuals from small JSON documents: 2D boards (diagrams, plots, charts, arrays,
tables, trees, graphs) and 3D mechanisms (gears, linkages, cutaways). Every completed document is checked before it
is drawn. While a scene is still streaming in, a host can show provisional previews; the full check runs when the
stream ends. See the [README](../README.md) and [Concepts](CONCEPTS.md).

## What does it run on?

Macs with macOS 14 or later, with a Swift 6 toolchain. The package also declares iOS 17 or later and uses SwiftUI and
SceneKit there, but no iPhone or iPad device has been accepted yet. Windows, Linux and web browsers are not supported:
the renderers need Apple frameworks. A [portability proposal](PORTABILITY-PROPOSAL.md) exists; it is planned, not
started.

## Is there a release I can depend on?

There is one tag, `v0.1.0` (2026-11-11). It is an early preview, and `main` has changed a lot since. The repository's
own examples depend on a local checkout, and the [quick start](../README.md#quick-start) does the same. Depending on
the tag by URL should work, but the project has not yet recorded the remote-install check that its
[release gates](DISTRIBUTION.md) require. APIs and formats can still change.

## Does it include an AI model?

No. MartyGraphics has no model, prompt, API key or network call. A host app can ask any model to write JSON; the
engine checks that JSON the same way it checks hand-written JSON.

## Does the engine check that a lesson is correct?

No. It checks structure, ranges, references, text rules and limits. For 3D mechanisms it also solves motion and
checks gear meshes and the direction of some arrows. It does not check whether a sentence is true, whether a typed
number is right, or whether a picture is easy to read. A "Solved" count in a 3D legend counts values the engine
computed from the author's model, not facts about a real object. See
[what a passing check means](CONCEPTS.md#what-a-passing-check-means).

## How do I check a scene file without an app?

On a Mac, build [`marty-scene-validate`](../tools/SceneValidator/README.md) and pass it file names. It runs the same
parser an app runs and prints `valid` or `invalid:` with a reason code. Exit status 0 means every file is valid. It
does not load opt-in packs, so `shortest_path` scenes fail there with `template.unknown`.

## My scene was refused. What does the reason mean?

The reason names the rule and the place, not the file line. Common ones:

| Reason | Usual cause |
| --- | --- |
| `json` | The text is not valid JSON, or not UTF-8. |
| `scene.missing` | The scene has no `v`. |
| `scene.version` | `v` is present but not `1`. |
| `scene.unknown.<key>` | A top-level key the format does not have, for example `scene.unknown.titel` for a misspelt `title`. |
| `item.<kind>.unknown.<key>` | An item key the format does not have, for example `item.body.unknown.colour`. |
| `<kind>.<key>` | A value is the wrong type or out of range, for example `body.at` for a point off the board. |
| `item.kind` | `k` is not one of the [19 kinds](CONCEPTS.md#items). |
| `id.duplicate.<id>` | Two items share an id. |
| `edge.nodes`, `vector.on`, `highlight.target` | A reference points to an item that does not exist or has the wrong kind. |
| `step.say.placeholder.<name>` | Braces in narration. Only templates fill `{...}` placeholders. |
| `bars.bars`, `items.count`, `scene.bytes` | Too many bars, items or bytes. See the [limits](CONCEPTS.md#limits). |
| `template.unknown` | The template is not built in and not registered by the host. |

The [protocol](PROTOCOL.md#developer-error-reasons) has the 2D list, and the [reason catalog](REASONS.md) has the 3D,
explainer and ML reasons. Reasons are for developers; show learners your own words.

## Can I make a bigger scene?

Not by turning a limit off. Limits are part of the format: they keep checking, layout and drawing bounded. Split a
long walkthrough into several scenes, or use a template. A proposal to raise a limit needs a real use case, tests
and measurements; see [bounds are part of the contract](CAPABILITIES.md#bounds-are-part-of-the-contract).

## Can I export images or video?

- **2D scenes:** the library draws frames; your host saves them. The [quick start](../README.md#quick-start) saves a
  PNG, and the [showcase exporter](../Examples/Showcase/Sources/MartyShowcase/Showcase.swift) also writes GIFs.
- **3D mechanisms and explainers:** `marty-solid render FILE.json NEW_DIR` writes stills. It also writes a loop when
  the document has a solid and loops are on (`--no-loop` turns them off), and a story video when the document has
  steps or beats and story output is on (`--no-story` turns it off) ([`marty-solid`](../Examples/Solid3D/README.md)).
- **glTF for Blender:** `marty-solid export-gltf FILE.json NEW_DIR --engine-commit SHA` takes an assembly document and
  writes a `.glb` file and a manifest for [Blender rendering](../tools/render-blender/README.md)
  ([glTF export](GLTF-EXPORT.md)).
- **Text:** `marty-solid transcript FILE.json` prints JSON with the captions, the visible annotation text and the
  board table rows ([transcript](EXPLAINER.md#transcript)).
- **Captions:** `marty-solid export-captions FILE.json --format vtt|srt|txt` prints the story video's captions as
  WebVTT or SubRip, timed to its frames, or a plain-text transcript
  ([captions and transcript export](EXPLAINER.md#captions-and-transcript-export)).
- **ML explainer boards:** `marty-ml-render` writes MP4 or transparent PNG frames ([ML explainers](ML-EXPLAINER.md)).
- **Programmatic 2D video** (`layer2d`): experimental and opt-in ([protocol](PROTOCOL.md)).

## Is it accessible?

Partly, and not yet accepted. The board view gives VoiceOver the scene title as its label and the current narration
as its value, and the
[render policy](../Sources/MartyGraphics/MGRenderPolicy.swift) stops continuous animation when Reduce Motion is on.
Keyboard use, VoiceOver behaviour and colour choices have not been checked by hand. The
[quality plan](QUALITY.md) lists the acceptance work. Do not rely on the board alone: give learners the narration
as text too.

## Is it fast?

Not measured for interactive use. One lesson benchmark on an Apple M1 Mac (not an iPad) is recorded in
[Lessons](LESSONS.md#measured-timing-this-mac-only). Frame rate, memory and device timing are listed as pending in the
[quality plan](QUALITY.md).

## Can a scene run code or load files?

No. A scene is data. Keys are closed, text cannot contain links or markup, and the parser never reads files or URLs
from a scene. Templates are Swift code compiled into the host, not code in the JSON.

## What are Marty and Morrowdock?

[Marty](https://github.com/morrowdock/marty) is a separate app that can ask a model to write MartyGraphics JSON.
[Morrowdock](https://morrowdock.app) is the host application's website; its browser demos are separate
implementations, not this Swift package running in a browser.

## What is the license?

Apache-2.0 for the code, the JSON examples and the images made from them ([license](../LICENSE),
[notice](../NOTICE)). Some sample fonts and artwork in `Examples/Explainers` have their own licenses
([ML sample artwork](../Examples/Explainers/ML-ASSETS.md)).

## How do I contribute?

Small, focused pull requests with a DCO sign-off (`git commit -s`). Read [CONTRIBUTING](../CONTRIBUTING.md) first; it
lists the required checks and what not to submit.
