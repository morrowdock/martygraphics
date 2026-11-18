// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation

/// Theme and layout defaults for every item.
enum MLStyle {
    static let shortSide = 720.0
    static let inset = 36.0
    static let titleOffset = 32.0
    static let title = 40.0
    static let heading = 38.0 / 1.5
    static let body = 32.0 / 1.5
    static let detail = 18.0
    static let minimumText = 16.0
    static let radius = 12.0
    static let stroke = 4.0 / 1.5
    static let cardOpacity = 0.14
    static let emphasisOpacity = 0.34
    static let trackOpacity = 0.18
    static let tokenHeight = 32.0
}

extension MLBoard {
    func vision(_ vision: MLVision) {
        let snake = size != .landscape
        let gap = snake ? 40.0 / 1.5 : 26.0
        let width = (panel.width - (snake ? gap : 3 * gap)) / (snake ? 2 : 4)
        let cardHeight = (size == .portrait ? 230.0 : size == .square ? 170.0 : 320.0) / 1.5
        let rowGap = (size == .square ? 40.0 : 48.0) / 1.5
        let top = panel.minY + 62
        func box(_ column: Int, _ y: Double, width cardWidth: Double, height: Double) -> CGRect {
            CGRect(x: panel.minX + Double(column) * (width + gap), y: y, width: cardWidth, height: height)
        }
        let second = top + cardHeight + rowGap
        let upper = (0..<4).map { index in
            box(snake && index >= 2 ? 3 - index : index, snake && index >= 2 ? second : top,
                width: width, height: cardHeight)
        }
        let joined = box(snake ? 0 : 2, snake ? second + cardHeight + rowGap : second,
                         width: snake ? panel.width : 2 * width + gap,
                         height: snake ? 170.0 / 1.5 : cardHeight)
        let lastY = snake ? joined.maxY + rowGap : second
        let model = box(snake ? 0 : 1, lastY, width: width, height: cardHeight)
        let output = box(snake ? 1 : 0, lastY, width: width, height: cardHeight)

        for (rect, label) in zip(upper + [joined, model, output],
                                 ["Image", "Patch grid", "Patch embeddings", "Projector",
                                  "Joined token sequence", "Language model", "Output tokens"]) {
            card(rect)
            text(label, x: rect.midX, y: rect.minY + 40 / 1.5, size: MLStyle.heading, maxWidth: rect.width - 16)
        }
        let clearance = 8.0 / 1.5
        func horizontal(_ from: CGRect, _ to: CGRect) {
            let right = to.midX > from.midX
            arrow([CGPoint(x: right ? from.maxX + clearance : from.minX - clearance, y: from.midY),
                   CGPoint(x: right ? to.minX - clearance : to.maxX + clearance, y: to.midY)])
        }
        func vertical(_ from: CGRect, _ to: CGRect, x: Double) {
            arrow([CGPoint(x: x, y: from.maxY + clearance), CGPoint(x: x, y: to.minY - clearance)])
        }
        horizontal(upper[0], upper[1])
        if snake {
            vertical(upper[1], upper[2], x: upper[1].midX)
        } else {
            horizontal(upper[1], upper[2])
        }
        horizontal(upper[2], upper[3])
        vertical(upper[3], joined, x: upper[3].midX)
        if snake {
            vertical(joined, model, x: model.midX)
        } else {
            horizontal(joined, model)
        }
        horizontal(model, output)
        thumbnail(in: upper[0], vision: vision, grid: false)
        thumbnail(in: upper[1], vision: vision, grid: true)
        foot("\(vision.imageSize[0]) × \(vision.imageSize[1]) px", in: upper[0], offset: 20)
        if size == .square {
            let grid = upper[1]
            text("\(vision.patchSize) px per edge", x: grid.midX + 27, y: grid.minY + 62,
                 size: MLStyle.detail, maxWidth: grid.width - 100, color: subtle, face: .mono)
        } else {
            foot("\(vision.patchSize) px per edge", in: upper[1], offset: snake ? 40 : 53)
        }
        foot("\(vision.columns) × \(vision.rows) = \(vision.patchCount) patches (derived)", in: upper[1], offset: snake ? 16 : 20, tracking: -1.3)
        symbol(in: upper[2], count: 4, dot: false)
        foot("Width \(vision.embeddingWidth) · \(vision.embeddingWidthCitation == nil ? "illustrative" : "cited")", in: upper[2], offset: 20)
        symbol(in: upper[3], count: 3, dot: true)
        foot(vision.projectorLabel ?? "Maps to token space", in: upper[3], offset: 20)

        let visual = "\(vision.patchCount) visual tokens · illustrative grouping"
        let available = joined.width - 24
        let tokenWidth = tokenGroupWidth(vision.textTokens)
        let sideBySide = snake && tokenWidth <= available * 0.47
        let visualWidth = ceil(textWidth(visual, size: MLStyle.detail, face: .mono)) + 44 / 1.5
        let chipWidth = min(visualWidth, sideBySide ? available - tokenWidth - 8 : available)
        let chipX = sideBySide ? joined.midX - (chipWidth + 8 + tokenWidth) / 2 : joined.midX - chipWidth / 2
        let chipY = joined.minY + (sideBySide ? 48 : 44)
        let chip = CGRect(x: chipX, y: chipY, width: chipWidth, height: MLStyle.tokenHeight)
        card(chip, role: .purple)
        text(visual, x: chip.midX, y: chip.midY, size: MLStyle.detail, maxWidth: chip.width - 44 / 1.5, face: .mono, lineSpacing: 0.94)
        let joinedTokens = CGRect(x: sideBySide ? chip.maxX + 8 : joined.minX + 12,
                                  y: sideBySide ? chipY : chip.maxY + 8,
                                  width: sideBySide ? tokenWidth : available, height: MLStyle.tokenHeight)
        let tokenHeight = tokens(vision.textTokens, in: joinedTokens, role: .teal)
        foot("Text tokens follow visual tokens", in: joined,
             offset: min(20, joined.maxY - joinedTokens.minY - tokenHeight - 12))
        symbol(in: model, count: 3, dot: true)
        foot(vision.languageModelLabel ?? "Processes the sequence", in: model, offset: 20)
        symbol(in: output, count: 3, dot: false)

        text(vision.caption, x: panel.midX, y: panel.maxY - 81, size: MLStyle.heading, maxWidth: panel.width)
        text("Illustrative layout · one visual token per patch in this diagram", x: panel.midX, y: panel.maxY - 55,
             size: MLStyle.detail, maxWidth: panel.width, color: subtle, face: .mono)
        let citation = vision.citation ?? "Illustrative image, patch size, projector and language model"
        text(citation, x: panel.midX, y: panel.maxY - 29, size: MLStyle.detail, maxWidth: panel.width, color: subtle, face: .mono)
        if let citation = vision.embeddingWidthCitation {
            text("Embedding width · " + citation, x: panel.midX, y: panel.maxY - 9,
                 size: MLStyle.detail, maxWidth: panel.width, color: subtle, face: .mono)
        }
    }

