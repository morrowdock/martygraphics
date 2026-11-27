# Public engine versus a host application

This table describes source in this repository. An app demonstration, private
pack, proposed screen or browser recreation does not expand the public API.

| Capability | Public here | Host/app responsibility or gap |
| --- | --- | --- |
| Scene model, structural grammar, closed-key parsing | `MGModel`, `MGGrammar`, `MGParser` | Produce content; handle errors; provide appropriate text alternatives. |
| Atomic patches and revisions | `MGPatch`, `MGSceneController` | Track current revisions and require them for untrusted updates. |
| Progressive JSON | `MGStreamParser`, controller stream methods | Transport chunks; treat previews as provisional; check final success. |
| Layout and deterministic motion | `MGLayout`, `MGViewport`, `MGTimeline` | Choose viewport, time and step; measure readability and frame cost. |
| Native 2D | `MGCanvasRenderer`, SwiftUI view | Apple SDKs; application lifecycle and interaction. |
| Function graphs and vector fields (2D, additive, pending Mac verification) | `func` (the engine samples y = f(x) from a closed expression grammar, `MGExpression`; gaps, poles, shading, a marked point, parameters, seamless moving graphs) and `field` (engine-evaluated arrows, unit and slope styles); drawing checks refuse aliasing, too many breaks and invisible graphs; `tools/mg_expr.py` mirrors the rules offline | A graph is y = f(x), with optional time `t` for moving graphs; a field takes `x` and `y`. No parametric, polar or implicit curves, no stream lines, no learner sliders or draggable points, no derivatives or integrals as numbers, no LaTeX. A graph is checked at interval midpoints, so detail narrower than one interval can be missed. Frame cost and on-device rendering are not measured. |
| Text alternatives (pending Mac verification) | `alt` on scenes and steps (read by VoiceOver after the narration), `MGDescribe` engine-written board descriptions, `describesBoard()` opt-in | Hosts own long descriptions and captions. The engine attaches an audio graph (`AXChartDescriptor`) to visible `plot`, `func` and `bars` items; no VoiceOver or device acceptance has run. The engine describes structure, not meaning. |
| Solid 3D | Geometry kernel, JSON assemblies with joints and gear meshes, explode, section planes and a SceneKit studio renderer (`docs/SOLID-3D.md`); turbomachinery blade rows (`bladeRow`: cambered, twisted airfoils on cylinders, repeated around the axis) and capped cutaways (`revolvedProfile` with `sweep`); assembly v2 annotations (labels, engine-checked motion and gravity arrows, measured dimensions as facts, deterministic text placement with a callout list); `Examples/Solid3D`, `Examples/Turbofan` (two-spool turbofan, also path traced through a snapshot adapter) | Schematic models; tooth checks are 2D at sampled angles; step `section` cuts in assembly v2 and partial-revolve cutaways are capped, but the legacy `MGStudioOptions.section` clip is not; the engine can solve slider-crank motion but has no general linkage solver and no cam-contact solver (the shipped four-bar uses authored rotation ratios, and the cam example uses a `crankSlider` drive); blade rows have straight stacking and flat tips; no flow simulation; no helical or bevel gears; force and flow arrows other than gravity are drawn as authored; macOS rendering checked, iOS not yet. |
| Explainer documents | `MGExplainer`, `MGExplainerSession`, `MGExplainerReport`, `MartyGraphicsExplainerView`: one document with a 2D board, a 3D solid or both, one beat timeline, one id namespace and one legend (`docs/EXPLAINER.md`); `marty-solid check` / `render` for explainers; `Examples/Explainers` | 3D annotations follow the assembly rules (one gate); beats cannot change the solid; learner controls bind 2D template parameters only; no on-device timing receipt. |
| Beat-by-beat lessons | `MGLesson`, `MGLessonSession`, `MartyGraphicsLessonView`: statements with engine-computed values, checks, learner controls and saved state (`docs/LESSONS.md`); `Examples/LessonDemo` | Timing measured on one Apple M1 Mac only; no iPad device timing, no XCUITest UI test; VoiceOver, Dynamic Type and Reduce Motion not checked by hand. |
| ML explainer boards | `MartyGraphicsMLKit` (separate, opt-in library; `main` only, not in `v0.1.0`): checked 2D boards for vision to language, next-token probabilities, meaning maps, picture to numbers, generation, simplified attention and agent loops (`docs/ML-EXPLAINER.md`); `marty-ml-render` | Checks shape, arithmetic and references, not the truth of the words; 2D only; illustrative values unless cited. |
| Programmatic 2D video (`layer2d`) | `MGProgrammaticVideo` behind an explicit `programmaticVideo: true` opt-in (`main` only): checked keyframes, MP4/GIF export, captions and SRT (`docs/PROTOCOL.md`) | Experimental phase 1; does not compose ordinary scene items; iPad memory and time targets not measured. |
| glTF export and Blender video | `marty-solid export-gltf` (library `MartySolidGLTF` in `Examples/Solid3D`, `main` only; `docs/GLTF-EXPORT.md`) and `tools/render-blender` | The exporter runs only after the strict check; the Blender render is cosmetic and its motion comes from the export. Needs a separate Blender install. |
| Path tracing | `MartyGraphicsPathTracer` (separate library): Metal GPU path tracer for triangle meshes with physically based materials, studio lighting, depth of field and denoising; `Examples/PathTrace` gearbox | Offline stills and loops, not interactive. Apple silicon with Metal ray tracing; not run on iOS. No motion blur or temporal denoise. |
| Native 3D | SceneKit renderer for the documented primitive subset; opt-in tap selection, emphasis glow/dimming (`inspects3D`) and camera keep/reset (`preserves3DCamera`) | Click-select, drag-orbit and reset were checked on screen on macOS in the KeySwitch3D example. iOS touch, VoiceOver and frame cost are not accepted. No 3D groups, collision or physics. |
| Templates and packs | Public constructors, validated registry, BST and two pointers; record-list parameters and an opt-in `shortest_path` graph pack | No downloadable catalog, premium/course pack, package signing or trust service. The graph pack is unregistered by default and not visually or accessibility accepted. |
| Model-assisted generation | No model/provider integration or prompts bundled | Optional host choice; scene validation still applies to every provider. |
| Learning workflows and content | Synthetic examples only | Curriculum, learner state, study scheduling, private sources and app adapters are outside this package. |
| Desktop overlays or computer control | Not implemented by this library | Not implied by the scene renderer. |
| Web/Windows/Linux rendering | Not implemented in this package | [Portable-core/browser proposal](PORTABILITY-PROPOSAL.md); no rewrite or delivery promise. |

