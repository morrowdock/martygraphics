// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A learner slider on a 2D board: one entry of the scene's `sliders` (docs/PROTOCOL.md, "Learner sliders"). It sets
/// one parameter (`a`, `b` or `c`) of every `func` item that sets that parameter, so the board has one value of it, as
/// in a graphing calculator. The slider holds no arithmetic of its own: `MGSliderState` re-parses every item it drives
/// with `MGParser.item`, so each curve, piece, marked point and readout number comes from the engine.
public struct MGSlider: Equatable, Sendable, Identifiable {
    /// The parameter, `a`, `b` or `c`. A scene has one slider per parameter, so this is also the slider's id.
    public let param: String
    public var id: String { param }
    /// The ends of the range, within ±`MGLimits.exprParameter`, `min` below `max`.
    public let min: Double, max: Double
    /// The distance between neighbouring positions. It divides `max − min` into `steps` equal steps.
    public let step: Double
    /// The starting value (wire `default`). It is exactly `value(at: defaultStop)` and equals the parameter of every
    /// item the slider drives, so a host that shows no sliders draws the board at the default.
    public let defaultValue: Double
    /// Fixed plain text (no placeholders); the current value is shown beside it.
    public let label: String
    /// The ids of the `func` items the slider drives (every one that sets `param`), in scene order.
    public let items: [String]
    /// The number of equal steps from `min` to `max`, 1…`MGLimits.sliderSteps`.
    public let steps: Int
    /// The grid position of `defaultValue`, 0…`steps`.
    public let defaultStop: Int
    /// Decimal places the slider's numbers need (0…6): enough to write `min` and `step` exactly.
    let decimals: Int

    /// The value sent to the engine at grid position `stop` (clamped to 0…`steps`): exactly the number the stop's
    /// label (`text`) reads as, so the board never draws a value other than the one shown. The parser refuses a grid
    /// where that is not exactly `min` at 0 and `max` at `steps` (`slider.grid`), and a default that is not exactly
    /// one of these values (`slider.default`), so the default never stands in for a stop.
    public func value(at stop: Int) -> Double {
        let v = candidate(at: stop)
        return Double(text(v)) ?? v
    }

    /// The stop before its label is written: `min` at 0, `max` at `steps`, else `min + (max − min) × stop / steps`.
    /// Where `decimals` places name that value, it is the value those places write, so a stop meant to be 0 is 0, not
    /// 4.4e-16 (−2.6 to 2.6 in steps of 0.1).
    func candidate(at stop: Int) -> Double {
        let i = Swift.min(Swift.max(stop, 0), steps)
        if i == 0 { return min }
        if i == steps { return max }
        let raw = min + (max - min) * Double(i) / Double(steps)
        if let snapped = Double(Self.trimmed(String(format: "%.\(decimals)f", raw))),
           Swift.abs(snapped - raw) <= step * 1e-6 { return snapped }
        return raw
    }

    /// The grid position whose value is exactly `value`, or nil when no stop has it.
    func stop(exactly value: Double) -> Int? {
        (0...steps).first { self.value(at: $0) == value }
    }

    /// The grid position nearest `value`. A value outside the range gives the nearer end; a value that is not finite
    /// gives the default.
    public func stop(nearest value: Double) -> Int {
        guard value.isFinite else { return defaultStop }
        let q = ((value - min) / step).rounded()
        return Int(Swift.min(Swift.max(q, 0), Double(steps)))
    }

    /// A value as the slider shows and speaks it: the visible value, the VoiceOver value, the range hint, the readout
    /// and the refusal note all use this one form.
    ///
    /// The compact form is `decimals` places with trailing zeros removed (`1.5`, `-2`, `0.25`). It is kept when it names
    /// the value: read back, it lies within a millionth of a step of it, so it round-trips to the same grid stop and two
    /// neighbouring stops never share a label. Otherwise (more than 6 places, as for a step of 10⁻⁷, where the compact
    /// form of a nonzero step would be `0`) the value is written with the fewest significant digits that name it the
    /// same way (`0.0000001`, `1.0000001`; below 10⁻⁹ with an exponent, `1.5e-12`).
    public func text(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let compact = Self.trimmed(String(format: "%.\(decimals)f", value))
        if names(compact, value) { return compact }
        for digits in 1...17 {
            let s = Self.significant(value, digits: digits)
            if names(s, value) { return s }
        }
        return Self.significant(value, digits: 17)
    }

