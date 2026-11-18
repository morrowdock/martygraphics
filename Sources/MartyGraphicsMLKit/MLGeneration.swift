// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

struct MLGeneration: Equatable, Sendable {
    enum Selection: String, Sendable { case greedy, sample }

    struct Step: Equatable, Sendable {
        let candidates: [MLProbabilities.Candidate]
        let distribution: MLProbabilities.Distribution
        let chosen: Int
        let draw: Double?

        var token: String { candidates[chosen].token }
    }

    let prompt: [String]
    let selection: Selection
    let seed: UInt32?
    let steps: [Step]

    init(_ input: MLObject) throws {
        let prompt = try input.tokens("prompt")
        let count = try input.integer("stepCount", in: 1...8, reason: .generationCount)
        let mode = try input.text("selection", max: 6, reason: .generationSelection)
        guard let selection = Selection(rawValue: mode) else { throw input.issue(.generationSelection, "selection") }
        var seed: UInt32?
        if selection == .sample {
            seed = UInt32(try input.integer("seed", in: 0...Int(UInt32.max), reason: .generationSelection))
        } else if input.values["seed"] != nil {
            throw input.issue(.generationSelection, "seed")
        }
        guard case .array(let raw)? = input.values["steps"], raw.count == count else {
            throw input.issue(.generationLogits, "steps")
        }
        var random = SplitMix64(state: UInt64(seed ?? 0))
        let steps = try raw.enumerated().map { index, rawStep -> Step in
            let step = try MLObject(rawStep, path: "\(input.path).steps[\(index)]",
                                    keys: ["candidates", "temperature", "chosen"])
            let candidates = try MLProbabilities.readCandidates(step, listReason: .generationLogits, logitReason: .generationLogits)
            let temperature: Double?
            if let value = step.values["temperature"] {
                guard let parsed = MLProbabilities.temperature(value) else { throw step.issue(.temperature, "temperature") }
                temperature = parsed
            } else { temperature = nil }
            let distribution = try MLProbabilities.softmax(candidates.map(\.logit), temperature: temperature,
                                                            issue: step.issue(.sum, "candidates"))
            let chosen: Int
            let draw: Double?
            switch selection {
            case .greedy:
                draw = nil
                chosen = candidates.indices.reduce(0) {
                    candidates[$1].logit > candidates[$0].logit ? $1 : $0
                }
            case .sample:
                let unit = random.next()
                draw = unit
                var cumulative = 0.0
                var lastPositive = 0
                for (candidate, probability) in distribution.probabilities.enumerated() where probability > 0 {
                    lastPositive = candidate
                    cumulative += probability
                    if unit < cumulative { break }
                }
                chosen = lastPositive
            }
            if let expected = try step.optionalText("chosen", max: 16, reason: .generationChosen),
               expected != candidates[chosen].token {
                throw step.issue(.generationChosen, "chosen")
            }
            return Step(candidates: candidates, distribution: distribution, chosen: chosen, draw: draw)
        }
        self.prompt = prompt
        self.selection = selection
        self.seed = seed
        self.steps = steps
    }

    private struct SplitMix64 {
        var state: UInt64

        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var bits = state
            bits = (bits ^ (bits >> 30)) &* 0xBF58476D1CE4E5B9
            bits = (bits ^ (bits >> 27)) &* 0x94D049BB133111EB
            bits ^= bits >> 31
            return Double(bits >> 11) / 9_007_199_254_740_992
        }
    }

    static let introFrames = 12
    static let stepFrames = 38
    static let finalFrames = 34
    var frameCount: Int { Self.introFrames + Self.stepFrames * steps.count + Self.finalFrames }

    struct Display {
        let stepIndex: Int?
        let offset: Int
        var progress: Double { min(1, Double(max(0, offset - 5)) / 8) }
        var picked: Bool { offset >= 22 }
        var appended: Bool { offset >= 29 }
    }

    func displayed(at frame: Int) -> Display {
        guard frame >= Self.introFrames else { return Display(stepIndex: nil, offset: 0) }
        let elapsed = frame - Self.introFrames
        let index = min(steps.count - 1, elapsed / Self.stepFrames)
        return Display(stepIndex: index, offset: min(Self.stepFrames - 1, elapsed - index * Self.stepFrames))
    }

    func imageKey(_ frame: Int) -> Int {
        guard let index = displayed(at: frame).stepIndex else { return 0 }
        let phase = displayed(at: frame).offset
        let hold = phase < 6 ? 1 : phase < 13 ? phase : phase < 22 ? 13 : phase < 29 ? 22 : 29
        return index * Self.stepFrames + hold
    }

    var facts: [String: MGJSON] {
        var strip = prompt
        return [
            "prompt": .array(prompt.map(MGJSON.string)), "stepCount": .number(Double(steps.count)),
            "selection": .string(selection.rawValue), "seed": seed.map { .number(Double($0)) } ?? .null,
            "tolerance": .number(MGMLKit.probabilityTolerance),
            "steps": .array(steps.enumerated().map { index, step in
                strip.append(step.token)
                return .object([
                    "step": .number(Double(index + 1)), "candidates": .array(step.candidates.map { .string($0.token) }),
                    "logits": .array(step.candidates.map { .number($0.logit) }),
                    "temperature": step.distribution.parameter.map(MGJSON.number) ?? .null,
                    "probabilities": .array(step.distribution.probabilities.map(MGJSON.number)),
                    "sum": .number(step.distribution.sum), "chosen": .string(step.token),
                    "draw": step.draw.map(MGJSON.number) ?? .null, "strip": .array(strip.map(MGJSON.string))
                ])
            })
        ]
    }
}
