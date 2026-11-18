// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest

extension MartySolidCLITests {
    /// Captured on the pre-kit engine. The existing renderer's determinism contract excludes wall time,
    /// the executable digest and encoded 3D media pixels. Snapshots stay in the manifest with their digests.
    func testLegacyExplainersKeepTheirChecksAndRenderPlans() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("LegacyExplainers")
        let data = try Data(contentsOf: fixture.appendingPathComponent("check-digests.json"))
        let digests = try JSONDecoder().decode([String: [String: String]].self, from: data)
        let names = ["gears-3d", "gears-mixed", "planets-2d"]
        XCTAssertEqual(Set(digests.keys), Set(names))
        for name in names {
            let source = explainers.appendingPathComponent(name + ".explainer.json")
            for (mode, flags) in [("check", [String]()), ("strict", ["--strict"])] {
                let report = try run(["check"] + flags + [source.path])
                XCTAssertEqual(report.status, 0, name)
                let stable = report.text.replacingOccurrences(
                    of: #"(?m)^\s*"executableSHA256" : "[0-9a-f]+",\n"#, with: "", options: .regularExpression)
                XCTAssertEqual(Self.sha256(Data(stable.utf8)), digests[name]?[mode], "\(name) \(mode)")
            }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-explainer-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: out) }
            let rendered = try renderOrSkip(["render", source.path, out.path, "--size", "640x400",
                                             "--no-loop", "--no-story", "--snapshots"])
            XCTAssertEqual(rendered.status, 0, name)
            let want = try Data(contentsOf: fixture.appendingPathComponent(name + ".manifest.json"))
            let object = try JSONSerialization.jsonObject(with: want)
            let expected = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
            XCTAssertEqual(try Self.decidedManifest(out.appendingPathComponent("manifest.json")), expected, name)
        }
    }
}