    /// True when `text`, read back, is within a millionth of a step of `value`. A nonzero value never reads as `0` or
    /// `-0`, however small it is beside the step (a default of 10⁻¹² is not `0`).
    func names(_ text: String, _ value: Double) -> Bool {
        guard let read = Double(text) else { return false }
        if read == 0 || value == 0 { return read == value }
        return Swift.abs(read - value) <= step * 1e-6
    }

    /// True when the engine gets exactly the shown value at every stop: each end's label reads back as exactly that
    /// end, and every stop's value is exactly the number its label reads as, within `min…max`, above the stop before,
    /// nearest its own grid position, with a label of its own. Fails for a step near the spacing of doubles (from 1 to
    /// 1.0000000000000004 in steps of 1.1102230246251565e-16, stops 0 and 1 are both 1) and for an end the slider's
    /// form cannot write (`max` 1.0000000002 with step 1 shows `1`).
    var gridIsDistinct: Bool {
        guard value(at: 0) == min, value(at: steps) == max else { return false }
        var previous = -Double.infinity
        var labels = Set<String>()
        for i in 0...steps {
            let v = value(at: i)
            guard v > previous, v >= min, v <= max else { return false }
            previous = v
            let label = text(v)
            guard Double(label) == v, stop(nearest: v) == i, labels.insert(label).inserted else { return false }
        }
        return true
    }

    /// `value` rounded to `digits` significant digits, in positional notation (trailing zeros removed) down to 10⁻⁹,
    /// below that as `1.5e-12`.
    static func significant(_ value: Double, digits: Int) -> String {
        let e = String(format: "%.\(digits - 1)e", value)   // "-1.500e-07"
        guard let cut = e.firstIndex(of: "e"), let exponent = Int(e[e.index(after: cut)...]) else { return e }
        guard let rounded = Double(e), rounded != 0 else { return "0" }
        if exponent >= -9 {
            return trimmed(String(format: "%.\(Swift.max(0, digits - 1 - exponent))f", rounded))
        }
        return trimmed(String(e[..<cut])) + "e" + String(exponent)
    }

    /// Trailing zeros (and a trailing point) removed from a decimal, and `-0` written `0`.
    static func trimmed(_ text: String) -> String {
        var s = text
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
        if s == "-0" { s = "0" }
        return s
    }

    /// The fewest decimal places (0…6) that write every value exactly, to within 10⁻⁹ of a unit in the last place.
    static func decimals(_ values: [Double]) -> Int {
        values.map { v -> Int in
            var places = 0
            while places < 6 {
                let scaled = v * pow(10, Double(places))
                if Swift.abs(scaled - scaled.rounded()) <= 1e-9 * Swift.max(1, Swift.abs(scaled)) { break }
                places += 1
            }
            return places
        }.max() ?? 0
    }
}

extension MGParser {
    /// The keys of one slider. All are required and no other key is allowed.
    static let sliderKeys: Set<String> = ["param", "min", "max", "step", "default", "label"]

