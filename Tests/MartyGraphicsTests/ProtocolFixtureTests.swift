// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
import MartyGraphics

final class ProtocolFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("docs/fixtures/v1/" + name))
    }

    func testVersionOneDocumentationFixtures() throws {
        let scene = try MGParser.scene(data: fixture("scene.json")).get()
        let patch = try MGPatch.parse(data: fixture("title.patch.json")).get()
        let updated = try scene.applying(patch).get()
        XCTAssertEqual(updated.title, "Synthetic dot")
        XCTAssertEqual(updated.revision, 1)
        XCTAssertEqual(scene.revision, 0)
        guard case .failure(let stale) = updated.applying(patch) else {
            return XCTFail("Reapplying the documented revision must fail")
        }
        XCTAssertEqual(stale.reason, "patch.stale")
        for (file, reason) in [("unknown-key.scene.json", "scene.unknown.unknown"),
                               ("highlight-cycle.scene.json", "highlight.cycle")] {
            guard case .failure(let error) = MGParser.scene(data: try fixture(file)) else {
                return XCTFail("Negative documentation fixture accepted: " + file)
            }
            XCTAssertEqual(error.reason, reason, file)
        }
    }
}
