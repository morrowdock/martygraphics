// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

/// Refusal tokens for the opt-in ML explainer format.
public enum MGMLReason: String, Error, CaseIterable, Sendable {
    case optIn = "ml.optIn"
    case bytes = "ml.bytes"
    case json = "ml.json"
    case object = "ml.object"
    case unknown = "ml.unknown"
    case version = "ml.version"
    case kind = "ml.kind"
    case title = "ml.title"
    case items = "ml.items"
    case itemKind = "ml.item.kind"
    case id = "ml.item.id"
    case duplicateID = "ml.item.id.duplicate"
    case caption = "ml.vision.caption"
    case citation = "ml.vision.citation"
    case visionSize = "ml.vision.size"
    case patchDivision = "ml.vision.patch.division"
    case patchCount = "ml.vision.patch.count"
    case embeddingWidth = "ml.vision.embeddingWidth"
    case visionLabel = "ml.vision.label"
    case tokens = "ml.tokens"
    case candidates = "ml.prob.candidates"
    case logit = "ml.prob.logit"
    case temperature = "ml.prob.temperature"
    case topK = "ml.prob.topK"
    case topP = "ml.prob.topP"
    case sum = "ml.prob.sum"
    case chosen = "ml.prob.chosen"
    case sweep = "ml.prob.sweep"
    case mapCount = "ml.map.count"
    case mapDuplicate = "ml.map.word.duplicate"
    case mapCoordinates = "ml.map.coordinates"
    case mapLengths = "ml.map.vector.length"
    case mapCosine = "ml.map.cosine"
    case mapCluster = "ml.map.cluster"
    case pictureCaption = "ml.picture.caption"
    case picturePNG = "ml.picture.png"
    case pictureSize = "ml.picture.size"
    case picturePatch = "ml.picture.patch.division"
    case pictureSelection = "ml.picture.patch.selection"
    case picturePresentation = "ml.picture.presentation"
    case generationCount = "ml.generation.count"
    case generationLogits = "ml.generation.logits"
    case generationSelection = "ml.generation.selection"
    case generationChosen = "ml.generation.chosen"
    case attentionGrid = "ml.attention.grid"
    case attentionQuery = "ml.attention.query"
    case attentionScores = "ml.attention.scores"
    case states = "ml.agent.states"
    case review = "ml.agent.review"
    case stop = "ml.agent.stop"
    case budget = "ml.agent.budget"
    case frame = "ml.render.frame"
    case raster = "ml.render.raster"
    case destination = "ml.export.destination"
    case exists = "ml.export.exists"
    case png = "ml.export.png"
}

public struct MGMLIssue: Error, Equatable, Sendable {
    public let reason: MGMLReason
    public let path: String
}

/// A strictly checked document. The renderer and exporter take only this type.
public struct MGMLDocument: Equatable, Sendable {
    public let title: String
    let items: [MLItem]
    public var itemCount: Int { items.count }
}

public enum MGMLKit {
    public static let maximumInputBytes = 16 * 1024
    public static let probabilityTolerance = 1e-12

    public static func check(data: Data, mlKit: Bool = false) -> Result<MGMLDocument, MGMLIssue> {
        guard mlKit else { return .failure(.init(reason: .optIn, path: "")) }
        guard data.count <= maximumInputBytes else { return .failure(.init(reason: .bytes, path: "")) }
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil,
              let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let json = MGJSON(any: raw) else { return .failure(.init(reason: .json, path: "")) }
        do {
            let root = try MLObject(json, path: "", keys: ["v", "kind", "title", "items"])
            guard root.values["v"] == .number(1) else { throw root.issue(.version, "v") }
            guard root.values["kind"] == .string("ml-explainer") else { throw root.issue(.kind, "kind") }
            let title = try root.text("title", max: 64, reason: .title)
            guard case .array(let rawItems)? = root.values["items"], (1...4).contains(rawItems.count) else {
                throw root.issue(.items, "items")
            }
            var ids = Set<String>()
            let items = try rawItems.enumerated().map { index, value in
                let path = "items[\(index)]"
                guard case .object(let values) = value else { throw MGMLIssue(reason: .object, path: path) }
                let kind: MLKind
                if case .string(let name)? = values["kind"], let parsed = MLKind(rawValue: name) {
                    kind = parsed
                } else { throw MGMLIssue(reason: .itemKind, path: path + ".kind") }
                let object = try MLObject(value, path: path, keys: kind.keys.union(["id", "kind"]))
                let id = try object.text("id", max: 24, reason: .id)
                guard id.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                    throw object.issue(.id, "id")
                }
                guard ids.insert(id).inserted else { throw object.issue(.duplicateID, "id") }
                switch kind {
                case .visionPipeline: return try MLItem(id: id, content: .vision(MLVision(object)))
                case .nextTokenProbabilities: return try MLItem(id: id, content: .probabilities(MLProbabilities(object)))
                case .agentLoop: return try MLItem(id: id, content: .agent(MLAgent(object)))
                case .pictureToNumbers: return try MLItem(id: id, content: .picture(MLPicture(object)))
                case .meaningMap: return try MLItem(id: id, content: .meaningMap(MLMeaningMap(object)))
                case .generationLoop: return try MLItem(id: id, content: .generation(MLGeneration(object)))
                case .attention: return try MLItem(id: id, content: .attention(MLAttention(object)))
                }
            }
            return .success(MGMLDocument(title: title, items: items))
        } catch let issue as MGMLIssue {
            return .failure(issue)
        } catch {
            return .failure(.init(reason: .json, path: ""))
        }
    }

    /// The sorted, deterministic JSON written by the opt-in strict check.
    public static func report(_ result: Result<MGMLDocument, MGMLIssue>) -> String {
        var fields: [String: MGJSON] = ["kind": .string("ml-explainer"), "version": .number(1), "strict": .bool(true)]
        switch result {
        case .success(let document):
            fields["ok"] = .bool(true)
            fields["title"] = .string(document.title)
            fields["items"] = .array(document.items.map(\.report))
        case .failure(let issue):
            fields["ok"] = .bool(false)
            fields["reason"] = .string(issue.reason.rawValue)
            fields["location"] = issue.path.isEmpty ? .null : .string(issue.path)
        }
        return MGSolidReport.text(.object(fields)) + "\n"
    }
}