    /// The scene's `sliders`, checked after every item and step (docs/PROTOCOL.md, "Learner sliders"). Reasons, in
    /// this order for each slider:
    ///
    /// - `sliders`: not a list of 1…`MGLimits.sliders` entries; `slider`: an entry is not an object;
    ///   `slider.missing`, `slider.unknown.<keys>`: the closed key set.
    /// - `slider.param`: not `a`, `b` or `c`; `slider.duplicate.<param>`: a second slider for the same parameter.
    /// - `slider.min`, `slider.max`: not a number within ±`MGLimits.exprParameter`; `slider.range`: `min` not below `max`.
    /// - `slider.step`: not above 0 and at most `max − min`, or `max − min` is not a whole number of steps;
    ///   `slider.step.count`: more than `MGLimits.sliderSteps` steps; `slider.grid`: the engine would not get exactly
    ///   the shown value at every stop: an end's label does not read back as exactly that end (`max` 1.0000000002
    ///   with step 1 shows `1`), two stops have the same value, or a stop's label does not read back as exactly its
    ///   value (a step too fine for the doubles near the range).
    /// - `slider.default`: outside `min…max`, or not exactly the value of a stop (`0.30000000000000004` where the
    ///   stop is `0.3`; `1e-12` where the stop is `0`).
    /// - `slider.label.placeholder`: braces (a label is fixed text); `slider.label`: the plain-text rules, 40 scalars.
    /// - `slider.unbound`: no `func` sets the parameter; `slider.field`: a `field` sets it (sliders drive `func` items
    ///   only, and a field that kept its own value would contradict the slider); `slider.default.<id>`: the `func`
    ///   `<id>` sets the parameter to another value; `sliders.bindings`: more than `MGLimits.sliderBindings` pairs of a
    ///   slider and a `func` it drives; `slider.edit`: a step edit sets the parameter of a `func` or `field`.
    /// - `slider.<param>.min.<reason>`, `slider.<param>.max.<reason>`: a driven `func` refuses that end of the range
    ///   with `<reason>` (for example `slider.b.max.func.detail`), checked exactly as a parse, with every other
    ///   parameter at its default.
    static func sliders(_ json: MGJSON, items: [MGItem], steps: [MGStep], _ ctx: MGContext) throws -> [MGSlider] {
        guard case .array(let list) = json, (1...MGLimits.sliders).contains(list.count) else { throw MGError("sliders") }
        let graphs = Set(items.filter { $0.kind == .function || $0.kind == .field }.map(\.id))
        var out: [MGSlider] = []
        var bindings = 0
        for entry in list {
            guard let o = entry.objectValue else { throw MGError("slider") }
            try closed(o, required: sliderKeys, optional: [], "slider")
            guard case .string(let param)? = o["param"], ["a", "b", "c"].contains(param) else { throw MGError("slider.param") }
            guard !out.contains(where: { $0.param == param }) else { throw MGError("slider.duplicate.\(param)") }
            let bound = MGLimits.exprParameter
            let lo = try num(o["min"], -bound...bound, "slider.min"), hi = try num(o["max"], -bound...bound, "slider.max")
            guard lo < hi else { throw MGError("slider.range") }
            let step = try num(o["step"], Double.leastNonzeroMagnitude...(hi - lo), "slider.step")
            // Whole steps, to within 10⁻⁹ of a step per step: 3 / 0.1 is 30.000000000000004.
            let q = (hi - lo) / step
            guard q < Double(MGLimits.sliderSteps) + 0.5 else { throw MGError("slider.step.count") }
            let count = q.rounded()
            guard Swift.abs(q - count) <= 1e-9 * count else { throw MGError("slider.step") }
            let decimals = MGSlider.decimals([lo, step])
            // The bare grid (the default is stop 0, which is min): every stop its own value and label.
            let grid = MGSlider(param: param, min: lo, max: hi, step: step, defaultValue: lo, label: "", items: [],
                                steps: Int(count), defaultStop: 0, decimals: decimals)
            guard grid.gridIsDistinct else { throw MGError("slider.grid") }
            let initial = try num(o["default"], lo...hi, "slider.default")
            // The default is a stop: exactly the number some stop's label reads as, so it never shows or draws a
            // number the grid lacks, and never replaces a stop's value.
            guard let at = grid.stop(exactly: initial) else { throw MGError("slider.default") }
            // A label is fixed text: an engine number filled in once would go stale when the slider moves.
            if case .string(let raw)? = o["label"], raw.contains("{") || raw.contains("}") { throw MGError("slider.label.placeholder") }
            let label = try text(o["label"], MGLimits.label, ctx, "slider.label")

            let driven = items.filter { $0.kind == .function && $0.num[param] != nil }
            guard !driven.isEmpty else { throw MGError("slider.unbound") }
            guard !items.contains(where: { $0.kind == .field && $0.num[param] != nil }) else { throw MGError("slider.field") }
            for f in driven where f.num[param] != initial { throw MGError("slider.default.\(f.id)") }
            bindings += driven.count
            guard bindings <= MGLimits.sliderBindings else { throw MGError("sliders.bindings") }
            // The slider is the one source of the parameter: no step may set it.
            for s in steps { for e in s.edits where e.key == param && graphs.contains(e.id) { throw MGError("slider.edit") } }
            // Both ends of the range, with every other parameter at its default, through the same item check as a parse.
            for f in driven {
                for (end, value) in [("min", lo), ("max", hi)] where value != initial {
                    var wire = f.wire()
                    wire[param] = .number(value)
                    do { _ = try item(.object(wire), ctx) } catch let e as MGError { throw MGError("slider.\(param).\(end).\(e.reason)") }
                }
            }
            out.append(MGSlider(param: param, min: lo, max: hi, step: step, defaultValue: initial, label: label,
                                items: driven.map(\.id), steps: Int(count), defaultStop: at, decimals: decimals))
        }
        return out
    }
}

