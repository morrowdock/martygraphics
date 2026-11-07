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
| Solid 3D | Geometry kernel, JSON assemblies with joints and gear meshes, explode, section planes and a SceneKit studio renderer (`docs/SOLID-3D.md`); turbomachinery blade rows (`bladeRow`: cambered, twisted airfoils on cylinders, repeated around the axis) and capped cutaways (`revolvedProfile` with `sweep`); assembly v2 annotations (labels, engine-checked motion and gravity arrows, measured dimensions as facts, deterministic text placement with a callout list); `Examples/Solid3D`, `Examples/Turbofan` (two-spool turbofan, also path traced through a snapshot adapter) | Schematic models; tooth checks are 2D at sampled angles; section-plane faces are not capped (partial-revolve cutaways are); blade rows have straight stacking and flat tips; no flow simulation; no helical or bevel gears; force and flow arrows other than gravity are drawn as authored; macOS rendering checked, iOS not yet. |
| Explainer documents | `MGExplainer`, `MGExplainerSession`, `MGExplainerReport`, `MartyGraphicsExplainerView`: one document with a 2D board, a 3D solid or both, one beat timeline, one id namespace and one legend (`docs/EXPLAINER.md`); `marty-solid check` / `render` for explainers; `Examples/Explainers` | 3D annotations follow the assembly rules (one gate); beats cannot change the solid; learner controls bind 2D template parameters only; no on-device timing receipt. |
| Path tracing | `MartyGraphicsPathTracer` (separate library): Metal GPU path tracer for triangle meshes with physically based materials, studio lighting, depth of field and denoising; `Examples/PathTrace` gearbox | Offline stills and loops, not interactive. Apple silicon with Metal ray tracing; not run on iOS. No motion blur or temporal denoise. |
| Native 3D | SceneKit renderer for the documented primitive subset; opt-in tap selection, emphasis glow/dimming (`inspects3D`) and camera keep/reset (`preserves3DCamera`) | Click-select, drag-orbit and reset were checked on screen on macOS in the KeySwitch3D example. iOS touch, VoiceOver and frame cost are not accepted. No 3D groups, collision or physics. |
| Templates and packs | Public constructors, validated registry, BST and two pointers; record-list parameters and an opt-in `shortest_path` graph pack | No downloadable catalog, premium/course pack, package signing or trust service. The graph pack is unregistered by default and not visually or accessibility accepted. |
| Model-assisted generation | No model/provider integration or prompts bundled | Optional host choice; scene validation still applies to every provider. |
| Learning workflows and content | Synthetic examples only | Curriculum, learner state, study scheduling, private sources and app adapters are outside this package. |
| Desktop overlays or computer control | Not implemented by this library | Not implied by the scene renderer or any other product's overlay demo. |
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

This showcase changes **no engine limit or renderer behavior**. The
record-list parameters add new bounds for the new shape only (`MGLimits.records`,
`MGLimits.recordFields`); no existing limit changes.
