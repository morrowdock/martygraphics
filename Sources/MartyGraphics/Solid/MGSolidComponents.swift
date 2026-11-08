// SPDX-License-Identifier: Apache-2.0
import Foundation

// Reusable solid components: a closed-key JSON definition with numeric parameters, expanded into plain assembly parts
// before the assembly is compiled. Foundation only, deterministic, bounded.

/// Hard limits for component definitions and their use. Input outside them is rejected, never clamped.
public enum MGSolidComponentLimits {
    /// Canonical JSON size of one definition.
    public static let bytes = 16 * 1024
    public static let params = 16, parts = 24, constraints = 32, anchors = 8, checks = 8
    /// Components a library can hold.
    public static let library = 128
    /// `use` nesting: an assembly using a component that uses a component that uses a component.
    public static let depth = 3
    /// Nesting of one expression, and expression nodes evaluated for one instance.
    public static let exprDepth = 8, exprNodes = 4096
    /// Operands of `add`, `mul`, `min` and `max`.
    public static let exprArgs = 8
    /// Largest magnitude a parameter or an expression result may have.
    public static let value = 1e6
    /// Resolved part ids (`stage1.gears.pinion`, `stage.planet12`), including a `repeat` suffix.
    public static let idLength = 64
    public static let about = 160
    /// Text of one `anchorAbout` entry, in Unicode scalars.
    public static let anchorAbout = 120
}

/// One numeric parameter of a component.
public struct MGSolidComponentParam: Equatable, Sendable {
    public let name: String
    public let defaultValue: Double
    public let min: Double
    public let max: Double
    public let integer: Bool
    public let about: String?
}

/// A validated component definition.
public struct MGSolidComponent: Equatable, Sendable {
    public let id: String
    public let title: String
    /// One line for catalogs.
    public let about: String
    /// Sorted by name.
    public let params: [MGSolidComponentParam]
    /// Public names for inner parts (`input` → `pinion`), usable from outside as `<instance>.<anchor>`.
    public let anchors: [String: String]
    /// Where each anchor's frame sits and how its axes point, for catalogs (`anchorAbout`; anchors without one are
    /// left out).
    public let anchorAbout: [String: String]
    /// Inner wire part ids at the default parameters (nested components included, before `repeat`).
    public let parts: [String]
    /// Components this one uses directly.
    public let uses: [String]
    /// The definition JSON.
    public let source: MGJSON

    /// Parses and structurally validates a definition. Nested components must already be in `library`.
    /// This expands the component at its defaults but does not compile it; `MGSolidLibrary.validate` also compiles.
    public static func parse(_ json: MGJSON, library: MGSolidLibrary) -> Result<MGSolidComponent, MGSolidIssue> {
        if json.nestsTooDeep { return .failure(.init("component.nesting")) }
        do { return .success(try MGSolidComponents.definition(json, library)) }
        catch let e as MGSolidIssue { return .failure(e) }
        catch let e as MGError { return .failure(.init(e.reason)) }
        catch { return .failure(.init("unknown")) }
    }
}

/// A set of components an assembly can `use`. A value type: hosts copy `builtIn` and register their own.
public struct MGSolidLibrary: Equatable, Sendable {
    public internal(set) var components: [String: MGSolidComponent] = [:]

    public init() {}

    /// The components shipped with MartyGraphics (`MGSolidBuiltInComponents`).
    public static let builtIn: MGSolidLibrary = {
        var library = MGSolidLibrary()
        for source in MGSolidBuiltInComponents.sources {
            // Built-ins are compiled by the tests, so loading them stays cheap.
            if case .failure = library.add(Data(source.utf8), compile: false) { assertionFailure("built-in component refused") }
        }
        return library
    }()

    public var ids: [String] { components.keys.sorted() }
    public subscript(id: String) -> MGSolidComponent? { components[id] }

    /// Validates a definition without registering it: closed keys, parameters, expressions, references, then the
    /// component instantiated at its defaults must compile as an assembly on its own.
    public func validate(_ data: Data) -> Result<MGSolidComponent, MGSolidIssue> {
        var copy = self
        return copy.add(data, compile: true)
    }

    /// Validates and registers a definition (see `validate`). A duplicate id is refused (`component.duplicate.<id>`).
    @discardableResult public mutating func register(_ data: Data) -> Result<MGSolidComponent, MGSolidIssue> {
        add(data, compile: true)
    }

    @discardableResult public mutating func register(json: MGJSON) -> Result<MGSolidComponent, MGSolidIssue> {
        add(json, compile: true)
    }

