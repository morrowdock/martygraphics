// SPDX-License-Identifier: Apache-2.0
import Foundation

// Per-step pose (`pose`) and per-step visibility (`hide`, `show`) of assembly v2 steps (and explainer beat views, which
// compile to steps). A pose changes only placements: each posed step is checked against a compile of the whole
// document with that pose applied, and any change other than placements, or any change to a solved mechanism or an
// engine fact, is refused. Foundation only, deterministic: entries are read in sorted key order, parts in assembly order.

enum MGSolidPoses {
    /// Entries one `pose` may hold (`step.pose`).
    static let entries = MGSolidLimits.idsPerStep

    /// The authored `pose` object, checked for shape only: 1–16 entries; each entry an object with `with` (an object)
    /// and/or `rot` ([ax, ay, az, degrees], a non-zero axis, degrees in -360...360). Which ids take which key is checked
    /// against the document (`compile`). Reasons: `step.pose`, `step.pose.key`, `step.pose.with`.
    static func parse(_ v: MGJSON) throws -> [String: MGJSON] {
        guard case .object(let o) = v, (1...entries).contains(o.count) else { throw MGSolidIssue("step.pose") }
        for (id, e) in o.sorted(by: { $0.key < $1.key }) {
            guard case .object(let eo) = e, !eo.isEmpty, Set(eo.keys).isSubset(of: ["with", "rot"]) else {
                throw MGSolidIssue("step.pose.key", part: MGSolidParser.token(id))
            }
            if let w = eo["with"] { guard case .object(let wo) = w, !wo.isEmpty else { throw MGSolidIssue("step.pose.with", part: MGSolidParser.token(id)) } }
            if let r = eo["rot"] {
                // [axisX, axisY, axisZ, degrees]: the part `rot` rule (axis components in -1000...1000, not all zero).
                let bad = MGSolidIssue("step.pose.key", part: MGSolidParser.token(id))
                guard case .array(let a) = r, a.count == 4 else { throw bad }
                var v: [Double] = []
                for (k, x) in a.enumerated() {
                    guard case .number(let d) = x, d.isFinite, (k < 3 ? -1e3...1e3 : -360...360).contains(d) else { throw bad }
                    v.append(d)
                }
                guard MGVec3(v[0], v[1], v[2]).length > 1e-9 else { throw bad }
            }
        }
        return o
    }

    /// Compiles every step `pose` of `doc` (called once the assembly, its motion and its facts are compiled, before
    /// annotations and text). For each posed step:
    ///
    /// 1. The pose edits a copy of the authored source: a component instance id (a top-level `use` entry) takes `with`
    ///    (merged into the entry's own `with`); an authored part id takes `rot` (replacing its `rot`); a part inside an
    ///    instance (`pilot.upperArmL`, or an anchor that names it) takes `rot` through the entry's `set`. Anything else
    ///    is `step.pose.ref` (also a part named twice) or `step.pose.key` (a key the id does not take).
    /// 2. The copy (without steps and annotations) compiles with the same library, reusing unchanged meshes.
    /// 3. Only placements may differ: the same parts in the same order, with the same shapes, names, materials,
    ///    parents, joints, explode vectors and windows, opacity and light (`step.pose.with` otherwise).
    /// 4. No moved part (a part whose placement changed, and every part below it) may be in a gear solve or a constrained
    ///    mechanism: a gear pair or its carrier, a gear-mesh or crank drive or its source, a part held by a `fixed` or
    ///    `gearMesh` constraint or phased by the solver. And the compiled motion (drives, ratios, motion sources, gear
    ///    pairs), every engine fact and every drive tier must be unchanged (`step.pose.solved`). So the step's
    ///    captions and claims use facts that hold at the pose: they are the same facts.
    ///
    /// The step keeps the placements of the parts the pose moved (`MGSolidStep.pose`).
    static func compile(_ doc: inout MGSolidDocument, authored: [String: MGJSON]) throws {
        for i in doc.steps.indices {
            guard let raw = doc.steps[i].poseSource else { continue }
            doc.steps[i].pose = try placements(raw, doc, authored: authored)
        }
    }

