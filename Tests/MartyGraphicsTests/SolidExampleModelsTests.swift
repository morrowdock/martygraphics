// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// The worked example models referenced from docs/SOLID-3D.md must stay valid and keep the behaviour the docs describe.
final class SolidExampleModelsTests: XCTestCase {
    private func model(_ name: String) throws -> MGSolidDocument {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/Solid3D/Sources/MartySolid3D/Models/\(name).json")
        switch MGSolidParser.document(data: try Data(contentsOf: url)) {
        case .success(let d): return d
        case .failure(let e): XCTFail("\(name).json refused: \(e)"); throw e
        }
    }

    func testEveryExampleModelParsesWithClosedMeshes() throws {
        for name in ["planetary", "slider-crank", "propeller", "planetary-components", "slider-crank-component", "horizontal-reduction",
                     "idler-gearbox"] {
            let doc = try model(name)
            for part in doc.assembly.parts { XCTAssertTrue(part.mesh.edgeReport.isClosed, "\(name): \(part.id)") }
            XCTAssertLessThanOrEqual(doc.title.count, MGSolidLimits.title)
        }
    }

    func testSliderCrankStrokeIsTwiceTheCrankRadius() throws {
        let doc = try model("slider-crank")
        let x0 = doc.pose(MGPoseParameters(input: 0)).world["piston"]!.translation.x
        let x1 = doc.pose(MGPoseParameters(input: .pi)).world["piston"]!.translation.x
        XCTAssertEqual(abs(x0 - x1), 36, accuracy: 1e-9)
    }

    func testPropellerRepeatsTheBladeAndTurnsWithTheHub() throws {
        let doc = try model("propeller")
        XCTAssertEqual(doc.assembly.parts.filter { $0.id.hasPrefix("blade") }.count, 3)
        XCTAssertEqual(doc.ratios["hub"], 1)
    }
}
