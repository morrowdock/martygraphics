// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest

/// `marty-solid` in fresh processes. Each process has its own hash seed, so a refusal chosen by dictionary order
/// would vary between runs; these tests also pin the exit codes (0 accepted, 1 refused, 2 usage) and JSON output.
final class MartySolidCLITests: XCTestCase {
    var binary: URL {
        // The test bundle sits next to the products, including the `marty-solid` executable.
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("marty-solid")
    }
    var models: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MartySolid3D/Models")
    }

    func run(_ args: [String]) throws -> (status: Int32, json: [String: Any]?, text: String) {
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, try? JSONSerialization.jsonObject(with: data) as? [String: Any], String(decoding: data, as: UTF8.self))
    }

    func write(_ text: String, _ name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marty-solid-cli-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    func testBinaryIsBuilt() {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), binary.path)
    }

    func testRefusalOrderIsTheSameInEveryProcess() throws {
        let box = #"{"box":{"size":[4,4,4]}}"#
        let names = ["bad one", "bad two", "bad 3", "bad four", "bad five", "bad six", "bad 7", "bad eight"]
        let anchors = try write(#"{"v":1,"kind":"component","id":"badAnchors","title":"T","about":"A.","parts":[{"id":"c","shape":\#(box)}],"anchors":{\#(names.map { #""\#($0)":"c""# }.joined(separator: ","))}}"#, "bad-anchors.json")
        let checks = try write(#"{"v":1,"kind":"component","id":"badChecks","title":"T","about":"A.","parts":[{"id":"c","shape":\#(box)}],"checks":{\#(names.map { #""\#($0)":{"lt":[1,2]}"# }.joined(separator: ","))}}"#, "bad-checks.json")
        for _ in 0..<10 {
            let a = try run(["component", "check", anchors]), c = try run(["component", "check", checks])
            XCTAssertEqual(a.status, 1)
            XCTAssertEqual(a.json?["reason"] as? String, "component.anchor.bad_3")
            XCTAssertEqual(c.status, 1)
            XCTAssertEqual(c.json?["reason"] as? String, "component.check.name.bad_3")
        }
    }

    func testExitCodesAndReports() throws {
        let catalog = try run(["components"])
        XCTAssertEqual(catalog.status, 0)
        XCTAssertEqual((catalog.json?["components"] as? [Any])?.count, 7)
        XCTAssertEqual(catalog.text.split(separator: "\n").count, 1)   // one line of compact JSON
        let accepted = try run(["check", models.appendingPathComponent("planetary-components.json").path])
        XCTAssertEqual(accepted.status, 0)
        XCTAssertEqual(accepted.json?["ok"] as? Bool, true)
        let refused = try run(["check", try write(#"{"v":1,"kind":"assembly","parts":[{"id":"s","use":"spurPair","with":{"module":50}}]}"#, "refused.json")])
        XCTAssertEqual(refused.status, 1)
        XCTAssertEqual(refused.json?["reason"] as? String, "component.param.range.module")
        XCTAssertEqual(refused.json?["part"] as? String, "s")
        let component = try run(["component", "check", try write(#"{"v":1,"kind":"component","id":"cube","title":"Cube","about":"One box.","parts":[{"id":"c","shape":{"box":{"size":[4,4,4]}}}]}"#, "cube.json")])
        XCTAssertEqual(component.status, 0)
        XCTAssertEqual((component.json?["use"] as? [String: Any])?["use"] as? String, "cube")
        XCTAssertEqual(try run(["bogus"]).status, 2)
        XCTAssertEqual(try run(["component", "check", "/nonexistent.json"]).status, 2)
    }

    func testStrictRefusesWhatTheNormalCheckOnlyWarns() throws {
        let idle = try write(#"{"v":2,"kind":"assembly","parts":[{"id":"disc","shape":{"shaft":{"radius":20,"length":5}},"joint":{"revolute":[0,0,1]}}],"steps":[{"say":"A disc on a joint."}]}"#, "idle.json")
        let normal = try run(["check", idle])
        XCTAssertEqual(normal.status, 0)
        XCTAssertEqual(normal.json?["ok"] as? Bool, true)
        XCTAssertEqual((normal.json?["warnings"] as? [[String: Any]])?.first?["reason"] as? String, "joint.idle.disc")
        for args in [["check", "--strict", idle], ["check", idle, "--strict"]] {
            let strict = try run(args)
            XCTAssertEqual(strict.status, 1)
            XCTAssertEqual(strict.json?["ok"] as? Bool, false)
            XCTAssertEqual(strict.json?["reason"] as? String, "joint.idle.disc")
            XCTAssertEqual(strict.json?["part"] as? String, "disc")
            XCTAssertEqual(strict.json?["strict"] as? Bool, true)
            XCTAssertNotNil(strict.json?["readBack"] as? [String])   // the full report is still printed
        }
        let example = try run(["check", "--strict", models.appendingPathComponent("horizontal-reduction.json").path])
        XCTAssertEqual(example.status, 0)
        XCTAssertEqual(example.json?["version"] as? Int, 2)
        XCTAssertEqual((example.json?["legend"] as? [String: Any])?["text"] as? String, "Solved 8 · Not checked 1")
        // Which fact filled each placeholder, and what each check proved.
        let stepFacts = example.json?["stepFacts"] as? [[String: Any]]
        XCTAssertEqual(stepFacts?[1]["facts"] as? [String], ["pinion.teeth", "wheel.teeth"])
        let check = (stepFacts?[3]["checks"] as? [[String: Any]])?.first
        XCTAssertEqual(check?["text"] as? String, "wheel.speed < 0")
        XCTAssertEqual(check?["comparison"] as? String, "lt")
        XCTAssertEqual(check?["target"] as? Double, 0)
        let exact = (stepFacts?[2]["checks"] as? [[String: Any]])?.first
        XCTAssertEqual(exact?["text"] as? String, "wheel.speed = -0.375 ± 1e-09")
        XCTAssertEqual(exact?["tolerance"] as? Double, 1e-9)
        XCTAssertEqual((example.json?["facts"] as? [String: Any]).flatMap { ($0["wheel.speed"] as? [String: Any])?["tier"] as? String }, "solved")
        XCTAssertEqual(try run(["check", "--strict", idle, idle]).status, 2)
        XCTAssertEqual(try run(["check", "--strict", "--strict", idle]).status, 2)
    }
}
