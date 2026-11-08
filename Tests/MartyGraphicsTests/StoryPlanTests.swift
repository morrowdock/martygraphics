// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The story video plan (`MGStoryPlan`, `MGStoryTiming`): bounded holds from caption length and spin, frame
/// ownership, the bounded camera move, the spin within its beat, refusals before anything is built, camera
/// interpolation and the manifest fields.
final class StoryPlanTests: XCTestCase {
    typealias T = MGStoryTiming

    func testHoldIsBoundedAndGrowsWithTheCaption() {
        XCTAssertEqual(T.holdSeconds(caption: "", spin: 0), T.minHoldSeconds)
        XCTAssertEqual(T.holdSeconds(caption: String(repeating: "a", count: 10_000), spin: 0), T.maxHoldSeconds)
        // 1 s lead + 60 scalars / 15 per second = 5 s.
        XCTAssertEqual(T.holdSeconds(caption: String(repeating: "a", count: 60), spin: 0), 5, accuracy: 1e-12)
        var last = 0.0
        for n in Swift.stride(from: 0, through: 400, by: 7) {
            let h = T.holdSeconds(caption: String(repeating: "x", count: n), spin: 0)
            XCTAssertGreaterThanOrEqual(h, last); XCTAssertGreaterThanOrEqual(h, T.minHoldSeconds); XCTAssertLessThanOrEqual(h, T.maxHoldSeconds)
            last = h
        }
        // A spin longer than the reading time sets the hold (4 s per turn), still within the bounds.
        XCTAssertEqual(T.holdSeconds(caption: "Turn.", spin: 1.5), 6, accuracy: 1e-12)
        XCTAssertEqual(T.holdSeconds(caption: "Turn.", spin: -1.5), 6, accuracy: 1e-12)
        XCTAssertEqual(T.holdSeconds(caption: "Turn.", spin: 50), T.maxHoldSeconds)
        XCTAssertEqual(T.holdSeconds(caption: "Turn.", spin: .nan), T.minHoldSeconds)
        XCTAssertEqual(T.holdSeconds(caption: "Turn.", spin: .infinity), T.minHoldSeconds)
    }

    /// Every Unicode scalar counts: combining marks, emoji parts and CJK text are read, not skipped.
    func testReadingTimeCountsEveryScalar() {
        let combining = String(repeating: "e\u{301}", count: 30)   // 30 characters, 60 scalars
        XCTAssertEqual(T.readSeconds(combining), 1 + 60.0 / 15, accuracy: 1e-12)
        XCTAssertEqual(T.readSeconds("👩‍🚀"), 1 + 3.0 / 15, accuracy: 1e-12)
        XCTAssertEqual(T.readSeconds(String(repeating: "齿", count: 45)), 4, accuracy: 1e-12)
    }

    func testFramesBelongToTheirBeatInOrder() throws {
        let captions = ["1. Short.", "2. " + String(repeating: "w", count: 87), "3. Spin it.", "4. " + String(repeating: "z", count: 500)]
        let spins = [0.0, 0, 2, 0]
        let p = try MGStoryPlan(captions: captions, spins: spins, fps: 30)
        XCTAssertEqual(p.beats.map(\.frames), [90, 210, 240, 270])           // 3 s, 7 s, 8 s (spin), 9 s (cap)
        XCTAssertEqual(p.beats.map(\.startFrame), [0, 90, 300, 540])
        XCTAssertEqual(p.frameCount, 810)
        XCTAssertEqual(p.seconds, 27, accuracy: 1e-12)
        XCTAssertEqual(p.beats.map(\.transitionFrames), [0, 18, 18, 18])     // 0.6 s at 30 fps, none for the first beat
        var last = 0
        for i in 0..<p.frameCount {
            let f = p.frame(i)
            XCTAssertGreaterThanOrEqual(f.beat, last)
            XCTAssertTrue((p.beats[f.beat].startFrame..<(p.beats[f.beat].startFrame + p.beats[f.beat].frames)).contains(i))
            XCTAssertTrue((0...1).contains(f.spin)); XCTAssertTrue((0...1).contains(f.camera))
            last = f.beat
        }
        // Out-of-range indices clamp (no trap).
        XCTAssertEqual(p.frame(-5), p.frame(0))
        XCTAssertEqual(p.frame(1_000_000), p.frame(p.frameCount - 1))
    }

