# Programmatic video: learn it, build it, teach it

Status: proposal. All new format fields, APIs, limits, UI and release dates below are **proposed**, not shipped features.

Checked: 2026-11-15 UTC. Verified source baseline: `3ce64d3dd15fb35a73ee79e65ba6730be5b94d86`.
Owner-approved goal and priority: 2026-11-15, “sooner”. Learners, lessons and the Marty agent should make short
animated explainers from code or data, then export MP4/GIF offline on iPad and Mac. This public document contains
only an original synthetic format proposal, no course material, private adapters or agent instructions.

## Verified baseline and gaps

The following observations are **verified by source inspection at the baseline above**, not new device tests:

| Existing source | What exists | Gap this proposal addresses |
| --- | --- | --- |
| [Scene protocol](../PROTOCOL.md), [tutorial](../GETTING-STARTED.md), [MGTimeline.swift](../../Sources/MartyGraphics/MGTimeline.swift) | Strict scene v1 JSON; 2D bodies, vectors, axes, text, arrays, plots and more. Timeline resolves cumulative step edits, motion and blending from scene/step/time. Code-style text already exists. | A bounded finite video plan with authored keyframes, code-line highlighting and a reusable export API. Reuse existing geometry and layout where possible. |
| [Lessons](../LESSONS.md), [explainer documents](../EXPLAINER.md), [MGStoryPlan.swift](../../Sources/MartyGraphics/Solid/MGStoryPlan.swift) | Beat-based lessons and mixed 2D-board/3D explainers; deterministic story beat/frame timing, captions and camera interpolation. Story timing supports 10/30 fps with a 3,600-frame cap. | General short 2D data animations independent of solid parts and camera beats. Do not change existing story timing. |
| [MGStoryRoute.swift](../../Sources/MartyGraphics/Solid/MGStoryRoute.swift), [MGSolidFrames.swift](../../Sources/MartyGraphics/Solid/MGSolidFrames.swift) | Fixed-order camera route checks and cuts; frame/joint/anchor lints with strict-profile refusals and read-back. | Equivalent preflight discipline for the new 2D layer, without implying camera or mechanics checks prove algorithms or prose. |
| [Solid3D CLI](../../Examples/Solid3D/Sources/MartySolidCLI/main.swift), [Solid3D example](../../Examples/Solid3D/README.md), [showcase tool](../../tools/showcase.sh) | CLI `MovieWriter` uses AVFoundation, H.264, integer frame timestamps and backpressure; ImageIO writes GIFs. Render commands generate stills, loops and stories. | Promote reusable bounded export behavior into an opt-in library surface usable on iPad; CLI output is not evidence of a shipped app export feature. |
| [Jet-suit receipt](../assets/jet-suit-ai/provenance.json), [fact check](../assets/jet-suit-ai/FACT-CHECK.md), [studio refresh](../assets/STUDIO-RERENDER.md) | Receipt records an unedited 1,280×800 H.264 story: 30 fps, 2,338 frames, 77.93 seconds, nine beats; it names capture/check provenance. The later refresh changed stills, not the MP4. Two independent AI checks found content errors despite engine acceptance. | Keep render/structural verification separate from educational fact checking, and issue equivalent receipts for new exports. |

The public [README](../../README.md) already limits determinism claims: plans and checks are deterministic;
SceneKit pixels can differ between processes. [Examples](../../Examples/) demonstrate mechanisms rather than a
sandboxed learner video lab. No Node, browser renderer, remote render service or new dependency is needed here.

## Proposed architecture and compatibility

Add an optional `layer2d` to the **same scene JSON**, not a separate executable animation language. It describes
shapes (rectangle/ellipse), arrows, labels, axes, number lines and code blocks with a highlighted line. Reuse 2D
layout/drawing primitives; a small adapter maps checked layer elements and keyframes into existing timeline state.
A code block groups monospaced text lines and a discrete highlight; it never evaluates that text.

The [draft schema](../schemas/scene-2d-layer.draft.schema.json) describes a closed **minimal scene subset** with
`v: 1`, `dim: "2d"`, `title`, empty `items`, and `layer2d`. It does not describe or restrict every existing v1 scene.
Empty base items let the three draft scenes stand alone without duplicating old item grammar. A later engine branch
must compose this extension with authoritative `MGParser` validation of legacy fields, preserving all existing
accepted inputs, refusal reasons and limits. If composition with nonempty legacy items is offered later, the layer
draws above base items, uses its own ID namespace and has no cross-namespace references in this draft.

