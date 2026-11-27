// SPDX-License-Identifier: Apache-2.0
import Foundation

// The story video's plan for a document (`story.mp4`), built once for `marty-solid render` and for the caption export
// (`MGCaptionExport`): the beats, each beat's hold camera and solid view, and the routed camera moves
// (`MGStoryPlan.routes`). Read-only and deterministic: it renders nothing.

/// A document's story video as `marty-solid render` plays it: `plan` is the routed plan (`MGStoryPlan.routed`: beat
/// timing, captions, camera moves), `shots` the beats as the move router tested them (`MGStoryPlan.routes`, the poses of
/// `MGStoryPlan.movePose`; empty without a solid), and `holdViews` each beat's solid view during its hold, with its
/// still's automatic ghosts (empty without a solid). Each shot's `view` is the view its camera move draws
/// (`MGSolidView.moving(from:_:)`; the first beat's hold view).
public struct MGStoryShots: Sendable {
    public let plan: MGStoryPlan
    public let shots: [MGStoryBeatShot]
    public let holdViews: [MGSolidView]

    /// The routed plan for `unrouted` with one camera, pose, hold view and step per beat. Without a solid there are no
    /// moves to route: `plan` is `unrouted`.
    init(unrouted: MGStoryPlan, solid: MGSolidDocument?, cameras: [MGSolidCamera?], params: [MGPoseParameters], holdViews: [MGSolidView],
         steps: [MGSolidStep?]) {
        guard let d = solid, holdViews.count == unrouted.beats.count else { plan = unrouted; shots = []; self.holdViews = []; return }
        let shots = holdViews.indices.map { k in
            MGStoryBeatShot(camera: cameras[k], params: params[k], view: k == 0 ? holdViews[0] : holdViews[k].moving(from: holdViews[k - 1], d.assembly),
                            step: steps[k])
        }
        self.shots = shots
        self.holdViews = holdViews
        plan = unrouted.routed(MGStoryPlan.routes(d, beats: shots, plan: unrouted))
    }

    /// An assembly's story: one beat per step (caption `n. say`, the step's spin), each held at its step still's camera
    /// and automatic ghosts (`stills`, framed by `cameras`: `MGSolidRenderPlan.cameras` at the video's size), its move
    /// routed. Nil for an assembly without steps. Throws the plan's refusals (`story.rate`, `story.beats`,
    /// `story.frames`).
    public init?(assembly doc: MGSolidDocument, stills: MGSolidRenderPlan, cameras: MGSolidRenderPlan.Cameras,
                 fps: Int = MGStoryTiming.defaultRate) throws {
        guard !doc.steps.isEmpty else { return nil }
        let unrouted = try MGStoryPlan(captions: doc.steps.indices.map { "\($0 + 1). \(doc.steps[$0].say)" }, spins: doc.steps.map(\.spin), fps: fps)
        // The first still of each step (a plan has one per step).
        var stepStill: [Int: Int] = [:]
        for k in stills.stills.indices { if let s = stills.stills[k].step, stepStill[s] == nil { stepStill[s] = k } }
        let holdViews = doc.steps.indices.map { k in
            stepStill[k].flatMap { cameras.clear.indices.contains($0) ? cameras.clear[$0].view(doc.view(step: k)) : nil } ?? doc.view(step: k)
        }
        self.init(unrouted: unrouted, solid: doc, cameras: doc.steps.indices.map { k in stepStill[k].map { cameras.stills[$0] } },
                  params: doc.steps.indices.map { MGSolidShot.step(doc, $0)?.params ?? doc.defaults }, holdViews: holdViews,
                  steps: doc.steps.map { Optional($0) })
    }

    /// An assembly's story at `width` × `height`: the stills and cameras of `MGSolidRenderPlan` at that size.
    public init?(assembly doc: MGSolidDocument, source: MGSolidSource, width: Int, height: Int, fps: Int = MGStoryTiming.defaultRate) throws {
        let stills = MGSolidRenderPlan(doc, sourceName: "", source: source, loop: false)
        try self.init(assembly: doc, stills: stills, cameras: stills.cameras(doc, width: Double(width), height: Double(height)), fps: fps)
    }
}

extension MGStoryShots {
    /// The frame sizes `marty-solid render`, `export-captions` and `export-gltf` take (`--size WxH`), in pixels.
    public static let widths = 320...3840, heights = 200...2160

