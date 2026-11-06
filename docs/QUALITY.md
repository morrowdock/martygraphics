# Rendering, accessibility, performance and integration evidence

Status: measurement plan and scoped evidence inventory; unrecorded acceptance is pending.

The release baseline `73f9e13bbe1bb72c2cceaff577c93756da83cd6d` passed a Mac build
and 23 tests before publication. That is a functional release receipt, not proof
of renderer performance, accessibility acceptance or independent adoption.
The [native capture receipt](assets/native/provenance.json) records a clean
checkout of showcase source `9b4ba89780af54d7de7f7e4fd209625a2db24f33`: build,
95 tests (zero failures), seven-scene verification and native export all passed.
The eight stills were visually inspected and all three GIFs checked for dimensions,
frame counts, stored delays and metadata. These are scoped export results;
interactive playback, accessibility, performance and adopter acceptance remain pending.

## What a capture proves

A native frame receipt must identify the source revision, original JSON, renderer,
command, OS/Swift build configuration, pixel dimensions, frame timing and hash.
Inspect the output at its intended GitHub display width as well as full size.
Look for clipped/overlapping labels, missing items, broken references, step/value
mismatches and unreadable small text. A successful export can still render badly.

An offscreen frame is not a physical-device screenshot, an interactive frame-rate
measurement, or a screen-reader test. The current showcase covers 2D; the library's
SceneKit renderer needs a separate interactive/device capture receipt.

## Representative acceptance work

| Dimension | Concrete exercise | Required receipt / current limit |
| --- | --- | --- |
| Layout and text | Short/long labels, dense nodes, extreme valid viewport ratios and maximum supported items; inspect each step. | Fixed inputs, dimensions, screenshots and overlap/clipping findings. The small showcase is not maximum-bound coverage. |
| Keyboard | Reach scene picker and board controls; operate steps/playback; verify focus visibility and no keyboard trap. | Exact app/OS build and action/result notes. A generated PNG does not establish this. |
| VoiceOver | Read title/current narration, controls and their state; verify meaning when the diagram cannot be seen. | Human or instrumented accessibility receipt, with missing semantics recorded. No blanket screen-reader support claim. |
| Reduce Motion | Enable system preference; switch scenes, change steps and play/stop. | Confirm actual animation policy and static alternatives; the exporter intentionally samples motion and is not the native preference test. |
| First scene / update latency | Warm and cold runs with exact fixture sizes; timestamp request, parse/layout, first display and patch-visible completion. | Named hardware/toolchain, build configuration, sample count, median/p95 and raw method; separate offscreen rendering from interactive display latency. |
| Memory | Repeated scene swaps, stream rejection/recovery and worst permitted geometry in an instrumented host. | Peak/resident memory, iteration count, teardown behavior and profiling method. No memory target is met just because tests pass. |
| Failed updates | Stale revisions, invalid refs/cycles, partial streams and limit violations. | Old scene remains intact; reference and malformed-input regressions run at the exact candidate. |
| Independent adoption | A developer integrates the public package in a clean host app using the tutorial, without private files or author guidance. | Dependencies, copied steps, errors/fixes, launch result and accessibility limitations. An internal example build is not an adopter exercise. |

## Bounds and changes

Preserve the current [bounds](CAPABILITIES.md#bounds-are-part-of-the-contract).
Propose an expansion only when a real public example needs it; measure old and
proposed maxima, add boundary/failure tests and review protocol compatibility.
No limit, renderer behavior or private domain pack is changed by this showcase.

## Roadmap from gaps

Prioritize demonstrated gaps: a clean runnable starter, legible cross-domain
examples, accessible control/scene semantics, reproducible rendering cost and an
independent integration. Portable renderer work follows the dependency/parity
[proposal](PORTABILITY-PROPOSAL.md), not an assumption that a framework rewrite
will resolve these quality issues.

Published asset receipts and measurements belong next to their actual source
revision. Pending items remain pending until the corresponding receipt exists.