enum MLKind: String, Sendable {
    case visionPipeline, nextTokenProbabilities, agentLoop, pictureToNumbers, meaningMap, generationLoop, attention

    var keys: Set<String> {
        switch self {
        case .visionPipeline:
            return ["caption", "citation", "imageSize", "patchSize", "embeddingWidth",
                    "embeddingWidthCitation", "projectorLabel", "languageModelLabel", "textTokens"]
        case .nextTokenProbabilities:
            return ["tokens", "candidates", "chosen", "temperature", "topK", "topP", "temperatures"]
        case .pictureToNumbers:
            return ["caption", "imagePNG", "patchSize", "highlight", "presentation"]
        case .meaningMap:
            return ["points", "vectors", "nearestNeighbors", "cluster", "vectorCitation"]
        case .generationLoop:
            return ["prompt", "stepCount", "steps", "selection", "seed"]
        case .attention:
            return ["imagePNG", "patchSize", "query", "scores"]
        case .agentLoop:
            return ["states", "requiresReview", "stepBudget"]
        }
    }
}

struct MLItem: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case vision(MLVision)
        case probabilities(MLProbabilities)
        case agent(MLAgent)
        case picture(MLPicture)
        case meaningMap(MLMeaningMap)
        case generation(MLGeneration)
        case attention(MLAttention)
    }

    let id: String
    let content: Content

    var report: MGJSON {
        let kind: MLKind
        let facts: [String: MGJSON]
        switch content {
        case .vision(let vision): (kind, facts) = (.visionPipeline, vision.facts)
        case .probabilities(let probabilities): (kind, facts) = (.nextTokenProbabilities, probabilities.facts)
        case .agent(let agent): (kind, facts) = (.agentLoop, agent.facts)
        case .picture(let picture): (kind, facts) = (.pictureToNumbers, picture.facts)
        case .meaningMap(let map): (kind, facts) = (.meaningMap, map.facts)
        case .generation(let generation): (kind, facts) = (.generationLoop, generation.facts)
        case .attention(let attention): (kind, facts) = (.attention, attention.facts)
        }
        return .object(["id": .string(id), "kind": .string(kind.rawValue), "facts": .object(facts)])
    }
}

struct MLObject {
    let values: [String: MGJSON]
    let path: String

    init(_ json: MGJSON, path: String, keys: Set<String>) throws {
        guard case .object(let values) = json else { throw MGMLIssue(reason: .object, path: path) }
        guard Set(values.keys).isSubset(of: keys) else { throw MGMLIssue(reason: .unknown, path: path) }
        self.values = values
        self.path = path
    }

    func issue(_ reason: MGMLReason, _ key: String) -> MGMLIssue {
        .init(reason: reason, path: path.isEmpty ? key : path + "." + key)
    }

    func text(_ key: String, max: Int, reason: MGMLReason) throws -> String {
        guard Self.safeText(values[key], max: max) else { throw issue(reason, key) }
        guard case .string(let text)? = values[key] else { throw issue(reason, key) }
        return text
    }

    func optionalText(_ key: String, max: Int, reason: MGMLReason) throws -> String? {
        guard values[key] != nil else { return nil }
        return try text(key, max: max, reason: reason)
    }

    func integer(_ key: String, in range: ClosedRange<Int>, reason: MGMLReason) throws -> Int {
        guard let result = Self.integer(values[key], in: range) else { throw issue(reason, key) }
        return result
    }

    func tokens(_ key: String) throws -> [String] {
        guard case .array(let values)? = values[key], (1...12).contains(values.count) else { throw issue(.tokens, key) }
        return try values.enumerated().map { index, value in
            guard case .string(let text) = value, Self.safeText(value, max: 16) else {
                throw issue(.tokens, "\(key)[\(index)]")
            }
            return text
        }
    }

    static func integer(_ value: MGJSON?, in range: ClosedRange<Int>) -> Int? {
        guard case .number(let number)? = value, number >= Double(range.lowerBound),
              number <= Double(range.upperBound) else { return nil }
        return Int(exactly: number)
    }

    static func safeText(_ value: MGJSON?, max: Int) -> Bool {
        guard case .string(let text)? = value, (1...max).contains(text.unicodeScalars.count),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.contains("<"), !text.contains(">"), !text.contains("://") else { return false }
        let prohibited = CharacterSet.controlCharacters.union(.newlines)
        return !text.unicodeScalars.contains { prohibited.contains($0) }
    }
}