**Opt-in contract:** the future parser/export entry points require `programmaticVideo: true`; default is false.
When false, the existing parser behavior remains byte-for-byte compatible (including rejection of `layer2d` as an
unknown key). Unknown extension versions fail closed. Do not register new templates globally or activate on import.
The public engine addition can land separately; Morrowdock enables it only in owner-internal builds until after the
2026-12-08 launch. Ordinary public builds keep it off. Dates are targets, not release guarantees.

### Proposed deterministic semantics

- Canvas units are logical pixels, origin bottom-left, +x right, +y up, separate from the v1 world-unit grid.
  Fit to the output with uniform scale and letterboxing. `at` is the shape centre, label baseline centre,
  code first-line baseline left, axes origin, number-line left endpoint, or arrow tail. Arrow `to` is an absolute
  canvas endpoint; animating its tail does not implicitly move its head. Array order defines painting order.
- Base state applies at frame 0. One track per target; IDs are unique. Keyframes start at 0 and increase strictly;
  all are less than `durationFrames`. Every keyframe in a track must name the same nonempty property set.
  Between keys, `linear` interpolates positions/opacity and `hold` retains the previous value until the next key.
  After the last key, retain its values. Highlight changes require `hold`; 0 means no highlight, 1-based values
  select an existing line. Elements cannot change kind. There are no callbacks, expressions, imports or loops.
- Frame index is the clock: `t = frame / 30`. Render exactly `durationFrames` frames, indices 0 through N−1,
  with end time N/30. Wall-clock speed, playback pauses and dropped UI frames never change exported state.
  The adapter uses explicit frame state rather than the interactive timeline's spring blend or perpetual loops.
- Same canonical input, engine build, bundled fonts and export settings must yield the same checked plan,
  positions, captions and refusal tokens. Raster/encoded bytes across devices or OS versions are **pending**
  measurement, not promised identical. No network fonts or assets, randomness, host time or locale formatting.

### Proposed verify-in-MG rule

**Nothing previews or exports until MartyGraphics has checked the complete scene.** Schema success alone grants no
preview permission. Do not show an unvalidated streaming layer. The engine parses bounded UTF-8 data, compiles a
finite plan, validates IDs, targets, ordered frame times, highlight indices, axis ranges (min < max), finite numbers,
geometry, safe text and resources, then returns an immutable checked plan tied to input/build hashes. Typed Swift
construction must take the same path. An edit invalidates the plan and requires a full recheck.

Proposed bounds: 64 KiB raw extension input, nesting ≤16, 64 elements, 64 tracks, 120 keys per track,
1,800 frames (60 seconds), 60 captions, and the per-field schema limits. Enforce aggregate glyph/geometry work
and canonical bytes at runtime as well as per-array bounds. Check layout at all exported frames (at most 1,800),
including text extents, arrows, ticks and captions: refuse clipped/unreadable teaching text or resource overflow;
report deliberate shape overlaps without pretending all overlap is wrong. Reserve bottom 96 canvas units for
captions and a fixed visible generated-media label. Axes/number-line tick count includes endpoints and ranges
are uniformly spaced; axis text uses a pinned locale-independent formatter.

Captions have nonoverlapping half-open `[startFrame, endFrame)` intervals with start < end ≤ duration. Apply the
existing engine text safety policy (no URLs, markup or control/bidi abuse), adapted for literal code display without
placeholder evaluation. Missing references, duplicate IDs and bad frames return stable proposed reason families
such as `video2d.target`, `video2d.frame`, `video2d.text`, `video2d.layout` and `video2d.budget` plus JSON paths.
No partial plan escapes on refusal. Exact reason catalog additions belong in the engine PR.

This checks bounded execution, timing and layout; it does **not** prove sorting correctness, physical laws, Git
semantics or caption truth. Authored/sampled numbers are not “solved facts”. Physics examples must state units,
assumptions and approximation. Any later computed-fact binding must preserve existing honesty rules.

### Proposed public Swift API sketch

These names are illustrative, **not existing declarations**. Value types contain bounded declarative data;
constructors do not bypass checks. The checked-plan initializer is engine-private.

