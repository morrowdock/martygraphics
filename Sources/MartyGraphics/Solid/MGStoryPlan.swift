// SPDX-License-Identifier: Apache-2.0
import Foundation

// The story video (`story.mp4`) as data: the beats (explainer beats or assembly steps) in order, how long each holds,
// which frame shows which beat, how far each beat's spin has played and how far the camera has moved from the previous
// beat's camera. Rendering stays in the host (`marty-solid render`). Foundation only, deterministic.

/// Timing rules of the story video (docs/SOLID-3D.md, "Story video").
public enum MGStoryTiming {
    /// Reading time: `leadSeconds` plus one second per `scalarsPerSecond` Unicode scalars of the caption.
    public static let leadSeconds = 1.0, scalarsPerSecond = 15.0
    /// Every beat holds at least `minHoldSeconds` and at most `maxHoldSeconds`.
    public static let minHoldSeconds = 3.0, maxHoldSeconds = 9.0
    /// The camera moves from the previous beat's camera to this beat's camera over the first `transitionSeconds` of the
    /// beat (at most half the beat), eased in and out. The first beat starts at its own camera.
    public static let transitionSeconds = 0.6
    /// A beat's `spin` plays at the explainer view's pace (`MGExplainerLimits.spinSecondsPerTurn` per input turn) from
    /// the beat's first frame, faster when that would not fit in `maxHoldSeconds`, so it always ends within the beat;
    /// the rest of the beat holds the end pose.
    public static let spinSecondsPerTurn = MGExplainerLimits.spinSecondsPerTurn
    /// Frame rates the story may use (`--story-fps`), and the default.
    public static let rates = [10, 30], defaultRate = 30
    /// Most frames a story may have (two minutes at 30 fps). A longer story is refused (`story.frames`) before any
    /// frame is rendered.
    public static let maxFrames = 3600

    /// Seconds a caption needs to be read (`leadSeconds` + scalars / `scalarsPerSecond`), before the hold bounds.
    public static func readSeconds(_ caption: String) -> Double {
        leadSeconds + Double(caption.unicodeScalars.count) / scalarsPerSecond
    }

    /// Seconds the beat's spin takes at the explainer pace, at most `maxHoldSeconds` (a longer spin plays faster). The
    /// sign is the turn direction only; a spin that is not finite counts as no spin.
    public static func spinSeconds(_ spin: Double) -> Double { spin.isFinite ? min(maxHoldSeconds, abs(spin) * spinSecondsPerTurn) : 0 }

    /// How long one beat holds: the longer of its reading time and its spin time, bounded to
    /// `minHoldSeconds`...`maxHoldSeconds`.
    public static func holdSeconds(caption: String, spin: Double) -> Double {
        min(maxHoldSeconds, max(minHoldSeconds, max(readSeconds(caption), spinSeconds(spin))))
    }
}

/// The frames of one story video.
public struct MGStoryPlan: Equatable, Sendable {
    /// One beat (an explainer beat or an assembly step), in order.
    public struct Beat: Equatable, Sendable {
        /// The caption the beat shows (the same text as the beat's still).
        public var caption: String
        /// Input turns the beat plays (0: the parts hold still).
        public var spin: Double
        /// First frame of the beat, and its frame count.
        public var startFrame: Int
        public var frames: Int
        /// Frames of the camera move at the start of the beat (0 for the first beat), and of the spin.
        public var transitionFrames: Int
        public var spinFrames: Int
    }

    /// One frame: the beat it shows, the played fraction of that beat's spin (0...1; 1 when the beat has no spin) and
    /// the camera blend from the previous beat's camera (0) to this beat's camera (1).
    public struct Frame: Equatable, Sendable {
        public var beat: Int
        public var spin: Double
        public var camera: Double
    }

    public let fps: Int
    public let beats: [Beat]
    /// Every frame, in order.
    public var frameCount: Int { beats.last.map { $0.startFrame + $0.frames } ?? 0 }
    /// Length of the video in seconds (frames / fps).
    public var seconds: Double { Double(frameCount) / Double(fps) }
    /// Start of each beat in seconds.
    public func startSeconds(_ k: Int) -> Double { Double(beats[k].startFrame) / Double(fps) }

