// SPDX-License-Identifier: Apache-2.0
import Foundation

/// What a template produces before the parser layers the model's extras, hides, overrides, steps and title on top.
public struct MGTemplateBuild {
    public init(title: String, width: Double = 12, height: Double = 8, items: [MGItem] = [], steps: [MGStep] = [],
                values: [String: MGValue] = [:], motion: MGMotion = .none, attachments: [String: String] = [:], camera: MGCamera? = nil) {
        self.title = title; self.width = width; self.height = height; self.items = items; self.steps = steps
        self.values = values; self.motion = motion; self.attachments = attachments; self.camera = camera
    }
    public var title: String
    public var width = 12.0, height = 8.0
    public var items: [MGItem] = []
    public var steps: [MGStep] = []
    public var values: [String: MGValue] = [:]
    public var motion: MGMotion = .none
    public var attachments: [String: String] = [:]
    public var camera: MGCamera?
}

public struct MGParams {
    public init(numbers: [String: Double] = [:], lists: [String: [Double]] = [:], records: [String: [[Double]]] = [:]) {
        self.numbers = numbers; self.lists = lists; self.records = records
    }
    public var numbers: [String: Double] = [:]
    public var lists: [String: [Double]] = [:]
    /// Record-list parameters: each record has exactly one value per declared field, in field order.
    public var records: [String: [[Double]]] = [:]
    public subscript(_ key: String) -> Double { numbers[key] ?? 0 }
}

/// One numeric field of a record-list parameter (for example an edge's `a`, `b` and `w`).
public struct MGParamField: Equatable, Sendable {
    public let name: String
    public let range: ClosedRange<Double>
    public let integer: Bool
    public init(_ name: String, _ range: ClosedRange<Double>, integer: Bool = false) {
        self.name = name; self.range = range; self.integer = integer
    }
    /// Field names become reason suffixes (`template.<param>.<field>`), so they may not reuse the parser's own suffixes.
    public static let reservedNames: Set<String> = ["arity", "count", "integer", "missing", "spec"]
    var doc: String {
        "\(name) \(MGPhysics.format(range.lowerBound, unit: ""))–\(MGPhysics.format(range.upperBound, unit: ""))\(integer ? " int" : "")"
    }
}

/// One template parameter: a number in a closed range (optionally integer, optionally defaulted), a short number list,
/// or a record list.
public struct MGParamSpec {
    public let name: String, unit: String
    public let range: ClosedRange<Double>
    public var defaultValue: Double? = nil
    public var integer = false
    /// Non-nil for list and record-list parameters: allowed element count.
    public var count: ClosedRange<Int>? = nil
    /// Non-nil (with `count`) for record-list parameters: each element is an array with exactly one number per field,
    /// validated against that field's own range. `range`/`integer` are unused for records. A count starting at 0 makes
    /// the parameter optional (absent = no records); number lists keep their existing rule (absent is rejected).
    public var fields: [MGParamField]? = nil
    /// A number (optionally integer, optionally defaulted; `.infinity` default = optional) or, with `count`, a number list.
    public init(name: String, unit: String, range: ClosedRange<Double>, defaultValue: Double? = nil, integer: Bool = false, count: ClosedRange<Int>? = nil) {
        self.name = name; self.unit = unit; self.range = range; self.defaultValue = defaultValue; self.integer = integer; self.count = count
    }
    /// A record-list parameter, e.g. weighted edges `[[a, b, w], ...]`. Bounded by `MGLimits.records`/`recordFields`.
    /// An out-of-contract declaration fails pack validation/registration (`MGPackError.badParamSpec`) and, if the
    /// template is parsed without registration, rejects every scene that uses it (`template.<name>.spec`).
    public static func records(_ name: String, count: ClosedRange<Int>, fields: [MGParamField]) -> MGParamSpec {
        var spec = MGParamSpec(name: name, unit: "", range: 0...0, count: count); spec.fields = fields; return spec
    }
    /// True for record lists. Record specs also set `count`, so test this before treating `count != nil` as a number list.
    public var isRecordList: Bool { fields != nil }
    public var doc: String {
        let r = "\(MGPhysics.format(range.lowerBound, unit: ""))–\(MGPhysics.format(range.upperBound, unit: ""))"
        if let fields, let count { return "\(name):[\(count.lowerBound)–\(count.upperBound) × (\(fields.map(\.doc).joined(separator: ", ")))]" }
        if let count { return "\(name):[\(count.lowerBound)–\(count.upperBound) ints \(r)]" }
        return "\(name) \(unit.isEmpty ? "" : unit + " ")\(r)" + (defaultValue.flatMap { $0.isFinite ? "=\(MGPhysics.format($0, unit: ""))" : " optional" } ?? "")
    }

