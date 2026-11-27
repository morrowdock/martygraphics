// SPDX-License-Identifier: Apache-2.0
import AVFoundation
import Foundation
import XCTest

/// `marty-solid export-captions` (`MGCaptionExport`): the golden files, the exit codes, and parity with the story video
/// that `render` writes at the same `--size` and `--story-fps`: each beat's cues start at the beat's `holdStart` and end
/// at its end in the `story.mp4` manifest record, the last cue ends where the movie ends, and the movie's own frames show
/// a caption exactly from the first cue frame of each step.
extension MartySolidCLITests {
    var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    var captionInputs: [(String, String)] {
        [("slider-crank", models.appendingPathComponent("slider-crank.json").path),
         ("gears-mixed", repoRoot.appendingPathComponent("Examples/Explainers/gears-mixed.explainer.json").path)]
    }

    /// Cue times in seconds from printed WebVTT.
    func vttCues(_ text: String) -> [(start: Double, end: Double)] {
        func seconds(_ s: String) -> Double {
            let p = s.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Double($0) }
            return p.count == 4 ? (p[0] * 60 + p[1]) * 60 + p[2] + p[3] / 1000 : -1
        }
        return text.components(separatedBy: "\n").compactMap { line -> (start: Double, end: Double)? in
            let parts = line.components(separatedBy: " --> ")
            guard parts.count == 2 else { return nil }
            return (seconds(parts[0]), seconds(parts[1]))
        }
    }

    func testExportCaptionsIsByteIdenticalToTheGoldenFiles() throws {
        for (name, path) in captionInputs {
            for format in ["vtt", "srt", "txt"] {
                let want = try Data(contentsOf: repoRoot.appendingPathComponent("docs/fixtures/captions/\(name).\(format)"))
                for args in [["export-captions", path, "--format", format], ["export-captions", path, "--strict", "--format", format]] {
                    let got = try run(args)
                    XCTAssertEqual(got.status, 0, "\(name) \(args)")
                    XCTAssertEqual(Data(got.text.utf8), want, "\(name) \(args)")
                }
            }
        }
        let lesson = try write(#"{"v":1,"kind":"lesson","steps":[]}"#, "lesson-captions.json")
        XCTAssertEqual(try run(["export-captions", lesson, "--format", "vtt"]).json?["reason"] as? String, "kind.unsupported")
        let refused = try write(#"{"v":2,"kind":"assembly","parts":[]}"#, "refused-captions.json")
        let r = try run(["export-captions", refused, "--format", "srt"])
        XCTAssertEqual(r.status, 1)
        XCTAssertEqual(r.text, try run(["check", refused]).text, "a refused document prints its check report")
        let path = captionInputs[0].1
        for bad in [["export-captions", path], ["export-captions", path, "--format", "webvtt"], ["export-captions", path, "--format", "vtt", "--format", "srt"],
                    ["export-captions", path, "--format", "vtt", "--story-fps", "24"], ["export-captions", path, "--format", "vtt", "--size", "10x10"],
                    ["export-captions", "--format", "vtt"]] {
            XCTAssertEqual(try run(bad).status, 2, "\(bad)")
        }
    }

    func testExportCaptionsMatchTheRenderedStoryVideo() throws {
        let size = (w: 640, h: 400), fps = 10
        for (name, path) in captionInputs {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("captions-\(name)-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: out) }
            let r = try renderOrSkip(["render", path, out.path, "--size", "\(size.w)x\(size.h)", "--no-loop", "--story-fps", "\(fps)"])
            XCTAssertEqual(r.status, 0, r.text)
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("manifest.json"))) as? [String: Any]
            let story = try XCTUnwrap((manifest?["outputs"] as? [[String: Any]])?.first { $0["file"] as? String == "story.mp4" })
            let beats = try XCTUnwrap(story["beats"] as? [[String: Any]])
            let vtt = try run(["export-captions", path, "--format", "vtt", "--size", "\(size.w)x\(size.h)", "--story-fps", "\(fps)"])
            XCTAssertEqual(vtt.status, 0, vtt.text)
            let cues = vttCues(vtt.text)
            // Cue blocks per beat: the cues back to back from the beat's hold start to its end.
            var k = 0, open: Double?
            for (start, end) in cues {
                if open == nil {
                    let hold = try XCTUnwrap(beats[k]["holdStart"] as? Double)
                    XCTAssertEqual(start, hold, accuracy: 0.001, "\(name) beat \(k + 1) starts at its hold")
                    XCTAssertLessThanOrEqual(start, hold)
                } else { XCTAssertEqual(start, open!, accuracy: 1e-9, "\(name): cues back to back") }
                let beatEnd = try XCTUnwrap(beats[k]["start"] as? Double) + (try XCTUnwrap(beats[k]["seconds"] as? Double))
                if abs(end - beatEnd) < 0.001 { k += 1; open = nil } else { open = end }
            }
            XCTAssertEqual(k, beats.count, "\(name): every beat has cues, in order")
            // The movie the writer finished lasts exactly as long as the last cue runs.
            let movie = out.appendingPathComponent("story.mp4")
            let frames = try XCTUnwrap(story["frames"] as? Int)
            let duration = CMTimeGetSeconds(AVURLAsset(url: movie).duration)
            XCTAssertEqual(duration, Double(frames) / Double(fps), accuracy: 0.001, name)
            XCTAssertEqual(try XCTUnwrap(cues.last?.end), duration, accuracy: 0.001, name)
            // An assembly's frames: the caption band is empty on the last move frame and shows text on the first cue frame.
            guard name == "slider-crank" else { continue }
            for b in beats.dropFirst() {
                let first = Int((try XCTUnwrap(b["holdStart"] as? Double) * Double(fps)).rounded())
                let start = Int((try XCTUnwrap(b["start"] as? Double) * Double(fps)).rounded())
                guard first > start else { continue }
                XCTAssertEqual(try captionTextPixels(movie, frame: first - 1, fps: fps, width: size.w, height: size.h), 0, "\(name) move frame")
                XCTAssertGreaterThan(try captionTextPixels(movie, frame: first, fps: fps, width: size.w, height: size.h), 20, "\(name) first cue frame")
            }
        }
    }
}