    static func placements(_ raw: [String: MGJSON], _ doc: MGSolidDocument, authored: [String: MGJSON]) throws -> [String: MGTransform] {
        guard case .array(var list)? = authored["parts"] else { throw MGSolidIssue("step.pose.ref") }
        func entryIndex(_ id: String) -> Int? { list.firstIndex { $0["id"] == .string(id) } }
        let parts = Set(doc.assembly.parts.map(\.id))
        var named = Set<String>()
        var usesWith = false
        for (key, e) in raw.sorted(by: { $0.key < $1.key }) {
            let t = MGSolidParser.token(key)
            guard case .object(let fields) = e else { throw MGSolidIssue("step.pose.key", part: t) }
            if let k = entryIndex(key), case .object(var o) = list[k] {
                guard named.insert(key).inserted else { throw MGSolidIssue("step.pose.ref", part: t) }
                if o["use"] != nil {
                    // A component instance: `with` only.
                    guard fields["rot"] == nil, case .object(let w)? = fields["with"] else { throw MGSolidIssue("step.pose.key", part: t) }
                    guard case .object(var merged) = o["with"] ?? .object([:]) else { throw MGSolidIssue("step.pose.with", part: t) }
                    for (name, value) in w { merged[name] = value }
                    o["with"] = .object(merged)
                    usesWith = true
                } else {
                    // An authored part: `rot` only, and not a `repeat` copy (copies have no entry of their own).
                    guard fields["with"] == nil, let r = fields["rot"] else { throw MGSolidIssue("step.pose.key", part: t) }
                    o["rot"] = r
                }
                list[k] = .object(o)
                continue
            }
            // A part inside an instance, named directly or by an anchor.
            let resolved = doc.aliases[key] ?? key
            let head = String(resolved.prefix { $0 != "." })
            guard resolved.contains("."), parts.contains(resolved), doc.copies[resolved] == nil,
                  let k = entryIndex(head), case .object(var o) = list[k], o["use"] != nil else {
                throw MGSolidIssue("step.pose.ref", part: t)
            }
            guard named.insert(resolved).inserted else { throw MGSolidIssue("step.pose.ref", part: t) }
            guard fields["with"] == nil, let r = fields["rot"] else { throw MGSolidIssue("step.pose.key", part: t) }
            let inner = String(resolved.dropFirst(head.count + 1))
            guard case .object(var set) = o["set"] ?? .object([:]), case .object(var edit) = set[inner] ?? .object([:]) else {
                throw MGSolidIssue("step.pose.ref", part: t)
            }
            edit["rot"] = r
            set[inner] = .object(edit)
            o["set"] = .object(set)
            list[k] = .object(o)
        }
        var src = authored
        src["parts"] = .array(list)
        // Geometry only: steps, annotations and the title (whose placeholders may name annotation facts) stay out.
        src.removeValue(forKey: "steps")
        src.removeValue(forKey: "annotations")
        src.removeValue(forKey: "title")
        let posed: MGSolidDocument
        do { posed = try MGSolidParser.compile(.object(src), doc, doc.library) }
        catch let e as MGSolidIssue {
            // A constraint refusal (the mechanism no longer solves at the pose) is a solved value the pose changed.
            if e.reason.split(separator: ".").first == "constraint" { throw MGSolidIssue("step.pose.solved", part: e.part) }
            throw MGSolidIssue(usesWith ? "step.pose.with" : "step.pose.key", part: e.part)
        }
        catch { throw MGSolidIssue(usesWith ? "step.pose.with" : "step.pose.key") }
        let base = doc.assembly.parts, now = posed.assembly.parts
        guard base.count == now.count, zip(base, now).allSatisfy({ $0.id == $1.id }) else { throw MGSolidIssue("step.pose.with") }
        // Which parts moved: a changed placement, and every part below one.
        var direct: [String: MGTransform] = [:]
        for (a, b) in zip(base, now) where a.placement != b.placement { direct[a.id] = b.placement }
        let parent = Dictionary(base.map { ($0.id, $0.parent) }, uniquingKeysWith: { a, _ in a })
        func moved(_ id: String) -> Bool {
            var cur: String? = id
            for _ in 0...base.count {
                guard let c = cur else { return false }
                if direct[c] != nil { return true }
                cur = parent[c] ?? nil
            }
            return false
        }
        let mechanism = mechanismParts(doc)
        if let id = base.map(\.id).first(where: { moved($0) && mechanism.contains($0) }) { throw MGSolidIssue("step.pose.solved", part: id) }
        // Only placements may change.
        for (a, b) in zip(base, now) {
            var x = b
            x.placement = a.placement
            x.drive = a.drive
            guard x.name == a.name, x.material == a.material, x.parent == a.parent, x.joint == a.joint, x.explode == a.explode,
                  x.explodeWindow == a.explodeWindow, x.creaseAngle == a.creaseAngle, x.opacity == a.opacity, x.emission == a.emission,
                  posed.shapes[a.id] == doc.shapes[a.id] else { throw MGSolidIssue("step.pose.with", part: a.id) }
        }
        // The compiled motion and every engine fact stay exactly as they are.
        if let a = zip(base, now).first(where: { $0.0.drive != $0.1.drive }) { throw MGSolidIssue("step.pose.solved", part: a.0.id) }
        guard posed.ratios == doc.ratios, posed.motionSources == doc.motionSources, posed.assembly.gearPairs == doc.assembly.gearPairs,
              posed.driveTiers == doc.driveTiers, posed.facts == doc.facts else { throw MGSolidIssue("step.pose.solved") }
        return direct
    }

