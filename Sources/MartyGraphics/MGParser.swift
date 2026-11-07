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
    /// Template record-list parameters: at most this many records of at most this many numeric fields. These bounds
    /// apply to the record-list shape only; no existing limit changes.
    public static let records = 32, recordFields = 6
    /// Raw (free-form JSON) template parameters: the canonical `params` object may be at most this many bytes.
    public static let rawParamsBytes = 4 * 1024
    /// Nesting limit (arrays and objects on one path; `[[1]]` is 2) of every JSON value a public entry point accepts:
    /// scenes (`scene.depth`), patches (`patch.depth`), raw template params (`template.params.depth`), lessons and
    /// snapshots (`MGLessonLimits`), Solid assemblies and components, and `MGJSON(any:)`. Real documents nest 6 to 15
    /// levels. The system JSON parser and encoder, Swift's `==`, hashing and freeing of nested values, and
    /// `MGJSON(any:)` all recurse once per level; at 64 levels they stay far inside a 512 KiB thread stack (iOS
    /// secondary threads) and a 1 MiB main-thread stack (iOS). The check is one walk that does not recurse, and it runs
    /// before any of them (on JSON text: before the system parser).
    public static let depth = 64
    /// `table` items: at most this many rows and columns, and this many characters per cell.
    public static let tableRows = 8, tableCols = 6, tableCellText = 12
}

public struct MGError: Error, Equatable, CustomStringConvertible {
    /// Developer reason for tests and logs only. Never shown to the learner.
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { reason }
}

/// Context shared by item parsing, edits and patches.
struct MGContext {
    let width: Double, height: Double, is3D: Bool
    let values: [String: MGValue]
    var span: Double { max(width, height) }
}

/// Strict, fail-safe decoder for the scene DSL. Every object has a closed key set; numbers must be finite and in range;
/// text must be short plain text; ids must be unique and every reference must resolve. Any violation rejects the whole
/// scene (the caller keeps whatever it showed before).
public enum MGParser {
    static let topKeys: Set<String> = ["v", "template", "params", "title", "dim", "world", "items", "steps", "camera", "hide", "over"]

    public static func scene(data: Data) -> Result<MGScene, MGError> {
        guard data.count <= MGLimits.sceneBytes * 2 else { return .failure(.init("json")) }
        guard MGJSON.textNesting(data) <= MGLimits.depth else { return .failure(.init("scene.depth")) }
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
        guard MGJSON.textNesting(data) <= MGLimits.depth else { return .failure(.init("scene.depth")) }
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
        do { return .success(try parseScene(json, extra: extraTemplates)) } catch let e as MGError { return .failure(e) } catch { return .failure(.init("unknown")) }
    }

    // MARK: scene

    static func parseScene(_ json: MGJSON, extra: [MGTemplate] = []) throws -> MGScene {
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
        let ctx = MGContext(width: width, height: height, is3D: is3D, values: build?.values ?? [:])

        // Template output goes through the same item validator as model-written items (fail safe on template bugs too).
        var items = try (build?.items ?? []).map { try item(.object($0.wire()), ctx) }
        if let raw = o["items"] {
            guard case .array(let list) = raw else { throw MGError("items") }
            let limit = build == nil ? MGLimits.items : MGLimits.templateExtras
            guard (build == nil ? 1 : 0)...limit ~= list.count else { throw MGError("items.count") }
            for entry in list { items.append(try item(entry, ctx)) }
        }
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
            var st = st; st.say = try text(.string(st.say), MGLimits.say, ctx, "template.say")
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
        let camera = try o["camera"].map { try self.camera($0, ctx) } ?? build?.camera.map { try self.camera($0.wire(), ctx) }

        guard items.count <= MGLimits.resolvedItems, !items.isEmpty else { throw MGError("items.total") }
        if is3D { for i in items where !MGKind.in3D.contains(i.kind) { throw MGError("3d.kind.\(i.kind.rawValue)") } }
        try checkReferences(items: items, steps: steps, ctx)

        let attachments = (build?.attachments ?? [:]).filter { ids.contains($0.key) && ids.contains($0.value) }
        return MGScene(source: json, template: o["template"].flatMap { if case .string(let s) = $0 { return s }; return nil },
                       title: title, is3D: is3D, width: width, height: height, items: items, steps: steps, camera: camera,
                       values: ctx.values, motion: build.map { prune($0.motion, ids) } ?? .none, attachments: attachments)
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
        try closed(o, required: ["say"], optional: ["show", "focus", "cam", "do"], "step")
        var s = MGStep(say: try text(o["say"], MGLimits.say, ctx, "step.say"))
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

    /// Re-encodes the item, changes one key and re-validates it with the same rules as the wire format.
    static func apply(_ e: MGEdit, to items: [MGItem], _ ctx: MGContext) throws -> [MGItem] {
        guard let index = items.firstIndex(where: { $0.id == e.id }) else { throw MGError("edit.ref") }
        var wire = items[index].wire()
        guard allowedKeys(items[index].kind).contains(e.key) else { throw MGError("edit.key.\(e.key)") }
        wire[e.key] = e.value
        // Changing one end of an either/or pair removes the other.
        if e.key == "on" { wire["from"] = nil }; if e.key == "from" && items[index].kind == .vector { wire["on"] = nil }
        var out = items; out[index] = try item(.object(wire), ctx); return out
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
        case .table, .region: return .accent
        }
    }

