// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphicsMLKit
import XCTest
import SceneValidatorCore

final class MLKitValidatorTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("MLGolden") }
    private var examples: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Explainers")
    }
    private var binary: URL {
        Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("marty-scene-validate")
    }

    private func strict(_ path: String) throws -> (Int32, Data) {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--ml-kit", "--strict", path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }

    func testMLKitStrictGoldenIsByteIdenticalAcrossProcesses() throws {
        for (input, golden, status) in [
            (fixtures.appendingPathComponent("vision.json"), "vision.strict.json", Int32(0)),
            (fixtures.appendingPathComponent("missing-caption.json"), "missing-caption.strict.json", Int32(1))
        ] {
            let expected = try Data(contentsOf: fixtures.appendingPathComponent(golden))
            let first = try strict(input.path), second = try strict(input.path)
            XCTAssertEqual(first.0, status, golden)
            XCTAssertEqual(second.0, status, golden)
            XCTAssertEqual(first.1, expected, golden)
            XCTAssertEqual(second.1, first.1, golden)
        }
    }

    /// `--hints` adds the reason's fix hint to a refusal; the default report stays byte-identical to its golden.
    func testMLKitStrictHintsAreOptIn() throws {
        let input = fixtures.appendingPathComponent("missing-caption.json").path
        let plain = SceneValidator.run(arguments: ["--ml-kit", "--strict", input])
        XCTAssertEqual(Data(plain.stdout.utf8), try Data(contentsOf: fixtures.appendingPathComponent("missing-caption.strict.json")))
        let hinted = SceneValidator.run(arguments: ["--ml-kit", "--strict", "--hints", input])
        XCTAssertEqual(hinted.status, .invalid)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(hinted.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(object["reason"] as? String, "ml.vision.caption")
        XCTAssertEqual(object["hint"] as? String, MGMLReason.caption.hint)
        XCTAssertTrue(MGMLReason.allCases.allSatisfy { !$0.hint.isEmpty && $0.hint.allSatisfy(\.isASCII) })
    }

    func testMLKitSamplesRequireOptInAndOutputIsDeterministic() throws {
        let names = ["ml-vision-pipeline", "ml-next-token-probabilities", "ml-agent-loop", "ml-combined"]
        for name in names {
            let path = examples.appendingPathComponent(name + ".json").path
            XCTAssertEqual(SceneValidator.run(arguments: ["--json", path]).status, .invalid)
            let first = try strict(path), second = try strict(path)
            XCTAssertEqual(first.0, 0, name)
            XCTAssertEqual(second.0, 0, name)
            XCTAssertEqual(first.1, second.1, name)
        }
        let path = examples.appendingPathComponent("ml-combined.json").path
        XCTAssertEqual(SceneValidator.run(arguments: ["--ml-kit", path]).status, .usage)
        XCTAssertEqual(SceneValidator.run(arguments: ["--strict", path]).status, .usage)
        XCTAssertEqual(SceneValidator.run(arguments: ["--ml-kit", "--strict", path, path]).status, .usage)
        XCTAssertEqual(SceneValidator.run(arguments: ["--ml-kit", "--strict", examples.path]).status, .unreadable)
    }
}