    /// Why a record-list declaration is out of contract, or nil (also nil for scalar and number-list parameters, whose
    /// declarations keep their existing lazy behaviour).
    var recordDeclarationProblem: String? {
        guard let fields else { return nil }
        guard Self.declName(name) else { return "name must be 1–16 lowercase ASCII letters, digits or _, starting with a letter" }
        guard let count else { return "a record list needs a count" }
        guard count.lowerBound >= 0, count.upperBound <= MGLimits.records else { return "count must lie within 0…\(MGLimits.records)" }
        guard (1...MGLimits.recordFields).contains(fields.count) else { return "needs 1…\(MGLimits.recordFields) fields" }
        var seen = Set<String>()
        for f in fields {
            guard Self.declName(f.name) else { return "field '\(f.name)' must be 1–16 lowercase ASCII letters, digits or _, starting with a letter" }
            guard !MGParamField.reservedNames.contains(f.name) else { return "field '\(f.name)' is a reserved reason suffix" }
            guard seen.insert(f.name).inserted else { return "field '\(f.name)' is declared twice" }
            guard f.range.lowerBound.isFinite, f.range.upperBound.isFinite else { return "field '\(f.name)' needs a finite range" }
        }
        return nil
    }

    static func declName(_ s: String) -> Bool {
        guard (1...16).contains(s.count), let first = s.unicodeScalars.first, first.isASCII, CharacterSet.lowercaseLetters.contains(first) else { return false }
        return s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "_") }
    }
}

/// A parametric scene. The model sends `{"v":1,"template":name,"params":{...}}` (tens of tokens); the app builds the
/// full animated, stepped scene with local math.
public struct MGTemplate {
    public let name: String
    public let summary: String
    public let params: [MGParamSpec]
    /// Cross-parameter constraints. Returns false to reject.
    let check: (MGParams) -> Bool
    /// Specific cross-parameter diagnosis: nil accepts, otherwise a reason suffix such as `"edges.loop"`.
    let reject: (MGParams) -> String?
    let make: (MGParams, Bool) -> MGTemplateBuild?

    /// `check`: cross-parameter rules (false rejects with `template.check`). `reject`: optional specific diagnosis that
    /// runs first; a returned suffix `s` rejects with `template.<s>` (lowercase ASCII words joined by dots, at most 48
    /// characters; anything else is reported as `template.check`). `make`: build from validated params (is3D); nil
    /// rejects. Everything `make` produces is re-validated by the parser with the wire rules.
    public init(name: String, summary: String, params: [MGParamSpec], check: @escaping (MGParams) -> Bool = { _ in true },
                reject: @escaping (MGParams) -> String? = { _ in nil },
                make: @escaping (MGParams, Bool) -> MGTemplateBuild?) {
        self.name = name; self.summary = summary; self.params = params; self.check = check; self.reject = reject; self.make = make
    }

    public var doc: String { "\(name){\(params.map(\.doc).joined(separator: ", "))}: \(summary)" }

    /// Declaration problems that can be found without parsing a scene. Only record-list declarations are checked, so
    /// existing scalar/number-list templates keep their current registration behaviour.
    var declarationProblems: [String] {
        params.filter(\.isRecordList).compactMap { spec -> String? in
            if params.filter({ $0.name == spec.name }).count > 1 { return "\(spec.name): parameter name declared twice" }
            return spec.recordDeclarationProblem.map { "\(spec.name): \($0)" }
        }
    }

