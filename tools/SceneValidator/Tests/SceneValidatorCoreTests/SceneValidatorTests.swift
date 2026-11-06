// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import MartyGraphics
import XCTest
@testable import SceneValidatorCore

/// Every test works inside a fresh temporary directory and passes relative paths, so expected output is exact
/// and no machine path appears in assertions or logs. All scenes are original synthetic examples.
final class SceneValidatorTests: XCTestCase {
    static let dot = #"{"v":1,"title":"Synthetic dot","items":[{"id":"dot","k":"body","at":[3,4]}]}"#
    static let tree = #"{"v":1,"template":"bst","params":{"values":[12,5,19,2,8],"find":8}}"#

    private var directory: URL!
    private var previousDirectory = ""

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-validator-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        previousDirectory = FileManager.default.currentDirectoryPath
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(directory.path))
    }

    override func tearDownWithError() throws {
        FileManager.default.changeCurrentDirectoryPath(previousDirectory)
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func write(_ name: String, _ text: String) throws -> String {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
        return name
    }

    private func run(_ arguments: String...) -> SceneValidator.Report { SceneValidator.run(arguments: arguments) }

    // MARK: valid and invalid scenes

    func testValidSceneExitsZeroWithSummary() throws {
        try write("dot.json", Self.dot)
        try write("tree.json", Self.tree)
        let report = run("dot.json", "tree.json")
        XCTAssertEqual(report.status, .valid)
        XCTAssertEqual(report.stderr, "")
        let tree = try MGParser.scene(data: Data(Self.tree.utf8)).get()
        XCTAssertEqual(report.stdout, """
            dot.json: valid (2d, 1 item, 0 steps)
            tree.json: valid (2d, \(tree.items.count) items, \(tree.steps.count) steps, template bst)
            Checked 2 files: 2 valid, 0 invalid, 0 unreadable.

            """)
    }

    func testEveryBuiltInFixtureValidates() throws {
        for fixture in MGPacks.core.fixtures {
            try write(fixture.id + ".json", fixture.json)
            XCTAssertEqual(SceneValidator.run(arguments: [fixture.id + ".json"]).status, .valid, fixture.id)
        }
    }

    func testMalformedJSONIsInvalid() throws {
        try write("truncated.json", #"{"v":1,"items":["#)
        try write("empty.json", "")
        let report = run("truncated.json", "empty.json")
        XCTAssertEqual(report.status, .invalid)
        XCTAssertEqual(report.stdout, """
            truncated.json: invalid: json (not valid JSON with an object or array at the top level)
            empty.json: invalid: json (not valid JSON with an object or array at the top level)
            Checked 2 files: 0 valid, 2 invalid, 0 unreadable.

            """)
    }

    func testParserReasonCodesAreReportedUnchanged() throws {
        let cases = [
            ("version.json", #"{"v":2,"items":[{"id":"dot","k":"body","at":[3,4]}]}"#, "scene.version"),
            ("duplicate.json", #"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]},{"id":"dot","k":"body","at":[4,4]}]}"#, "id.duplicate.dot"),
            ("unknown-key.json", #"{"v":1,"unknown":true,"items":[{"id":"dot","k":"body","at":[3,4]}]}"#, "scene.unknown.unknown"),
            ("array.json", "[]", "scene.object"),
            ("template.json", #"{"v":1,"template":"not_registered","params":{}}"#, "template.unknown")
        ]
        for (name, text, expected) in cases {
            try write(name, text)
            // The tool must agree with the engine itself, not with an approximation of it.
            guard case .failure(let engine) = MGParser.scene(data: Data(text.utf8)) else {
                return XCTFail("engine accepted \(name)")
            }
            XCTAssertEqual(engine.reason, expected, name)
            guard case .invalid(let reason, _) = SceneValidator.check(path: name) else {
                return XCTFail("tool accepted \(name)")
            }
            XCTAssertEqual(reason, expected, name)
        }
        XCTAssertEqual(run("template.json").stdout.components(separatedBy: "\n").first,
                       "template.json: invalid: template.unknown (not a built-in template; "
                       + "app-registered packs are not loaded by this tool)")
    }

    func testByteLimitMatchesParser() throws {
        let limit = SceneValidator.maximumInputBytes
        XCTAssertEqual(limit, MGLimits.sceneBytes * 2)
        let atLimit = Self.dot + String(repeating: " ", count: limit - Self.dot.utf8.count)
        let overLimit = atLimit + " "
        try write("at-limit.json", atLimit)
        try write("over-limit.json", overLimit)
        try write("huge.json", String(repeating: " ", count: 1 << 20))
        XCTAssertNoThrow(try MGParser.scene(data: Data(atLimit.utf8)).get())
        XCTAssertThrowsError(try MGParser.scene(data: Data(overLimit.utf8)).get())
        XCTAssertEqual(SceneValidator.check(path: "at-limit.json"),
                       .valid(dimension: "2d", items: 1, steps: 0, template: nil))
        let tooLarge = SceneValidator.Outcome.invalid(reason: "input.too-large", detail: "larger than \(limit) bytes")
        XCTAssertEqual(SceneValidator.check(path: "over-limit.json"), tooLarge)
        XCTAssertEqual(SceneValidator.check(path: "huge.json"), tooLarge)
    }

    // MARK: unreadable inputs

    func testMissingFileIsUnreadable() {
        let report = run("missing.json")
        XCTAssertEqual(report.status, .unreadable)
        XCTAssertEqual(report.stdout, """
            missing.json: unreadable: not-found (no such file)
            Checked 1 file: 0 valid, 0 invalid, 1 unreadable.

            """)
    }

    func testSpecialFilesAreRefusedWithoutBlocking() throws {
        XCTAssertEqual(mkfifo("pipe.json", 0o644), 0)
        try FileManager.default.createDirectory(atPath: "folder.json", withIntermediateDirectories: false)
        let started = Date()
        XCTAssertEqual(SceneValidator.check(path: "pipe.json"),
                       .unreadable(reason: "not-a-regular-file", detail: "FIFO"))
        XCTAssertEqual(SceneValidator.check(path: "folder.json"),
                       .unreadable(reason: "not-a-regular-file", detail: "directory"))
        XCTAssertEqual(SceneValidator.check(path: "/dev/null"),
                       .unreadable(reason: "not-a-regular-file", detail: "character device"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testSymlinksAreFollowedToRegularFilesOnly() throws {
        try write("dot.json", Self.dot)
        XCTAssertEqual(symlink("dot.json", "link.json"), 0)
        XCTAssertEqual(symlink("absent.json", "dangling.json"), 0)
        XCTAssertEqual(mkfifo("pipe", 0o644), 0)
        XCTAssertEqual(symlink("pipe", "pipe-link.json"), 0)
        XCTAssertEqual(SceneValidator.check(path: "link.json"), .valid(dimension: "2d", items: 1, steps: 0, template: nil))
        XCTAssertEqual(SceneValidator.check(path: "dangling.json"), .unreadable(reason: "not-found", detail: "no such file"))
        XCTAssertEqual(SceneValidator.check(path: "pipe-link.json"),
                       .unreadable(reason: "not-a-regular-file", detail: "FIFO"))
    }

    func testUnreadablePermissions() throws {
        try XCTSkipIf(geteuid() == 0, "root ignores file permissions")
        try write("locked.json", Self.dot)
        XCTAssertEqual(chmod("locked.json", 0), 0)
        defer { chmod("locked.json", 0o644) }
        XCTAssertEqual(SceneValidator.check(path: "locked.json"),
                       .unreadable(reason: "permission-denied", detail: "permission denied"))
    }

    // MARK: command line

    func testUsageErrorsExitTwoBeforeReadingFiles() {
        for arguments in [["--bogus", "missing.json"], ["missing.json", "-x"], [], ["--json"], ["-"], ["--"]] {
            let report = SceneValidator.run(arguments: arguments)
            XCTAssertEqual(report.status, .usage, "\(arguments)")
            XCTAssertEqual(report.stdout, "", "\(arguments)")
            XCTAssertTrue(report.stderr.hasSuffix("Try 'marty-scene-validate --help' for usage.\n"), "\(arguments)")
        }
        XCTAssertEqual(run("--bogus").stderr.components(separatedBy: "\n").first,
                       "marty-scene-validate: unknown option '--bogus'")
    }

    func testHelpExitsZeroAndDocumentsExitCodes() {
        for flag in ["--help", "-h"] {
            let report = run(flag)
            XCTAssertEqual(report.status, .valid)
            XCTAssertEqual(report.stdout, SceneValidator.usage)
            XCTAssertEqual(report.stderr, "")
        }
        for line in ["  0  every file is a valid scene", "  2  usage error; no file was read"] {
            XCTAssertTrue(SceneValidator.usage.contains(line), line)
        }
    }

    func testDoubleDashTreatsLaterArgumentsAsFiles() throws {
        try write("-dash.json", Self.dot)
        try write("--json", Self.dot)
        XCTAssertEqual(run("-dash.json").status, .usage)
        let report = run("--", "-dash.json", "--json")
        XCTAssertEqual(report.status, .valid)
        XCTAssertEqual(report.stdout, """
            -dash.json: valid (2d, 1 item, 0 steps)
            --json: valid (2d, 1 item, 0 steps)
            Checked 2 files: 2 valid, 0 invalid, 0 unreadable.

            """)
    }

    func testHelpMustBeUsedAloneRegardlessOfOrder() {
        for arguments in [["--help", "--bogus"], ["--bogus", "--help"],
                          ["missing.json", "--help"], ["--help", "missing.json"],
                          ["--json", "--help"]] {
            let report = SceneValidator.run(arguments: arguments)
            XCTAssertEqual(report.status, .usage)
            XCTAssertEqual(report.stdout, "")
        }
    }

    func testBidirectionalPathsAreEscapedWithoutChangingJSONValues() throws {
        let path = "scene\u{202e}\u{85}.json"
        try write(path, Self.dot)
        let text = run(path).stdout
        XCTAssertTrue(text.contains("scene\\u{202e}\\u{85}.json"))
        let json = run("--json", path).stdout
        XCTAssertFalse(json.contains("\u{202e}"))
        XCTAssertFalse(json.contains("\u{85}"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let files = try XCTUnwrap(document["files"] as? [[String: Any]])
        XCTAssertEqual(files.first?["path"] as? String, path)
    }

    func testMultipleFilesKeepOrderAndExitPrecedence() throws {
        try write("b.json", Self.dot)
        try write("a.json", "{}")
        XCTAssertEqual(run("b.json", "a.json").status, .invalid)
        XCTAssertEqual(run("a.json", "b.json").status, .invalid)
        let mixed = run("b.json", "missing.json", "a.json", "b.json")
        XCTAssertEqual(mixed.status, .unreadable)
        XCTAssertEqual(mixed.stdout, """
            b.json: valid (2d, 1 item, 0 steps)
            missing.json: unreadable: not-found (no such file)
            a.json: invalid: scene.missing
            b.json: valid (2d, 1 item, 0 steps)
            Checked 4 files: 2 valid, 1 invalid, 1 unreadable.

            """)
    }

    func testPathsWithSpacesAndControlCharacters() throws {
        try FileManager.default.createDirectory(atPath: "my scenes", withIntermediateDirectories: false)
        try write("my scenes/first scene.json", Self.dot)
        try write("odd\nname.json", "{}")
        let report = run("my scenes/first scene.json", "odd\nname.json")
        XCTAssertEqual(report.stdout, """
            my scenes/first scene.json: valid (2d, 1 item, 0 steps)
            odd\\u{a}name.json: invalid: scene.missing
            Checked 2 files: 1 valid, 1 invalid, 0 unreadable.

            """)
        XCTAssertEqual(SceneValidator.terminalSafe("a\u{1B}[31mb\\c"), "a\\u{1b}[31mb\\\\c")
    }

    func testJSONReportIsStableAndParsable() throws {
        try write("dot.json", Self.dot)
        try write("bad.json", #"{"v":2}"#)
        let report = run("--json", "dot.json", "bad.json", "missing.json")
        XCTAssertEqual(report.status, .unreadable)
        XCTAssertEqual(report.stdout, #"{"exitCode":3,"files":[{"dim":"2d","items":1,"path":"dot.json","status":"valid","steps":0},"#
            + #"{"path":"bad.json","reason":"scene.version","status":"invalid"},"#
            + #"{"detail":"no such file","path":"missing.json","reason":"not-found","status":"unreadable"}],"#
            + #""format":"marty-scene-validate/1","summary":{"invalid":1,"unreadable":1,"valid":1}}"# + "\n")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(report.stdout.utf8)))
        XCTAssertEqual(report.stdout, run("dot.json", "--json", "bad.json", "missing.json").stdout)
    }

    // MARK: the built executable

    /// Runs the real binary, failing (instead of hanging) if it does not exit promptly.
    private func execute(_ arguments: [String], shell: String? = nil) throws -> (status: Int32, stdout: String, stderr: String) {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let process = Process()
        process.executableURL = products.appendingPathComponent("marty-scene-validate")
        process.arguments = arguments
        if let shell {
            process.arguments = ["-c", shell, "probe", process.executableURL!.path] + arguments
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
        }
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            XCTFail("executable did not exit for \(arguments)")
        }
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func testExecutableExitStatuses() throws {
        try write("good scene.json", Self.dot)
        try write("bad.json", "not json")
        XCTAssertEqual(mkfifo("pipe.json", 0o644), 0)

        let valid = try execute(["good scene.json"])
        XCTAssertEqual(valid.status, 0)
        XCTAssertEqual(valid.stdout, "good scene.json: valid (2d, 1 item, 0 steps)\n"
                       + "Checked 1 file: 1 valid, 0 invalid, 0 unreadable.\n")
        XCTAssertEqual(try execute(["good scene.json", "bad.json"]).status, 1)
        let usage = try execute(["--nope"])
        XCTAssertEqual(usage.status, 2)
        XCTAssertEqual(usage.stdout, "")
        XCTAssertTrue(usage.stderr.contains("unknown option '--nope'"))
        XCTAssertEqual(try execute(["bad.json", "pipe.json"]).status, 3)
        XCTAssertEqual(try execute(["--help"]).status, 0)
    }

    func testClosedOutputDescriptorsExitFourWithoutCrashing() throws {
        let stdoutClosed = try execute(["--help"], shell: "exec \"$@\" 1>&-")
        XCTAssertEqual(stdoutClosed.status, 4)
        XCTAssertEqual(stdoutClosed.stderr, "marty-scene-validate: output write failed\n")
        let stderrClosed = try execute(["--bogus"], shell: "exec \"$@\" 2>&-")
        XCTAssertEqual(stderrClosed.status, 4)
        XCTAssertEqual(stderrClosed.stdout, "")
        XCTAssertEqual(stderrClosed.stderr, "")
    }
}
