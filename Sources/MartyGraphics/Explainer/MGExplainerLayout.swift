// SPDX-License-Identifier: Apache-2.0
import Foundation

// The adaptive board pane of an explainer: one deterministic rule that the renderer stills, the story video and the
// SwiftUI explainer view all read. Foundation only.

/// Whether the board pane is drawn at the shown state, and the board text that moves to the title band when it is not.
///
/// The rule (docs/EXPLAINER.md, "Adaptive board pane"): in an explainer with both a board and a solid, the board pane
/// is drawn only while the shown board state has at least one item that is not a `text` item (a table with a data row,
/// a plot, a shape, a vector, a highlight, any other kind). A table with no data row (`MGItem.isEmptyTable`: a header
/// waiting for its first `set`) is not drawn and does not count, so the pane opens when the table is first filled (the
/// story slides it open, "Pane slide in the story video"). While the shown board has only `text` items and empty
/// tables (or none), the solid takes the whole frame and the board's texts, in board order, move to the title band
/// (`text`). An explainer with only a board always draws it; an explainer with only a solid never has a board pane.
public struct MGExplainerBoardPane: Equatable, Sendable {
    /// True when the board pane is drawn.
    public var shown: Bool
    /// The shown board's `text` items (filled text, board order, empty texts left out), when the pane is not drawn and
    /// the explainer has a solid; empty otherwise.
    public var texts: [String]

    public init(shown: Bool, texts: [String] = []) { self.shown = shown; self.texts = texts }

    /// The texts on one line, joined with " · " (nil when there is none). Hosts truncate it to their width.
    public var line: String? { texts.isEmpty ? nil : texts.joined(separator: " · ") }

