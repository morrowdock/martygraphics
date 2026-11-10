// SPDX-License-Identifier: Apache-2.0
import Foundation

// One id namespace and one honesty system across the 2D board and the 3D solid of an explainer: the parse environment
// (dotted names are 3D facts), number rule N1 over 2D wire text, table sub-addresses, claims and the one legend.
// Foundation only, deterministic: every first error comes from an ordered list.

/// One truth tier for 2D and 3D claims (`described < built < solved`).
public typealias MGTier = MGSolidTier

/// Internal parse environment of an explainer. With it, `MGParser` sends every `{…}` name that holds a `.` or a `|` to
/// `fill` (3D facts and modifiers) and checks text length on the filled text; the lesson session turns the D3 decimal
/// rule off (the explainer applies rule N1 first) and refuses a 2D id that equals a 3D id (`reserved`).
struct MGParseEnvironment: Sendable {
    var facts: [String: MGSolidFact] = [:]
    var aliases: [String: String] = [:]
    /// The 3D namespace: part, copy, `repeat` base, instance and anchor ids (later: annotation ids).
    var reserved: Set<String> = []

    /// Fills one placeholder body that holds `.` or `|`. A name without a dot is a 2D engine value, which takes no
    /// modifier (`text.modifier.<mod>.<name>`). A dotted name is a 3D fact (#21 grammar, formatter and reasons); `abs`
    /// is allowed only in a beat caption (`stmt.say`), where a check of the same beat must prove the sign.
    func fill(_ body: String, _ what: String) throws -> String {
        let pieces = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let name = pieces[0]
        if !name.contains(".") {
            guard pieces.count > 1, (1...16).contains(name.count),
                  name.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) else {
                throw MGError("\(what).placeholder")
            }
            let m = pieces[1]
            throw MGError(MGSolidFacts.modifierNames.contains(m) ? "text.modifier.\(m).\(name)" : "text.modifier.\(MGSolidParser.token(m))")
        }
        do {
            let (text, canonical, mods) = try MGSolidFacts.placeholder(body, facts, aliases)
            if mods.contains("abs"), what != "stmt.say" { throw MGError("text.sign.\(MGSolidParser.token(canonical))") }
            return text
        } catch let e as MGSolidIssue { throw MGError(e.reason) }
    }
}

/// One claim of an explainer, with its engine tier. Kinds: `motion` (3D part motion), `annotation` (3a), `title`,
/// `template` (the board's template values), `data` (a 2D item with a note), `caption` (a beat caption, or a 2D item
/// whose numbers all come from placeholders) and `check`.
public struct MGExplainerClaim: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case motion, annotation, title, template, data, caption, check }
    public var kind: Kind
    /// Part id (motion), `title`, `board.template`, `item.<id>`, `beat.<n>` or `beat.<n>.check.<k>` (1-based).
    public var id: String
    public var tier: MGTier
    public var badge: String
    public var why: String
}

/// The one legend of an explainer (owner D4: always shown). Groups in this order, each only when non-zero:
/// `Solved N · Schematic N · Given N · Not checked N`. `Schematic` counts Built claims of every kind except `data`;
/// `Given` counts Built `data` claims, so a 3D-only explainer's legend text equals its assembly's.
public struct MGExplainerLegend: Equatable, Sendable {
    public var claims: [MGExplainerClaim]
    public var solved: Int, schematic: Int, given: Int, described: Int
    public var text: String
    /// Engine notes, one line each: "Some motion is schematic" (a motion claim below Solved), the solid's own notes
    /// ("Arrow lengths are not to scale") and "Shapes and drawings as authored" (always).
    public var notes: [String]

    init(_ claims: [MGExplainerClaim], solidNotes: [String] = []) {
        self.claims = claims
        solved = claims.filter { $0.tier == .solved }.count
        schematic = claims.filter { $0.tier == .built && $0.kind != .data }.count
        given = claims.filter { $0.tier == .built && $0.kind == .data }.count
        described = claims.filter { $0.tier == .described }.count
        var groups: [String] = []
        if solved > 0 { groups.append("Solved \(solved)") }
        if schematic > 0 { groups.append("Schematic \(schematic)") }
        if given > 0 { groups.append("Given \(given)") }
        if described > 0 { groups.append("Not checked \(described)") }
        text = groups.isEmpty ? "No engine-checked claims" : groups.joined(separator: " · ")
        var notes: [String] = []
        if claims.contains(where: { $0.kind == .motion && $0.tier < .solved }) { notes.append("Some motion is schematic") }
        // The solid's own notes (for example "Arrow lengths are not to scale"), once each.
        for n in solidNotes where !notes.contains(n) && n != "Some motion is schematic" { notes.append(n) }
        notes.append("Shapes and drawings as authored")
        self.notes = notes
    }
}

