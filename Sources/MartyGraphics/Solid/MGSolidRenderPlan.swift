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
}

/// The stills and loop frames of `marty-solid render`, and its manifest.
public struct MGSolidRenderPlan: Equatable, Sendable {
    /// 120 frames at 0.10 s: one full orbit, one input turn, and an explode-and-reassemble beat (12.00 s).
    public static let loopFrames = 120, loopDelaySeconds = 0.1, loopWidth = 640
    /// `loopFrames` × `loopDelaySeconds`, written exactly.
    public static let loopSeconds = 12.0

    /// Footer line of every captioned still.
    public var footer: String
    /// `hero.png`, `exploded.png`, then one `step-<n>.png` per step.
    public var stills: [MGSolidShot]
    /// The loop frames, in order; empty when the plan has no loop.
    public var loop: [MGSolidShot]

    /// `sourceName` is the file name the footer and manifest show.
    public init(_ doc: MGSolidDocument, sourceName: String, source: MGSolidSource, loop: Bool = true) {
        footer = "Rendered by the MartyGraphics solid engine from \(sourceName) (\(source.sizeText))"
        var stills = [
            MGSolidShot(file: "hero.png", params: doc.defaults, preset: "hero", orbit: 0, highlight: [], margin: 0.8, step: nil,
                        title: doc.title, caption: nil),
            MGSolidShot(file: "exploded.png", params: MGPoseParameters(input: doc.defaults.input, explode: 1), preset: "hero", orbit: 0,
                        highlight: [], margin: 0.92, step: nil, title: doc.title + " · exploded", caption: nil),
        ]
        for (i, step) in doc.steps.enumerated() {
            let params = MGPoseParameters(input: doc.defaults.input + step.spin * 2 * .pi, explode: step.explode ?? doc.defaults.explode)
            stills.append(MGSolidShot(file: "step-\(i + 1).png", params: params, preset: step.camera ?? "hero", orbit: step.orbit,
                                      highlight: step.highlight, margin: 0.8, step: i, title: doc.title, caption: "\(i + 1). \(step.say)"))
        }
        self.stills = stills
        let n = MGSolidRenderPlan.loopFrames
        self.loop = !loop ? [] : (0..<n).map { k -> MGSolidShot in
            let t = Double(k) / Double(n)
            let e = t > 0.4 && t < 0.9 ? 0.5 - 0.5 * cos((t - 0.4) / 0.5 * 2 * .pi) : 0
            return MGSolidShot(file: "", params: MGPoseParameters(input: doc.defaults.input + t * 2 * .pi, explode: e), preset: "hero",
                               orbit: t * 360, highlight: [], margin: 0.86, step: nil, title: nil, caption: nil)
        }
    }

    /// The exported snapshot: format v2 for a v2 document (part opacity, emission), the v1 snapshot for a v1 document.
    public static func snapshot(_ doc: MGSolidDocument) -> MGSolidSnapshot {
        doc.version >= 2 ? MGSolidSnapshot.make(doc, step: nil, params: doc.defaults) : MGSolidSnapshot.make(doc.assembly, params: doc.defaults)
    }

    /// `manifest.json`: `{"source": {"file", "lines", "sha256"}, "title", "parts", "steps", "checks", "framesRendered",
    /// "renderSecondsPerFrame", "outputs", "engine"?}`. `outputs` are the host's file records.
    public static func manifest(_ doc: MGSolidDocument, sourceName: String, source: MGSolidSource, framesRendered: Int,
                                secondsPerFrame: Double, outputs: [MGJSON], engine: MGJSON? = MGEngine.identity) -> MGJSON {
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

extension MGSolidSource {
    /// "53 lines"; a document on one line is described by its size instead ("812 bytes on one line").
    public var sizeText: String { lines > 1 ? "\(lines) lines" : "\(bytes) bytes on one line" }
}