    /// `template.<suffix>` for a well-formed suffix, otherwise the generic `template.check`.
    static func rejection(_ suffix: String) -> String {
        let parts = suffix.split(separator: ".", omittingEmptySubsequences: false)
        let ok = suffix.count <= 48 && !parts.isEmpty && parts.allSatisfy { part in
            guard let f = part.unicodeScalars.first, f.isASCII, CharacterSet.lowercaseLetters.contains(f) else { return false }
            return part.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "_") }
        }
        return ok ? "template.\(suffix)" : "template.check"
    }

    func validate(_ raw: [String: MGJSON]) throws -> MGParams {
        let names = Set(params.map(\.name))
        guard Set(raw.keys).isSubset(of: names) else { throw MGError("template.params.unknown") }
        var out = MGParams()
        for spec in params {
            if let fields = spec.fields {
                out.records[spec.name] = try Self.records(spec, fields, raw[spec.name])
            } else if let count = spec.count {
                guard case .array(let list)? = raw[spec.name], count.contains(list.count) else { throw MGError("template.\(spec.name)") }
                out.lists[spec.name] = try list.map { v in
                    let d = try MGParser.num(v, spec.range, "template.\(spec.name)")
                    guard !spec.integer || d.rounded() == d else { throw MGError("template.\(spec.name).integer") }; return d
                }
            } else if let v = raw[spec.name] {
                let d = try MGParser.num(v, spec.range, "template.\(spec.name)")
                guard !spec.integer || d.rounded() == d else { throw MGError("template.\(spec.name).integer") }
                out.numbers[spec.name] = d
            } else if let d = spec.defaultValue {
                out.numbers[spec.name] = d
            } else { throw MGError("template.\(spec.name).missing") }
        }
        if let why = reject(out) { throw MGError(Self.rejection(why)) }
        guard check(out) else { throw MGError("template.check") }
        return out
    }

    /// Record lists: closed arity, per-field finite range and integrality. Never clamps. An absent record list is empty
    /// when its count allows 0; JSON `null` is not "absent" and is rejected like any other non-array.
    static func records(_ spec: MGParamSpec, _ fields: [MGParamField], _ value: MGJSON?) throws -> [[Double]] {
        guard spec.recordDeclarationProblem == nil, let count = spec.count else { throw MGError("template.\(spec.name).spec") }
        let list: [MGJSON]
        switch value {
        case .array(let l)?: list = l
        case nil where count.lowerBound == 0: list = []
        case nil: throw MGError("template.\(spec.name).missing")
        default: throw MGError("template.\(spec.name)")
        }
        guard count.contains(list.count) else { throw MGError("template.\(spec.name).count") }
        return try list.map { record in
            guard case .array(let values) = record, values.count == fields.count else { throw MGError("template.\(spec.name).arity") }
            return try zip(fields, values).map { field, v in
                let d = try MGParser.num(v, field.range, "template.\(spec.name).\(field.name)")
                guard !field.integer || d.rounded() == d else { throw MGError("template.\(spec.name).\(field.name).integer") }
                return d
            }
        }
    }

    /// Build after validation. Fills placeholders in template text with the computed values.
    func build(_ p: MGParams, _ is3D: Bool) -> MGTemplateBuild? { make(p, is3D) }
}

// MARK: - Item helpers (template code only; the parser re-validates every item produced here)

