// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Hard limits for the scene DSL v1. Everything outside them is rejected, never clamped.
public enum MGLimits {
    public static let sceneBytes = 8 * 1024, patchBytes = 4 * 1024
    public static let items = 24, templateExtras = 10, resolvedItems = 40
    public static let steps = 8, stepEdits = 6,
    /// Walkthrough length a template may build locally (an algorithm needs one step per move); the wire limit stays `steps`.
    templateSteps = 48, showPerStep = 16, overrides = 16, hide = 16
    public static let label = 40, text = 120, say = 200, title = 60
    public static let points = 64, ropePoints = 6, cells = 16, cellText = 6, pointers = 4, bars = 6, barLabel = 16, nodeText = 8
    public static let worldRange: ClosedRange<Double> = 2...100
    static let bodyMoveTime: ClosedRange<Double> = 0.3...10
    /// Whole coils a `spring` may draw.
    static let springCoils: ClosedRange<Double> = 3...24
    /// Template record-list parameters: at most this many records of at most this many numeric fields. These bounds
    /// apply to the record-list shape only; no existing limit changes.
    public static let records = 32, recordFields = 6
    /// Raw (free-form JSON) template parameters: the canonical `params` object may be at most this many bytes.
    public static let rawParamsBytes = 4 * 1024
    /// Nesting limit (arrays and objects on one path; `[[1]]` is 2) of every JSON value a public entry point accepts:
    /// scenes (`scene.depth`), patches (`patch.depth`), raw template params (`template.params.depth`), lessons and
    /// snapshots (`MGLessonLimits`), Solid assemblies and components, and `MGJSON(any:)`. Real documents nest 6 to 15
    /// levels. The system JSON parser and encoder, Swift's `==`, hashing and freeing of nested values, and
    /// `MGJSON(any:)` all recurse once per level; at 64 levels the deepest of them (a sorted-key encode of nested
    /// objects) uses less than half of a 512 KiB thread stack (iOS secondary threads) and about a fifth of the 1 MiB iOS
    /// main-thread stack. The check is one walk that does not recurse, and it runs before any of them (on JSON `Data`:
    /// before the system parser; the `Data` must be UTF-8).
    public static let depth = 64
    /// `table` items: at most this many rows and columns, and this many characters per cell.
    public static let tableRows = 8, tableCols = 6, tableCellText = 12
    /// `func` and `field` expressions (`MGExpression`): at most this many Unicode scalars, tokens and nested
    /// parentheses, so one evaluation runs at most `exprTokens` operations. These bounds, like the others in this
    /// group, apply to the new kinds only; no existing limit changes.
    public static let exprLength = 80, exprTokens = 48, exprDepth = 8
    /// At most this many graph checks in one resolved scene (`items.expr`). Each `func` and `field` item counts once, and
    /// each step or `over` edit that targets one counts once more, because an edit checks the whole item again
    /// (`MGParser.apply`); a `curve` item, and each edit of it, counts `curveWeight`; a `func` item that computes
    /// readouts, and each such edit of it that can change one, counts `readoutWeight` (`MGParser.exprWeight`,
    /// `editWeight`). All are counted before any wire item is evaluated. A `func` check costs at most 7,169
    /// evaluations per checked instant (257 samples, 512 gap probes, 768 × 8 bisection steps, 256 midpoints); a moving
    /// one is checked at 4 instants plus 2 × 257 loop values (29,190). So one parse of a scene, its edits included, is at
    /// most 175,140 evaluations of at most 48 operations each, plus at most 3 readout computations (`readouts`); a
    /// typical smooth graph needs 513 per instant. A `field` costs 2 per arrow (≤ 384). A patch or a lesson command
    /// parses the whole scene again, with the same bound per parse. `MGTimeline.items` applies the step edits again, at
    /// most that bound. A controller keeps the items of the last 4 steps its views read (`MGTimelineCache`), and a 2D
    /// board reads its step from there at most once each time it is evaluated and draws every frame from those items
    /// (`MGSceneController.boardFrames`; with a learner slider moved it draws the slider's items and reads nothing), so
    /// a drawn frame does not apply the edits again and computes no readout, also after other views on the controller
    /// pushed the step out of the cache: readouts are computed once per cache fill. A slider move re-parses each `func`
    /// it drives once (`MGSliderState`), never per frame.
    public static let exprItems = 6
    /// A `func` is sampled on this many equal intervals (257 samples) and may break into at most `funcBreaks + 1` pieces.
    public static let funcIntervals = 256, funcBreaks = 16
    /// Farthest the drawn polyline may be from the function at an interval midpoint, as a fraction of the frame height
    /// (`MGGraph.curve`). A 12 × 8 world fitted to 1280 × 720 is 85.5 px per unit, so on a 4-unit-high graph 1 % is
    /// 3.4 px: about one stroke width (2.8 px).
    public static let funcTolerance = 0.01
    /// `a`, `b` and `c` parameters lie within ±`exprParameter`; a moving graph's `period` within `funcPeriod` seconds.
    public static let exprParameter = 1000.0
    public static let funcPeriod: ClosedRange<Double> = 0.5...20
    /// `field` grids: 2…`fieldCols` columns and 2…`fieldRows` rows of arrows.
    public static let fieldCols = 16, fieldRows = 12
    /// A `curve` (parametric x(θ), y(θ) or polar r(θ)) is sampled on this many equal steps of `theta` (257 points) and
    /// may break into at most `curveBreaks + 1` pieces. Each point needs two coordinates, so a curve costs at most
    /// 2 × 7,169 evaluations per checked instant and a moving one at most 2 × 29,190 = 58,380 (a polar curve needs half:
    /// one value of `r` and a native cosine and sine). It counts `curveWeight` times toward `exprItems`, and so does
    /// each step or `over` edit of it, which checks the whole curve again (`MGParser.exprWeight`, `editWeight`), so one
    /// parse of a scene, its edits included, stays within 6 × 29,190 = 175,140 evaluations (three moving parametric
    /// curves at most). These bounds, like the other graph bounds, apply to the new kind only. A curve computes no
    /// readouts (`curve.readouts`) and no slider drives it (`slider.curve`), so neither adds work to a curve.
    public static let curveIntervals = 256, curveBreaks = 16, curveWeight = 2
    /// Each end of a `theta` range lies within ±`curveEnd` (the parameter bound) and its span within `curveSpan`. The
    /// upper span is what 256 steps can draw: on a circle that fills the frame the chord at a step of Δ is
    /// (1 − cos(Δ/2)) × radius, which is within 1 % of the frame for Δ ≤ 0.4 rad, so 256 steps cover at most 102.4 rad;
    /// 100 rad is about 15.9 turns. The lower span keeps a gap probe (span / 262,144) above 10⁴ ulps of an end at 1,000.
    public static let curveEnd = 1000.0
    public static let curveSpan: ClosedRange<Double> = 0.001...100
    /// Farthest the drawn polyline may be from the curve at a step midpoint, as a fraction of the frame's shorter side
    /// (`MGGraph.planar`): 3.4 px on a 4-unit square frame of a 12 × 8 world fitted to 1280 × 720, as for `func`.
    public static let curveTolerance = 0.01
    /// Scene `sliders` (`MGSlider`): at most `sliders` sliders; each runs from `min` to `max` (both within
    /// ±`exprParameter`) in at most `sliderSteps` equal steps; and a scene has at most `sliderBindings` pairs of a slider
    /// and a `func` it drives. The parser checks each pair at the slider's `min` and `max` as well as its default, so a
    /// scene's parse runs at most 2 × `sliderBindings` = 12 extra `func` checks (at most 12 × 29,190 evaluations for
    /// moving graphs; typically 2 × 513). These bounds apply to the new key only; no existing limit changes.
    public static let sliders = 3, sliderSteps = 100, sliderBindings = 6
    /// `func` readouts (`MGReadout`, wire `readouts`): at most one of each of the 3 names, on a graph without a period.
    /// Their bounds are counts of their own operations, independent of the graph checks' evaluation bound: a parse
    /// computes readouts at most 3 times, and one computation is at most 258 interval passes (an area certifies the
    /// curve in at most `MGReadout.certifyBudget`, a slope runs two), 962 evaluations (the composite 5-point
    /// Gauss-Legendre rule on `readoutPanels` panels and on half as many, and the two ends) and 1 forward-mode pass (the
    /// slope). So a parse spends at most 774 interval passes, 2,886 evaluations and 3 forward-mode passes on readouts,
    /// besides its graph checks. A graph that computes them weighs `readoutWeight` graph checks, and so does each edit
    /// of it that can change one (a key in `MGReadout.inputKeys`); any other edit keeps the item's readouts, computes
    /// none and weighs 1. These bounds apply to the new key only.
    public static let readouts = 3, readoutPanels = 128
    /// Graph checks (`exprItems`) that a `func` item computing readouts weighs, and each step or `over` edit of it that
    /// can change a readout (`MGParser.editWeight`): one for its check and one for its readouts. The weight is what
    /// limits a parse to `readouts` (3) readout computations, each bounded by the operation counts above; an interval
    /// pass squares at most 54 times per whole power (`MGExpression.squaringLimit`). The 175,140-evaluation bound counts
    /// graph checks only, and still holds: a graph with readouts has no period, so its own check is at most 7,169
    /// evaluations. Measured, not a bound: on one machine (x86-64 Linux, AMD Ryzen 9 5900X, WSL2 Ubuntu 22.04, Swift
    /// 6.4.3 release build) an interval pass cost 4 to 34 evaluations of the same expression for the expressions
    /// measured, so one readout computation cost at most about a third of a check (29,190 evaluations) there
    /// (docs/PROTOCOL.md, "Readouts: slopes and areas").
    public static let readoutWeight = 2
}

