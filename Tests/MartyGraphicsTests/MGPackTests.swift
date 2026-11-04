// SPDX-License-Identifier: Apache-2.0
import XCTest
import MartyGraphics            // public API only: what a pack lane can use
@testable import MartyGraphics  // resetRegistered / builtIn

/// The pack registry: a pack built only from public API registers and parses; bad packs
/// are refused with a precise reason and nothing is registered.
final class MGPackTests: XCTestCase {
    override func tearDown() { MGPacks.resetRegistered() }

    /// A tiny public-API template: n dots in a row, one step per dot.
    static let dots = MGTemplate(
        name: "demo_dots", summary: "n dots in a row, one per step",
        params: [MGParamSpec(name: "n", unit: "", range: 1...6, integer: true)],
        make: { p, _ in
            let n = Int(p["n"])
            var items: [MGItem] = [], steps = [MGStep(say: "Count the dots.")]
            for i in 0..<n {
                items.append(MGMake.kind("d\(i)", .node, [MGPoint(1.5 + Double(i) * 1.6, 4)], ["r": 0.4]).with(text: "\(i + 1)"))
                steps.append(MGStep(say: "Dot {d\(i)}.", show: ["d\(i)"], focus: "d\(i)"))
            }
            var values: [String: MGValue] = ["n": MGValue(value: Double(n), unit: "")]
            for i in 0..<n { values["d\(i)"] = MGValue(value: Double(i + 1), unit: "") }
            return MGTemplateBuild(title: "Dots", items: items, steps: steps, values: values)
        })
    static func pack(id: String = "demo", templates: [MGTemplate] = [dots], json: String = #"{"v":1,"template":"demo_dots","params":{"n":3}}"#,
                     shots: [MGFewShot] = [MGFewShot(ask: "Show three dots.", fixture: "demo_three")]) -> MGPack {
        MGPack(id: id, title: "Demo", summary: "registry test pack", templates: templates,
               fixtures: [MGFixtures.Demo(id: "demo_three", title: "Three dots", json: json)], fewShots: shots)
    }