    /// Parts of a gear solve or a constrained mechanism, which a pose may not move: gear pair members and carriers, the
    /// parts and sources of gear-mesh and crank drives, and parts the solver holds (`fixed`, `gearMesh`, `phase`).
    static func mechanismParts(_ doc: MGSolidDocument) -> Set<String> {
        var out = Set<String>()
        for g in doc.assembly.gearPairs { out.insert(g.a); out.insert(g.b); if let c = g.carrier { out.insert(c) } }
        for p in doc.assembly.parts {
            switch p.drive {
            case .gear(let d, _, let c, _)?: out.insert(p.id); out.insert(d); if let c { out.insert(c) }
            case .crankSlider(let c, _, _, _)?, .crankRod(let c, _, _)?: out.insert(p.id); out.insert(c)
            default: break
            }
        }
        for (id, s) in doc.motionSources where ["gearMesh", "fixed", "phase"].contains(s) { out.insert(id) }
        return out
    }
}

/// Per-step `hide` and `show` (v2): which parts a view draws.
enum MGSolidStepVisibility {
    /// The show-only parts (every part some step lists in `show`, part order) after the list rules: a step may not list
    /// a part in both `hide` and `show` (`step.hide.both`), and may not focus, highlight, ghost or cut a part it hides (`step.hide.use`; a show-only part a step does not show counts as hidden there).
    static func check(_ steps: [MGSolidStep], order: [String]) throws -> [String] {
        let shown = Set(steps.flatMap(\.show))
        let showOnly = order.filter { shown.contains($0) }
        for s in steps {
            if let id = s.hide.first(where: { s.show.contains($0) }) { throw MGSolidIssue("step.hide.both", part: id) }
            let hidden = hiddenSet(s, showOnly: showOnly)
            let used = s.focus + s.highlight + s.ghost + (s.section?.parts ?? [])
            if let id = used.first(where: { hidden.contains($0) }) { throw MGSolidIssue("step.hide.use", part: id) }
        }
        return showOnly
    }

    static func hiddenSet(_ s: MGSolidStep?, showOnly: [String]) -> Set<String> {
        guard let s else { return Set(showOnly) }
        return Set(showOnly).subtracting(s.show).union(s.hide)
    }

    /// Hidden parts make no claim in a view. In each view (the plain view, then the steps):
    /// - no annotation the view shows is anchored on a part it hides (`step.hide.claim`; in the plain view, an
    ///   annotation on a show-only part: `step.show.claim`);
    /// - no fact the view displays belongs to a part it hides (`step.hide.fact`, `part` names the fact): the text of
    ///   every annotation it shows, and a step's caption and `check` claims.
    /// The title shows in every frame, so it may not show a fact of a part that any view hides (`step.hide.fact`).
    /// The facts of a part: `<part>.<name>`, a `repeat` base's shared facts and `count.<base>` (every copy),
    /// `<instance>.ratio` (the input and output anchor parts) and `dim.<id>` (the dimension's anchor parts).
    static func checkClaims(_ doc: MGSolidDocument) throws {
        guard !doc.showOnly.isEmpty || doc.steps.contains(where: { !$0.hide.isEmpty }) else { return }
        var everHidden = Set<String>()
        for step in [nil] + doc.steps.indices.map({ Optional($0) }) {
            let hidden = doc.hiddenParts(step: step)
            guard !hidden.isEmpty else { continue }
            everHidden.formUnion(hidden)
            let shown = doc.visibleAnnotations(step: step)
            for id in shown {
                if MGSolidAnnotationEngine.anchors(doc.annotations, id).contains(where: { $0.part.map(hidden.contains) ?? false }) {
                    throw MGSolidIssue(step == nil ? "step.show.claim" : "step.hide.claim", part: id)
                }
            }
            var names = doc.annotationTextFacts(shown)
            if let i = step { names += doc.stepFacts(i) }
            if let n = doc.firstFact(names, ownedBy: hidden) { throw MGSolidIssue("step.hide.fact", part: MGSolidParser.token(n)) }
        }
        if let n = doc.firstFact(doc.titleFacts, ownedBy: everHidden) { throw MGSolidIssue("step.hide.fact", part: MGSolidParser.token(n)) }
    }
}

