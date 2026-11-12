// SPDX-License-Identifier: Apache-2.0
import AppKit
import CryptoKit
import Foundation
import WebKit

enum RenderError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case let .invalid(message): return message } }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func arguments() throws -> [String: String] {
    let values = Array(CommandLine.arguments.dropFirst())
    guard values.count == 8 else { throw RenderError.invalid("need --html FILE --out DIR --three-tarball FILE --lock FILE") }
    var result: [String: String] = [:]
    for index in stride(from: 0, to: values.count, by: 2) {
        guard ["--html", "--out", "--three-tarball", "--lock"].contains(values[index]),
              result[values[index]] == nil else { throw RenderError.invalid("unknown or duplicate argument") }
        result[values[index]] = values[index + 1]
    }
    return result
}

final class OfflineFiles: NSObject, WKURLSchemeHandler {
    let archive: URL
    let coreHash: String
    let archiveHash: String
    let sourceHash: String
    let html: Data
    var cache: [String: Data] = [:]

    init(options: [String: String]) throws {
        archive = URL(fileURLWithPath: options["--three-tarball"]!)
        let lockData = try Data(contentsOf: URL(fileURLWithPath: options["--lock"]!))
        guard let lock = try JSONSerialization.jsonObject(with: lockData) as? [String: Any],
              let arm = lock["arm2"] as? [String: Any], let three = arm["three"] as? [String: Any],
              three["version"] as? String == "0.170.0",
              let expected = three["tarballSha256"] as? String,
              let files = three["files"] as? [String: String],
              let core = files["build/three.module.min.js"] else { throw RenderError.invalid("invalid three.js lock") }
        guard sha256(try Data(contentsOf: archive)) == expected else { throw RenderError.invalid("three.js tarball SHA-256 mismatch") }
        archiveHash = expected
        coreHash = core
        let source = try String(contentsOfFile: options["--html"]!, encoding: .utf8)
        sourceHash = sha256(Data(source.utf8))
        let policy = "default-src 'none'; script-src bench: 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; font-src 'none'; frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        let insertion = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><script type=\"importmap\">{\"imports\":{\"three\":\"bench://local/build/three.module.min.js\",\"three/addons/\":\"bench://local/examples/jsm/\"}}</script>"
        if let head = source.range(of: "<head(?:\\s[^>]*)?>", options: [.regularExpression, .caseInsensitive]) {
            html = Data((String(source[..<head.upperBound]) + insertion + String(source[head.upperBound...])).utf8)
        } else {
            html = Data(("<!doctype html><head>" + insertion + "</head>" + source).utf8)
        }
        super.init()
        _ = try resource("build/three.module.min.js")
    }

