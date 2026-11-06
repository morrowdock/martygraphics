// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Engine keyframes for one template parameter change (the lesson `animate` command).
///
/// A point blend between the start and end scene is wrong for a rotation: the in-between vertex lies on the chord, so
/// at the middle of a 90° turn its distance to the pivot drops to cos 45° ≈ 71 %. Keyframes instead re-run the template
/// at intermediate parameter values. Every keyframe is a fully validated `MGScene`, so each in-between frame is a true
/// rotation (or whatever the template computes), and labels show the numbers of that frame. A view blends only between
/// neighbouring keyframes; with at most 5° between them the chord error is r·(1 − cos 2.5°) ≈ 0.1 % of r.
public enum MGTween {
    /// At most this many keyframes per change (72 × 5° = one full turn).
    public static let maxFrames = 72
    /// Frames for a change of a parameter whose unit is not degrees.
    public static let nonAngleFrames = 36

    /// Keyframes from `scene` to `param = to`, excluding the start scene and ending with exactly the scene that the
    /// patch `{"op":"params","params":{param: to}}` gives (same canonical source, items, values and revision).
    /// `maxStep`: largest parameter change between neighbours when the parameter's unit is degrees.
    /// Fails with `animate.param` (not a numeric template parameter), `animate.to` (outside the parameter's range, or
    /// more than `maxFrames × maxStep` away), `animate.step` (`maxStep` not finite and positive) or `animate.frame` (an intermediate value does not validate; the issue's
    /// reason carries the inner reason after a colon: `animate.frame:template.pts.radius`).
    public static func keyframes(_ scene: MGScene, param: String, to: Double, maxStep: Double = 5) -> Result<[MGScene], MGError> {
        guard let spec = numericSpec(scene, param), spec.defaultValue?.isFinite != false || scene.source["params"]?[param] != nil,
              !spec.integer else { return .failure(.init("animate.param")) }
        guard to.isFinite, spec.range.contains(to) else { return .failure(.init("animate.to")) }
        guard maxStep.isFinite, maxStep > 0 else { return .failure(.init("animate.step")) }
        let from = current(scene, param, spec)
        let delta = to - from
        let frames: Int
        if spec.unit == "°" {
            guard abs(delta) <= Double(maxFrames) * maxStep + 1e-9 else { return .failure(.init("animate.to")) }
            frames = max(1, Int((abs(delta) / maxStep - 1e-9).rounded(.up)))
        } else {
            frames = delta == 0 ? 1 : nonAngleFrames
        }
        var out: [MGScene] = []
        out.reserveCapacity(frames)
        for k in 1...frames {
            let value = k == frames ? to : from + delta * Double(k) / Double(frames)
            let patch = MGPatch(ops: [.object(["op": .string("params"), "params": .object([param: .number(value)])])])
            switch scene.applying(patch) {
            case .success(let next): out.append(next)
            case .failure(let e): return .failure(.init("animate.frame:" + e.reason))
            }
        }
        return .success(out)
    }

    /// The scalar numeric parameter spec `param` of the scene's template, or nil.
    static func numericSpec(_ scene: MGScene, _ param: String) -> MGParamSpec? {
        guard let name = scene.template, let template = MGTemplates.library[name],
              let spec = template.params.first(where: { $0.name == param }), spec.count == nil, spec.fields == nil else { return nil }
        return spec
    }

    /// The parameter's value in the scene source, or its declared default.
    static func current(_ scene: MGScene, _ param: String, _ spec: MGParamSpec) -> Double {
        if case .number(let d)? = scene.source["params"]?[param] { return d }
        return spec.defaultValue.flatMap { $0.isFinite ? $0 : nil } ?? spec.range.lowerBound
    }

    /// Items `seconds` into a sequence of timed segments: segment k plays over its own duration; at a segment boundary
    /// the next segment starts from its own first frame (a cut, never a blend across segments). After the end: the
    /// last frame of the last segment.
    public static func sample(_ segments: [MGAdoption.Segment], at seconds: Double) -> [MGItem] {
        var t = max(0, seconds)
        for segment in segments {
            if t < segment.duration { return sample(segment.items, at: t / segment.duration) }
            t -= segment.duration
        }
        return segments.last?.items.last ?? []
    }

    /// Items at `fraction` (0…1) of a keyframe sequence: geometry is blended linearly between the two neighbouring
    /// keyframes; text and labels come from the nearer keyframe, so a label never shows a number no frame computed.
    public static func sample(_ frames: [[MGItem]], at fraction: Double) -> [MGItem] {
        guard let last = frames.last else { return [] }
        guard frames.count > 1, fraction < 1 else { return last }
        let position = max(0, fraction) * Double(frames.count - 1)
        let i = min(Int(position), frames.count - 2)
        let t = position - Double(i)
        let near = t < 0.5 ? frames[i] : frames[i + 1]
        let texts = Dictionary(near.map { ($0.id, ($0.label, $0.text)) }, uniquingKeysWith: { a, _ in a })
        return MGTimeline.blend(from: frames[i], to: frames[i + 1], t: t).map { item in
            var item = item
            if let (label, text) = texts[item.id] { item.label = label; item.text = text }
            return item
        }
    }
}
