// SPDX-License-Identifier: Apache-2.0
import Foundation
import XCTest
@testable import MartyGraphics

/// Template steps are bounded by `MGLimits.templateSteps` (48), not the wire limit `MGLimits.steps` (8).
final class TwoPointersStepLimitTests: XCTestCase {
    private typealias R = MGRegression
    private func json(_ vals: [Int], _ target: Int) -> String {
        #"{"v":1,"template":"two_pointers","params":{"vals":\#(vals),"target":\#(target)}}"#
    }

    func testTwelveValueWalkReachesThePair() throws {
        let scene = try R.scene(json(Array(1...12), 23))
        XCTAssertEqual(scene.steps.count, 12)   // intro + 10 moves + the pair
        XCTAssertEqual(scene.steps.last?.say, "11 + 12 = 23. Found the pair.")
    }

    func testTwelveValueWalkWithoutPairEndsWithMeetingStep() throws {
        let scene = try R.scene(json(Array(1...12), 1000))
        XCTAssertEqual(scene.steps.last?.say, "The pointers met: no pair adds to 1000.")
        XCTAssertLessThanOrEqual(scene.steps.count, MGLimits.templateSteps)
    }

    func testWalkNeverExceedsTemplateStepLimit() throws {
        // At most 12 values, so the longest walk (intro + 11 moves + closing line) is far below the limit;
        // an over-limit template build would be refused as `template.steps`, never silently cut at 8.
        for target in [-1998, 3, 13, 23, 1998] {
            let result = MGParser.scene(data: Data(json(Array(1...12), target).utf8))
            let scene = try result.get()
            XCTAssertLessThanOrEqual(scene.steps.count, MGLimits.templateSteps)
        }
    }
}
