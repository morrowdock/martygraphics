// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import MartyGraphics
@testable import MartySolidGLTF

/// `marty-solid export-gltf --seamless` (`MGSolidGLTF.seamlessLoop`, docs/ENGINE.md "Seamless loops") on the
/// robot-joint gearbox: the default export's output carrier advances 0.082° a frame and then jumps 29.306° back at the
/// wrap; the seamless export plays the exact period (49/6 input turns) with no jump, keys a closing frame and records
/// the loop for the render path.
final class SeamlessLoopExportTests: XCTestCase {
    func checked() throws -> MGSolidGLTF.Checked {
        let data = try Data(contentsOf: MartySolidGLTFTests.gearbox)
        guard case .success(let c) = MGSolidGLTF.check(data: data) else {
            XCTFail("the gearbox must pass the strict check")
            throw MGSolidGLTF.Refusal("test.check")
        }
        return c
    }

    func testTheSeamlessExportHasNoJumpAtTheWrap() throws {
        let c = try checked()
        let a = c.document.assembly
        let period = try MGSolidLoop.period(c.document).get()

        // The default export: one input turn in 360 frames.
        let plain = try MGSolidGLTF.renderLoop(c, fps: 30)
        XCTAssertNil(plain.loop)
        XCTAssertEqual(plain.poses.count, 360)
        let carrier = try XCTUnwrap(MGSolidLoop.wrap(a, poses: plain.poses, symmetry: period.symmetry).first { $0.part == "carrier2" })
        XCTAssertEqual(carrier.step, 4.0 / 49, accuracy: 1e-9, "0.082° a frame")
        XCTAssertEqual(carrier.jump, -4.0 / 49 * 359, accuracy: 1e-9, "29.306° back at the wrap")

        // The seamless export: 49/6 input turns over 490 frames, then the closing frame.
        let t = try MGSolidGLTF.seamlessLoop(c, fps: 30)
        let loop = try XCTUnwrap(t.loop)
        XCTAssertEqual(loop.inputTurns, "49/6")
        XCTAssertEqual(loop.frames, 490)
        XCTAssertEqual(t.poses.count, 491, "the loop frames and the closing frame")
        XCTAssertEqual(t.cameras.count, 491)
        let rows = MGSolidLoop.wrap(a, poses: Array(t.poses.prefix(loop.frames)), closing: t.poses[loop.frames], symmetry: period.symmetry)
        XCTAssertFalse(rows.isEmpty)
        XCTAssertLessThan(MGSolidLoop.worst(rows)?.error ?? 1, 1e-7)
        // The animated camera closes the loop too.
        XCTAssertLessThan((t.cameras[loop.frames].position - t.cameras[0].position).length, 1e-6 * max(1, t.cameras[0].position.length))

        // The manifest tells the render path: frameCount counts the closing frame, `loop` names the loop frames.
        let o = try MGSolidGLTF.export(c, timeline: t, sourceID: "robot-joint-gearbox", glbName: "robot-joint-gearbox.glb",
                                       engineCommit: MartySolidGLTFTests.commit)
        let m = o.manifest
        XCTAssertEqual(m["frameCount"], .number(491))
        XCTAssertEqual(m["loop"]?["seamless"], .bool(true))
        XCTAssertEqual(m["loop"]?["frames"], .number(490))
        XCTAssertEqual(m["loop"]?["closingFrame"], .number(490))
        XCTAssertEqual(m["loop"]?["inputTurns"], .string("49/6"))
        XCTAssertNil(try MGSolidGLTF.export(c, timeline: plain, sourceID: "robot-joint-gearbox", glbName: "robot-joint-gearbox.glb",
                                            engineCommit: MartySolidGLTFTests.commit).manifest["loop"], "the default export is unchanged")
        // Deterministic.
        let again = try MGSolidGLTF.export(c, timeline: try MGSolidGLTF.seamlessLoop(c, fps: 30), sourceID: "robot-joint-gearbox",
                                           glbName: "robot-joint-gearbox.glb", engineCommit: MartySolidGLTFTests.commit)
        XCTAssertEqual(again.glb, o.glb)
        XCTAssertEqual(again.manifestText, o.manifestText)
    }

