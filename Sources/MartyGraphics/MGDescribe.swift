// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Plain-text descriptions of what a 2D or 3D board shows, written by the engine from the checked scene (docs/PROTOCOL.md,
/// "Function graphs, vector fields and text alternatives"). A description names each visible item's kind, its label and
/// the numbers the engine holds (ranges, values, cells), in item order. It describes structure, not meaning: it says
/// "a graph of y = sin(x)", never what the graph is about. Prefer an author's `alt` text when there is one; use this
/// as the fallback text alternative, for example through `MartyGraphicsView.describesBoard()`.
///
/// Deterministic and bounded: numbers use `MGPhysics.format`, and the length is bounded by the scene's own limits.
public enum MGDescribe {
    /// The items visible at `step` (with that step's edits), except `hiding` (for example concealed practice values),
    /// described as one sentence, for example "A graph of y = sin(x) for x from -3 to 3 and y from -1.5 to 1.5; the
    /// text “Sine”." An empty board is "The board is empty."
    public static func board(_ scene: MGScene, step: Int = 0, hiding: Set<String> = []) -> String {
        board(stepItems: MGTimeline.items(scene, step: step), hiding: hiding)
    }

    /// `board(_:step:hiding:)` from the step's items (`MGTimeline.items`), for a view that keeps them (`MGTimelineCache`).
    static func board(stepItems: [MGItem], hiding: Set<String>) -> String {
        sentence(stepItems.filter { !hiding.contains($0.id) })
    }

    /// `items` described as one sentence (the form of `board`); learner sliders describe the items they drew.
    static func sentence(_ items: [MGItem]) -> String {
        let phrases = items.map { item($0, in: items) }
        guard let first = phrases.first else { return "The board is empty." }
        return ([capitalized(first)] + phrases.dropFirst()).joined(separator: "; ") + "."
    }

    /// The board's VoiceOver value in `MartyGraphicsView`: the step's narration (`say`), then the step's `alt` text
    /// (else the scene's), else, when `describing`, `board(scene, step:hiding:)`. Without `alt` text and without
    /// `describing` it is the narration alone (empty for a scene without steps), as before `alt` existed.
    public static func accessibilityValue(_ scene: MGScene, step: Int, describing: Bool = false, hiding: Set<String> = []) -> String {
        accessibilityValue(scene, step: step, describing: describing, hiding: hiding) { MGTimeline.items(scene, step: step) }
    }

