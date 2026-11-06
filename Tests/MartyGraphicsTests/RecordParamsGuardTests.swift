// SPDX-License-Identifier: Apache-2.0
// Guards for two record-parameter contracts: surplus `at` positions are refused, and every reserved reason suffix is
// refused as a record field name. Synthetic data only.
import XCTest
@testable import MartyGraphics

final class RecordParamsGuardTests: XCTestCase {
    override func tearDown() { MGPacks.resetRegistered() }

    func reason(_ json: String) -> String? {
        if case .failure(let e) = MGParser.scene(data: Data(json.utf8), extraTemplates: MGGraphPack.pack.templates) { return e.reason }
        return nil
    }

    /// "none or exactly one per node": surplus positions are refused, not ignored.
    func testSurplusNodePositionsAreRefused() {
        let base = #"{"v":1,"template":"shortest_path","params":{"n":3,"edges":[[0,1,1]],"at":"#
        XCTAssertNil(reason(base + #"[[1,3],[5,3],[9,3]]}}"#))
        XCTAssertEqual(reason(base + #"[[1,3],[5,3],[9,3],[9,6]]}}"#), "template.at.count")
    }

    /// Every reserved reason suffix is refused as a field name, at registration and lazily.
    func testEveryReservedSuffixIsRefusedAsAFieldName() {
        XCTAssertEqual(MGParamField.reservedNames, ["arity", "count", "integer", "missing", "spec"])
        for name in MGParamField.reservedNames.sorted() {
            let spec = MGParamSpec.records("r", count: 1...2, fields: [.init(name, 0...1)])
            let template = MGTemplate(name: "demo_reserved", summary: "", params: [spec],
                                      make: { _, _ in MGTemplateBuild(title: "x", items: [MGMake.body("b", MGPoint(1, 1))]) })
            XCTAssertEqual(template.declarationProblems, ["r: field '\(name)' is a reserved reason suffix"], name)
            let lazy = MGParser.scene(data: Data(#"{"v":1,"template":"demo_reserved","params":{"r":[[1]]}}"#.utf8), extraTemplates: [template])
            if case .failure(let e) = lazy { XCTAssertEqual(e.reason, "template.r.spec", name) } else { XCTFail(name) }
        }
    }
}