/// A slider position the engine refused, and the sentence the board shows for it.
public struct MGSliderRefusal: Equatable, Sendable {
    /// The slider that moved, or nil when a step change sent every slider back to its default.
    public let param: String?
    /// The refused grid position, or nil with `param`.
    public let stop: Int?
    /// The refused value as the slider writes it (`"3.5"`), or nil with `param`.
    public let value: String?
    /// The reason a driven `func` gave at that value, for example `func.empty`. A developer diagnostic.
    public let error: MGError

    /// Plain text for the learner, for example "a = 3.5 is not shown: nothing of the graph would be in view."
    public var text: String {
        let why = Self.phrase(error.reason)
        if let param, let value { return "\(param) = \(value) is not shown: \(why)." }
        return "The sliders are back at their starting values: at this step \(why)."
    }

    /// What a `func` refusal means for the drawing, in words.
    static func phrase(_ reason: String) -> String {
        switch reason {
        case "func.empty": return "nothing of the graph would be in view"
        case "func.detail": return "the curve would change too fast to draw faithfully"
        case "func.breaks": return "the graph would break into too many pieces"
        case "func.shade": return "the shaded area would have a gap"
        case "func.mark": return "the marked point would have no value in view"
        case "func.loop": return "the motion would no longer repeat seamlessly"
        default: return "the graph would not pass the engine's checks"
        }
    }
}

/// What VoiceOver reads for one slider control, and its identifier. `MartyGraphicsView` applies these values, and its
/// adjustable action calls `MGSliderState.increment` and `decrement`.
public struct MGSliderAccessibility: Equatable, Sendable {
    /// The slider's label.
    public let label: String
    /// The current value as the slider shows it.
    public let value: String
    /// The range and the step, for example "From 0 to 3 in steps of 0.5."
    public let hint: String
    /// `board.slider.<param>`.
    public let identifier: String
    /// Always true: one swipe up or down moves the slider one step (past any position the engine refuses).
    public let adjustable: Bool
}

/// The learner's slider positions on one scene and the board they give. Foundation only and deterministic, so a test,
/// an export and `MartyGraphicsView` agree.
///
/// Every move re-parses each `func` the slider drives with `MGParser.item`, the path of a scene parse and a step edit,
/// so the samples, pieces, shaded band, marked point and every readout number come from the engine, never from the
/// model. A position the checks refuse (`func.empty`, `func.detail`, …) leaves the board as it was and records a
/// `refusal`. With every slider at its default the items are `MGTimeline.items(scene, step:)`, unchanged.
public struct MGSliderState: Equatable, Sendable {
    public let scene: MGScene
    /// The step whose items are shown (`MGTimeline.items(scene, step:)` plus the slider values).
    public private(set) var step: Int
    /// The accepted grid position of each slider, by parameter.
    public private(set) var stops: [String: Int]
    /// The board items at `step` with the accepted slider values.
    public private(set) var items: [MGItem]
    /// The last refused position. An accepted move clears it, except a VoiceOver step that skipped refused positions,
    /// which keeps the first one so the board can say why.
    public private(set) var refusal: MGSliderRefusal?

    /// The sliders at their defaults, or at `values` (by parameter) where a value is still on its slider's grid and the
    /// whole board passes the checks with them (for example after a patch); otherwise every slider starts at its default.
    public init(scene: MGScene, step: Int = 0, keeping values: [String: Double] = [:]) {
        self.scene = scene
        self.step = step
        let defaults = Self.defaults(scene)
        var wanted = defaults
        for s in scene.sliders {
            guard let v = values[s.param], v.isFinite else { continue }
            let k = s.stop(nearest: v)
            if Swift.abs(s.value(at: k) - v) <= 1e-9 * Swift.max(1, Swift.abs(v)) { wanted[s.param] = k }
        }
        if wanted != defaults, case .success(let resolved) = Self.resolve(scene, step: step, stops: wanted) {
            stops = wanted; items = resolved
        } else {
            stops = defaults; items = MGTimeline.items(scene, step: step)
        }
        refusal = nil
    }

