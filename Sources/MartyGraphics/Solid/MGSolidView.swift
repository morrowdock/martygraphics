// SPDX-License-Identifier: Apache-2.0
import Foundation

// What a renderer shows for one step of a compiled solid document: capped section cuts (step `section`), see-through
// parts (step `ghost`, part `opacity`) and part light (`emissive`). Sections are cut once when the document compiles,
// counted exactly against the mesh budget before any cut triangle is built. Foundation only, deterministic.

/// v2 step `section`: a capped plane cut of the listed parts.
public struct MGSolidStepSection: Equatable, Sendable {
    /// Plane in assembly coordinates (kernel frame: Z up, mm) at the document's default input with explode 0.
    /// Points with `normal · p > offset` are cut away.
    public internal(set) var plane: MGSectionPlane
    /// Cut parts (resolved ids: a `repeat` base lists every copy), in the authored order.
    public internal(set) var parts: [String]
    /// Each part's capped cut, in its own frame. The cut moves with its part, like a physical cutaway model.
    public internal(set) var cuts: [String: MGSectionCut] = [:]

    public init(plane: MGSectionPlane, parts: [String]) { self.plane = plane; self.parts = parts }
}

/// How one part looks in a view.
public struct MGSolidPartView: Equatable, Sendable {
    /// The capped cut to show instead of the part's mesh, if the step cuts it.
    public var cut: MGSectionCut?
    /// Coverage 0.1...1 (1 = opaque); renderers multiply it with the material's own opacity.
    public var opacity: Double
    public var emission: MGEmission?
    /// v2: the view does not draw the part (step `hide`, or a show-only part the step does not `show`). A hidden part
    /// is not framed, hides no other part and makes no claim.
    public var hidden: Bool = false
}

/// Per-part appearance for one step (or for the plain scene).
public struct MGSolidView: Equatable, Sendable {
    /// Opacity of a part listed in a step's `ghost`.
    public static let ghostOpacity = 0.2
    /// Allowed part `opacity`. Below 0.1 a part would be invisible but still claim to be there.
    public static let opacityRange: ClosedRange<Double> = 0.1...1

    public internal(set) var parts: [String: MGSolidPartView]
    /// The step's section, if any.
    public internal(set) var section: MGSolidStepSection?
    /// v2: ids of the annotations this view shows (`MGSolidDocument.visibleAnnotations(step:)`), in authored or
    /// `annotate` order. Empty for a plain assembly.
    public internal(set) var annotations: [String] = []
    /// +1, or −1 for a step with a negative `spin` (it plays the input backwards): motion arrows draw the motion the
    /// view shows.
    public internal(set) var motionSense: Double = 1
    /// The step this view shows (nil: the plain view). Only a view from `MGSolidDocument.view(step:)` has poses the
    /// engine checked (`MGSolidDocument.checkedAnnotations(_:params:)`).
    public internal(set) var step: Int?
    /// The fingerprint of the compiled document this view came from (nil for a view built by a host).
    public internal(set) var fingerprint: String?
    /// The force and flow arrows a framed still does not draw because that still's camera cannot see the unit their
    /// tail rides on (`MGSolidFraming.arrowDrops`, docs/SOLID-3D.md "Arrow drop"). Only the framing
    /// sets it (`MGSolidClearView.view(_:)`); `MGSolidDocument.checkedAnnotations` leaves these arrows out.
    public internal(set) var arrowDrops: [MGArrowDrop] = []

    /// The view of a plain assembly: every part with its own opacity and light, nothing cut.
    public init(_ assembly: MGAssembly) {
        parts = Dictionary(assembly.parts.map { ($0.id, MGSolidPartView(cut: nil, opacity: $0.opacity, emission: $0.emission)) },
                           uniquingKeysWith: { a, _ in a })
        section = nil
    }

    /// Ids of the parts this view does not draw, sorted.
    public var hiddenParts: [String] { parts.keys.filter { parts[$0]!.hidden }.sorted() }

    /// One part's view with its numbers limited to the allowed ranges (opacity 0.1...1, NaN gives 1; light 0...4), so
    /// values set in code always give a valid snapshot and render. The parser refuses out-of-range authored values.
    public func part(_ id: String) -> MGSolidPartView {
        guard var v = parts[id] else { return MGSolidPartView(cut: nil, opacity: 1, emission: nil) }
        v.opacity = MGSolidView.clamp(opacity: v.opacity)
        v.emission = v.emission?.clamped
        return v
    }

    public static func clamp(opacity x: Double) -> Double {
        x.isNaN ? 1 : min(max(x, opacityRange.lowerBound), opacityRange.upperBound)
    }
}