enum MGExplainerHonesty {
    // MARK: Text

    /// The bodies of `{…}` placeholders, in order (no grammar check: the parsers check it).
    static func placeholders(_ s: String) -> [String] {
        var out: [String] = [], body = "", inside = false
        for ch in s {
            if inside { if ch == "}" { out.append(body); body = ""; inside = false } else { body.append(ch) } }
            else if ch == "{" { inside = true }
        }
        return out
    }

    /// True when a typed number character stands outside the `{…}` placeholders: rule N1 on the NFKC form of the text,
    /// where a token that exactly equals a declared name types no number (`MGSolidFacts.typedNumberOffsets`).
    static func typedNumber(_ s: String, names: Set<String>) -> Bool {
        var inside = false
        let chars = Array(s), typed = MGSolidFacts.typedNumberOffsets(chars, names: names)
        for (k, ch) in chars.enumerated() {
            if inside { if ch == "}" { inside = false }; continue }
            if ch == "{" { inside = true; continue }
            if typed.contains(k) { return true }
        }
        return false
    }

    /// True when any string in the value has a typed number.
    static func typedNumber(in v: MGJSON, names: Set<String>) -> Bool {
        var stack = [v]
        while let x = stack.popLast() {
            switch x {
            case .string(let s): if typedNumber(s, names: names) { return true }
            case .array(let a): stack += a
            case .object(let o): stack += o.keys.sorted().map { o[$0]! }
            default: break
            }
        }
        return false
    }

    /// True when any number appears in the value (a numeric display field: the renderer draws it as digits).
    static func hasNumber(_ v: MGJSON) -> Bool {
        var stack = [v]
        while let x = stack.popLast() {
            switch x {
            case .number: return true
            case .array(let a): stack += a
            case .object(let o): stack += o.values
            default: break
            }
        }
        return false
    }

    /// Item keys whose numbers the 2D renderer draws as digits: table cells, array values, bar values and plot ranges.
    static let displayKeys: Set<String> = ["cells", "vals", "bars", "xr", "yr"]
    /// Item keys that hold ids, kinds or names, never text the learner reads.
    static let nonTextKeys: Set<String> = ["id", "k", "color", "target", "a", "b", "style", "shape", "on"]

    /// True when a wire item (or one value set on it) shows author-typed numbers: a typed number in any of its text, or
    /// a number in a numeric display field.
    static func itemShowsNumbers(_ item: [String: MGJSON], names: Set<String>) -> Bool {
        for key in item.keys.sorted() where !nonTextKeys.contains(key) {
            if valueShowsNumbers(key: key, item[key]!, names: names) { return true }
        }
        return false
    }
    static func valueShowsNumbers(key: String, _ v: MGJSON, names: Set<String>) -> Bool {
        if nonTextKeys.contains(key) { return false }
        if displayKeys.contains(key), key == "bars" {
            // A bar's `value` is drawn as digits; its `label` is text.
            if case .array(let bars) = v {
                for b in bars { if b["value"].map(hasNumber) == true || b["label"].map({ typedNumber(in: $0, names: names) }) == true { return true } }
                return false
            }
        }
        if displayKeys.contains(key), hasNumber(v) { return true }
        return typedNumber(in: v, names: names)
    }

    /// Rule N1 over a 2D wire board: every item without a note shows no typed number, and neither do `over` values on
    /// items without a note. The first offender in wire order: `text.number.item.<id>`.
    static func checkBoard(_ board: [String: MGJSON], notes: [String: MGExplainer.Note], names: Set<String>) throws {
        if case .array(let items)? = board["items"] {
            for entry in items {
                guard let o = entry.objectValue, case .string(let id)? = o["id"] else { continue }
                if notes[id] == nil, itemShowsNumbers(o, names: names) { throw MGError("text.number.item.\(MGLessonIssue.segment(id))") }
            }
        }
        if case .array(let over)? = board["over"] {
            for entry in over {
                guard case .string(let id)? = entry["id"], case .string(let key)? = entry["key"], let value = entry["value"] else { continue }
                if notes[id] == nil, valueShowsNumbers(key: key, value, names: names) { throw MGError("text.number.item.\(MGLessonIssue.segment(id))") }
            }
        }
        // A raw template's free-form params can carry text the template draws.
        if let params = board["params"], typedNumber(in: params, names: names) { throw MGError("text.number.template") }
    }

