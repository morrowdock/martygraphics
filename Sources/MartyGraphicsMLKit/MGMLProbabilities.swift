// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

struct MLProbabilities: Equatable, Sendable {
    enum Stage: String, Sendable {
        case softmax, temperature, topK, topP
    }

    struct Candidate: Equatable, Sendable {
        let token: String
        let logit: Double
    }

    struct Distribution: Equatable, Sendable {
        let stage: Stage
        let parameter: Double?
        let probabilities: [Double]
        var sum: Double { probabilities.reduce(0, +) }
    }

    let tokens: [String]
    let candidates: [Candidate]
    let chosen: Int
    let distributions: [Distribution]

    init(_ input: MLObject) throws {
        tokens = try input.tokens("tokens")
        guard case .array(let raw)? = input.values["candidates"], (2...8).contains(raw.count) else {
            throw input.issue(.candidates, "candidates")
        }
        var seen = Set<String>()
        let candidates = try raw.enumerated().map { index, value in
            let candidate = try MLObject(value, path: "\(input.path).candidates[\(index)]", keys: ["token", "logit"])
            let token = try candidate.text("token", max: 16, reason: .candidates)
            guard seen.insert(token).inserted else { throw candidate.issue(.candidates, "token") }
            guard case .number(let logit)? = candidate.values["logit"], abs(logit) <= 1_000_000 else {
                throw candidate.issue(.logit, "logit")
            }
            return Candidate(token: token, logit: logit)
        }
        self.candidates = candidates
        let choice = try input.text("chosen", max: 16, reason: .chosen)
        guard let chosen = candidates.firstIndex(where: { $0.token == choice }) else {
            throw input.issue(.chosen, "chosen")
        }
        self.chosen = chosen

        func normalized(_ weights: [Double], stage: Stage, parameter: Double? = nil) throws -> Distribution {
            try Self.normalize(weights, stage: stage, parameter: parameter, issue: input.issue(.sum, "candidates"))
        }
        let logits = candidates.map(\.logit)
        let maximum = logits.max() ?? 0
        let relative = logits.map { $0 - maximum }
        var current = try normalized(relative.map { exp($0) }, stage: .softmax)
        var distributions = [current]
        if let value = input.values["temperature"] {
            guard case .number(let temperature) = value, (0.01...100).contains(temperature) else {
                throw input.issue(.temperature, "temperature")
            }
            current = try normalized(relative.map { exp($0 / temperature) }, stage: .temperature, parameter: temperature)
            distributions.append(current)
        }

        // Positive probabilities are monotone in the logits. Authored order breaks exact ties.
        let ranked = logits.indices.sorted { a, b in
            logits[a] == logits[b] ? a < b : logits[a] > logits[b]
        }
        if input.values["topK"] != nil {
            let k = try input.integer("topK", in: 1...candidates.count, reason: .topK)
            let retained = Set(ranked.prefix(k))
            let weights = logits.indices.map { retained.contains($0) ? current.probabilities[$0] : 0 }
            current = try normalized(weights, stage: .topK, parameter: Double(k))
            distributions.append(current)
        }
        if let value = input.values["topP"] {
            guard case .number(let p) = value, p > 0, p <= 1 else { throw input.issue(.topP, "topP") }
            var cumulative = 0.0
            var retained = Set<Int>()
            for index in ranked where current.probabilities[index] > 0 {
                retained.insert(index)
                cumulative += current.probabilities[index]
                // p = 1 keeps every positive entry, including those below one ulp of the running sum.
                if p < 1, cumulative >= p { break }
            }
            let weights = logits.indices.map { retained.contains($0) ? current.probabilities[$0] : 0 }
            current = try normalized(weights, stage: .topP, parameter: p)
            distributions.append(current)
        }
        guard current.probabilities[chosen] > 0 else { throw input.issue(.chosen, "chosen") }
        self.distributions = distributions
    }

    static func normalize(_ weights: [Double], stage: Stage, parameter: Double?, issue: MGMLIssue) throws -> Distribution {
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { throw issue }
        let distribution = Distribution(stage: stage, parameter: parameter, probabilities: weights.map { $0 / total })
        try checkSum(distribution, issue: issue)
        return distribution
    }

    static func checkSum(_ distribution: Distribution, issue: MGMLIssue) throws {
        guard distribution.probabilities.allSatisfy({ (0...1).contains($0) }),
              abs(distribution.sum - 1) <= MGMLKit.probabilityTolerance else { throw issue }
    }

    var facts: [String: MGJSON] {
        [
            "candidateTokens": .array(candidates.map { .string($0.token) }),
            "logits": .array(candidates.map { .number($0.logit) }),
            "chosen": .string(candidates[chosen].token),
            "tolerance": .number(MGMLKit.probabilityTolerance),
            "distributions": .array(distributions.map { distribution in
                .object(["step": .string(distribution.stage.rawValue), "sum": .number(distribution.sum),
                         "parameter": distribution.parameter.map(MGJSON.number) ?? .null,
                         "probabilities": .array(distribution.probabilities.map(MGJSON.number))])
            })
        ]
    }
}