```swift
public struct MGProgrammaticVideoOptions: Sendable {
    public var programmaticVideo: Bool = false
}
public enum MGVideo2DElement: Sendable {
    case shape(MGVideoShape), arrow(MGVideoArrow), label(MGVideoLabel)
    case axes(MGVideoAxes), numberLine(MGVideoNumberLine), code(MGVideoCode)
}
public struct MGVideo2DLayer: Sendable { /* version, canvas, elements, tracks, captions */ }
public struct MGVideoTrack: Sendable { /* target, interpolation, keyframes */ }
public struct MGCheckedVideoPlan: Sendable { /* immutable frames, checks, source hash */ }
public enum MGVideoFormat: Sendable { case mp4, gif }
public enum MGVideoCaptionMode: Sendable { case burnedIn, srt, both }
public struct MGVideoExportOptions: Sendable { /* format, dimensions, caption mode */ }
public struct MGVideoExportReceipt: Sendable { /* hashes, settings, frames, warnings */ }
public enum MGProgrammaticVideo {
    public static func check(sceneJSON: Data, options: MGProgrammaticVideoOptions)
        throws -> MGCheckedVideoPlan
    public static func check(layer: MGVideo2DLayer, options: MGProgrammaticVideoOptions)
        throws -> MGCheckedVideoPlan
    public static func frame(_ index: Int, in plan: MGCheckedVideoPlan) throws -> MGRenderInput
    public static func export(_ plan: MGCheckedVideoPlan, to destination: URL,
        options: MGVideoExportOptions) async throws -> MGVideoExportReceipt
}
```

`MGVideoShape/Arrow/Label/Axes/NumberLine/Code` carry the matching schema fields; keyframe values are typed
position, opacity or code-line highlight. The builder should settle exact initializer and renderer signatures on its
feature branch. A destination is a host-granted local URL, never a path supplied in scene data. Export supports
Swift task cancellation and progress through a bounded host callback/stream; that callback is not scene code.

## Proposed on-device export and budgets

Render checked frames offscreen using native 2D drawing. Feed pooled BGRA buffers to **AVFoundation
AVAssetWriter → MP4**, H.264, exactly 30 fps, up to 1,920×1,080. Require even output dimensions, validate supported
encoder settings up front, preserve aspect ratio and tag the color space. Use integer `CMTime(frame, timescale: 30)`;
wait for writer readiness with a timeout, keep a bounded queue, and check append and finish errors. No array of all
frames, PNG intermediate sequence, audio, speech, or FFmpeg dependency. Finalize to an app-private partial file,
then atomically publish only a successful complete export. Cancellation/failure removes partial outputs.

Use **ImageIO → GIF**, sequential frame addition, bounded downscale and palette handling. Proposed GIF preset:
640-pixel longest edge, at most 15 seconds, 10 fps by sampling every third checked source frame, 0.1-second frame
delay, loop forever. Require GIF source duration divisible by three frames and ≤450 frames; refuse incompatible
requests rather than silently truncating. The underlying scene clock stays 30 fps. GIF has no embedded captions;
burn them in, optionally also write `.srt`. MP4 allows burn-in, `.srt`, or both; default both. Generate SRT cues from
the same frame intervals, rounding endpoints to nearest millisecond, not from wall time. Always burn in the
`Generated educational animation` label, including when captions are sidecar-only. No voice or face generation.

**Proposed iPad acceptance budget; device evidence pending:**

| Resource | Initial target and response |
| --- | --- |
| Memory | ≤128 MiB incremental peak for export above idle app. Three 1080p BGRA buffers are about 24 MiB; include raster, fonts and encoder overhead in measured peak. ImageIO buffering may grow: enforce GIF bounds and measure, not assume streaming is constant-memory. |
| Time | 60-second 720p MP4 in ≤120 seconds; 1080p in ≤180 seconds on the oldest supported iPad test device. GIF preset in ≤30 seconds. Check in ≤2 seconds for the three small fixtures. These are acceptance targets, not observed performance. |
| Responsiveness | Cancel within 1 second, keep UI responsive, yield under thermal pressure; stop safely on background suspension/memory warning rather than claiming completion. |
| Storage | Preflight estimated output plus partial-file headroom; propose a 256 MiB output cap and refuse cleanly on low space. Never overwrite a destination without host authorization. |

