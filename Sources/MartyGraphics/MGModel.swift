// SPDX-License-Identifier: Apache-2.0
import Foundation

// MartyGraphics scene model. Pure value types: no I/O, no app types, no provider calls.
// World coordinates: x right, y UP, origin bottom-left; z toward the viewer (3D only). Units are "world units";
// templates map physical metres/newtons into them with one consistent scale per scene.

public struct MGPoint: Equatable, Hashable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    public static let zero = MGPoint(0, 0)
    public static func + (a: MGPoint, b: MGPoint) -> MGPoint { .init(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: MGPoint, b: MGPoint) -> MGPoint { .init(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: MGPoint, s: Double) -> MGPoint { .init(a.x * s, a.y * s, a.z * s) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    /// Unit vector at `degrees` counter-clockwise from +x in the xy plane.
    public static func polar(_ degrees: Double, _ r: Double = 1) -> MGPoint {
        let a = degrees * .pi / 180; return .init(cos(a) * r, sin(a) * r)
    }
    public func lerp(_ b: MGPoint, _ t: Double) -> MGPoint { self + (b - self) * t }
}

/// Semantic colour classes. The theme maps each to a dark-board-friendly colour.
public enum MGColorRole: String, CaseIterable, Sendable {
    case force, normal, friction, gravity, tension, velocity, accel, energy, kinetic, potential
    case accent, muted, good, warn, blue, red, green, orange, purple, yellow, teal, white
}

public enum MGKind: String, CaseIterable, Sendable {
    case body, incline, line, vector, axes, plot, spring, pulley, rope, orbit, text, highlight, bars, path
    case array, node, edge
    /// Additive 2D kinds: a small grid of short text cells and a filled closed polygon. Both are 2D only.
    case table, region
    /// Kinds the 3D renderer draws. Others make a 3D scene invalid (fail safe instead of silently missing parts).
    public static let in3D: Set<MGKind> = [.body, .incline, .line, .vector, .axes, .orbit, .text, .highlight, .path]
}

public struct MGBar: Equatable, Sendable {
    public var label: String; public var value: Double; public var color: MGColorRole
    public init(label: String, value: Double, color: MGColorRole) { self.label = label; self.value = value; self.color = color }
}
public struct MGPointer: Equatable, Sendable {
    /// Cell index as a Double so pointer moves can animate between cells.
    public var index: Double; public var label: String
    public init(index: Double, label: String) { self.index = index; self.label = label }
}

/// One drawable item. Kind-specific geometry lives in a few generic slots so patches, blends and steps
/// treat every kind the same way. `MGParser` is the only producer and fully validates each slot per kind.
public struct MGItem: Equatable, Identifiable, Sendable {
    public let id: String
    public var kind: MGKind
    /// at | from,to | polyline points, depending on kind.
    public var pts: [MGPoint] = []
    /// Numeric properties: size, angle, len, r, w, h, base, coils, cell, moveT, xr0... (validated per kind).
    public var num: [String: Double] = [:]
    public var label: String?
    public var text: String?
    public var color: MGColorRole
    /// body id for `vector.on`, target for `highlight`, node ids for `edge`.
    public var ref: String?
    public var ref2: String?
    /// ball, dashed, ground, callout, title, dir, dir3
    public var flags: Set<String> = []
    /// array cell values or axis labels [x, y].
    public var list: [String] = []
    public var bars: [MGBar] = []
    public var pointers: [MGPointer] = []
    public var marked: [Int] = []
    /// 3D direction for vectors in 3D scenes.
    public var dir: MGPoint?

    /// Templates build items with this (or `MGMake`); the parser re-validates every slot with the wire rules.
    public init(id: String, kind: MGKind, color: MGColorRole) { self.id = id; self.kind = kind; self.color = color }

    public func n(_ key: String, _ fallback: Double = 0) -> Double { num[key] ?? fallback }
    public func has(_ flag: String) -> Bool { flags.contains(flag) }
}

public struct MGCamera: Equatable, Sendable {
    /// 2D: centre in world units (nil = world centre) and zoom. 3D: yaw/pitch in degrees around the scene.
    public var x: Double?, y: Double?
    public var zoom: Double = 1, yaw: Double = 25, pitch: Double = 20
    public init(x: Double? = nil, y: Double? = nil, zoom: Double = 1, yaw: Double = 25, pitch: Double = 20) {
        self.x = x; self.y = y; self.zoom = zoom; self.yaw = yaw; self.pitch = pitch
    }
}

/// A resolved item edit used by steps and template overrides: same keys and validation as the wire format.
public struct MGEdit: Equatable, Sendable {
    public let id: String; public let key: String; public let value: MGJSON
    public init(id: String, key: String, value: MGJSON) { self.id = id; self.key = key; self.value = value }
}

public struct MGStep: Equatable, Sendable {
    public var say: String
    public var show: [String] = []
    public var focus: String?
    public var camera: MGCamera?
    /// Applied cumulatively when moving forward (code animations: move a pointer, mark a cell).
    public var edits: [MGEdit] = []
    public init(say: String, show: [String] = [], focus: String? = nil, camera: MGCamera? = nil, edits: [MGEdit] = []) {
        self.say = say; self.show = show; self.focus = focus; self.camera = camera; self.edits = edits
    }
}

/// Locally computed number shown through `{name}` placeholders.
public struct MGValue: Equatable, Sendable {
    public let value: Double; public let unit: String
    public init(value: Double, unit: String) { self.value = value; self.unit = unit }
    public var text: String { MGPhysics.format(value, unit: unit) }
}

/// Template-driven motion. Every case is evaluated by `MGTimeline.frame`, never by the model.
public enum MGMotion: Equatable, Sendable {
    public struct Slide: Equatable, Sendable {
        public let id: String; public let dir: MGPoint; public let accel: Double
        public init(id: String, dir: MGPoint, accel: Double) { self.id = id; self.dir = dir; self.accel = accel }
    }
    case none
    /// Bodies accelerate from rest along `dir` for `travel` seconds, hold, then loop.
    case slide([Slide], travel: Double, hold: Double)
    case orbit(id: String, center: MGPoint, period: Double, rotating: [String])
    /// Ball follows x = vx t, y = vy0 t − ½ g t² in world units (already scaled), with live velocity components.
    case projectile(id: String, vx: Double, vy0: Double, g: Double, flight: Double, visual: Double, hold: Double,
                    vxVector: String?, vyVector: String?, vectorScale: Double)
    /// Block released from maximum compression; energy bars split ½kx² live.
    case oscillate(id: String, amplitude: Double, period: Double, energy: Double, bars: String?, vector: String?, vectorLength: Double)
}

/// A validated, resolved scene: everything a renderer needs. Create with `MGScene.parse` or `MGTemplates`.
public struct MGScene: Equatable, Sendable {
    /// Canonical JSON of the validated wire scene. Patches rewrite this and re-validate from scratch.
    public let source: MGJSON
    public let template: String?
    public let title: String
    public let is3D: Bool
    public let width: Double, height: Double
    public let items: [MGItem]
    public let steps: [MGStep]
    public let camera: MGCamera?
    public let values: [String: MGValue]
    public let motion: MGMotion
    /// spring/rope id -> body id whose motion drags the item's last point.
    public let attachments: [String: String]
    /// Step to open on (a patch can jump to a step); view hint only.
    public var startStep: Int = 0
    /// Number of patches applied. A patch may name `"rev"`; a stale one (made against an older revision) is refused.
    public var revision: Int = 0
    /// Engine values the template marks as data the author gave (`MGTemplateBuild.builtValues`): tier Built ("Data as
    /// given") instead of Solved in an explainer legend. Empty for every built-in template.
    public internal(set) var builtValues: Set<String> = []

    public func item(_ id: String) -> MGItem? { items.first { $0.id == id } }
    public var animates: Bool { motion != .none || items.contains { $0.num["moveT"] != nil } }
}

/// Minimal immutable JSON value so scenes stay Equatable/Sendable and canonical-encodable.
///
/// Nesting: every public entry point that takes a value built in code (`MGParser.scene(json:)`, `MGPatch.parse(json:)`,
/// `MGScene.applying`, `MGTemplate.validate`, `MGLesson.parse(json:)`, lesson `apply`, `restore`, the Solid parsers)
/// first runs one walk that does not recurse (`measure`) and refuses a value that nests deeper than `MGLimits.depth`
/// (64) before it reads, compares, hashes or encodes it. Entry points that take JSON text count its nesting
/// (`utf8Nesting`) before the system parser runs; JSON `Data` must be UTF-8. `canonicalData` and `canonicalByteCount` never encode a deeper value.
/// Swift itself compares, hashes and frees nested enum values recursively, and so does `any`: a host that builds a much
/// deeper value in code should give it to an entry point (which refuses it) and not compare, hash or convert it itself.
public indirect enum MGJSON: Equatable, Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([MGJSON]), object([String: MGJSON])

    /// Converts a Foundation value (for example `JSONSerialization` output). Nil for any other type, a non-finite
    /// number, or nesting deeper than `MGLimits.depth`, so the conversion itself is bounded.
    public init?(any value: Any?) { self.init(any: value, level: 0) }

    private init?(any value: Any?, level: Int) {
        switch value {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else { guard n.doubleValue.isFinite else { return nil }; self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]:
            guard level < MGLimits.depth else { return nil }
            var out: [MGJSON] = []; out.reserveCapacity(a.count)
            for v in a { guard let j = MGJSON(any: v, level: level + 1) else { return nil }; out.append(j) }
            self = .array(out)
        case let o as [String: Any]:
            guard level < MGLimits.depth else { return nil }
            var out: [String: MGJSON] = [:]
            for (k, v) in o { guard let j = MGJSON(any: v, level: level + 1) else { return nil }; out[k] = j }
            self = .object(out)
        default: return nil
        }
    }
    /// The Foundation form (for `JSONSerialization`). It recurses once per level of nesting (see the type's note).
    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }
    /// True when every number in the value is finite. A value built in code can hold NaN or an infinity, which JSON
    /// cannot encode (the system encoder raises an exception that Swift cannot catch), so check before encoding.
    public var isEncodable: Bool { measure().finite }
    /// Nesting of UTF-8 JSON `Data`, or nil when the bytes are not UTF-8 JSON text: they are not valid UTF-8, or they
    /// hold a raw NUL byte (valid UTF-8 JSON never does, and UTF-16 or UTF-32 text with any bracket or quote always
    /// does). The system parser also reads UTF-16 and UTF-32, which the byte counter cannot read, so every `Data` entry
    /// point refuses such text (with its `json` reason) before the parser runs.
    static func utf8Nesting(_ data: Data) -> Int? {
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil else { return nil }
        return textNesting(data)
    }

    /// The first check of a `Data` entry point, before the system parser: `json` when the bytes are not UTF-8 JSON
    /// text (`utf8Nesting`), `depth` when the text nests deeper than `maxDepth`, else nil.
    static func dataRefusal(_ data: Data, maxDepth: Int = MGLimits.depth, json: String, depth: String) -> String? {
        guard let nesting = utf8Nesting(data) else { return json }
        return nesting <= maxDepth ? nil : depth
    }

    /// Nesting of UTF-8 JSON text (arrays and objects on one path), counted in one pass without parsing; brackets
    /// inside strings do not count. Use `utf8Nesting` for `Data` from a host: this counter reads UTF-8 only.
    static func textNesting<S: Sequence>(_ bytes: S) -> Int where S.Element == UInt8 {
        var depth = 0, deepest = 0, inString = false, escape = false
        for b in bytes {
            if inString {
                if escape { escape = false } else if b == UInt8(ascii: "\\") { escape = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1; deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
            default: break
            }
        }
        return deepest
    }
    /// Sorted-key JSON: stable cache keys and byte limits. Empty when the value is not encodable (a non-finite number,
    /// or nesting deeper than `MGLimits.depth`); use `canonicalByteCount` for limits, so such a value never counts as small.
    public var canonicalData: Data { encoded ?? Data() }
    /// Canonical size in bytes for limit checks. `Int.max` when the value is not encoded (a non-finite number, or
    /// nesting deeper than `MGLimits.depth`), so a bound check refuses it as over the limit.
    public var canonicalByteCount: Int { encoded?.count ?? Int.max }
    private var encoded: Data? {
        // The encoder recurses once per level: check the nesting first, with a walk that does not recurse.
        let m = measure()
        guard m.finite, m.depth <= MGLimits.depth else { return nil }
        return try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    }

    /// What one walk over a value found (`measure`).
    struct Measure: Equatable {
        /// Lower bound of the canonical JSON size: strings, keys, brackets and commas; every other value counts at least
        /// one byte.
        var bytes = 0
        /// Nesting: the most arrays and objects on one path from the root. A scalar is 0; `[]`, `[1]` and `{"a":1}` are
        /// 1; `[[1]]` is 2. The system JSON parser limits this number.
        var depth = 0
        /// False when a number is NaN or infinite.
        var finite = true
        /// True when the walk stopped because `bytes` passed `stopAbove`. Then `depth` and `finite` cover only the
        /// nodes visited, so check the size first.
        var stopped = false
    }

    /// One walk with an explicit stack, so no nesting can exhaust the call stack. Its time and memory are linear in the
    /// value's size. Without `stopAbove` it visits every node, so the result does not depend on dictionary order.
    func measure(stopAbove limit: Int = .max) -> Measure {
        var m = Measure()
        var stack: [(value: MGJSON, level: Int)] = [(self, 0)]
        while let item = stack.popLast() {
            if m.bytes > limit { m.stopped = true; break }
            switch item.value {
            case .null, .bool: m.bytes += 4
            case .number(let d): m.bytes += 1; if !d.isFinite { m.finite = false }
            case .string(let s): m.bytes += s.utf8.count + 2
            case .array(let a):
                m.depth = max(m.depth, item.level + 1)
                m.bytes += 1 + max(1, a.count)   // brackets and commas
                if m.bytes <= limit { for v in a { stack.append((v, item.level + 1)) } }
            case .object(let o):
                m.depth = max(m.depth, item.level + 1)
                m.bytes += 1 + max(1, o.count)
                for (k, v) in o {
                    if m.bytes > limit { break }
                    m.bytes += k.utf8.count + 3; stack.append((v, item.level + 1))
                }
            }
        }
        if m.bytes > limit { m.stopped = true }
        return m
    }

    /// The first check of a public entry point, before it reads, compares or encodes a value built in code. Reasons, in
    /// this order: `number` (a NaN or infinite number), `depth` (nesting over `maxDepth`), `bytes` (canonical size over
    /// `maxBytes`; the lower bound is checked first, so a huge value is never encoded). Only a value at most
    /// `maxDepth` deep reaches the (recursive) encoder.
    /// True when the value nests deeper than `MGLimits.depth` (one walk that does not recurse).
    var nestsTooDeep: Bool { measure().depth > MGLimits.depth }

    func checkEntry(maxDepth: Int, maxBytes: Int, number: String, depth: String, bytes: String) throws {
        let m = measure()
        guard m.finite else { throw MGError(number) }
        guard m.depth <= maxDepth else { throw MGError(depth) }
        guard m.bytes <= maxBytes, canonicalByteCount <= maxBytes else { throw MGError(bytes) }
    }
    public var canonicalString: String { String(decoding: canonicalData, as: UTF8.self) }
    public subscript(key: String) -> MGJSON? { if case .object(let o) = self { return o[key] }; return nil }
    public var objectValue: [String: MGJSON]? { if case .object(let o) = self { return o }; return nil }
}