    /// The closing key on the exported file (docs/ENGINE.md, "Verify on a Mac"): re-read with the independent GLB
    /// reader, key `frames` (490 for the robot joint) shows what key 0 shows. Every mesh vertex at the closing key lies
    /// on a vertex of the same material at key 0 (the turning parts moved by whole symmetry steps, so the scene looks
    /// the same although their transforms differ), and every camera node is where it was at key 0.
    func testTheClosingKeyLooksLikeKeyZero() throws {
        let c = try checked()
        let t = try MGSolidGLTF.seamlessLoop(c, fps: 30)
        let loop = try XCTUnwrap(t.loop)
        XCTAssertEqual(loop.frames, 490)
        let o = try MGSolidGLTF.export(c, timeline: t, sourceID: "robot-joint-gearbox", glbName: "robot-joint-gearbox.glb",
                                       engineCommit: MartySolidGLTFTests.commit)
        let g = try MartySolidGLTFTests.GLB(o.glb)
        let first = MartySolidGLTFTests.nodeWorlds(g, MartySolidGLTFTests.nodeLocals(g, frame: 0))
        let closing = MartySolidGLTFTests.nodeWorlds(g, MartySolidGLTFTests.nodeLocals(g, frame: loop.frames))
        let nodes = g.array("nodes"), meshes = g.array("meshes")

        // World-space vertices (metres) of every mesh node at one key, with their material.
        func vertices(_ world: [MartySolidGLTFTests.Rigid]) -> [(p: [Double], material: Int)] {
            var out: [(p: [Double], material: Int)] = []
            for (i, n) in nodes.enumerated() {
                guard let m = n["mesh"] as? Int, let primitives = meshes[m]["primitives"] as? [[String: Any]] else { continue }
                let w = world[i]
                for prim in primitives {
                    guard let attributes = prim["attributes"] as? [String: Any], let a = attributes["POSITION"] as? Int else { continue }
                    let f = g.floats(a).map(Double.init), material = prim["material"] as? Int ?? -1
                    for k in stride(from: 0, to: f.count - 2, by: 3) {
                        let x = [f[k], f[k + 1], f[k + 2]]
                        out.append(((0..<3).map { r in w.t[r] + (0..<3).map { w.r[r][$0] * x[$0] }.reduce(0, +) }, material))
                    }
                }
            }
            return out
        }
        let a = vertices(first), b = vertices(closing)
        XCTAssertEqual(a.count, b.count)
        XCTAssertGreaterThan(a.count, 1000, "the gearbox's meshes")
        var lo = [Double](repeating: .infinity, count: 3), hi = [Double](repeating: -.infinity, count: 3)
        for v in a { for r in 0..<3 { lo[r] = min(lo[r], v.p[r]); hi[r] = max(hi[r], v.p[r]) } }
        let size = zip(lo, hi).map { $1 - $0 }.max() ?? 1
        let tolerance = max(1e-7, size * 1e-5)

        // Key-0 vertices hashed on a grid of twice the tolerance: a match lies in one of the 27 cells around a query.
        struct Cell: Hashable { let m: Int, x: Int, y: Int, z: Int }
        let cell = 2 * tolerance
        func key(_ p: [Double], _ m: Int, _ d: (Int, Int, Int) = (0, 0, 0)) -> Cell {
            Cell(m: m, x: Int((p[0] / cell).rounded(.down)) + d.0, y: Int((p[1] / cell).rounded(.down)) + d.1, z: Int((p[2] / cell).rounded(.down)) + d.2)
        }
        var grid: [Cell: [[Double]]] = [:]
        for v in a { grid[key(v.p, v.material), default: []].append(v.p) }
        var unmatched = 0, worst = 0.0
        for v in b {
            var best = Double.infinity
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                for q in grid[key(v.p, v.material, (dx, dy, dz))] ?? [] {
                    best = min(best, zip(q, v.p).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot())
                }
            } } }
            if best > tolerance { unmatched += 1; worst = max(worst, best) }
        }
        XCTAssertEqual(unmatched, 0, "\(unmatched) closing-key vertices are off every key-0 vertex (worst \(worst) m, tolerance \(tolerance) m)")

        // The camera nodes close the loop too.
        var cameras = 0
        for (i, n) in nodes.enumerated() where n["camera"] != nil {
            let e = MartySolidGLTFTests.Rigid.error(first[i], closing[i])
            XCTAssertLessThan(e.angle, 1e-5, "camera node \(i) turns at the wrap")
            XCTAssertLessThan(e.distance, 1e-6 * max(1, first[i].t.map(abs).max() ?? 1), "camera node \(i) moves at the wrap")
            cameras += 1
        }
        XCTAssertGreaterThan(cameras, 0)
    }

    func testASeamlessLoopThatCannotFitIsRefusedWithAReason() throws {
        let c = try checked()
        var options = MGSolidLoop.Options()
        options.maxTurns = 4                               // the gearbox needs 49/6
        XCTAssertThrowsError(try MGSolidGLTF.seamlessLoop(c, fps: 30, options: options)) {
            XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.loop.period")
        }
        XCTAssertThrowsError(try MGSolidGLTF.seamlessLoop(c, fps: 24)) { XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.fps") }
    }
}
