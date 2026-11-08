// SPDX-License-Identifier: Apache-2.0
import Foundation

// The adaptive board pane of an explainer: one deterministic rule that the renderer stills, the story video and the
// SwiftUI explainer view all read. Foundation only.

/// Whether the board pane is drawn at the shown state, and the board text that moves to the title band when it is not.
///
/// The rule (docs/EXPLAINER.md, "Adaptive board pane"): in an explainer with both a board and a solid, the board pane
/// is drawn only while the shown board state has at least one item that is not a `text` item (a table, a plot, a
/// shape, a vector, a highlight, any other kind). While the shown board has only `text` items (or none), the solid
/// takes the whole frame and the board's texts, in board order, move to the title band (`text`). An explainer with
/// only a board always draws it; an explainer with only a solid never has a board pane.
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
        if scene.items.contains(where: { $0.kind != .text }) { return MGExplainerBoardPane(shown: true) }
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
    /// with both panes, the `primary` view gets 55 % (side by side when wider than tall, else stacked, the first pane
    /// on top). `board` is false in a beat whose board pane is not drawn (`MGExplainerSession.boardPane`): the solid
    /// then takes the whole area.
    public static func panes(width w: Int, height h: Int, board: Bool, solid: Bool, primarySolid: Bool) -> (board: MGFrameRect?, solid: MGFrameRect?) {
        let s = Double(w) / 1280, gap = (16 * s).rounded()
        let x0 = Int((24 * s).rounded()), y0 = Int((132 * s).rounded())
        let area = MGFrameRect(x: x0, y: y0, width: max(1, w - 2 * x0), height: max(1, h - y0 - Int((112 * s).rounded())))
        guard board && solid else { return (board ? area : nil, solid ? area : nil) }
        var first = area, second = area
        if w >= h {
            let a = Int((Double(area.width) - gap) * 0.55), b = area.width - Int(gap) - a
            first.width = primarySolid ? b : a
            second.x = first.x + first.width + Int(gap); second.width = primarySolid ? a : b
        } else {
            let a = Int((Double(area.height) - gap) * 0.55), b = area.height - Int(gap) - a
            second.height = primarySolid ? a : b
            first.y = second.y + second.height + Int(gap); first.height = primarySolid ? b : a
        }
        return (first, second)
    }

    /// The pose of a beat view: the beat's explode and `spin` (0...1) of its spin played.
    public static func pose(_ doc: MGSolidDocument, view: MGExplainerBeatView, spin: Double = 1) -> MGPoseParameters {
        let step = view.step
        return MGPoseParameters(input: doc.defaults.input + (step?.spin ?? 0) * 2 * .pi * spin, explode: step?.explode ?? doc.defaults.explode)
    }

    /// The camera of the solid pane for one beat view: the assembly framing rule (`MGSolidFraming`) for the step the
    /// beat shows (`stepIndex`; nil for the plain view), at the beat's end pose, for the pane's own pixel size. The
    /// pane holds no title or caption, so the whole pane is the safe window. A beat's still and every hold frame of the
    /// beat in `story.mp4` use this camera.
    public static func solidCamera(_ doc: MGSolidDocument, view: MGExplainerBeatView, stepIndex: Int?, pane: MGFrameRect)
        -> (camera: MGSolidCamera, rule: MGSolidFraming.Rule) {
        let step = view.step
        let shot = MGSolidShot(file: "", params: pose(doc, view: view), preset: step?.camera ?? "hero", orbit: step?.orbit ?? 0,
                               highlight: view.solidHighlight, margin: 0.8, step: step == nil ? nil : stepIndex, title: nil, caption: nil)
        // (The camera of the pane only; captions, labels and claims of a story frame follow `MGStoryPlan.holds`.)
        return MGSolidFraming.framing(doc, shot: shot, aspect: pane.aspect, titleBand: 0, captionBand: 0)
    }
}

extension MGStoryPlan {
    /// The camera of frame `i` from each beat's camera (its still's camera; nil without a solid): during a beat's hold
    /// it is exactly that beat's camera; in the camera move at the start of a beat it lies between the previous beat's
    /// camera and this one (`camera(from:to:_:)`). A beat in `cuts` starts at its own camera (no move): the story cuts
    /// when the pane layout changes, because the previous camera was fitted for another pane.
    public func camera(frame i: Int, beatCameras: [MGSolidCamera?], cuts: Set<Int> = []) -> MGSolidCamera? {
        let f = frame(i)
        guard beatCameras.indices.contains(f.beat), let to = beatCameras[f.beat] else { return nil }
        guard f.camera < 1, f.beat > 0, !cuts.contains(f.beat), let from = beatCameras[f.beat - 1] else { return to }
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
