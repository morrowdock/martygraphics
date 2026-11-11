// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Foundation
import MartyGraphics

/// glTF 2.0 binary (`.glb`) export of a checked solid document and its motion, so an offline renderer (for example
/// Blender Cycles) can render the same scene at film quality on another machine. See docs/GLTF-EXPORT.md.
///
/// The exporter only reads. It takes a document that passed the strict check (`check(data:library:engine:)` is the
/// only way to get a `Checked` value), poses it with the engine's own `MGAssembly.pose`, and writes what the engine
/// computed: one node per part (the part hierarchy, part ids as node names), each part's mesh in its own frame, simple
/// PBR materials, the cameras and the studio's directional lights, and the motion baked as one translation and one
/// rotation key per frame for every node that moves. It adds nothing to the scene and changes no engine output.
///
/// Units are metres (the engine's millimetres times 0.001), +Y up, right-handed, as glTF requires: the engine's Z-up
/// kernel frame goes through `MGSolidStage.zUpToYUp`, as in every render. The output is deterministic: the same
/// document and timeline give the same bytes.
public enum MGSolidGLTF {
    /// `format` of the sidecar manifest: the Blender render path's export format (tools/render-blender/README.md,
    /// "Export manifest"). Its checker refuses an export whose `.glb` SHA-256, fps, frame count, key grid or node names
    /// do not match.
    public static let manifestFormat = "martygraphics.render-export/1"
    /// Longest node name in bytes (Blender's object-name limit; the render path refuses longer names).
    public static let nodeNameLimit = 63
    /// Name of the root node (part ids never hold a dot, so no part node can take it).
    public static let rootName = "martygraphics.scene"
    /// Engine units (millimetres) to glTF units (metres).
    public static let metresPerMillimetre = 0.001
    public static let defaultFPS = 30
    /// Frame rates a hand-built timeline may use.
    public static let fpsRange = 1...240
    /// Most frames one export bakes (60 s at 240 fps).
    public static let maxFrames = 14_400
    /// glTF directional light intensity (lux) per unit of studio intensity: studio intensity / 1000 × 683, so a
    /// renderer that converts lux to W/m² at 683 lm/W (Blender's glTF importer, standard lighting mode) gets the key light
    /// at strength 1.45.
    public static let luxPerStudioUnit = 0.683

    /// Why an export was refused: a stable reason (`gltf.*`, docs/GLTF-EXPORT.md) and the part it concerns, if any.
    public struct Refusal: Error, Equatable, CustomStringConvertible {
        public var reason: String
        public var part: String?
        public init(_ reason: String, part: String? = nil) { self.reason = reason; self.part = part }
        public var description: String { part.map { "\(reason) (\($0))" } ?? reason }
    }

    /// A document that passed the strict check (`marty-solid check --strict`), with its source facts and report.
    /// Only `check(data:library:engine:)` makes one, so the exporter can never write a scene the engine refused.
    public struct Checked: Sendable {
        public let document: MGSolidDocument
        public let source: MGSolidSource
        public let report: MGSolidReport
        fileprivate init(document: MGSolidDocument, source: MGSolidSource, report: MGSolidReport) {
            self.document = document; self.source = source; self.report = report
        }
    }

    /// A document the strict check refused: its full report, for the author to repair from.
    public struct Refused: Error, Sendable {
        public let report: MGSolidReport
        public var reason: String? { report.reason }
    }

    /// The strict check, exactly as `marty-solid check --strict` runs it (`MGSolidReport.check`, profile `.strict`),
    /// then the same compile `marty-solid render` uses. A refused document gives its report and nothing to export.
    public static func check(data: Data, library: MGSolidLibrary = .builtIn, engine: MGJSON? = MGEngine.identity) -> Result<Checked, Refused> {
        let report = MGSolidReport.check(data: data, library: library, profile: .strict, engine: engine)
        guard report.ok else { return .failure(Refused(report: report)) }
        switch MGSolidParser.document(data: data, library: library) {
        case .success(let doc): return .success(Checked(document: doc, source: MGSolidSource(data: data), report: report))
        case .failure(let issue): return .failure(Refused(report: MGSolidReport.refused(issue, engine: engine)))
        }
    }

    // MARK: Timeline

    /// A named still camera.
    public struct NamedCamera: Equatable, Sendable {
        public var name: String
        public var camera: MGSolidCamera
        public init(name: String, camera: MGSolidCamera) { self.name = name; self.camera = camera }
    }