    mutating func add(_ data: Data, compile: Bool) -> Result<MGSolidComponent, MGSolidIssue> {
        guard data.count <= MGSolidComponentLimits.bytes else { return .failure(.init("component.bytes")) }
        if let r = MGJSON.dataRefusal(data, json: "json", depth: "component.nesting") { return .failure(.init(r)) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = MGJSON(any: object) else {
            return .failure(.init("json"))
        }
        return add(json, compile: compile)
    }

    mutating func add(_ json: MGJSON, compile: Bool) -> Result<MGSolidComponent, MGSolidIssue> {
        let parsed = MGSolidComponent.parse(json, library: self)
        guard case .success(let c) = parsed else { return parsed }
        guard components[c.id] == nil else { return .failure(.init("component.duplicate.\(MGSolidParser.token(c.id))")) }
        guard components.count < MGSolidComponentLimits.library else { return .failure(.init("component.library.count")) }
        if compile {
            var trial = self
            trial.components[c.id] = c
            if case .failure(let e) = trial.instantiate(c.id) { return .failure(e) }
        }
        components[c.id] = c
        return .success(c)
    }

    /// The assembly a component gives on its own: one instance (id = the component id) with these parameters.
    public func assemblyJSON(_ id: String, with values: [String: Double] = [:]) -> MGJSON {
        let title = components[id]?.title ?? id
        let with = MGJSON.object(values.mapValues { .number($0) })
        return .object(["v": .number(1), "kind": .string("assembly"), "title": .string(title),
                        "parts": .array([.object(["id": .string(id), "use": .string(id), "with": with])])])
    }

    /// Compiles a component on its own (see `assemblyJSON`).
    public func instantiate(_ id: String, with values: [String: Double] = [:]) -> Result<MGSolidDocument, MGSolidIssue> {
        MGSolidParser.document(json: assemblyJSON(id, with: values), library: self)
    }

    /// A compact, sorted catalog an author or a model can read to discover components and their parameters.
    public func catalog() -> MGJSON {
        .object(["format": .string("martygraphics.solid.components/1"),
                 "components": .array(ids.compactMap { components[$0]?.catalogEntry })])
    }
}

extension MGSolidComponent {
    /// `{"id", "title", "about", "params": {name: {default, min, max, integer?, about?}}, "parts", "anchors", "anchorAbout"?}`.
    public var catalogEntry: MGJSON {
        var params: [String: MGJSON] = [:]
        for p in self.params {
            var o: [String: MGJSON] = ["default": .number(p.defaultValue), "min": .number(p.min), "max": .number(p.max)]
            if p.integer { o["integer"] = .bool(true) }
            if let a = p.about { o["about"] = .string(a) }
            params[p.name] = .object(o)
        }
        var o: [String: MGJSON] = ["id": .string(id), "title": .string(title), "about": .string(about), "params": .object(params),
                                   "parts": .array(parts.map { .string($0) })]
        if !anchors.isEmpty { o["anchors"] = .object(anchors.mapValues { .string($0) }) }
        if !anchorAbout.isEmpty { o["anchorAbout"] = .object(anchorAbout.mapValues { .string($0) }) }
        return .object(o)
    }
}

/// Definition parsing, expression evaluation and expansion of `use` entries.
enum MGSolidComponents {
    static let topKeys: Set<String> = ["v", "kind", "id", "title", "about", "params", "parts", "constraints", "anchors", "anchorAbout", "checks"]
    static let useKeys: Set<String> = ["id", "use", "with", "at", "rot", "parent", "set"]
    /// A top-level `use` entry in an assembly v2 may also take `explode` (one offset for the whole instance).
    static let useKeysV2: Set<String> = useKeys.union(["explode"])
    /// Step part-id lists in which a component instance id names all of its parts (`section.parts` too).
    static let stepListKeys = ["focus", "highlight", "ghost", "hide", "show"]
    static let ops: Set<String> = ["param", "add", "sub", "mul", "div", "min", "max", "neg", "pi", "sin", "cos"]

    // MARK: Definitions