    private func foot(_ label: String, in rect: CGRect, offset: Double, tracking: Double = 0) {
        text(label, x: rect.midX, y: rect.maxY - offset, size: MLStyle.detail, maxWidth: rect.width - 10, color: subtle, face: .mono, tracking: tracking)
    }

    private func thumbnail(in card: CGRect, vision: MLVision, grid: Bool) {
        let availableWidth = card.width - 20
        let artTop = 40.0 / 1.5 + MLStyle.heading / 2 + 18.0 / 1.5
        let compactGrid = grid && size == .square
        let availableHeight = compactGrid ? 36 : card.height - artTop - (grid ? (size == .landscape ? 70 : 52) : 32)
        let centerX = compactGrid ? card.minX + 52 : card.midX
        let scale = min(availableWidth / Double(vision.columns), availableHeight / Double(vision.rows))
        let width = Double(vision.columns) * scale, height = Double(vision.rows) * scale
        let rect = CGRect(x: centerX - width / 2, y: card.minY + artTop + (availableHeight - height) / 2, width: width, height: height)
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
        let gridStroke = min(0.75, scale * 0.22)
        for column in 1..<vision.columns {
            let x = rect.minX + Double(column) * scale
            line([CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)], color: gridColor, width: gridStroke)
        }
        for row in 1..<vision.rows {
            let y = rect.minY + Double(row) * scale
            line([CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)], color: gridColor, width: gridStroke)
        }
    }

    private func symbol(in rect: CGRect, count: Int, dot: Bool) {
        let artTop = rect.minY + 40 / 1.5 + MLStyle.heading / 2 + 18 / 1.5
        let artBottom = rect.maxY - 32
        let aspect = dot ? 1.0 : 2.15
        let side = min(rect.width * 0.13, 32, (artBottom - artTop) / aspect)
        let spacing = side * 1.35
        for index in 0..<count {
            let x = rect.midX + (Double(index) - Double(count - 1) / 2) * spacing - side / 2
            let height = side * aspect
            let icon = CGRect(x: x, y: (artTop + artBottom - height) / 2, width: side, height: height)
            fill(icon, color: color(index.isMultiple(of: 2) ? .accent : .teal), radius: dot ? side / 2 : 4)
        }
    }

    func probabilities(_ item: MLProbabilities, frame: Int) {
        if item.isSweep { simplified("Simplified · illustrative logits") }
        let top = panel.minY + (item.isSweep ? 112 : 86)
        text("Context tokens", x: panel.midX, y: top, size: MLStyle.heading, maxWidth: panel.width)
        let chipHeight = tokens(item.tokens, in: CGRect(x: panel.minX, y: top + 20,
                                                       width: panel.width, height: MLStyle.tokenHeight), role: .teal)
        let chart = CGRect(x: panel.minX, y: top + 45 + chipHeight, width: panel.width, height: 0)
        let nameX = chart.minX + 10
        let logitX = chart.minX + chart.width * 0.35
        let barX = logitX + 20
        let percentageX = chart.maxX - 10
        let percentageWidth = 104.0
        let barWidth = percentageX - percentageWidth - 12 - barX
        let pitch = min(size == .portrait ? 80.0 : 64.0,
                        (panel.maxY - chart.minY - 105) / Double(item.candidates.count - 1))
        let firstRow = chart.minY + 44
        let display = item.displayed(at: frame)
        text("Candidate", x: nameX, y: chart.minY, size: MLStyle.heading, maxWidth: chart.width * 0.22, alignment: .left)
        text("Logit", x: logitX, y: chart.minY, size: MLStyle.heading, maxWidth: chart.width * 0.12, alignment: .right)
        if let display {
            let stage = display.stage
            let parameter = stage.parameter.map { Self.number($0) } ?? ""
            let label: String
            switch stage.stage {
            case .softmax: label = "Softmax probability"
            case .temperature: label = "Temperature \(parameter)"
            case .topK: label = "Top-k · \(parameter)"
            case .topP: label = "Top-p · \(parameter)"
            }
            text(label, x: barX + barWidth / 2, y: chart.minY, size: MLStyle.heading, maxWidth: barWidth, face: stage.parameter == nil ? .heading : .mono)
        }
        for (index, candidate) in item.candidates.enumerated() {
            let y = firstRow + Double(index) * pitch
            let chosen = (display?.selection ?? false) && item.chosen == index
            let tint = chosen ? color(.good) : ink
            if chosen {
                let bandHeight = (44.0 + 2 * 12) / 1.5
                fill(CGRect(x: chart.minX, y: y - bandHeight / 2, width: chart.width, height: bandHeight),
                     color: tint.copy(alpha: 0.12) ?? tint, radius: 8)
            }
            text(candidate.token, x: nameX, y: y, size: MLStyle.body, maxWidth: chart.width * 0.21, color: tint, alignment: .left)
            text(Self.number(candidate.logit), x: logitX, y: y, size: MLStyle.body, maxWidth: chart.width * 0.13, color: subtle, face: .mono, alignment: .right)
            if let display {
                let value = display.values[index]
                let height = 44.0 / 1.5
                let track = CGRect(x: barX, y: y - height / 2, width: barWidth, height: height)
                fill(track, color: color(.muted).copy(alpha: MLStyle.trackOpacity) ?? subtle, radius: 10 / 1.5)
                if value > 0 {
                    let bar = CGRect(x: track.minX, y: track.minY, width: track.width * value, height: track.height)
                    fill(bar, color: color(chosen ? .good : .accent), radius: min(10 / 1.5, bar.width / 2))
                }
                text(display.stage.percentageLabel(at: index), x: percentageX, y: y, size: MLStyle.body,
                     maxWidth: percentageWidth, color: tint, face: .mono, alignment: .right)
            }
        }
        if display?.selection == true {
            text("Chosen token · " + item.candidates[item.chosen].token, x: panel.midX, y: firstRow + Double(item.candidates.count - 1) * pitch + 48,
                 size: MLStyle.heading, maxWidth: panel.width, color: color(.good))
        }
    }

    func agent(_ agent: MLAgent) {
        let top = panel.minY + 131 + (panel.height - 720) * 0.25
        let width = min(230, panel.width * 0.25), height = 112.0 / 1.5
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
            card(rect, role: state == .review ? .warn : .accent, emphasized: state == .stop,
                 radius: 20 / 1.5, review: state == .review)
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
                text(approved ? "Approve" : "Reject", x: (start.x + to.midX) / 2, y: branchY - (10 + 14) / 1.5,
                     size: 28 / 1.5, maxWidth: width, color: tint, face: .heading)
            case (.review, .stop):
                arrow([down, topOfTarget], role: .warn)
                text("Reject", x: to.midX + 10 / 1.5, y: to.minY - 29, size: 28 / 1.5,
                     maxWidth: 80, color: color(.warn), face: .heading, alignment: .left)
            case (.revise, .plan):
                let x = panel.minX + 6
                arrow([CGPoint(x: from.minX - 4, y: from.midY), CGPoint(x: x, y: from.midY),
                       CGPoint(x: x, y: to.midY), CGPoint(x: to.minX - 4, y: to.midY)])
            default: arrow([down, topOfTarget])
            }
        }
        let heading = "Step budget · \(agent.budget) transitions"
        text(heading, x: panel.midX, y: panel.maxY - 96, size: MLStyle.heading, maxWidth: panel.width, face: .mono)
        text(hasReview ? "Act follows approval. Stop when the budget is exhausted."
                       : "Stop when the budget is exhausted.",
             x: panel.midX, y: panel.maxY - 62, size: MLStyle.body, maxWidth: panel.width, color: subtle)
    }
}
