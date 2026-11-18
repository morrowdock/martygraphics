// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation

extension MLBoard {
    func vision(_ vision: MLVision) {
        let gap = MLStyle.gap
        let w = (panel.width - 3 * gap) / 4
        let cardHeight = min(205, panel.height * 0.25)
        let top = panel.minY + 120 + (panel.height - 720) * 0.25
        let upper = (0..<4).map { CGRect(x: panel.minX + Double($0) * (w + gap), y: top, width: w, height: cardHeight) }
        let lowerY = upper[0].maxY + 56
        let output = CGRect(x: panel.minX, y: lowerY, width: w, height: cardHeight)
        let model = CGRect(x: output.maxX + gap, y: lowerY, width: w, height: cardHeight)
        let joined = CGRect(x: model.maxX + gap, y: lowerY, width: 2 * w + gap, height: cardHeight)

        for (index, label) in ["Image", "Patch grid", "Patch embeddings", "Projector"].enumerated() {
            let rect = upper[index]
            card(rect)
            text(label, x: rect.midX, y: rect.minY + 22, size: MLStyle.heading, maxWidth: rect.width - 16)
            if index < upper.count - 1 {
                arrow([CGPoint(x: rect.maxX + 3, y: rect.midY), CGPoint(x: upper[index + 1].minX - 3, y: rect.midY)])
            }
        }
        thumbnail(in: upper[0], vision: vision, grid: false)
        thumbnail(in: upper[1], vision: vision, grid: true)
        foot("\(vision.imageSize[0]) × \(vision.imageSize[1]) px", in: upper[0], offset: 20)
        foot("\(vision.patchSize) px per edge", in: upper[1], offset: 38)
        foot("\(vision.columns) × \(vision.rows) = \(vision.patchCount) (derived)", in: upper[1], offset: 18)
        symbol(in: upper[2], count: 4, dot: false)
        foot("Width \(vision.embeddingWidth) · \(vision.embeddingWidthCitation == nil ? "illustrative" : "cited")", in: upper[2], offset: 20)
        symbol(in: upper[3], count: 3, dot: true)
        foot(vision.projectorLabel ?? "Maps to token space", in: upper[3], offset: 20)

        arrow([CGPoint(x: upper[3].midX, y: upper[3].maxY + 5), CGPoint(x: upper[3].midX, y: joined.minY - 5)])
        for (box, label) in [(joined, "Joined token sequence"), (model, "Language model"), (output, "Output tokens")] {
            card(box)
            text(label, x: box.midX, y: box.minY + 22, size: MLStyle.heading, maxWidth: box.width - 16)
        }
        arrow([CGPoint(x: joined.minX - 3, y: joined.midY), CGPoint(x: model.maxX + 3, y: model.midY)])
        arrow([CGPoint(x: model.minX - 3, y: model.midY), CGPoint(x: output.maxX + 3, y: output.midY)])
        let chip = CGRect(x: joined.minX + 12, y: joined.minY + 42, width: joined.width - 24, height: MLStyle.tokenHeight)
        card(chip, role: .purple)
        text("\(vision.patchCount) visual tokens · illustrative grouping", x: chip.midX, y: chip.midY,
             size: MLStyle.detail, maxWidth: chip.width - 8)
        tokens(vision.textTokens, in: chip.offsetBy(dx: 0, dy: 35), columns: min(4, vision.textTokens.count), role: .teal)
        foot("Text tokens follow visual tokens", in: joined, offset: 13)
        symbol(in: model, count: 3, dot: true)
        foot(vision.languageModelLabel ?? "Processes the sequence", in: model, offset: 20)
        symbol(in: output, count: 3, dot: false)

        text(vision.caption, x: panel.midX, y: panel.maxY - 90, size: MLStyle.heading, maxWidth: panel.width)
        text("Illustrative layout · one visual token per patch in this diagram", x: panel.midX, y: panel.maxY - 61,
             size: MLStyle.detail, maxWidth: panel.width, color: subtle)
        let citation = vision.citation ?? "Illustrative image, patch size, projector and language model"
        text(citation, x: panel.midX, y: panel.maxY - 38, size: MLStyle.detail, maxWidth: panel.width, color: subtle)
        if let citation = vision.embeddingWidthCitation {
            text("Embedding width · " + citation, x: panel.midX, y: panel.maxY - 17,
                 size: MLStyle.detail, maxWidth: panel.width, color: subtle)
        }
    }

