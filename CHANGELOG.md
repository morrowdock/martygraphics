# Changelog

## Unreleased

- **Faster CI that does not block merges.** The hosted macOS tests now run in four shards on four `macos-26`
  runners at the same time (about 13 minutes instead of about 43). Every split is a `--filter` shard plus a `--skip`
  shard with the same pattern, so no test is dropped; a filter shard that runs no test fails. No test changed, tests
  in one shard still run one at a time, and there are still no caches. `macos` (a short job that passes only when
  all shards pass) still runs on every pull request and push, but it is no longer a required merge check: the
  required checks are `hygiene` and `maintainer/local-validation`. A red `macos` after a merge is fixed or reverted
  at once.

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
