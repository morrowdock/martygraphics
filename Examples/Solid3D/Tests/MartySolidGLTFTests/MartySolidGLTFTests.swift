// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Foundation
import XCTest
import MartyGraphics
@testable import MartySolidGLTF

/// The glTF exporter on a published showcase scene (the AI-written robot-joint gearbox): the `.glb` is re-read with
/// an independent reader, and every node's world transform at sampled frames must equal the engine's own transform
/// (`MGSolidStage.zUpToYUp * MGAssembly.pose(...).world`) within 1e-5 m and 1e-5 rad. Two exports are byte-identical,
/// and a document the strict check refuses never reaches the exporter.
final class MartySolidGLTFTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let gearbox = root.appendingPathComponent("docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json")
    /// A placeholder engine commit (the tests do not know the commit they were built from).
    static let commit = "0123456789abcdef0123456789abcdef01234567"
    static let refused = root.appendingPathComponent("docs/assets/from-a-prompt/robot-joint/attempt-1-refused.json")

    /// One strict check and export, shared by the tests (the engine identity without a build hash, as a library host).
    static let exported: (checked: MGSolidGLTF.Checked, timeline: MGSolidGLTF.Timeline, output: MGSolidGLTF.Output)? = {
        guard let data = try? Data(contentsOf: gearbox), case .success(let c) = MGSolidGLTF.check(data: data),
              let t = try? MGSolidGLTF.renderLoop(c),
              let o = try? MGSolidGLTF.export(c, timeline: t, sourceID: "robot-joint-gearbox", glbName: "robot-joint-gearbox.glb",
                                         engineCommit: MartySolidGLTFTests.commit) else { return nil }
        return (c, t, o)
    }()

    func export() throws -> (checked: MGSolidGLTF.Checked, timeline: MGSolidGLTF.Timeline, output: MGSolidGLTF.Output) {
        try XCTUnwrap(Self.exported, "the gearbox must pass the strict check and export")
    }

    // MARK: Independent GLB reader

    struct GLB {
        let json: [String: Any]
        let bin: Data

        init(_ d: Data) throws {
            func u32(_ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 | Int(d[at + 2]) << 16 | Int(d[at + 3]) << 24 }
            guard d.count >= 28, u32(0) == 0x4654_6C67, u32(4) == 2, u32(8) == d.count else { throw XCTSkip("not a GLB 2 file") }
            let jl = u32(12)
            guard u32(16) == 0x4E4F_534A, jl % 4 == 0 else { throw XCTSkip("bad JSON chunk") }
            json = try XCTUnwrap(JSONSerialization.jsonObject(with: d.subdata(in: 20..<(20 + jl))) as? [String: Any])
            let b = 20 + jl
            guard u32(b + 4) == 0x004E_4942, u32(b) % 4 == 0, b + 8 + u32(b) == d.count else { throw XCTSkip("bad BIN chunk") }
            bin = d.subdata(in: (b + 8)..<(b + 8 + u32(b)))
        }

        func array(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }

        /// The float components of accessor `i` (component type 5126), in order.
        func floats(_ i: Int) -> [Float] {
            let a = array("accessors")[i], v = array("bufferViews")[a["bufferView"] as! Int]
            let width = ["SCALAR": 1, "VEC3": 3, "VEC4": 4][a["type"] as! String]!
            precondition(a["componentType"] as! Int == 5126)
            let start = (v["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0), n = (a["count"] as! Int) * width
            precondition(start + 4 * n <= (v["byteOffset"] as? Int ?? 0) + (v["byteLength"] as! Int))
            return (0..<n).map { k in
                let o = start + 4 * k
                return Float(bitPattern: UInt32(bin[o]) | UInt32(bin[o + 1]) << 8 | UInt32(bin[o + 2]) << 16 | UInt32(bin[o + 3]) << 24)
            }
        }
    }

    /// Row-major 3 × 3 rotation and a translation.
    struct Rigid {
        var r: [[Double]]
        var t: [Double]
        static let identity = Rigid(r: [[1, 0, 0], [0, 1, 0], [0, 0, 1]], t: [0, 0, 0])
        init(r: [[Double]], t: [Double]) { self.r = r; self.t = t }
        /// From a glTF translation and unit quaternion (x, y, z, w).
        init(t: [Double], q: [Double]) {
            let (x, y, z, w) = (q[0], q[1], q[2], q[3])
            r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
            self.t = t
        }
        /// From an engine transform, translation in millimetres to metres.
        init(_ m: MGTransform) {
            r = [[m.c0.x, m.c1.x, m.c2.x], [m.c0.y, m.c1.y, m.c2.y], [m.c0.z, m.c1.z, m.c2.z]]
            t = [m.translation.x * 0.001, m.translation.y * 0.001, m.translation.z * 0.001]
        }
        static func * (a: Rigid, b: Rigid) -> Rigid {
            var r = [[Double]](repeating: [0, 0, 0], count: 3), t = a.t
            for i in 0..<3 {
                for j in 0..<3 { r[i][j] = (0..<3).map { a.r[i][$0] * b.r[$0][j] }.reduce(0, +) }
                t[i] += (0..<3).map { a.r[i][$0] * b.t[$0] }.reduce(0, +)
            }
            return Rigid(r: r, t: t)
        }
        /// Angle (radians) of the rotation between `a` and `b`, and the distance (metres) between their origins.
        static func error(_ a: Rigid, _ b: Rigid) -> (angle: Double, distance: Double) {
            var m = [[Double]](repeating: [0, 0, 0], count: 3)   // aᵀ b
            for i in 0..<3 { for j in 0..<3 { m[i][j] = (0..<3).map { a.r[$0][i] * b.r[$0][j] }.reduce(0, +) } }
            let s = [m[2][1] - m[1][2], m[0][2] - m[2][0], m[1][0] - m[0][1]].map { $0 / 2 }
            let angle = atan2((s[0] * s[0] + s[1] * s[1] + s[2] * s[2]).squareRoot(), (m[0][0] + m[1][1] + m[2][2] - 1) / 2)
            let d = zip(a.t, b.t).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
            return (angle, d)
        }
    }

    /// Each node's local transform at frame `k`: its animation keys where it has them, else its rest transform.
    func locals(_ g: GLB, frame k: Int) -> [Rigid] {
        var keyed: [Int: (t: [Double]?, q: [Double]?)] = [:]
        if let anim = g.array("animations").first, let channels = anim["channels"] as? [[String: Any]],
           let samplers = anim["samplers"] as? [[String: Any]] {
            for c in channels {
                let target = c["target"] as! [String: Any], node = target["node"] as! Int
                let out = g.floats(samplers[c["sampler"] as! Int]["output"] as! Int).map(Double.init)
                if target["path"] as! String == "translation" { keyed[node, default: (nil, nil)].t = Array(out[(3 * k)..<(3 * k + 3)]) }
                else { keyed[node, default: (nil, nil)].q = Array(out[(4 * k)..<(4 * k + 4)]) }
            }
        }
        return g.array("nodes").enumerated().map { i, n in
            let t = keyed[i]?.t ?? (n["translation"] as? [Double] ?? [0, 0, 0])
            let q = keyed[i]?.q ?? (n["rotation"] as? [Double] ?? [0, 0, 0, 1])
            return Rigid(t: t, q: q)
        }
    }

    /// World transforms from the node hierarchy (parents from `children`).
    func worlds(_ g: GLB, _ locals: [Rigid]) -> [Rigid] {
        var parent: [Int: Int] = [:]
        for (i, n) in g.array("nodes").enumerated() { for c in n["children"] as? [Int] ?? [] { parent[c] = i } }
        var memo: [Int: Rigid] = [:]
        func w(_ i: Int) -> Rigid {
            if let m = memo[i] { return m }
            let r = (parent[i].map(w) ?? .identity) * locals[i]
            memo[i] = r
            return r
        }
        return locals.indices.map(w)
    }

    // MARK: Tests

    func testNodeTransformsMatchTheEngineAtSampledFrames() throws {
        let (c, t, o) = try export()
        let g = try GLB(o.glb)
        let a = c.document.assembly
        XCTAssertEqual(t.fps, 30)
        XCTAssertEqual(t.poses.count, 360, "12 s at 30 fps")
        let nodes = g.array("nodes")
        var byName: [String: Int] = [:]
        for (i, n) in nodes.enumerated() { byName[n["name"] as! String] = i }
        XCTAssertEqual(Set(a.parts.map(\.id)).subtracting(byName.keys), [], "one node per part, named by part id")
        // Key times are k / fps.
        let anim = try XCTUnwrap(g.array("animations").first)
        let samplers = try XCTUnwrap(anim["samplers"] as? [[String: Any]])
        let times = g.floats(samplers[0]["input"] as! Int)
        XCTAssertEqual(times.count, 360)
        for k in [0, 1, 359] { XCTAssertEqual(times[k], Float(Double(k) / 30)) }
        var moving = 0, worst = (angle: 0.0, distance: 0.0)
        for k in [0, 61, 137, 241, 359] {
            let pose = a.pose(t.poses[k])
            let world = worlds(g, locals(g, frame: k))
            for part in a.parts {
                let i = try XCTUnwrap(byName[part.id])
                let engine = Rigid(MGSolidStage.zUpToYUp * (pose.world[part.id] ?? .identity))
                let e = Rigid.error(engine, world[i])
                worst = (max(worst.angle, e.angle), max(worst.distance, e.distance))
                XCTAssertLessThanOrEqual(e.distance, 1e-5, "\(part.id) frame \(k): \(e.distance) m")
                XCTAssertLessThanOrEqual(e.angle, 1e-5, "\(part.id) frame \(k): \(e.angle) rad")
            }
            // The animated loop camera sits where the plan's camera sits and looks at its target.
            let cam = t.cameras[k], ci = try XCTUnwrap(byName["camera.loop"])
            let p = cam.position, target = cam.targetVector
            let e = Rigid.error(Rigid(r: world[ci].r, t: [p.x * 0.001, p.y * 0.001, p.z * 0.001]), world[ci])
            XCTAssertLessThanOrEqual(e.distance, 1e-5)
            let f = (target - p).normalized, look = world[ci].r.map { -$0[2] }   // local −Z in world
            XCTAssertLessThanOrEqual((MGVec3(look[0], look[1], look[2]) - f).length, 1e-5)
        }
        let manifest = o.manifest
        if case .array(let parts)? = manifest["parts"] { moving = parts.filter { $0["moving"] == .bool(true) }.count }
        XCTAssertGreaterThan(moving, 10, "the suns, planets and carriers move")
        print("gltf: worst error over 5 frames: \(worst.angle) rad, \(worst.distance) m")
    }

    func testExportIsDeterministicAndTheManifestNamesTheGLB() throws {
        let (_, _, first) = try export()
        let data = try Data(contentsOf: Self.gearbox)
        guard case .success(let c) = MGSolidGLTF.check(data: data) else { return XCTFail("strict check") }
        let again = try MGSolidGLTF.export(c, timeline: try MGSolidGLTF.renderLoop(c), sourceID: "robot-joint-gearbox",
                                           glbName: "robot-joint-gearbox.glb", engineCommit: Self.commit)
        XCTAssertEqual(first.glb, again.glb, "two exports are byte-identical")
        XCTAssertEqual(first.manifestText, again.manifestText)
        let sha = SHA256.hash(data: first.glb).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(first.sha256, sha)
        let m = first.manifest
        // The render path's export format (martygraphics.render-export/1, tools/render-blender/README.md).
        XCTAssertEqual(m["format"], .string("martygraphics.render-export/1"))
        XCTAssertEqual(m["engine"]?["commit"], .string(Self.commit))
        XCTAssertEqual(m["engine"]?["name"], .string("MartyGraphics"))
        XCTAssertEqual(m["scene"]?["id"], .string("robot-joint-gearbox"))
        XCTAssertEqual(m["glb"]?["sha256"], .string(sha))
        XCTAssertEqual(m["glb"]?["bytes"], .number(Double(first.glb.count)))
        XCTAssertEqual(m["fps"], .number(30))
        XCTAssertEqual(m["frameCount"], .number(360))
        XCTAssertEqual(m["source"]?["sha256"], .string(MGSolidSource(data: data).sha256))
        XCTAssertEqual(m["units"], .string("metres"))
        XCTAssertEqual(m["check"]?["profile"], .string("strict"))
        if case .array(let cams)? = m["cameras"] {
            XCTAssertEqual(cams.first?["name"], .string("camera.loop"), "the animated camera first, named by its node")
            XCTAssertTrue(cams.contains { $0["name"] == .string("camera.hero") })
        } else { XCTFail("cameras") }
    }

    func testGLBIsWellFormed() throws {
        let (c, _, o) = try export()
        let g = try GLB(o.glb)
        XCTAssertEqual((g.json["asset"] as? [String: Any])?["version"] as? String, "2.0")
        XCTAssertEqual(g.array("buffers").first?["byteLength"] as? Int, g.bin.count)
        for v in g.array("bufferViews") {
            let off = v["byteOffset"] as? Int ?? 0, len = v["byteLength"] as! Int
            XCTAssertEqual(off % 4, 0)
            XCTAssertLessThanOrEqual(off + len, g.bin.count)
        }
        var triangles = 0
        for mesh in g.array("meshes") {
            for p in mesh["primitives"] as! [[String: Any]] {
                let attrs = p["attributes"] as! [String: Int]
                let pos = g.array("accessors")[attrs["POSITION"]!]
                XCTAssertNotNil(pos["min"]); XCTAssertNotNil(pos["max"])
                triangles += (g.array("accessors")[p["indices"] as! Int]["count"] as! Int) / 3
                // Metres: the gearbox is about a tenth of a metre across, not a hundred.
                let hi = (pos["max"] as! [Double]).map(abs).max()!
                XCTAssertLessThan(hi, 1)
            }
        }
        XCTAssertEqual(triangles, 102_352, "the triangles `marty-solid check` reports")
        XCTAssertEqual(c.report.ok, true)
        let used = g.json["extensionsUsed"] as? [String] ?? []
        XCTAssertTrue(used.contains("KHR_lights_punctual"))
        let lights = ((g.json["extensions"] as? [String: Any])?["KHR_lights_punctual"] as? [String: Any])?["lights"] as? [[String: Any]]
        XCTAssertEqual(lights?.map { $0["name"] as! String }, ["key", "fill", "rim"])
    }

    func testRefusedDocumentsNeverReachTheExporter() throws {
        // Refused by the standard check (the published first try of the same prompt).
        let first = try Data(contentsOf: Self.refused)
        guard case .failure(let r) = MGSolidGLTF.check(data: first) else { return XCTFail("the refused try must not pass") }
        XCTAssertEqual(r.reason, "constraint.gearMesh.phase")
        // Accepted by the standard profile, refused by the strict one (a joint that nothing drives).
        let idle = Data(#"""
        {"v": 1, "kind": "assembly", "title": "Idle wheel", "units": "mm",
         "parts": [{"id": "base", "name": "Base", "material": "aluminum", "shape": {"box": {"size": [40, 40, 10]}}},
                   {"id": "wheel", "name": "Wheel", "parent": "base", "material": "brass",
                    "shape": {"shaft": {"radius": 10, "length": 10}}, "joint": {"revolute": [0, 0, 1]}}]}
        """#.utf8)
        XCTAssertTrue(MGSolidReport.check(data: idle).ok, "the standard profile accepts it")
        guard case .failure(let s) = MGSolidGLTF.check(data: idle) else { return XCTFail("the strict check must refuse it") }
        XCTAssertEqual(s.reason, "joint.idle.wheel")
    }

    func testTimelineGuards() throws {
        let (c, t, _) = try export()
        XCTAssertThrowsError(try MGSolidGLTF.renderLoop(c, fps: 24)) { XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.fps") }
        var bad = t
        bad.cameras.removeLast()
        XCTAssertThrowsError(try MGSolidGLTF.export(c, timeline: bad, sourceID: "x", glbName: "x.glb", engineCommit: Self.commit)) {
            XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.cameras")
        }
        XCTAssertThrowsError(try MGSolidGLTF.export(c, timeline: t, sourceID: "x", glbName: "x.glb", engineCommit: "main")) {
            XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.engineCommit")
        }
        XCTAssertThrowsError(try MGSolidGLTF.export(c, timeline: t, sourceID: "-bad id", glbName: "x.glb", engineCommit: Self.commit)) {
            XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.sourceID")
        }
        var long = t
        long.stills.append(.init(name: String(repeating: "x", count: 60), camera: t.stills[0].camera))
        XCTAssertThrowsError(try MGSolidGLTF.export(c, timeline: long, sourceID: "x", glbName: "x.glb", engineCommit: Self.commit)) {
            XCTAssertEqual(($0 as? MGSolidGLTF.Refusal)?.reason, "gltf.nodeName", "camera.<60 x> is over 63 bytes")
        }
    }

    func testQuaternionRoundTrip() {
        for (axis, angle) in [(MGVec3(1, 0, 0), 0.3), (MGVec3(0, 1, 1), 3.1), (MGVec3(1, -2, 0.5), -2.9), (MGVec3(0, 0, 1), .pi)] {
            let m = MGTransform.rotation(axis: axis, angle: angle)
            let q = MGSolidGLTF.quaternion(m)
            XCTAssertGreaterThanOrEqual(q[3], 0)
            let e = Rigid.error(Rigid(m), Rigid(t: [0, 0, 0], q: q))
            XCTAssertLessThan(e.angle, 1e-12)
        }
    }
}