public enum MGMake {
    public static func body(_ id: String, _ at: MGPoint, size: Double = 1, angle: Double = 0, ball: Bool = false, label: String? = nil, color: MGColorRole = .blue) -> MGItem {
        var i = MGItem(id: id, kind: .body, color: color); i.pts = [at]; i.num = ["size": size, "angle": angle]; i.label = label
        if ball { i.flags.insert("ball") }; return i
    }
    public static func vector(_ id: String, on: String? = nil, from: MGPoint? = nil, angle: Double, len: Double, label: String?, color: MGColorRole, dashed: Bool = false) -> MGItem {
        var i = MGItem(id: id, kind: .vector, color: color); i.ref = on; if let from { i.pts = [from] }
        i.num = ["angle": angle, "len": len]; i.label = label; if dashed { i.flags.insert("dashed") }; return i
    }
    public static func line(_ id: String, _ a: MGPoint, _ b: MGPoint, style: String? = nil, color: MGColorRole = .muted) -> MGItem {
        var i = MGItem(id: id, kind: .line, color: color); i.pts = [a, b]; if let style { i.flags.insert(style) }; return i
    }
    public static func text(_ id: String, _ at: MGPoint, _ text: String, style: String? = nil, color: MGColorRole = .white) -> MGItem {
        var i = MGItem(id: id, kind: .text, color: color); i.pts = [at]; i.text = text; if let style { i.flags.insert(style) }; return i
    }
    public static func kind(_ id: String, _ kind: MGKind, _ pts: [MGPoint], _ num: [String: Double] = [:], color: MGColorRole? = nil, label: String? = nil) -> MGItem {
        var i = MGItem(id: id, kind: kind, color: color ?? MGParser.defaultColor(kind)); i.pts = pts; i.num = num; i.label = label; return i
    }
    /// Arrow length in world units, one scale per scene so arrows compare honestly. Zero stays zero.
    public static func scaled(_ value: Double, _ scale: Double) -> Double { abs(value) < 1e-9 ? 0 : max(0.35, abs(value) * scale) }
    public static func say(_ s: String, show: [String] = [], focus: String? = nil, _ values: [String: MGValue]) -> MGStep {
        MGStep(say: (try? MGParser.fill(s, values, "template")) ?? s, show: show, focus: focus)
    }
    public static func fill(_ s: String, _ values: [String: MGValue]) -> String { (try? MGParser.fill(s, values, "template")) ?? s }
    /// Visual travel time for a physical acceleration over a display distance, kept watchable (1.2–3.5 s).
    public static func travel(distance: Double, accel: Double) -> Double {
        guard accel > 1e-9 else { return 2 }; return min(3.5, max(1.2, (2 * distance / accel).squareRoot()))
    }
}

public enum MGTemplates {
    public static let all: [MGTemplate] = [bst, twoPointers]
    /// Every template from every registered pack (core first), by name.
    public static var library: [String: MGTemplate] { MGPacks.library }

    // MARK: Binary search tree
    static let bst = MGTemplate(
        name: "bst", summary: "insert values into a binary search tree in order; optional find path",
        params: [.init(name: "values", unit: "", range: -999...999, integer: true, count: 1...15),
                 .init(name: "find", unit: "", range: -999...999, defaultValue: .infinity, integer: false)],
        check: { p in Set(p.lists["values"] ?? []).count == (p.lists["values"] ?? []).count },
        make: { p, _ in
            let values = p.lists["values"] ?? []
            var left: [Int: Int] = [:], right: [Int: Int] = [:], depth: [Int] = [0]
            for i in 1..<max(values.count, 1) {
                var at = 0, d = 1
                while true {
                    if values[i] < values[at] { if let l = left[at] { at = l; d += 1 } else { left[at] = i; break } }
                    else { if let r = right[at] { at = r; d += 1 } else { right[at] = i; break } }
                }
                depth.append(d)
            }
            let maxDepth = depth.max() ?? 0
            guard maxDepth <= 6 else { return nil }
            let order = values.indices.sorted { values[$0] < values[$1] }
            let dx = values.count > 1 ? 10.4 / Double(values.count - 1) : 0
            let dy = maxDepth > 0 ? min(1.4, 5.8 / Double(maxDepth)) : 0
            var pos: [Int: MGPoint] = [:]
            for (rank, i) in order.enumerated() { pos[i] = MGPoint(values.count > 1 ? 0.8 + Double(rank) * dx : 6, 7 - Double(depth[i]) * dy) }
            var items: [MGItem] = []
            for i in values.indices {
                var n = MGMake.kind("n\(i)", .node, [pos[i]!], ["r": 0.42]); n.text = MGPhysics.format(values[i], unit: ""); items.append(n)
            }
            let edges = left.map({ ($0.key, $0.value) }) + right.map({ ($0.key, $0.value) })
            for (parent, child) in edges.sorted(by: { $0.1 < $1.1 }) {
                var e = MGItem(id: "e\(child)", kind: .edge, color: .muted); e.ref = "n\(parent)"; e.ref2 = "n\(child)"; items.append(e)
            }
            items.sort { $0.kind == .edge && $1.kind != .edge }
            let v: [String: MGValue] = ["n": .init(value: Double(values.count), unit: ""), "height": .init(value: Double(maxDepth), unit: "")]
            var steps = [MGMake.say("Insert in order. Smaller goes left, bigger or equal goes right. Height {height}.", focus: "n0", v)]
            let target = p["find"]
            if target.isFinite {
                var at: Int? = 0, k = 0
                while let node = at, k < 6 {
                    let value = values[node]
                    var h = MGItem(id: "h\(k)", kind: .highlight, color: .yellow); h.ref = "n\(node)"; items.append(h)
                    let a = MGPhysics.format(target, unit: ""), b = MGPhysics.format(value, unit: "")
                    if value == target { steps.append(MGStep(say: "\(a) = \(b). Found it in \(k + 1) comparisons.", show: ["h\(k)"], focus: "n\(node)")); break }
                    let goLeft = target < value
                    steps.append(MGStep(say: "\(a) is \(goLeft ? "smaller" : "bigger") than \(b), so go \(goLeft ? "left" : "right").", show: ["h\(k)"], focus: "n\(node)"))
                    at = goLeft ? left[node] : right[node]; k += 1
                    if at == nil { steps.append(MGStep(say: "Nothing there: \(a) isn't in the tree.")); break }
                }
            }
            return MGTemplateBuild(title: "Binary search tree", items: items, steps: Array(steps.prefix(MGLimits.steps)), values: v)
        })

