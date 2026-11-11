// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Foundation
import MartyGraphics
import MartySolidGLTF
import TurbofanKit

/// `--export-gltf`: the turbofan and its showcase loop (the motion and camera of `turbofan-loop.mp4`: LP spool one turn,
/// HP spool three turns, the slow orbit swing, 12 s) as glTF 2.0 binary (docs/GLTF-EXPORT.md). Runs only after the
/// strict check passes; writes `turbofan.glb` and `turbofan.manifest.json` into a NEW directory.
func exportGLTF(_ m: TurbofanModel, to path: String, fps: Int, engineCommit: String) throws {
    var identity = MGEngine.identity.objectValue ?? [:]
    if let exe = Bundle.main.executableURL.flatMap({ try? Data(contentsOf: $0, options: .mappedIfSafe) }) {
        identity["executableSHA256"] = .string(SHA256.hash(data: exe).map { String(format: "%02x", $0) }.joined())
    }
    let engine = MGJSON.object(identity)
    let checked: MGSolidGLTF.Checked
    switch MGSolidGLTF.check(data: m.data, engine: engine) {
    case .failure(let refused): throw Failure("turbofan.json refused by the strict check: \(refused.reason ?? "?") (no export)")
    case .success(let c): checked = c
    }
    let a = checked.document.assembly, aspect = 1280.0 / 800.0
    let frames = Int((Loop.seconds * Double(fps)).rounded())
    let us = (0..<frames).map { Double($0) / Double(frames) }
    let all: [String] = []
    let hero = framedCamera(a, aspect: aspect, all, MGPoseParameters(input: 0.2), yaw: -32, pitch: 20, zoom: 0.88)
    let labelled = framedCamera(a, aspect: aspect, all, MGPoseParameters(input: 0.2), yaw: -30, pitch: 24, zoom: 0.98)
    let timeline = MGSolidGLTF.Timeline(
        fps: fps, poses: us.map { MGPoseParameters(input: Loop.input($0)) },
        cameras: us.map { framedCamera(a, aspect: aspect, all, MGPoseParameters(), yaw: Loop.yaw($0), pitch: Loop.pitch($0), zoom: Loop.zoom($0)) },
        cameraName: "loop", stills: [.init(name: "hero", camera: hero), .init(name: "labelled", camera: labelled)], aspect: aspect,
        about: "marty-turbofan showcase loop: \(Loop.seconds) s, LP spool one turn, HP spool three turns, slow orbit swing")
    let out = try MGSolidGLTF.export(checked, timeline: timeline, sourceID: "turbofan", glbName: "turbofan.glb",
                                     engineCommit: engineCommit, engine: engine)
    let dir = try Media.newDirectory(path)
    try out.glb.write(to: dir.appendingPathComponent("turbofan.glb"), options: .withoutOverwriting)
    try Data(out.manifestText.utf8).write(to: dir.appendingPathComponent("turbofan.manifest.json"), options: .withoutOverwriting)
    print("Exported turbofan.glb: \(out.glb.count) bytes, sha256 \(out.sha256), \(frames) frames at \(fps) fps.")
}