    static func definition(_ json: MGJSON, _ library: MGSolidLibrary) throws -> MGSolidComponent {
        guard case .object(let o) = json else { throw MGSolidIssue("component.object") }
        guard json.canonicalByteCount <= MGSolidComponentLimits.bytes else { throw MGSolidIssue("component.bytes") }
        try MGSolidParser.closed(o, ["v", "kind", "id", "title", "about", "parts"], topKeys, "component")
        guard o["v"] == .number(1) else { throw MGSolidIssue("component.version") }
        guard o["kind"] == .string("component") else { throw MGSolidIssue("component.kind") }
        let id: String
        do { id = try MGParser.identifier(o["id"] ?? .null, "component.id") } catch { throw MGSolidIssue("component.id") }
        let title = try MGSolidParser.text(o["title"] ?? .null, MGSolidLimits.title, "component.title")
        let about = try MGSolidParser.text(o["about"] ?? .null, MGSolidComponentLimits.about, "component.about")
        var params: [MGSolidComponentParam] = []
        if let p = o["params"] {
            guard case .object(let po) = p, po.count <= MGSolidComponentLimits.params else { throw MGSolidIssue("component.params") }
            for (name, spec) in po.sorted(by: { $0.key < $1.key }) {
                guard (try? MGParser.identifier(.string(name), "")) != nil, !ops.contains(name) else {
                    throw MGSolidIssue("component.param.name.\(MGSolidParser.token(name))")
                }
                let w = "component.param.\(MGSolidParser.token(name))"
                guard case .object(let so) = spec else { throw MGSolidIssue(w) }
                try MGSolidParser.closed(so, ["default", "min", "max"], ["default", "min", "max", "integer", "about"], w)
                let V = -MGSolidComponentLimits.value...MGSolidComponentLimits.value
                let lo = try MGSolidParser.num(so["min"], V, w), hi = try MGSolidParser.num(so["max"], V, w)
                let d = try MGSolidParser.num(so["default"], V, w)
                guard lo <= d, d <= hi else { throw MGSolidIssue(w) }
                var integer = false
                if let i = so["integer"] {
                    guard case .bool(let b) = i else { throw MGSolidIssue(w) }
                    integer = b
                    if b { guard [lo, hi, d].allSatisfy({ $0.rounded() == $0 }) else { throw MGSolidIssue(w) } }
                }
                let a = try so["about"].map { try MGSolidParser.text($0, MGSolidLimits.name, w) }
                params.append(MGSolidComponentParam(name: name, defaultValue: d, min: lo, max: hi, integer: integer, about: a))
            }
        }
        guard case .array(let parts)? = o["parts"], (1...MGSolidComponentLimits.parts).contains(parts.count) else {
            throw MGSolidIssue("component.parts.count")
        }
        var ids = Set<String>(), uses: [String] = []
        for entry in parts {
            guard case .object(let po) = entry else { throw MGSolidIssue("component.part") }
            let pid: String
            do { pid = try MGParser.identifier(po["id"] ?? .null, "part.id") } catch { throw MGSolidIssue("part.id") }
            guard ids.insert(pid).inserted else { throw MGSolidIssue("id.duplicate.\(pid)", part: pid) }
            if let u = po["use"] {
                guard case .string(let uid) = u else { throw MGSolidIssue("component.use", part: pid) }
                guard uid != id else { throw MGSolidIssue("component.cycle.\(MGSolidParser.token(uid))", part: pid) }
                guard library.components[uid] != nil else { throw MGSolidIssue("component.unknown.\(MGSolidParser.token(uid))", part: pid) }
                if !uses.contains(uid) { uses.append(uid) }
            }
        }
        if let c = o["constraints"] {
            guard case .array(let list) = c, list.count <= MGSolidComponentLimits.constraints else { throw MGSolidIssue("component.constraints") }
        }
        var anchors: [String: String] = [:]
        if let a = o["anchors"] {
            guard case .object(let ao) = a, ao.count <= MGSolidComponentLimits.anchors else { throw MGSolidIssue("component.anchors") }
            // Sorted, so the same bytes always give the same first refusal.
            for (name, target) in ao.sorted(by: { $0.key < $1.key }) {
                guard (try? MGParser.identifier(.string(name), "")) != nil, !ids.contains(name), case .string(let t) = target else {
                    throw MGSolidIssue("component.anchor.\(MGSolidParser.token(name))")
                }
                anchors[name] = t
            }
        }
        // One line per anchor saying where its frame is, for catalogs: keys must be anchors, texts 1–120 scalars.
        var anchorAbout: [String: String] = [:]
        if let a = o["anchorAbout"] {
            guard case .object(let ao) = a else { throw MGSolidIssue("component.anchorAbout") }
            for (name, text) in ao.sorted(by: { $0.key < $1.key }) {
                guard anchors[name] != nil else { throw MGSolidIssue("component.anchorAbout") }
                anchorAbout[name] = try MGSolidParser.text(text, MGSolidComponentLimits.anchorAbout, "component.anchorAbout")
            }
        }
        if let c = o["checks"] {
            guard case .object(let co) = c, co.count <= MGSolidComponentLimits.checks else { throw MGSolidIssue("component.checks") }
            for name in co.keys.sorted() where (try? MGParser.identifier(.string(name), "")) == nil {
                throw MGSolidIssue("component.check.name.\(MGSolidParser.token(name))")
            }
        }
        // Expand at the defaults: evaluates every expression and resolves every inner reference, `set` and anchor.
        var c = MGSolidComponent(id: id, title: title, about: about, params: params, anchors: anchors, anchorAbout: anchorAbout, parts: [],
                                 uses: uses, source: json)
        var lib = library
        lib.components[id] = c
        var ctx = Context(library: lib)
        let expanded = try instance(c, with: [:], prefix: id, depth: 1, stack: [], &ctx)
        c = MGSolidComponent(id: id, title: title, about: about, params: params, anchors: anchors, anchorAbout: anchorAbout,
                             parts: expanded.parts.compactMap { p -> String? in
                                 guard case .string(let s)? = p["id"] else { return nil }
                                 return String(s.dropFirst(id.count + 1))
                             }, uses: uses, source: json)
        return c
    }

