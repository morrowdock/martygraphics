// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation
import MartyGraphics

/// HOST EXAMPLE LOGIC: inspection state for one key-switch board.
/// Parameters change only through validated engine patches; a refused update leaves both the scene and `params` as they were.
@MainActor
public final class KeySwitchSession: ObservableObject {
    public let controller: MGSceneController
    /// Parameters of the scene currently shown (only ever a set the engine accepted).
    @Published public private(set) var params = KeySwitchParams.rest
    /// Selected component id, or nil.
    @Published public private(set) var selected: String?
    /// Incremented by `reset()`; passed to `preserves3DCamera(resetKey:)`.
    @Published public private(set) var cameraReset = 0
    /// True when the most recent update was refused.
    @Published public private(set) var lastUpdateRefused = false

    public init() throws {
        try KeySwitchModel.registerPack()
        controller = MGSceneController(scene: try KeySwitchModel.scene(.rest).get())
    }

    public var state: KeySwitchState { KeySwitchModel.state(params) }
    public var selectedComponent: KeySwitchComponent? { selected.flatMap(KeySwitchModel.component(id:)) }
    /// The item the board treats as selected (first item of the selected component).
    public var selectionItem: String? { selectedComponent?.items.first }
    /// Every item of the selected component, so multi-item parts (the stem and its leg) light up together.
    public var emphasis: Set<String> { Set(selectedComponent?.items ?? []) }

    /// From a board tap: any item of a component selects that component; nil or an unknown item clears.
    public func select(item: String?) { selected = item.flatMap { KeySwitchModel.component(containing: $0)?.id } }
    /// From the parts list: an unknown id is ignored (selection unchanged); nil clears.
    public func select(component id: String?) {
        guard let id else { selected = nil; return }
        if KeySwitchModel.component(id: id) != nil { selected = id }
    }

    @discardableResult public func set(press: Double) -> Bool { var p = params; p.press = press; return update(p) }
    @discardableResult public func set(explode: Double) -> Bool { var p = params; p.explode = explode; return update(p) }
    @discardableResult public func set(actuate: Double) -> Bool { var p = params; p.actuate = actuate; return update(p) }

    /// Sends a revision-checked params patch. Out-of-range or non-finite values are refused by the engine (never clamped).
    @discardableResult public func update(_ next: KeySwitchParams) -> Bool {
        guard case .success(let patch) = KeySwitchModel.patch(next, revision: controller.scene?.revision),
              controller.apply(patch: patch, requireRevision: true) else { lastUpdateRefused = true; return false }
        params = next; lastUpdateRefused = false; return true
    }

    /// Rest parameters, no selection, and the scene camera again.
    @discardableResult public func reset() -> Bool {
        selected = nil
        cameraReset &+= 1
        return params == .rest ? { lastUpdateRefused = false; return true }() : update(.rest)
    }

    /// VoiceOver value for the board: the engine narration plus the selection.
    public var summary: String {
        KeySwitchModel.narration(params) + (selectedComponent.map { " Selected: \($0.name)." } ?? "")
    }
}