    /// The motion to bake: one pose per frame at `fps` (frame k at k / fps seconds), an optional animated camera (one
    /// per frame) and still cameras. Cameras are in the engine's Y-up world, millimetres (`MGSolidCamera`).
    public struct Timeline: Equatable, Sendable {
        public var fps: Int
        public var poses: [MGPoseParameters]
        /// One camera per frame, or empty for no animated camera.
        public var cameras: [MGSolidCamera]
        public var cameraName: String
        public var stills: [NamedCamera]
        /// Width over height of the frame the cameras were framed for.
        public var aspect: Double
        /// One line on where the motion comes from (for the manifest).
        public var about: String

        public init(fps: Int, poses: [MGPoseParameters], cameras: [MGSolidCamera] = [], cameraName: String = "loop",
                    stills: [NamedCamera] = [], aspect: Double = 1.6, about: String) {
            self.fps = fps; self.poses = poses; self.cameras = cameras; self.cameraName = cameraName
            self.stills = stills; self.aspect = aspect; self.about = about
        }
        public var seconds: Double { Double(poses.count) / Double(max(fps, 1)) }
    }

    /// The loop of `marty-solid render` (`MGSolidRenderPlan`, 12 s: one input turn, one orbit and an
    /// explode-and-reassemble beat) at `fps` (10 or 30, `MGSolidRenderPlan.loopRates`), with the plan's loop camera per
    /// frame and one still camera per still (`hero`, `exploded`, `step-<n>`), framed for `width` × `height` pixels.
    public static func renderLoop(_ c: Checked, fps: Int = defaultFPS, width: Int = 1280, height: Int = 800) throws -> Timeline {
        guard MGSolidRenderPlan.loopRates.contains(fps) else { throw Refusal("gltf.fps") }
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { throw Refusal("gltf.size") }
        let doc = c.document
        let plan = MGSolidRenderPlan(doc, sourceName: "", source: c.source, loop: true, loopRate: fps)
        let cams = plan.cameras(doc, width: Double(width), height: Double(height))
        let stills = zip(plan.stills, cams.stills).map { shot, cam in
            NamedCamera(name: shot.file.hasSuffix(".png") ? String(shot.file.dropLast(4)) : shot.file, camera: cam)
        }
        return Timeline(fps: fps, poses: plan.loop.map(\.params), cameras: cams.loop, cameraName: "loop", stills: stills,
                        aspect: Double(width) / Double(height),
                        about: "marty-solid render loop (MGSolidRenderPlan): \(MGSolidRenderPlan.loopSeconds) s, one input turn, one orbit, explode and reassemble")
    }

    // MARK: Export

    /// The `.glb` bytes, their SHA-256 and the sidecar manifest.
    public struct Output: Sendable {
        public var glb: Data
        public var sha256: String
        public var manifest: MGJSON
        /// The manifest as pretty-printed JSON with sorted keys and a final newline.
        public var manifestText: String { MGSolidReport.text(manifest) + "\n" }
    }

    /// True for a scene id the render path accepts: a letter or digit, then up to 63 letters, digits, `.`, `_` or `-`.
    public static func isSceneID(_ s: String) -> Bool {
        let ok = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard let first = s.first, first.isASCII, first.isLetter || first.isNumber, s.count <= 64 else { return false }
        return s.allSatisfy(ok.contains)
    }