Record named device/OS/build, peak memory, elapsed time, frame count and decode/duration checks before acceptance.
If a target fails, offer a user-selected lower preset or return a budget refusal; do not silently change timing or
send work to a server. Export receipts include canonical scene hash, engine version, font/settings identifiers,
format, dimensions, fps, frames, captions, label, warnings and output hashes, without learner identity.

## Proposed authoring paths and student safety

1. **Hand-written JSON:** editor/import → size check → schema feedback → authoritative engine check → checked
   preview → explicit Export. Imports never execute text or automatically write media.
2. **Learner Python:** the app's proposed Animate it integration uses Pyodide inside a WKWebView sandbox to
   calculate samples and **emit scene data only** over a narrow, size-bounded message bridge. This is host-app work,
   not a Python runtime added to MartyGraphics. The engine never receives or executes Python. A teaching helper
   can emit keyframes from a list or loop; no Python expression reaches the renderer.
3. **Marty drafting:** the agent drafts the same JSON and handles precise refusal feedback. It cannot bypass
   verification, export consent or course review. Cloud assistance, if separately enabled by the user/app policy,
   is outside the offline render guarantee; offline editing, preview and export must never depend on it.

Offline by default. The app must bundle Pyodide and approved packages and deny network, navigation, popups,
file-picker/download and arbitrary native bridge access. “No file access” includes no host files and no learner
filesystem APIs; an in-memory runtime alone is insufficient. Pyodide/WKWebView is **not by itself a security
boundary against arbitrary Python/JS access**. Block JS interop/import escape routes and filesystem entry points,
use a restricted execution surface plus host request denial, and test attempted `fetch`, sockets, file reads,
`js` interop, infinite loops and oversized bridge output. Set proposed 2-second run/64-KiB emit budgets and tear
down the execution worker on timeout. The sandbox may not ship until its no-file/no-network claim is demonstrated;
if it cannot be enforced, retain hand-written JSON and postpone Python. No private app filesystem is exposed.

Export happens only through an explicit user action and the system destination/share UI; no auto-upload or
background publication. Catalog sharing goes only through course review: **two independent AI fact-checks plus
human approval**, including captions, visuals, numeric assumptions and generated-media disclosure. Engine acceptance
alone is insufficient. Templates use original synthetic data and contain no faces, voices, names, profiles or
personal data. Do not log learner code or scene contents by default. Strip identity from receipts. Reject external
assets/URLs in this draft. Generated media stays visibly labelled in preview and exported output.

## Alternatives and licence evidence

The following licence observations are **verified from primary sources on 2026-11-15 UTC**; upstream terms can
change. Source snapshots: Remotion `cc7879e13f7dc5ef33d8d735ffee33c94e983b47`, Motion Canvas
`7b91435c301d530351dcf5ebb91dd139c002e405`, Revideo `b5de67a009a55aa2768a1e178b0446b2479a0b4e`.
Runtime requirements are supported by the linked upstream docs/source. No upstream code is imported here.