    /// `WxH` as a frame size: exactly two fields around one `x`, each only ASCII digits (no sign, no space, not empty),
    /// both parsed as integers before the bounds (`widths`, `heights`) are checked. Nil otherwise (`640xx400`, `640x`,
    /// `x400`, `640x400x1`, `+640x400`, a size out of bounds).
    public static func size(_ text: String) -> (width: Int, height: Int)? {
        let fields = text.split(separator: "x", omittingEmptySubsequences: false)
        guard fields.count == 2, fields.allSatisfy({ f in !f.isEmpty && f.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
              let w = Int(fields[0]), let h = Int(fields[1]), widths.contains(w), heights.contains(h) else { return nil }
        return (w, h)
    }
}

/// An explainer's beats as its story video shows them at `width` × `height`: a session with speech pacing presents the
/// beats in order, each settled (`MGExplainerSession.settledBeats`); each beat's panes (`MGExplainerFrame.panes`, the
/// adaptive board pane and its width), its solid pane's camera and automatic ghosts (`MGExplainerFrame.solidClearView`,
/// the camera of the beat's still and of its hold frames), and the story (`MGStoryShots`; nil without beats).
public struct MGExplainerStory: Sendable {
    /// One settled beat: its caption (placeholders filled; empty when the beat has none), its view and solid step, the
    /// board scene as the beat leaves it, and its solid pane's camera and framing (nil without a solid pane).
    public struct Beat: Sendable {
        public var caption: String
        public var view: MGExplainerBeatView
        public var stepIndex: Int?
        public var scene: MGScene?
        public var camera: MGSolidCamera?
        public var clear: MGSolidClearView?
    }

    public let title: String?
    public let solid: MGSolidDocument?
    public let beats: [Beat]
    public let story: MGStoryShots?

    /// Nil when the document does not load. Throws the plan's refusals (`story.rate`, `story.beats`, `story.frames`).
    public init?(_ doc: MGExplainer, library: MGSolidLibrary = .builtIn, width: Int = 1280, height: Int = 800,
                 fps: Int = MGStoryTiming.defaultRate) throws {
        let clock = MGManualClock()
        var session = MGExplainerSession(pacing: .speech, clock: clock, library: library)
        guard case .success = session.load(doc) else { return nil }
        let solid = session.solid
        let primarySolid = (session.primary ?? (solid != nil ? "solid" : "board")) == "solid"
        var beats: [Beat] = []
        MGExplainerSession.settledBeats(&session, clock: clock) { s, k in
            let view = s.presented, pane = s.boardPane, step = s.solidStep(forBeat: k)
            let share = pane.shown && solid != nil
                ? MGExplainerFrame.boardShare(scene: s.state?.scene, width: width, height: height, primarySolid: primarySolid) : nil
            let rects = MGExplainerFrame.panes(width: width, height: height, board: pane.shown, solid: solid != nil, primarySolid: primarySolid,
                                               boardShare: share)
            var clear: MGSolidClearView?
            if let d = solid, let r = rects.solid { clear = MGExplainerFrame.solidClearView(d, view: view, stepIndex: step, pane: r) }
            beats.append(Beat(caption: s.caption ?? "", view: view, stepIndex: step, scene: s.state?.scene, camera: clear?.camera, clear: clear))
        }
        title = session.title
        self.solid = solid
        self.beats = beats
        guard !beats.isEmpty else { story = nil; return }
        let unrouted = try MGStoryPlan(captions: beats.indices.map { "\($0 + 1). \(beats[$0].caption)" }, spins: beats.map { $0.view.step?.spin ?? 0 },
                                       fps: fps)
        let holdViews = solid.map { d in beats.map { b in b.clear?.view(b.view.solid ?? d.view(step: nil)) ?? (b.view.solid ?? d.view(step: nil)) } } ?? []
        story = MGStoryShots(unrouted: unrouted, solid: solid, cameras: beats.map(\.camera),
                             params: solid.map { d in beats.map { MGExplainerFrame.pose(d, view: $0.view) } } ?? [],
                             holdViews: holdViews, steps: beats.map(\.view.step))
    }
}

extension MGExplainerSession {
    /// Presents the beats of a loaded session in order, each settled, as the beat stills, the story video, the caption
    /// export and the transcript read them: the clock advances by `motionRemaining` (the board's motion plays out), one
    /// `tick`, then `body` reads the session at beat `k` (0-based), then the beat's line ends. Stops at the first beat
    /// that is not presented next, and after `MGExplainerLimits.beats` beats.
    public static func settledBeats(_ session: inout MGExplainerSession, clock: MGManualClock,
                                    _ body: (inout MGExplainerSession, Int) throws -> Void) rethrows {
        var k = 0
        while k < MGExplainerLimits.beats, let beat = session.presented.beat, beat == k {
            clock.advance(by: session.motionRemaining)
            _ = session.tick()
            try body(&session, k)
            _ = session.lineEnded(k)
            k += 1
        }
    }
}