    public func slider(_ param: String) -> MGSlider? { scene.sliders.first { $0.param == param } }
    /// The accepted value of the slider for `param`, or nil when the scene has no such slider.
    public func value(_ param: String) -> Double? { slider(param).map { $0.value(at: stops[$0.param] ?? $0.defaultStop) } }
    /// The accepted value of every slider, by parameter.
    public var values: [String: Double] {
        Dictionary(uniqueKeysWithValues: scene.sliders.map { ($0.param, $0.value(at: stops[$0.param] ?? $0.defaultStop)) })
    }
    public var isAtDefaults: Bool { scene.sliders.allSatisfy { stops[$0.param] == $0.defaultStop } }

    /// Move the slider for `param` to grid position `stop`. Returns false, and keeps the board, when there is no such
    /// slider or position, or when a driven `func` refuses the value (then `refusal` says why).
    @discardableResult public mutating func set(_ param: String, stop: Int) -> Bool {
        guard let s = slider(param), (0...s.steps).contains(stop) else { return false }
        guard stops[param] != stop else { refusal = nil; return true }
        // A drag reports the same refused position many times: check it once.
        if let r = refusal, r.param == param, r.stop == stop { return false }
        var next = stops
        next[param] = stop
        switch Self.resolve(scene, step: step, stops: next) {
        case .success(let resolved):
            stops = next; items = resolved; refusal = nil
            return true
        case .failure(let error):
            refusal = MGSliderRefusal(param: param, stop: stop, value: s.text(s.value(at: stop)), error: error)
            return false
        }
    }

    /// Move the slider for `param` to the grid position nearest `value` (a continuous drag).
    @discardableResult public mutating func set(_ param: String, nearest value: Double) -> Bool {
        guard let s = slider(param) else { return false }
        return set(param, stop: s.stop(nearest: value))
    }

    /// One step up (VoiceOver: swipe up). Refused positions are skipped, so the whole range stays reachable without a
    /// drag; false at the end of the range or when every position beyond is refused.
    @discardableResult public mutating func increment(_ param: String) -> Bool { move(param, by: 1) }
    /// One step down (VoiceOver: swipe down); see `increment`.
    @discardableResult public mutating func decrement(_ param: String) -> Bool { move(param, by: -1) }

    private mutating func move(_ param: String, by delta: Int) -> Bool {
        guard let s = slider(param), let current = stops[param] else { return false }
        var k = current + delta
        var first: MGSliderRefusal?
        while (0...s.steps).contains(k) {
            if set(param, stop: k) {
                if let first { refusal = first }
                return true
            }
            if first == nil { first = refusal }
            k += delta
        }
        if let first { refusal = first }
        return false
    }

    /// The items a board shows at `step`: the learner's items once a slider sits at an accepted non-default position on
    /// this scene revision and step, else the step's items through `cache`, so frames never compute them again. At the
    /// defaults (before the first move and after a reset) the slider items equal the step items, so the cache gives
    /// the same board.
    static func boardItems(_ scene: MGScene, step: Int, sliders: MGSliderState?, cache: MGTimelineCache) -> [MGItem] {
        if let s = sliders, !s.isAtDefaults, s.scene.revision == scene.revision, s.step == step { return s.items }
        return cache.items(scene, step: step)
    }

    /// Every slider back to its default.
    public mutating func reset() {
        stops = Self.defaults(scene); items = MGTimeline.items(scene, step: step); refusal = nil
    }

    /// Show another step with the same slider values. When that step's items refuse them (a step edit changed a
    /// driven graph), every slider goes back to its default and `refusal` says why.
    public mutating func show(step: Int) {
        self.step = step
        refusal = nil
        guard !isAtDefaults else { items = MGTimeline.items(scene, step: step); return }
        switch Self.resolve(scene, step: step, stops: stops) {
        case .success(let resolved): items = resolved
        case .failure(let error):
            stops = Self.defaults(scene); items = MGTimeline.items(scene, step: step)
            refusal = MGSliderRefusal(param: nil, stop: nil, value: nil, error: error)
        }
    }

