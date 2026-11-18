// SPDX-License-Identifier: Apache-2.0
import MartyGraphics

struct MLVision: Equatable, Sendable {
    let caption: String
    let citation: String?
    let imageSize: [Int]
    let patchSize: Int
    let embeddingWidth: Int
    let embeddingWidthCitation: String?
    let projectorLabel: String?
    let languageModelLabel: String?
    let textTokens: [String]
    let columns: Int
    let rows: Int
    var patchCount: Int { rows * columns }

    init(_ input: MLObject) throws {
        caption = try input.text("caption", max: 100, reason: .caption)
        citation = try input.optionalText("citation", max: 120, reason: .citation)
        embeddingWidthCitation = try input.optionalText("embeddingWidthCitation", max: 120, reason: .citation)
        let pixelRange = 1...8192
        guard case .array(let size)? = input.values["imageSize"], size.count == 2,
              let width = MLObject.integer(size[0], in: pixelRange),
              let height = MLObject.integer(size[1], in: pixelRange) else {
            throw input.issue(.visionSize, "imageSize")
        }
        imageSize = [width, height]
        let patch = try input.integer("patchSize", in: pixelRange, reason: .visionSize)
        patchSize = patch
        guard width % patch == 0, height % patch == 0 else { throw input.issue(.patchDivision, "patchSize") }
        columns = width / patch
        rows = height / patch
        guard columns <= 128, rows <= 128, columns * rows <= 4096 else {
            throw input.issue(.patchCount, "patchSize")
        }
        embeddingWidth = try input.integer("embeddingWidth", in: 1...65536, reason: .embeddingWidth)
        projectorLabel = try input.optionalText("projectorLabel", max: 32, reason: .visionLabel)
        languageModelLabel = try input.optionalText("languageModelLabel", max: 32, reason: .visionLabel)
        textTokens = try input.tokens("textTokens")
    }

    var facts: [String: MGJSON] {
        [
            "caption": .string(caption), "citation": citation.map(MGJSON.string) ?? .null,
            "architectureBasis": .string(citation == nil ? "illustrative" : "cited"),
            "layoutBasis": .string("illustrative"),
            "imageSize": .array(imageSize.map { .number(Double($0)) }),
            "patchSize": .number(Double(patchSize)),
            "patchGrid": .array([.number(Double(columns)), .number(Double(rows))]),
            "patchCount": .number(Double(patchCount)), "patchCountBasis": .string("derived"),
            "embeddingWidth": .number(Double(embeddingWidth)),
            "embeddingWidthCitation": embeddingWidthCitation.map(MGJSON.string) ?? .null,
            "embeddingWidthBasis": .string(embeddingWidthCitation == nil ? "illustrative" : "cited"),
            "projectorLabel": projectorLabel.map(MGJSON.string) ?? .null,
            "languageModelLabel": languageModelLabel.map(MGJSON.string) ?? .null,
            "illustrativeVisualTokenCount": .number(Double(patchCount)),
            "textTokenCount": .number(Double(textTokens.count)),
            "illustrativeJoinedTokenCount": .number(Double(patchCount + textTokens.count))
        ]
    }
}