public struct MGError: Error, Equatable, CustomStringConvertible {
    /// Developer reason for tests and logs only. Never shown to the learner.
    public let reason: String
    /// Repair detail of a length, count or size limit (explainer reasons; the check report's `limit`), else nil.
    public var limit: MGSolidLimitDetail?
    public init(_ reason: String) { self.reason = reason; limit = nil }
    /// A limit reason with its repair detail.
    public init(_ reason: String, limit: MGSolidLimitDetail?) { self.reason = reason; self.limit = limit }
    public var description: String { reason }
}

/// Context shared by item parsing, edits and patches.
struct MGContext {
    let width: Double, height: Double, is3D: Bool
    let values: [String: MGValue]
    /// Explainer documents only (internal): how `{…}` names with a dot or a modifier fill.
    var env: MGParseEnvironment? = nil
    var span: Double { max(width, height) }
}

/// Strict, fail-safe decoder for the scene DSL. Every object has a closed key set; numbers must be finite and in range;
/// text must be short plain text; ids must be unique and every reference must resolve. Any violation rejects the whole
/// scene (the caller keeps whatever it showed before).
public enum MGParser {
    public static func scene(data: Data, programmaticVideo: Bool) -> Result<MGScene, MGError> {
        guard programmaticVideo else { return scene(data: data) }
        guard data.count <= 65536 else { return .failure(MGError("video2d.budget.bytes")) }
        if let reason = MGJSON.dataRefusal(data, json: "json", depth: "scene.depth") { return .failure(MGError(reason)) }
        if let refusal = duplicateKeyRefusal(data) { return .failure(refusal) }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .failure(MGError("json")) }
        if (object as? [String: Any])?["layer2d"] == nil { return scene(data: data) }
        return scene(object: object, programmaticVideo: true)
    }

    public static func scene(object: Any, programmaticVideo: Bool) -> Result<MGScene, MGError> {
        guard programmaticVideo else { return scene(object: object) }
        guard let json = MGJSON(any: object) else { return .failure(MGError("json")) }
        return scene(json: json, programmaticVideo: true)
    }

    public static func scene(json: MGJSON, programmaticVideo: Bool) -> Result<MGScene, MGError> {
        guard programmaticVideo, case .object(let object) = json, object["layer2d"] != nil else { return scene(json: json) }
        do { return .success(try MGProgrammaticVideo.parse(json)) }
        catch let error as MGError { return .failure(error) }
        catch { return .failure(MGError("video2d.schema")) }
    }

    /// `scene.key.duplicate.<path>` when an object in the scene text repeats a key (`MGJSON.duplicateKeyPath`), else
    /// nil. Scene `Data` entry points check it after the UTF-8 and depth checks and before the system parser. The
    /// stream parser feeds the same scanner (`MGKeyScanner`) each chunk as it arrives and stops its previews at the
    /// first repeated key, so a preview never keeps a value the final parse refuses. `finish()` runs `scene(data:)`, so
    /// its reason follows the same order.
    static func duplicateKeyRefusal<S: Sequence>(_ bytes: S) -> MGError? where S.Element == UInt8 {
        guard let path = MGJSON.duplicateKeyPath(bytes) else { return nil }
        return MGError("scene.key.duplicate.\(path)")
    }

    static let topKeys: Set<String> = ["v", "template", "params", "title", "dim", "world", "items", "steps", "camera", "hide", "over", "alt", "sliders"]

    public static func scene(data: Data) -> Result<MGScene, MGError> {
        guard data.count <= MGLimits.sceneBytes * 2 else { return .failure(.init("json")) }
        // UTF-8 only, and the nesting counted before the recursive system parser. Then a repeated key, then the system
        // parser: `MGStreamParser.finish()` and `tools/scene_v1_check.py` give their reasons in this order too.
        if let r = MGJSON.dataRefusal(data, json: "json", depth: "scene.depth") { return .failure(.init(r)) }
        if let refusal = duplicateKeyRefusal(data) { return .failure(refusal) }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .failure(.init("json")) }
        return scene(object: object)
    }
    public static func scene(object: Any) -> Result<MGScene, MGError> {
        guard let json = MGJSON(any: object) else { return .failure(.init("json")) }
        return scene(json: json)
    }
    public static func scene(json: MGJSON) -> Result<MGScene, MGError> { scene(json: json, extraTemplates: []) }

    /// Parse with templates that are not registered yet, for example to check a pack before `MGPacks.register`.
    /// A registered template with the same name wins over an extra one. Extras are used for this call only; they are
    /// never registered. A scene that names an extra template keeps the template name, so a later patch on it must
    /// also go through `applying(_:extraTemplates:)` with the same extras (or the template must be registered).
    public static func scene(data: Data, extraTemplates: [MGTemplate]) -> Result<MGScene, MGError> {
        guard data.count <= MGLimits.sceneBytes * 2 else { return .failure(.init("json")) }
        // UTF-8 only, and the nesting counted before the recursive system parser.
        if let r = MGJSON.dataRefusal(data, json: "json", depth: "scene.depth") { return .failure(.init(r)) }
        if let refusal = duplicateKeyRefusal(data) { return .failure(refusal) }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return .failure(.init("json")) }
        return scene(object: object, extraTemplates: extraTemplates)
    }
    /// See `scene(data:extraTemplates:)`.
    public static func scene(object: Any, extraTemplates: [MGTemplate]) -> Result<MGScene, MGError> {
        guard let json = MGJSON(any: object) else { return .failure(.init("json")) }
        return scene(json: json, extraTemplates: extraTemplates)
    }
    /// See `scene(data:extraTemplates:)`.
    public static func scene(json: MGJSON, extraTemplates: [MGTemplate]) -> Result<MGScene, MGError> {
        scene(json: json, extraTemplates: extraTemplates, env: nil)
    }
    /// Internal: parse inside an explainer (`env` fills dotted and modified placeholders from 3D facts).
    static func scene(json: MGJSON, extraTemplates: [MGTemplate], env: MGParseEnvironment?) -> Result<MGScene, MGError> {
        do { return .success(try parseScene(json, extra: extraTemplates, env: env)) } catch let e as MGError { return .failure(e) } catch { return .failure(.init("unknown")) }
    }

    // MARK: scene

    static func parseScene(_ json: MGJSON, extra: [MGTemplate] = [], env: MGParseEnvironment? = nil) throws -> MGScene {
        guard case .object(let o) = json else { throw MGError("scene.object") }
        // A value built in code may hold NaN or an infinity, which has no JSON form, or nest deep enough to exhaust the
        // stack of a recursive walk; refuse both before measuring.
        try json.checkEntry(maxDepth: MGLimits.depth, maxBytes: MGLimits.sceneBytes, number: "scene.number", depth: "scene.depth", bytes: "scene.bytes")
        try closed(o, required: ["v"], optional: topKeys, "scene")
        guard o["v"] == .number(1) else { throw MGError("scene.version") }
        let is3D: Bool
        switch o["dim"] { case nil, .string("2d"): is3D = false; case .string("3d"): is3D = true; default: throw MGError("scene.dim") }

        var build: MGTemplateBuild?
        if let t = o["template"] {
            guard case .string(let name) = t, let template = MGTemplates.library[name] ?? extra.first(where: { $0.name == name }) else { throw MGError("template.unknown") }
            guard o["world"] == nil else { throw MGError("template.world") }
            guard let p = o["params"]?.objectValue else { throw MGError("template.params") }
            let params = try template.validate(p)
            // A template may throw; `build` keeps a well-formed `template.<suffix>` reason and reports anything else
            // as `template.build`.
            guard let built = try template.build(params, is3D) else { throw MGError("template.build") }
            build = built
        } else {
            for key in ["params", "hide", "over"] where o[key] != nil { throw MGError("scene.\(key).without.template") }
            guard o["items"] != nil else { throw MGError("scene.items.required") }
        }

        // Template output gets the same checks as wire input: world size, title, step count and every camera.
        if let b = build {
            guard MGLimits.worldRange.contains(b.width), MGLimits.worldRange.contains(b.height) else { throw MGError("template.world") }
            guard b.steps.count <= MGLimits.templateSteps else { throw MGError("template.steps") }
        }
        var width = build?.width ?? 12, height = build?.height ?? 8
        if let w = o["world"] {
            guard let wo = w.objectValue else { throw MGError("world") }
            try closed(wo, required: ["w", "h"], optional: [], "world")
            width = try num(wo["w"], MGLimits.worldRange, "world.w"); height = try num(wo["h"], MGLimits.worldRange, "world.h")
        }
        var ctx = MGContext(width: width, height: height, is3D: is3D, values: build?.values ?? [:], env: env)

        // Template output goes through the same item validator as model-written items (fail safe on template bugs too).
        var items = try (build?.items ?? []).map { try item(.object($0.wire()), ctx) }
        // Function graphs, vector fields and curves evaluate expressions; count them, and the edits that check one
        // again, before evaluating any wire item (`MGLimits.exprItems`). A curve, and a graph that computes readouts,
        // weigh more (`exprWeight`, `editWeight`).
        let templateGraphs = items.filter { graphKinds.contains($0.kind) }
        let readoutIDs = readoutGraphs(o, templateItems: templateGraphs, templateSteps: build?.steps ?? [])
        let curveIDs = curveGraphs(o, templateItems: templateGraphs)
        var graphs = templateGraphs.reduce(0) { $0 + exprWeight($1, readouts: readoutIDs) }
        let edits = graphEdits(o, templateGraphs: Set(templateGraphs.map(\.id)), templateSteps: build?.steps ?? []) {
            editWeight($0, key: $1, readouts: readoutIDs, curves: curveIDs)
        }
        if let raw = o["items"] {
            guard case .array(let list) = raw else { throw MGError("items") }
            let limit = build == nil ? MGLimits.items : MGLimits.templateExtras
            guard (build == nil ? 1 : 0)...limit ~= list.count else { throw MGError("items.count") }
            graphs += list.reduce(0) { $0 + exprWeight($1, readouts: readoutIDs) }
            guard graphs + edits <= MGLimits.exprItems else { throw MGError("items.expr") }
            // Readouts (docs/PROTOCOL.md, "Readouts: slopes and areas") are computed before any text is filled, so every
            // text of the scene can name them: each `func` item that lists them is checked first, without its texts,
            // and the rest of the scene is parsed with their values.
            var early: [Int: MGItem] = [:]
            for (k, entry) in list.enumerated() {
                guard let e = entry.objectValue, e["k"] == .string(MGKind.function.rawValue), e["readouts"] != nil else { continue }
                early[k] = try item(.object(e.filter { !MGReadout.textKeys.contains($0.key) }), ctx)
            }
            let readouts = MGReadout.values(list.indices.compactMap { early[$0] })
            if !readouts.isEmpty {
                ctx = MGContext(width: ctx.width, height: ctx.height, is3D: ctx.is3D,
                                values: ctx.values.merging(readouts) { old, _ in old }, env: ctx.env)
            }
            for (k, entry) in list.enumerated() {
                if let core = early[k], let e = entry.objectValue { items.append(try functionTexts(core, e, ctx)) } else { items.append(try item(entry, ctx)) }
            }
        }
        guard graphs + edits <= MGLimits.exprItems else { throw MGError("items.expr") }
        var ids = Set<String>()
        for i in items { guard ids.insert(i.id).inserted else { throw MGError("id.duplicate.\(i.id)") } }

        if let raw = o["hide"] {
            guard case .array(let list) = raw, list.count <= MGLimits.hide else { throw MGError("hide") }
            let templateIDs = Set(build?.items.map(\.id) ?? [])
            for entry in list {
                guard case .string(let id) = entry, templateIDs.contains(id) else { throw MGError("hide.ref") }
                items.removeAll { $0.id == id }; ids.remove(id)
            }
        }
        if let raw = o["over"] {
            guard case .array(let list) = raw, list.count <= MGLimits.overrides else { throw MGError("over") }
            let templateIDs = Set(build?.items.map(\.id) ?? [])
            for entry in list {
                let e = try edit(entry)
                guard templateIDs.contains(e.id) else { throw MGError("over.ref") }
                items = try apply(e, to: items, ctx)
            }
        }

        // Template walkthroughs skip anything the model hid (e.g. "hide the components").
        var steps = try (build?.steps ?? []).map { st -> MGStep in
            var st = st; st.say = try text(.string(st.say), MGLimits.say, ctx, "template.say", multiline: true)
            if let a = st.alt { st.alt = try text(.string(a), MGLimits.say, ctx, "template.alt") }
            if let c = st.camera { st.camera = try self.camera(c.wire(), ctx) }
            st.show = st.show.filter(ids.contains); if let f = st.focus, !ids.contains(f) { st.focus = nil }
            return st
        }
        if let raw = o["steps"] {
            guard case .array(let list) = raw, (1...MGLimits.steps).contains(list.count) else { throw MGError("steps") }
            steps = try list.map { try step($0, ctx) }
        }
        var title = try build.map { $0.title.isEmpty ? "" : try text(.string($0.title), MGLimits.title, ctx, "template.title") } ?? ""
        if let t = o["title"] { title = try text(t, MGLimits.title, ctx, "title") }
        // A text alternative for the whole board (docs/PROTOCOL.md, "Function graphs, vector fields and text alternatives").
        let alt = try o["alt"].map { try text($0, MGLimits.say, ctx, "alt") }
        let camera = try o["camera"].map { try self.camera($0, ctx) } ?? build?.camera.map { try self.camera($0.wire(), ctx) }

        guard items.count <= MGLimits.resolvedItems, !items.isEmpty else { throw MGError("items.total") }
        if is3D { for i in items where !MGKind.in3D.contains(i.kind) { throw MGError("3d.kind.\(i.kind.rawValue)") } }
        try checkReferences(items: items, steps: steps, ctx)
        // Learner sliders (docs/PROTOCOL.md, "Learner sliders"): after every item and step, because a slider binds to
        // the parsed `func` items and refuses step edits of the parameter it drives.
        let sliders = try o["sliders"].map { try self.sliders($0, items: items, steps: steps, ctx) } ?? []

        let motion = build.map { prune($0.motion, ids) } ?? .none
        try validateMotion(motion)
        let attachments = (build?.attachments ?? [:]).filter { ids.contains($0.key) && ids.contains($0.value) }
        var scene = MGScene(source: json, template: o["template"].flatMap { if case .string(let s) = $0 { return s }; return nil },
                            title: title, is3D: is3D, width: width, height: height, items: items, steps: steps, camera: camera,
                            values: ctx.values, motion: motion, attachments: attachments)
        scene.builtValues = (build?.builtValues ?? []).intersection(ctx.values.keys)
        scene.alt = alt
        scene.sliders = sliders
        return scene
    }

    /// The kinds that evaluate expressions: graph checks that `MGLimits.exprItems` bounds.
    static let graphKinds: Set<MGKind> = [.function, .field, .curve]

    /// A wire item entry of kind `func`, `field` or `curve` (read before the entry is validated).
    static func isGraphEntry(_ entry: MGJSON) -> Bool {
        guard case .string(let k)? = entry["k"], let kind = MGKind(rawValue: k) else { return false }
        return graphKinds.contains(kind)
    }

    /// The graph checks a wire item entry weighs (`MGLimits.exprItems`): 0 unless it is a graph entry,
    /// `MGLimits.curveWeight` for a `curve` entry (two coordinates per point), `MGLimits.readoutWeight` for a `func`
    /// entry that computes readouts (it lists `readouts`, or an edit gives it them: `readoutGraphs`), else 1.
    static func exprWeight(_ entry: MGJSON, readouts: Set<String>) -> Int {
        guard isGraphEntry(entry) else { return 0 }
        if entry["k"] == .string(MGKind.curve.rawValue) { return MGLimits.curveWeight }
        guard entry["k"] == .string(MGKind.function.rawValue) else { return 1 }
        if entry["readouts"] != nil { return MGLimits.readoutWeight }
        if case .string(let id)? = entry["id"], readouts.contains(id) { return MGLimits.readoutWeight }
        return 1
    }

    /// The graph checks a template item weighs (`MGLimits.exprItems`), as `exprWeight(_:readouts:)` weighs a wire
    /// entry: `MGLimits.curveWeight` for a `curve`, `MGLimits.readoutWeight` for a `func` that computes readouts
    /// (`readouts`), 1 for any other `func` or `field`, else 0.
    static func exprWeight(_ item: MGItem, readouts: Set<String>) -> Int {
        switch item.kind {
        case .curve: return MGLimits.curveWeight
        case .function: return readouts.contains(item.id) ? MGLimits.readoutWeight : 1
        case .field: return 1
        default: return 0
        }
    }

    /// The graph checks one edit of graph item `id` weighs (`MGLimits.exprItems`): `MGLimits.curveWeight` for a `curve`
    /// (`curves`, from `curveGraphs`; the edit checks the whole curve again); `MGLimits.readoutWeight` when the graph
    /// computes readouts (`readouts`, from `readoutGraphs`) and the edit can change one (its key is in
    /// `MGReadout.inputKeys`, or is not a string); else 1: an edit of any other key keeps the readouts
    /// (`MGReadout.kept`) and checks only the graph.
    static func editWeight(_ id: String, key: String?, readouts: Set<String>, curves: Set<String> = []) -> Int {
        if curves.contains(id) { return MGLimits.curveWeight }
        guard readouts.contains(id) else { return 1 }
        return key.map { MGReadout.inputKeys.contains($0) } ?? true ? MGLimits.readoutWeight : 1
    }

    /// The ids of the `func` items that may compute readouts: a template `func` item that requests them, a wire `func`
    /// entry that lists `readouts`, and a `func` item that a step or `over` edit gives `readouts` (the edits
    /// `graphEdits` counts). Read from the raw object before any wire item is evaluated, like `graphEdits`.
    static func readoutGraphs(_ o: [String: MGJSON], templateItems: [MGItem], templateSteps: [MGStep]) -> Set<String> {
        let templateFuncs = Set(templateItems.filter { $0.kind == .function }.map(\.id))
        var funcs = templateFuncs
        var out = Set(templateItems.filter { $0.kind == .function && !MGReadout.requested($0).isEmpty }.map(\.id))
        if case .array(let list)? = o["items"] {
            for entry in list where entry["k"] == .string(MGKind.function.rawValue) {
                guard case .string(let id)? = entry["id"] else { continue }
                funcs.insert(id)
                if entry["readouts"] != nil { out.insert(id) }
            }
        }
        // The `func` item an edit gives readouts, among `ids` (`over` names template items only).
        func gives(_ edit: MGJSON, _ ids: Set<String>) -> String? {
            guard case .string(let id)? = edit["id"], edit["key"] == .string("readouts"), ids.contains(id) else { return nil }
            return id
        }
        if case .array(let over)? = o["over"] { out.formUnion(over.compactMap { gives($0, templateFuncs) }) }
        if let raw = o["steps"] {
            if case .array(let steps) = raw {
                for step in steps { if case .array(let list)? = step["do"] { out.formUnion(list.compactMap { gives($0, funcs) }) } }
            }
        } else {
            for step in templateSteps { for e in step.edits where e.key == "readouts" && funcs.contains(e.id) { out.insert(e.id) } }
        }
        return out
    }

    /// The ids of the `curve` items: template `curve` items and wire `curve` entries, read from the raw object before
    /// any wire item is evaluated, like `readoutGraphs`. An edit never changes an item's kind (`edit.key`).
    static func curveGraphs(_ o: [String: MGJSON], templateItems: [MGItem]) -> Set<String> {
        var out = Set(templateItems.filter { $0.kind == .curve }.map(\.id))
        if case .array(let list)? = o["items"] {
            for entry in list where entry["k"] == .string(MGKind.curve.rawValue) {
                if case .string(let id)? = entry["id"] { out.insert(id) }
            }
        }
        return out
    }

    /// Edits that check a `func`, `field` or `curve` item again: wire step edits (or, without wire steps, the
    /// template's own step edits) that name a graph item, and `over` edits that name a template graph item (`over` may
    /// only name template items), each counted with its `weight` (the graph it names and its key, if a string; 1 unless
    /// the parse passes `editWeight`). Read from the raw object before any wire item is evaluated; a malformed entry is
    /// not counted here, the strict parse refuses it later. The scene is at most `MGLimits.sceneBytes`, so this walk is
    /// bounded.
    static func graphEdits(_ o: [String: MGJSON], templateGraphs: Set<String>, templateSteps: [MGStep],
                           weight: (_ id: String, _ key: String?) -> Int = { _, _ in 1 }) -> Int {
        var graphIDs = templateGraphs
        if case .array(let list)? = o["items"] {
            for entry in list where isGraphEntry(entry) { if case .string(let id)? = entry["id"] { graphIDs.insert(id) } }
        }
        func cost(_ edit: MGJSON, _ ids: Set<String>) -> Int {
            guard case .string(let id)? = edit["id"], ids.contains(id) else { return 0 }
            if case .string(let key)? = edit["key"] { return weight(id, key) }
            return weight(id, nil)
        }
        var count = 0
        if case .array(let over)? = o["over"] { count += over.reduce(0) { $0 + cost($1, templateGraphs) } }
        if let raw = o["steps"] {
            if case .array(let steps) = raw {
                for step in steps { if case .array(let list)? = step["do"] { count += list.reduce(0) { $0 + cost($1, graphIDs) } } }
            }
        } else {
            for step in templateSteps { count += step.edits.reduce(0) { $0 + (graphIDs.contains($1.id) ? weight($1.id, $1.key) : 0) } }
        }
        return count
    }

    /// The timeline uses the authored move duration bounds for active template motion as well.
    private static func validateMotion(_ motion: MGMotion) throws {
        let duration = MGLimits.bodyMoveTime
        let holdDuration = 0...duration.upperBound
        let valid: Bool
        switch motion {
        case .none:
            return
        case .slide(let entries, let travel, let hold):
            valid = duration.contains(travel) && holdDuration.contains(hold) && entries.allSatisfy {
                [$0.dir.x, $0.dir.y, $0.dir.z, $0.accel].allSatisfy(\.isFinite)
            }
        case .orbit(_, let center, let period, _):
            valid = duration.contains(period) && [center.x, center.y, center.z].allSatisfy(\.isFinite)
        case .projectile(_, let vx, let vy, let gravity, let flight, let visual, let hold, _, _, let scale):
            valid = duration.contains(visual) && holdDuration.contains(hold) && flight > 0
                && [vx, vy, gravity, flight, scale].allSatisfy(\.isFinite)
        case .oscillate(_, let amplitude, let period, let energy, _, _, let length):
            valid = duration.contains(period) && [amplitude, energy, length].allSatisfy(\.isFinite)
        }
        guard valid else { throw MGError("template.motion") }
    }

    /// Drop motion pieces for hidden items so the timeline never moves something that is not drawn.
    static func prune(_ motion: MGMotion, _ ids: Set<String>) -> MGMotion {
        switch motion {
        case .slide(let s, let travel, let hold):
            let kept = s.filter { ids.contains($0.id) }; return kept.isEmpty ? .none : .slide(kept, travel: travel, hold: hold)
        case .orbit(let id, let c, let p, let rotating):
            return ids.contains(id) ? .orbit(id: id, center: c, period: p, rotating: rotating.filter(ids.contains)) : .none
        case .projectile(let id, let vx, let vy, let g, let f, let v, let h, let a, let b, let s):
            return ids.contains(id) ? .projectile(id: id, vx: vx, vy0: vy, g: g, flight: f, visual: v, hold: h,
                                                   vxVector: a.flatMap { ids.contains($0) ? $0 : nil },
                                                   vyVector: b.flatMap { ids.contains($0) ? $0 : nil }, vectorScale: s) : .none
        case .oscillate(let id, let a, let p, let e, let bars, let v, let len):
            return ids.contains(id) ? .oscillate(id: id, amplitude: a, period: p, energy: e, bars: bars.flatMap { ids.contains($0) ? $0 : nil },
                                                  vector: v.flatMap { ids.contains($0) ? $0 : nil }, vectorLength: len) : .none
        case .none: return .none
        }
    }

    static func checkReferences(items: [MGItem], steps: [MGStep], _ ctx: MGContext) throws {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        try checkItemReferences(items)
        var current = items
        for s in steps {
            for id in s.show { guard byID[id] != nil else { throw MGError("step.show") } }
            if let f = s.focus { guard byID[f] != nil else { throw MGError("step.focus") } }
            for e in s.edits {
                current = try apply(e, to: current, ctx)
                try MGReadout.checkEdit(e.id, current, ctx.values)
                try checkItemReferences(current)
            }
        }
    }

    /// Validate the reference graph both initially and after each cumulative step edit.
    static func checkItemReferences(_ items: [MGItem]) throws {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for i in items {
            switch i.kind {
            case .vector: if let on = i.ref { guard byID[on]?.kind == .body || byID[on]?.kind == .node else { throw MGError("vector.on") } }
            case .highlight: guard let t = i.ref, byID[t] != nil, t != i.id else { throw MGError("highlight.target") }
            case .edge: guard byID[i.ref ?? ""]?.kind == .node, byID[i.ref2 ?? ""]?.kind == .node else { throw MGError("edge.nodes") }
            default: break
            }
        }
        // Follow each highlight chain without recursion. A repeated id is a cycle;
        // valid chains terminate at a non-highlight item and remain supported.
        for item in items where item.kind == .highlight {
            var current = item
            var visited = Set<String>()
            while current.kind == .highlight {
                guard visited.insert(current.id).inserted else { throw MGError("highlight.cycle") }
                guard let target = current.ref, let next = byID[target] else { throw MGError("highlight.target") }
                current = next
            }
        }
    }

    // MARK: steps, camera, edits

    static func step(_ json: MGJSON, _ ctx: MGContext) throws -> MGStep {
        guard let o = json.objectValue else { throw MGError("step") }
        try closed(o, required: ["say"], optional: ["show", "focus", "cam", "do", "alt"], "step")
        var s = MGStep(say: try text(o["say"], MGLimits.say, ctx, "step.say", multiline: true))
        if let a = o["alt"] { s.alt = try text(a, MGLimits.say, ctx, "step.alt") }
        if let raw = o["show"] {
            guard case .array(let list) = raw, list.count <= MGLimits.showPerStep else { throw MGError("step.show") }
            s.show = try list.map { try identifier($0, "step.show") }
        }
        if let f = o["focus"] { s.focus = try identifier(f, "step.focus") }
        if let c = o["cam"] { s.camera = try camera(c, ctx) }
        if let raw = o["do"] {
            guard case .array(let list) = raw, (1...MGLimits.stepEdits).contains(list.count) else { throw MGError("step.do") }
            s.edits = try list.map(edit)
        }
        return s
    }

    static func camera(_ json: MGJSON, _ ctx: MGContext) throws -> MGCamera {
        guard let o = json.objectValue else { throw MGError("camera") }
        try closed(o, required: [], optional: ["x", "y", "zoom", "yaw", "pitch"], "camera")
        var c = MGCamera()
        if let x = o["x"] { c.x = try num(x, 0...ctx.width, "camera.x") }
        if let y = o["y"] { c.y = try num(y, 0...ctx.height, "camera.y") }
        if let z = o["zoom"] { c.zoom = try num(z, 0.5...4, "camera.zoom") }
        if let y = o["yaw"] { c.yaw = try num(y, -180...180, "camera.yaw") }
        if let p = o["pitch"] { c.pitch = try num(p, -89...89, "camera.pitch") }
        return c
    }

    static func edit(_ json: MGJSON) throws -> MGEdit {
        guard let o = json.objectValue else { throw MGError("edit") }
        try closed(o, required: ["id", "key", "value"], optional: [], "edit")
        let id = try identifier(o["id"]!, "edit.id")
        guard case .string(let key) = o["key"]!, key != "id", key != "k" else { throw MGError("edit.key") }
        return MGEdit(id: id, key: key, value: o["value"]!)
    }

    /// Re-encodes the item, changes one key and re-validates it with the same rules as the wire format. An edit of a
    /// `func` item that changes no readout input (`MGReadout.inputKeys`: its colour, labels, position or size) checks
    /// the item without its readouts and keeps their values, which `MGReadout.compute` would give again (`kept`).
    static func apply(_ e: MGEdit, to items: [MGItem], _ ctx: MGContext) throws -> [MGItem] {
        guard let index = items.firstIndex(where: { $0.id == e.id }) else { throw MGError("edit.ref") }
        var wire = items[index].wire()
        if items[index].kind == .curve, e.key == "readouts" { throw MGError("curve.readouts") }
        guard allowedKeys(items[index].kind).contains(e.key) else { throw MGError("edit.key.\(reasonKeys([e.key]))") }
        wire[e.key] = e.value
        // Changing one end of an either/or pair removes the other.
        if e.key == "on" { wire["from"] = nil }; if e.key == "from" && items[index].kind == .vector { wire["on"] = nil }
        var out = items
        if let kept = MGReadout.kept(items[index], editing: e.key) {
            wire["readouts"] = nil
            out[index] = MGReadout.restored(try item(.object(wire), ctx), kept)
        } else {
            out[index] = try item(.object(wire), ctx)
        }
        return out
    }

    // MARK: items

    static let common: Set<String> = ["id", "k", "color"]
    static func allowedKeys(_ kind: MGKind) -> Set<String> {
        let extra: Set<String>
        switch kind {
        case .body: extra = ["at", "shape", "size", "angle", "label", "move"]
        case .incline: extra = ["at", "base", "angle", "label"]
        case .line: extra = ["from", "to", "style"]
        case .vector: extra = ["from", "on", "angle", "dir", "len", "label", "dashed"]
        case .axes: extra = ["at", "w", "h", "xl", "yl"]
        case .plot: extra = ["at", "w", "h", "xr", "yr", "pts", "xl", "yl", "label"]
        case .spring: extra = ["from", "to", "coils", "label"]
        case .pulley: extra = ["at", "r"]
        case .rope: extra = ["pts"]
        case .orbit: extra = ["at", "r", "label"]
        case .text: extra = ["at", "text", "style"]
        case .highlight: extra = ["target", "label"]
        case .bars: extra = ["at", "w", "h", "bars", "unit", "label"]
        case .path: extra = ["pts", "dashed"]
        case .array: extra = ["at", "vals", "cell", "ptrs", "marked", "label"]
        case .node: extra = ["at", "text", "r"]
        case .edge: extra = ["a", "b", "dir", "label"]
        case .table: extra = ["at", "cells", "header", "cw", "rh", "marked", "label"]
        case .region: extra = ["pts", "dashed", "label"]
        case .function: extra = ["at", "w", "h", "xr", "yr", "y", "a", "b", "c", "period", "shade", "mark", "readouts", "xl", "yl", "label"]
        case .field: extra = ["at", "w", "h", "xr", "yr", "dx", "dy", "a", "b", "c", "n", "style", "xl", "yl", "label"]
        case .curve: extra = ["at", "w", "h", "xr", "yr", "x", "y", "r", "theta", "a", "b", "c", "period", "mark", "xl", "yl", "label"]
        }
        return common.union(extra)
    }
    static func required(_ kind: MGKind) -> Set<String> {
        switch kind {
        case .body: return ["at"]
        case .incline: return ["at", "base", "angle"]
        case .line, .spring: return ["from", "to"]
        case .vector: return ["len"]
        case .axes: return ["at", "w", "h"]
        case .plot: return ["at", "w", "h", "xr", "yr", "pts"]
        case .pulley, .orbit: return ["at", "r"]
        case .rope, .path: return ["pts"]
        case .text: return ["at", "text"]
        case .highlight: return ["target"]
        case .bars: return ["at", "w", "h", "bars"]
        case .array: return ["at", "vals"]
        case .node: return ["at", "text"]
        case .edge: return ["a", "b"]
        case .table: return ["at", "cells"]
        case .region: return ["pts"]
        case .function: return ["at", "w", "h", "xr", "yr", "y"]
        case .field: return ["at", "w", "h", "xr", "yr", "dx", "dy"]
        case .curve: return ["at", "w", "h", "xr", "yr"]
        }
    }
    static func defaultColor(_ kind: MGKind) -> MGColorRole {
        switch kind {
        case .body: return .blue
        case .vector: return .force
        case .spring: return .teal
        case .text, .axes, .line, .pulley, .rope, .edge: return .muted
        case .highlight: return .yellow
        case .plot, .path: return .accent
        case .orbit: return .purple
        case .bars: return .energy
        case .incline: return .muted
        case .array, .node: return .blue
        case .table, .region, .function, .curve: return .accent
        case .field: return .teal
        }
    }

    static func item(_ json: MGJSON, _ ctx: MGContext) throws -> MGItem {
        guard let o = json.objectValue, case .string(let k)? = o["k"], let kind = MGKind(rawValue: k) else { throw MGError("item.kind") }
        // Readouts are `func` numbers (MGReadout): a curve has no value, slope or area readout to fill a text with.
        if kind == .curve, o["readouts"] != nil { throw MGError("curve.readouts") }
        try closed(o, required: required(kind).union(["id", "k"]), optional: allowedKeys(kind), "item.\(k)")
        let id = try identifier(o["id"]!, "item.id")
        var color = defaultColor(kind)
        if let c = o["color"] { guard case .string(let s) = c, let role = MGColorRole(rawValue: s) else { throw MGError("item.color") }; color = role }
        var it = MGItem(id: id, kind: kind, color: color)
        if let l = o["label"] { it.label = try text(l, MGLimits.label, ctx, "item.label") }
        let span = ctx.span
        func p(_ key: String) throws -> MGPoint { try point(o[key], ctx, "\(k).\(key)") }
        func n(_ key: String, _ range: ClosedRange<Double>) throws -> Double { try num(o[key], range, "\(k).\(key)") }
        func opt(_ key: String, _ range: ClosedRange<Double>) throws -> Double? { try o[key].map { try num($0, range, "\(k).\(key)") } }
        func flag(_ key: String) throws -> Bool {
            guard let v = o[key] else { return false }; guard case .bool(let b) = v else { throw MGError("\(k).\(key)") }; return b
        }

        switch kind {
        case .body:
            it.pts = [try p("at")]
            switch o["shape"] { case nil, .string("box"): break; case .string("ball"): it.flags.insert("ball"); default: throw MGError("body.shape") }
            it.num["size"] = try opt("size", 0.1...(span / 2)) ?? 1
            it.num["angle"] = try opt("angle", -360...360) ?? 0
            if let m = o["move"] {
                guard let mo = m.objectValue else { throw MGError("body.move") }
                try closed(mo, required: ["to", "t"], optional: [], "body.move")
                it.pts.append(try point(mo["to"], ctx, "body.move.to"))
                it.num["moveT"] = try num(mo["t"], MGLimits.bodyMoveTime, "body.move.t")
            }
        case .incline:
            it.pts = [try p("at")]
            it.num["base"] = try n("base", 0.5...(ctx.width * 1.25)); it.num["angle"] = try n("angle", 0...80)
        case .line:
            it.pts = [try p("from"), try p("to")]
            switch o["style"] {
            case nil, .string("solid"): break
            case .string("dashed"): it.flags.insert("dashed")
            case .string("ground"): it.flags.insert("ground")
            default: throw MGError("line.style")
            }
        case .vector:
            switch (o["from"], o["on"]) {
            case (let f?, nil): it.pts = [try point(f, ctx, "vector.from")]
            case (nil, let on?): it.ref = try identifier(on, "vector.on")
            default: throw MGError("vector.anchor")
            }
            if let d = o["dir"] {
                guard ctx.is3D, o["angle"] == nil else { throw MGError("vector.dir") }
                let v = try vector3(d, "vector.dir"); it.dir = v; it.flags.insert("dir3")
            } else {
                it.num["angle"] = try n("angle", -360...360)
            }
            it.num["len"] = try n("len", 0...span)
            if try flag("dashed") { it.flags.insert("dashed") }
        case .axes:
            it.pts = [try p("at")]; it.num["w"] = try n("w", 0.5...(span * 1.25)); it.num["h"] = try n("h", 0.5...(span * 1.25))
            it.list = [try o["xl"].map { try text($0, MGLimits.label, ctx, "axes.xl") } ?? "", try o["yl"].map { try text($0, MGLimits.label, ctx, "axes.yl") } ?? ""]
        case .plot:
            it.pts = [try p("at")]; it.num["w"] = try n("w", 0.5...(span * 1.25)); it.num["h"] = try n("h", 0.5...(span * 1.25))
            let xr = try range(o["xr"], "plot.xr"), yr = try range(o["yr"], "plot.yr")
            it.num["x0"] = xr.0; it.num["x1"] = xr.1; it.num["y0"] = yr.0; it.num["y1"] = yr.1
            guard case .array(let list)? = o["pts"], (2...MGLimits.points).contains(list.count) else { throw MGError("plot.pts") }
            it.pts += try list.map { try dataPoint($0, "plot.pts") }
            it.list = [try o["xl"].map { try text($0, MGLimits.label, ctx, "plot.xl") } ?? "", try o["yl"].map { try text($0, MGLimits.label, ctx, "plot.yl") } ?? ""]
        case .spring:
            it.pts = [try p("from"), try p("to")]
            let coils = try opt("coils", MGLimits.springCoils) ?? 8
            guard coils.rounded() == coils else { throw MGError("spring.coils") }; it.num["coils"] = coils
        case .pulley:
            it.pts = [try p("at")]; it.num["r"] = try n("r", 0.05...(span / 4))
        case .rope, .path:
            let maximum = kind == .rope ? MGLimits.ropePoints : MGLimits.points
            guard case .array(let list)? = o["pts"], (2...maximum).contains(list.count) else { throw MGError("\(k).pts") }
            it.pts = try list.map { try point($0, ctx, "\(k).pts") }
            if kind == .path, try flag("dashed") { it.flags.insert("dashed") }
        case .orbit:
            it.pts = [try p("at")]; it.num["r"] = try n("r", 0.1...(span / 2))
        case .text:
            it.pts = [try p("at")]
            // Text is checked before style, as before `code` existed, so older invalid documents keep their reason.
            // `code` keeps leading spaces and allows comparison signs; markup-like tags stay refused.
            let isCode = o["style"] == .string("code")
            it.text = try text(o["text"], MGLimits.text, ctx, "text.text", code: isCode, multiline: true)
            switch o["style"] {
            case nil, .string("label"): break
            case .string("callout"): it.flags.insert("callout")
            case .string("title"): it.flags.insert("title")
            case .string("code"):
                // The 3D view draws text centred and proportional, so it cannot show a code listing faithfully.
                guard !ctx.is3D else { throw MGError("3d.text.code") }
                it.flags.insert("code")
            default: throw MGError("text.style")
            }
        case .highlight:
            it.ref = try identifier(o["target"]!, "highlight.target")
        case .bars:
            it.pts = [try p("at")]; it.num["w"] = try n("w", 0.5...(span * 1.25)); it.num["h"] = try n("h", 0.5...(span * 1.25))
            guard case .array(let list)? = o["bars"], (1...MGLimits.bars).contains(list.count) else { throw MGError("bars.bars") }
            it.bars = try list.map { b in
                guard let bo = b.objectValue else { throw MGError("bars.bar") }
                try closed(bo, required: ["label", "value"], optional: ["color"], "bars.bar")
                var role = MGColorRole.energy
                if let c = bo["color"] { guard case .string(let s) = c, let r = MGColorRole(rawValue: s) else { throw MGError("bars.color") }; role = r }
                return MGBar(label: try text(bo["label"], MGLimits.barLabel, ctx, "bars.label"), value: try num(bo["value"], -1e7...1e7, "bars.value"), color: role)
            }
            if let u = o["unit"] { it.text = try text(u, 8, ctx, "bars.unit") }
        case .array:
            it.pts = [try p("at")]
            guard case .array(let list)? = o["vals"], (1...MGLimits.cells).contains(list.count) else { throw MGError("array.vals") }
            it.list = try list.map { v in
                switch v {
                case .number(let d):
                    // A number is stored as its displayed text, so that text obeys the string-cell limit too; otherwise a
                    // value like -123456 would parse once and then fail every step edit or patch of the array.
                    guard abs(d) < 1e6 else { throw MGError("array.val") }
                    let shown = MGPhysics.format(d, unit: "")
                    guard shown.unicodeScalars.count <= MGLimits.cellText else { throw MGError("array.val") }
                    return shown
                case .string: return try text(v, MGLimits.cellText, ctx, "array.val")
                default: throw MGError("array.val")
                }
            }
            // The default is capped to the accepted range so the wire form of a defaulted cell re-parses in small worlds.
            it.num["cell"] = try opt("cell", 0.3...(span / 4)) ?? min(1, span / 4)
            if let raw = o["ptrs"] {
                guard case .array(let ps) = raw, ps.count <= MGLimits.pointers else { throw MGError("array.ptrs") }
                it.pointers = try ps.map { pv in
                    guard let po = pv.objectValue else { throw MGError("array.ptr") }
                    try closed(po, required: ["i", "label"], optional: [], "array.ptr")
                    let i = try num(po["i"], 0...Double(list.count - 1), "array.ptr.i")
                    guard i.rounded() == i else { throw MGError("array.ptr.i") }
                    return MGPointer(index: i, label: try text(po["label"], MGLimits.nodeText, ctx, "array.ptr.label"))
                }
            }
            if let raw = o["marked"] {
                guard case .array(let ms) = raw, ms.count <= MGLimits.cells else { throw MGError("array.marked") }
                it.marked = try ms.map { m in
                    let i = try num(m, 0...Double(list.count - 1), "array.marked"); guard i.rounded() == i else { throw MGError("array.marked") }; return Int(i)
                }
            }
        case .node:
            it.pts = [try p("at")]; it.text = try text(o["text"], MGLimits.nodeText, ctx, "node.text")
            // The default is capped to the accepted range so the wire form of a defaulted node re-parses in small worlds.
            it.num["r"] = try opt("r", 0.2...(span / 6)) ?? min(0.5, span / 6)
        case .edge:
            it.ref = try identifier(o["a"]!, "edge.a"); it.ref2 = try identifier(o["b"]!, "edge.b")
            guard it.ref != it.ref2 else { throw MGError("edge.self") }
            if try flag("dir") { it.flags.insert("dir") }
        case .table:
            it.pts = [try p("at")]
            guard case .array(let rows)? = o["cells"], (1...MGLimits.tableRows).contains(rows.count) else { throw MGError("table.cells") }
            var cols = 0
            for row in rows {
                guard case .array(let cells) = row, (1...MGLimits.tableCols).contains(cells.count), cols == 0 || cells.count == cols else {
                    throw MGError("table.cells")
                }
                cols = cells.count
                for v in cells {
                    switch v {
                    case .number(let d):
                        // A number is stored as its displayed text, so that text obeys the string-cell limit too.
                        guard abs(d) < 1e6 else { throw MGError("table.cell") }
                        let shown = MGPhysics.format(d, unit: "")
                        guard shown.unicodeScalars.count <= MGLimits.tableCellText else { throw MGError("table.cell") }
                        it.list.append(shown)
                    case .string(let s) where s.isEmpty: it.list.append("")
                    case .string: it.list.append(try text(v, MGLimits.tableCellText, ctx, "table.cell"))
                    default: throw MGError("table.cell")
                    }
                }
            }
            it.num["rows"] = Double(rows.count); it.num["cols"] = Double(cols)
            // Defaults are capped to the accepted range so the wire form of a defaulted table re-parses in small worlds.
            it.num["cw"] = try opt("cw", 0.3...(span / 3)) ?? min(1.6, span / 3)
            it.num["rh"] = try opt("rh", 0.3...(span / 6)) ?? min(0.7, span / 6)
            if try flag("header") { it.flags.insert("header") }
            if let raw = o["marked"] {
                guard case .array(let ms) = raw, ms.count <= rows.count * cols else { throw MGError("table.marked") }
                it.marked = try ms.map { m in
                    guard case .array(let rc) = m, rc.count == 2 else { throw MGError("table.marked") }
                    let r = try num(rc[0], 0...Double(rows.count - 1), "table.marked"), c = try num(rc[1], 0...Double(cols - 1), "table.marked")
                    guard r.rounded() == r, c.rounded() == c else { throw MGError("table.marked") }
                    return Int(r) * cols + Int(c)
                }
            }
        case .region:
            guard case .array(let points)? = o["pts"], (3...MGLimits.points).contains(points.count) else { throw MGError("region.pts") }
            it.pts = try points.map { try point($0, ctx, "region.pts") }
            if try flag("dashed") { it.flags.insert("dashed") }
        case .function:
            // A graph of y = f(x) that the engine samples and checks (MGGraph.checkFunction); the model writes no points.
            it.pts = [try p("at")]
            it.num["w"] = try n("w", 0.5...(span * 1.25)); it.num["h"] = try n("h", 0.5...(span * 1.25))
            let xr = try graphRange(o["xr"], "func.xr"), yr = try graphRange(o["yr"], "func.yr")
            it.num["x0"] = xr.0; it.num["x1"] = xr.1; it.num["y0"] = yr.0; it.num["y1"] = yr.1
            var allowed = try graphParameters(&it, o, k)
            if let period = try opt("period", MGLimits.funcPeriod) { it.num["period"] = period; allowed.insert(.t) }
            let expr = try expression(o["y"], allowed, "func.y")
            if it.num["period"] != nil, !expr.variables.contains(.t) { throw MGError("func.period") }
            it.text = expr.text
            if let raw = o["shade"] {
                guard case .array(let s) = raw, s.count == 2 else { throw MGError("func.shade") }
                let s0 = try num(s[0], xr.0...xr.1, "func.shade"), s1 = try num(s[1], xr.0...xr.1, "func.shade")
                guard s0 < s1 else { throw MGError("func.shade") }
                it.num["s0"] = s0; it.num["s1"] = s1
            }
            if let m = try opt("mark", xr.0...xr.1) { it.num["mark"] = m }
            if let raw = o["readouts"] {
                let list = try MGReadout.parse(raw)
                try MGReadout.checkKeys(list, it)
                for r in list { it.flags.insert(r.key) }
            }
            try MGGraph.checkFunction(&it, expr)
            try MGReadout.compute(&it, expr)
            it.list = try functionLabels(o, ctx)
        case .field:
            // Arrows of (dx, dy) at the centres of a grid of cells, evaluated by the engine.
            it.pts = [try p("at")]
            it.num["w"] = try n("w", 0.5...(span * 1.25)); it.num["h"] = try n("h", 0.5...(span * 1.25))
            let xr = try graphRange(o["xr"], "field.xr"), yr = try graphRange(o["yr"], "field.yr")
            it.num["x0"] = xr.0; it.num["x1"] = xr.1; it.num["y0"] = yr.0; it.num["y1"] = yr.1
            let allowed = try graphParameters(&it, o, k).union([.y])
            if let raw = o["n"] {
                guard case .array(let grid) = raw, grid.count == 2 else { throw MGError("field.n") }
                let cols = try num(grid[0], 2...Double(MGLimits.fieldCols), "field.n")
                let rows = try num(grid[1], 2...Double(MGLimits.fieldRows), "field.n")
                guard cols.rounded() == cols, rows.rounded() == rows else { throw MGError("field.n") }
                it.num["cols"] = cols; it.num["rows"] = rows
            } else {
                // Twelve arrows along the longer side and the shorter side in proportion (at least three).
                let w = it.n("w"), h = it.n("h")
                it.num["cols"] = w >= h ? 12 : Swift.max(3, (12 * w / h).rounded())
                it.num["rows"] = w >= h ? Swift.max(3, (12 * h / w).rounded()) : 12
            }
            switch o["style"] {
            case nil, .string("arrows"): break
            case .string("unit"): it.flags.insert("unit")
            case .string("slope"): it.flags.insert("slope")
            default: throw MGError("field.style")
            }
            let dx = try expression(o["dx"], allowed, "field.dx"), dy = try expression(o["dy"], allowed, "field.dy")
            let xl = try o["xl"].map { try text($0, MGLimits.label, ctx, "field.xl") } ?? ""
            let yl = try o["yl"].map { try text($0, MGLimits.label, ctx, "field.yl") } ?? ""
            it.list = [xl, yl, dx.text, dy.text]
            let sampled = MGGraph.fieldVectors(it, dx, dy)
            guard sampled.vectors.contains(where: { $0.x != 0 || $0.y != 0 }) else { throw MGError("field.empty") }
            it.pts += sampled.vectors
            it.marked = sampled.missing
        case .curve:
            // A parametric (`x`, `y`) or polar (`r`) curve in `theta` that the engine samples and checks
            // (MGGraph.checkCurve); the model writes no points. The frame is aspect-correct (MGGraph.curveWindow).
            it.pts = [try p("at")]
            let w = try n("w", 0.5...(span * 1.25)), h = try n("h", 0.5...(span * 1.25))
            it.num["w"] = w; it.num["h"] = h
            let xr = try graphRange(o["xr"], "curve.xr"), yr = try graphRange(o["yr"], "curve.yr")
            it.num["rx0"] = xr.0; it.num["rx1"] = xr.1; it.num["ry0"] = yr.0; it.num["ry1"] = yr.1
            let window = MGGraph.curveWindow(xr, yr, w: w, h: h)
            it.num["x0"] = window.x0; it.num["x1"] = window.x1; it.num["y0"] = window.y0; it.num["y1"] = window.y1
            var allowed = try graphParameters(&it, o, k)
            allowed.remove(.x); allowed.insert(.theta)
            var theta = (0.0, 2 * Double.pi)
            if let raw = o["theta"] {
                guard case .array(let ends) = raw, ends.count == 2 else { throw MGError("curve.theta") }
                let bound = -MGLimits.curveEnd...MGLimits.curveEnd
                theta = (try num(ends[0], bound, "curve.theta"), try num(ends[1], bound, "curve.theta"))
                guard MGLimits.curveSpan.contains(theta.1 - theta.0) else { throw MGError("curve.theta") }
            }
            it.num["th0"] = theta.0; it.num["th1"] = theta.1
            if let period = try opt("period", MGLimits.funcPeriod) { it.num["period"] = period; allowed.insert(.t) }
            // Exactly one form: `x` and `y` together, or `r` alone.
            let expressions: [MGExpression]
            switch (o["x"], o["y"], o["r"]) {
            case (let x?, let y?, nil):
                expressions = [try expression(x, allowed, "curve.x"), try expression(y, allowed, "curve.y")]
            case (nil, nil, let r?):
                expressions = [try expression(r, allowed, "curve.r")]
                it.flags.insert("polar")
            default: throw MGError("curve.form")
            }
            if it.num["period"] != nil, !expressions.contains(where: { $0.variables.contains(.t) }) { throw MGError("curve.period") }
            if let m = try opt("mark", theta.0...theta.1) { it.num["mark"] = m }
            try MGGraph.checkCurve(&it, expressions)
            it.list = [try o["xl"].map { try text($0, MGLimits.label, ctx, "curve.xl") } ?? "",
                       try o["yl"].map { try text($0, MGLimits.label, ctx, "curve.yl") } ?? ""] + expressions.map(\.text)
        }
        return it
    }

    /// The axis labels of a `func` item (`xl`, `yl`; empty when not set).
    static func functionLabels(_ o: [String: MGJSON], _ ctx: MGContext) throws -> [String] {
        [try o["xl"].map { try text($0, MGLimits.label, ctx, "func.xl") } ?? "",
         try o["yl"].map { try text($0, MGLimits.label, ctx, "func.yl") } ?? ""]
    }

    /// A `func` item parsed without its texts (`MGReadout.textKeys`), with its label and axis labels from `o` added: the
    /// same item as `item(.object(o), ctx)`.
    static func functionTexts(_ core: MGItem, _ o: [String: MGJSON], _ ctx: MGContext) throws -> MGItem {
        var it = core
        if let l = o["label"] { it.label = try text(l, MGLimits.label, ctx, "item.label") }
        it.list = try functionLabels(o, ctx)
        return it
    }

    /// A `func`, `field` or `curve` range: like `range` (two numbers within ±10⁶, increasing) and at least 10⁻⁶ wide.
    static func graphRange(_ v: MGJSON?, _ what: String) throws -> (Double, Double) {
        let r = try range(v, what)
        guard r.1 - r.0 >= 1e-6 else { throw MGError(what) }
        return r
    }

    /// The optional `a`, `b` and `c` parameters of a `func`, `field` or `curve` item (each within ±`MGLimits.exprParameter`,
    /// reason `<kind>.<name>`) and the variables its expressions may read: `x` and each parameter that is set.
    static func graphParameters(_ it: inout MGItem, _ o: [String: MGJSON], _ k: String) throws -> Set<MGExpression.Variable> {
        var allowed: Set<MGExpression.Variable> = [.x]
        for v in [MGExpression.Variable.a, .b, .c] {
            guard let raw = o[v.rawValue] else { continue }
            it.num[v.rawValue] = try num(raw, -MGLimits.exprParameter...MGLimits.exprParameter, "\(k).\(v.rawValue)")
            allowed.insert(v)
        }
        return allowed
    }

    /// A `func`, `field` or `curve` expression string, compiled with `MGExpression` (reasons `what`, `what.syntax`, …).
    static func expression(_ v: MGJSON?, _ allowed: Set<MGExpression.Variable>, _ what: String) throws -> MGExpression {
        guard case .string(let s)? = v else { throw MGError(what) }
        return try MGExpression.compile(s, allowed: allowed, reason: what)
    }

    // MARK: primitives

    static func closed(_ o: [String: MGJSON], required: Set<String>, optional: Set<String>, _ what: String) throws {
        let keys = Set(o.keys)
        guard required.isSubset(of: keys) else { throw MGError("\(what).missing") }
        let unknown = keys.subtracting(required.union(optional))
        guard unknown.isEmpty else {
            let ordered = unknown.sorted { lhs, rhs in
                lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars, by: { $0.value < $1.value })
            }
            throw MGError("\(what).unknown.\(reasonKeys(ordered))")
        }
    }

    /// Reason names for scene, item, `edit.key` and `patch.op` reasons: at most 4 names, and any name that is not 1–24
    /// ASCII letters, digits or `_` becomes `?`. Lesson-owned reasons use `MGLessonEngine.segments`.
    static func reasonKeys(_ keys: [String]) -> String {
        keys.prefix(4).map { key in
            let scalars = key.unicodeScalars
            guard (1...24).contains(scalars.count), scalars.allSatisfy({
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_")
            }) else { return "?" }
            return key
        }.joined(separator: ",")
    }
    static func num(_ v: MGJSON?, _ range: ClosedRange<Double>, _ what: String) throws -> Double {
        guard case .number(let d)? = v, d.isFinite, range.contains(d) else { throw MGError(what) }
        return d
    }
    static func identifier(_ v: MGJSON, _ what: String) throws -> String {
        guard case .string(let s) = v, (1...24).contains(s.count), let f = s.unicodeScalars.first,
              CharacterSet.letters.contains(f), f.isASCII,
              s.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }) else { throw MGError(what) }
        return s
    }
    static func point(_ v: MGJSON?, _ ctx: MGContext, _ what: String) throws -> MGPoint {
        guard case .array(let a)? = v, a.count == 2 || (a.count == 3 && ctx.is3D) else { throw MGError(what) }
        let x = try num(a[0], (-0.25 * ctx.width)...(1.25 * ctx.width), what)
        let y = try num(a[1], (-0.25 * ctx.height)...(1.25 * ctx.height), what)
        let z = a.count == 3 ? try num(a[2], (-ctx.span)...ctx.span, what) : 0
        return MGPoint(x, y, z)
    }
    static func vector3(_ v: MGJSON, _ what: String) throws -> MGPoint {
        guard case .array(let a) = v, a.count == 3 else { throw MGError(what) }
        let p = MGPoint(try num(a[0], -1...1, what), try num(a[1], -1...1, what), try num(a[2], -1...1, what))
        guard p.length > 0.01 else { throw MGError(what) }
        return abs(p.length - 1) < 1e-9 ? p : p * (1 / p.length)
    }
    static func dataPoint(_ v: MGJSON, _ what: String) throws -> MGPoint {
        guard case .array(let a) = v, a.count == 2 else { throw MGError(what) }
        return MGPoint(try num(a[0], -1e6...1e6, what), try num(a[1], -1e6...1e6, what))
    }
    static func range(_ v: MGJSON?, _ what: String) throws -> (Double, Double) {
        guard case .array(let a)? = v, a.count == 2 else { throw MGError(what) }
        let lo = try num(a[0], -1e6...1e6, what), hi = try num(a[1], -1e6...1e6, what)
        guard hi - lo >= 1e-6 else { throw MGError(what) }
        return (lo, hi)
    }

    /// Short plain text with `{name}` placeholders filled from locally computed values. Rejects markup, code fences,
    /// URLs, control characters and unknown placeholders. `code` text (text style `code`) keeps leading spaces and may
    /// hold `<` and `>` as long as nothing looks like a markup tag. Text items and narration may contain line feeds.
    static func text(_ v: MGJSON?, _ max: Int, _ ctx: MGContext, _ what: String, code: Bool = false,
                     multiline: Bool = false) throws -> String {
        guard case .string(let s)? = v else { throw MGError(what) }
        let t = s.trimmingCharacters(in: code ? .newlines : .whitespacesAndNewlines)
        // Explainers allow longer placeholder names. Filled text uses the same limit in every scene.
        let rawLimit = ctx.env == nil ? max : 4 * max
        guard !t.isEmpty, !(code && t.allSatisfy(\.isWhitespace)), s.unicodeScalars.count <= rawLimit,
              code ? !looksLikeMarkup(s) : (!s.unicodeScalars.contains("<") && !s.unicodeScalars.contains(">")),
              s.range(of: "```", options: .literal) == nil, s.range(of: "://", options: .literal) == nil,
              !s.unicodeScalars.contains(where: { scalar in
                  if multiline && scalar == "\n" { return false }
                  return CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x2028 || scalar.value == 0x2029
              }) else { throw MGError(what) }
        let filled = try fill(t, ctx.values, what, env: ctx.env)
        guard filled.unicodeScalars.count <= max else { throw MGError(what) }
        return filled
    }
    /// True when `<` is directly followed by a letter, `/`, `!` or `?` and a `>` comes later (a tag, comment or
    /// processing instruction). Comparisons such as `i < n` or `a > b` are not tags.
    static func looksLikeMarkup(_ s: String) -> Bool {
        let scalars = s.unicodeScalars
        guard let end = scalars.lastIndex(of: ">") else { return false }
        let beforeClose = scalars[..<end]
        for (lead, next) in zip(beforeClose, beforeClose.dropFirst()) where lead == "<" {
            if next == "/" || next == "!" || next == "?" { return true }
            switch next.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
            default: break
            }
        }
        return false
    }

    static func fill(_ s: String, _ values: [String: MGValue], _ what: String, env: MGParseEnvironment? = nil) throws -> String {
        let scalars = Array(s.unicodeScalars)
        guard scalars.contains("{") || scalars.contains("}") else { return s }
        var out = "", name = "", inside = false
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            i += 1
            if !inside, ch == "{", let end = scalars[i...].firstIndex(of: "}"), let readout = MGReadout.placeholder(scalars[i..<end]) {
                // A readout of a `func` item (`{wave.area}`, MGReadout), filled from the engine's value. Without one, an
                // explainer looks the name up as a 3D fact as before; a plain scene refuses it.
                if let v = values[readout] { out += v.text; i = end + 1; continue }
                if env == nil { throw MGError("\(what).placeholder.readout") }
            }
            if inside {
                if ch == "}" {
                    if let env, name.contains(".") || name.contains("|") {
                        // Explainer: a dotted name is a 3D fact; a modifier never applies to a plain 2D value.
                        out += try env.fill(name, what)
                    } else {
                        guard name.count <= 16, !name.contains("_") else { throw MGError("\(what).placeholder") }
                        guard let v = values[name] else { throw MGError("\(what).placeholder.\(name)") }
                        out += v.text
                    }
                    name = ""; inside = false
                } else if env != nil {
                    guard ch.isASCII, CharacterSet.alphanumerics.contains(ch) || ch == "." || ch == "|" || ch == "_",
                          name.count < MGSolidFacts.nameLength + 8 * MGSolidFacts.modifiers else { throw MGError("\(what).placeholder") }
                    name.unicodeScalars.append(ch)
                } else {
                    guard ch.isASCII, CharacterSet.alphanumerics.contains(ch), name.count < 16 else { throw MGError("\(what).placeholder") }
                    name.unicodeScalars.append(ch)
                }
            } else if ch == "{" { inside = true } else if ch == "}" { throw MGError("\(what).brace") } else { out.unicodeScalars.append(ch) }
        }
        guard !inside else { throw MGError("\(what).brace") }
        return out
    }
}

