// SPDX-License-Identifier: Apache-2.0
import Foundation

// Packs add templates through the public API without editing core files.
// Each pack supplies validated synthetic fixtures and optional example-reference metadata.
// Hosts may register packs at runtime; invalid registrations leave the registry unchanged.

/// Optional example metadata referencing a fixture; no model instructions are included.
public struct MGFewShot: Equatable, Sendable {
    public let ask: String
    /// Fixture id in the same pack.
    public let fixture: String
    public init(ask: String, fixture: String) { self.ask = ask; self.fixture = fixture }
}

/// A domain pack.
public struct MGPack {
    /// Lowercase id, e.g. "computing".
    public let id: String
    /// Gallery section title, e.g. "Computing".
    public let title: String
    public let summary: String
    public let templates: [MGTemplate]
    /// Gallery entries and test vectors (exact wire JSON). Each template needs at least one.
    public let fixtures: [MGFixtures.Demo]
    /// At most 3 example references per pack.
    public let fewShots: [MGFewShot]

    public init(id: String, title: String, summary: String, templates: [MGTemplate], fixtures: [MGFixtures.Demo], fewShots: [MGFewShot] = []) {
        self.id = id; self.title = title; self.summary = summary; self.templates = templates; self.fixtures = fixtures; self.fewShots = fewShots
    }
}

public enum MGPackError: Error, Equatable, CustomStringConvertible {
    case badId(String)
    case duplicatePack(String)
    case badTemplateName(String)
    case duplicateTemplate(String)
    case duplicateFixture(String)
    case fixtureInvalid(String, String)
    case templateWithoutFixture(String)
    case fewShotUnknown(String)
    case tooManyFewShots(String)

    public var description: String {
        switch self {
        case .badId(let s): return "pack id '\(s)': lowercase letters, digits, _ (2–24)"
        case .duplicatePack(let s): return "pack '\(s)' is already registered"
        case .badTemplateName(let s): return "template name '\(s)': lowercase letters, digits, _ (2–24)"
        case .duplicateTemplate(let s): return "template '\(s)' already exists"
        case .duplicateFixture(let s): return "fixture '\(s)' already exists"
        case .fixtureInvalid(let id, let why): return "fixture '\(id)' does not parse: \(why)"
        case .templateWithoutFixture(let s): return "template '\(s)' has no fixture"
        case .fewShotUnknown(let s): return "few-shot fixture '\(s)' is not in the pack"
        case .tooManyFewShots(let s): return "pack '\(s)' has more than 3 few-shots"
        }
    }
}

public enum MGPacks {
    /// Generic built-in templates with original synthetic validation fixtures.
    public static let core = MGPack(
        id: "core", title: "Core: generic scenes", summary: "trees and arrays",
        templates: MGTemplates.all, fixtures: MGFixtures.all)

    /// Compiled-in packs in stable registration order.
    static let builtIn: [MGPack] = [core]

    private static let lock = NSLock()
    /// Serialises whole registrations (validate + append) so two concurrent registrations can't both pass validation
    /// against a registry that has neither. Separate from `lock`, which fixture parsing takes through `library`.
    private static let registrationLock = NSLock()
    nonisolated(unsafe) private static var registered: [MGPack] = []
    nonisolated(unsafe) private static var cachedLibrary: [String: MGTemplate]?

    /// Built-in packs, then runtime registrations in order.
    public static var all: [MGPack] { lock.lock(); defer { lock.unlock() }; return builtIn + registered }

    /// Every template from every pack, by name.
    static var library: [String: MGTemplate] {
        lock.lock(); defer { lock.unlock() }
        if let cachedLibrary { return cachedLibrary }
        var lib: [String: MGTemplate] = [:]
        for p in builtIn + registered { for t in p.templates where lib[t.name] == nil { lib[t.name] = t } }
        cachedLibrary = lib
        return lib
    }

    /// The pack a template belongs to.
    public static func pack(ofTemplate name: String) -> MGPack? { all.first { $0.templates.contains { $0.name == name } } }

    /// Problems with `pack` against everything already registered (empty = OK). Pack tests should assert this is empty.
    public static func validate(_ pack: MGPack) -> [MGPackError] {
        // Against every other pack; re-validating an already registered pack (e.g. a built-in pack's own test) is fine.
        problems(pack, against: all.filter { $0.id != pack.id }, packIdTaken: false)
    }

    /// Register a pack at runtime (tests, external hosts). Throws the first problem; nothing is registered on failure.
    public static func register(_ pack: MGPack) throws {
        registrationLock.lock(); defer { registrationLock.unlock() }
        // Inside the registration lock, so no other registration can land between this check and the append.
        if all.contains(where: { $0.id == pack.id }) { throw MGPackError.duplicatePack(pack.id) }
        if let first = validate(pack).first { throw first }
        lock.lock(); defer { lock.unlock() }
        registered.append(pack); cachedLibrary = nil
    }

    /// Test support: drop runtime registrations.
    static func resetRegistered() {
        registrationLock.lock(); lock.lock(); registered = []; cachedLibrary = nil; lock.unlock(); registrationLock.unlock()
    }

    static func problems(_ pack: MGPack, against others: [MGPack], packIdTaken: Bool) -> [MGPackError] {
        var out: [MGPackError] = []
        func ok(_ s: String) -> Bool {
            (2...24).contains(s.count) && s.first!.isLetter && s.allSatisfy { ($0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "_" }
        }
        if !ok(pack.id) { out.append(.badId(pack.id)) }
        if packIdTaken { out.append(.duplicatePack(pack.id)) }
        let otherTemplates = Set(others.flatMap { $0.templates.map(\.name) })
        let otherFixtures = Set(others.flatMap { $0.fixtures.map(\.id) })
        var names = Set<String>(), fixtureIds = Set<String>()
        for t in pack.templates {
            if !ok(t.name) { out.append(.badTemplateName(t.name)) }
            if otherTemplates.contains(t.name) || !names.insert(t.name).inserted { out.append(.duplicateTemplate(t.name)) }
        }
        // Fixtures parse with this pack's templates visible (they may not be registered yet).
        var used = Set<String>()
        for f in pack.fixtures {
            if otherFixtures.contains(f.id) || !fixtureIds.insert(f.id).inserted { out.append(.duplicateFixture(f.id)) }
            switch MGParser.scene(data: Data(f.json.utf8), extraTemplates: pack.templates) {
            case .success(let s): if let t = s.template { used.insert(t) }
            case .failure(let e): out.append(.fixtureInvalid(f.id, e.reason))
            }
        }
        for t in pack.templates where !used.contains(t.name) { out.append(.templateWithoutFixture(t.name)) }
        if pack.fewShots.count > 3 { out.append(.tooManyFewShots(pack.id)) }
        for s in pack.fewShots where !fixtureIds.contains(s.fixture) { out.append(.fewShotUnknown(s.fixture)) }
        return out
    }
}