    // MARK: Expressions

    struct Context {
        let library: MGSolidLibrary
        /// Wire parts produced so far over the whole document (bounded by `MGSolidLimits.expandedParts`).
        var parts = 0
        var nodes = 0
    }

    /// True for `{"<op>": …}` with exactly one operator key.
    static func isExpr(_ v: MGJSON) -> Bool {
        guard case .object(let o) = v, o.count == 1, let k = o.keys.first else { return false }
        return ops.contains(k)
    }

    static func eval(_ v: MGJSON, _ env: [String: Double], _ depth: Int, _ ctx: inout Context) throws -> Double {
        ctx.nodes += 1
        guard ctx.nodes <= MGSolidComponentLimits.exprNodes else { throw MGSolidIssue("component.expr.size") }
        guard depth <= MGSolidComponentLimits.exprDepth else { throw MGSolidIssue("component.expr.depth") }
        let result: Double
        switch v {
        case .number(let d): result = d
        case .object(let o) where o.count == 1:
            let (op, arg) = o.first!
            func args(_ count: ClosedRange<Int>) throws -> [Double] {
                guard case .array(let a) = arg, count.contains(a.count) else { throw MGSolidIssue("component.expr.\(op)") }
                return try a.map { try eval($0, env, depth + 1, &ctx) }
            }
            func one() throws -> Double { try eval(arg, env, depth + 1, &ctx) }
            let n = MGSolidComponentLimits.exprArgs
            switch op {
            case "param":
                guard case .string(let name) = arg else { throw MGSolidIssue("component.expr.param") }
                guard let value = env[name] else { throw MGSolidIssue("component.expr.param.\(MGSolidParser.token(name))") }
                result = value
            case "add": result = try args(1...n).reduce(0, +)
            case "mul": result = try args(1...n).reduce(1, *)
            case "min": result = try args(1...n).min()!
            case "max": result = try args(1...n).max()!
            case "sub": let a = try args(2...2); result = a[0] - a[1]
            case "div":
                let a = try args(2...2)
                guard a[1] != 0 else { throw MGSolidIssue("component.expr.div") }
                result = a[0] / a[1]
            case "neg": result = -(try one())
            case "pi": result = .pi * (try one())
            case "sin": result = sin(try one() * .pi / 180)
            case "cos": result = cos(try one() * .pi / 180)
            default: throw MGSolidIssue("component.expr")
            }
        default: throw MGSolidIssue("component.expr")
        }
        guard result.isFinite, abs(result) <= MGSolidComponentLimits.value else { throw MGSolidIssue("component.expr.range") }
        return result
    }

    /// Replaces every expression in a JSON value by its number.
    static func substitute(_ v: MGJSON, _ env: [String: Double], _ ctx: inout Context) throws -> MGJSON {
        if isExpr(v) { return .number(try eval(v, env, 1, &ctx)) }
        switch v {
        case .array(let a): return .array(try a.map { try substitute($0, env, &ctx) })
        case .object(let o):
            var out: [String: MGJSON] = [:]
            for (k, x) in o.sorted(by: { $0.key < $1.key }) { out[k] = try substitute(x, env, &ctx) }
            return .object(out)
        default: return v
        }
    }

    /// Parameter values for one instance: defaults overridden by `with` (numbers in range, integers where declared).
    static func bind(_ c: MGSolidComponent, _ with: [String: MGJSON]) throws -> [String: Double] {
        var env: [String: Double] = [:]
        for p in c.params { env[p.name] = p.defaultValue }
        for (name, value) in with.sorted(by: { $0.key < $1.key }) {
            let t = MGSolidParser.token(name)
            guard let p = c.params.first(where: { $0.name == name }) else { throw MGSolidIssue("component.param.unknown.\(t)") }
            guard case .number(let d) = value, d.isFinite else { throw MGSolidIssue("component.param.value.\(t)") }
            guard d >= p.min, d <= p.max else { throw MGSolidIssue("component.param.range.\(t)") }
            guard !p.integer || d.rounded() == d else { throw MGSolidIssue("component.param.integer.\(t)") }
            env[name] = d
        }
        return env
    }

    // MARK: References

    /// Maps every part reference in a part object: `parent` and the drive sources.
    static func mapPartRefs(_ p: [String: MGJSON], _ f: (String) throws -> String) throws -> [String: MGJSON] {
        var p = p
        if case .string(let s)? = p["parent"] { p["parent"] = .string(try f(s)) }
        if case .object(let d)? = p["drive"], d.count == 1, let (kind, body) = d.first, case .object(var b) = body {
            let key = kind == "follow" ? "source" : (kind == "crankSlider" || kind == "crankRod") ? "crank" : nil
            if let key, case .string(let s)? = b[key] {
                b[key] = .string(try f(s))
                p["drive"] = .object([kind: .object(b)])
            }
        }
        return p
    }

