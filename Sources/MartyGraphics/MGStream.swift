// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Progressive parser for a scene that is still streaming in from a fast model.
///
/// Feed raw text chunks of the scene JSON as they arrive. As soon as something renderable is complete, `feed` returns a
/// preview scene: a template scene renders once `v`, `template` and `params` are complete; a full scene grows item by
/// item (each complete item is validated on its own and shown once its references resolve). Steps join when complete.
/// `finish()` runs the strict parser on the whole text, so the final scene is exactly what a non-streamed parse gives.
/// If the final parse fails, callers must drop the preview (fail safe).
/// The stream accepts up to 16 KiB of UTF-8, matching the strict parser's input limit. After an overflow,
/// `finish()` refuses the stream and a new parser is needed. Preview candidates are limited to `MGLimits.items`.
///
/// Recommended field order for early previews: v, template, params | dim, world, title, items, steps.
public struct MGStreamParser {
    private static let inputBytes = MGLimits.sceneBytes * 2
    public private(set) var text = ""
    private var overflowed = false
    private var previewItemLimitExceeded = false
    private var accepted: [MGJSON] = []
    private var pending: [MGJSON] = []
    private var seenItems = 0
    private var trialRoot: [String: MGJSON]?
    private(set) var candidateValidationCount = 0
    /// Full parses of a preview root (the `steps` trial and the preview itself), for tests.
    private(set) var previewValidationCount = 0
    private var lastPreview: MGJSON?
    /// The complete top-level members and the number of complete `items` elements of the last call. A chunk that
    /// completes nothing new (white space, part of a value) cannot change the preview, so `feed` stops there.
    private var lastShape: Shape?
    /// The last root the `steps` trial ran on, and whether it passed.
    private var stepsTrial: (root: MGJSON, passed: Bool)?
    /// The last preview root that did not parse, so the same root is not parsed again.
    private var refusedPreview: MGJSON?
    public init() {}

    struct Shape: Equatable {
        let members: [Member]
        let items: Int
    }

    /// Returns a new preview when the renderable part changed, else nil.
    public mutating func feed(_ chunk: String) -> MGScene? {
        guard !overflowed else { return nil }
        guard chunk.utf8.count <= Self.inputBytes - text.utf8.count else {
            overflowed = true
            pending.removeAll()
            return nil
        }
        text += chunk
        guard !previewItemLimitExceeded else { return nil }
        let members = Self.members(Array(text.utf8))
        // Nothing new completed since the last call: the preview is what that call computed (shown, or refused).
        let itemsMember = members.last { $0.key == "items" }
        let shape = Shape(members: members.filter { $0.complete && $0.key != "items" },
                          items: itemsMember.map { Self.elements($0.raw, limit: MGLimits.items + 1).count } ?? -1)
        if shape == lastShape { return nil }
        lastShape = shape
        var root: [String: MGJSON] = [:]
        var itemsRaw: [UInt8]?
        for m in members {
            if m.key == "items" { itemsRaw = m.raw; continue }
            guard m.complete, let j = Self.json(m.raw) else { continue }
            root[m.key] = j
        }
        guard root["v"] == .number(1) else { return nil }
        // Learner sliders bind to the board's graphs, so they join a preview only once the board they drive parses
        // (like steps); until then every item is tried without them.
        let sliders = root.removeValue(forKey: "sliders")
        if root["template"] != nil {
            guard root["params"] != nil else { return nil }
            root["items"] = nil
        } else {
            let previousPendingCount = pending.count
            if let itemsRaw {
                let elements = Self.elements(itemsRaw, limit: MGLimits.items + 1)
                guard elements.count <= MGLimits.items else {
                    previewItemLimitExceeded = true
                    pending.removeAll()
                    return nil
                }
                if elements.count > seenItems {
                    for element in elements[seenItems...] {
                        if let candidate = Self.json(element), case .object = candidate { pending.append(candidate) }
                    }
                    seenItems = elements.count
                }
            }
            var trial = root
            trial["steps"] = nil
            // Only new candidates need checking while the trial context and accepted items stay the same.
            var index = trialRoot == trial ? previousPendingCount : 0
            trialRoot = trial
            while index < pending.count {
                let candidate = pending[index]
                trial["items"] = .array(accepted + [candidate])
                candidateValidationCount += 1
                if case .success = MGParser.scene(json: .object(trial)) {
                    accepted.append(candidate)
                    pending.remove(at: index)
                    index = 0  // The new item may resolve earlier references.
                } else {
                    index += 1
                }
            }
            guard !accepted.isEmpty else { return nil }
            root["items"] = .array(accepted)
            if root["steps"] != nil {
                // Once `steps` is complete, the trial runs again only when the root it checks changed.
                let candidate = MGJSON.object(root)
                let passed: Bool
                if let t = stepsTrial, t.root == candidate { passed = t.passed } else {
                    previewValidationCount += 1
                    if case .success = MGParser.scene(json: candidate) { passed = true } else { passed = false }
                    stepsTrial = (candidate, passed)
                }
                if !passed { root["steps"] = nil }
            }
        }
        if let sliders {
            root["sliders"] = sliders
            if case .failure = MGParser.scene(json: .object(root)) { root["sliders"] = nil }
        }
        let preview = MGJSON.object(root)
        guard preview != lastPreview, preview != refusedPreview else { return nil }
        previewValidationCount += 1
        guard case .success(let scene) = MGParser.scene(json: preview) else { refusedPreview = preview; return nil }
        lastPreview = preview
        return scene
    }

    /// Strict final parse of everything received.
    public func finish() -> Result<MGScene, MGError> {
        guard !overflowed else { return .failure(.init("json")) }
        return MGParser.scene(data: Data(text.utf8))
    }

    // MARK: tolerant scanning (never trusted for the final result)

    struct Member: Equatable { let key: String; let raw: [UInt8]; let complete: Bool }

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
            if let end = valueEnd(b, i), end > i { out.append(.init(key: key, raw: Array(b[start..<end]), complete: true)); i = end }
            else { out.append(.init(key: key, raw: Array(b[start...]), complete: false)); return out }
        }
    }

    /// Complete elements of a possibly truncated JSON array.
    static func elements(_ b: [UInt8], limit: Int = MGLimits.items + 1) -> [[UInt8]] {
        var i = 0, out: [[UInt8]] = []
        guard !b.isEmpty, b[0] == UInt8(ascii: "[") else { return [] }; i = 1
        while i < b.count, out.count < limit {
            while i < b.count, [0x20, 0x0A, 0x0D, 0x09, UInt8(ascii: ",")].contains(b[i]) { i += 1 }
            guard i < b.count, b[i] != UInt8(ascii: "]") else { break }
            guard let end = valueEnd(b, i), end > i else { break }
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
