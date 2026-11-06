// SPDX-License-Identifier: Apache-2.0
import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import MartyGraphics

private struct Example {
    let id: String
    let category: String
    let title: String
    let detail: String
    let scene: MGScene
}

private let descriptions: [(String, String, String, String)] = [
    ("tree", "ALGORITHMS", "Follow a search", "Binary search tree · find 8"),
    ("two-pointers", "ALGORITHMS", "Walk an array", "Two pointers · find a pair totaling 14"),
    ("handoff", "SYSTEMS", "Trace a handoff", "Nodes and edges · an illustrative message flow"),
    ("function", "MATH", "See the samples", "Plot supplied points · y = x²"),
    ("counts", "DATA", "Compare quantities", "Bars · three explicitly synthetic counts"),
    ("motion", "MOTION", "Move through a scene", "Timeline · a geometric back-and-forth loop"),
    ("shortest-path", "GRAPHS", "Find the cheapest route", "Opt-in graph pack · Dijkstra over six routers")
]

private enum ShowcaseError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

private func loadExamples() throws -> [Example] {
    try descriptions.map { id, category, title, detail in
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Scenes") else {
            throw ShowcaseError.invalid("Missing bundled scene: \(id)")
        }
        let scene = try MGParser.scene(data: Data(contentsOf: url)).get()
        return Example(id: id, category: category, title: title, detail: detail, scene: scene)
    }
}

private struct Board: View {
    let example: Example
    let step: Int
    let time: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let scene = example.scene
        let size = CGSize(width: width, height: height)
        let items = MGTimeline.frame(scene, items: MGTimeline.items(scene, step: step), time: time)
        let focus = scene.steps.indices.contains(step) ? scene.steps[step].focus : nil
        let input = MGRenderInput(scene: scene, items: items,
                                  viewport: MGViewport(size: size, width: scene.width, height: scene.height, camera: scene.camera),
                                  focus: focus, time: time)
        Canvas { context, _ in MGCanvasRenderer.draw(input, in: context) }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct Card: View {
    let example: Example
    let step: Int
    let time: Double
    let width: CGFloat
    let boardHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(example.category).font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5).foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1))
            HStack(alignment: .firstTextBaseline) {
                Text(example.title).font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                if example.scene.steps.count > 1 {
                    Text("\(step + 1) / \(example.scene.steps.count)")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Text(example.detail).font(.system(size: 13)).foregroundStyle(.secondary)
            Board(example: example, step: step, time: time, width: width, height: boardHeight)
            if example.scene.steps.indices.contains(step) {
                Text(example.scene.steps[step].say).font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.84)).frame(height: 44, alignment: .topLeading)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(20)
        .background(Color(red: 0.055, green: 0.075, blue: 0.12), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .foregroundStyle(Color(white: 0.96))
    }
}

private struct Overview: View {
    let examples: [Example]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MARTYGRAPHICS / NATIVE SWIFT RENDERER")
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1))
                Text("Make the idea visible.").font(.system(size: 42, weight: .bold, design: .rounded))
                Text("Seven small scenes. One validated format. Actual engine output.")
                    .font(.system(size: 17)).foregroundStyle(Color(white: 0.68))
            }
            ForEach(0..<(examples.count + 1) / 2, id: \.self) { row in
                HStack(alignment: .top, spacing: 20) {
                    ForEach(row * 2..<min(row * 2 + 2, examples.count), id: \.self) { index in
                        let example = examples[index]
                        Card(example: example, step: max(0, example.scene.steps.count - 1), time: 1,
                             width: 500, boardHeight: 270)
                    }
                }
            }
            Text("Original synthetic examples • Apple SwiftUI Canvas • No browser recreation or model-generated imagery")
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.60))
        }
        .padding(36)
        .background(Color(red: 0.025, green: 0.035, blue: 0.065))
        .foregroundStyle(Color(white: 0.96))
        .environment(\.colorScheme, .dark)
    }
}

private struct InteractiveGallery: View {
    let examples: [Example]
    @State private var selection = "tree"