    static func mapConstraintRefs(_ c: MGJSON, _ f: (String) throws -> String) throws -> MGJSON {
        guard case .object(let o) = c, o.count == 1, let (kind, body) = o.first else { return c }
        switch (kind, body) {
        case ("fixed", .string(let s)): return .object(["fixed": .string(try f(s))])
        case ("gearMesh", .object(var g)):
            for key in ["a", "b", "carrier"] { if case .string(let s)? = g[key] { g[key] = .string(try f(s)) } }
            return .object(["gearMesh": .object(g)])
        default: return c
        }
    }

    // MARK: Expansion

    struct Expanded {
        /// Wire parts with full ids, in document order.
        var parts: [[String: MGJSON]] = []
        /// `repeat` copies the compiler will make (`stage.planet2` → `stage.planet`).
        var copies: [String: String] = [:]
        var constraints: [MGJSON] = []
        /// Instance frames of parts that were roots of an instance placed with `at` / `rot`.
        var frames: [String: MGTransform] = [:]
        /// Anchor ids to the ids they name (full ids).
        var aliases: [String: String] = [:]
        /// Instance ids to every wire part id inside them.
        var groups: [String: [String]] = [:]

        /// Every name a reference can use (wire ids, copy ids, instance ids, anchors); expansion keeps them unique.
        var names: [String] { parts.compactMap { $0["id"]?.stringValue } + copies.keys.sorted() + groups.keys.sorted() + aliases.keys.sorted() }
        /// Ids the expansion made: wire parts and their copies. Only these may contain a dot.
        var generated: Set<String> { Set(parts.compactMap { $0["id"]?.stringValue }).union(copies.keys) }
    }

    /// One reference namespace: wire part ids, resolved `repeat` copy ids, instance (group) ids and anchors. A name used
    /// twice would make a reference ambiguous (an anchor `pin1` beside the copy `pin1`), so it is refused.
    struct Namespace {
        var names = Set<String>()
        mutating func claim(_ name: String, part: String? = nil) throws {
            guard names.insert(name).inserted else { throw MGSolidIssue("id.duplicate.\(MGSolidParser.token(name))", part: part ?? name) }
        }
    }

    /// The copy ids `repeat` will give a part (`pin` → `pin1`, `pin2`) when its count is a valid whole number; none
    /// otherwise (the assembly compiler then refuses the count).
    static func copyIDs(_ p: [String: MGJSON], _ id: String) -> [String] {
        guard case .object(let r)? = p["repeat"], case .number(let c)? = r["count"], c.rounded() == c,
              (2...Double(MGSolidLimits.repeatCount)).contains(c) else { return [] }
        return (1...Int(c)).map { id + "\($0)" }
    }

