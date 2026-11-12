// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest

/// `render --look`: a look changes pixels and nothing else. Every JSON the render writes is the same for every look.
extension MartySolidCLITests {
    func testAnUnknownLookIsAUsageErrorAndWritesNothing() throws {
        let model = models.appendingPathComponent("planetary-components.json").path
        for args in [["--look"], ["--look", "bogus"], ["--look", "Studio"], ["--look", ""]] {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("look-usage-\(UUID().uuidString)")
            XCTAssertEqual(try run(["render", model, out.path] + args).status, 2, "\(args)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "\(args)")
        }
    }

    func testALookChangesPixelsAndNoJSON() throws {
        let model = models.appendingPathComponent("planetary-components.json").path
        var manifests: [Data] = [], snapshots: [Data] = [], heroes: [Data] = []
        for look in [nil, "classic", "studio", "paper"] as [String?] {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("look-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: out) }
            let r = try renderOrSkip(["render", model, out.path, "--size", "640x400", "--no-loop", "--no-story"] + (look.map { ["--look", $0] } ?? []))
            XCTAssertEqual(r.status, 0, r.text)
            manifests.append(try Self.decidedManifest(out.appendingPathComponent("manifest.json")))
            snapshots.append(try Data(contentsOf: out.appendingPathComponent("snapshot.json")))
            heroes.append(try Data(contentsOf: out.appendingPathComponent("hero.png")))
        }
        XCTAssertEqual(Set(manifests).count, 1, "the decided manifest is the same for every look")
        XCTAssertEqual(Set(snapshots).count, 1, "snapshot.json is the same for every look")
        // The new looks draw a different picture (the two classic renders may differ by SceneKit's bounded noise).
        XCTAssertNotEqual(heroes[2], heroes[1]); XCTAssertNotEqual(heroes[3], heroes[1]); XCTAssertNotEqual(heroes[2], heroes[3])
    }
}