    // MARK: Two pointers on a sorted array
    static let twoPointers = MGTemplate(
        name: "two_pointers", summary: "sorted array pair-sum with L/R pointers moving step by step",
        params: [.init(name: "vals", unit: "", range: -999...999, integer: true, count: 2...12),
                 .init(name: "target", unit: "", range: -1998...1998, integer: true)],
        check: { p in let a = p.lists["vals"] ?? []; return zip(a, a.dropFirst()).allSatisfy { $0 <= $1 } },
        make: { p, _ in
            let a = p.lists["vals"] ?? [], target = p["target"]
            var arr = MGMake.kind("arr", .array, [MGPoint(6, 4)], ["cell": min(0.9, 10.5 / Double(a.count))])
            arr.list = a.map { MGPhysics.format($0, unit: "") }
            arr.pointers = [MGPointer(index: 0, label: "L"), MGPointer(index: Double(a.count - 1), label: "R")]
            func ptrs(_ l: Int, _ r: Int) -> MGJSON { .array([.object(["i": .number(Double(l)), "label": .string("L")]), .object(["i": .number(Double(r)), "label": .string("R")])]) }
            let f = { (d: Double) in MGPhysics.format(d, unit: "") }
            var steps = [MGStep(say: "Find two numbers that add to \(f(target)). Start L at the smallest, R at the largest.", focus: "arr")]
            var l = 0, r = a.count - 1
            while l < r, steps.count < MGLimits.steps {
                let sum = a[l] + a[r]
                if sum == target {
                    steps.append(MGStep(say: "\(f(a[l])) + \(f(a[r])) = \(f(sum)). Found the pair.", focus: "arr",
                                        edits: [MGEdit(id: "arr", key: "marked", value: .array([.number(Double(l)), .number(Double(r))]))]))
                    break
                }
                let small = sum < target
                if small { l += 1 } else { r -= 1 }
                steps.append(MGStep(say: "\(f(a[small ? l - 1 : l])) + \(f(a[small ? r : r + 1])) = \(f(sum)) is too \(small ? "small, so move L right" : "big, so move R left").",
                                    focus: "arr", edits: [MGEdit(id: "arr", key: "ptrs", value: ptrs(l, r))]))
            }
            if l >= r, steps.count < MGLimits.steps { steps.append(MGStep(say: "The pointers met: no pair adds to \(f(target)).")) }
            let v: [String: MGValue] = ["target": .init(value: target, unit: "")]
            return MGTemplateBuild(title: "Two pointers", items: [arr, MGMake.text("goal", MGPoint(6, 6.6), "target \(f(target))", style: "callout", color: .warn)],
                                   steps: steps, values: v)
        })
}