    /// Expands one component instance whose parts get ids `prefix.<inner id>`.
    static func instance(_ c: MGSolidComponent, with: [String: MGJSON], prefix: String, depth: Int, stack: [String],
                         _ ctx: inout Context) throws -> Expanded {
        do {
            guard depth <= MGSolidComponentLimits.depth else { throw MGSolidIssue("component.depth") }
            guard !stack.contains(c.id) else { throw MGSolidIssue("component.cycle.\(MGSolidParser.token(c.id))") }
            guard case .object(let def) = c.source, case .array(let entries)? = def["parts"] else { throw MGSolidIssue("component.parts.count") }
            let env = try bind(c, with)
            // Expression nodes are counted per instance (a nested instance has its own count).
            let outerNodes = ctx.nodes
            ctx.nodes = 0
            defer { ctx.nodes = outerNodes }
            if case .object(let checks)? = def["checks"] {
                for (name, check) in checks.sorted(by: { $0.key < $1.key }) {
                    guard try test(check, env, &ctx) else { throw MGSolidIssue("component.check.\(name)") }
                }
            }
            enum Item { case plain([String: MGJSON]), nested(String, [String: MGJSON], Expanded) }
            var items: [Item] = []
            // Names relative to this instance, after `repeat` (so `pin1` is a name when `pin` repeats).
            var ns = Namespace()
            var groupNames = Set<String>()
            var copies: [String: String] = [:]
            func relative(_ full: String) -> String { String(full.dropFirst(prefix.count + 1)) }
            for entry in entries {
                guard case .object(let o) = try substitute(entry, env, &ctx), case .string(let rid)? = o["id"] else { throw MGSolidIssue("component.part") }
                let full = prefix + "." + rid
                guard full.count <= MGSolidComponentLimits.idLength else { throw MGSolidIssue("component.id.length", part: full) }
                if let u = o["use"] {
                    try MGSolidParser.closed(o, ["id", "use"], useKeys, "component.use")
                    guard case .string(let uid) = u, let inner = ctx.library.components[uid] else {
                        throw MGSolidIssue("component.unknown.\(MGSolidParser.token(u.stringValue ?? "_"))", part: full)
                    }
                    let child = try instance(inner, with: try withValues(o, full), prefix: full, depth: depth + 1,
                                             stack: stack + [c.id], &ctx)
                    // Name discovery: the child's names after its `set` (which may change repeat counts), so this
                    // component can reference the copies the set makes. The ids inside `set` are mapped to this
                    // context later, in the reference phase; names do not depend on them.
                    var edited = child
                    try applySet(o, &edited, instance: full, map: { $0 })
                    for name in edited.names { try ns.claim(relative(name), part: name) }
                    for g in edited.groups.keys { groupNames.insert(relative(g)) }
                    items.append(.nested(rid, o, child))
                } else {
                    ctx.parts += 1
                    guard ctx.parts <= MGSolidLimits.expandedParts else { throw MGSolidIssue("parts.count") }
                    try ns.claim(rid, part: full)
                    for copy in copyIDs(o, rid) {
                        // The 64-character cap holds for the ids the compiler makes, repeat suffix included.
                        guard prefix.count + 1 + copy.count <= MGSolidComponentLimits.idLength else {
                            throw MGSolidIssue("component.id.length", part: prefix + "." + copy)
                        }
                        try ns.claim(copy, part: prefix + "." + copy)
                        copies[prefix + "." + copy] = full
                    }
                    items.append(.plain(o))
                }
            }
            // Anchors take names from the same namespace and name a part, a copy or a nested anchor (not a group).
            var anchors: [(String, String)] = []
            if case .object(let list)? = def["anchors"] {
                for (name, target) in list.sorted(by: { $0.key < $1.key }) {
                    guard case .string(let t) = target, ns.names.contains(t), !groupNames.contains(t),
                          !ns.names.contains(name) else { throw MGSolidIssue("component.anchor.\(MGSolidParser.token(name))") }
                    anchors.append((name, t))
                }
                for (name, _) in anchors { try ns.claim(name) }
            }
            // Inner references name inner parts only (or a nested instance's parts, copies and anchors).
            let known = ns.names
            let map: (String) throws -> String = { r in
                guard known.contains(r) else { throw MGSolidIssue("component.ref.unknown.\(MGSolidParser.token(r))") }
                return prefix + "." + r
            }
            var out = Expanded()
            out.copies = copies
            for item in items {
                switch item {
                case .plain(let o):
                    var p = try mapPartRefs(o, map)
                    guard case .string(let rid)? = o["id"] else { continue }
                    p["id"] = .string(prefix + "." + rid)
                    out.parts.append(p)
                case .nested(let rid, let o, var child):
                    try applyUse(o, &child, instance: prefix + "." + rid, map: map)
                    out.merge(child)
                }
            }
            if case .array(let list)? = def["constraints"] {
                for entry in list { out.constraints.append(try mapConstraintRefs(try substitute(entry, env, &ctx), map)) }
            }
            for (name, t) in anchors { out.aliases[prefix + "." + name] = prefix + "." + t }
            out.groups[prefix] = out.parts.compactMap { $0["id"]?.stringValue }
            return out
        } catch let e as MGSolidIssue {
            throw e.part == nil ? MGSolidIssue(e.reason, part: prefix) : e
        } catch let e as MGError {
            throw MGSolidIssue(e.reason, part: prefix)
        }
    }

    /// A component check: `{"lt": [a, b]}`, `{"le": [a, b]}` or `{"int": a}` (a whole number).
    static func test(_ check: MGJSON, _ env: [String: Double], _ ctx: inout Context) throws -> Bool {
        guard case .object(let o) = check, o.count == 1, let (kind, arg) = o.first else { throw MGSolidIssue("component.check") }
        switch (kind, arg) {
        case ("lt", .array(let a)) where a.count == 2: return try eval(a[0], env, 1, &ctx) < eval(a[1], env, 1, &ctx)
        case ("le", .array(let a)) where a.count == 2: return try eval(a[0], env, 1, &ctx) <= eval(a[1], env, 1, &ctx)
        case ("int", _): let v = try eval(arg, env, 1, &ctx); return abs(v - v.rounded()) < 1e-9
        default: throw MGSolidIssue("component.check")
        }
    }

    static func withValues(_ o: [String: MGJSON], _ part: String) throws -> [String: MGJSON] {
        guard let w = o["with"] else { return [:] }
        guard case .object(let wo) = w else { throw MGSolidIssue("component.with", part: part) }
        return wo
    }

    /// Applies a `use` entry's `set`, `parent`, `at` and `rot` to an expanded instance. `map` resolves ids written in
    /// the context of the `use` entry (the outer document's ids). `set` edits wire parts: a repeated part is edited
    /// through its base id (every copy), never one copy (`component.set.repeat.<id>`).
    static func applyUse(_ o: [String: MGJSON], _ child: inout Expanded, instance: String, map: (String) throws -> String) throws {
        try applySet(o, &child, instance: instance, map: map)
        try place(o, &child, instance: instance, map: map)
    }