    /// Exports `c` posed over `timeline`. `sourceID` is the scene id (`isSceneID`, for example the file name without
    /// `.json`); `glbName` is the file name the manifest records; `engineCommit` is the 40-hex-digit commit the engine
    /// was built from (required: the engine does not know its own commit, so the host passes it). `engineCommit` and
    /// `engine` (the engine identity, with a build hash if the host has one) go into the manifest only, never into
    /// the `.glb`.
    public static func export(_ c: Checked, timeline t: Timeline, sourceID: String, glbName: String,
                              engineCommit: String, engine: MGJSON? = MGEngine.identity) throws -> Output {
        guard fpsRange.contains(t.fps) else { throw Refusal("gltf.fps") }
        guard !t.poses.isEmpty, t.poses.count <= maxFrames else { throw Refusal("gltf.frames") }
        guard t.cameras.isEmpty || t.cameras.count == t.poses.count else { throw Refusal("gltf.cameras") }
        guard t.aspect.isFinite, t.aspect > 0 else { throw Refusal("gltf.aspect") }
        guard isSceneID(sourceID) else { throw Refusal("gltf.sourceID") }
        guard glbName.hasSuffix(".glb"), !glbName.contains("/"), glbName.utf8.count <= 200 else { throw Refusal("gltf.name") }
        guard engineCommit.count == 40, engineCommit.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw Refusal("gltf.engineCommit") }
        var b = Builder(c.document, timeline: t)
        try b.build()
        let glb = b.glb()
        let sha = SHA256.hash(data: glb).map { String(format: "%02x", $0) }.joined()
        let manifest = b.manifest(c, sourceID: sourceID, glbName: glbName, glbBytes: glb.count, sha256: sha,
                                  engineCommit: engineCommit, engine: engine)
        return Output(glb: glb, sha256: sha, manifest: manifest)
    }

    // MARK: Math

    /// Unit quaternion (x, y, z, w) of a rigid transform's rotation, w ≥ 0.
    static func quaternion(_ m: MGTransform) -> [Double] {
        let m00 = m.c0.x, m10 = m.c0.y, m20 = m.c0.z, m01 = m.c1.x, m11 = m.c1.y, m21 = m.c1.z
        let m02 = m.c2.x, m12 = m.c2.y, m22 = m.c2.z
        let tr = m00 + m11 + m22
        var q: [Double]
        if tr > 0 {
            let s = (tr + 1).squareRoot() * 2
            q = [(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s]
        } else if m00 > m11 && m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            q = [0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s]
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            q = [(m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s]
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            q = [(m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s]
        }
        let n = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).squareRoot()
        q = q.map { $0 / n }
        return q[3] < 0 ? q.map { -$0 } : q
    }

    /// True for a finite rotation-plus-translation (orthonormal columns, determinant +1, within 1e-6).
    static func isRigid(_ m: MGTransform) -> Bool {
        let cs = [m.c0, m.c1, m.c2]
        guard (cs + [m.translation]).allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return false }
        for i in 0..<3 {
            guard abs(cs[i].length - 1) < 1e-6 else { return false }
            for j in (i + 1)..<3 where abs(cs[i].dot(cs[j])) > 1e-6 { return false }
        }
        return m.c0.dot(m.c1.cross(m.c2)) > 0
    }

    /// The node transform of a camera at `c` (world Y-up, mm): its position (still in millimetres, like every engine
    /// transform; the node writer scales once) and a rotation whose local −Z looks at the target with +Y up (the glTF
    /// camera convention).
    static func cameraTransform(_ c: MGSolidCamera) -> MGTransform {
        let p = c.position, f = (c.targetVector - p).normalized
        var x = f.cross(c.up)
        if x.length < 1e-9 { x = f.cross(MGVec3(0, 0, -1)) }
        x = x.normalized
        let y = x.cross(f).normalized
        return MGTransform(c0: x, c1: y, c2: f * -1, translation: p)
    }

    /// The node transform of a directional light shining along `direction` (world): local −Z along it.
    static func lightTransform(_ direction: [Double]) -> MGTransform {
        let d = MGVec3(direction[0], direction[1], direction[2]).normalized
        var x = d.cross(MGVec3(0, 1, 0))
        if x.length < 1e-9 { x = d.cross(MGVec3(0, 0, -1)) }
        x = x.normalized
        let y = x.cross(d).normalized
        return MGTransform(c0: x, c1: y, c2: d * -1, translation: .zero)
    }

    /// sRGB-encoded component to linear light (glTF colour factors are linear).
    static func linear(_ c: Double) -> Double {
        let x = min(max(c, 0), 1)
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
}

// MARK: Ordered JSON

