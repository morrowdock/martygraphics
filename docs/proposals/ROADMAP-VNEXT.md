# MartyGraphics vNext: what the best teaching-visual tools do, and a ranked roadmap

**Status:** proposal, 2026-11-26. The top three items are implemented on branch `feat/vnext-kinds`. They are
**pending Mac verification**: written and checked offline on a Windows machine with no Swift toolchain, where the
Python mirror of the new rules ran and passed. No Swift build or test has run yet. Nothing here is released.

**Method.** I read the public documentation of the tools below, as surfaced by web searches on 2026-11-26 (search
summaries of the official pages, not full manual reads), and mapped each capability against this repository:
[CAPABILITIES.md](../CAPABILITIES.md), [PROTOCOL.md](../PROTOCOL.md), the item kinds in
[MGModel.swift](../../Sources/MartyGraphics/MGModel.swift), the [ML explainer kit](../ML-EXPLAINER.md) and
[Solid 3D](../SOLID-3D.md). Version-specific details should be checked on each tool's page before quoting them.

## What the best tools do

| Dimension | What the leaders do | Sources |
| --- | --- | --- |
| Item kinds | Function graphs from an expression (Desmos, GeoGebra, Manim `FunctionGraph`/`ParametricFunction`, Mafs `Plot.OfX`), vector fields and stream lines (Manim `ArrowVectorField`, `StreamLines`; Mafs `Plot.VectorField`; GeoGebra `SlopeField`), simulations (PhET), hand-drawn diagrams from text (Excalidraw, Mermaid), data marks with scales and transforms (Observable Plot) | [Manim ParametricFunction](https://docs.manim.community/en/stable/reference/manim.mobject.graphing.functions.ParametricFunction.html), [Manim ArrowVectorField](https://docs.manim.community/en/stable/reference/manim.mobject.vector_field.ArrowVectorField.html), [Manim StreamLines](https://docs.manim.community/en/stable/reference/manim.mobject.vector_field.StreamLines.html), [Mafs vector fields](https://mafs.pages.dev/guides/display/vector-fields), [GeoGebra SlopeField](https://geogebra.github.io/docs/manual/en/commands/SlopeField), [PhET Wave on a String](https://phet.colorado.edu/en/simulation/wave-on-a-string), [Mermaid to Excalidraw](https://docs.excalidraw.com/docs/@excalidraw/mermaid-to-excalidraw/api) |
| Animation and easing | Named rate functions (ease in, out, in-out) per animation (Manim, Motion Canvas), springs (Motion Canvas `PlopSpring`, `SmoothSpring`), morphs between shapes and matching equation parts (Manim `Transform`, `TransformMatchingTex`), redraw from a tracked value every frame (Manim `ValueTracker` + `always_redraw`), diff-based code animation (Motion Canvas Code node) | [Manim rate functions](https://docs.manim.community/en/stable/reference/manim.utils.rate_functions.html), [Motion Canvas tweening](https://motioncanvas.io/docs/tweening), [TransformMatchingTex](https://docs.manim.community/en/stable/reference/manim.animation.transform_matching_parts.TransformMatchingTex.html), [always_redraw](https://docs.manim.community/en/stable/reference/manim.animation.updaters.mobject_update_utils.html), [Motion Canvas Code](https://motioncanvas.io/docs/code) |
| Interaction | Sliders bound to parameters with animate controls (Desmos), movable points (Desmos, Mafs `useMovablePoint`), pointer tips and crosshairs (Observable Plot), reactive documents whose numbers readers drag (Bret Victor's explorable explanations) | [Desmos sliders](https://help.desmos.com/hc/en-us/articles/202529069-Sliders-and-Movable-Points), [Observable Plot interactions](https://observablehq.com/plot/features/interactions), [Explorable Explanations](https://worrydream.com/ExplorableExplanations/) |
| Authoring ergonomics | Text first: an expression list (Desmos), a diagram from Mermaid text (Excalidraw), declarative substance and style files with constraint layout (Penrose), code-defined scenes (Manim, Motion Canvas). Penrose's optimiser is designed to always return a diagram, which a 2024 paper notes can mislead when constraints cannot be met | [Penrose docs](https://penrose.cs.cmu.edu/docs/ref/), [arXiv 2412.03310](https://arxiv.org/pdf/2412.03310) |
| Accessibility | Audio trace of a curve, point-of-interest summaries, screen reader and Braille support (Desmos); WCAG 2.2 AA keyboard and screen-reader support (GeoGebra); interactive description, sonification and Voicing (PhET); `ariaLabel` / `ariaDescription` on plots and axes (Observable Plot); OS audio graphs from a chart descriptor (Apple `AXChartDescriptor`); long descriptions for complex images (W3C WAI, NCAM/DIAGRAM STEM guidelines); reduced motion (WCAG 2.3.3) | [Desmos accessibility](https://help.desmos.com/hc/en-us/articles/4404860698253), [Desmos audio trace](https://help.desmos.com/hc/en-us/articles/37064105800333-Audio-Trace), [GeoGebra accessibility](https://help.geogebra.org/hc/en-us/articles/20048444963869-Accessibility), [PhET Voicing study](https://par.nsf.gov/biblio/10397994), [Observable Plot accessibility](https://observablehq.com/plot/features/accessibility), [Apple audio graphs](https://developer.apple.com/documentation/accessibility/representing-chart-data-as-an-audio-graph), [WAI complex images](https://www.w3.org/WAI/tutorials/images/complex), [NCAM STEM image descriptions](https://www.wgbh.org/ncam-resources/2026-08-25/effective-practices-for-description-of-science-content-guidelines-for-describing-stem-images), [WCAG 2.3.3](https://w3.org/WAI/WCAG21/Understanding/animation-from-interactions) |
| Export | MP4/GIF/PNG sequences (Manim, Motion Canvas image-sequence and FFmpeg exporters), SVG/PNG with the scene embedded (Excalidraw), SVG (Observable Plot) | [Motion Canvas image sequence](https://motioncanvas.io/docs/rendering/image-sequence), [Motion Canvas video](https://motioncanvas.io/docs/rendering/video), [Excalidraw export](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/utils/export) |

Why accessibility ranks high: public schools, colleges and universities in the US must meet WCAG 2.1 AA for web
content and apps under the ADA Title II rule. The April 2026 interim final rule moved the deadlines to April 2027
(entities serving 50,000 or more people) and April 2028 (smaller ones), and left the standard unchanged
([Federal Register 2026-07663](https://www.govinfo.gov/content/pkg/FR-2026-04-20/html/2026-07663.htm),
[EDUCAUSE](https://er.educause.edu/articles/2026/6/doj-and-hhs-extend-web-accessibility-deadlines-to-2027-2028)).
A teaching visual without a text alternative does not meet WCAG 1.1.1.

Why the expression grammar is closed: `NSExpression` string expressions can invoke arbitrary methods through the
`FUNCTION` form, a technique used in a published iMessage sandbox escape
([Project Zero, FORCEDENTRY](https://projectzero.google/2022/03/forcedentry-sandbox-escape.html)). The engine
must never hand model-written text to such an evaluator.

## Where MartyGraphics stands

Strengths the others mostly lack: one closed, bounded wire format with stable refusal reasons the model repairs
from; checked motion (Solid 3D gear meshes and joints); numbers in captions from the engine; deterministic
parse, layout and timing; fail-closed patches and streaming; honesty labels ("Solved", "Data as given").

Gaps before this branch (2D): no way to plot a function except by listing up to 64 points the model computed
itself (its arithmetic was never checked); no fields; no per-step or per-scene text alternative (VoiceOver read the
title and the narration only); one fixed transition (a damped spring); no sliders bound to plotted parameters; no
audio graphs; no math typography; no SVG or PDF export; the board is always dark.

## Ranked upgrades

Effort: S (days), M (one to two weeks), L (several weeks), XL (a quarter). Protocol: wire impact on scene v1.
Limits: whether the closed-key limits change (new bounds for a new shape only never change existing ones).

| # | Upgrade | Value to learners and teachers | Effort | Risk | Protocol | Limits | Accessibility |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **`func` engine-sampled function graphs** (closed expression grammar, gaps and poles, shading, marked point, parameters, seamless moving graphs) — *implemented* | Very high: the core of school maths and physics; plotted values come from the engine, not the model | M | Medium: expression safety (closed grammar, no host evaluator), frame cost of re-sampling on step replay | Additive kind | New bounds only | Described by `MGDescribe` |
| 2 | **Text alternatives**: `alt` on scenes and steps, engine-written board descriptions, VoiceOver wiring — *implemented* | High: blind and low-vision learners; WCAG 1.1.1; institutional adoption | S | Low | Additive root and step key | None new (reuses the narration limit) | Large |
| 3 | **`field` vector and slope fields** (arrows, unit, slope styles; honest magnitude note) — *implemented* | High: electric and magnetic fields, flow, differential equations | M | Low | Additive kind | New bounds only | Described by `MGDescribe` |
| 4 | Audio graphs for `func`, `plot` and `bars` (through Apple's `AXChartDescriptor`): a VoiceOver user could play a series as a tone that rises and falls with the value, step from point to point and hear each x and y read out, jump to the start, the end and the marked point, and hear a summary of the axes and ranges | High for blind learners: the shape of a curve and its values without seeing it | M | Medium: needs device VoiceOver testing (not available in the simulator) | None | None | Very large |
| 5 | Learner sliders bound to `func`/`field` parameters `a`, `b`, `c` (extend lesson `bind`) | High: Desmos-style what-ifs; explorables | M | Medium: lesson protocol change | Additive lesson control target | One new bound (controls per board) | Needs an adjustable accessibility action |
| 6 | Engine-computed calculus numbers: tangent line at the mark, area of the shaded band, derivative, as placeholders (`{wave.area}`) with an error bound | High: integrals and slopes with checked numbers in captions | M | Medium: numerical claims must carry a stated accuracy | Additive keys and placeholders | New bounds only | Numbers become speakable text |
| 7 | Eased and timed step transitions (`ease`: spring, smooth, linear, none; `dur` 0.2–3 s) honouring Reduce Motion | Medium-high: pacing and morphs; WCAG 2.3.3 | S | Low | Additive step keys | One small enum and range | Positive (reduced motion) |
| 8 | Math typography: a bounded `math` text style (superscripts, fractions, Greek, roots) with a spoken form | High: labels such as y = a sin x read as maths | L | Medium: text measurement and layout | Additive text style | New bounds only | Needs speech text for each formula |
| 9 | Parametric and polar curves (`curve`: x(t), y(t); r(θ)) reusing the grammar and sampler | Medium-high: circles, cycloids, orbits, Lissajous figures | M | Low | Additive kind | New bounds only | Described |
| 10 | Captions and transcript export for walkthroughs (WebVTT/SRT with the `alt` track) | Medium-high: WCAG 1.2.2 captions and 1.2.5 audio description for exported video | S–M | Low | None | None | Large |
| 11 | VoiceOver navigation between items (a rotor of `MGDescribe.item` phrases, highlight on focus) | High for screen-reader users of dense boards | M | Medium: device testing | None | None | Large |
| 12 | Simulation kinds with checked integration (pendulum, mass-spring, projectile with drag; RK4 with an energy-drift check) | Medium-high: PhET-style labs | L | Medium: numerical honesty | Additive kinds | New bounds only | Described |
| 13 | Geometry constructions (points, segments, circles, angle markers with engine-measured labels) | High for geometry | L | Medium: constraint semantics | Additive kinds | New bounds only | Described |
| 14 | Data marks with engine transforms (scatter, histogram bins, least-squares line) | Medium-high: statistics | M–L | Low | Additive kinds | New bounds only | Described, audio graphs |
| 15 | Light and print theme, contrast and colour-vision checks of the palette | Medium: projectors and handouts; WCAG 1.4.3 / 1.4.11 | S–M | Low | None | None | Positive |
| 16 | Transform-matching morphs (match items by id across steps; cross-fade text; match code lines) | Medium: 3Blue1Brown-style continuity | M–L | Medium | None or additive step key | None | Neutral |
| 17 | Stream lines and particles for `field` | Medium | M | Medium: frame cost | Additive style | New bound (lines) | Described |
| 18 | SVG and PDF export of 2D boards | Medium: print, slides, web | M | Low | None | None | Text stays selectable in PDF |
| 19 | Number line and interval kind (inequalities, open and closed ends) | Medium: algebra | S | Low | Additive kind | New bounds only | Described |
| 20 | Diff-based code animation for `code` text | Medium: computing lessons | M | Low–medium | Additive step edit semantics | None | Neutral |
| 21 | Draggable constrained points (a mark that moves along its curve) | Medium-high: explorables | L | High: interaction semantics and accessible alternatives | Additive interaction key | New bounds | Needs an accessible alternative |
| 22 | Hand-drawn sketch look (rough strokes) | Low–medium: engagement | M | Low | None (theme) | None | Neutral |
| 23 | Portable core and browser renderer | High reach | XL | High | None (same wire) | None | Web accessibility work |

Item 23 is tracked in the [portability proposal](../PORTABILITY-PROPOSAL.md) and is not ranked against the rest.

## What this branch implements (items 1–3)

All three follow the v1 rules: closed keys, bounded values, refusal with one stable reason, the validator first, and
no change to any existing scene.

| | `func` | `field` | `alt` text |
| --- | --- | --- | --- |
| Model | `MGKind.function` (wire `func`); samples in `pts`, piece starts in `marked`, marked value in `num["my"]` | `MGKind.field`; one vector per cell in `pts`, cells without a value in `marked` | `MGScene.alt`, `MGStep.alt` |
| Parser | `MGParser.item`, `MGExpression` (grammar), `MGGraph.checkFunction` (drawing checks) | `MGParser.item`, `MGGraph.fieldVectors` | root and step keys; template steps |
| Renderer | `MGCanvasRenderer.functionGraph`, shared `graphFrame` | `MGCanvasRenderer.vectorField` | `MartyGraphicsView` VoiceOver value; `describesBoard()` |
| Motion | `period` + `t`: `MGTimeline.frame` re-samples; `cycle`, `animates` | static | none |
| Describe | `MGDescribe.item` | `MGDescribe.item` | `MGDescribe.board`, `accessibilityValue` |
| New bounds | expression 80 scalars / 48 tokens / 8 parentheses; 257 samples; 16 breaks; 1 % of frame height; parameters ±1,000; period 0.5–20 s; 6 graph items per scene | 2–16 × 2–12 arrows | 200 characters (the narration limit) |

Each bound is derived in the source (`MGLimits`): one evaluation is at most 48 operations; a `func` costs at most
7,169 evaluations per checked instant and a moving one at most 29,190, so six are at most 175,140 (a typical smooth
graph needs 513 per instant); the 1 % tolerance is 3.4 px on a 4-unit-high graph of a 12 × 8 world fitted to
1280 × 720, about one stroke width. Parse and frame times are **not measured**; the parse-budget test prints one
line (`MGVNEXT six moving graphs parsed in …`) for the Mac receipt.

Files: [MGExpression.swift](../../Sources/MartyGraphics/MGExpression.swift),
[MGGraph.swift](../../Sources/MartyGraphics/MGGraph.swift),
[MGDescribe.swift](../../Sources/MartyGraphics/MGDescribe.swift), and changes in `MGModel`, `MGParser`,
`MGCanvasRenderer`, `MGLayout`, `MGTimeline`, `MGGrammar`, `MGFixtures`, `MGLesson` and `MartyGraphicsView`.
Tests: `ExpressionTests`, `GraphCaseTests`, `GraphKindTests`, `AltTextTests`, a new `SceneValidatorTests` case,
and updated expectations in `LessonCoreTests` (grammar hash), `RegressionFixtures` (`allKinds` gains one item of
each new kind) and `TemplateExtensionTests` (eight new fail-safe cases). Fixtures:
[graphs.scene.json](../fixtures/v1/graphs.scene.json), [wave.scene.json](../fixtures/v1/wave.scene.json),
[expressions.cases.json](../fixtures/v1/expressions.cases.json) and
[graphs.cases.json](../fixtures/v1/graphs.cases.json). Offline mirror:
[tools/mg_expr.py](../../tools/mg_expr.py) with `tools/tests/test_mg_expr.py`, which runs in the hosted `hygiene` job.

The grammar-document hash in `LessonCoreTests` (`675bf2bec0e2e9a3`, 3,343 bytes) was computed offline by
rebuilding the document in Python; the same rebuild reproduces the previous value (`96001c839d70324d`, 2,700
bytes) exactly.

## Rules for the schema branch

`tools/scene_v1_check.py` and `docs/schemas/scene-v1.draft.schema.json` live on `feat/scene-v1-json-schema`, not
on this branch's base, so they are not changed here. To bring them in line:

1. Schema `$defs`, in the draft's style (`point`, `label`, `color`, `id` as today):

```json
"expression": {"type": "string", "minLength": 1, "maxLength": 80},
"graphRange": {"type": "array", "prefixItems": [{"type": "number", "minimum": -1000000, "maximum": 1000000},
               {"type": "number", "minimum": -1000000, "maximum": 1000000}], "minItems": 2, "items": false},
"parameter": {"type": "number", "minimum": -1000, "maximum": 1000},
"func": {"type": "object", "properties": {
  "id": {"$ref": "#/$defs/id"}, "k": {"const": "func"}, "color": {"$ref": "#/$defs/color"},
  "at": {"$ref": "#/$defs/point"}, "w": {"type": "number", "minimum": 0.5, "maximum": 125},
  "h": {"type": "number", "minimum": 0.5, "maximum": 125}, "xr": {"$ref": "#/$defs/graphRange"},
  "yr": {"$ref": "#/$defs/graphRange"}, "y": {"$ref": "#/$defs/expression"},
  "a": {"$ref": "#/$defs/parameter"}, "b": {"$ref": "#/$defs/parameter"}, "c": {"$ref": "#/$defs/parameter"},
  "period": {"type": "number", "minimum": 0.5, "maximum": 20}, "shade": {"$ref": "#/$defs/graphRange"},
  "mark": {"type": "number", "minimum": -1000000, "maximum": 1000000},
  "xl": {"$ref": "#/$defs/label"}, "yl": {"$ref": "#/$defs/label"}, "label": {"$ref": "#/$defs/label"}},
  "required": ["id", "k", "at", "w", "h", "xr", "yr", "y"], "additionalProperties": false},
"field": {"type": "object", "properties": {
  "id": {"$ref": "#/$defs/id"}, "k": {"const": "field"}, "color": {"$ref": "#/$defs/color"},
  "at": {"$ref": "#/$defs/point"}, "w": {"type": "number", "minimum": 0.5, "maximum": 125},
  "h": {"type": "number", "minimum": 0.5, "maximum": 125}, "xr": {"$ref": "#/$defs/graphRange"},
  "yr": {"$ref": "#/$defs/graphRange"}, "dx": {"$ref": "#/$defs/expression"}, "dy": {"$ref": "#/$defs/expression"},
  "a": {"$ref": "#/$defs/parameter"}, "b": {"$ref": "#/$defs/parameter"}, "c": {"$ref": "#/$defs/parameter"},
  "n": {"type": "array", "prefixItems": [{"type": "integer", "minimum": 2, "maximum": 16},
        {"type": "integer", "minimum": 2, "maximum": 12}], "minItems": 2, "items": false},
  "style": {"enum": ["arrows", "unit", "slope"]},
  "xl": {"$ref": "#/$defs/label"}, "yl": {"$ref": "#/$defs/label"}, "label": {"$ref": "#/$defs/label"}},
  "required": ["id", "k", "at", "w", "h", "xr", "yr", "dx", "dy"], "additionalProperties": false}
```

   Add both to `item.oneOf` and to the 2D-only branch (they are refused in 3D, as `table` and `region` are). Add
   `"alt": {"type": "string", "minLength": 1, "maxLength": 200}` to the root properties and to `step`. The `w`/`h`
   maxima of 125 are the 1.25 × span ceiling of the largest world, as for `plot`; the checker tightens them per
   world.

2. Python preflight, next to the existing rules (the mirror raises `mg_expr.Refusal` with the Swift reason):

```python
import mg_expr  # tools/mg_expr.py, standard library only

# item_rules(item, dimensions, template, is3d): after the shape checks. is3d: the scene's dim is "3d"; a
# three-coordinate `at` is then allowed, as in MGParser.point, and the scene is refused as 3d.kind.<kind> later.
if kind in ("func", "field"):
    try:
        mg_expr.check_graph_item(item, dimensions or (12, 8), is3d=is3d)
    except mg_expr.Refusal as refusal:
        raise Invalid(refusal.reason) from refusal

# scene_rules(scene): before the item loop
graphs = sum(1 for item in scene.get("items", ()) if isinstance(item, dict) and item.get("k") in ("func", "field"))
if graphs > mg_expr.EXPR_ITEMS:
    raise Invalid("items.expr")
# after title: text_rules(scene["alt"], "alt", template, multiline=True) when present
# per step:    text_rules(step["alt"], "step.alt", template, multiline=True) when present
```

   Replayed step edits that change a `func` or `field` key go through the same `check_graph_item`. Template scenes
   keep deferring to Swift. `docs/fixtures/v1/graphs.cases.json` and `expressions.cases.json` hold the shared
   sampling and refusal cases. So far they have passed in the Python mirror only (tools/tests/test_mg_expr.py);
   the Swift run (GraphCaseTests, ExpressionTests) is part of the pending Mac verification below, so Python and
   Swift are not yet shown to agree on any case.

## Mac verification

Pending: no Swift test of this branch has run yet. Run on the mini from a clone of the `feat/vnext-kinds` bundle
(`git clone -b feat/vnext-kinds <bundle> mg-vnext`; check `git log -1` against the receipt's commit), with Xcode 26.6
selected as in CI. No simulator and no VoiceOver are needed for this run.

```sh
swift --version && xcodebuild -version && sw_vers
mkdir -p logs
swift build --jobs 2 2>&1 | tee logs/vnext-build.log
# 1. The new suites, including the fix-round assertions (GraphKindTests:
#    testANonFiniteMidpointBetweenTwoSamplesSplitsThePiece, testAnAnimatedMarkerIsDroppedWhenItsCurrentValueIsInvalid;
#    GraphCaseTests: the shared midpoint, three-coordinate `at` and missing-id cases in graphs.cases.json).
swift test --jobs 2 --filter 'MartyGraphicsTests\.(ExpressionTests|GraphCaseTests|GraphKindTests|AltTextTests)' 2>&1 | tee logs/vnext-new.log
grep -E "testANonFiniteMidpointBetweenTwoSamplesSplitsThePiece|testAnAnimatedMarkerIsDroppedWhenItsCurrentValueIsInvalid|GraphCaseTests" logs/vnext-new.log
grep MGVNEXT logs/vnext-new.log
# 2. Tests whose expectations this branch changed, and suites that walk every kind, stream or replay steps.
swift test --jobs 2 --filter 'MartyGraphicsTests\.(LessonCoreTests/testU16DefaultGrammarDocumentIsUnchanged|TemplateExtensionTests/testCorePackPatchesApplyAndInvalidCasesFailWithExpectedReasons|ParserRegressionTests/testEveryKindRoundTripsThroughItsWireForm)$' 2>&1 | tee logs/vnext-changed.log
swift test --jobs 2 --filter 'MartyGraphicsTests\.(StreamRegressionTests|TimelineRegressionTests|ControllerRollbackTests)' 2>&1 | tee logs/vnext-touched.log
# 3. The scene validator tool on the new kinds.
swift test --jobs 2 --package-path tools/SceneValidator --filter 'SceneValidatorCoreTests\.SceneValidatorTests/testFunctionGraphFieldAndAltScenesUseTheParserRules$' 2>&1 | tee logs/vnext-validator-graphs.log
# 4. Review stills as PNGs (a person looks at them; anti-aliasing is not byte-exact across machines).
MG_VNEXT_RENDER_DIR="$PWD/vnext-stills" swift test --filter 'MartyGraphicsTests\.GraphKindTests/testRenderReviewStills' 2>&1 | tee logs/vnext-stills.log
grep 'MGVNEXT still' logs/vnext-stills.log
shasum -a 256 vnext-stills/*.png
open vnext-stills
# 5. Full sweep, as the CI shards.
swift test --jobs 2 --filter '^MartyGraphicsTests\.Solid' 2>&1 | tee logs/vnext-solid.log
swift test --jobs 2 --skip '^MartyGraphicsTests\.Solid' 2>&1 | tee logs/vnext-rest.log
swift test --jobs 2 --package-path tools/SceneValidator 2>&1 | tee logs/vnext-validator.log
swift test --jobs 2 --package-path Examples/Solid3D 2>&1 | tee logs/vnext-solid3d.log
for p in Examples/Turbofan Examples/KeySwitch3D; do swift test --jobs 2 --package-path "$p"; done
for p in Examples/Showcase Examples/PathTrace; do swift build --jobs 2 --package-path "$p"; done
# 6. Offline checks (also in hosted CI).
python3 -m unittest discover -s tools/tests -v
python3 tools/validate_local.py --check-files
```

What to record in the receipt: the commit, toolchain, each log's pass and fail counts (and that the two fix-round
test names passed), the `MGVNEXT` parse time, the still hashes, and a short note on each still (curve on the
samples, no line through a pole, the hole in `sin(x)/x`, shading under the curve, the marked point, arrows centred in
their cells). Only after GraphCaseTests and ExpressionTests pass can the shared cases be called verified in both
runtimes. VoiceOver on a device (scene and step `alt`, `describesBoard()`) is a separate manual check, not part of
this run.

## Open questions

- Should a moving graph's loop allow ping-pong (there and back) as `body.move` does? Today every loop must be
  seamless and is checked; ping-pong would make any `t` expression loopable.
- Should `alt` gain its own patch operation? Today a step's `alt` changes with the `steps` operation and the
  scene's with a new scene, and lessons and explainers need no new operation.
- Frame cost: a step edit of a `func` re-samples it each time the board resolves the step, which the native view
  does on every animation frame. Six graph items keep this bounded; caching the resolved step is the follow-up if
  the Mac measurement shows a cost.
