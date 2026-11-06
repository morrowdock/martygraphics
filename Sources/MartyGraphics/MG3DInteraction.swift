// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics

/// Pure decisions behind the opt-in 3D inspection hooks (tap selection, emphasis, camera keep/reset).
/// `MG3DView` only feeds them SceneKit hit results and applies the answers, so tests can check every rule
/// without a window, a gesture or a GPU.
enum MG3DInteraction {
    /// Same finger slop as the 2D board's hit test (12 pt).
    static let slop: CGFloat = 12

    /// Where one tap probes, as offsets from the touch point: the centre first, then a ring at half the slop
    /// and a ring at the full slop (8 points each, starting at +x, counter-clockwise). Thin parts such as
    /// path and line segments are a few points wide, so a single ray would usually miss them.
    static func tapSamples(slop: CGFloat = slop) -> [CGPoint] {
        var out = [CGPoint.zero]
        for radius in [slop / 2, slop] {
            for k in 0..<8 {
                let a = Double(k) * .pi / 4
                out.append(CGPoint(x: (radius * CGFloat(cos(a)) * 1e6).rounded() / 1e6,
                                   y: (radius * CGFloat(sin(a)) * 1e6).rounded() / 1e6))
            }
        }
        return out
    }

    /// Items a 3D tap may ever resolve to. Mirrors `MGLayout.hit` in 2D: highlights, axes and ground lines are
    /// never targets (a highlight halo surrounds its target, so it would otherwise always be the nearest hit).
    static func targets(_ items: [MGItem]) -> Set<String> {
        Set(items.filter { ![.highlight, .axes].contains($0.kind) && !$0.has("ground") }.map(\.id))
    }

    /// Resolves one tap to an item id.
    /// - `samples`: per probe (in `tapSamples` order), the hits nearest first; each hit is its node's ancestor chain,
    ///   starting with the node that was hit and ending at the scene root.
    /// - `roots`: the node that represents each pickable item (identity, not node names: an item may be called
    ///   "head" or "label"). Callers pass only `targets` here; anything else is skipped like empty space.
    /// - `selectable`: nil means every target; otherwise only these ids (e.g. the host's markers).
    /// The first probe that reaches any selectable item wins; inside a probe the nearest such hit wins. nil clears.
    /// (2D picks the smallest footprint under the finger instead; 3D has no footprint, so depth order decides.)
    static func pick<Key: Hashable>(_ samples: [[[Key]]], roots: [Key: String], selectable: Set<String>?) -> String? {
        for hits in samples {
            for chain in hits {
                guard let id = chain.lazy.compactMap({ roots[$0] }).first else { continue }
                if selectable?.contains(id) ?? true { return id }
            }
        }
        return nil
    }

    struct Style: Equatable {
        var opacity: Double
        var highlighted: Bool
        static let plain = Style(opacity: 1, highlighted: false)
    }

    /// Opacity of items outside the emphasis while something is emphasised and dimming was requested. Partial
    /// transparency alone made the other parts look deeper rather than dimmer in offscreen captures.
    static let dimmedOpacity = 0.2
    /// SceneKit emission intensity for emphasised items (1 is the unemphasised value). Higher values washed the
    /// emphasised colour out towards white in offscreen captures.
    static let highlightEmission = 1.6

    /// Per-item look for the current emphasis.
    /// - `drawn`: ids that have nodes; emphasis ids that are not drawn are ignored, so a stale id never dims the board.
    /// - `glow`: emphasised items get the stronger emission (the 3D counterpart of the 2D glow ring).
    /// - `dim`: everything else drops to `dimmedOpacity` (3D only; 2D emphasis never dims, so this is a separate opt-in).
    /// A highlight halo follows its target: it glows when the target (or the halo itself) is emphasised and dims
    /// with the target otherwise, so emphasising a highlighted part never erases its existing highlight cue.
    static func styles(items: [MGItem], drawn: Set<String>, emphasis: Set<String>, glow: Bool, dim: Bool) -> [String: Style] {
        let shown = emphasis.intersection(drawn)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: Style] = [:]
        for id in drawn {
            guard !shown.isEmpty, glow || dim else { out[id] = .plain; continue }
            let item = byID[id]
            let emphasised = shown.contains(id) || (item?.kind == .highlight && item?.ref.map { shown.contains($0) } == true)
            out[id] = emphasised ? Style(opacity: 1, highlighted: glow) : Style(opacity: dim ? dimmedOpacity : 1, highlighted: false)
        }
        return out
    }

    /// What the scene camera was last applied for. Width, height and identity (template + title, the same rule the
    /// host uses to decide that a scene is "the same scene") make a different or resized 3D scene re-frame the camera
    /// even while the learner's camera is being preserved.
    struct CameraKey: Equatable {
        var camera: MGCamera?
        var width: Double
        var height: Double
        var identity: String
        var reset: Int

        init(camera: MGCamera?, width: Double = 0, height: Double = 0, identity: String = "", reset: Int) {
            self.camera = camera; self.width = width; self.height = height; self.identity = identity; self.reset = reset
        }
        init(scene: MGScene, reset: Int) {
            self.init(camera: scene.camera, width: scene.width, height: scene.height,
                      identity: (scene.template ?? "") + "\u{1F}" + scene.title, reset: reset)
        }
    }

    /// Whether to move the SceneKit camera back to the scene camera.
    /// - Not preserving (the default, unchanged behaviour): every geometry rebuild re-applies the scene camera.
    /// - Preserving: only the first time, or when the scene camera, world size, scene identity or the host's reset key
    ///   changes; parameter patches and other rebuilds of the same scene keep the learner's orbit and zoom.
    static func placesCamera(preserving: Bool, rebuilt: Bool, last: CameraKey?, next: CameraKey) -> Bool {
        guard preserving else { return rebuilt }
        return last != next
    }

    /// The 3D hook arguments a host board derives from its teaching modifiers. Pure, so the view wiring
    /// (read-only, markers, selection ∪ emphasis, opt-in flags, camera key) is testable without SwiftUI.
    struct Hooks: Equatable {
        /// Taps are resolved and written to the selection binding.
        var selects = false
        /// nil = every target; otherwise only these ids (the host's markers).
        var selectable: Set<String>?
        var emphasis: Set<String> = []
        var glows = false
        var dims = false
        var cameraReset: Int?

        /// Exactly the original behaviour: no taps, no styling, camera re-placed on every rebuild.
        static let legacy = Hooks()

        /// - `selection`: whether a selection binding is set, and its current value.
        /// - `inspection`: the host's explicit opt-in. Without it the existing 2D modifiers have no 3D effect.
        static func derive(hasSelection: Bool, selected: String?, emphasis: Set<String>, markers: [String: Int],
                           inspection: MG3DInspection, cameraReset: Int?, readOnly: Bool) -> Hooks {
            var h = Hooks()
            h.selects = inspection.contains(.selection) && hasSelection && !readOnly
            h.selectable = h.selects && !markers.isEmpty ? Set(markers.keys) : nil
            h.glows = inspection.contains(.emphasis)
            h.dims = inspection.contains(.dimming)
            // Same composition as the 2D renderer input: the host's emphasis plus the current selection.
            if h.glows || h.dims { h.emphasis = emphasis.union(selected.map { [$0] } ?? []) }
            h.cameraReset = cameraReset
            return h
        }
    }
}