/// JSON with ordered object keys and fixed number spelling (Swift's shortest round-trip form), so output bytes are
/// deterministic.
indirect enum GLTFJSON {
    case int(Int), double(Double), float(Float), string(String), bool(Bool), array([GLTFJSON]), object([(String, GLTFJSON)])

    static func floats(_ v: [Float]) -> GLTFJSON { .array(v.map { .float($0) }) }
    static func doubles(_ v: [Double]) -> GLTFJSON { .array(v.map { .double($0) }) }

    func write(_ s: inout String) {
        switch self {
        case .int(let i): s += String(i)
        case .double(let d): s += d.isFinite ? (d == 0 ? "0.0" : "\(d)") : "0.0"
        case .float(let f): s += f.isFinite ? (f == 0 ? "0.0" : "\(f)") : "0.0"
        case .bool(let b): s += b ? "true" : "false"
        case .string(let t):
            s += "\""
            for u in t.unicodeScalars {
                switch u {
                case "\"": s += "\\\""
                case "\\": s += "\\\\"
                case "\n": s += "\\n"
                case "\r": s += "\\r"
                case "\t": s += "\\t"
                default:
                    if u.value < 0x20 { s += String(format: "\\u%04x", u.value) } else { s.unicodeScalars.append(u) }
                }
            }
            s += "\""
        case .array(let a):
            s += "["
            for (i, v) in a.enumerated() { if i > 0 { s += "," }; v.write(&s) }
            s += "]"
        case .object(let o):
            s += "{"
            for (i, kv) in o.enumerated() {
                if i > 0 { s += "," }
                GLTFJSON.string(kv.0).write(&s); s += ":"; kv.1.write(&s)
            }
            s += "}"
        }
    }
}

// MARK: Builder

extension MGSolidGLTF {
    /// One baked node track: translation (3 floats) and rotation (4 floats) per frame.
    struct Track {
        var translations: [Float] = []
        var rotations: [Float] = []
        var moving = false
    }

    struct Builder {
        let doc: MGSolidDocument
        let t: MGSolidGLTF.Timeline
        let stage = MGSolidStage.zUpToYUp
        let s = MGSolidGLTF.metresPerMillimetre

        var bin: [UInt8] = []
        var bufferViews: [GLTFJSON] = []
        var accessors: [GLTFJSON] = []
        var nodes: [GLTFJSON] = []
        var meshes: [GLTFJSON] = []
        var materials: [GLTFJSON] = []
        var materialIndex: [String: Int] = [:]
        var cameras: [GLTFJSON] = []
        var lights: [GLTFJSON] = []
        var samplers: [GLTFJSON] = []
        var channels: [GLTFJSON] = []
        var extensionsUsed = Set<String>()
        // Manifest records.
        var partRecords: [MGJSON] = []
        var cameraRecords: [MGJSON] = []
        var lightRecords: [MGJSON] = []
        var movingNodes = 0
        var triangles = 0

        init(_ doc: MGSolidDocument, timeline: MGSolidGLTF.Timeline) { self.doc = doc; self.t = timeline }

        // Binary chunk: every view starts on a 4-byte boundary (all components here are 4 bytes).
        mutating func addView<T>(_ values: [T], target: Int?) -> Int {
            while bin.count % 4 != 0 { bin.append(0) }
            let offset = bin.count
            values.withUnsafeBytes { bin.append(contentsOf: $0) }
            var o: [(String, GLTFJSON)] = [("buffer", .int(0)), ("byteOffset", .int(offset)), ("byteLength", .int(bin.count - offset))]
            if let target { o.append(("target", .int(target))) }
            bufferViews.append(.object(o))
            return bufferViews.count - 1
        }

        mutating func accessor(view: Int, componentType: Int, count: Int, type: String, min: GLTFJSON? = nil, max: GLTFJSON? = nil) -> Int {
            var o: [(String, GLTFJSON)] = [("bufferView", .int(view)), ("componentType", .int(componentType)), ("count", .int(count)),
                                           ("type", .string(type))]
            if let min { o.append(("min", min)) }
            if let max { o.append(("max", max)) }
            accessors.append(.object(o))
            return accessors.count - 1
        }

        mutating func floatAccessor(_ v: [Float], width: Int, type: String, target: Int?, bounds: Bool) -> Int {
            var lo: GLTFJSON?, hi: GLTFJSON?
            if bounds {
                var mn = [Float](repeating: .infinity, count: width), mx = [Float](repeating: -.infinity, count: width)
                for i in 0..<(v.count / width) {
                    for k in 0..<width { mn[k] = Swift.min(mn[k], v[i * width + k]); mx[k] = Swift.max(mx[k], v[i * width + k]) }
                }
                lo = .floats(mn); hi = .floats(mx)
            }
            return accessor(view: addView(v, target: target), componentType: 5126, count: v.count / width, type: type, min: lo, max: hi)
        }