    /// The rule for one shown board scene. `scene` is the shown 2D state (nil without a board); `hasSolid` is true when
    /// the explainer has a solid.
    public static func rule(scene: MGScene?, hasSolid: Bool) -> MGExplainerBoardPane {
        guard let scene else { return MGExplainerBoardPane(shown: false) }
        guard hasSolid else { return MGExplainerBoardPane(shown: true) }
        if scene.items.contains(where: { $0.kind != .text && !$0.isEmptyTable }) { return MGExplainerBoardPane(shown: true) }
        let texts = scene.items.compactMap { item -> String? in
            let t = (item.text ?? item.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return MGExplainerBoardPane(shown: false, texts: texts)
    }
}

extension MGExplainerSession {
    /// The board pane at the shown state: the rule (`MGExplainerBoardPane.rule`) on the lesson's shown 2D state
    /// (`state`, the state each presented beat, set-up command and accepted change makes the shown state, the same
    /// state the legend's record of shown items reads), with the explainer's solid. Before the board is shown, and
    /// without a board, the pane is not drawn.
    public var boardPane: MGExplainerBoardPane {
        guard board != nil else { return MGExplainerBoardPane(shown: false) }
        return MGExplainerBoardPane.rule(scene: lesson.state?.scene, hasSolid: solid != nil)
    }
}

/// A rectangle of a rendered frame in whole pixels, bottom-left origin (CoreGraphics bitmaps).
public struct MGFrameRect: Equatable, Sendable {
    public var x: Int, y: Int, width: Int, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    /// Width over height (1.6 for an empty rect).
    public var aspect: Double { width > 0 && height > 0 ? Double(width) / Double(height) : 1.6 }
}

/// The layout of one composite explainer frame (`marty-solid render` stills and `story.mp4`) and the camera of its
/// solid pane. The pane rects are whole pixels, and the solid pane is framed for exactly the pixels it is rendered at,
/// so a still and a story frame of the same beat in the same layout get the same camera.
public enum MGExplainerFrame {
    /// The panes at `width` × `height` pixels: the content area under the title band and above the caption band;
    /// with both panes side by side (wider than tall), the board pane takes `boardShare` of the width (nil: 45 %, or 55 %
    /// when the board is primary; `marty-solid render` passes `boardShare(scene:…)`) and the solid the rest; stacked
    /// (taller than wide), the `primary` view gets 55 %, the first pane on top. `board` is false in a beat whose board
    /// pane is not drawn (`MGExplainerSession.boardPane`): the solid then takes the whole area.
    public static func panes(width w: Int, height h: Int, board: Bool, solid: Bool, primarySolid: Bool,
                             boardShare: Double? = nil) -> (board: MGFrameRect?, solid: MGFrameRect?) {
        let area = contentArea(width: w, height: h), gap = paneGap(width: w)
        guard board && solid else { return (board ? area : nil, solid ? area : nil) }
        var first = area, second = area
        if w >= h {
            let total = area.width - Int(gap)
            let boardWidth: Int
            if let share = boardShare {
                let bounded = share.isFinite ? min(boardPrimaryMaxShare, max(boardMinShare, share)) : boardMaxShare
                boardWidth = min(total - 1, max(1, Int(Double(total) * bounded)))
            } else {
                // The split of earlier releases, to the pixel: the primary view gets 55 %.
                let a = Int((Double(area.width) - gap) * 0.55)
                boardWidth = primarySolid ? total - a : a
            }
            first.width = boardWidth
            second.x = first.x + first.width + Int(gap); second.width = total - boardWidth
        } else {
            let a = Int((Double(area.height) - gap) * 0.55), b = area.height - Int(gap) - a
            second.height = primarySolid ? a : b
            first.y = second.y + second.height + Int(gap); first.height = primarySolid ? b : a
        }
        return (first, second)
    }

    /// The content area of a `width` × `height` frame: under the title band, above the caption band, inside the side
    /// margins (whole pixels).
    public static func contentArea(width w: Int, height h: Int) -> MGFrameRect {
        let s = Double(w) / 1280
        let x0 = Int((24 * s).rounded()), y0 = Int((132 * s).rounded())
        return MGFrameRect(x: x0, y: y0, width: max(1, w - 2 * x0), height: max(1, h - y0 - Int((112 * s).rounded())))
    }

    /// The gap between two panes of a `width`-pixel frame (16 px at 1280 px wide).
    public static func paneGap(width w: Int) -> Double { (16 * Double(w) / 1280).rounded() }

    // MARK: Board pane width

    /// Bounds of the board pane's share of a side-by-side split (docs/EXPLAINER.md, "Board pane width"): at least
    /// `boardMinShare`, at most `boardMaxShare` (`boardPrimaryMaxShare` when the board is the primary view).
    public static let boardMinShare = 0.28, boardMaxShare = 0.50, boardPrimaryMaxShare = 0.55
    /// Margin kept on each side of the board's content, in pixels (points) at `unit` 1 (1280 px wide).
    public static let boardMargin = 24.0

    /// The reference board pane of a side-by-side split of `areaWidth` × `areaHeight` with `gap` between the panes: the
    /// board pane at its largest share. The board is drawn at the scale and centre its viewport has in this pane, so a
    /// narrower pane crops only empty board.
    public static func boardReferenceSize(areaWidth: Double, areaHeight: Double, gap: Double, primarySolid: Bool) -> CGSize {
        let share = primarySolid ? boardMaxShare : boardPrimaryMaxShare
        guard areaWidth.isFinite, areaHeight.isFinite, gap.isFinite, areaWidth > gap, areaHeight > 0 else { return CGSize(width: 1, height: 1) }
        return CGSize(width: max(1, Int((areaWidth - gap) * share)), height: max(1, Int(areaHeight)))
    }

    /// The board pane's share of a side-by-side split of `areaWidth` × `areaHeight` (pixels in a still, points in
    /// SwiftUI), with `gap` between the panes. The shown board's items (`MGLayout.bounds` of every item of `scene`, at
    /// the viewport of the reference pane, `boardReferenceSize`) span some width about the pane centre; the share is that
    /// width plus `boardMargin × unit` on each side, over the split width, bounded to `boardMinShare`...`boardMaxShare`
    /// (`boardPrimaryMaxShare` for a primary board). A board without measurable items keeps the largest share.
    /// Deterministic; `marty-solid render` stills, `story.mp4` and the SwiftUI explainer view call it with their own
    /// area.
    public static func boardShare(scene: MGScene?, areaWidth: Double, areaHeight: Double, gap: Double, unit: Double = 1,
                                  primarySolid: Bool) -> Double {
        let top = primarySolid ? boardMaxShare : boardPrimaryMaxShare
        guard let scene, areaWidth.isFinite, areaHeight.isFinite, gap.isFinite, unit.isFinite, areaWidth > gap, areaHeight > 0 else { return top }
        let ref = boardReferenceSize(areaWidth: areaWidth, areaHeight: areaHeight, gap: gap, primarySolid: primarySolid)
        let vp = MGViewport(size: ref, width: scene.width, height: scene.height, camera: scene.camera)
        let mid = Double(ref.width) / 2
        var half = 0.0, measured = false
        for item in scene.items.prefix(MGLimits.resolvedItems) where !item.isEmptyTable {
            guard let r = MGLayout.bounds(item, in: scene.items, vp), !r.isNull, r.minX.isFinite, r.maxX.isFinite else { continue }
            measured = true
            half = max(half, abs(Double(r.minX) - mid), abs(Double(r.maxX) - mid))
        }
        guard measured else { return top }
        let need = 2 * half + 2 * boardMargin * max(0, unit)
        return min(top, max(boardMinShare, need / (areaWidth - gap)))
    }

    /// `boardShare` for a `width` × `height` composite frame (its content area and pane gap, `unit` = width / 1280).
    public static func boardShare(scene: MGScene?, width w: Int, height h: Int, primarySolid: Bool) -> Double {
        let area = contentArea(width: w, height: h)
        return boardShare(scene: scene, areaWidth: Double(area.width), areaHeight: Double(area.height), gap: paneGap(width: w),
                          unit: Double(w) / 1280, primarySolid: primarySolid)
    }

    /// The pose of a beat view: the beat's explode, `spin` (0...1) of its spin played, and its `pose` placements.
    public static func pose(_ doc: MGSolidDocument, view: MGExplainerBeatView, spin: Double = 1) -> MGPoseParameters {
        view.step?.poseParameters(defaults: doc.defaults, spin: spin) ?? doc.defaults
    }

    /// The camera of the solid pane for one beat view: the assembly framing rule (`MGSolidFraming`) for the step the
    /// beat shows (`stepIndex`; nil for the plain view), at the beat's end pose, for the pane's own pixel size. The
    /// pane holds no title or caption, so the whole pane is the safe window. The unblocked-focus rule applies
    /// (`solidClearView`). A beat's still and every hold frame of the beat in `story.mp4` use this camera.
    public static func solidCamera(_ doc: MGSolidDocument, view: MGExplainerBeatView, stepIndex: Int?, pane: MGFrameRect)
        -> (camera: MGSolidCamera, rule: MGSolidFraming.Rule) {
        let c = solidClearView(doc, view: view, stepIndex: stepIndex, pane: pane)
        return (c.camera, c.rule)
    }

    /// `solidCamera` with the whole unblocked-focus result (`MGSolidFraming.clearView`): the camera, the parts the
    /// beat draws as automatic ghosts and the hidden share. A beat's still and its story frames show
    /// `clear.view(view.solid)`.
    public static func solidClearView(_ doc: MGSolidDocument, view: MGExplainerBeatView, stepIndex: Int?, pane: MGFrameRect) -> MGSolidClearView {
        solidClearView(doc, view: view, stepIndex: stepIndex, aspect: pane.aspect)
    }

    /// `solidClearView` for a pane of width over height `aspect` (the framing reads only the pane's aspect): the
    /// SwiftUI solid pane (`MGExplainerController`) frames each beat with this, for its own size in points, so it
    /// shows the camera and automatic ghosts of the beat's still and story hold frames. A non-finite or non-positive
    /// aspect gives 1.6 (`MGFrameRect.aspect` of an empty pane).
    ///
    /// The arrow drops are the beat's canonical set (`beatArrowDrops`), whatever `aspect`: every view of a beat draws
    /// the same annotations, and the legend counts exactly those.
    public static func solidClearView(_ doc: MGSolidDocument, view: MGExplainerBeatView, stepIndex: Int?, aspect: Double) -> MGSolidClearView {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : 1.6
        var c = MGSolidFraming.clearView(doc, shot: beatShot(doc, view: view, stepIndex: stepIndex), aspect: aspect, titleBand: 0, captionBand: 0,
                                         stage: MGSolidStage.zUpToYUp, drops: false)
        c.arrowDrops = beatArrowDrops(doc, view: view, stepIndex: stepIndex)
        return c
    }

    /// The shot a beat's solid pane frames (the camera of the pane only; captions, labels and claims of a story frame
    /// follow `MGStoryPlan.holds`).
    static func beatShot(_ doc: MGSolidDocument, view: MGExplainerBeatView, stepIndex: Int?) -> MGSolidShot {
        let step = view.step
        return MGSolidShot(file: "", params: pose(doc, view: view), preset: step?.camera ?? "hero", orbit: step?.orbit ?? 0,
                           highlight: view.solidHighlight, margin: 0.8, step: step == nil ? nil : stepIndex, title: nil, caption: nil)
    }

    /// The arrows a beat drops (docs/SOLID-3D.md, "Arrow drop"): the drop rule at the beat's framing for the whole
    /// content area of a 1280 × 800 frame (`contentArea`, no board pane). It reads only the beat's solid step and its
    /// highlighted 3D parts, so a session, a still, the story and the SwiftUI pane all get the same set for a beat,
    /// whatever their own pane; the legend counts what they draw (`MGExplainerSession.displayedAnnotations`).
    public static func beatArrowDrops(_ doc: MGSolidDocument, view: MGExplainerBeatView, stepIndex: Int?) -> [MGArrowDrop] {
        guard !doc.annotations.arrows.isEmpty else { return [] }
        let area = contentArea(width: MGAnnotationAnchorRules.width, height: MGAnnotationAnchorRules.height)
        let shot = beatShot(doc, view: view, stepIndex: stepIndex)
        let c = MGSolidFraming.clearView(doc, shot: shot, aspect: area.aspect, titleBand: 0, captionBand: 0, stage: MGSolidStage.zUpToYUp, drops: false)
        return MGSolidFraming.arrowDrops(doc, shot: shot, camera: c.camera, autoGhost: c.autoGhost, aspect: area.aspect)
    }
}

extension MGStoryPlan {
    /// The camera of frame `i` from each beat's camera (its still's camera; nil without a solid): during a beat's hold
    /// it is exactly that beat's camera; in the camera move at the start of a beat it lies between the previous beat's
    /// camera and this one (`camera(from:to:_:)`, or along the beat's routed path in `moves` when that path runs from
    /// the previous beat's camera to this one). A beat in `cuts` or with a cut in `moves` starts at its own camera (no
    /// move): the story cuts when every path of the move meets a part (`routes`). When the pane layout changes, the
    /// render tool fits this camera to the sliding pane of each move frame (`MGPaneSlide.camera`).
    public func camera(frame i: Int, beatCameras: [MGSolidCamera?], cuts: Set<Int> = []) -> MGSolidCamera? {
        let f = frame(i)
        guard beatCameras.indices.contains(f.beat), let to = beatCameras[f.beat] else { return nil }
        guard f.camera < 1, f.beat > 0, !cuts.contains(f.beat), !self.cuts.contains(f.beat), let from = beatCameras[f.beat - 1] else { return to }
        if let m = moves[f.beat], m.keys.count >= 2, m.keys.first == from, m.keys.last == to { return m.camera(f.camera) }
        return MGStoryPlan.camera(from: from, to: to, f.camera)
    }

    /// True when frame `i` is in its beat's hold (from `holdStartFrame`): the beat's own camera, caption, labels and
    /// claims show. False during the camera move before it.
    public func holds(frame i: Int, cuts: Set<Int> = []) -> Bool {
        guard frameCount > 0 else { return false }
        let i = min(max(0, i), frameCount - 1)
        return i >= holdStartFrame(frame(i).beat, cuts: cuts)
    }
}

extension MGSolidCamera {
    /// `{"target", "yaw", "pitch", "distance", "fieldOfView"}` for manifests.
    public var manifestJSON: MGJSON {
        .object(["target": .array(target.map { .number($0) }), "yaw": .number(yaw), "pitch": .number(pitch), "distance": .number(distance),
                 "fieldOfView": .number(fieldOfView)])
    }
}

/// One beat as `marty-solid render` frames its still: the beat (0-based), its view, the solid step it shows (nil: the
/// plain view) and its solid pane.
public struct MGExplainerBeatPane: Equatable, Sendable {
    public var beat: Int
    public var view: MGExplainerBeatView
    public var stepIndex: Int?
    public var pane: MGFrameRect
}

extension MGExplainerFrame {
    /// The solid pane of every beat still of `doc` at `width` × `height`, as `marty-solid render` lays it out: a fresh
    /// session with speech pacing and a manual clock plays the beats in order; at each beat the board's motion is let
    /// settle, and the board pane rule (`MGExplainerSession.boardPane`) and the board pane width (`boardShare`) give the
    /// panes (`panes`). Returns the solid the session compiled at load (the document every beat view comes from) and
    /// one entry per beat with a solid pane; nil solid when the document does not load or has no solid. Deterministic;
    /// at most `MGExplainerLimits.beats` beats.
    public static func beatPanes(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = MGAnnotationAnchorRules.width,
                                 height: Int = MGAnnotationAnchorRules.height) -> (solid: MGSolidDocument?, beats: [MGExplainerBeatPane]) {
        let clock = MGManualClock()
        var session = MGExplainerSession(pacing: .speech, clock: clock, library: library)
        guard case .success = session.load(doc), let solid = session.solid else { return (nil, []) }
        let primarySolid = (session.primary ?? "solid") == "solid"
        var out: [MGExplainerBeatPane] = []
        var k = 0
        while k < MGExplainerLimits.beats, let beat = session.presented.beat, beat == k {
            clock.advance(by: session.motionRemaining)
            _ = session.tick()
            let pane = session.boardPane
            let share = pane.shown ? boardShare(scene: session.state?.scene, width: width, height: height, primarySolid: primarySolid) : nil
            let rects = panes(width: width, height: height, board: pane.shown, solid: true, primarySolid: primarySolid, boardShare: share)
            if let r = rects.solid {
                out.append(MGExplainerBeatPane(beat: k, view: session.presented, stepIndex: session.solidStep(forBeat: k), pane: r))
            }
            _ = session.lineEnded(k)
            k += 1
        }
        return (solid, out)
    }

    /// The anchor rules (`MGSolidDocument.anchorIssues`) of every beat still at `width` × `height`: each beat's solid
    /// pane (`beatPanes`), its camera with the unblocked-focus rule and its automatic ghosts (`solidClearView`, the
    /// camera of the beat's still and of its hold frames in `story.mp4`), at the beat's end pose (`pose`). The poses
    /// during a beat's spin and `solid-0.png` are not tested.
    public static func beatAnchorIssues(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = MGAnnotationAnchorRules.width,
                                        height: Int = MGAnnotationAnchorRules.height) -> MGAnnotationAnchorReport {
        var out = MGAnnotationAnchorReport()
        let r = beatAnchorViews(doc, library: library, width: width, height: height)
        guard let d = r.solid else { return out }
        for v in r.views { out.append(d.anchorIssues(v)) }
        return out
    }

    /// The framed view of every beat still whose solid view shows a label or pointer, as `beatAnchorIssues` tests it,
    /// with the solid document they belong to.
    public static func beatAnchorViews(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = MGAnnotationAnchorRules.width,
                                       height: Int = MGAnnotationAnchorRules.height) -> (solid: MGSolidDocument?, views: [MGAnnotationAnchorView]) {
        beatViews(doc, library: library, width: width, height: height) { d, v in d.showsCheckedAnchor(v) }
    }

    /// The framed view of every beat still whose solid view shows a label, a pointer or an arrow: the views both the
    /// anchor checks and the arrow rule (`MGSolidDocument.arrowIssues`) test.
    public static func beatCheckViews(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = MGAnnotationAnchorRules.width,
                                      height: Int = MGAnnotationAnchorRules.height) -> (solid: MGSolidDocument?, views: [MGAnnotationAnchorView]) {
        beatViews(doc, library: library, width: width, height: height) { d, v in d.showsCheckedAnchor(v) || d.showsArrow(v) }
    }

    /// Every beat still with a solid pane at `width` × `height` (`beatPanes`), framed as the still and its story hold
    /// frames are (`solidClearView`: the automatic ghosts and the beat's arrow drops), at the beat's end pose, with the
    /// whole pane as its safe window and the beat's shot (`beatShot`: its 3D highlight and step); with the solid
    /// document. The subject rule and the small-unit rule of the check report read these.
    public static func beatStills(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = MGAnnotationAnchorRules.width,
                                  height: Int = MGAnnotationAnchorRules.height) -> (solid: MGSolidDocument?, stills: [MGFramedStill]) {
        let r = beatPanes(doc, library: library, width: width, height: height)
        guard let d = r.solid else { return (nil, []) }
        return (d, r.beats.map { b in
            let base = b.view.solid ?? d.view(step: nil)
            let clear = solidClearView(d, view: b.view, stepIndex: b.stepIndex, pane: b.pane)
            let still = MGAnnotationAnchorView(view: clear.view(base), params: pose(d, view: b.view), camera: clear.camera,
                                               width: Double(b.pane.width), height: Double(b.pane.height), step: b.stepIndex, beat: b.beat)
            var named: [String] = []
            if doc.beats.indices.contains(b.beat) {
                named = (doc.beats[b.beat].highlight ?? []).compactMap { if case .string(let x) = $0 { return x } else { return nil } }
                if case .object(let v)? = doc.beats[b.beat].view { named += MGSolidDocument.strings(v["focus"]) }
            }
            return MGFramedStill(still: still, shot: beatShot(d, view: b.view, stepIndex: b.stepIndex),
                                 window: MGSolidFraming.Window(titleBand: 0, captionBand: 0), rule: clear.rule, wholeInstances: d.instances(named),
                                 namedParts: d.namedParts(named))
        })
    }

    /// The framed view of every beat still whose solid view satisfies `shows`, with the solid document.
    static func beatViews(_ doc: MGExplainer, library: MGSolidLibrary, width: Int, height: Int,
                          where shows: (MGSolidDocument, MGSolidView) -> Bool) -> (solid: MGSolidDocument?, views: [MGAnnotationAnchorView]) {
        let r = beatPanes(doc, library: library, width: width, height: height)
        guard let d = r.solid, !d.annotations.isEmpty else { return (r.solid, []) }
        var out: [MGAnnotationAnchorView] = []
        for b in r.beats {
            let base = b.view.solid ?? d.view(step: nil)
            guard shows(d, base) else { continue }
            let clear = solidClearView(d, view: b.view, stepIndex: b.stepIndex, pane: b.pane)
            out.append(MGAnnotationAnchorView(view: clear.view(base), params: pose(d, view: b.view), camera: clear.camera,
                                              width: Double(b.pane.width), height: Double(b.pane.height), step: b.stepIndex, beat: b.beat))
        }
        return (d, out)
    }
}

/// A board item that a beat's board pane cuts (docs/EXPLAINER.md, "Board items inside the pane"): its box leaves the
/// pane's safe area at a 1280 × 800 frame. `board.clip.<id>`, a warning, with the exact move that brings it inside.
public struct MGBoardClip: Equatable, Sendable {
    public let id: String
    /// The 0-based beat whose pane cuts it first.
    public let beat: Int
    /// How far the item's box passes each side of the safe area, in pixels (0 when inside on that side).
    public let left: Double, right: Double, top: Double, bottom: Double
    /// Pixels per board unit in that pane.
    public let scale: Double
    /// The item's `at` (board units), when it has one.
    public let at: MGPoint?

    public var reason: String { "board.clip.\(id)" }

    /// The board-unit move (x right, y up) that brings the box inside the safe area, each part rounded away from zero
    /// to 0.01; nil when the box is wider or taller than the safe area (no move fits).
    public var move: (dx: Double, dy: Double)? {
        guard scale.isFinite, scale > 0, !(left > 0 && right > 0), !(top > 0 && bottom > 0) else { return nil }
        func up(_ px: Double) -> Double { (px / scale * 100).rounded(.up) / 100 }
        let dx = left > 0 ? up(left) : right > 0 ? -up(right) : 0
        let dy = top > 0 ? -up(top) : bottom > 0 ? up(bottom) : 0
        return (dx, dy)
    }

    static func n(_ x: Double) -> String { MGAnnotationAnchorIssue.number(x) }

    /// One line a tool can pass to a model (at most `MGAnnotationAnchorIssue.repairScalars` Unicode scalars).
    public var repair: String {
        var sides: [String] = []
        for (px, name) in [(top, "top"), (bottom, "bottom"), (left, "left"), (right, "right")] where px > 0 { sides.append("\(MGBoardClip.n(px.rounded(.up))) px past the \(name)") }
        let what = "Board item \(id) (beat \(beat + 1)) runs \(sides.joined(separator: " and ")) of the board pane's safe area, so the pane cuts it."
        guard let m = move else {
            return MGAnnotationAnchorIssue.bounded(what + " It does not fit the pane: give it fewer rows or columns, split it, or zoom the board out (`camera` zoom below 1).",
                                                   MGAnnotationAnchorIssue.repairScalars)
        }
        var line = what + " Move it by [\(MGBoardClip.n(m.dx)), \(MGBoardClip.n(m.dy))] board units"
        if let at { line += ": \"at\": [\(MGBoardClip.n(at.x + m.dx)), \(MGBoardClip.n(at.y + m.dy))]" }
        line += ", and keep the other items clear of it."
        return MGAnnotationAnchorIssue.bounded(line, MGAnnotationAnchorIssue.repairScalars)
    }

    /// `{"id", "reason", "beat", "overflow": {"left", "right", "top", "bottom"} (px), "scale", "at", "move", "repair"}`
    /// (`beat` 1-based; `at` and `move` [x, y] board units or null).
    public var json: MGJSON {
        func r(_ x: Double) -> MGJSON { x.isFinite ? .number((x * 1000).rounded() / 1000) : .null }
        return .object(["id": .string(id), "reason": .string(reason), "beat": .number(Double(beat + 1)),
                        "overflow": .object(["left": r(left), "right": r(right), "top": r(top), "bottom": r(bottom)]),
                        "scale": r(scale), "at": at.map { .array([r($0.x), r($0.y)]) } ?? .null,
                        "move": move.map { .array([r($0.dx), r($0.dy)]) } ?? .null, "repair": .string(repair)])
    }
}

extension MGExplainerFrame {
    /// The board pane's safe area: the pane less this many pixels on each side at a frame 1280 px wide.
    public static let boardSafeInset = 8.0

    /// The board items each beat's board pane cuts (`boardClips`), as `marty-solid render` lays the beats out: a fresh
    /// session with speech pacing and a manual clock plays the beats in order (as `beatPanes`); at each beat whose board
    /// pane is drawn (`MGExplainerSession.boardPane`) the settled board state is measured. Each item once, at the first
    /// beat that cuts it. Empty when the document does not load or has no board. Deterministic; at most
    /// `MGExplainerLimits.beats` beats.
    public static func beatBoardClips(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = MGAnnotationAnchorRules.width,
                                      height: Int = MGAnnotationAnchorRules.height) -> [MGBoardClip] {
        let clock = MGManualClock()
        var session = MGExplainerSession(pacing: .speech, clock: clock, library: library)
        guard case .success = session.load(doc), session.board != nil else { return [] }
        let solid = session.solid != nil
        let primarySolid = (session.primary ?? (solid ? "solid" : "board")) == "solid"
        var out: [MGBoardClip] = [], seen = Set<String>()
        var k = 0
        while k < MGExplainerLimits.beats, let beat = session.presented.beat, beat == k {
            clock.advance(by: session.motionRemaining)
            _ = session.tick()
            if session.boardPane.shown, let scene = session.state?.scene {
                for c in boardClips(scene: scene, beat: k, width: width, height: height, solid: solid, primarySolid: primarySolid)
                where seen.insert(c.id).inserted { out.append(c) }
            }
            _ = session.lineEnded(k)
            k += 1
        }
        return out
    }

    /// The items of `scene` that a board pane cuts at a `width` × `height` frame (docs/EXPLAINER.md, "Board items inside
    /// the pane"): the pane as `marty-solid render` lays it out (`panes`, side by side at `boardShare`, the viewport of the
    /// reference pane `boardReferenceSize` when both views show; the whole content area for a board alone), each item's
    /// box (`MGLayout.bounds`; empty tables and highlights skipped) against the pane less `boardSafeInset` × width / 1280
    /// on each side. Item order; nil `beat` labels are the caller's.
    public static func boardClips(scene: MGScene, beat: Int, width w: Int = MGAnnotationAnchorRules.width, height h: Int = MGAnnotationAnchorRules.height,
                                  solid: Bool, primarySolid: Bool) -> [MGBoardClip] {
        let both = solid
        let share = both ? boardShare(scene: scene, width: w, height: h, primarySolid: primarySolid) : nil
        guard let pane = panes(width: w, height: h, board: true, solid: solid, primarySolid: primarySolid, boardShare: share).board else { return [] }
        let area = contentArea(width: w, height: h)
        let size = CGSize(width: pane.width, height: pane.height)
        let fit = both && w >= h ? boardReferenceSize(areaWidth: Double(area.width), areaHeight: Double(area.height), gap: paneGap(width: w),
                                                      primarySolid: primarySolid) : size
        let vp = MGViewport(size: fit, width: scene.width, height: scene.height, camera: scene.camera).resized(to: size)
        let inset = boardSafeInset * Double(w) / 1280
        let safe = CGRect(x: inset, y: inset, width: Double(pane.width) - 2 * inset, height: Double(pane.height) - 2 * inset)
        var out: [MGBoardClip] = []
        for item in scene.items.prefix(MGLimits.resolvedItems) where item.kind != .highlight && !item.isEmptyTable {
            guard let r = MGLayout.bounds(item, in: scene.items, vp), !r.isNull, r.minX.isFinite, r.maxX.isFinite, r.minY.isFinite, r.maxY.isFinite else { continue }
            let left = max(0, Double(safe.minX - r.minX)), right = max(0, Double(r.maxX - safe.maxX))
            let top = max(0, Double(safe.minY - r.minY)), bottom = max(0, Double(r.maxY - safe.maxY))
            // Half a pixel of rounding is not a cut.
            guard max(left, right, top, bottom) > 0.5 else { continue }
            out.append(MGBoardClip(id: item.id, beat: beat, left: left, right: right, top: top, bottom: bottom, scale: Double(vp.scale),
                                   at: item.pts.count == 1 ? item.pts.first : nil))
        }
        return out
    }
}