    /// A `use` entry's `set`: merges fields into wire parts (refs mapped with `map`), keeps the copy list in step with
    /// edited repeat counts and checks that the instance's names stay unique.
    static func applySet(_ o: [String: MGJSON], _ child: inout Expanded, instance: String, map: (String) throws -> String) throws {
        if let s = o["set"] {
            guard case .object(let edits) = s else { throw MGSolidIssue("component.set", part: instance) }
            for (key, value) in edits.sorted(by: { $0.key < $1.key }) {
                let target = instance + "." + key
                guard let k = child.parts.firstIndex(where: { $0["id"] == .string(target) }) else {
                    let what = child.copies[target] != nil ? "repeat" : "unknown"
                    throw MGSolidIssue("component.set.\(what).\(MGSolidParser.token(key))", part: instance)
                }
                guard case .object(let fields) = value, fields["id"] == nil, fields["use"] == nil else { throw MGSolidIssue("component.set.id", part: target) }
                let mapped = try mapPartRefs(fields, map)
                for (f, v) in mapped { if v == .null { child.parts[k].removeValue(forKey: f) } else { child.parts[k][f] = v } }
                // `set` may change a repeat count: keep the copy list in step with the edited part.
                child.copies = child.copies.filter { $0.value != target }
                for copy in copyIDs(child.parts[k], key) {
                    let full = instance + "." + copy
                    guard full.count <= MGSolidComponentLimits.idLength else { throw MGSolidIssue("component.id.length", part: full) }
                    child.copies[full] = target
                }
            }
            // The edited counts must keep the namespace unique.
            var ns = Namespace()
            for name in child.names { try ns.claim(name) }
        }
    }

    /// A `use` entry's `parent`, `at` and `rot`, applied to the instance's root parts.
    static func place(_ o: [String: MGJSON], _ child: inout Expanded, instance: String, map: (String) throws -> String) throws {
        let frame = try MGSolidParser.transform(o["at"], o["rot"], "component.use")
        var parent: String?
        if let p = o["parent"] {
            guard case .string(let s) = p else { throw MGSolidIssue("component.use.parent", part: instance) }
            parent = try map(s)
        }
        for k in child.parts.indices where child.parts[k]["parent"] == nil {
            guard case .string(let id)? = child.parts[k]["id"] else { continue }
            if let parent { child.parts[k]["parent"] = .string(parent) }
            guard frame != .identity else { continue }
            child.frames[id] = frame * (child.frames[id] ?? .identity)
            // The explode offset is in the parent frame: turn it with the instance.
            if let e = child.parts[k]["explode"], let v = try? MGSolidParser.vector(e, "") {
                let r = frame.applyVector(v)
                child.parts[k]["explode"] = .array([.number(r.x), .number(r.y), .number(r.z)])
            }
        }
    }