        func trs(_ m: MGTransform) -> (t: [Double], r: [Double]) {
            ([m.translation.x * s, m.translation.y * s, m.translation.z * s], MGSolidGLTF.quaternion(m))
        }

        /// Appends one frame to a track, keeping each rotation in the hemisphere of the frame before (no flips).
        func append(_ m: MGTransform, to track: inout Track) {
            var (tr, q) = trs(m)
            if track.rotations.count >= 4 {
                let n = track.rotations.count
                let prev = track.rotations[(n - 4)..<n].map(Double.init)
                if zip(prev, q).map(*).reduce(0, +) < 0 { q = q.map { -$0 } }
            }
            tr.forEach { track.translations.append(Float($0)) }
            q.forEach { track.rotations.append(Float($0)) }
        }

        func node(name: String, track: Track, extra: [(String, GLTFJSON)]) -> [(String, GLTFJSON)] {
            var o: [(String, GLTFJSON)] = [("name", .string(name))]
            o += extra
            o.append(("translation", .floats(Array(track.translations[0..<3]))))
            o.append(("rotation", .floats(Array(track.rotations[0..<4]))))
            return o
        }

        mutating func material(_ part: MGPart, _ pv: MGSolidPartView) -> (index: Int, name: String) {
            let p = part.material.parameters
            let emission = pv.emission.flatMap { $0.intensity > 0 ? $0 : nil }
            let alpha = min(max(p.opacity * pv.opacity, 0), 1)
            let key = part.material.id + (emission.map { "+" + $0.id } ?? "") + (alpha < 1 ? "@" + String(alpha) : "")
            if let i = materialIndex[key] { return (i, key) }
            let base = p.baseColor.map(MGSolidGLTF.linear) + [alpha]
            var o: [(String, GLTFJSON)] = [("name", .string(key)),
                                           ("pbrMetallicRoughness", .object([("baseColorFactor", .doubles(base)),
                                                                             ("metallicFactor", .double(min(max(p.metallic, 0), 1))),
                                                                             ("roughnessFactor", .double(min(max(p.roughness, 0), 1)))]))]
            var ext: [(String, GLTFJSON)] = []
            if p.clearcoat > 0 {
                ext.append(("KHR_materials_clearcoat", .object([("clearcoatFactor", .double(min(p.clearcoat, 1))),
                                                                 ("clearcoatRoughnessFactor", .double(min(max(p.clearcoatRoughness, 0), 1)))])))
            }
            if p.transmission > 0 {
                ext.append(("KHR_materials_ior", .object([("ior", .double(max(p.ior, 1)))])))
                ext.append(("KHR_materials_transmission", .object([("transmissionFactor", .double(min(p.transmission, 1)))])))
            }
            if let e = emission {
                o.append(("emissiveFactor", .doubles(e.color.map(MGSolidGLTF.linear))))
                ext.append(("KHR_materials_emissive_strength", .object([("emissiveStrength", .double(e.intensity))])))
            }
            if alpha < 1 { o.append(("alphaMode", .string("BLEND"))) }
            if !ext.isEmpty {
                ext.forEach { extensionsUsed.insert($0.0) }
                o.append(("extensions", .object(ext)))
            }
            materials.append(.object(o))
            materialIndex[key] = materials.count - 1
            return (materials.count - 1, key)
        }

