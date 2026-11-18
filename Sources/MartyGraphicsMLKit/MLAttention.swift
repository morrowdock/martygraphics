// SPDX-License-Identifier: Apache-2.0
import Foundation
import MartyGraphics

struct MLAttention: Equatable, Sendable {
    struct Cell: Equatable, Sendable {
        let column: Int
        let row: Int
        var facts: MGJSON { .array([.number(Double(column)), .number(Double(row))]) }
    }

    let image: MLPixels
    let columns: Int
    let rows: Int
    let patchSize: Int
    let query: Cell
    let targets: [Cell]
    let scores: [Double]
    let distribution: MLProbabilities.Distribution

    var strongest: Double { distribution.probabilities.max() ?? 0 }

    init(_ input: MLObject) throws {
        let image = try MLPixels(input.values["imagePNG"], invalid: input.issue(.picturePNG, "imagePNG"),
                                 size: input.issue(.pictureSize, "imagePNG"))
        let patchSize = try input.integer("patchSize", in: 1...64, reason: .picturePatch)
        guard image.width.isMultiple(of: patchSize), image.height.isMultiple(of: patchSize) else {
            throw input.issue(.picturePatch, "patchSize")
        }
        let columns = image.width / patchSize, rows = image.height / patchSize
        guard (2...64).contains(columns * rows) else { throw input.issue(.attentionGrid, "patchSize") }
        guard case .array(let rawQuery)? = input.values["query"], rawQuery.count == 2,
              let column = MLObject.integer(rawQuery[0], in: 0...(columns - 1)),
              let row = MLObject.integer(rawQuery[1], in: 0...(rows - 1)) else {
            throw input.issue(.attentionQuery, "query")
        }
        let query = Cell(column: column, row: row)
        let targets = (0..<rows).flatMap { y in (0..<columns).map { x in Cell(column: x, row: y) } }
            .filter { $0 != query }
        guard case .array(let rawScores)? = input.values["scores"], rawScores.count == targets.count else {
            throw input.issue(.attentionScores, "scores")
        }
        let scores = try rawScores.enumerated().map { index, value in
            guard let score = MLProbabilities.logit(value) else { throw input.issue(.attentionScores, "scores[\(index)]") }
            return score
        }
        self.distribution = try MLProbabilities.softmax(scores, temperature: nil, issue: input.issue(.sum, "scores"))
        self.image = image
        self.columns = columns
        self.rows = rows
        self.patchSize = patchSize
        self.query = query
        self.targets = targets
        self.scores = scores
    }

    static let label = "Simplified attention · illustrative scores"
    static let frameCount = 150
    static let revealFrame = 34
    static let transitionFrames = 29

    func displayed(at frame: Int) -> Double {
        let unit = min(1, Double(max(0, frame - Self.revealFrame)) / Double(Self.transitionFrames))
        return unit * unit * (3 - 2 * unit)
    }

    var facts: [String: MGJSON] {
        [
            "label": .string(Self.label), "columns": .number(Double(columns)), "rows": .number(Double(rows)),
            "patchSize": .number(Double(patchSize)), "query": query.facts, "targets": .array(targets.map(\.facts)),
            "scores": .array(scores.map(MGJSON.number)),
            "weights": .array(distribution.probabilities.map(MGJSON.number)),
            "sum": .number(distribution.sum), "tolerance": .number(MGMLKit.probabilityTolerance),
            "strongestWeight": .number(strongest)
        ]
    }
}
