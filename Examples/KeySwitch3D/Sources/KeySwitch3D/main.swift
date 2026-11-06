// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI
import KeySwitchModel
import MartyGraphics

// HOST EXAMPLE: a native window around one MartyGraphics 3D board. The parts list, notes, sliders and Reset are this
// example's SwiftUI; the engine draws the board, validates every update and resolves taps on the board.

private struct Inspector: View {
    @ObservedObject var session: KeySwitchSession

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            MartyGraphicsView(controller: session.controller)
                .selection(Binding(get: { session.selectionItem }, set: { session.select(item: $0) }))
                .emphasis(session.emphasis)
                .markers(KeySwitchModel.markers)
                .inspects3D([.selection, .emphasis, .dimming])   // explicit opt-in; without it a 3D board ignores the three above
                .preserves3DCamera(resetKey: session.cameraReset)
                .boardAccessibility(session.summary)
                .frame(minWidth: 520, maxWidth: .infinity, minHeight: 560)
            panel.frame(width: 320)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 640)
        .preferredColorScheme(.dark)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Schematic key switch").font(.title2.bold())
            Text("A schematic teaching model, not validated mechanics: parts move with the controls. Forces, bending, timing and real switch dimensions are not modelled.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Parts").font(.headline)
            ForEach(Array(KeySwitchModel.components.enumerated()), id: \.element.id) { n, part in
                Button { session.select(component: session.selected == part.id ? nil : part.id) } label: {
                    HStack {
                        Text("\(n + 1)").font(.caption.monospacedDigit()).frame(width: 18)
                        Text(part.name + (part.reference ? " (reference)" : ""))
                        Spacer()
                        if session.selected == part.id { Image(systemName: "checkmark") }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(session.selected == part.id ? .isSelected : [])
            }
            if let part = session.selectedComponent {
                Text(part.note).font(.callout).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Choose a part here or click it on the board.").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            slider("Press", value: session.params.press, range: 0...1) { session.set(press: $0) }
            slider("Explode", value: session.params.explode, range: 0...1) { session.set(explode: $0) }
            slider("Actuation", value: session.params.actuate, range: 0.3...0.8) { session.set(actuate: $0) }
            Text(session.state.contactClosed ? "Contacts closed" : "Contacts open")
                .font(.headline).foregroundStyle(session.state.contactClosed ? .green : .orange)
            if session.lastUpdateRefused { Text("That update was refused; the previous view is kept.").font(.caption) }
            Button("Reset view and parts") { session.reset() }
            Spacer(minLength: 0)
        }
    }

    /// 0.05 steps bound how many validated rebuilds one drag can request (at most 21 values per slider).
    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, _ set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title) \(Int((value * 100).rounded()))%").font(.subheadline)
            Slider(value: Binding(get: { value }, set: { set(($0 * 20).rounded() / 20) }), in: range, step: 0.05)
                .accessibilityLabel(title)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Headless scripted check of the example's state machine through the real engine (no window, no gestures).
@MainActor private func verify() throws -> Bool {
    let s = try KeySwitchSession()
    var ok = MGPacks.validate(KeySwitchModel.pack).isEmpty
    func check(_ label: String, _ condition: Bool) { print((condition ? "PASS " : "FAIL ") + label); ok = ok && condition }
    check("rest: contacts open", !s.state.contactClosed)
    check("press 0.6 accepted, contacts closed", s.set(press: 0.6) && s.state.contactClosed)
    check("press 1.5 refused, previous kept", !s.set(press: 1.5) && s.params.press == 0.6 && s.lastUpdateRefused)
    check("press 1 then explode 0.05: stem still past actuation, contacts closed and narrated as closed",
          s.set(press: 1) && s.set(explode: 0.05) && s.state.contactClosed
            && KeySwitchModel.narration(s.params).contains("contacts stay closed") && !KeySwitchModel.narration(s.params).contains("released"))
    check("explode 1 accepted, contacts open", s.set(explode: 1) && !s.state.contactClosed)
    s.select(item: "stem_leg")
    check("tap on stem leg selects the stem", s.selected == "stem" && s.emphasis == ["stem", "stem_leg"])
    let before = s.cameraReset
    check("reset restores rest, clears selection, bumps camera key",
          s.reset() && s.params == .rest && s.selected == nil && s.cameraReset == before + 1)
    check("scene after reset equals a fresh rest scene",
          s.controller.scene?.items == (try? KeySwitchModel.scene(.rest).get())?.items)
    return ok
}

@MainActor private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments {
    case ["--verify"]:
        let ok = try verify()
        print(ok ? "Verified the schematic key-switch example (state and validation only)." : "Verification FAILED")
        if !ok { exit(1) }
    case ["--preview"]:
        let session = try KeySwitchSession()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Schematic key switch"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Inspector(session: session))
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        withExtendedLifetime((delegate, window, session)) { application.run() }
    default:
        print("Usage: key-switch-3d --verify | --preview")
        exit(2)
    }
}

MainActor.assumeIsolated { do { try run() } catch { print("Error: \(error)"); exit(1) } }
