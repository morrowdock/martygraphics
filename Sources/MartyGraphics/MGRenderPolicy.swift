// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// When a MartyGraphics board may redraw continuously. Everything else is drawn once per state change:
/// static diagrams, paused motion, hidden or backgrounded boards and Reduce Motion never keep a frame loop alive.
/// Camera interaction in 3D still renders on demand (SceneKit redraws for gestures without continuous rendering).
public enum MGRenderPolicy {
    public struct State: Equatable, Sendable {
        /// The scene has motion and the learner hasn't paused it.
        public var motionPlaying: Bool
        /// A short-lived transition is still running (draw-on, patch blend, camera move, step focus pulse).
        public var transientActive: Bool
        /// The board is on screen (onAppear/onDisappear).
        public var visible: Bool
        /// The app's scene phase is `.active`.
        public var sceneActive: Bool
        public var reduceMotion: Bool
        public init(motionPlaying: Bool, transientActive: Bool, visible: Bool, sceneActive: Bool, reduceMotion: Bool) {
            self.motionPlaying = motionPlaying; self.transientActive = transientActive; self.visible = visible
            self.sceneActive = sceneActive; self.reduceMotion = reduceMotion
        }
    }

    /// 2D: run the TimelineView only while something is actually moving on a visible board in an active app.
    public static func continuous(_ s: State) -> Bool {
        s.visible && s.sceneActive && !s.reduceMotion && (s.motionPlaying || s.transientActive)
    }

    /// 3D: SceneKit plays (advances motion each frame) only for real motion; transitions don't apply in 3D.
    public static func sceneKitPlaying(_ s: State) -> Bool {
        s.visible && s.sceneActive && !s.reduceMotion && s.motionPlaying
    }

    /// How long a transition keeps the 2D loop alive: longest of patch blend (1.2 s), staggered draw-on (≈0.95 s)
    /// and camera move (1.0 s), plus a margin, so the final settled frame is what remains on screen.
    public static let transientSeconds: Double = 1.6

    /// 2D cadence while running. The motion here is smooth at 60 Hz; no need to ask ProMotion for 120.
    public static let frameInterval: Double = 1.0 / 60
}