        mutating func build() throws {
            let a = doc.assembly
            let plain = doc.view(step: nil)
            let frames = t.poses.count
            let index = Dictionary(a.parts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { x, _ in x })
            // Bake every part's local transform (parent frame; the stage for a top-level part) for every frame.
            var tracks = [Track](repeating: Track(), count: a.parts.count)
            for params in t.poses {
                let pose = a.pose(params)
                for (i, part) in a.parts.enumerated() {
                    let world = pose.world[part.id] ?? .identity
                    guard MGSolidGLTF.isRigid(world) else { throw MGSolidGLTF.Refusal("gltf.transform", part: part.id) }
                    let local = part.parent.map { (pose.world[$0] ?? .identity).inverse * world } ?? stage * world
                    append(local, to: &tracks[i])
                }
            }
            func moves(_ tr: Track) -> Bool {
                for k in 1..<max(frames, 1) {
                    for j in 0..<3 where tr.translations[3 * k + j] != tr.translations[j] { return true }
                    for j in 0..<4 where tr.rotations[4 * k + j] != tr.rotations[j] { return true }
                }
                return false
            }
            for i in tracks.indices { tracks[i].moving = moves(tracks[i]) }

            // Node 0 is the root (the document title); parts follow in assembly order, then cameras, then lights.
            let partBase = 1
            var children = [[Int]](repeating: [], count: a.parts.count)
            var top: [Int] = []
            for (i, part) in a.parts.enumerated() {
                if let p = part.parent, let j = index[p] { children[j].append(partBase + i) } else { top.append(partBase + i) }
            }
            nodes.append(.object([("name", .string(MGSolidGLTF.rootName)), ("children", .array(top.map { .int($0) })),
                                  ("extras", .object([("title", .string(doc.title))]))]))
            for (i, part) in a.parts.enumerated() {
                let pv = plain.part(part.id)
                var extra: [(String, GLTFJSON)] = []
                var meshIndex: Int?
                var partTriangles = 0
                var materialName: MGJSON = .null
                if !pv.hidden {
                    let rm = pv.cut?.renderMesh(creaseAngle: part.creaseAngle) ?? part.mesh.renderMesh(creaseAngle: part.creaseAngle)
                    if !rm.indices.isEmpty {
                        var pos = [Float](), nor = [Float]()
                        pos.reserveCapacity(rm.positions.count * 3); nor.reserveCapacity(rm.normals.count * 3)
                        for p in rm.positions { pos += [Float(p.x * s), Float(p.y * s), Float(p.z * s)] }
                        for n in rm.normals { nor += [Float(n.x), Float(n.y), Float(n.z)] }
                        let (mat, matName) = material(part, pv)
                        materialName = .string(matName)
                        let pa = floatAccessor(pos, width: 3, type: "VEC3", target: 34962, bounds: true)
                        let na = floatAccessor(nor, width: 3, type: "VEC3", target: 34962, bounds: false)
                        let ia = accessor(view: addView(rm.indices, target: 34963), componentType: 5125, count: rm.indices.count, type: "SCALAR")
                        meshes.append(.object([("name", .string(part.id)),
                                               ("primitives", .array([.object([("attributes", .object([("POSITION", .int(pa)), ("NORMAL", .int(na))])),
                                                                                ("indices", .int(ia)), ("material", .int(mat)), ("mode", .int(4))])]))]))
                        meshIndex = meshes.count - 1
                        partTriangles = rm.indices.count / 3
                        triangles += partTriangles
                    }
                }
                if !children[i].isEmpty { extra.append(("children", .array(children[i].map { .int($0) }))) }
                if let meshIndex { extra.append(("mesh", .int(meshIndex))) }
                var x: [(String, GLTFJSON)] = [("martygraphicsId", .string(part.id)), ("partName", .string(part.name))]
                if pv.hidden { x.append(("hidden", .bool(true))) }
                extra.append(("extras", .object(x)))
                nodes.append(.object(node(name: part.id, track: tracks[i], extra: extra)))
                // `name` is the node name (the part id). `material` stays free for the render path's look-dev override
                // ({preset, baseColor}); the exported glTF material is `gltfMaterial`.
                partRecords.append(.object(["name": .string(part.id), "label": .string(part.name), "node": .number(Double(partBase + i)),
                                            "parent": part.parent.map(MGJSON.string) ?? .null, "moving": .bool(tracks[i].moving),
                                            "hidden": .bool(pv.hidden), "triangles": .number(Double(partTriangles)),
                                            "gltfMaterial": materialName]))
            }

            // Cameras: the animated camera first (if any), then the stills.
            let stillNames = t.stills.map(\.name)
            guard Set(stillNames).count == stillNames.count, !stillNames.contains(t.cameraName) || t.cameras.isEmpty else {
                throw MGSolidGLTF.Refusal("gltf.nodeName", part: t.cameraName)
            }
            var cameraTracks: [(name: String, track: Track, fov: Double, animated: Bool)] = []
            if !t.cameras.isEmpty {
                var tr = Track()
                for c in t.cameras { append(MGSolidGLTF.cameraTransform(c), to: &tr) }
                tr.moving = moves(tr)
                cameraTracks.append((t.cameraName, tr, t.cameras[0].fieldOfView, tr.moving))
            }
            for still in t.stills {
                var tr = Track()
                append(MGSolidGLTF.cameraTransform(still.camera), to: &tr)
                cameraTracks.append((still.name, tr, still.camera.fieldOfView, false))
            }
            for (k, c) in cameraTracks.enumerated() {
                cameras.append(.object([("name", .string(c.name)), ("type", .string("perspective")),
                                        ("perspective", .object([("aspectRatio", .double(t.aspect)), ("yfov", .double(c.fov * .pi / 180)),
                                                                 ("zfar", .double(1000)), ("znear", .double(0.01))]))]))
                nodes.append(.object(node(name: "camera." + c.name, track: c.track, extra: [("camera", .int(k))])))
                cameraRecords.append(.object(["name": .string("camera." + c.name), "node": .number(Double(nodes.count - 1)), "animated": .bool(c.animated),
                                              "fieldOfViewDegrees": .number(c.fov), "aspect": .number(t.aspect)]))
            }

            // The studio's directional lights (KHR_lights_punctual), fixed in the world.
            let studio = MGStudioLighting.studio
            for (k, l) in studio.lights.enumerated() {
                var tr = Track()
                append(MGSolidGLTF.lightTransform(l.direction), to: &tr)
                let lux = l.intensity * MGSolidGLTF.luxPerStudioUnit
                lights.append(.object([("name", .string(l.name)), ("type", .string("directional")),
                                       ("color", .doubles(l.color.map(MGSolidGLTF.linear))), ("intensity", .double(lux))]))
                nodes.append(.object(node(name: "light." + l.name, track: tr,
                                          extra: [("extensions", .object([("KHR_lights_punctual", .object([("light", .int(k))]))]))])))
                lightRecords.append(.object(["name": .string(l.name), "node": .number(Double(nodes.count - 1)), "type": .string("directional"),
                                             "studioIntensity": .number(l.intensity), "lux": .number(lux), "castsShadow": .bool(l.castsShadow),
                                             "softnessDegrees": .number(l.softness)]))
            }
            if !lights.isEmpty { extensionsUsed.insert("KHR_lights_punctual") }

            // Node names: unique and at most `nodeNameLimit` bytes, as the render path requires.
            var seen = Set<String>()
            for n in nodes {
                guard case .object(let o) = n, case .string(let name)? = o.first?.1 else { continue }
                guard name.utf8.count <= MGSolidGLTF.nodeNameLimit, seen.insert(name).inserted else { throw MGSolidGLTF.Refusal("gltf.nodeName", part: name) }
            }

            // One animation: every moving node, one key per frame, linear interpolation (spherical for rotations).
            var animated: [(node: Int, track: Track)] = []
            for i in a.parts.indices where tracks[i].moving { animated.append((partBase + i, tracks[i])) }
            movingNodes = animated.count
            if let cam = cameraTracks.first, cam.animated { animated.append((partBase + a.parts.count, cam.track)) }
            // The render path needs exactly one animation that spans every frame: a scene where nothing moves keys the
            // root node at its rest transform on every frame.
            if animated.isEmpty {
                var rest = Track()
                for _ in 0..<frames { append(.identity, to: &rest) }
                animated.append((0, rest))
            }
            do {
                let times = (0..<frames).map { Float(Double($0) / Double(t.fps)) }
                let input = floatAccessor(times, width: 1, type: "SCALAR", target: nil, bounds: true)
                for (nodeIndex, tr) in animated {
                    for (path, values, type) in [("translation", tr.translations, "VEC3"), ("rotation", tr.rotations, "VEC4")] {
                        let out = floatAccessor(values, width: type == "VEC3" ? 3 : 4, type: type, target: nil, bounds: false)
                        samplers.append(.object([("input", .int(input)), ("interpolation", .string("LINEAR")), ("output", .int(out))]))
                        channels.append(.object([("sampler", .int(samplers.count - 1)),
                                                 ("target", .object([("node", .int(nodeIndex)), ("path", .string(path))]))]))
                    }
                }
            }
        }

