// SPDX-License-Identifier: Apache-2.0
import Foundation

// The render sequence of a solid document as data: which stills and loop frames to take, with what pose, camera,
// highlight and caption, and the manifest that describes the result. Rendering itself stays in the SceneKit layer
// (`MGSolidRenderer`, `marty-solid render`). Foundation only, deterministic.

/// One frame the render sequence takes.
public struct MGSolidShot: Equatable, Sendable {
    /// Output file name (`hero.png`, `exploded.png`, `step-<n>.png`); empty for a loop frame.
    public var file: String
    public var params: MGPoseParameters
    /// Camera preset (`MGSolidCamera.presets`); an unknown name falls back to `hero`.
    public var preset: String
    /// Extra yaw in degrees.
    public var orbit: Double
    public var highlight: [String]
    /// Framing margin below 1 fills more of the frame.
    public var margin: Double
    /// 0-based step whose view (section cuts, ghosts) the shot shows; nil for the plain scene.
    public var step: Int?
    /// Caption title (top line); nil for a loop frame.
    public var title: String?
    /// Caption text (bottom band), for step stills.
    public var caption: String?

    /// A shot built by a host (for example a pane that shows one step); `MGSolidShot.step(_:_:)` builds a step's still.
    public init(file: String, params: MGPoseParameters, preset: String, orbit: Double, highlight: [String], margin: Double, step: Int?,
                title: String?, caption: String?) {
        self.file = file; self.params = params; self.preset = preset; self.orbit = orbit; self.highlight = highlight
        self.margin = margin; self.step = step; self.title = title; self.caption = caption
    }
}

/// The stills and loop frames of `marty-solid render`, and its manifest.
public struct MGSolidRenderPlan: Equatable, Sendable {
    /// 120 frames at 0.10 s: one full orbit, one input turn, and an explode-and-reassemble beat (12.00 s).
    public static let loopFrames = 120, loopDelaySeconds = 0.1, loopWidth = 640
    /// `loopFrames` × `loopDelaySeconds`, written exactly.
    public static let loopSeconds = 12.0
    /// Loop frame rates a plan may render: 10 (the GIF rate) or 30. At 30 the plan renders 360 frames over the same
    /// 12 s; every third frame is a GIF frame (the same pose as at 10).
    public static let loopRates = [10, 30]
    /// Caption band (bottom) and title band (top, title and footer lines) of a captioned still in pixels at 1280 px
    /// wide; they scale with the width.
    public static let captionBandPixels = 120.0, titleBandPixels = 100.0
    /// Height the framing reads the bands at when a host gives none (16:10 at 1280 × 800).
    public static let referenceHeight = 800.0

