// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A follow-up update to the CURRENT scene: `{"v":1,"rev":n?,"ops":[...]}`. Ops (1–12):
///   {"op":"params","params":{...}}       merge template params (the app recomputes every number)
///   {"op":"add","item":{...}}            add an item
///   {"op":"remove","id":"x"}             remove an item (template items are hidden)
///   {"op":"set","id":"x","key":"k","value":v}   change one key of one item (same validation as the wire format)
///   {"op":"steps","steps":[...]}         replace the walkthrough
///   {"op":"step","index":n}              jump to a step
///   {"op":"camera","camera":{...}} | {"op":"title","title":"..."} | {"op":"dim","dim":"2d"|"3d"}
/// The patch rewrites the scene's canonical source and re-validates the WHOLE result. If anything fails the old scene stays.
public struct MGPatch: Equatable, Sendable {
    public let ops: [MGJSON]
    /// Optional `"rev"`: the scene revision this patch was written against.
    public var baseRevision: Int? = nil

    /// A patch built in code, for example by a host slider that changes one template parameter. Nothing is checked
    /// here: `MGScene.applying` checks the operation count (1–12), finite numbers (`patch.number`), nesting
    /// (`patch.depth`), the patch byte bound and each operation's shape with the same rules and reasons as `parse`,
    /// then re-validates the whole scene.
    public init(ops: [MGJSON], baseRevision: Int? = nil) {
        self.ops = ops; self.baseRevision = baseRevision
    }

    /// The `parse` rules for a patch that did not come through `parse`.
    func checkShape() throws {
        guard (1...12).contains(ops.count) else { throw MGError("patch.ops") }
        try MGJSON.object(["v": .number(1), "ops": .array(ops)])
            .checkEntry(maxDepth: MGLimits.depth, maxBytes: MGLimits.patchBytes, number: "patch.number", depth: "patch.depth", bytes: "patch.object")
        for op in ops { try Self.shape(op) }
    }

    public static func parse(data: Data) -> Result<MGPatch, MGError> {
        guard data.count <= MGLimits.patchBytes * 2 else { return .failure(.init("patch.json")) }
        if let r = MGJSON.dataRefusal(data, json: "patch.json", depth: "patch.depth") { return .failure(.init(r)) }   // UTF-8 only
        guard let o = try? JSONSerialization.jsonObject(with: data), let j = MGJSON(any: o) else { return .failure(.init("patch.json")) }
        return parse(json: j)
    }
    public static func parse(object: Any) -> Result<MGPatch, MGError> {
        guard let j = MGJSON(any: object) else { return .failure(.init("patch.json")) }
        return parse(json: j)
    }
    public static func parse(json: MGJSON) -> Result<MGPatch, MGError> {
        do {
            try json.checkEntry(maxDepth: MGLimits.depth, maxBytes: MGLimits.patchBytes, number: "patch.number", depth: "patch.depth", bytes: "patch.object")
            guard let o = json.objectValue else { throw MGError("patch.object") }
            try MGParser.closed(o, required: ["v", "ops"], optional: ["rev"], "patch")
            guard o["v"] == .number(1), case .array(let ops)? = o["ops"], (1...12).contains(ops.count) else { throw MGError("patch.ops") }
            for op in ops { try shape(op) }
            var base: Int?
            if let r = o["rev"] { let d = try MGParser.num(r, 0...1_000_000, "patch.rev"); guard d.rounded() == d else { throw MGError("patch.rev") }; base = Int(d) }
            return .success(MGPatch(ops: ops, baseRevision: base))
        } catch let e as MGError { return .failure(e) } catch { return .failure(.init("patch")) }
    }

    static func shape(_ op: MGJSON) throws {
        guard let o = op.objectValue, case .string(let name)? = o["op"] else { throw MGError("patch.op") }
        let keys: Set<String>
        switch name {
        case "params": keys = ["params"]
        case "add": keys = ["item"]
        case "remove": keys = ["id"]
        case "set": keys = ["id", "key", "value"]
        case "steps": keys = ["steps"]
        case "step": keys = ["index"]
        case "camera": keys = ["camera"]
        case "title": keys = ["title"]
        case "dim": keys = ["dim"]
        default: throw MGError("patch.op.\(name)")
        }
        try MGParser.closed(o, required: keys.union(["op"]), optional: [], "patch.\(name)")
        if name == "step" {
            let index = try MGParser.num(o["index"], 0...Double(MGLimits.steps - 1), "patch.step")
            guard index.rounded() == index else { throw MGError("patch.step") }
        }
    }
}