    /// The sliders that drive at least one item on the board now (shown at this step and not in `hiding`).
    public func sliders(hiding: Set<String> = []) -> [MGSlider] {
        let shown = Set(items.map(\.id)).subtracting(hiding)
        return scene.sliders.filter { $0.items.contains(where: shown.contains) }
    }

    /// One line per driven `func` on the board now, from the engine's numbers: its name (label, else `y = <expression>`),
    /// the slider parameters it reads and, for a still graph with a `mark`, the marked point, for example
    /// "y = a sin x: a = 1.5, marked point (1.57, 1.5)". A moving graph's marked point moves, so it is left to the board.
    public func caption(hiding: Set<String> = []) -> [String] {
        let driven = Set(scene.sliders.flatMap(\.items))
        return items.filter { $0.kind == .function && driven.contains($0.id) && !hiding.contains($0.id) }.map { item -> String in
            var parts = scene.sliders.filter { $0.items.contains(item.id) }.map { "\($0.param) = \($0.text(item.n($0.param)))" }
            if item.num["period"] == nil, let m = item.num["mark"] {
                parts.append(item.num["my"].map { "marked point (\(MGDescribe.f(m)), \(MGDescribe.f($0)))" }
                             ?? "no marked value at x = \(MGDescribe.f(m))")
            }
            return (item.label ?? "y = \(item.text ?? "")") + ": " + parts.joined(separator: ", ")
        }
    }

    /// The board's VoiceOver value. At the defaults it is `MGDescribe.accessibilityValue` (narration, then authored
    /// `alt` text). Once a slider has moved, an authored `alt` describes another board, so the engine's description of
    /// the items now drawn follows the narration instead (`describing` is then implied).
    public func accessibilityValue(describing: Bool = false, hiding: Set<String> = []) -> String {
        guard !isAtDefaults else { return MGDescribe.accessibilityValue(scene, step: step, describing: describing, hiding: hiding) }
        let say = scene.steps.indices.contains(step) ? scene.steps[step].say : ""
        return [say, MGDescribe.sentence(items.filter { !hiding.contains($0.id) })].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The VoiceOver label, value, hint and identifier of the slider for `param`.
    public func accessibility(_ param: String) -> MGSliderAccessibility? {
        guard let s = slider(param), let v = value(param) else { return nil }
        return MGSliderAccessibility(label: s.label, value: s.text(v),
                                     hint: "From \(s.text(s.min)) to \(s.text(s.max)) in steps of \(s.text(s.step)).",
                                     identifier: "board.slider.\(s.param)", adjustable: true)
    }

    static func defaults(_ scene: MGScene) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: scene.sliders.map { ($0.param, $0.defaultStop) })
    }

    /// The items at `step` with each slider at `stops`.
    static func resolve(_ scene: MGScene, step: Int, stops: [String: Int]) -> Result<[MGItem], MGError> {
        var values: [String: Double] = [:]
        for s in scene.sliders { values[s.param] = s.value(at: stops[s.param] ?? s.defaultStop) }
        return apply(values, to: MGTimeline.items(scene, step: step), in: scene)
    }

    /// `items` with each slider's value (`values`, by parameter) set on the `func` items it drives. A changed item is
    /// re-parsed from its wire form with `MGParser.item`, so it is re-sampled and re-checked as in a parse; the first
    /// refusal is returned. Items the sliders do not drive, and items already at the value, are returned unchanged.
    static func apply(_ values: [String: Double], to items: [MGItem], in scene: MGScene) -> Result<[MGItem], MGError> {
        let ctx = MGContext(width: scene.width, height: scene.height, is3D: scene.is3D, values: scene.values)
        var out = items
        for k in out.indices where out[k].kind == .function {
            var wire = out[k].wire()
            var changed = false
            for s in scene.sliders where s.items.contains(out[k].id) {
                guard let v = values[s.param], out[k].num[s.param] != v else { continue }
                wire[s.param] = .number(v)
                changed = true
            }
            guard changed else { continue }
            do { out[k] = try MGParser.item(.object(wire), ctx) }
            catch let e as MGError { return .failure(e) }
            catch { return .failure(MGError("slider")) }
        }
        return .success(out)
    }
}