    /// `accessibilityValue(_:step:describing:hiding:)` with the step's items from the caller (read only when needed;
    /// `MGBoardFrames.accessibilityValue` passes the items its board's evaluation read).
    static func accessibilityValue(_ scene: MGScene, step: Int, describing: Bool, hiding: Set<String>, stepItems: () -> [MGItem]) -> String {
        let current = scene.steps.indices.contains(step) ? scene.steps[step] : nil
        let alt = current?.alt ?? scene.alt
        let text = alt ?? (describing ? board(stepItems: stepItems(), hiding: hiding) : nil)
        return [current?.say ?? "", text ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// One item's phrase, in lower case, for example "a ball labelled “Cart”". `items` resolves references (edges,
    /// highlights).
    public static func item(_ i: MGItem, in items: [MGItem]) -> String {
        func named(_ s: String) -> String { i.label.map { "\(s) labelled “\($0)”" } ?? s }
        func name(of id: String?) -> String {
            guard let id, let target = items.first(where: { $0.id == id }) else { return "a missing item" }
            if let label = target.label { return "“\(label)”" }
            if target.kind == .node, let text = target.text { return "“\(text)”" }
            return "“\(target.id)”"
        }
        func ranges(_ i: MGItem) -> String {
            "x from \(f(i.n("x0"))) to \(f(i.n("x1"))) and y from \(f(i.n("y0"))) to \(f(i.n("y1")))"
        }
        func parameters(_ i: MGItem) -> String {
            let set = ["a", "b", "c"].compactMap { k in i.num[k].map { "\(k) = \(f($0))" } }
            return set.isEmpty ? "" : " with " + set.joined(separator: ", ")
        }
        switch i.kind {
        case .body: return named(i.has("ball") ? "a ball" : "a box")
        case .incline: return named("a slope at \(f(i.n("angle")))°")
        case .line: return i.has("ground") ? "the ground" : i.has("dashed") ? "a dashed line" : "a line"
        case .vector: return named(i.has("dir3") ? "an arrow" : "an arrow at \(f(i.n("angle")))°")
        case .axes:
            let labels = i.list.filter { !$0.isEmpty }
            return labels.count == 2 ? "axes \(labels[0]) and \(labels[1])" : "axes"
        case .plot: return named("a plot of \(Swift.max(0, i.pts.count - 1)) points") + " for " + ranges(i)
        case .spring: return named("a spring")
        case .pulley: return "a pulley"
        case .rope: return "a rope"
        case .orbit: return named("a circular path")
        case .text:
            let text = i.text ?? ""
            return i.has("code") ? "the code “\(text)”" : i.has("title") ? "the title “\(text)”" : "the text “\(text)”"
        case .highlight: return named("a highlight on \(name(of: i.ref))")
        case .bars:
            let unit = i.text ?? ""
            return named("a bar chart") + ": " + i.bars.map { "\($0.label) \(MGPhysics.format($0.value, unit: unit))" }.joined(separator: ", ")
        case .path: return i.has("dashed") ? "a dashed path" : "a path"
        case .array:
            var s = named("an array of \(i.list.count) cells") + ": " + i.list.joined(separator: ", ")
            if !i.pointers.isEmpty {
                s += ", with " + i.pointers.map { "\($0.label) at cell \(whole($0.index))" }.joined(separator: " and ")
            }
            if !i.marked.isEmpty { s += ", marked cells " + i.marked.map(String.init).joined(separator: ", ") }
            return s
        case .node: return "the node “\(i.text ?? "")”"
        case .edge:
            let a = name(of: i.ref), b = name(of: i.ref2)
            return named(i.has("dir") ? "an arrow from \(a) to \(b)" : "a link between \(a) and \(b)")
        case .table:
            guard !i.isEmptyTable else { return named("an empty table") }
            let cols = Swift.max(1, whole(i.n("cols", 1))), rows = Swift.max(1, whole(i.n("rows", 1)))
            let cells = stride(from: 0, to: i.list.count, by: cols).map { i.list[$0..<Swift.min($0 + cols, i.list.count)].joined(separator: ", ") }
            return named("a table of \(rows) rows and \(cols) columns") + ": " + cells.joined(separator: "; ")
        case .region: return named(i.has("dashed") ? "a dashed region" : "a shaded region")
        case .function:
            var s = named("a graph of y = \(i.text ?? "")") + " for " + ranges(i) + parameters(i)
            if let p = i.num["period"] { s += ", moving and repeating every \(f(p)) s" }
            let pieces = MGGraph.pieces(i.pts.count - 1, starts: i.marked).count
            if pieces > 1 { s += ", in \(pieces) pieces" }
            if let s0 = i.num["s0"], let s1 = i.num["s1"] { s += ", shaded from x = \(f(s0)) to \(f(s1))" }
            if let a = i.num[MGReadout.area.key] { s += " (signed area \(f(a)))" }
            if let m = i.num["mark"], let y = i.num["my"] { s += ", marking the point (\(f(m)), \(f(y)))" }
            if let k = i.num[MGReadout.slope.key] { s += " where the slope is \(f(k))" }
            return s
        case .field:
            let dx = i.list.count == 4 ? i.list[2] : "", dy = i.list.count == 4 ? i.list[3] : ""
            let style = i.has("slope") ? "direction segments" : i.has("unit") ? "equal arrows" : "arrows"
            return named("a vector field (\(dx), \(dy))") + " of \(whole(i.n("cols"))) by \(whole(i.n("rows"))) \(style) for "
                + ranges(i) + parameters(i)
        case .curve:
            // The drawn (aspect-correct) window, the theta range and facts the engine measured on its samples.
            let polar = i.has("polar")
            let form = polar ? "polar curve r = \(i.list.count == 3 ? i.list[2] : "")"
                : "parametric curve x = \(i.list.count == 4 ? i.list[2] : ""), y = \(i.list.count == 4 ? i.list[3] : "")"
            var s = named((MGGraph.isClosed(i) ? "a closed " : "a ") + form)
                + " for theta from \(f(i.n("th0"))) to \(f(i.n("th1"))), " + ranges(i) + parameters(i)
            if let p = i.num["period"] { s += ", moving and repeating every \(f(p)) s" }
            let pieces = MGGraph.pieces(Swift.max(0, i.pts.count - 1), starts: i.marked).count
            if pieces > 1 { s += ", in \(pieces) pieces" }
            if let m = i.num["mark"], let x = i.num["mx"], let y = i.num["my"] {
                s += ", marking the point (\(f(x)), \(f(y))) at theta = \(f(m))"
            }
            return s
        }
    }

    static func f(_ v: Double) -> String { MGPhysics.format(v, unit: "") }

    /// A count or index as a whole number; 0 for a value that is not finite or not below 10⁶ (an item built in code).
    static func whole(_ v: Double) -> Int { v.isFinite && Swift.abs(v) < 1e6 ? Int(v.rounded()) : 0 }

    static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

extension MGBoardFrames {
    /// The board's VoiceOver value, from the items this evaluation of the board read, so it describes what the board
    /// draws and reads no cache: `MGDescribe.accessibilityValue` (the narration, then the authored `alt`, or the
    /// engine's description of these items when `describing`). Once a learner slider has moved (`fromSliders`), an
    /// authored `alt` describes another board, so the engine's description of these items follows the narration.
    func accessibilityValue(describing: Bool = false, hiding: Set<String> = []) -> String {
        guard fromSliders else {
            return MGDescribe.accessibilityValue(scene, step: step, describing: describing, hiding: hiding) { items }
        }
        let say = scene.steps.indices.contains(step) ? scene.steps[step].say : ""
        return [say, MGDescribe.sentence(items.filter { !hiding.contains($0.id) })].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