extension MGScene {
    /// Returns the updated scene, or a failure and the caller keeps showing `self` (fail safe).
    public func applying(_ patch: MGPatch) -> Result<MGScene, MGError> { applying(patch, extraTemplates: []) }

    /// Same, with templates that are not registered (for example a pack under validation). Use the same extras that
    /// parsed this scene; a registered template with the same name wins.
    public func applying(_ patch: MGPatch, extraTemplates: [MGTemplate]) -> Result<MGScene, MGError> {
        guard var root = source.objectValue else { return .failure(.init("patch.source")) }
        if let base = patch.baseRevision, base != revision { return .failure(.init("patch.stale")) }
        var jump: Int?
        do {
            try patch.checkShape()
            for op in patch.ops {
                guard let o = op.objectValue, case .string(let name)? = o["op"] else { throw MGError("patch.op") }
                switch name {
                case "params":
                    guard template != nil, var params = root["params"]?.objectValue, let add = o["params"]?.objectValue else { throw MGError("patch.params") }
                    for (k, v) in add { params[k] = v }
                    root["params"] = .object(params)
                case "add":
                    guard let added = o["item"] else { throw MGError("patch.add") }
                    var list = Self.array(root["items"])
                    list.append(added); root["items"] = .array(list)
                case "remove":
                    guard case .string(let id)? = o["id"] else { throw MGError("patch.remove") }
                    var list = Self.array(root["items"])
                    if let i = list.firstIndex(where: { $0["id"] == .string(id) }) {
                        list.remove(at: i); root["items"] = list.isEmpty && template != nil ? nil : .array(list)
                    } else if template != nil, item(id) != nil {
                        var hide = Self.array(root["hide"]); if !hide.contains(.string(id)) { hide.append(.string(id)) }; root["hide"] = .array(hide)
                        let over = Self.array(root["over"]).filter { $0["id"] != .string(id) }; root["over"] = over.isEmpty ? nil : .array(over)
                    } else { throw MGError("patch.remove.ref") }
                case "set":
                    guard case .string(let id)? = o["id"], case .string(let key)? = o["key"], let value = o["value"] else { throw MGError("patch.set") }
                    var list = Self.array(root["items"])
                    if let i = list.firstIndex(where: { $0["id"] == .string(id) }), var obj = list[i].objectValue {
                        guard key != "id", key != "k" else { throw MGError("patch.set.key") }
                        obj[key] = value
                        if key == "on" { obj["from"] = nil }; if key == "from", obj["k"] == .string("vector") { obj["on"] = nil }
                        list[i] = .object(obj); root["items"] = .array(list)
                    } else if template != nil, item(id) != nil {
                        var over = Self.array(root["over"]).filter { !($0["id"] == .string(id) && $0["key"] == .string(key)) }
                        over.append(.object(["id": .string(id), "key": .string(key), "value": value])); root["over"] = .array(over)
                    } else { throw MGError("patch.set.ref") }
                case "steps": root["steps"] = o["steps"]
                case "step":
                    guard case .number(let d)? = o["index"], d.isFinite, d.rounded() == d,
                          d >= 0, d < Double(MGLimits.steps) else { throw MGError("patch.step") }
                    jump = Int(d)
                case "camera": root["camera"] = o["camera"]
                case "title": root["title"] = o["title"]
                case "dim": root["dim"] = o["dim"]
                default: throw MGError("patch.op")
                }
            }
        } catch let e as MGError { return .failure(e) } catch { return .failure(.init("patch")) }
        switch MGParser.scene(json: .object(root), extraTemplates: extraTemplates) {
        case .success(var next):
            next.revision = revision + 1
            if let jump {
                guard jump < max(next.steps.count, 1) else { return .failure(.init("patch.step.range")) }
                next.startStep = jump
            }
            return .success(next)
        case .failure(let e): return .failure(e)
        }
    }

    static func array(_ v: MGJSON?) -> [MGJSON] { if case .array(let a)? = v { return a }; return [] }
}