        func json() -> String {
            let sceneNodes = [0] + Array((1 + doc.assembly.parts.count)..<nodes.count)
            var o: [(String, GLTFJSON)] = [("asset", .object([("generator", .string("MartyGraphics glTF exporter (MartySolidGLTF)")),
                                                              ("version", .string("2.0"))]))]
            if !extensionsUsed.isEmpty { o.append(("extensionsUsed", .array(extensionsUsed.sorted().map { .string($0) }))) }
            o.append(("scene", .int(0)))
            o.append(("scenes", .array([.object([("name", .string(doc.title)), ("nodes", .array(sceneNodes.map { .int($0) }))])])))
            o.append(("nodes", .array(nodes)))
            if !meshes.isEmpty { o.append(("meshes", .array(meshes))) }
            if !materials.isEmpty { o.append(("materials", .array(materials))) }
            if !cameras.isEmpty { o.append(("cameras", .array(cameras))) }
            if !channels.isEmpty {
                o.append(("animations", .array([.object([("name", .string("martygraphics")), ("channels", .array(channels)),
                                                         ("samplers", .array(samplers))])])))
            }
            o.append(("accessors", .array(accessors)))
            o.append(("bufferViews", .array(bufferViews)))
            o.append(("buffers", .array([.object([("byteLength", .int((bin.count + 3) / 4 * 4))])])))
            if !lights.isEmpty { o.append(("extensions", .object([("KHR_lights_punctual", .object([("lights", .array(lights))]))]))) }
            var s = ""
            GLTFJSON.object(o).write(&s)
            return s
        }

