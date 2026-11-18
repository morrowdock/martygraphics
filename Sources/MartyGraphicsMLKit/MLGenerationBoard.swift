// SPDX-License-Identifier: Apache-2.0
import CoreGraphics

extension MLBoard {
    private struct GenerationChip {
        let token: String
        let width: Double
        let generated: Bool
    }

    func generation(_ item: MLGeneration, frame: Int) {
        simplified("Simplified · illustrative logits")
        let display = item.displayed(at: frame)
        let stepIndex = display.stepIndex
        let usedSteps = stepIndex.map { $0 + (display.appended ? 1 : 0) } ?? 0
        let strip = item.prompt + item.steps.prefix(usedSteps).map(\.token)
        let stripTitle = stepIndex == nil ? "Prompt tokens" : "Token strip"
        text(stripTitle, x: panel.midX, y: panel.minY + 107, size: MLStyle.heading,
             maxWidth: panel.width)
        let stripBottom = generationStrip(strip, promptCount: item.prompt.count, from: panel.minY + 128)
        guard let stepIndex else { return }
        let step = item.steps[stepIndex]
        let phase = display.appended ? "Append" : display.picked ? "Pick" : display.progress > 0 ? "Odds" : "Logits"
        let status = "Step \(stepIndex + 1)/\(item.steps.count) · \(phase)"
        let top = max(panel.minY + 235, stripBottom + 44)
        text(status, x: panel.midX, y: top - 19, size: MLStyle.heading, maxWidth: panel.width, face: .mono)
        generationCandidates(step, display: display, top: top)
        if display.picked {
            let method: String
            if let seed = item.seed {
                method = "Seeded draw · seed \(seed)"
            } else {
                method = "Greedy · highest odds"
            }
            let action = display.appended ? "Appended" : "Picked"
            text("\(action) · \(step.token)", x: panel.midX, y: panel.maxY - 63,
                 size: MLStyle.heading, maxWidth: panel.width, color: color(.good))
            text(method, x: panel.midX, y: panel.maxY - 32, size: MLStyle.detail,
                 maxWidth: panel.width, color: subtle, face: .mono)
        }
    }

    private func generationStrip(_ strip: [String], promptCount: Int, from top: Double) -> Double {
        let gap = 8.0
        let available = panel.width - 20
        let maxChip = (available - gap) / 2
        var rows: [[GenerationChip]] = [[]]
        var used = 0.0
        for (index, token) in strip.enumerated() {
            let width = min(maxChip, chipWidth(token))
            if used > 0, used + gap + width > available {
                rows.append([])
                used = 0
            }
            rows[rows.count - 1].append(GenerationChip(token: token, width: width, generated: index >= promptCount))
            used += used > 0 ? gap + width : width
        }
        let height = rows.count > 5 ? 27.0 : 34.0
        let pitch = height + (rows.count > 5 ? 4 : gap)
        for (index, row) in rows.enumerated() {
            let width = row.reduce(0) { $0 + $1.width } + Double(row.count - 1) * gap
            var x = panel.midX - width / 2
            let y = top + Double(index) * pitch
            for chip in row {
                let box = CGRect(x: x, y: y, width: chip.width, height: height)
                card(box, role: chip.generated ? .good : .teal, emphasized: chip.generated, radius: 8)
                text(chip.token, x: box.midX, y: box.midY, size: MLStyle.detail, maxWidth: chip.width - 12)
                x += chip.width + gap
            }
        }
        return top + Double(rows.count - 1) * pitch + height
    }

    private func generationCandidates(_ step: MLGeneration.Step, display: MLGeneration.Display, top: Double) {
        let left = panel.minX + 10
        let logitX = panel.minX + panel.width * 0.41
        let oddsX = panel.maxX - 10
        let barX = logitX + 20
        let barWidth = oddsX - barX - 107
        let labelY = top + 21
        text("Candidate", x: left, y: labelY, size: MLStyle.detail, maxWidth: panel.width * 0.25, alignment: .left)
        text("Logit", x: logitX, y: labelY, size: MLStyle.detail, maxWidth: 90, alignment: .right)
        if display.progress == 1 {
            let odds = step.distribution.parameter.map { "Softmax odds · T \(Self.number($0))" } ?? "Softmax odds"
            text(odds, x: oddsX, y: labelY, size: MLStyle.detail, maxWidth: panel.width * 0.48, alignment: .right)
        }
        let firstRow = labelY + 33
        let pitch = min(59, (panel.maxY - 108 - firstRow) / Double(max(1, step.candidates.count - 1)))
        for (index, candidate) in step.candidates.enumerated() {
            let y = firstRow + Double(index) * pitch
            let chosen = display.picked && step.chosen == index
            let labelColor = chosen ? color(.good) : ink
            if chosen {
                fill(CGRect(x: panel.minX, y: y - pitch * 0.43, width: panel.width, height: pitch * 0.86),
                     color: labelColor.copy(alpha: 0.12) ?? labelColor, radius: 9)
            }
            text(candidate.token, x: left, y: y, size: MLStyle.body, maxWidth: panel.width * 0.26,
                 color: labelColor, alignment: .left)
            text(Self.number(candidate.logit), x: logitX, y: y, size: MLStyle.detail, maxWidth: 92,
                 color: subtle, face: .mono, alignment: .right)
            guard display.progress > 0 else { continue }
            let height = min(29, pitch * 0.64)
            let track = CGRect(x: barX, y: y - height / 2, width: barWidth, height: height)
            fill(track, color: subtle.copy(alpha: 0.18) ?? subtle, radius: 7)
            let amount = step.distribution.probabilities[index] * display.progress
            if amount > 0 {
                let bar = CGRect(x: track.minX, y: track.minY, width: track.width * amount, height: height)
                fill(bar, color: chosen ? labelColor : color(.accent), radius: min(7, bar.width / 2))
            }
            if display.progress == 1 {
                text(step.distribution.percentageLabel(at: index), x: oddsX, y: y, size: MLStyle.detail, maxWidth: 95,
                     color: labelColor, face: .mono, alignment: .right)
            }
        }
    }
}
