// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MartyGraphics

/// Frame plan for `lesson-demo --capture` (example code, not engine code).
///
/// One run of the rotation lesson on the demo's default pacing (`.estimate(wordsPerSecond: 2.5)`) on an injected
/// clock. The plan lists every board frame with the time the live view is due to show it:
/// - each beat's settled state at the time the beat is presented;
/// - for an `animate`, every frame of its keyframe segment (`MGKeyframeSegment.frames`: the start scene, then engine
///   keyframes at most 5° apart) at the time the view reaches it (frame `j` of `n` at `duration × j / (n − 1)` into
///   the segment, as `MGTween.sample` plays it); the settled state replaces the last frame when the segment ends;
/// - a scripted learner who moves the slider during beat 4 (85° → 45° in 5° steps, 0.1 s apart, from 1 s after the
///   beat is presented) through the controller's `control`, the call the slider makes.
/// The capture tool shows each planned frame on the live demo view and records it offscreen; the GIF delays are the
/// differences between these planned times. The live view also blends between neighbouring keyframes and draws new
/// items on over 0.55 s; the capture shows settled frames at the planned times only.
public enum LessonCapture {
    public static let wordsPerSecond = 2.5
    public static let learnerAngles: [Double] = Array(stride(from: 85.0, through: 45.0, by: -5))
    /// Seconds after beat 4 is presented before the scripted learner's first slider tick.
    public static let learnerDelay = 1.0
    /// Seconds between the scripted learner's slider ticks.
    public static let learnerStep = 0.1
    /// Seconds the last frame is held after `lessonComplete` before the GIF loops.
    public static let endHold = 2.0

    public enum Kind: Equatable, Sendable {
        /// The state just after a beat without `animate` is presented.
        case beat
        /// Frame `index` (0-based; 0 is the start scene) of the `count` frames of the beat's `animate` segment.
        case keyframe(index: Int, count: Int)
        /// The state after the beat's keyframes (items added after the turn included).
        case settled
        /// The scripted learner moved the slider to `angle`.
        case learner(angle: Double)

        public var name: String {
            switch self {
            case .beat: return "beat"
            case .keyframe(let i, let n): return "keyframe-\(i + 1)-of-\(n)"
            case .settled: return "settled"
            case .learner(let a): return "learner-\(Int(a))"
            }
        }
    }

    public struct Frame: Equatable, Sendable {
        /// Seconds after the lesson was loaded, on the injected clock.
        public let at: Double
        /// 0-based beat.
        public let beat: Int
        public let kind: Kind
        /// The engine keyframe scene for `.keyframe`; nil otherwise (the live state is shown).
        public let scene: MGScene?
    }

    public struct Plan: Equatable, Sendable {
        public let frames: [Frame]
        /// `lessonComplete`, seconds after load.
        public let complete: Double
        /// `lineDue(0)` → `lessonComplete`, seconds.
        public let lineDueToComplete: Double
        /// `lineDue(k)`, seconds after load.
        public let lineDue: [Double]
    }

    static func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }

    /// Runs the lesson headless on an injected clock and returns the frame plan.
    public static func plan() throws -> Plan {
        RotationLesson.register()
        let clock = MGManualClock()
        var session = MGLessonSession(pacing: .estimate(wordsPerSecond: wordsPerSecond), clock: clock)
        let origin = clock.now
        _ = try session.load(RotationLesson.lesson()).get()
        var frames: [Frame] = []
        var seen = 0
        var learner: [(at: Double, angle: Double)] = []
        func now() -> Double { seconds(clock.now - origin) }
        func collect() {
            while seen < session.history.count {
                let record = session.history[seen]; seen += 1
                guard case .beatPresented(let k) = record.event else { continue }
                let p = seconds(record.at - origin)
                if case .keyframes(let segments)? = session.lastChange?.transition {
                    var offset = 0.0
                    for segment in segments where segment.frames.count >= 2 && segment.duration > 0 {
                        let n = segment.frames.count
                        // The last frame is the end of the segment: the settled frame below shows it at that time.
                        for (j, scene) in segment.frames.enumerated() where j < n - 1 {
                            frames.append(Frame(at: p + offset + segment.duration * Double(j) / Double(n - 1), beat: k,
                                                kind: .keyframe(index: j, count: n), scene: scene))
                        }
                        offset += segment.duration
                    }
                    frames.append(Frame(at: p + offset, beat: k, kind: .settled, scene: nil))
                } else {
                    frames.append(Frame(at: p, beat: k, kind: .beat, scene: nil))
                }
                if k == 3 { learner = learnerAngles.enumerated().map { (p + learnerDelay + learnerStep * Double($0.offset), $0.element) } }
            }
        }
        collect()
        var guardSteps = 0
        while !session.isComplete {
            guardSteps += 1
            if guardSteps > 10_000 { throw MGError("capture.pacing") }
            let wake = session.nextWake.map { seconds($0 - origin) }
            if let next = learner.first, wake == nil || next.at <= wake! {
                clock.advance(by: .milliseconds(Int64(((next.at - now()) * 1000).rounded())))
                learner.removeFirst()
                if case .failure(let issue) = session.control("angle", next.angle) { throw MGError("capture.learner." + issue.reason) }
                frames.append(Frame(at: now(), beat: session.openLine ?? 3, kind: .learner(angle: next.angle), scene: nil))
            } else if let wake {
                clock.advance(by: .milliseconds(Int64((max(0, wake - now()) * 1000).rounded(.up))))
                session.tick()
            } else {
                throw MGError("capture.stalled")
            }
            collect()
        }
        let complete = session.history.first { $0.event == .lessonComplete }.map { seconds($0.at - origin) } ?? now()
        let due = session.history.compactMap { r -> Double? in if case .lineDue = r.event { return seconds(r.at - origin) }; return nil }
        return Plan(frames: frames.sorted { $0.at < $1.at }, complete: complete,
                    lineDueToComplete: complete - (due.first ?? 0), lineDue: due)
    }

    /// GIF delays in centiseconds: frame `i` lasts until frame `i + 1`'s time, the last frame until `end`. Rounded
    /// cumulatively, so the total equals `end − times[0]` to the nearest centisecond. At least 2 cs per frame.
    public static func gifDelays(_ times: [Double], end: Double) -> [Int] {
        var written = 0
        return times.indices.map { i in
            let until = i + 1 < times.count ? times[i + 1] : end
            let cs = max(2, Int(((until - times[0]) * 100).rounded()) - written)
            written += cs
            return cs
        }
    }

    /// `image` scaled to `width` pixels (aspect kept), sRGB, high-quality interpolation.
    public static func scaled(_ image: CGImage, width: Int) -> CGImage? {
        let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Writes a looping GIF with ImageIO (no external tools). `delays` in centiseconds, one per image.
    public static func writeGIF(_ images: [CGImage], delays: [Int], to url: URL) throws {
        guard images.count == delays.count, !images.isEmpty,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil)
        else { throw MGError("capture.gif") }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, cs) in zip(images, delays) {
            let d = Double(cs) / 100
            CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: d,
                                                                                     kCGImagePropertyGIFUnclampedDelayTime: d]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw MGError("capture.gif") }
    }

    /// Writes `image` as PNG.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw MGError("capture.png") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw MGError("capture.png") }
    }
}