    /// Rule N1 over one 2D command: `add` and `set` on an item without a note, a control label, raw template params.
    static func checkCommand(_ o: [String: MGJSON], notes: [String: MGExplainer.Note], names: Set<String>) throws {
        guard case .string(let name)? = o["op"] else { return }
        switch name {
        case "add":
            guard let item = o["item"]?.objectValue, case .string(let id)? = item["id"] else { return }
            if notes[id] == nil, itemShowsNumbers(item, names: names) { throw MGError("text.number.item.\(MGLessonIssue.segment(id))") }
        case "set":
            guard case .string(let id)? = o["id"], case .string(let key)? = o["key"], let value = o["value"] else { return }
            if notes[id] == nil, valueShowsNumbers(key: key, value, names: names) { throw MGError("text.number.item.\(MGLessonIssue.segment(id))") }
        case "bind":
            guard let c = o["control"]?.objectValue, let label = c["label"] else { return }
            if typedNumber(in: label, names: names) {
                let id = c["id"].flatMap { if case .string(let s) = $0 { return s }; return nil } ?? "_"
                throw MGError("text.number.control.\(MGLessonIssue.segment(id))")
            }
        case "params":
            if let p = o["params"], typedNumber(in: p, names: names) { throw MGError("text.number.template") }
        default: break
        }
    }

    /// True when any string in a 2D board names a 3D fact (`{a.b}`): such a board must come after the solid.
    static func usesFacts(_ v: MGJSON) -> Bool {
        var stack = [v]
        while let x = stack.popLast() {
            switch x {
            case .string(let s): if placeholders(s).contains(where: { $0.contains(".") }) { return true }
            case .array(let a): stack += a
            case .object(let o): stack += o.values
            default: break
            }
        }
        return false
    }

    // MARK: Namespace

    /// The 3D namespace in canonical order: for each resolved part, its component instance ids (outermost first), its
    /// `repeat` base id and its own id; then anchor names, sorted; then annotation ids in authored order.
    static func ids3D(_ doc: MGSolidDocument) -> [String] {
        var out: [String] = [], seen = Set<String>()
        func add(_ s: String) { if seen.insert(s).inserted { out.append(s) } }
        for p in doc.assembly.parts {
            let parts = p.id.split(separator: ".").map(String.init)
            if parts.count > 1 { for i in 1..<parts.count { add(parts[0..<i].joined(separator: ".")) } }
            if let base = doc.copies[p.id] { add(base) }
            add(p.id)
        }
        for a in doc.aliases.keys.sorted() { add(a) }
        // 3D annotation ids (PR 3a): labels, arrows, dimensions, in authored order.
        for a in doc.annotations.ids { add(a) }
        return out
    }

    /// Part ids a 3D namespace member stands for: itself, every copy of a `repeat` base, every part of an instance, or
    /// the part an anchor names. nil for a name that is not a 3D member.
    static func parts3D(_ id: String, _ doc: MGSolidDocument) -> [String]? {
        if doc.assembly.part(id) != nil { return [id] }
        let target = doc.aliases[id] ?? id
        if doc.assembly.part(target) != nil { return [target] }
        let copies = doc.assembly.parts.filter { doc.copies[$0.id] == target }.map(\.id)
        if !copies.isEmpty { return copies }
        let inside = doc.assembly.parts.filter { $0.id.hasPrefix(target + ".") }.map(\.id)
        return inside.isEmpty ? nil : inside
    }

    /// A table sub-address `<table>.r<k>` or `<table>.r<k>c<j>` (decimal, no sign, no leading zero) inside the table's
    /// current size: (table id, row, column or nil). nil when the text is not one.
    static func subAddress(_ id: String, _ scene: MGScene) -> (table: String, row: Int, column: Int?)? {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        let table = String(id[..<dot]), tail = Array(id[id.index(after: dot)...])
        guard let item = scene.item(table), item.kind == .table, tail.first == "r" else { return nil }
        func number(_ s: ArraySlice<Character>) -> Int? {
            guard !s.isEmpty, s.count <= 2, s.allSatisfy({ $0.isASCII && $0.isNumber }), !(s.count > 1 && s.first == "0") else { return nil }
            return Int(String(s))
        }
        let rest = tail.dropFirst()
        let rows = Int(item.n("rows", 0)), cols = Int(item.n("cols", 0))
        if let c = rest.firstIndex(of: "c") {
            guard let r = number(rest[rest.startIndex..<c]), let k = number(rest[(c + 1)...]), r < rows, k < cols else { return nil }
            return (table, r, k)
        }
        guard let r = number(rest), r < rows else { return nil }
        return (table, r, nil)
    }
}
