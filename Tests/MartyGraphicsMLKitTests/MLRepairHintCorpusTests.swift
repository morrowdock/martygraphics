// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphicsMLKit

/// Every `MGMLReason` hint must equal the shared corpus (docs/fixtures/repair-hints/corpus.json), which the Python
/// mirror asserts too. A corpus reason with a null hint is not an ML reason.
final class MLRepairHintCorpusTests: XCTestCase {
    func testMLHintsMatchTheSharedCorpus() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/fixtures/repair-hints/corpus.json")
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let ml = try XCTUnwrap(corpus["ml"] as? [[String: Any]])
        var covered = Set<String>()
        for entry in ml {
            let raw = try XCTUnwrap(entry["reason"] as? String)
            let reason = MGMLReason(rawValue: raw)
            XCTAssertEqual(reason?.hint, entry["hint"] as? String, raw)
            if let reason { covered.insert(reason.rawValue) }
        }
        XCTAssertEqual(covered, Set(MGMLReason.allCases.map(\.rawValue)))
    }
}