| Alternative | Primary licence and runtime evidence | Fit for this proposal |
| --- | --- | --- |
| Remotion | [Remotion License](https://github.com/remotion-dev/remotion/blob/cc7879e13f7dc5ef33d8d735ffee33c94e983b47/LICENSE.md), source-available rather than MIT/Apache. Free for individuals, for-profit organizations up to 3 employees, and non-profits; for-profit companies with 4+ need a Company License. [Rendering docs](https://www.remotion.dev/docs/renderer) and [browser provisioning](https://www.remotion.dev/docs/renderer/ensure-browser) describe Node.js and headless Chrome/Chromium rendering. | Good React video tooling; company licence obligations and Node + headless Chromium do not fit a small offline native iPad export path. |
| Motion Canvas | [MIT licence](https://github.com/motion-canvas/motion-canvas/blob/7b91435c301d530351dcf5ebb91dd139c002e405/LICENSE); [getting started](https://motioncanvas.io/docs/quickstart/) describes its Node/browser/TypeScript toolchain. | Permissive and expressive, but brings a separate authoring/runtime stack and executable animation programs. |
| Revideo | [MIT licence](https://github.com/redotvideo/revideo/blob/b5de67a009a55aa2768a1e178b0446b2479a0b4e/LICENSE). Its [telemetry source](https://github.com/redotvideo/revideo/blob/b5de67a009a55aa2768a1e178b0446b2479a0b4e/packages/telemetry/src/index.ts) counts render-start and other events using PostHog; `DISABLE_TELEMETRY=true` disables event submission. [Installation source](https://github.com/redotvideo/revideo/blob/b5de67a009a55aa2768a1e178b0446b2479a0b4e/packages/telemetry/src/postinstall.js) documents that switch. | Permissive video framework, but web/server tooling adds runtime and auditing work. Disabling render counting does not by itself prove all dependencies are offline. |

**Proposed choice: native.** It reuses existing timeline/check/render work and system encoders, adds no external
packages, and keeps scene data portable between learner, lesson and agent. The tradeoff is building a smaller
animation vocabulary and validating performance/security ourselves. Do not copy upstream code or claim feature
parity with these frameworks.

## Proposed MVP order, milestones and exclusions

1. **2D layer + MP4/GIF export:** authoritative checks, finite frame adapter, caption/label rendering, cancellable
   library export and receipts. Acceptance: three fixtures pass runtime preflight, deliberate malformed variants
   are refused before preview, legacy fixtures remain unchanged, exported files decode at the expected duration,
   memory/time targets are measured on iPad and Mac. The builder implements this on a separate feature branch.
2. **Animate it lab:** host app adds sorting, ideal projectile and Git branch/merge templates using synthetic data,
   JSON editing and the secured Python emission path. Show model assumptions and explicit export controls.
3. **Marty drafting:** JSON drafts and bounded repairs through the same check gate; retain review and disclosure.

| Target | Status and release gate |
| --- | --- |
| Now, 2026-11-15 | Proposed docs + draft schema + three examples in this docs-only PR; coordinator reviews and merges. |
| Around 2026-11-20 | Proposed separate engine branch: 2D layer + export, opt-in and OFF by default; native correctness/performance receipts required. |
| Before 2026-12-08 | Proposed owner-internal TestFlight validation, gated to internal builds; sandbox and real-device acceptance required before enabling those paths. |
| After launch | Proposed public flip after the 2026-12-08 launch, only with owner approval and review evidence; no date-triggered enablement. |

Out of scope: engine implementation in this PR; 3D authoring expansion; arbitrary Swift/JS/Python execution inside
the engine; external media, music, voiceovers or faces; cloud rendering; automatic publishing; full physics or
algorithm proofs; collaboration; arbitrary user fonts; Remotion compatibility; long-form/video editing; public
app enablement before launch. The draft is not a stable public wire contract.

## Draft examples and validation boundary

Original, synthetic, **proposed** scenes:
[sorting](../examples/programmatic-video/sorting.json),
[projectile](../examples/programmatic-video/projectile.json),
[Git flow](../examples/programmatic-video/git-flow.json).
Sorting shows one adjacent swap, not a full sort. Projectile uses authored samples of an ideal trajectory, with
linear interpolation between samples, not a continuous engine physics solver. Git arrows show teaching sequence,
not commit-parent pointers. No fixture claims checked educational truth.

The existing [SceneValidator](../../tools/SceneValidator/README.md) uses `MGParser` on macOS; it is **not** a JSON
Schema tool, and today's parser correctly rejects `layer2d`. Repository tools contain no general JSON Schema
validator. Do not weaken it or add dependencies for a proposal. Where Python `jsonschema` is already available,
this read-only check validates the schema and examples using Draft 2020-12:

```sh
python3 - <<'PY'
import json
from pathlib import Path
from jsonschema import Draft202012Validator
schema = json.loads(Path('docs/schemas/scene-2d-layer.draft.schema.json').read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)
for path in sorted(Path('docs/examples/programmatic-video').glob('*.json')):
    validator.validate(json.loads(path.read_text()))
    print('PASS', path)
PY
```

Schema validation cannot enforce unique IDs, target existence, increasing frames, uniform track property sets,
axis ordering, highlight line count, caption interval relationships, aggregate bytes or layout bounds. Those checks
are mandatory in the proposed engine preflight. Draft-schema success is not an engine acceptance receipt. macOS/iPad
build, device performance, visual QA and sandbox acceptance remain **pending** for the implementation branch.