    /// A plan for beats with these captions and spins (one spin per caption). Refusals, before anything is built:
    /// `story.rate` (an fps outside `MGStoryTiming.rates`), `story.beats` (no beat, or captions and spins of different
    /// counts) and `story.frames` (more than `MGStoryTiming.maxFrames` frames).
    public init(captions: [String], spins: [Double], fps: Int = MGStoryTiming.defaultRate) throws {
        guard MGStoryTiming.rates.contains(fps) else { throw MGSolidIssue("story.rate") }
        guard !captions.isEmpty, captions.count == spins.count, captions.count <= MGSolidLimits.steps else { throw MGSolidIssue("story.beats") }
        var beats: [Beat] = [], start = 0
        for (k, (caption, spin)) in zip(captions, spins).enumerated() {
            let hold = MGStoryTiming.holdSeconds(caption: caption, spin: spin)
            let frames = max(1, Int((hold * Double(fps)).rounded()))
            let transition = k == 0 ? 0 : min(Int((MGStoryTiming.transitionSeconds * Double(fps)).rounded()), frames / 2)
            // `spinSeconds` is at most `maxHoldSeconds`, so the conversion to frames is always in range.
            let s = spin.isFinite && spin != 0 ? min(frames, max(1, Int((MGStoryTiming.spinSeconds(spin) * Double(fps)).rounded()))) : 0
            beats.append(Beat(caption: caption, spin: spin.isFinite ? spin : 0, startFrame: start, frames: frames, transitionFrames: transition,
                              spinFrames: s))
            start += frames
            guard start <= MGStoryTiming.maxFrames else { throw MGSolidIssue("story.frames") }
        }
        self.fps = fps; self.beats = beats
    }

    /// Frame `i` (0 ≤ i < `frameCount`). The last frame of every beat shows the beat's end pose at its own camera, the
    /// same pose and camera as the beat's still.
    public func frame(_ i: Int) -> Frame {
        let i = min(max(0, i), max(0, frameCount - 1))
        var k = beats.count - 1
        while k > 0 && beats[k].startFrame > i { k -= 1 }
        let b = beats[k], j = i - b.startFrame
        let spin: Double = b.spinFrames <= 1 ? 1 : min(1, Double(j) / Double(b.spinFrames - 1))
        var camera = 1.0
        if b.transitionFrames > 0, j < b.transitionFrames {
            let u = Double(j) / Double(b.transitionFrames)
            camera = u * u * (3 - 2 * u)
        }
        return Frame(beat: k, spin: b.spin == 0 ? 1 : spin, camera: camera)
    }

    /// The camera `t` of the way from `a` to `b` (0: `a`, 1: `b`, exactly): the target and field of view move in a
    /// straight line, yaw takes the shorter way round, pitch moves linearly and the distance moves geometrically (a
    /// steady zoom).
    public static func camera(from a: MGSolidCamera, to b: MGSolidCamera, _ t: Double) -> MGSolidCamera {
        guard t.isFinite, t < 1 else { return b }
        guard t > 0 else { return a }
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var dy = (b.yaw - a.yaw).truncatingRemainder(dividingBy: 360)
        if dy > 180 { dy -= 360 } else if dy < -180 { dy += 360 }
        let d = a.distance > 0 && b.distance > 0 ? exp(lerp(log(a.distance), log(b.distance))) : lerp(a.distance, b.distance)
        let at = a.targetVector, bt = b.targetVector
        return MGSolidCamera(target: MGVec3(lerp(at.x, bt.x), lerp(at.y, bt.y), lerp(at.z, bt.z)), yaw: a.yaw + dy * t,
                             pitch: lerp(a.pitch, b.pitch), distance: d, fieldOfView: lerp(a.fieldOfView, b.fieldOfView))
    }

    /// The first frame of beat `k`'s hold: after its camera move, or its first frame when it has no move (the first
    /// beat, or a beat in `cuts`).
    public func holdStartFrame(_ k: Int, cuts: Set<Int> = []) -> Int {
        let b = beats[k]
        return b.startFrame + (k == 0 || cuts.contains(k) ? 0 : b.transitionFrames)
    }

    /// The caption frame `i` shows: its beat's caption from the first frame of the beat's hold, and none (an empty
    /// caption band) during the camera move before it. A beat's labels and claims follow the same rule.
    public func caption(frame i: Int, cuts: Set<Int> = []) -> String? {
        guard frameCount > 0 else { return nil }
        let i = min(max(0, i), frameCount - 1)
        let k = frame(i).beat
        return i >= holdStartFrame(k, cuts: cuts) ? beats[k].caption : nil
    }

    /// The manifest record fields of `story.mp4` besides the file facts: `fps`, `frames`, `seconds`, the timing rules
    /// and per beat `{"beat" (1-based), "start", "holdStart", "seconds"}` in seconds (`holdStart`: when its caption,
    /// labels and claims appear).
    public func manifestFields(cuts: Set<Int> = []) -> [String: MGJSON] {
        ["fps": .number(Double(fps)), "frames": .number(Double(frameCount)), "seconds": .number(seconds),
         "transitionSeconds": .number(MGStoryTiming.transitionSeconds),
         "holdSeconds": .object(["min": .number(MGStoryTiming.minHoldSeconds), "max": .number(MGStoryTiming.maxHoldSeconds)]),
         "beats": .array(beats.enumerated().map { k, b in
             .object(["beat": .number(Double(k + 1)), "start": .number(Double(b.startFrame) / Double(fps)),
                      "holdStart": .number(Double(holdStartFrame(k, cuts: cuts)) / Double(fps)),
                      "seconds": .number(Double(b.frames) / Double(fps))])
         })]
    }
}
