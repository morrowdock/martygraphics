// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Progressive parser for a scene that is still streaming in from a fast model.
///
/// Feed raw text chunks of the scene JSON as they arrive. As soon as something renderable is complete, `feed` returns a
/// preview scene: a template scene renders in full the moment `template` and `params` close; a full scene grows item by
/// item (each complete item is validated on its own and shown once its references resolve). Steps join when complete.
/// `finish()` runs the strict parser on the whole text, so the final scene is exactly what a non-streamed parse gives.
/// If the final parse fails, callers must drop the preview (fail safe).
///
/// Recommended field order for early previews: v, template, params | dim, world, title, items, steps.
public struct MGStreamParser {
    public private(set) var text = ""
    private var accepted: [MGJSON] = []
    private var pending: [MGJSON] = []
    private var seenItems = 0
    private var lastPreview: MGJSON?
    public init() {}

    /// Returns a new preview when the renderable part changed, else nil.
    public mutating func feed(_ chunk: String) -> MGScene? {
        text += chunk
        guard text.utf8.count <= MGLimits.sceneBytes * 2 else { return nil }
        let members = Self.members(Array(text.utf8))
        var root: [String: MGJSON] = [:]
        var itemsRaw: [UInt8]?
        for m in members {
            if m.key == "items" { itemsRaw = m.raw; continue }
            guard m.complete, let j = Self.json(m.raw) else { continue }
            root[m.key] = j
        }
        guard root["v"] != nil || root["template"] != nil else { return nil }
        // Only version 1 previews; any other complete version is refused by `finish()`, so never preview it.
        if let v = root["v"], v != .number(1) { return nil }
        root["v"] = .number(1)
        if let itemsRaw {
            let elements = Self.elements(itemsRaw)
            if elements.count > seenItems {
                for e in elements[seenItems...] { if let j = Self.json(e) { pending.append(j) } }
                seenItems = elements.count
            }
        }
        if root["template"] != nil {
            guard root["params"] != nil else { return nil }
            root["items"] = nil
            root["steps"] = root["steps"]  // only present once complete
        } else {
            // Grow the accepted list: an item is accepted once the scene parses with it (references resolved).
            var progress = true
            while progress {
                progress = false
                for (k, candidate) in pending.enumerated() {
                    var trial = root; trial["items"] = .array(accepted + [candidate]); trial["steps"] = nil
                    if case .success = MGParser.scene(json: .object(trial)) { accepted.append(candidate); pending.remove(at: k); progress = true; break }
                }
            }
            guard !accepted.isEmpty else { return nil }
            root["items"] = .array(accepted)
            if root["steps"] != nil, case .failure = MGParser.scene(json: .object(root)) { root["steps"] = nil }
        }
        let preview = MGJSON.object(root)
        guard preview != lastPreview, case .success(let scene) = MGParser.scene(json: preview) else { return nil }
        lastPreview = preview
        return scene
    }

    /// Strict final parse of everything received.
    public func finish() -> Result<MGScene, MGError> { MGParser.scene(data: Data(text.utf8)) }

    // MARK: tolerant scanning (never trusted for the final result)

    struct Member { let key: String; let raw: [UInt8]; let complete: Bool }

    /// Top-level members of a possibly truncated JSON object, with each value's raw bytes and whether it closed.
    static func members(_ b: [UInt8]) -> [Member] {
        var i = 0, out: [Member] = []
        func ws() { while i < b.count, [0x20, 0x0A, 0x0D, 0x09].contains(b[i]) { i += 1 } }
        ws(); guard i < b.count, b[i] == UInt8(ascii: "{") else { return [] }; i += 1
        while true {
            ws(); guard i < b.count else { return out }
            if b[i] == UInt8(ascii: "}") { return out }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            guard b[i] == UInt8(ascii: "\"") else { return out }
            guard let keyEnd = stringEnd(b, i) else { return out }
            let key = String(decoding: b[(i + 1)..<keyEnd], as: UTF8.self); i = keyEnd + 1
            ws(); guard i < b.count, b[i] == UInt8(ascii: ":") else { return out }; i += 1; ws()
            guard i < b.count else { return out }
            let start = i
            if let end = valueEnd(b, i) { out.append(.init(key: key, raw: Array(b[start..<end]), complete: true)); i = end }
            else { out.append(.init(key: key, raw: Array(b[start...]), complete: false)); return out }
        }
    }

    /// Complete elements of a possibly truncated JSON array.
    static func elements(_ b: [UInt8]) -> [[UInt8]] {
        var i = 0, out: [[UInt8]] = []
        guard !b.isEmpty, b[0] == UInt8(ascii: "[") else { return [] }; i = 1
        while i < b.count {
            while i < b.count, [0x20, 0x0A, 0x0D, 0x09, UInt8(ascii: ",")].contains(b[i]) { i += 1 }
            guard i < b.count, b[i] != UInt8(ascii: "]") else { break }
            guard let end = valueEnd(b, i) else { break }
            out.append(Array(b[i..<end])); i = end
        }
        return out
    }

    static func stringEnd(_ b: [UInt8], _ start: Int) -> Int? {
        var i = start + 1
        while i < b.count { if b[i] == UInt8(ascii: "\\") { i += 2; continue }; if b[i] == UInt8(ascii: "\"") { return i }; i += 1 }
        return nil
    }

    /// End index (exclusive) of the value starting at `start`, or nil if it is not complete yet.
    static func valueEnd(_ b: [UInt8], _ start: Int) -> Int? {
        let c = b[start]
        if c == UInt8(ascii: "\"") { return stringEnd(b, start).map { $0 + 1 } }
        if c == UInt8(ascii: "{") || c == UInt8(ascii: "[") {
            var depth = 0, i = start
            while i < b.count {
                let x = b[i]
                if x == UInt8(ascii: "\"") { guard let e = stringEnd(b, i) else { return nil }; i = e + 1; continue }
                if x == UInt8(ascii: "{") || x == UInt8(ascii: "[") { depth += 1 }
                if x == UInt8(ascii: "}") || x == UInt8(ascii: "]") { depth -= 1; if depth == 0 { return i + 1 } }
                i += 1
            }
            return nil
        }
        // Number or literal: complete only once a delimiter follows.
        var i = start
        while i < b.count, ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x0A, 0x0D, 0x09].contains(b[i]) { i += 1 }
        return i < b.count ? i : nil
    }

    static func json(_ raw: [UInt8]) -> MGJSON? {
        guard MGJSON.textNesting(raw) <= MGLimits.depth else { return nil }   // before the recursive system parser
        guard let o = try? JSONSerialization.jsonObject(with: Data(raw), options: [.fragmentsAllowed]) else { return nil }
        return MGJSON(any: o)
    }
}