    static func item(_ json: MGJSON, _ ctx: MGContext) throws -> MGItem {
        guard let o = json.objectValue, case .string(let k)? = o["k"], let kind = MGKind(rawValue: k) else { throw MGError("item.kind") }
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
                it.num["moveT"] = try num(mo["t"], 0.3...10, "body.move.t")
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
            let coils = try opt("coils", 3...24) ?? 8
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
            it.text = try text(o["text"], MGLimits.text, ctx, "text.text", code: isCode)
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
        }
        return it
    }

    // MARK: primitives

    static func closed(_ o: [String: MGJSON], required: Set<String>, optional: Set<String>, _ what: String) throws {
        let keys = Set(o.keys)
        guard required.isSubset(of: keys) else { throw MGError("\(what).missing") }
        guard keys.isSubset(of: required.union(optional)) else { throw MGError("\(what).unknown.\(keys.subtracting(required.union(optional)).sorted().joined(separator: ","))") }
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
        guard lo < hi else { throw MGError(what) }
        return (lo, hi)
    }

    /// Short plain text with `{name}` placeholders filled from locally computed values. Rejects markup, code fences,
    /// URLs, control characters and unknown placeholders. `code` text (text style `code`) keeps leading spaces and may
    /// hold `<` and `>` as long as nothing looks like a markup tag; every other rule is the same.
    static func text(_ v: MGJSON?, _ max: Int, _ ctx: MGContext, _ what: String, code: Bool = false) throws -> String {
        guard case .string(let s)? = v else { throw MGError(what) }
        let t = s.trimmingCharacters(in: code ? .newlines : .whitespacesAndNewlines)
        guard !t.isEmpty, !(code && t.allSatisfy(\.isWhitespace)), s.unicodeScalars.count <= max,
              code ? !looksLikeMarkup(s) : (!s.contains("<") && !s.contains(">")), !s.contains("```"), !s.contains("://"),
              !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }) else { throw MGError(what) }
        return try fill(t, ctx.values, what)
    }
    /// True when `<` is directly followed by a letter, `/`, `!` or `?` and a `>` comes later (a tag, comment or
    /// processing instruction). Comparisons such as `i < n` or `a > b` are not tags.
    static func looksLikeMarkup(_ s: String) -> Bool {
        let c = Array(s)
        for (i, ch) in c.enumerated() where ch == "<" && i + 1 < c.count {
            let n = c[i + 1]
            if n.isLetter || n == "/" || n == "!" || n == "?", c[(i + 1)...].contains(">") { return true }
        }
        return false
    }

    static func fill(_ s: String, _ values: [String: MGValue], _ what: String) throws -> String {
        guard s.contains("{") || s.contains("}") else { return s }
        var out = "", name = "", inside = false
        for ch in s {
            if inside {
                if ch == "}" {
                    guard let v = values[name] else { throw MGError("\(what).placeholder.\(name)") }
                    out += v.text; name = ""; inside = false
                } else {
                    guard ch.isASCII, ch.isLetter || ch.isNumber, name.count < 16 else { throw MGError("\(what).placeholder") }
                    name.append(ch)
                }
            } else if ch == "{" { inside = true } else if ch == "}" { throw MGError("\(what).brace") } else { out.append(ch) }
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
