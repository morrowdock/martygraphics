# Portability map (step 1)

[Proposal](PORTABILITY-PROPOSAL.md) · [Semantic fixtures](fixtures/semantics/README.md) · [Map generator](../tools/portability_map.py)

Status: **inventory only.** No file moved, no module split, no API change. This page and the
fixture corpus are
[step 1 of the proposal](PORTABILITY-PROPOSAL.md#a-bounded-proposal): map, then test,
before moving anything. No Windows, Linux or browser support is claimed. The inventory is a
source scan and provides no Swift build or runtime evidence for any platform.

The tables under [Generated inventory](#generated-inventory) come from a static text scan
(`python3 tools/portability_map.py --write`). A tool test fails when they go stale. The scan
removes comments and string literals, reads `import` lines, counts platform symbols, and follows
`MG`/`ML` type names between files. It does not run the compiler, so it can miss implicit
references (inferred types, conformances on another file's type) and misattribute names that
two files declare.

## Summary

- `Package.swift` declares macOS 14 and iOS 17 only. It has one engine target, `MartyGraphics`,
  plus the opt-in `MartyGraphicsMLKit` and `MartyGraphicsPathTracer` libraries.
- Foundation is the only framework import in 68 of the 98 Swift files under `Sources/`.
  Five of those files also import a package target. See [Counts](#counts) for the breakdown.
- One Foundation-only file, `Explainer/MGExplainerLayout.swift`, still names `CGRect` and
  `CGSize`. Darwin Foundation re-exports the CoreGraphics geometry types.
- All 12 core candidates import only Foundation, and none names a hard platform symbol directly.
  They are **not** separable as they stand. Every candidate except `MGPhysics.swift` reaches
  CoreGraphics/CoreText code through package types (below).
- The scan matches platform names in 18 of the 317 `MartyGraphics` scope/file pairs that
  contain explicit public declarations. It also finds `Any` in the core declarations of
  `MGJSON`, `MGParser`, `MGPatch` and `MGGrammar`.
  [Details](#public-declarations-that-name-platform-types).
- The three `tools/SceneValidator` source targets import `Darwin`. The Python draft
  preflight provides a subset of the Swift validator's checks.

## What blocks each core candidate

The candidates come from the proposal's list: model, parser, validation, grammar,
patches/streams, timeline and templates/packs, plus `MGPhysics` for number formatting. Each
row names the exact symbol that pulls the file toward platform code.

| Candidate | Blocking symbols (the edge into platform code) | Seams inside the file (not hard blockers) |
| --- | --- | --- |
| `MGModel.swift` | `MGScene.layer2d: MGCheckedVideoPlan?` → `MGProgrammaticVideo.swift` (CoreGraphics, CoreText). `MGJSON.number(of:)` uses `MGSolidLimitDetail.exactLimit` → `Solid/MGSolidParser.swift`, which brings in the Solid graph. | `JSONSerialization` encode for `canonicalData` and `canonicalByteCount`, so the byte limits depend on its number spelling. `NSNumber`, `NSNull`, `CFGetTypeID`, `CFBooleanGetTypeID` and `CFNumberIsFloatType` for bool and exact-integer detection. `init?(any:)` and `any` take and return `Any`. |
| `MGParser.swift` | `MGProgrammaticVideo.parse` for opt-in `layer2d`. It checks layout with CoreText font measurement (`MGVideoDrawing.textBounds`, `captionHeight` and `textSize`) and `CGRect` geometry, and loads its schema through `Bundle.module`. `MGParseEnvironment` (explainer placeholder filling) → `Explainer/MGExplainerHonesty.swift` → `MGExplainer` → `MGExplainerState` → `MGExplainerLayout` (`CGRect`, `CGSize`) → `MGLayout`. `MGError.limit: MGSolidLimitDetail?` and `MGSolidFacts.nameLength`/`modifiers` → Solid. | `JSONSerialization` decode, with duplicate-key and BOM policy unmeasured. `CharacterSet` classes in `identifier`, `text` and trimming. `scene(object: Any)` entry points. |
| `MGGrammar.swift` | Through `MGParser`/`MGModel` only. | `document()` returns `[String: Any]`. |
| `MGPatch.swift` | `MGParseEnvironment` (explainer re-parse), and through `MGParser`/`MGModel`. | `JSONSerialization` decode; `parse(object: Any)`. |
| `MGStream.swift` | Through `MGParser`/`MGModel` only. | `JSONSerialization` with `.fragmentsAllowed` for partial members. |
| `MGTimeline.swift` | `videoFrame(_:in:)` uses `MGCheckedVideoPlan`, `MGVideoElement` and `MGVideoKeyframe`. These are Foundation value types, but they are declared in `MGProgrammaticVideo.swift`, which imports CoreGraphics and CoreText. | libm `exp`, `cos` and `atan2` in motion and spring samples, so cross-platform comparisons need tolerances. |
| `MGTemplates.swift` | Through `MGParser`/`MGModel`, and `MGPacks` (registry). | `CharacterSet` in declaration-name and reason-suffix rules. |
| `MGPack.swift` | Through `MGParser`. | Global registry: `NSLock` ×2 and `nonisolated(unsafe)` statics (`registered`, `cachedLibrary`). |
| `MGGraphPack.swift`, `MGGeometryPack.swift`, `MGFixtures.swift` | Through `MGModel`/`MGParser` only. | none found |
| `MGPhysics.swift` | none: it references no other package file. | `String(format: "%.Nf")` in `format(_:unit:)`, which every label, array cell, table cell and template value goes through. |

In short, two package edges block a Foundation-only core:

1. **Programmatic video types and validation** (`MGProgrammaticVideo.swift`, `MGVideoDrawing.swift`).
   The model stores the checked plan. The parser runs its CoreText layout check. The timeline
   samples its keyframes.
2. **Explainer and Solid back-references from the parser** (`MGParseEnvironment`,
   `MGSolidLimitDetail`, `MGSolidFacts`). The scan traces these references to
   `MGExplainerLayout` and `MGLayout` (CoreGraphics).

## Suggested seams

These are candidates for the proposal's step 2. Each one keeps the current limits, closed keys
and fail-closed behavior, and each still needs its own proposal, consumer list, fixture tests
and rollback path.

1. **JSON decode.** `MGJSON` from UTF-8 bytes. Keep the UTF-8-only check, the depth-64
   pre-scan, the raw-byte bound, bool/number separation and the 2^53 exactness rule. Decide the
   duplicate-key and BOM policy first (see the open fixtures). Today the policy is whatever
   `JSONSerialization` does.
2. **Canonical encode.** `canonicalData` and `canonicalByteCount` (sorted keys, unescaped
   slashes, number spelling). The 8 KiB scene and 4 KiB patch limits are measured on this output,
   so a second encoder must give the same bytes or a documented, reviewed bound.
3. **Text classification.** `CharacterSet.controlCharacters`, `whitespacesAndNewlines`,
   `letters` and `alphanumerics`. Use explicit tables with fixtures. The U+2028 open fixture
   shows one place where two implementations may already disagree.
4. **Number formatting.** `MGPhysics.format`, plus `%.4g` with `en_US_POSIX` in
   `MGVideoDrawing`. Use one formatter with the fixture cases (ties, negative zero, ≥ 1e21).
5. **Programmatic video split.** Move the wire and plan value types (`MGVideoElement`,
   `…Keyframe`, `…Track`, `…Caption`, `…Canvas`, `MGCheckedVideoPlan`) into a Foundation-only
   file. Keep CoreText measurement, `Bundle.module` schema loading and
   `frame(...) -> CGImage` behind an Apple adapter. A host without that adapter must refuse
   `layer2d` with a reason. It must not skip the layout check.
6. **Parser context.** Replace the concrete `MGParseEnvironment`, `MGSolidLimitDetail` and
   `MGSolidFacts` references with a small core type or protocol, so the parser closure stops
   at the core.
7. **Template registry.** Replace the `MGPacks` global locks and `nonisolated(unsafe)` state
   with an explicit registry value passed to parsing, or keep the global and test it on every
   target. The proposal already names this as a seam.
8. **Geometry and layout.** `MGLayout`, `MGViewport` and `MGExplainerLayout` use `CGFloat`,
   `CGPoint`, `CGRect` and `CGSize`. Keep them as renderer-adapter code, or define MG geometry
   value types before any explainer state moves.
9. **Host lifecycle.** `MGSceneController`, `MGLessonController` and `MGExplainerController`
   (Combine `ObservableObject`, clocks, `OSSignposter`) stay in the Apple adapter, as the
   proposal's step 3 says.

## Generated inventory

<!-- BEGIN GENERATED: tools/portability_map.py -->

_Generated by `python3 tools/portability_map.py --write`; a static text scan, not a build._

### Counts

Each Swift file counts once under its most restrictive import (AppKit/UIKit, SceneKit, SwiftUI, Combine,
simd, CoreGraphics, other, Foundation-only). `other` covers AVFoundation, CoreText, ImageIO,
UniformTypeIdentifiers, Metal, os, Darwin, XCTest, PackageDescription and files that import only a
package module or nothing. Package imports do not affect the primary group.
The second count is every file importing the group at all.

| Group | Sources (primary) | Sources (any import) | tools (primary) | tools (any import) |
| --- | ---: | ---: | ---: | ---: |
| Foundation-only | 72 | 85 | 0 | 5 |
| CoreGraphics | 11 | 15 | 0 | 0 |
| SwiftUI | 7 | 9 | 0 | 0 |
| SceneKit | 1 | 3 | 0 | 0 |
| AppKit/UIKit | 2 | 2 | 0 | 0 |
| simd | 4 | 6 | 0 | 0 |
| Combine | 0 | 3 | 0 | 0 |
| other | 5 | 12 | 6 | 6 |

Swift files scanned: 102 under `Sources/`, 6 under `tools/`. Foundation-only files that still use a hard platform symbol: 1 (Darwin Foundation re-exports CoreGraphics geometry types).

### Core candidates

Direct = what the file itself names. Via = the first package file with a non-Foundation import or
hard platform symbol that the candidate reaches through MG/ML type references (witness path shown).
Foundation and CoreFoundation bridges are seams, not hard blockers: swift-corelibs-foundation has
most of them, with behavior that has not been compared here.

| File | Role | Direct hard symbols | Foundation / CF / lock seams | Reaches platform code via |
| --- | --- | --- | --- | --- |
| `MGModel.swift` | model, limits-adjacent JSON value | none | CoreFoundation bridge: `CFBooleanGetTypeID`, `CFGetTypeID`, `CFNumberIsFloatType`; Foundation bridge: `JSONSerialization`, `NSNull`, `NSNumber` | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGModel → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGParser.swift` | parser, limits, validation | none | Foundation bridge: `CharacterSet`, `JSONSerialization` | `MGProgrammaticVideo.swift` (`MGProgrammaticVideo`; MGParser → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGGrammar.swift` | grammar document | none | none | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGGrammar → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGGrammar → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGPatch.swift` | patch transactions | none | Foundation bridge: `JSONSerialization` | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGPatch → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGPatch → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGStream.swift` | stream preview and finalization | none | Foundation bridge: `JSONSerialization` | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGStream → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGStream → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGTimeline.swift` | timeline, blend | none | none | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`, `MGVideoElement`, `MGVideoKeyframe`; MGTimeline → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGTimeline → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGTemplates.swift` | templates, parameter validation | none | Foundation bridge: `CharacterSet` | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGTemplates → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGTemplates → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGPack.swift` | pack registry and pack validation | none | locks/global state: `NSLock`, `nonisolated(unsafe)` | `MGProgrammaticVideo.swift` (`MGProgrammaticVideo`; MGPack → MGParser → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGPack → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGGraphPack.swift` | opt-in graph pack | none | none | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGGraphPack → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGGraphPack → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGGeometryPack.swift` | opt-in geometry pack | none | none | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGGeometryPack → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGGeometryPack → MGModel → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGFixtures.swift` | built-in synthetic fixtures | none | none | `MGProgrammaticVideo.swift` (`MGCheckedVideoPlan`; MGFixtures → MGModel → MGProgrammaticVideo)<br>`MGExplainerLayout.swift` (`MGExplainerFrame`; MGFixtures → MGParser → MGExplainerHonesty → MGExplainer → MGExplainerState → MGExplainerLayout) |
| `MGPhysics.swift` | closed-form values, number formatting | none | Foundation bridge: `String(format:` | none found |

### Public declarations that name platform types

The scan counts explicit `public` or `open` declarations in `Sources/`. It matches known
platform names and `Any` in the signature text. This is a partial API inventory.

| Module | Public declarations | Name platform types | Name `Any` |
| --- | ---: | ---: | ---: |
| MartyGraphics | 2416 | 52 | 8 |
| MartyGraphicsMLKit | 31 | 2 | 0 |
| MartyGraphicsPathTracer | 158 | 59 | 0 |

#### MartyGraphics: public scopes with matching signatures

324 scope/file pairs scanned, of which 22 match.

| Type (scope) | File | Public decls | Platform tokens | Untyped |
| --- | --- | ---: | --- | --- |
| `MGCanvasRenderer` | `MGCanvasRenderer.swift` | 2 | `GraphicsContext` | — |
| `MGExplainerBoard` | `MartyGraphicsExplainerView.swift` | 2 | `CGSize` | — |
| `MGExplainerController` | `MartyGraphicsExplainerView.swift` | 34 | `CGSize`, `ObservableObject` | — |
| `MGExplainerFrame` | `MGExplainerLayout.swift` | 22 | `CGSize` | — |
| `MGGrammar` | `MGGrammar.swift` | 5 | — | `Any` |
| `MGJSON` | `MGModel.swift` | 9 | — | `Any` |
| `MGLayout` | `MGLayout.swift` | 6 | `CGFloat`, `CGPoint`, `CGRect`, `CGSize` | — |
| `MGLayout.LabelRequest` | `MGLayout.swift` | 5 | `CGPoint`, `CGSize`, `CGVector` | — |
| `MGLessonController` | `MartyGraphicsLessonView.swift` | 28 | `ObservableObject` | — |
| `MGMovieWriter` | `MGMovieWriter.swift` | 8 | `CGImage` | — |
| `MGParser` | `MGParser.swift` | 10 | — | `Any` |
| `MGPatch` | `MGPatch.swift` | 7 | — | `Any` |
| `MGProgrammaticVideo` | `MGProgrammaticVideo.swift` | 3 | `CGImage` | — |
| `MGSceneController` | `MartyGraphicsView.swift` | 23 | `ObservableObject` | `Any` |
| `MGSolidOverlay` | `MGSolidOverlayView.swift` | 6 | `CGContext` | — |
| `MGSolidOverlayView` | `MGSolidOverlayView.swift` | 7 | `View` | — |
| `MGSolidRenderer` | `MGSolidRenderer.swift` | 35 | `CGImage`, `CGPoint`, `CGRect`, `CGSize`, `SCNGeometry` +1 | — |
| `MGTheme` | `MGTheme.swift` | 10 | `Color` | — |
| `MGViewport` | `MGLayout.swift` | 8 | `CGFloat`, `CGPoint`, `CGSize` | — |
| `MartyGraphicsExplainerView` | `MartyGraphicsExplainerView.swift` | 4 | `View` | — |
| `MartyGraphicsLessonView` | `MartyGraphicsLessonView.swift` | 4 | `View` | — |
| `MartyGraphicsView` | `MartyGraphicsView.swift` | 15 | `CGSize`, `View` | — |

#### MartyGraphicsMLKit: public scopes with matching signatures

11 scope/file pairs scanned, of which 1 match.

| Type (scope) | File | Public decls | Platform tokens | Untyped |
| --- | --- | ---: | --- | --- |
| `MGMLDocument` | `MGMLRendering.swift` | 4 | `CGImage` | — |

#### MartyGraphicsPathTracer: public scopes with matching signatures

17 scope/file pairs scanned, of which 11 match.

| Type (scope) | File | Public decls | Platform tokens | Untyped |
| --- | --- | ---: | --- | --- |
| `MGRTAreaLight` | `MGRTScene.swift` | 11 | `SIMD2`, `SIMD3` | — |
| `MGRTCamera` | `MGRTScene.swift` | 11 | `SIMD2`, `SIMD3` | — |
| `MGRTEnvironment` | `MGRTEnvironment.swift` | 13 | `SIMD2`, `SIMD3`, `SIMD4` | — |
| `MGRTEnvironment.Softbox` | `MGRTEnvironment.swift` | 6 | `SIMD2`, `SIMD3` | — |
| `MGRTEnvironmentDistribution` | `MGRTEnvironment.swift` | 8 | `SIMD2`, `SIMD3` | — |
| `MGRTInstance` | `MGRTScene.swift` | 4 | `simd_float4x4` | — |
| `MGRTMaterial` | `MGRTScene.swift` | 21 | `SIMD3` | — |
| `MGRTMesh` | `MGRTScene.swift` | 10 | `SIMD3` | — |
| `MGRTRenderer` | `MGRTRenderer.swift` | 7 | `MTLCreateSystemDefaultDevice`, `MTLDevice`, `simd_float4x4` | — |
| `MGRTRenderer.Output` | `MGRTRenderer.swift` | 7 | `CGImage`, `SIMD4` | — |
| `MGRTSampling` | `MGRTSampling.swift` | 20 | `SIMD2`, `SIMD3` | — |

### Imports per Swift file

| File | Primary group | Imports | `#if canImport` | Hard platform symbols (sample) |
| --- | --- | --- | --- | --- |
| `Sources/MartyGraphics/Explainer/MGExplainer.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Explainer/MGExplainerHonesty.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Explainer/MGExplainerLayout.swift` | Foundation-only | Foundation | — | CoreGraphics: `CGRect`, `CGSize` |
| `Sources/MartyGraphics/Explainer/MGExplainerReport.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Explainer/MGExplainerSession.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Explainer/MGExplainerState.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Explainer/MGPaneSlide.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Explainer/MGTranscript.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MG3DInteraction.swift` | CoreGraphics | CoreGraphics, Foundation | — | CoreGraphics: `CGFloat`, `CGPoint` |
| `Sources/MartyGraphics/MG3DView.swift` | AppKit/UIKit | AppKit, SceneKit, SwiftUI, UIKit, simd | UIKit | CoreGraphics: `CGFloat`, `CGPoint`; SceneKit: `SCNBillboardConstraint`, `SCNBox`, `SCNCamera` +18; simd: `simd_float3`, `simd_length`, `simd_normalize` +1; AppKit/UIKit: `NSBezierPath`, `NSColor`, `NSViewRepresentable` +3 |
| `Sources/MartyGraphics/MGCanvasRenderer.swift` | SwiftUI | SwiftUI | — | CoreGraphics: `CGFloat`, `CGPoint`, `CGRect` +2; SwiftUI: `Color`, `Gradient`, `GraphicsContext` +1 |
| `Sources/MartyGraphics/MGDescribe.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGEngine.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGExpression.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGFixtures.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGGeometryPack.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGGrammar.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGGraph.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGGraphPack.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGLayout.swift` | CoreGraphics | CoreGraphics, Foundation | — | CoreGraphics: `CGFloat`, `CGPoint`, `CGRect` +2 |
| `Sources/MartyGraphics/MGLesson.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGLessonSession.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGLessonSnapshot.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGModel.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGMovieWriter.swift` | other | AVFoundation, Foundation | — | CoreGraphics: `CGBitmapInfo`, `CGColorSpace`, `CGContext` +3; AVFoundation/ImageIO/UTType: `AVAssetWriter`, `AVAssetWriterInput`, `AVAssetWriterInputPixelBufferAdaptor` +17 |
| `Sources/MartyGraphics/MGPack.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGParser.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGPatch.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGPhysics.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGProgrammaticVideo.swift` | CoreGraphics | CoreGraphics, CoreText, Foundation | — | CoreGraphics: `CGImage`, `CGRect` |
| `Sources/MartyGraphics/MGRenderPolicy.swift` | SwiftUI | SwiftUI | — | — |
| `Sources/MartyGraphics/MGRepairHint.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGSceneDiff.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGStream.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGTemplates.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGTheme.swift` | SwiftUI | SwiftUI | — | SwiftUI: `Color` |
| `Sources/MartyGraphics/MGTimeline.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGTween.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/MGVideoDrawing.swift` | CoreGraphics | CoreGraphics, CoreText, Foundation | — | CoreGraphics: `CGColor`, `CGColorSpace`, `CGContext` +7; CoreText: `CTFont`, `CTFontCreateWithName`, `CTFrameDraw` +11 |
| `Sources/MartyGraphics/MGVideoExport.swift` | other | AVFoundation, Foundation, ImageIO, UniformTypeIdentifiers | — | CoreGraphics: `CGColorSpace`, `CGContext`, `CGImageAlphaInfo` +6; AVFoundation/ImageIO/UTType: `AVFoundation`, `CGImageDestination`, `CGImageDestinationAddImage` +4 |
| `Sources/MartyGraphics/MartyGraphicsExplainerView.swift` | SceneKit | Combine, SceneKit, SwiftUI, os | — | CoreGraphics: `CGFloat`, `CGSize`; SwiftUI: `@Environment`, `@ObservedObject`, `Canvas` +3; SceneKit: `SCNScene`, `SCNSceneRenderer`, `SCNSceneRendererDelegate`; Combine: `@Published`, `ObservableObject`; Darwin/os: `OSSignposter` |
| `Sources/MartyGraphics/MartyGraphicsLessonView.swift` | SwiftUI | Combine, SwiftUI, os | — | SwiftUI: `@Environment`, `@ObservedObject`, `Canvas` +2; Combine: `@Published`, `ObservableObject`; Darwin/os: `OSSignposter` |
| `Sources/MartyGraphics/MartyGraphicsView.swift` | SwiftUI | Combine, SwiftUI | — | CoreGraphics: `CGFloat`, `CGPoint`, `CGSize`; SwiftUI: `@Environment`, `@ObservedObject`, `@State` +6; Combine: `@Published`, `ObservableObject` |
| `Sources/MartyGraphics/Solid/MGAnnotationLayout.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGAssembly.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGGear.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGMaterial.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGMesh.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGProfile.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidAnchorCheck.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidAnchorSuggest.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidAnnotationMotion.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidAnnotations.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidArrowCheck.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidBuilders.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidBuiltInComponents.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidChecks.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidClearView.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidComponents.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidFacts.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidFrames.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidFraming.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidLook.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidMath.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidModels.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidNumericScalars.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidOverlayView.swift` | SwiftUI | CoreGraphics, CoreText, Foundation, SwiftUI | — | CoreGraphics: `CGAffineTransform`, `CGColor`, `CGContext` +5; SwiftUI: `Canvas`, `Color`, `StrokeStyle` +1; CoreText: `CTFont`, `CTFontCreateUIFontForLanguage`, `CTFontCreateWithName` +7 |
| `Sources/MartyGraphics/Solid/MGSolidParser.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidPoses.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidReasons.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidRenderPlan.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidRenderer.swift` | AppKit/UIKit | AppKit, CoreGraphics, Foundation, Metal, SceneKit, UIKit, simd | Metal, UIKit | CoreGraphics: `CGBitmapInfo`, `CGColor`, `CGColorSpace` +11; SceneKit: `SCNCamera`, `SCNGeometry`, `SCNGeometryElement` +10; simd: `simd_float3`, `simd_float4`, `simd_float4x4` +2; Metal: `MTLCreateSystemDefaultDevice` |
| `Sources/MartyGraphics/Solid/MGSolidReport.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidSection.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidShapes.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidSnapshot.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidStillChecks.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidTiers.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidTurbo.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGSolidView.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGStoryPlan.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphics/Solid/MGStoryRoute.swift` | Foundation-only | Foundation | — | — |
| `Sources/MartyGraphicsMLKit/MGMLAgent.swift` | other | MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MGMLDrawItems.swift` | CoreGraphics | CoreGraphics, Foundation | — | CoreGraphics: `CGPath`, `CGPoint`, `CGRect` |
| `Sources/MartyGraphicsMLKit/MGMLExport.swift` | CoreGraphics | CoreGraphics, Foundation, ImageIO, UniformTypeIdentifiers | — | CoreGraphics: `CGImage`, `CGImageDestinationAddImage`, `CGImageDestinationCreateWithURL` +1; AVFoundation/ImageIO/UTType: `CGImageDestinationAddImage`, `CGImageDestinationCreateWithURL`, `CGImageDestinationFinalize` +1 |
| `Sources/MartyGraphicsMLKit/MGMLKit.swift` | Foundation-only | Foundation, MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MGMLProbabilities.swift` | Foundation-only | Foundation, MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MGMLRendering.swift` | SwiftUI | CoreGraphics, CoreText, Foundation, MartyGraphics, SwiftUI | — | CoreGraphics: `CGColor`, `CGColorSpace`, `CGContext` +7; SwiftUI: `Color`; CoreText: `CTFont`, `CTFontCreateWithFontDescriptor`, `CTFontCreateWithName` +14 |
| `Sources/MartyGraphicsMLKit/MGMLVision.swift` | other | MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MLAttention.swift` | Foundation-only | Foundation, MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MLAttentionBoard.swift` | CoreGraphics | CoreGraphics | — | CoreGraphics: `CGColor`, `CGPoint`, `CGRect` |
| `Sources/MartyGraphicsMLKit/MLGeneration.swift` | Foundation-only | Foundation, MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MLGenerationBoard.swift` | CoreGraphics | CoreGraphics | — | CoreGraphics: `CGRect` |
| `Sources/MartyGraphicsMLKit/MLMeaningBoard.swift` | CoreGraphics | CoreGraphics | — | CoreGraphics: `CGPoint`, `CGRect` |
| `Sources/MartyGraphicsMLKit/MLMeaningMap.swift` | Foundation-only | Foundation, MartyGraphics | — | — |
| `Sources/MartyGraphicsMLKit/MLPicture.swift` | CoreGraphics | CoreGraphics, Foundation, ImageIO, MartyGraphics | — | CoreGraphics: `CGBitmapInfo`, `CGContext`, `CGImageAlphaInfo` +5; AVFoundation/ImageIO/UTType: `CGImageSourceCreateImageAtIndex`, `CGImageSourceCreateWithData`, `CGImageSourceGetCount` +1 |
| `Sources/MartyGraphicsMLKit/MLPictureBoard.swift` | CoreGraphics | CoreGraphics | — | CoreGraphics: `CGColor`, `CGPoint`, `CGRect` |
| `Sources/MartyGraphicsPathTracer/MGRTEnvironment.swift` | simd | simd | — | simd: `SIMD2`, `SIMD3`, `SIMD4` +4 |
| `Sources/MartyGraphicsPathTracer/MGRTRenderer.swift` | simd | CoreGraphics, Foundation, Metal, simd | Metal | CoreGraphics: `CGBitmapInfo`, `CGColorSpace`, `CGDataProvider` +2; simd: `SIMD3`, `SIMD4`, `simd_float4x4`; Metal: `MTLAccelerationStructure`, `MTLAccelerationStructureInstanceDescriptor`, `MTLAccelerationStructureTriangleGeometryDescriptor` +17 |
| `Sources/MartyGraphicsPathTracer/MGRTSampling.swift` | simd | simd | — | simd: `SIMD2`, `SIMD3`, `simd_clamp` +5 |
| `Sources/MartyGraphicsPathTracer/MGRTScene.swift` | simd | simd | — | simd: `SIMD2`, `SIMD3`, `SIMD4` +6 |
| `Sources/MartyGraphicsPathTracer/MGRTShaderSource.swift` | other | — | — | — |
| `tools/SceneValidator/Package.swift` | other | PackageDescription | — | — |
| `tools/SceneValidator/Sources/MartyMLRender/main.swift` | other | Darwin, Foundation, MartyGraphicsMLKit, SceneValidatorCore | — | — |
| `tools/SceneValidator/Sources/MartySceneValidate/main.swift` | other | Darwin, Foundation, SceneValidatorCore | — | — |
| `tools/SceneValidator/Sources/SceneValidatorCore/SceneValidator.swift` | other | Darwin, Foundation, MartyGraphics, MartyGraphicsMLKit | — | — |
| `tools/SceneValidator/Tests/SceneValidatorCoreTests/MLKitValidatorTests.swift` | other | Foundation, MartyGraphicsMLKit, SceneValidatorCore, XCTest | — | — |
| `tools/SceneValidator/Tests/SceneValidatorCoreTests/SceneValidatorTests.swift` | other | Darwin, Foundation, MartyGraphics, SceneValidatorCore, XCTest | — | — |

### Python tooling imports

Python files under `tools/` are listed with their static Python imports.

| File | Imports |
| --- | --- |
| `tools/check_dco.py` | re, subprocess, sys |
| `tools/mg_expr.py` | math, unicodedata |
| `tools/portability_map.py` | argparse, ast, collections, pathlib, re, sys |
| `tools/render-blender/mgrender/__init__.py` | — |
| `tools/render-blender/mgrender/busyguard.py` | os, re, subprocess, sys |
| `tools/render-blender/mgrender/device.py` | bpy |
| `tools/render-blender/mgrender/faststart.py` | os, struct, sys |
| `tools/render-blender/mgrender/ffmpeg.py` | subprocess |
| `tools/render-blender/mgrender/frames.py` | json, os |
| `tools/render-blender/mgrender/gpu_probe.py` | mgrender, os, sys |
| `tools/render-blender/mgrender/lookdev.py` | .device, .presets, bmesh, bpy, bpy_extras, math, mathutils |
| `tools/render-blender/mgrender/manifest.py` | .presets, hashlib, json, math, os, re, struct, sys |
| `tools/render-blender/mgrender/presets.py` | re |
| `tools/render-blender/render.py` | bpy, hashlib, json, mathutils, mgrender, os, shutil, subprocess, sys, time, traceback |
| `tools/render-blender/render_variants.py` | argparse, mgrender, os, pathlib, subprocess |
| `tools/render-blender/selftest_scene.py` | bmesh, bpy, hashlib, json, math, os, sys |
| `tools/scene_lint.py` | json, math, pathlib, sys |
| `tools/scene_v1_check.py` | argparse, json, math, mg_expr, os, pathlib, re, stat, tools, unicodedata |
| `tools/semantic_fixtures.py` | argparse, json, math, pathlib, scene_v1_check, sys |
| `tools/tests/test_check_dco.py` | os, pathlib, subprocess, sys, tempfile, unittest |
| `tools/tests/test_mg_expr.py` | json, math, mg_expr, pathlib, sys, unittest |
| `tools/tests/test_portability_tools.py` | copy, importlib, json, pathlib, subprocess, sys, tempfile, unittest |
| `tools/tests/test_release_install.py` | argparse, contextlib, importlib, io, json, pathlib, subprocess, sys, tempfile, unittest |
| `tools/tests/test_render_blender.py` | hashlib, json, math, mgrender, os, pathlib, re, render, render_variants, shutil, struct, subprocess, sys, tempfile, unittest |
| `tools/tests/test_repair_hints.py` | importlib, json, pathlib, re, sys, unittest |
| `tools/tests/test_scene_lint.py` | json, pathlib, re, scene_lint, scene_v1_check, sys, unittest |
| `tools/tests/test_scene_v1_schema.py` | json, os, subprocess, sys, tools, unittest |
| `tools/tests/test_validate_local.py` | contextlib, hashlib, importlib, io, json, os, pathlib, re, shlex, subprocess, sys, tempfile, unittest |
| `tools/validate_local.py` | argparse, datetime, hashlib, json, pathlib, platform, posixpath, re, socket, subprocess, sys, urllib |
| `tools/verify_release_install.py` | argparse, dataclasses, datetime, hashlib, json, os, pathlib, platform, re, socket, subprocess, sys |
| `tools/write_native_receipt.py` | argparse, importlib, json, pathlib, shlex, subprocess, sys |

<!-- END GENERATED: tools/portability_map.py -->
