# Changelog

## Unreleased

- **The `studio` and `paper` looks draw modern type, plates and bands (pixels only).** No black title or caption
  bars: text sits on the look's own backdrop in the look's ink, with measured contrast of at least 4.5:1. Label
  plates are rounded with a hairline edge and a tier bar; leaders have a casing and a ringed anchor; every drawn
  metric is a multiple of the label font size. The model's cut at a band fades into the backdrop. Band sizes, the
  safe window, framing, font sizes, line breaks, label boxes and every JSON output are unchanged; `classic` draws as
  before. Turning marks on machined metals are a little fainter.
- **The `studio` and `paper` looks finish surfaces (pixels only).** Parts reflect a procedural product studio with
  soft-edged boxes, so metals show gradients; plastics get a glossy clear coat and a calibrated colour of the same
  hue; machined metals get fine per-fragment turning marks; ambient occlusion no longer draws faint rings on curved
  faces; the radial streaks on flat gear faces are gone in these looks. `classic` is unchanged, and so are the
  exported material parameters, the rig in `snapshot.json` and every check report.
  [docs/SOLID-3D.md](docs/SOLID-3D.md#looks-and-quality) has the before and after.
- **Looks and quality levels for the built-in renderer (pixels only).** `marty-solid render --look
  classic|studio|paper` and `MGSolidRenderer(document:look:)` choose how a solid is presented: `studio` is a graphite
  studio sweep with a pool of light under the subject, `paper` a near-white one; both make shadows land on a floor,
  keep the outline of dark parts and the form of white parts, and use a dithered backdrop that does not band.
  `classic` (the default) is the renderer as it was. `MGSolidQuality` (`interactive`, `balanced`, `still`) sets the
  cost of a frame through `MGStudioOptions(quality:)`; `still` equals `MGStudioOptions()`. The explainer view takes
  both (`MGExplainerController.solidLook`, `solidQuality`, default `balanced`: 16 shadow samples instead of 24). No
  check report or snapshot changes for any look (tested). The render `manifest.json` gains one member, `look` (the
  look the images were drawn with), so the four render goldens gain the line `"look" : "classic"` and nothing else. Design:
  [docs/VISUAL-STYLE.md](docs/VISUAL-STYLE.md); details: [docs/SOLID-3D.md](docs/SOLID-3D.md#looks-and-quality).
- **Transcript export (v0.2 G2).** `marty-solid transcript FILE.json [--strict]` and `MGTranscript` print every
  caption, every shown label, arrow and dimension text, and every board table, per beat, as plain reflowable text for
  screen readers, large text and a static equivalent ([docs/EXPLAINER.md](docs/EXPLAINER.md#transcript)). The format is
  the one the Part 107 course transcripts were written in by hand (`morrowdock-explainer-transcript` v1), so the
  engine now makes them. The document is checked first; a refused document prints its check report. Read-only: no
  check, report or render output changes. Golden transcripts for the five drone explainers, the jet-suit lesson and a
  board-only explainer. Closes the transcript workaround of a recorded course gap (no label size key).
- **Faster CI that does not block merges.** The hosted macOS tests now run in four shards on four `macos-26`
  runners at the same time (about 13 minutes instead of about 43). Every split is a `--filter` shard plus a `--skip`
  shard with the same pattern, so no test is dropped; a filter shard that runs no test fails. No test changed, tests
  in one shard still run one at a time, and there are still no caches. `macos` (a short job that passes only when
  all shards pass) still runs on every pull request and push, but it is no longer a required merge check: the
  required checks are `hygiene` and `maintainer/local-validation`. A red `macos` after a merge is fixed or reverted
  at once.
- **Drone and aviation explainers (docs only, no engine change).** `docs/assets/drone-aviation` adds five hand-built
  explainers made with the engine as it is: quadcopter steering, payload position and centre of gravity, a brushless
  outrunner motor, a three-axis camera gimbal and a landing gear over-centre lock. Each folder holds the document, the exact brief, every attempt
  (39 in all: 14 refused, 2 of them deliberate negative controls), the strict check output, a story video and stills.
  `FACTS.md` lists every claim with a source and what the engine checked. Two independent fact checks (Sol and
  Gemini) found no wrong claim; all 16 fixes are applied to the captions, labels and `FACTS.md` (words only), with a
  new render of the story videos and of the stills whose words changed.
  `GAPS.md` lists what the frozen engine could not show (the helicopter swashplate topic was dropped), with exact
  refusal texts. `docs/SHOWCASE.md` has a new section. Golden check files for the eleven new JSON files.

## v0.1.0 — 2026-11-11

The first tagged release. **Early preview:** the API and the JSON formats can still change. Swift 6, macOS 14+ and
iOS 17+, no external packages. Every change in full: [docs/HISTORY.md](docs/HISTORY.md).

### What it does

- **Kinematically checked 3D mechanism explainers.** A Foundation-only solid kernel (extrude, revolve, tube, involute
  spur and ring gears, blades and blade rows, capped partial revolves) and assemblies with revolute and prismatic
  joints and gear meshes, solved from one input. A closed-key JSON format (assembly v1 and v2) refuses a wrong
  document with one stable reason and the part, for example `constraint.gearMesh.phase` on `ring1`
  ([reason catalog](docs/REASONS.md)). v2 adds section cuts, see-through parts, labels, arrows and measured
  dimensions, reusable components and a facts table: a caption takes its numbers from the solved values.
- **Explainer documents.** One document drives a 2D board, a 3D solid or both on one beat timeline, with one legend
  that counts only what the learner was shown ([docs/EXPLAINER.md](docs/EXPLAINER.md)).
- **A strict check made for AI authors.** `--strict` refuses labels and arrows that a step does not show, gravity and
  dimension claims that motion can break (with proven bounds), and text numbers that the engine did not compute.
  Reports give exact, validated repairs.
- **`marty-solid`** (`Examples/Solid3D`): `check` prints the JSON report; `render` writes stills, a loop, a story
  video and a manifest with digests.
- **2D scenes and lessons.** Validated v1 scenes for SwiftUI diagrams, plots, arrays and trees, with templates,
  patches and streaming; beat-by-beat lessons with saved state ([docs/LESSONS.md](docs/LESSONS.md)).
- **Also:** `MartyGraphicsPathTracer` (Metal path tracing), 3D inspection hooks, `marty-scene-validate` and the
  `Examples/`. Hosted CI (`hygiene`, `macos`) gates every merge.

### Shown with real output

- A schematic two-spool turbofan cutaway from 38 lines of example JSON, written directly in the format, not from a
  prompt ([docs/assets/turbofan](docs/assets/turbofan)).
- A robot-joint gearbox from a prompt: Claude Haiku 5.5 wrote it, the engine refused try 1
  (`constraint.gearMesh.phase`: 20 + 56 does not divide by 3) and accepted try 2
  ([docs/assets/from-a-prompt/robot-joint](docs/assets/from-a-prompt/robot-joint)).
- An AI-written jet-suit lesson (Claude Opus 5.5 through Marty), shown unedited beside an independent fact check that
  found 1 wrong sentence and 12 corrections ([docs/SHOWCASE.md](docs/SHOWCASE.md)).

### Next: a blind benchmark

[benchmark/mechanisms-v1](benchmark/mechanisms-v1/README.md) pre-registers a comparison of MartyGraphics through Marty
against the same model writing three.js directly, on 20 mechanism questions. It is design only and not run; there is
no result yet.

### Limits

- Not checked: the meaning of words, strength, load, wear, friction, air or gas flow, forces other than the gravity
  direction, and collisions. Gear contact is checked in 2D at sampled angles. The only linkage is the slider-crank;
  there are no helical or bevel gears, belts or cams ([docs/SOLID-3D.md](docs/SOLID-3D.md#limits-1)).
- "Solved" in a legend means a ratio computed from the model's own joints and drives, not a fact about the real object.
- Reliability is not good enough yet. In a 50-question development test, Claude Haiku 5.5 got all 40 in-scope
  questions accepted within three repairs, but only 29 of 40 were fully correct in mechanics.
- The renderers need Apple frameworks. Windows, Linux and browser builds are not supported.
- Parses, reports, cameras, layout and snapshots are byte-identical across processes; 3D pixels are not (at most
  5.02 % of the pixels in a still differed, measured 2026-11-10).
- The remote Swift Package Manager install is checked after tagging ([docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)).

### How it was made

AI agents (mainly Claude Opus 5.5) wrote the code and the docs under the direction of Collin Craig. After the first
import commits, changes went through pull requests with recorded local checks and independent reviews by other AI
models. The fact checks are AI model checks with web access, not an engineer's review. The
showcase runs were picked after grading from the runs that passed, and the 50-question set was used to
tune the engine, so its results are not held-out evidence.