extension MGItem {
    /// Wire form of a resolved item (placeholders already filled). Used by edits and patches.
    func wire() -> [String: MGJSON] {
        // Never trap on malformed (public-API) template items: a missing point serialises as non-finite and the item
        // validator then rejects it with a reason.
        func at(_ k: Int) -> MGPoint { pts.indices.contains(k) ? pts[k] : MGPoint(.nan, .nan) }
        var o: [String: MGJSON] = ["id": .string(id), "k": .string(kind.rawValue), "color": .string(color.rawValue)]
        func pt(_ p: MGPoint, _ z: Bool = false) -> MGJSON { .array(z || p.z != 0 ? [.number(p.x), .number(p.y), .number(p.z)] : [.number(p.x), .number(p.y)]) }
        func put(_ key: String, _ numKey: String? = nil) { if let v = num[numKey ?? key] { o[key] = .number(v) } }
        if let label { o["label"] = .string(label) }
        switch kind {
        case .body:
            o["at"] = pt(at(0)); if has("ball") { o["shape"] = .string("ball") }; put("size"); put("angle")
            if pts.count > 1, let t = num["moveT"] { o["move"] = .object(["to": pt(at(1)), "t": .number(t)]) }
        case .incline: o["at"] = pt(at(0)); put("base"); put("angle")
        case .line: o["from"] = pt(at(0)); o["to"] = pt(at(1)); if has("dashed") { o["style"] = .string("dashed") }; if has("ground") { o["style"] = .string("ground") }
        case .vector:
            if let ref { o["on"] = .string(ref) } else if let p = pts.first { o["from"] = pt(p) }
            if let d = dir { o["dir"] = .array([.number(d.x), .number(d.y), .number(d.z)]) } else { put("angle") }
            put("len"); if has("dashed") { o["dashed"] = .bool(true) }
        case .axes:
            o["at"] = pt(at(0)); put("w"); put("h")
            if list.count == 2 { if !list[0].isEmpty { o["xl"] = .string(list[0]) }; if !list[1].isEmpty { o["yl"] = .string(list[1]) } }
        case .plot:
            o["at"] = pt(at(0)); put("w"); put("h")
            o["xr"] = .array([.number(n("x0")), .number(n("x1"))]); o["yr"] = .array([.number(n("y0")), .number(n("y1"))])
            o["pts"] = .array(pts.dropFirst().map { .array([.number($0.x), .number($0.y)]) })
            if list.count == 2 { if !list[0].isEmpty { o["xl"] = .string(list[0]) }; if !list[1].isEmpty { o["yl"] = .string(list[1]) } }
        case .spring: o["from"] = pt(at(0)); o["to"] = pt(at(1)); put("coils")
        case .pulley, .orbit: o["at"] = pt(at(0)); put("r")
        case .rope: o["pts"] = .array(pts.map { pt($0) })
        case .path: o["pts"] = .array(pts.map { pt($0) }); if has("dashed") { o["dashed"] = .bool(true) }
        case .text:
            o["at"] = pt(at(0)); o["text"] = .string(text ?? "")
            if has("callout") { o["style"] = .string("callout") }; if has("title") { o["style"] = .string("title") }
            if has("code") { o["style"] = .string("code") }
        case .highlight: o["target"] = .string(ref ?? "")
        case .bars:
            o["at"] = pt(at(0)); put("w"); put("h"); if let text { o["unit"] = .string(text) }
            o["bars"] = .array(bars.map { .object(["label": .string($0.label), "value": .number($0.value), "color": .string($0.color.rawValue)]) })
        case .array:
            o["at"] = pt(at(0)); o["vals"] = .array(list.map { .string($0) }); put("cell")
            if !pointers.isEmpty { o["ptrs"] = .array(pointers.map { .object(["i": .number($0.index.rounded()), "label": .string($0.label)]) }) }
            if !marked.isEmpty { o["marked"] = .array(marked.map { .number(Double($0)) }) }
        case .node: o["at"] = pt(at(0)); o["text"] = .string(text ?? ""); put("r")
        case .edge: o["a"] = .string(ref ?? ""); o["b"] = .string(ref2 ?? ""); if has("dir") { o["dir"] = .bool(true) }
        case .table:
            o["at"] = pt(at(0)); put("cw"); put("rh")
            // Never trap on a malformed (public-API) table: an inconsistent shape serialises as null and is refused.
            let rawCols = n("cols", 1), rawRows = n("rows", 1)
            guard rawCols.isFinite, rawRows.isFinite, rawCols.rounded() == rawCols, rawRows.rounded() == rawRows,
                  (1...Double(MGLimits.tableCols)).contains(rawCols), (1...Double(MGLimits.tableRows)).contains(rawRows),
                  list.count == Int(rawCols) * Int(rawRows) else { o["cells"] = .null; break }
            let cols = Int(rawCols)
            o["cells"] = .array(stride(from: 0, to: list.count, by: cols).map { r in .array(list[r..<(r + cols)].map { .string($0) }) })
            if has("header") { o["header"] = .bool(true) }
            if !marked.isEmpty { o["marked"] = .array(marked.map { .array([.number(Double($0 / cols)), .number(Double($0 % cols))]) }) }
        case .region: o["pts"] = .array(pts.map { pt($0) }); if has("dashed") { o["dashed"] = .bool(true) }
        case .function:
            // The samples are derived and never serialised: a re-parse samples and checks the expression again.
            o["at"] = pt(at(0)); put("w"); put("h")
            o["xr"] = .array([.number(n("x0")), .number(n("x1"))]); o["yr"] = .array([.number(n("y0")), .number(n("y1"))])
            o["y"] = .string(text ?? "")
            for key in ["a", "b", "c", "period", "mark"] { put(key) }
            if let s0 = num["s0"], let s1 = num["s1"] { o["shade"] = .array([.number(s0), .number(s1)]) }
            let readouts = MGReadout.requested(self)
            if !readouts.isEmpty { o["readouts"] = .array(readouts.map { .string($0.rawValue) }) }
            if list.count >= 2 { if !list[0].isEmpty { o["xl"] = .string(list[0]) }; if !list[1].isEmpty { o["yl"] = .string(list[1]) } }
        case .field:
            // `list` is [x label, y label, dx, dy]; the arrows are derived and never serialised.
            o["at"] = pt(at(0)); put("w"); put("h")
            o["xr"] = .array([.number(n("x0")), .number(n("x1"))]); o["yr"] = .array([.number(n("y0")), .number(n("y1"))])
            for key in ["a", "b", "c"] { put(key) }
            if let cols = num["cols"], let rows = num["rows"] { o["n"] = .array([.number(cols), .number(rows)]) }
            if has("unit") { o["style"] = .string("unit") }; if has("slope") { o["style"] = .string("slope") }
            if list.count == 4 {
                if !list[0].isEmpty { o["xl"] = .string(list[0]) }; if !list[1].isEmpty { o["yl"] = .string(list[1]) }
                o["dx"] = .string(list[2]); o["dy"] = .string(list[3])
            }
        case .curve:
            // `list` is [x label, y label, r] (polar) or [x label, y label, x, y]; the given ranges are written back (the
            // drawn window is derived from them), and the samples are derived and never serialised.
            o["at"] = pt(at(0)); put("w"); put("h")
            o["xr"] = .array([.number(num["rx0"] ?? n("x0")), .number(num["rx1"] ?? n("x1"))])
            o["yr"] = .array([.number(num["ry0"] ?? n("y0")), .number(num["ry1"] ?? n("y1"))])
            if let t0 = num["th0"], let t1 = num["th1"] { o["theta"] = .array([.number(t0), .number(t1)]) }
            for key in ["a", "b", "c", "period", "mark"] { put(key) }
            if list.count >= 2 { if !list[0].isEmpty { o["xl"] = .string(list[0]) }; if !list[1].isEmpty { o["yl"] = .string(list[1]) } }
            if has("polar"), list.count == 3 { o["r"] = .string(list[2]) }
            if !has("polar"), list.count == 4 { o["x"] = .string(list[2]); o["y"] = .string(list[3]) }
        }
        return o
    }
}

extension MGCamera {
    /// Wire form, so template-built cameras are validated by the same rules as model-written ones.
    func wire() -> MGJSON {
        var o: [String: MGJSON] = ["zoom": .number(zoom), "yaw": .number(yaw), "pitch": .number(pitch)]
        if let x { o["x"] = .number(x) }; if let y { o["y"] = .number(y) }
        return .object(o)
    }
}
