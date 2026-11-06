// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import MartyGraphics

/// The demo screen: the public `MartyGraphicsLessonView` with the rotation lesson, plus demo-only controls
/// (play as a document, stream it statement by statement like a model reply, restart) and a debug state fingerprint.
@MainActor
public final class LessonDemoModel: ObservableObject {
    public let controller: MGLessonController
    private var streaming: Task<Void, Never>?

    public init(pacing: MGPacing = .estimate(wordsPerSecond: 2.5)) {
        RotationLesson.register()
        controller = MGLessonController(pacing: pacing)
    }

    /// Load the whole document (all-or-nothing) and start the beats.
    public func play() {
        streaming?.cancel()
        controller.begin()
        if let lesson = try? RotationLesson.lesson() { controller.load(lesson) }
    }

    /// Feed the statements one at a time with a delay, as a model stream would arrive.
    public func stream(every delay: Duration = .milliseconds(120)) {
        streaming?.cancel()
        controller.begin()
        guard let statements = try? RotationLesson.statements() else { return }
        streaming = Task { [controller] in
            for line in statements {
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
                controller.feed(line + "\n")
            }
            controller.endStream()
        }
    }
}

public struct LessonDemoView: View {
    @ObservedObject var model: LessonDemoModel
    @ObservedObject var controller: MGLessonController

    public init(model: LessonDemoModel) { self.model = model; controller = model.controller }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MartyGraphicsLessonView(controller: controller)
            HStack(spacing: 12) {
                Button("Play lesson") { model.play() }.accessibilityIdentifier("demo.play")
                Button("Stream it") { model.stream() }.accessibilityIdentifier("demo.stream")
                Spacer()
                if let t = controller.timing.timeToFirstVisible {
                    Text("first visible \(Self.ms(t)) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(RotationLesson.fingerprint(controller.state)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("demo.stateHash")
                    .accessibilityValue(RotationLesson.fingerprint(controller.state))
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(Color(red: 0.05, green: 0.07, blue: 0.11))
        .preferredColorScheme(.dark)
    }

    static func ms(_ d: Duration) -> String {
        String(format: "%.0f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }
}
