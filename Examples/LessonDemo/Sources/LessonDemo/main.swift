// SPDX-License-Identifier: Apache-2.0
import Foundation
import LessonDemoKit
#if os(macOS)
import AppKit
import SwiftUI
import MartyGraphics

// HOST EXAMPLE: a native window around the public MartyGraphics lesson view. The lesson, slider and beats are engine
// features; the Play / Stream buttons and the state fingerprint are this example's SwiftUI.

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// PNGs of the live demo view at each beat (review receipts, not pixel-gated). The view is hosted in an offscreen
/// window and captured after its transitions settle, so draw-on and native controls render as on screen.
@MainActor private func render(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let model = LessonDemoModel(pacing: .speech)
    model.play()
    for (w, h) in [(1366, 1024), (1024, 768)] {
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: LessonDemoView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        window.contentView = host
        window.orderFrontRegardless()
        model.play()
        for k in 0..<5 {
            if k == 4 { model.controller.control("angle", 45) }   // the learner moved the slider during beat 4
            if k > 0 { model.controller.lineEnded(k - 1) }
            // Wait past the transition: an offscreen window has no display link, so only the settled redraw is captured.
            RunLoop.main.run(until: Date().addingTimeInterval(3.0))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = directory.appendingPathComponent("beat\(k + 1)-\(w)x\(h).png")
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
        window.close()
    }
}

@MainActor private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "--verify":
        let result = RotationLesson.verify()
        result.lines.forEach { print($0) }
        print(result.ok ? "Verified the rotation lesson example (state, narration and validation only)." : "Verification FAILED")
        if !result.ok { exit(1) }
    case "--timing":
        print(LessonTiming.report(LessonTiming.run()))
    case "--render" where arguments.count == 2:
        try render(to: URL(fileURLWithPath: arguments[1]))
    case "--preview":
        let model = LessonDemoModel()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Rotating a triangle"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LessonDemoView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        model.play()
        application.activate(ignoringOtherApps: true)
        application.run()
    default:
        print("usage: lesson-demo --verify | --timing | --render <directory> | --preview")
        exit(2)
    }
}

MainActor.assumeIsolated { do { try run() } catch { print("error: \(error)"); exit(1) } }
#else
print("lesson-demo is a macOS command; on iPadOS embed LessonDemoKit.LessonDemoView in an app.")
#endif