extension MGSolidPoses {
    /// Every geometry fact a step displays holds over the step's whole motion domain at its pose: every input its
    /// `spin` plays, at its explode value and its placements (`MGSolidAnnotationEngine.dimensionHolds`, the rule shown
    /// dimensions already follow: constant during the view and equal to the measured value, or the exact `over` range).
    /// A `dim.<id>` fact that does not provably hold is `step.pose.fact` (`part` names the fact). Checked: the `check`
    /// claims of every step, and for a posed step also its caption, the title and the text of every annotation it shows
    /// (an unposed step's caption, title and annotation text keep their own reasons: `text.pose.step.<n>`,
    /// `text.pose.title`, `annotation.pose.<id>`). Every other fact is a joint or shape fact that the pose compile
    /// already proved unchanged (`step.pose.solved`).
    static func checkFacts(_ doc: MGSolidDocument) throws {
        for i in doc.steps.indices {
            let names = doc.steps[i].pose.isEmpty ? doc.checkFacts(i)
                : doc.stepFacts(i) + doc.titleFacts + doc.annotationTextFacts(doc.visibleAnnotations(step: i))
            if let n = doc.factNotHolding(step: i, names: names) { throw MGSolidIssue("step.pose.fact", part: MGSolidParser.token(n)) }
        }
    }
}

extension MGSolidDocument {
    /// Parts every view hides: the plain view and every step (empty when no view hides anything).
    var neverShownParts: Set<String> {
        guard !showOnly.isEmpty || steps.contains(where: { !$0.hide.isEmpty }) else { return [] }
        var out = hiddenParts(step: nil)
        for i in steps.indices where !out.isEmpty { out.formIntersection(hiddenParts(step: i)) }
        return out
    }

    /// The canonical facts step `i` displays: its caption's, then its `check` claims'.
    func stepFacts(_ i: Int) -> [String] { steps[i].facts + checkFacts(i) }

    /// The canonical facts of step `i`'s `check` claims.
    func checkFacts(_ i: Int) -> [String] { steps[i].checks.compactMap { MGSolidFacts.lookup($0.value, facts, aliases)?.name } }

    /// The canonical facts the text of these annotations displays (labels, arrows, dimensions), in the given order.
    func annotationTextFacts(_ ids: [String]) -> [String] {
        ids.flatMap { id -> [String] in annotations.label(id)?.facts ?? annotations.arrow(id)?.facts ?? annotations.dimension(id)?.facts ?? [] }
    }

    /// The first fact (in sorted order) that belongs to one of `parts` (`factParts`), or nil.
    func firstFact(_ names: [String], ownedBy parts: Set<String>) -> String? {
        guard !parts.isEmpty else { return nil }
        return Set(names).sorted().first { factParts($0).contains(where: parts.contains) }
    }

    /// The first `dim.<id>` fact (in sorted order) among `names` that does not hold over step `i`'s whole motion domain
    /// at its pose (`MGSolidAnnotationEngine.dimensionHolds`: with `spin`, its anchors must keep their relative place
    /// during the motion; its value at the step's placements, default input and explode value must equal the measured
    /// value within 1e-9 × max(1, |value|, model diagonal); with `over`, the exact range there), or nil.
    func factNotHolding(step i: Int, names: [String]) -> String? {
        guard steps.indices.contains(i) else { return nil }
        for n in Set(names).sorted() where n.hasPrefix("dim.") {
            guard let d = annotations.dimension(String(n.dropFirst(4))) else { continue }
            if !MGSolidAnnotationEngine.dimensionHolds(d, self, step: i) { return n }
        }
        return nil
    }

    /// The parts view `step` (0-based; nil for the plain view) does not draw: show-only parts it does not show, and the
    /// parts it hides. A hidden part is not drawn, not framed, never hides another part and makes no claim.
    public func hiddenParts(step: Int?) -> Set<String> {
        guard let i = step, steps.indices.contains(i) else { return Set(showOnly) }
        return MGSolidStepVisibility.hiddenSet(steps[i], showOnly: showOnly)
    }