extension MGSolidDocument {
    /// What step `step` (0-based) shows: its section cuts and ghosts over the parts' own opacity and light. `nil` (or
    /// an index outside the steps) gives the plain scene.
    public func view(step: Int?) -> MGSolidView {
        var v = MGSolidView(assembly)
        v.annotations = visibleAnnotations(step: step)
        v.fingerprint = checkedFingerprint
        for id in hiddenParts(step: step) { v.parts[id]?.hidden = true }
        guard let i = step, steps.indices.contains(i) else { return v }
        v.step = i
        let s = steps[i]
        if s.spin < 0 { v.motionSense = -1 }
        for id in s.ghost {
            let faint = min(v.part(id).opacity, MGSolidView.ghostOpacity)
            v.parts[id]?.opacity = faint
        }
        if let sec = s.section {
            v.section = sec
            for (id, cut) in sec.cuts { v.parts[id]?.cut = cut }
        }
        return v
    }
}

enum MGSolidSections {
    /// Most part triangles that all distinct cuts of one document may read (each distinct part and plane reads its
    /// part's mesh once). With `capWork` this bounds the compile time of many cuts of large parts (`section.budget`).
    /// Measured benchmarks, not a proven worst case (Apple M1, release): 0.65 s for seven face cuts of a 200-tooth
    /// gear, 1.08 s for one cut of eight 63-fin concentric revolves (docs/SOLID-3D.md, Sections).
    static let work = 400_000
    /// Most cap work units (loop points grouped, hole-to-outer visits and point-in-polygon points, bridge scans) that
    /// the pre-passes of all distinct cuts may charge; `section.budget`. Ordinary caps use a few points per point.
    static let capWork = 4_000_000

    /// Cuts every step section. Each listed part must be crossed by the plane: `section.miss.<id>` when nothing of it
    /// would be removed, `section.empty.<id>` when all of it would. The exact counts of every distinct cut join the
    /// document's mesh budget (`assembly.budget`) before any cut triangle is built. A cut whose part shape and local
    /// plane did not change is reused from `previous`.
    static func compile(_ steps: inout [MGSolidStep], _ assembly: MGAssembly, defaults: MGPoseParameters,
                        budget: (triangles: Int, vertices: Int), shapes: [String: [MGShapeSpec]], previous: MGSolidDocument?,
                        work: Int = MGSolidSections.work, capWork: Int = MGSolidSections.capWork) throws {
        guard steps.contains(where: { $0.section != nil }) else { return }
        let world = assembly.pose(MGPoseParameters(input: defaults.input, explode: 0)).world
        struct Key: Hashable { let part: String; let plane: MGSectionPlane }
        var planned: [Key] = []
        var seen = Set<Key>()
        var triangles = budget.triangles, vertices = budget.vertices, read = 0, capUsed = 0
        for s in steps {
            guard let sec = s.section else { continue }
            for id in sec.parts {
                guard let part = assembly.part(id) else { throw MGSolidIssue("ref.unknown.\(MGSolidParser.token(id))") }
                let local = sec.plane.local(world[id] ?? .identity)
                // A part and plane already checked (another step with the same section) gives the same result.
                let key = Key(part: id, plane: local)
                guard seen.insert(key).inserted else { continue }
                read += part.mesh.triangleCount
                guard read <= work else { throw MGSolidIssue("section.budget") }
                switch MGSolidSection.crossing(part.mesh, local) {
                case .misses: throw MGSolidIssue("section.miss.\(MGSolidParser.token(id))", part: id)
                case .removesAll: throw MGSolidIssue("section.empty.\(MGSolidParser.token(id))", part: id)
                case .cuts: break
                }
                let e: (triangles: Int, vertices: Int)
                do {
                    let r = try MGSolidSection.estimate(part.mesh, local, workLimit: capWork - capUsed)
                    e = (r.triangles, r.vertices); capUsed += r.work
                } catch let e as MGSolidIssue where e.reason == "section.budget" { throw e
                } catch let e as MGSolidIssue { throw MGSolidIssue("\(e.reason).\(MGSolidParser.token(id))", part: id) }
                triangles += e.triangles; vertices += e.vertices
                // Stop counting as soon as the budget is exceeded.
                if let b = MGSolidParser.budgetIssue(triangles, vertices) { throw b }
                planned.append(key)
            }
        }
        var old: [Key: MGSectionCut] = [:]
        if let prev = previous {
            for s in prev.steps { for (id, cut) in s.section?.cuts ?? [:] where prev.shapes[id] == shapes[id] { old[Key(part: id, plane: cut.plane)] = cut } }
        }
        var cuts: [Key: MGSectionCut] = [:]
        for key in planned {
            if let reused = old[key] { cuts[key] = reused; continue }
            let cut: MGSectionCut
            do { cut = try MGSolidSection.cut(assembly.part(key.part)!.mesh, key.plane) }
            catch let e as MGSolidIssue { throw MGSolidIssue("\(e.reason).\(MGSolidParser.token(key.part))", part: key.part) }
            // Safety net: a cut that fails the consistency check (closed, outward, caps without overlap) is refused.
            guard cut.isSound else { throw MGSolidIssue("section.open.\(MGSolidParser.token(key.part))", part: key.part) }
            cuts[key] = cut
        }
        for i in steps.indices {
            guard let sec = steps[i].section else { continue }
            for id in sec.parts { steps[i].section!.cuts[id] = cuts[Key(part: id, plane: sec.plane.local(world[id] ?? .identity))] }
        }
    }
}