    /// The title and caption bands of a `width` × `height` still as fractions of its height: the drawn bands, but at
    /// least the bands the annotation layout keeps free (`MGAnnotationLayout.titleBand`, `.captionBand`).
    public static func bands(width: Double, height: Double) -> (title: Double, caption: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return (MGAnnotationLayout.titleBand, MGAnnotationLayout.captionBand) }
        let s = width / 1280
        return (max(MGAnnotationLayout.titleBand, titleBandPixels * s / height), max(MGAnnotationLayout.captionBand, captionBandPixels * s / height))
    }

    /// Footer line of every captioned still.
    public var footer: String
    /// `hero.png`, `exploded.png`, then one `step-<n>.png` per step.
    public var stills: [MGSolidShot]
    /// The loop frames, in order; empty when the plan has no loop.
    public var loop: [MGSolidShot]
    /// Frames per second of `loop` (one of `loopRates`); the GIF takes every `loopRate / 10`-th frame.
    public var loopRate: Int

    /// `sourceName` is the file name the footer and manifest show. `loopRate` outside `loopRates` gives 10.
    public init(_ doc: MGSolidDocument, sourceName: String, source: MGSolidSource, loop: Bool = true, loopRate: Int = 10) {
        footer = "Rendered by the MartyGraphics solid engine from \(sourceName) (\(source.sizeText))"
        var stills = [
            MGSolidShot(file: "hero.png", params: doc.defaults, preset: "hero", orbit: 0, highlight: [], margin: 0.8, step: nil,
                        title: doc.title, caption: nil),
            MGSolidShot(file: "exploded.png", params: MGPoseParameters(input: doc.defaults.input, explode: 1), preset: "hero", orbit: 0,
                        highlight: [], margin: 0.92, step: nil, title: doc.title + " · exploded", caption: nil),
        ]
        stills += doc.steps.indices.compactMap { MGSolidShot.step(doc, $0) }
        self.stills = stills
        let rate = MGSolidRenderPlan.loopRates.contains(loopRate) ? loopRate : 10
        self.loopRate = rate
        let n = Int((MGSolidRenderPlan.loopSeconds * Double(rate)).rounded())
        self.loop = !loop ? [] : (0..<n).map { k -> MGSolidShot in
            let t = Double(k) / Double(n)
            let e = t > 0.4 && t < 0.9 ? 0.5 - 0.5 * cos((t - 0.4) / 0.5 * 2 * .pi) : 0
            return MGSolidShot(file: "", params: MGPoseParameters(input: doc.defaults.input + t * 2 * .pi, explode: e), preset: "hero",
                               orbit: t * 360, highlight: [], margin: 0.86, step: nil, title: nil, caption: nil)
        }
    }

    /// Every `loopRate / 10`-th loop frame: the GIF frames (at 0.10 s each).
    public var gifFrameIndices: [Int] { Array(Swift.stride(from: 0, to: loop.count, by: max(1, loopRate / 10))) }

    /// The cameras of a plan for a view of `width` × `height` pixels (`MGSolidFraming`): one per still with the rule
    /// that chose it, one per loop frame, and the factor the loop moved back by (1 when nothing was cut).
    public struct Cameras: Equatable, Sendable {
        public var stills: [MGSolidCamera]
        public var rules: [MGSolidFraming.Rule]
        public var loop: [MGSolidCamera]
        public var loopScale: Double
    }

    /// The camera of each still and each loop frame for a view of `width` × `height` pixels (`MGSolidFraming`).
    public func cameras(_ doc: MGSolidDocument, width: Double, height: Double, fieldOfView: Double = 30) -> Cameras {
        let aspect = width > 0 && height > 0 && width.isFinite && height.isFinite ? width / height : 1.6
        let bands = MGSolidRenderPlan.bands(width: width, height: height)
        let stills = self.stills.map {
            MGSolidFraming.framing(doc, shot: $0, aspect: aspect, fieldOfView: fieldOfView, titleBand: $0.title != nil ? bands.title : 0,
                                   captionBand: $0.caption != nil ? bands.caption : 0)
        }
        let loop = MGSolidFraming.loopFraming(doc, shots: self.loop, aspect: aspect, fieldOfView: fieldOfView)
        return Cameras(stills: stills.map(\.camera), rules: stills.map(\.rule), loop: loop.cameras, loopScale: loop.scale)
    }

    /// The exported snapshot: format v2 for a v2 document (part opacity, emission), the v1 snapshot for a v1 document.
    public static func snapshot(_ doc: MGSolidDocument) -> MGSolidSnapshot {
        doc.version >= 2 ? MGSolidSnapshot.make(doc, step: nil, params: doc.defaults) : MGSolidSnapshot.make(doc.assembly, params: doc.defaults)
    }

    /// `manifest.json`: `{"source": {"file", "lines", "sha256"}, "title", "parts", "steps", "checks", "framesRendered",
    /// "renderSecondsPerFrame", "outputs", "engine"?}`. `outputs` are the host's file records. Throws `report.engine`
    /// for an unusable `engine` and `report.encoding` for outputs that are not finite or nest deeper than 8 levels,
    /// before it reads them.
    public static func manifest(_ doc: MGSolidDocument, sourceName: String, source: MGSolidSource, framesRendered: Int,
                                secondsPerFrame: Double, outputs: [MGJSON], engine: MGJSON? = MGEngine.identity) throws -> MGJSON {
        if MGSolidReport.badEngine(engine) { throw MGSolidIssue("report.engine") }
        for o in outputs {
            let m = o.measure(stopAbove: MGSolidLimits.bytes)
            guard !m.stopped, m.finite, m.depth <= 8 else { throw MGSolidIssue("report.encoding") }
        }
        var o: [String: MGJSON] = ["source": .object(["file": .string(sourceName), "lines": .number(Double(source.lines)),
                                                      "sha256": .string(source.sha256)]),
                                   "title": .string(doc.title), "parts": .number(Double(doc.assembly.parts.count)),
                                   "steps": .number(Double(doc.steps.count)), "checks": MGSolidReport.Checks(doc).json,
                                   "framesRendered": .number(Double(framesRendered)),
                                   "renderSecondsPerFrame": secondsPerFrame.isFinite ? .number(secondsPerFrame) : .null,
                                   "outputs": .array(outputs)]
        if let engine { o["engine"] = engine }
        return .object(o)
    }
}

extension MGSolidShot {
    /// The still of step `i` (0-based) as `MGSolidRenderPlan` takes it: the step's pose after its spin, its camera
    /// preset and orbit, highlight, view and caption. A host that shows one step frames it with
    /// `MGSolidRenderer.frame(_:document:aspect:)`. Nil for an index outside the steps.
    public static func step(_ doc: MGSolidDocument, _ i: Int) -> MGSolidShot? {
        guard doc.steps.indices.contains(i) else { return nil }
        let step = doc.steps[i]
        let params = MGPoseParameters(input: doc.defaults.input + step.spin * 2 * .pi, explode: step.explode ?? doc.defaults.explode)
        return MGSolidShot(file: "step-\(i + 1).png", params: params, preset: step.camera ?? "hero", orbit: step.orbit,
                           highlight: step.highlight, margin: 0.8, step: i, title: doc.title, caption: "\(i + 1). \(step.say)")
    }
}

extension MGSolidSource {
    /// "53 lines"; a document on one line is described by its size instead ("812 bytes on one line").
    public var sizeText: String { lines > 1 ? "\(lines) lines" : "\(bytes) bytes on one line" }
}