    /// The camera move: bounded to `transitionSeconds` and to half the beat, starting at the previous camera (0) and
    /// arriving before the beat's end; the first beat never moves. The last frame of every beat is the still's camera
    /// and pose (camera 1, spin 1).
    func testCameraMoveAndSpinStayInsideTheirBeat() throws {
        let p = try MGStoryPlan(captions: ["a", "b", "c"], spins: [1, 0, 0.25], fps: 10)
        for (k, b) in p.beats.enumerated() {
            XCTAssertLessThanOrEqual(b.transitionFrames, Int((T.transitionSeconds * 10).rounded()))
            XCTAssertLessThanOrEqual(b.transitionFrames, b.frames / 2)
            let first = p.frame(b.startFrame), end = p.frame(b.startFrame + b.frames - 1)
            XCTAssertEqual(first.camera, k == 0 ? 1 : 0)
            XCTAssertEqual(end.camera, 1); XCTAssertEqual(end.spin, 1)
            for j in b.transitionFrames..<b.frames { XCTAssertEqual(p.frame(b.startFrame + j).camera, 1) }
        }
        // Beat 1 spins one turn over 4 s (40 frames): 0 at its first frame, 1 from frame 39 on.
        XCTAssertEqual(p.beats[0].spinFrames, 40)
        XCTAssertEqual(p.frame(0).spin, 0)
        XCTAssertEqual(p.frame(39).spin, 1)
        XCTAssertEqual(p.frame(20).spin, 20.0 / 39, accuracy: 1e-12)
        // A beat without spin holds its pose (progress 1 in every frame).
        for j in 0..<p.beats[1].frames { XCTAssertEqual(p.frame(p.beats[1].startFrame + j).spin, 1) }
        // A short spin ends early and holds.
        let c = p.beats[2]
        XCTAssertEqual(c.spinFrames, 10)
        XCTAssertEqual(p.frame(c.startFrame + 9).spin, 1)
        XCTAssertEqual(p.frame(c.startFrame + c.frames - 1).spin, 1)
    }

    /// Refusals come before anything is built, as single tokens.
    func testRefusalsAreSingleTokens() {
        func reason(_ f: () throws -> MGStoryPlan) -> String? {
            do { _ = try f(); return nil } catch let e as MGSolidIssue { return e.reason } catch { return "other" }
        }
        XCTAssertEqual(reason { try MGStoryPlan(captions: ["a"], spins: [0], fps: 24) }, "story.rate")
        XCTAssertEqual(reason { try MGStoryPlan(captions: [], spins: [], fps: 30) }, "story.beats")
        XCTAssertEqual(reason { try MGStoryPlan(captions: ["a", "b"], spins: [0], fps: 30) }, "story.beats")
        XCTAssertEqual(reason { try MGStoryPlan(captions: Array(repeating: "a", count: 17), spins: Array(repeating: 0, count: 17), fps: 30) },
                       "story.beats")
        // 16 beats held 9 s at 30 fps is 4,320 frames, over the 3,600 cap; at 10 fps it is 1,440 frames.
        let long = Array(repeating: String(repeating: "r", count: 300), count: 16)
        XCTAssertEqual(reason { try MGStoryPlan(captions: long, spins: Array(repeating: 0, count: 16), fps: 30) }, "story.frames")
        XCTAssertNil(reason { try MGStoryPlan(captions: long, spins: Array(repeating: 0, count: 16), fps: 10) })
        XCTAssertEqual(try MGStoryPlan(captions: long, spins: Array(repeating: 0, count: 16), fps: 10).frameCount, 1440)
        // Spins alone can reach the cap too.
        XCTAssertEqual(reason { try MGStoryPlan(captions: Array(repeating: "x", count: 16), spins: Array(repeating: 3, count: 16), fps: 30) },
                       "story.frames")
        // Every reason is in the catalog.
        for r in ["story.rate", "story.beats", "story.frames"] { XCTAssertNotNil(MGSolidReasons.lookup(r), r) }
    }

    /// Hostile spins never trap: the spin time is clamped before it becomes a frame count; the sign is the direction;
    /// a spin that is not finite counts as none.
    func testHostileSpinsAreClamped() throws {
        for spin in [1e100, -1e100, .infinity, -.infinity, .nan, -1, Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude] {
            let p = try MGStoryPlan(captions: ["Turn"], spins: [spin], fps: 30)
            let b = p.beats[0]
            XCTAssertLessThanOrEqual(b.frames, Int(T.maxHoldSeconds * 30), "\(spin)")
            XCTAssertGreaterThanOrEqual(b.frames, Int(T.minHoldSeconds * 30), "\(spin)")
            XCTAssertLessThanOrEqual(b.spinFrames, b.frames, "\(spin)")
            XCTAssertTrue(b.spin.isFinite, "\(spin)")
            for i in 0..<p.frameCount { XCTAssertTrue((0...1).contains(p.frame(i).spin), "\(spin)") }
            XCTAssertLessThanOrEqual(T.spinSeconds(spin), T.maxHoldSeconds)
        }
        XCTAssertEqual(try MGStoryPlan(captions: ["Turn"], spins: [1e100], fps: 30).beats[0].frames, 270)
        XCTAssertEqual(try MGStoryPlan(captions: ["Turn"], spins: [.nan], fps: 30).beats[0].spinFrames, 0)
        XCTAssertEqual(try MGStoryPlan(captions: ["Turn"], spins: [.infinity], fps: 30).beats[0].spinFrames, 0)
        // A negative spin plays backwards over the same time as a positive one.
        let back = try MGStoryPlan(captions: ["Turn"], spins: [-1], fps: 30).beats[0], forward = try MGStoryPlan(captions: ["Turn"], spins: [1], fps: 30).beats[0]
        XCTAssertEqual(back.spinFrames, forward.spinFrames)
        XCTAssertEqual(back.spin, -1)
    }