    func resource(_ path: String) throws -> Data {
        guard path == "build/three.module.min.js" || path.hasPrefix("examples/jsm/"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }),
              path.hasSuffix(".js") else { throw RenderError.invalid("offline resource denied") }
        if let data = cache[path] { return data }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzOf", archive.path, "package/" + path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RenderError.invalid("pinned resource is missing: " + path) }
        if path == "build/three.module.min.js", sha256(data) != coreHash {
            throw RenderError.invalid("three.js module SHA-256 mismatch")
        }
        cache[path] = data
        return data
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        do {
            guard let url = task.request.url, url.scheme == "bench", url.host == "local",
                  url.query == nil, task.request.httpMethod == "GET" else { throw RenderError.invalid("offline URL denied") }
            let data = url.path == "/index.html" ? html : try resource(String(url.path.dropFirst()))
            let response = URLResponse(url: url, mimeType: url.path == "/index.html" ? "text/html" : "text/javascript",
                                       expectedContentLength: data.count, textEncodingName: "utf-8")
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch { task.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class RenderWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class Renderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let output: URL
    let offline: OfflineFiles
    let eventLog: FileHandle
    let started = ProcessInfo.processInfo.systemUptime
    var view: WKWebView!
    var window: NSWindow!
    var finished = false
    var loadedAt = 0.0
    var duration = 10.0
    var frameCount = 300
    var frame = 0
    var stillIndices = [30, 90, 150, 210, 270]
    var frames: [String] = []
    var errors: [String] = []
    var exceptions: [String] = []
    var console: [String] = []
    var notes: [String] = []
    var viewport: [String: Any] = [:]
    var activity: NSObjectProtocol?

    init(options: [String: String]) throws {
        output = URL(fileURLWithPath: options["--out"]!, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let eventURL = output.appendingPathComponent("events.ndjson")
        FileManager.default.createFile(atPath: eventURL.path, contents: nil)
        eventLog = try FileHandle(forWritingTo: eventURL)
        offline = try OfflineFiles(options: options)
        super.init()
    }

    func start() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Offline benchmark frame capture")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(offline, forURLScheme: "bench")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(self, name: "benchLog")
        let script = """
        (() => {
          const send = (kind, value) => window.webkit.messageHandlers.benchLog.postMessage({kind, value: String(value)});
          for (const kind of ['error', 'warn']) {
            const original = console[kind];
            console[kind] = (...values) => { send('console', kind + ': ' + values.map(value => {
              try { return typeof value === 'string' ? value : JSON.stringify(value); } catch { return String(value); }
            }).join(' ')); original.apply(console, values); };
          }
          addEventListener('error', event => send('exception', event.message || 'Resource load error'), true);
          addEventListener('unhandledrejection', event => send('exception', event.reason));
          addEventListener('securitypolicyviolation', event => send('console', 'blocked: ' + event.blockedURI + ' (' + event.violatedDirective + ')'));
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let rules = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^bench://local/"},"action":{"type":"ignore-previous-rules"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: UUID().uuidString, encodedContentRuleList: rules) { rules, error in
            guard let rules = rules, error == nil else { self.fail("offline rules: \(String(describing: error))"); return }
            config.userContentController.add(rules)
            self.open(config)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { self.fail("300 s render timeout") }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 300) {
            FileHandle.standardError.write(Data("R-WK: 300 s render timeout; see progress.json and events.ndjson\n".utf8))
            exit(124)
        }
    }

    func open(_ config: WKWebViewConfiguration) {
        guard !finished else { return }
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard view.responds(to: selector) else { fail("R-WK offscreen scheduling selector is unavailable"); return }
        let setOcclusion = unsafeBitCast(view.method(for: selector), to: (@convention(c) (AnyObject, Selector, Bool) -> Void).self)
        setOcclusion(view, selector, false)
        view.navigationDelegate = self
        window = RenderWindow(contentRect: NSRect(x: -1600, y: 0, width: 1280, height: 800),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        loadedAt = ProcessInfo.processInfo.systemUptime
        view.load(URLRequest(url: URL(string: "bench://local/index.html")!))
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if self.frame == 0 && self.frames.isEmpty && !self.finished && !self.ready { self.fail("benchReady timeout (30 s)") }
        }
    }

    var ready = false

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String: String], let value = data["value"] else { return }
        do {
            var line = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
            line.append(10)
            try eventLog.write(contentsOf: line)
            try eventLog.synchronize()
        } catch { fail("console recording: \(error)"); return }
        if data["kind"] == "exception" { exceptions.append(value) } else { console.append(value) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = !ready && navigationAction.request.url?.absoluteString == "bench://local/index.html"
        if !allowed { console.append("blocked navigation: " + (navigationAction.request.url?.absoluteString ?? "unknown")) }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { pollReady() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("navigation: \(error)") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("navigation: \(error)") }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("WebContent process terminated") }

    func pollReady() {
        guard !finished else { return }
        view.evaluateJavaScript("window.benchReady === true") { value, error in
            guard !self.finished else { return }
            if let error = error { self.fail("readiness: \(error)"); return }
            if value as? Bool == true {
                self.ready = true
                self.readDuration()
            } else if ProcessInfo.processInfo.systemUptime - self.loadedAt >= 30 {
                self.fail("benchReady timeout (30 s)")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.pollReady() }
            }
        }
    }

    func readDuration() {
        let script = """
        ({width: innerWidth, height: innerHeight, scale: devicePixelRatio,
          duration: typeof benchDuration === 'number' && Number.isFinite(benchDuration) ? benchDuration : null,
          frameFunction: typeof benchFrame === 'function'})
        """
        view.evaluateJavaScript(script) { value, error in
            guard let info = value as? [String: Any], error == nil else { self.fail("page properties: \(String(describing: error))"); return }
            self.viewport = ["width": info["width"] ?? NSNull(), "height": info["height"] ?? NSNull(), "scale": info["scale"] ?? NSNull()]
            guard info["width"] as? Int == 1280, info["height"] as? Int == 800, info["scale"] as? Double == 1 else {
                self.fail("viewport must be 1280x800 at scale 1; got \(self.viewport)"); return
            }
            guard let number = info["duration"] as? Double else { self.fail("benchDuration must be a finite number"); return }
            guard info["frameFunction"] as? Bool == true else { self.fail("benchFrame must be a function"); return }
            self.duration = min(60, max(10, number))
            if self.duration != number { self.notes.append("benchDuration clamped from \(number) to \(self.duration)") }
            self.frameCount = Int(ceil(30 * self.duration))
            self.stillIndices = [0.1, 0.3, 0.5, 0.7, 0.9].map { Int(floor(self.duration * 30 * $0)) }
            self.nextFrame()
        }
    }

    func nextFrame() {
        guard !finished else { return }
        if frame >= frameCount { finish(); return }
        checkpoint("benchFrame and two animation frames")
        guard !finished else { return }
        let script = "await window.benchFrame(time); await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); return true;"
        view.callAsyncJavaScript(script, arguments: ["time": Double(frame) / 30], in: nil, in: .page) { result in
            guard !self.finished else { return }
            switch result {
            case .failure(let error): self.fail("benchFrame: \(error)")
            case .success:
                self.checkpoint("composited snapshot")
                guard !self.finished else { return }
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: 1280, height: 800)
                config.snapshotWidth = 1280
                config.afterScreenUpdates = true
                self.view.takeSnapshot(with: config) { image, error in
                    guard !self.finished else { return }
                    do {
                        guard let image = image, error == nil,
                              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                              cg.width == 1280, cg.height == 800 else { throw RenderError.invalid("snapshot is not 1280x800: \(String(describing: error))") }
                        let bitmap = NSBitmapImageRep(cgImage: cg)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.invalid("PNG encode failed") }
                        let name = String(format: "frame-%06d.png", self.frame)
                        try png.write(to: self.output.appendingPathComponent(name))
                        self.frames.append(name)
                        self.frame += 1
                        self.nextFrame()
                    } catch { self.fail("capture: \(error)") }
                }
            }
        }
    }

    func fail(_ message: String) {
        guard !finished else { return }
        errors.append(message)
        finish()
    }

    func checkpoint(_ stage: String) {
        do {
            let state: [String: Any] = ["stage": stage, "frame": frame, "observedViewport": viewport,
                                        "seconds": ProcessInfo.processInfo.systemUptime - started]
            try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]).write(to: output.appendingPathComponent("progress.json"), options: .atomic)
        } catch { fail("progress recording: \(error)") }
    }

    func blankFraction(_ data: Data) throws -> Double {
        guard let image = NSBitmapImageRep(data: data)?.cgImage,
              let context = CGContext(data: nil, width: 1280, height: 800, bitsPerComponent: 8, bytesPerRow: 1280 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = context.data else { throw RenderError.invalid("cannot inspect still pixels") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1280, height: 800))
        let pixels = buffer.bindMemory(to: UInt32.self, capacity: 1280 * 800)
        var counts: [UInt32: Int] = [:]
        for index in 0..<(1280 * 800) { counts[pixels[index], default: 0] += 1 }
        return 1 - Double(counts.values.max() ?? 0) / Double(1280 * 800)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        do {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800,
                                          bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
            let placeholder = bitmap.representation(using: .png, properties: [:])!
            var stills: [String] = []
            var fractions: [Double] = []
            var placeholders: [Int] = []
            for (index, frameIndex) in stillIndices.enumerated() {
                let name = "still-\(index + 1).png"
                let data: Data
                if frameIndex < frames.count { data = try Data(contentsOf: output.appendingPathComponent(frames[frameIndex])) }
                else { data = placeholder; placeholders.append(index + 1) }
                try data.write(to: output.appendingPathComponent(name))
                stills.append(name)
                fractions.append(try blankFraction(data))
            }
            let report: [String: Any] = ["kind": "mechanisms-v1.r-wk/1", "renderer": "R-WK", "complete": frames.count == frameCount && errors.isEmpty,
                "duration": duration, "fps": 30, "width": 1280, "height": 800, "scale": 1,
                "observedViewport": viewport,
                "frames": frames, "stills": stills, "stillIndices": stillIndices, "nonModalPixelFractions": fractions,
                "allBlank": fractions.allSatisfy { $0 < 0.005 }, "placeholderStills": placeholders,
                "harnessErrors": errors, "exceptions": exceptions, "console": console, "notes": notes,
                "seconds": ProcessInfo.processInfo.systemUptime - started,
                "resourceSha256": offline.cache.mapValues { sha256($0) }, "htmlLoadedSha256": sha256(offline.html),
                "htmlSourceSha256": offline.sourceHash, "tarballSha256": offline.archiveHash,
                "rendererExecutableSha256": sha256(try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))),
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "webKitVersion": Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
            if let activity = activity { ProcessInfo.processInfo.endActivity(activity) }
            exit(errors.isEmpty ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("report error: \(error)\n".utf8))
            exit(2)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
do {
    let renderer = try Renderer(options: arguments())
    renderer.start()
    withExtendedLifetime(renderer) { application.run() }
} catch {
    FileHandle.standardError.write(Data("R-WK: \(error)\n".utf8))
    exit(2)
}
