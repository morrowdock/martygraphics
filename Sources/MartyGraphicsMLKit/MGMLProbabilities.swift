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
        var removed: Set<Int> = []

        func percentageLabel(at index: Int) -> String {
            if removed.contains(index) { return "removed" }
            let percent = probabilities[index] * 100
            return MLBoard.number(percent, precision: percent > 0 && percent < 0.05 ? "%.3g" : "%.2f") + "%"
        }

        var sum: Double { probabilities.reduce(0, +) }
    }

    let tokens: [String]
    let candidates: [Candidate]
    let chosen: Int
    let distributions: [Distribution]
    let isSweep: Bool

    init(_ input: MLObject) throws {
        tokens = try input.tokens("tokens")
        let candidates = try Self.readCandidates(input)
        self.candidates = candidates
        let choice = try input.text("chosen", max: 16, reason: .chosen)
        guard let chosen = candidates.firstIndex(where: { $0.token == choice }) else {
            throw input.issue(.chosen, "chosen")
        }
        self.chosen = chosen

        func normalized(_ weights: [Double], stage: Stage, parameter: Double? = nil,
                        removed: Set<Int> = []) throws -> Distribution {
            try Self.normalize(weights, stage: stage, parameter: parameter, removed: removed, issue: input.issue(.sum, "candidates"))
        }
        let logits = candidates.map(\.logit)
        let sumIssue = input.issue(.sum, "candidates")
        isSweep = input.values["temperatures"] != nil
        if isSweep {
            guard case .array(let values)? = input.values["temperatures"], (2...4).contains(values.count),
                  ["temperature", "topK", "topP"].allSatisfy({ input.values[$0] == nil }) else {
                throw input.issue(.sweep, "temperatures")
            }
            var seen = Set<Double>()
            distributions = try values.enumerated().map { index, value in
                guard let temperature = Self.temperature(value), seen.insert(temperature).inserted else {
                    throw input.issue(.sweep, "temperatures[\(index)]")
                }
                return try Self.softmax(logits, temperature: temperature, issue: sumIssue)
            }
            guard let final = distributions.last, final.probabilities[chosen] > 0 else {
                throw input.issue(.chosen, "chosen")
            }
            return
        }

        var current = try Self.softmax(logits, temperature: nil, issue: sumIssue)
        var distributions = [current]
        if let value = input.values["temperature"] {
            guard let temperature = Self.temperature(value) else { throw input.issue(.temperature, "temperature") }
            current = try Self.softmax(logits, temperature: temperature, issue: sumIssue)
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
            current = try normalized(weights, stage: .topK, parameter: Double(k),
                                     removed: Set(logits.indices).subtracting(retained))
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
            current = try normalized(weights, stage: .topP, parameter: p,
                                     removed: Set(logits.indices).subtracting(retained))
            distributions.append(current)
        }
        guard current.probabilities[chosen] > 0 else { throw input.issue(.chosen, "chosen") }
        self.distributions = distributions
    }

    static func readCandidates(_ input: MLObject, listReason: MGMLReason = .candidates,
                               logitReason: MGMLReason = .logit) throws -> [Candidate] {
        guard case .array(let raw)? = input.values["candidates"], (2...8).contains(raw.count) else {
            throw input.issue(listReason, "candidates")
        }
        var seen = Set<String>()
        return try raw.enumerated().map { index, value in
            let candidate = try MLObject(value, path: "\(input.path).candidates[\(index)]", keys: ["token", "logit"])
            let token = try candidate.text("token", max: 16, reason: listReason)
            guard seen.insert(token).inserted else { throw candidate.issue(listReason, "token") }
            guard let logit = Self.logit(candidate.values["logit"]) else {
                throw candidate.issue(logitReason, "logit")
            }
            return Candidate(token: token, logit: logit)
        }
    }

    static func logit(_ value: MGJSON?) -> Double? {
        guard case .number(let logit)? = value, abs(logit) <= 1_000_000 else { return nil }
        return logit
    }

    static func temperature(_ value: MGJSON) -> Double? {
        guard case .number(let temperature) = value, (0.01...100).contains(temperature) else { return nil }
        return temperature
    }

    static func softmax(_ logits: [Double], temperature: Double?, issue: MGMLIssue) throws -> Distribution {
        guard let maximum = logits.max() else { throw issue }
        return try normalize(logits.map { exp(($0 - maximum) / (temperature ?? 1)) },
                             stage: temperature == nil ? .softmax : .temperature, parameter: temperature, issue: issue)
    }

    static func normalize(_ weights: [Double], stage: Stage, parameter: Double?,
                          removed: Set<Int> = [], issue: MGMLIssue) throws -> Distribution {
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { throw issue }
        let distribution = Distribution(stage: stage, parameter: parameter, probabilities: weights.map { $0 / total }, removed: removed)
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