    var body: some View {
        let selected = examples.first { $0.id == selection } ?? examples[0]
        VStack(alignment: .leading, spacing: 18) {
            Text("MartyGraphics").font(.largeTitle.bold())
            Text("Choose a scene. Use the board's step and playback controls.")
                .foregroundStyle(.secondary)
            Picker("Example", selection: $selection) {
                ForEach(examples, id: \.id) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            MartyGraphicsView(scene: selected.scene).id(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(selected.detail).font(.callout).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 800, minHeight: 640)
        .preferredColorScheme(.dark)
    }
}

private final class ShowcaseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor private func image<V: View>(_ view: V) throws -> CGImage {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = 1
    guard let output = renderer.cgImage else { throw ShowcaseError.invalid("Native renderer returned no image") }
    return output
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ShowcaseError.invalid("Cannot create PNG: \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ShowcaseError.invalid("Cannot finalize PNG") }
}

@MainActor private func writeGIF(_ example: Example, to url: URL, animatedMotion: Bool) throws {
    let count = animatedMotion ? 32 : example.scene.steps.count
    guard count > 0,
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
        throw ShowcaseError.invalid("Cannot create GIF")
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in 0..<count {
        let step = animatedMotion ? 0 : frame
        let time = animatedMotion ? Double(frame) / 8 : 0
        let capture = try image(Card(example: example, step: step, time: time, width: 760, boardHeight: 440)
            .padding(20).background(Color(red: 0.025, green: 0.035, blue: 0.065)))
        let delay = animatedMotion ? 0.125 : 1.2
        CGImageDestinationAddImage(destination, capture,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw ShowcaseError.invalid("Cannot finalize GIF") }
}

@main struct Showcase {
    @MainActor static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments == ["--verify"] || arguments == ["--preview"] || (arguments.count == 2 && arguments[0] == "--export") else {
            throw ShowcaseError.invalid("Usage: marty-showcase --verify | --preview | --export NEW_OUTPUT_DIRECTORY")
        }
        // The graph pack is opt-in: a host registers it once before parsing scenes that use `shortest_path`.
        try MGPacks.register(MGGraphPack.pack)
        let examples = try loadExamples()
        guard examples.count == 7, MGPacks.validate(MGPacks.core).isEmpty, MGPacks.validate(MGGraphPack.pack).isEmpty else {
            throw ShowcaseError.invalid("Example or core pack validation failed")
        }
        print("Validated \(examples.count) original synthetic examples against MartyGraphics.")
        if arguments == ["--verify"] { return }
        if arguments == ["--preview"] {
            let application = NSApplication.shared
            let delegate = ShowcaseAppDelegate()
            application.delegate = delegate
            application.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "MartyGraphics Showcase"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: InteractiveGallery(examples: examples))
            window.center()
            window.makeKeyAndOrderFront(nil)
            application.activate(ignoringOtherApps: true)
            withExtendedLifetime((delegate, window)) { application.run() }
            return
        }

        let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ShowcaseError.invalid("Output directory already exists; choose a new directory")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        try writePNG(image(Overview(examples: examples)), to: output.appendingPathComponent("overview.png"))
        for example in examples {
            let capture = try image(Card(example: example, step: max(0, example.scene.steps.count - 1), time: 1,
                                         width: 760, boardHeight: 440)
                .padding(20).background(Color(red: 0.025, green: 0.035, blue: 0.065)))
            try writePNG(capture, to: output.appendingPathComponent(example.id + ".png"))
        }
        let pointers = examples.first { $0.id == "two-pointers" }!
        let motion = examples.first { $0.id == "motion" }!
        try writeGIF(pointers, to: output.appendingPathComponent("two-pointers.gif"), animatedMotion: false)
        try writeGIF(motion, to: output.appendingPathComponent("motion.gif"), animatedMotion: true)
        let route = examples.first { $0.id == "shortest-path" }!
        try writeGIF(route, to: output.appendingPathComponent("shortest-path.gif"), animatedMotion: false)
        print("Exported native PNG and GIF captures to the requested directory.")
    }
}