    /// A beat's caption (and with it its labels and claims) shows from the first frame of its hold, never during the
    /// camera move before it; a cut beat and the first beat show it from their first frame.
    func testCaptionAppearsOnlyWhenTheHoldStarts() throws {
        let p = try MGStoryPlan(captions: ["1. Left gear.", "2. Right gear.", "3. Both."], spins: [0, 0, 0], fps: 30)
        for cuts: Set<Int> in [[], [2]] {
            for (k, b) in p.beats.enumerated() {
                let start = p.holdStartFrame(k, cuts: cuts)
                let moves = k == 0 || cuts.contains(k) ? 0 : b.transitionFrames
                XCTAssertEqual(start, b.startFrame + moves)
                for i in b.startFrame..<(b.startFrame + b.frames) {
                    let shows = i >= start
                    XCTAssertEqual(p.caption(frame: i, cuts: cuts), shows ? b.caption : nil, "frame \(i)")
                    XCTAssertEqual(p.holds(frame: i, cuts: cuts), shows, "frame \(i)")
                    // While the caption is hidden, the frame is inside the camera move; once it shows, the camera has arrived.
                    if !shows { XCTAssertLessThan(p.frame(i).camera, 1) }
                    if shows, !cuts.contains(k) { XCTAssertEqual(p.frame(i).camera, 1) }
                }
            }
        }
        XCTAssertEqual(p.caption(frame: p.beats[1].startFrame + p.beats[1].transitionFrames), "2. Right gear.")
        XCTAssertNil(p.caption(frame: p.beats[1].startFrame + p.beats[1].transitionFrames - 1))
    }

    func testCameraInterpolation() {
        let a = MGSolidCamera(target: MGVec3(0, 0, 0), yaw: 350, pitch: 10, distance: 100, fieldOfView: 30)
        let b = MGSolidCamera(target: MGVec3(10, -20, 40), yaw: 10, pitch: 30, distance: 400, fieldOfView: 30)
        XCTAssertEqual(MGStoryPlan.camera(from: a, to: b, 0), a)
        XCTAssertEqual(MGStoryPlan.camera(from: a, to: b, 1), b)
        XCTAssertEqual(MGStoryPlan.camera(from: a, to: b, -3), a)
        XCTAssertEqual(MGStoryPlan.camera(from: a, to: b, .nan), b)
        let m = MGStoryPlan.camera(from: a, to: b, 0.5)
        XCTAssertEqual(m.yaw, 360, accuracy: 1e-9)             // the short way round, not through 180
        XCTAssertEqual(m.pitch, 20, accuracy: 1e-9)
        XCTAssertEqual(m.distance, 200, accuracy: 1e-9)        // geometric: √(100 × 400)
        XCTAssertEqual(m.targetVector, MGVec3(5, -10, 20))
        let back = MGStoryPlan.camera(from: b, to: a, 0.25)
        XCTAssertEqual(back.yaw, 5, accuracy: 1e-9)
    }

    func testPlansAreDeterministicAndManifestFieldsAreInSeconds() throws {
        let captions = ["1. One.", "2. Two words here.", "3. " + String(repeating: "q", count: 70)]
        let p = try MGStoryPlan(captions: captions, spins: [0, 1, 0], fps: 30)
        XCTAssertEqual(p, try MGStoryPlan(captions: captions, spins: [0, 1, 0], fps: 30))
        let f = MGJSON.object(p.manifestFields())
        XCTAssertEqual(f["fps"], .number(30))
        XCTAssertEqual(f["frames"], .number(Double(p.frameCount)))
        XCTAssertEqual(f["transitionSeconds"], .number(0.6))
        XCTAssertEqual(f["holdSeconds"], .object(["min": .number(3), "max": .number(9)]))
        guard case .array(let beats)? = f["beats"] else { return XCTFail("beats") }
        XCTAssertEqual(beats.count, 3)
        XCTAssertEqual(beats[0], .object(["beat": .number(1), "start": .number(0), "holdStart": .number(0), "seconds": .number(3)]))
        XCTAssertEqual(beats[1]["holdStart"], .number(3.6))           // after the 0.6 s camera move
        // A cut beat's hold starts at its first frame.
        guard case .array(let cut)? = MGJSON.object(p.manifestFields(cuts: [1]))["beats"] else { return XCTFail("beats") }
        XCTAssertEqual(cut[1]["holdStart"], .number(3))
        XCTAssertEqual(beats[1]["start"], .number(3))
        XCTAssertEqual(beats[2]["start"], .number(p.startSeconds(2)))
        XCTAssertEqual(p.startSeconds(2), 7, accuracy: 1e-12)   // 3 s, then 4 s for one turn
        XCTAssertTrue(f.isEncodable)
    }
}