    private func foot(_ label: String, in rect: CGRect, offset: Double) {
        text(label, x: rect.midX, y: rect.maxY - offset, size: MLStyle.detail, maxWidth: rect.width - 10, color: subtle)
    }

    private func thumbnail(in card: CGRect, vision: MLVision, grid: Bool) {
        let availableWidth = card.width - 20, availableHeight = card.height - 88
        let scale = min(availableWidth / Double(vision.columns), availableHeight / Double(vision.rows))
        let width = Double(vision.columns) * scale, height = Double(vision.rows) * scale
        let rect = CGRect(x: card.midX - width / 2, y: card.minY + 37 + (availableHeight - height) / 2, width: width, height: height)
        fill(rect, color: color(.blue))
        let sun = min(width, height) * 0.19
        context.setFillColor(color(.yellow))
        context.fillEllipse(in: CGRect(x: rect.minX + width * 0.70, y: rect.minY + height * 0.18, width: sun, height: sun))
        context.setFillColor(color(.teal))
        context.move(to: CGPoint(x: rect.minX, y: rect.minY + height * 0.70))
        context.addLine(to: CGPoint(x: rect.minX + width * 0.35, y: rect.minY + height * 0.34))
        context.addLine(to: CGPoint(x: rect.minX + width * 0.63, y: rect.minY + height * 0.65))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.55))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.closePath()
        context.fillPath()
        guard grid else { return }
        let gridColor = ink.copy(alpha: 0.77) ?? ink
        for column in 1..<vision.columns {
            let x = rect.minX + Double(column) * scale
            line([CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)], color: gridColor, width: 0.75)
        }
        for row in 1..<vision.rows {
            let y = rect.minY + Double(row) * scale
            line([CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)], color: gridColor, width: 0.75)
        }
    }

    private func symbol(in rect: CGRect, count: Int, dot: Bool) {
        let side = min(rect.width * 0.13, 32)
        let spacing = side * 1.35
        for index in 0..<count {
            let x = rect.midX + (Double(index) - Double(count - 1) / 2) * spacing - side / 2
            let height = dot ? side : side * 2.15
            let icon = CGRect(x: x, y: rect.midY - height / 2, width: side, height: height)
            fill(icon, color: color(index.isMultiple(of: 2) ? .accent : .teal), radius: dot ? side / 2 : 4)
        }
    }

    func probabilities(_ item: MLProbabilities, frame: Int) {
        let top = panel.minY + 110 + (panel.height - 720) * 0.25
        text("Context tokens", x: panel.midX, y: top, size: MLStyle.heading, maxWidth: panel.width)
        let contextWidth = min(760, panel.width)
        tokens(item.tokens, in: CGRect(x: panel.midX - contextWidth / 2, y: top + 24, width: contextWidth, height: 52),
               columns: min(6, item.tokens.count), role: .teal)

        let display = item.displayed(at: frame)
        let chart = CGRect(x: panel.minX, y: top + 112, width: panel.width, height: 404)
        let nameX = chart.minX + chart.width * 0.12
        let logitX = chart.minX + chart.width * 0.30
        let barX = chart.minX + chart.width * 0.39
        let barWidth = chart.width * 0.46
        let percentageX = chart.minX + chart.width * 0.93
        text("Candidate", x: nameX, y: chart.minY, size: MLStyle.heading, maxWidth: chart.width * 0.21)
        text("Logit", x: logitX, y: chart.minY, size: MLStyle.heading, maxWidth: chart.width * 0.12)
        if let display {
            let stage = display.stage
            let parameter = stage.parameter.map { number($0) } ?? ""
            let label: String
            switch stage.stage {
            case .softmax: label = "Softmax probability"
            case .temperature: label = "Temperature \(parameter)"
            case .topK: label = "Top-k · \(parameter)"
            case .topP: label = "Top-p · \(parameter)"
            }
            text(label, x: barX + barWidth / 2, y: chart.minY, size: MLStyle.heading, maxWidth: barWidth)
        }
        for (index, candidate) in item.candidates.enumerated() {
            let y = chart.minY + 42 + Double(index) * 39
            let chosen = (display?.selection ?? false) && item.chosen == index
            let tint = chosen ? color(.good) : ink
            text(candidate.token, x: nameX, y: y, size: MLStyle.body, maxWidth: chart.width * 0.21, color: tint)
            text(number(candidate.logit), x: logitX, y: y, size: MLStyle.body, maxWidth: chart.width * 0.13, color: subtle)
            if let display {
                let value = display.values[index]
                let track = CGRect(x: barX, y: y - 8, width: barWidth, height: 16)
                fill(track, color: color(.muted).copy(alpha: MLStyle.trackOpacity) ?? subtle, radius: 5)
                if value > 0 {
                    let bar = CGRect(x: track.minX, y: track.minY, width: track.width * value, height: track.height)
                    fill(bar, color: color(chosen ? .good : .accent), radius: min(5, bar.width / 2))
                }
                text(number(value * 100, precision: "%.1f") + "%", x: percentageX, y: y, size: MLStyle.body,
                     maxWidth: chart.width * 0.12, color: tint)
            }
        }
        if display?.selection == true {
            text("Chosen token · " + item.candidates[item.chosen].token, x: panel.midX, y: panel.maxY - 58,
                 size: MLStyle.heading, maxWidth: panel.width, color: color(.good))
        }
    }

    func agent(_ agent: MLAgent) {
        let top = panel.minY + 131 + (panel.height - 720) * 0.25
        let width = min(230, panel.width * 0.25), height = 54.0
        let left = panel.minX + panel.width * 0.19, center = panel.midX, right = panel.maxX - panel.width * 0.19
        let hasReview = agent.states.contains(.review)
        func box(_ x: Double, _ y: Double) -> CGRect {
            CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
        }
        let nodes: [MLAgent.State: CGRect] = [
            .plan: box(left, top), .toolCall: box(center, top), .toolResult: box(right, top),
            .review: box(center, top + 160), .act: box(right, top + 344),
            .revise: box(left, top + 344), .stop: box(center, top + 344)
        ]
        for state in agent.states {
            guard let rect = nodes[state] else { continue }
            let label: String
            switch state {
            case .plan: label = "Plan"
            case .toolCall: label = "Tool call"
            case .toolResult: label = "Tool result"
            case .review: label = "Human review"
            case .act: label = "Act"
            case .revise: label = "Revise"
            case .stop: label = "Stop"
            }
            card(rect, role: state == .review ? .warn : .accent, emphasized: state == .review || state == .stop)
            text(label, x: rect.midX, y: rect.midY, size: MLStyle.heading, maxWidth: rect.width - 12)
        }
        for edge in agent.edges {
            guard let from = nodes[edge.from], let to = nodes[edge.to] else { continue }
            let down = CGPoint(x: from.midX, y: from.maxY + 4)
            let topOfTarget = CGPoint(x: to.midX, y: to.minY - 4)
            switch (edge.from, edge.to) {
            case (.plan, .toolCall), (.toolCall, .toolResult):
                arrow([CGPoint(x: from.maxX + 4, y: from.midY), CGPoint(x: to.minX - 4, y: to.midY)])
            case (.act, .stop):
                arrow([CGPoint(x: from.minX - 4, y: from.midY), CGPoint(x: to.maxX + 4, y: to.midY)])
            case (.toolResult, .review):
                arrow([down, CGPoint(x: from.midX, y: to.midY), CGPoint(x: to.maxX + 4, y: to.midY)])
            case (.review, .act), (.review, .revise):
                let approved = edge.to == .act
                let start = CGPoint(x: from.midX + (approved ? 1 : -1) * width / 4, y: down.y)
                let branchY = from.maxY + 45
                let tint = approved ? color(.good) : color(.warn)
                arrow([start, CGPoint(x: start.x, y: branchY), CGPoint(x: to.midX, y: branchY), topOfTarget],
                      role: approved ? .good : .warn)
                text(approved ? "Approve" : "Reject", x: (start.x + to.midX) / 2, y: branchY - 16,
                     size: MLStyle.detail, maxWidth: width, color: tint)
            case (.review, .stop):
                arrow([down, topOfTarget], role: .warn)
                text("Reject", x: to.midX + 34, y: to.minY - 25, size: MLStyle.detail, maxWidth: 66, color: color(.warn))
            case (.revise, .plan):
                let x = panel.minX + 6
                arrow([CGPoint(x: from.minX - 4, y: from.midY), CGPoint(x: x, y: from.midY),
                       CGPoint(x: x, y: to.midY), CGPoint(x: to.minX - 4, y: to.midY)])
            default: arrow([down, topOfTarget])
            }
        }
        let heading = "Step budget · \(agent.budget) transitions"
        text(heading, x: panel.midX, y: panel.maxY - 96, size: MLStyle.heading, maxWidth: panel.width)
        text(hasReview ? "Act follows approval. Stop when the budget is exhausted."
                       : "Stop when the budget is exhausted.",
             x: panel.midX, y: panel.maxY - 62, size: MLStyle.body, maxWidth: panel.width, color: subtle)
    }
}