    /// The pose step `step` shows with `spin` (0...1) of its spin played (`MGSolidStep.poseParameters`); the default
    /// pose for nil or an index outside the steps.
    public func poseParameters(step: Int?, spin: Double = 1) -> MGPoseParameters {
        guard let i = step, steps.indices.contains(i) else { return defaults }
        return steps[i].poseParameters(defaults: defaults, spin: spin)
    }

    /// The parts a fact belongs to (see `MGSolidStepVisibility.checkClaims`), in part order.
    func factParts(_ name: String) -> [String] {
        let ids = assembly.parts.map(\.id)
        if name.hasPrefix("dim."), let d = annotations.dimension(String(name.dropFirst(4))) {
            let on = Set([d.a, d.b, d.vertex].compactMap { $0?.part })
            return ids.filter { on.contains($0) }
        }
        if name.hasPrefix("count.") {
            let base = String(name.dropFirst(6))
            return ids.filter { copies[$0] == base }
        }
        if name.hasSuffix(".ratio") {
            let inst = String(name.dropLast(6))
            let on = Set([aliases[inst + ".input"], aliases[inst + ".output"]].compactMap { $0 })
            if !on.isEmpty { return ids.filter { on.contains($0) } }
        }
        guard let dot = name.lastIndex(of: ".") else { return [] }
        let owner = String(name[..<dot])
        if ids.contains(owner) { return [owner] }
        return ids.filter { copies[$0] == owner }
    }

    /// The read-back of every posed step: for each step with `pose`, `{"step" (1-based), "parts": [line]}` with one
    /// plain-words line per part the pose moved (its placement, or one above it, changed), in part order: world centre,
    /// size and local +Z direction at the default input with explode 0, as the step shows it. Empty without poses.
    public var poseReadBack: [(step: Int, lines: [String])] {
        steps.indices.compactMap { i -> (step: Int, lines: [String])? in
            let s = steps[i]
            guard !s.pose.isEmpty else { return nil }
            let w = assembly.pose(MGPoseParameters(input: 0, explode: 0, placements: s.pose)).world
            let base = assembly.pose(MGPoseParameters(input: 0, explode: 0)).world
            let lines = assembly.parts.compactMap { p -> String? in
                guard let t = w[p.id], t != base[p.id] else { return nil }
                let b = MGSolidFrames.vertexBounds(p.mesh, t)
                var line = "\(p.id): world centre \(MGSolidFrames.point(b.center)) mm, size \(MGSolidFrames.num(b.size.x)) x "
                    + "\(MGSolidFrames.num(b.size.y)) x \(MGSolidFrames.num(b.size.z)) mm; local +Z points \(MGSolidFrames.direction(t.applyVector(.unitZ)))"
                if let own = s.pose[p.id] {
                    line += "; posed placement at \(MGSolidFrames.list(own.translation)) in the \(p.parent ?? "world") frame"
                } else if let parent = p.parent {
                    line += "; moves with \(parent)"
                }
                return line
            }
            return (i + 1, lines)
        }
    }
}

extension MGSolidDocument {
    /// The size (a box diagonal, mm) that motion arrows (turn and line) take in a view: for a step with a `focus`, or
    /// else a `highlight` or `section`, the diagonal of those parts' posed box at the step's still pose, when it is at
    /// most `MGSolidFraming.focusShare` of the model's diagonal (`MGSolidAnnotations.diagonal`); otherwise, and for the
    /// plain view, the model's diagonal. Shaft radius, head and turn-arc radius (at least 1.15 × the part's widest
    /// radius) and the automatic line length scale with it, so a small spinning part seen close up keeps a small arrow.
    public func motionArrowDiagonal(step: Int?) -> Double {
        let model = annotations.diagonal
        guard let i = step, steps.indices.contains(i) else { return model }
        let s = steps[i]
        let core = Set(s.focus.isEmpty ? s.highlight + (s.section?.parts ?? []) : s.focus)
        guard !core.isEmpty else { return model }
        let pose = assembly.pose(poseParameters(step: i))
        var b = MGBounds.empty
        for p in assembly.parts where core.contains(p.id) { b = b.union(MGSolidFrames.worldBounds(p.mesh.bounds, pose.world[p.id] ?? .identity)) }
        let d = b.isEmpty ? 0 : b.size.length
        guard d.isFinite, d > 1e-6 * max(1, model), d <= MGSolidFraming.focusShare * model else { return model }
        return d
    }
}