    func testPublicAPIPackRegistersAndRenders() throws {
        XCTAssertEqual(MGPacks.validate(Self.pack()), [])
        XCTAssertNil(MGTemplates.library["demo_dots"])
        try MGPacks.register(Self.pack())
        let scene = try MGParser.scene(data: Data(#"{"v":1,"template":"demo_dots","params":{"n":4}}"#.utf8)).get()
        XCTAssertEqual(scene.items.count, 4)
        XCTAssertEqual(scene.steps[2].say, "Dot 2.")
        XCTAssertEqual(MGPacks.pack(ofTemplate: "demo_dots")?.id, "demo")
        XCTAssertEqual(MGPacks.all.map(\.id).prefix(1), ["core"])
        // Patches resolve registered templates too.
        XCTAssertThrowsError(try MGPacks.register(Self.pack())) { XCTAssertEqual($0 as? MGPackError, .duplicatePack("demo")) }
    }

    func testBadPacksAreRefusedPrecisely() {
        XCTAssertEqual(MGPacks.validate(Self.pack(id: "Demo!")), [.badId("Demo!")])
        XCTAssertEqual(MGPacks.validate(Self.pack(templates: [Self.dots, MGTemplates.library["bst"]!])).first, .duplicateTemplate("bst"))
        XCTAssertEqual(MGPacks.validate(Self.pack(json: #"{"v":1,"template":"demo_dots","params":{"n":9}}"#)),
                       [.fixtureInvalid("demo_three", "template.n"), .templateWithoutFixture("demo_dots")])
        XCTAssertEqual(MGPacks.validate(Self.pack(shots: [MGFewShot(ask: "x", fixture: "nope")])), [.fewShotUnknown("nope")])
        XCTAssertThrowsError(try MGPacks.register(Self.pack(id: "x")))       // too short
        XCTAssertNil(MGTemplates.library["demo_dots"])                          // nothing registered on failure
    }

    /// Regression: concurrent registrations of packs that share a template name (or a pack id) — exactly one wins.
    func testConcurrentRegistrationsNeverDuplicate() {
        for round in 0..<20 {
            MGPacks.resetRegistered()
            let packs = (0..<8).map { k in Self.pack(id: "race\(round)_\(k)") }           // 8 packs, same template + fixture ids
            let wins = NSLock(); var won: [String] = []
            DispatchQueue.concurrentPerform(iterations: packs.count) { k in
                if (try? MGPacks.register(packs[k])) != nil { wins.lock(); won.append(packs[k].id); wins.unlock() }
            }
            XCTAssertEqual(won.count, 1, "round \(round): \(won)")
            XCTAssertEqual(MGPacks.all.flatMap(\.templates).filter { $0.name == "demo_dots" }.count, 1)
            // Same pack id raced: one wins too.
            MGPacks.resetRegistered()
            var same = 0
            DispatchQueue.concurrentPerform(iterations: 6) { _ in
                if (try? MGPacks.register(Self.pack())) != nil { wins.lock(); same += 1; wins.unlock() }
            }
            XCTAssertEqual(same, 1)
        }
    }

    /// Malformed public-API template output is refused with a reason, never a crash, and template
    /// metadata (steps, cameras, title, world) gets the wire checks.
    func testMalformedTemplateOutputIsRefusedNotTrapped() {
        func pack(_ build: @escaping () -> MGTemplateBuild) -> MGPack {
            let t = MGTemplate(name: "demo_bad", summary: "bad", params: [], make: { _, _ in build() })
            return MGPack(id: "demo_bad", title: "Bad", summary: "x", templates: [t],
                          fixtures: [MGFixtures.Demo(id: "demo_bad_1", title: "b", json: #"{"v":1,"template":"demo_bad","params":{}}"#)])
        }
        func reason(_ p: MGPack) -> String? { if case .fixtureInvalid(_, let r)? = MGPacks.validate(p).first { return r }; return nil }
        let good = MGMake.body("b", MGPoint(3, 3))
        // P1: an item with no geometry at all (each kind that serialises points).
        for kind in MGKind.allCases where ![.highlight, .edge].contains(kind) {
            XCTAssertNotNil(reason(pack { MGTemplateBuild(title: "x", items: [MGItem(id: "x", kind: kind, color: .blue)]) }), kind.rawValue)
        }
        // P2: step count, cameras, title and world size.
        XCTAssertEqual(reason(pack { MGTemplateBuild(title: "x", items: [good], steps: (0..<49).map { _ in MGStep(say: "x") }) }), "template.steps")
        XCTAssertNil(reason(pack { MGTemplateBuild(title: "x", items: [good], steps: (0..<48).map { _ in MGStep(say: "x") }) }))
        XCTAssertEqual(reason(pack { MGTemplateBuild(title: "x", items: [good], camera: MGCamera(zoom: 0)) }), "camera.zoom")
        XCTAssertEqual(reason(pack { MGTemplateBuild(title: "x", items: [good], steps: [MGStep(say: "x", camera: MGCamera(pitch: 120))]) }), "camera.pitch")
        XCTAssertEqual(reason(pack { MGTemplateBuild(title: "<b>x</b>", items: [good]) }), "template.title")
        XCTAssertEqual(reason(pack { MGTemplateBuild(title: "x", width: 1, items: [good]) }), "template.world")
        XCTAssertTrue(MGPacks.all.allSatisfy { $0.id != "demo_bad" })
    }

    func testCorePackIsValidAndComplete() {
        XCTAssertEqual(MGPacks.validate(MGPacks.core), [])
        XCTAssertEqual(Set(MGPacks.core.templates.map(\.name)), Set(MGTemplates.all.map(\.name)))
    }
}

private extension MGItem { func with(text: String) -> MGItem { var c = self; c.text = text; return c } }