        /// The GLB container: 12-byte header, the JSON chunk padded with spaces, the binary chunk padded with zeros.
        func glb() -> Data {
            var jsonBytes = Array(json().utf8)
            while jsonBytes.count % 4 != 0 { jsonBytes.append(0x20) }
            var binBytes = bin
            while binBytes.count % 4 != 0 { binBytes.append(0) }
            var out = [UInt8]()
            func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { out.append(contentsOf: $0) } }
            u32(0x4654_6C67); u32(2); u32(12 + 8 + jsonBytes.count + 8 + binBytes.count)
            u32(jsonBytes.count); u32(0x4E4F_534A); out += jsonBytes
            u32(binBytes.count); u32(0x004E_4942); out += binBytes
            return Data(out)
        }

        func manifest(_ c: MGSolidGLTF.Checked, sourceID: String, glbName: String, glbBytes: Int, sha256: String,
                      engineCommit: String, engine: MGJSON?) -> MGJSON {
            let l = MGStudioLighting.studio
            // The render path's fields (`format`, `engine.commit`, `scene.id`, `glb`, `fps`, `frameCount`, `parts[].name`,
            // `cameras[].name`) first; the rest is provenance it ignores.
            var e = engine?.objectValue ?? [:]
            e["name"] = .string(MGEngine.name)
            e["commit"] = .string(engineCommit)
            let o: [String: MGJSON] = [
                "format": .string(MGSolidGLTF.manifestFormat),
                "engine": .object(e),
                "scene": .object(["id": .string(sourceID), "title": .string(doc.title)]),
                "glb": .object(["file": .string(glbName), "bytes": .number(Double(glbBytes)), "sha256": .string(sha256)]),
                "fps": .number(Double(t.fps)), "frameCount": .number(Double(t.poses.count)), "seconds": .number(t.seconds),
                "parts": .array(partRecords), "cameras": .array(cameraRecords),
                "source": .object(["lines": .number(Double(c.source.lines)),
                                   "bytes": .number(Double(c.source.bytes)), "sha256": .string(c.source.sha256)]),
                "check": .object(["profile": .string("strict"), "ok": .bool(c.report.ok)]),
                "units": .string("metres"), "upAxis": .string("+Y"),
                "timeline": .string(t.about),
                "movingParts": .number(Double(movingNodes)), "triangles": .number(Double(triangles)),
                "lights": .array(lightRecords),
                "environment": .object(["note": .string("Not in the .glb (glTF has no portable environment light); the studio values, sRGB."),
                                        "background": .array(l.background.map(MGJSON.number)),
                                        "zenith": .array(l.environment.zenith.map(MGJSON.number)),
                                        "horizon": .array(l.environment.horizon.map(MGJSON.number)),
                                        "floor": .array(l.environment.floor.map(MGJSON.number)),
                                        "intensity": .number(l.environment.intensity)]),
                "limits": .array([.string("No textures, labels, arrows, dimensions, captions or section cuts of steps: the plain scene only."),
                                  .string("Materials are simple PBR factors (base colour, metallic, roughness, clear coat, transmission, emission)."),
                                  .string("Motion is baked per frame (linear keys); there are no joints, drives or constraints in the file.")]),
                "note": .string("A render of this file is cosmetic. The proof stays in MartyGraphics: the strict check report of the source."),
            ]
            return .object(o)
        }
    }
}