The current **renderers** use SwiftUI, CoreGraphics, SceneKit and related Apple
frameworks. Native iPad support does not require an Apple-only core architecture;
the present package simply has not separated a portable core from its adapters.

## Bounds are part of the contract

Current limits include 8 KiB canonical scene JSON, 4 KiB patches, 24 wire items,
10 template extras, 40 resolved items, 8 wire-authored steps and 48 template-built
steps. They bound validation, drawing, text and transition work. Input-size
headroom before canonicalization is not permission to exceed canonical limits.

Do not silently remove limits to fit a larger demo. A proposed expansion needs:

1. A concrete public use case and a scene that hits the existing limit.
2. Rejection/boundary tests, including references, cycles, edits and patches.
3. Measurements at the old and proposed maxima on named platform/toolchain
   configurations, including frame cost, memory and text/layout quality.
4. Independent integration review and an explicit format/version compatibility decision.

The record-list parameters added new bounds for the new shape only
(`MGLimits.records`, `MGLimits.recordFields`); no existing limit changed.
Likewise the `func` and `field` kinds add bounds for the new shapes only
(`MGLimits.exprLength`, `exprTokens`, `exprDepth`, `exprItems`, `exprParameter`,
`funcIntervals`, `funcBreaks`, `funcTolerance`, `funcPeriod`, `fieldCols`, `fieldRows`),
each with its derivation in the source; a 24-item scene of existing kinds parses exactly
as before. Their worst-case evaluation counts are computed, not yet measured on a Mac.