    /// Expands every `use` entry of an assembly. Returns the plain assembly object, the instance frames, the ids
    /// the expansion generated (only those may contain a dot) and every anchor resolved to the part (or `repeat`
    /// base) id it names. An assembly without `use` entries is returned unchanged.
    static func expand(_ o: [String: MGJSON], _ library: MGSolidLibrary) throws
        -> (object: [String: MGJSON], frames: [String: MGTransform], generated: Set<String>, aliases: [String: String]) {
        guard case .array(let entries)? = o["parts"], (1...MGSolidLimits.parts).contains(entries.count),
              entries.contains(where: { $0["use"] != nil }) else { return (o, [:], [], [:]) }
        // Authored step lists keep their own limit, before groups are expanded or duplicates merged: an instance id is
        // one entry.
        if case .array(let steps)? = o["steps"] {
            for s in steps {
                for key in stepListKeys {
                    if case .array(let ids)? = s[key], ids.count > MGSolidLimits.idsPerStep { throw MGSolidIssue("step.\(key)") }
                }
                if case .array(let ids)? = s["section"]?["parts"], ids.count > MGSolidLimits.idsPerStep { throw MGSolidIssue("step.section.parts") }
            }
        }
        // One namespace over the whole document. Authored ids must be plain identifiers here, so an authored part can
        // never take a dotted id the expansion makes (`p.hub`); provenance is never inferred from a dot.
        var ns = Namespace()
        for e in entries where e["use"] == nil {
            guard case .object(let eo) = e, let idValue = eo["id"] else { continue }
            guard let id = try? MGParser.identifier(idValue, "") else { throw MGSolidIssue("part.id") }
            try ns.claim(id)
            for copy in copyIDs(eo, id) { try ns.claim(copy) }
        }
        var ctx = Context(library: library)
        var out = Expanded()
        var parts: [MGJSON] = []
        for e in entries {
            guard case .object(let eo) = e, let u = eo["use"] else {
                ctx.parts += 1
                guard ctx.parts <= MGSolidLimits.expandedParts else { throw MGSolidIssue("parts.count") }
                parts.append(e)
                continue
            }
            let id: String
            do { id = try MGParser.identifier(eo["id"] ?? .null, "part.id") } catch { throw MGSolidIssue("part.id") }
            guard !ns.names.contains(id) else { throw MGSolidIssue("id.duplicate.\(id)", part: id) }
            do {
                try MGSolidParser.closed(eo, ["id", "use"], o["v"] == .number(2) ? useKeysV2 : useKeys, "component.use")
                guard case .string(let cid) = u, let c = library.components[cid] else {
                    throw MGSolidIssue("component.unknown.\(MGSolidParser.token(u.stringValue ?? "_"))")
                }
                var child = try instance(c, with: try withValues(eo, id), prefix: id, depth: 1, stack: [], &ctx)
                try applySet(eo, &child, instance: id, map: { $0 })
                // v2 `explode` on the instance: one offset (in the instance's parent frame, like a part's `explode`) added
                // to the explode of every root part of the instance, so the whole instance moves out together; inner
                // parts ride on their roots and keep their own explode.
                let roots = child.parts.filter { $0["parent"] == nil }.compactMap { $0["id"]?.stringValue }
                try place(eo, &child, instance: id, map: { $0 })
                if let e = eo["explode"] {
                    let v = try MGSolidParser.vector(e, "component.use.explode")
                    for k in child.parts.indices {
                        guard let pid = child.parts[k]["id"]?.stringValue, roots.contains(pid) else { continue }
                        let own = try child.parts[k]["explode"].map { try MGSolidParser.vector($0, "component.use.explode") } ?? .zero
                        let sum = own + v
                        child.parts[k]["explode"] = .array([.number(sum.x), .number(sum.y), .number(sum.z)])
                    }
                }
                for name in child.names { try ns.claim(name) }
                parts += child.parts.map { .object($0) }
                out.merge(child)
            } catch let e as MGSolidIssue {
                throw e.part == nil ? MGSolidIssue(e.reason, part: id) : e
            } catch let e as MGError {
                throw MGSolidIssue(e.reason, part: id)
            }
        }
        // Anchors resolve to their parts everywhere; an instance id names a group, which only steps may highlight.
        func resolve(_ r: String) throws -> String {
            var cur = r
            for _ in 0...MGSolidComponentLimits.depth { guard let a = out.aliases[cur] else { break }; cur = a }
            guard out.groups[cur] == nil else { throw MGSolidIssue("ref.component.\(MGSolidParser.token(cur))") }
            return cur
        }
        var result = o
        result["parts"] = .array(try parts.map { p in
            guard case .object(let po) = p else { return p }
            do { return .object(try mapPartRefs(po, resolve)) } catch let e as MGSolidIssue {
                throw MGSolidIssue(e.reason, part: po["id"]?.stringValue)
            }
        })
        var constraints: [MGJSON] = []
        if let c = o["constraints"] {
            guard case .array(let list) = c, list.count + out.constraints.count <= MGSolidLimits.constraints else { throw MGSolidIssue("constraints.count") }
            constraints = list
        }
        result["constraints"] = .array(try (out.constraints + constraints).map { try mapConstraintRefs($0, resolve) })
        if case .array(let steps)? = o["steps"] {
            // Step part lists: an anchor names its part, an instance id names every part of the instance (one authored
            // entry, counted above), duplicates merge (first kept).
            func expandList(_ ids: [MGJSON]) -> [MGJSON] {
                var list: [MGJSON] = [], seen = Set<String>()
                for v in ids {
                    guard case .string(let id) = v else { list.append(v); continue }
                    var cur = id
                    for _ in 0...MGSolidComponentLimits.depth { guard let a = out.aliases[cur] else { break }; cur = a }
                    let names = out.groups[cur] ?? [cur]
                    for n in names where seen.insert(n).inserted { list.append(.string(n)) }
                }
                return list
            }
            result["steps"] = .array(steps.map { s in
                guard case .object(var so) = s else { return s }
                for key in stepListKeys {
                    guard case .array(let ids)? = so[key] else { continue }
                    so[key] = .array(expandList(ids))
                }
                if case .object(var sec)? = so["section"], case .array(let ids)? = sec["parts"] {
                    sec["parts"] = .array(expandList(ids))
                    so["section"] = .object(sec)
                }
                return .object(so)
            })
        }
        var aliases: [String: String] = [:]
        for key in out.aliases.keys.sorted() { aliases[key] = try resolve(key) }
        return (result, out.frames, out.generated, aliases)
    }
}

extension MGSolidComponents.Expanded {
    mutating func merge(_ o: MGSolidComponents.Expanded) {
        parts += o.parts
        copies.merge(o.copies) { a, _ in a }
        constraints += o.constraints
        frames.merge(o.frames) { a, _ in a }
        aliases.merge(o.aliases) { a, _ in a }
        groups.merge(o.groups) { a, _ in a }
    }
}

extension MGJSON {
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
}
