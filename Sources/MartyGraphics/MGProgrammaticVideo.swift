// SPDX-License-Identifier: Apache-2.0
import Foundation
import CoreGraphics
import CoreText

public struct MGVideoElement: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public internal(set) var at: [Double]
    public let color: String
    public internal(set) var opacity: Double?
    public let shape: String?
    public let size: [Double]?
    public let to: [Double]?
    public let strokeWidth: Double?
    public let text: String?
    public let fontSize: Double?
    public let xRange: [Double]?
    public let yRange: [Double]?
    public let ticks: Int?
    public let length: Double?
    public let range: [Double]?
    public let lines: [String]?
    public internal(set) var highlightLine: Int?
}

public struct MGVideoKeyframe: Codable, Equatable, Sendable {
    public let frame: Int
    public let at: [Double]?
    public let opacity: Double?
    public let highlightLine: Int?
}

public struct MGVideoTrack: Codable, Equatable, Sendable {
    public let target: String
    public let interpolation: String
    public let keyframes: [MGVideoKeyframe]
}

public struct MGVideoCaption: Codable, Equatable, Sendable {
    public let startFrame: Int
    public let endFrame: Int
    public let text: String
}

public struct MGVideoCanvas: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
}

public struct MGCheckedVideoPlan: Equatable, Sendable {
    public let canvas: MGVideoCanvas
    public let durationFrames: Int
    public let elements: [MGVideoElement]
    public let tracks: [MGVideoTrack]
    public let captions: [MGVideoCaption]
    public let warnings: [String]
    public let generatedMediaLabel: String

    init(_ wire: MGVideoWire, warnings: [String]) {
        canvas = wire.canvas; durationFrames = wire.durationFrames
        elements = wire.elements; tracks = wire.tracks; captions = wire.captions
        generatedMediaLabel = wire.generatedMediaLabel; self.warnings = warnings
    }
}

struct MGVideoWire: Decodable {
    let canvas: MGVideoCanvas
    let durationFrames: Int
    let elements: [MGVideoElement]
    let tracks: [MGVideoTrack]
    let captions: [MGVideoCaption]
    let generatedMediaLabel: String
}

public enum MGProgrammaticVideo {
    static func parse(_ json: MGJSON) throws -> MGScene {
        try json.checkEntry(maxDepth: 16, maxBytes: 65536, number: "video2d.number", depth: "video2d.budget.depth", bytes: "video2d.budget.bytes")
        guard case .object(let object) = json, case .object(let layer)? = object["layer2d"] else { throw MGError("video2d.schema.layer2d") }
        guard layer["version"] == .string("0.1.0-draft") else { throw MGError("video2d.version.layer2d.version") }
        guard let url = Bundle.module.url(forResource: "scene-2d-layer.draft.schema", withExtension: "json"),
              let schema = MGJSON(any: try JSONSerialization.jsonObject(with: Data(contentsOf: url))) else { throw MGError("video2d.schema.resource") }
        try MGVideoSchema.validate(json, schema: schema, root: schema, path: "scene")
        let wire = try JSONDecoder().decode(MGVideoWire.self, from: MGJSON.object(layer).canonicalData)
        try safeText(object["title"].flatMap { if case .string(let title) = $0 { return title }; return nil } ?? "", path: "title")
        var ids = Set<String>(), targets = Set<String>(), glyphs = wire.generatedMediaLabel.unicodeScalars.count
        for element in wire.elements {
            guard ids.insert(element.id).inserted else { throw MGError("video2d.target.elements.\(element.id).duplicate") }
            for text in (element.lines ?? []) + (element.text.map { [$0] } ?? []) {
                try safeText(text, path: "elements.\(element.id).text", code: element.kind == "code")
                glyphs += text.unicodeScalars.count
            }
            for range in [element.range, element.xRange, element.yRange].compactMap({ $0 }) {
                guard range[0] < range[1] else { throw MGError("video2d.range.elements.\(element.id)") }
            }
            glyphs += MGVideoDrawing.ticks(element).reduce(0) { $0 + $1.0.unicodeScalars.count }
            if let highlight = element.highlightLine, highlight > (element.lines?.count ?? 0) { throw MGError("video2d.highlight.elements.\(element.id)") }
        }
        for track in wire.tracks {
            guard let target = wire.elements.first(where: { $0.id == track.target }), targets.insert(track.target).inserted else { throw MGError("video2d.target.tracks.\(track.target)") }
            var previous = -1
            for key in track.keyframes {
                guard key.frame > previous, key.frame < wire.durationFrames else { throw MGError("video2d.frame.tracks.\(track.target)") }
                previous = key.frame
                if let highlight = key.highlightLine {
                    guard target.kind == "code", highlight <= (target.lines?.count ?? 0) else { throw MGError("video2d.highlight.tracks.\(track.target)") }
                }
            }
        }
        var end = 0
        for caption in wire.captions {
            guard caption.startFrame >= end, caption.startFrame < caption.endFrame, caption.endFrame <= wire.durationFrames else { throw MGError("video2d.frame.captions") }
            end = caption.endFrame
            try safeText(caption.text, path: "captions.text")
            glyphs += caption.text.unicodeScalars.count
        }
        guard glyphs <= 8192, glyphs * wire.durationFrames <= 4_000_000 else { throw MGError("video2d.budget.glyphs") }
        var plan = MGCheckedVideoPlan(wire, warnings: [])
        var overlaps = Set<String>()
        for index in 0..<plan.durationFrames {
            let elements = try MGTimeline.videoFrame(index, in: plan)
            var shapes: [(String, CGRect)] = []
            var texts: [(String, CGRect)] = []
            for element in elements {
                let bounds = MGVideoDrawing.bounds(element)
                let area = CGRect(x: 8, y: 96, width: plan.canvas.width - 16, height: plan.canvas.height - 104)
                guard area.contains(bounds) else { throw MGError("video2d.layout.elements.\(element.id).frame.\(index)") }
                if ["label", "code"].contains(element.kind), (element.opacity ?? 1) > 0 {
                    guard !texts.contains(where: { $0.1.intersects(bounds) }) else { throw MGError("video2d.layout.textOverlap.\(element.id).frame.\(index)") }
                    texts.append((element.id, bounds))
                }
                if element.kind == "shape", (element.opacity ?? 1) > 0 {
                    for (id, other) in shapes where other.intersects(bounds) { overlaps.insert("video2d.overlap.\(id).\(element.id)") }
                    shapes.append((element.id, bounds))
                }
            }
        }
        for caption in plan.captions {
            guard MGVideoDrawing.captionHeight(caption.text, width: Double(plan.canvas.width - 32)) <= 52 else { throw MGError("video2d.layout.captions") }
        }
        guard MGVideoDrawing.textSize(plan.generatedMediaLabel, size: 12).width <= Double(plan.canvas.width - 16) else { throw MGError("video2d.layout.generatedMediaLabel") }
        plan = MGCheckedVideoPlan(wire, warnings: overlaps.sorted())
        let title: String
        if case .string(let value)? = object["title"] { title = value } else { title = "" }
        var scene = MGScene(source: json, template: nil, title: title, is3D: false, width: Double(plan.canvas.width), height: Double(plan.canvas.height), items: [], steps: [], camera: nil, values: [:], motion: .none, attachments: [:])
        scene.layer2d = plan
        return scene
    }

    static func safeText(_ text: String, path: String, code: Bool = false) throws {
        let prohibited = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "\u{061c}\u{200e}\u{200f}\u{202a}\u{202b}\u{202c}\u{202d}\u{202e}\u{2066}\u{2067}\u{2068}\u{2069}"))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.unicodeScalars.contains(where: { prohibited.contains($0) }),
              !text.contains("://"), !text.contains("```"),
              code ? !MGParser.looksLikeMarkup(text) : (!text.contains("<") && !text.contains(">")) else { throw MGError("video2d.text.\(path)") }
    }

    public static func check(_ scene: MGScene, programmaticVideo: Bool = false) throws -> MGCheckedVideoPlan {
        guard programmaticVideo else { throw MGError("video2d.optIn") }
        guard let plan = scene.layer2d else { throw MGError("video2d.missing") }
        return plan
    }

    public static func frame(_ index: Int, in plan: MGCheckedVideoPlan, burnCaptions: Bool = true) throws -> CGImage {
        let elements = try MGTimeline.videoFrame(index, in: plan)
        return try MGVideoDrawing.draw(elements, plan: plan, frame: index, burnCaptions: burnCaptions)
    }
}

enum MGVideoSchema {
    static func validate(_ value: MGJSON, schema: MGJSON, root: MGJSON, path: String) throws {
        guard case .object(let rules) = schema else { throw MGError("video2d.schema.resource") }
        func refuse() throws -> Never { throw MGError("video2d.schema.\(path)") }
        if case .string(let ref)? = rules["$ref"], case .object(let document) = root,
           case .object(let definitions)? = document["$defs"], let definition = definitions[String(ref.split(separator: "/").last!)] {
            try validate(value, schema: definition, root: root, path: path); return
        }
        if case .array(let choices)? = rules["oneOf"] {
            let matches = choices.filter { (try? validate(value, schema: $0, root: root, path: path)) != nil }
            guard matches.count == 1 else { try refuse() }; return
        }
        if let constant = rules["const"], value != constant { try refuse() }
        if case .array(let choices)? = rules["enum"], !choices.contains(value) { try refuse() }
        func number(_ name: String, _ fallback: Double) -> Double {
            if case .number(let value)? = rules[name] { return value }; return fallback
        }
        switch rules["type"] {
        case .string("object"):
            guard case .object(let object) = value, case .object(let properties)? = rules["properties"] else { try refuse() }
            if rules["additionalProperties"] == .bool(false), !Set(object.keys).isSubset(of: Set(properties.keys)) { try refuse() }
            if case .array(let required)? = rules["required"] {
                for key in required { if case .string(let name) = key, object[name] == nil { throw MGError("video2d.schema.\(path).\(name)") } }
            }
            guard Double(object.count) >= number("minProperties", 0) else { try refuse() }
            for key in object.keys.sorted() {
                if let child = properties[key] { try validate(object[key]!, schema: child, root: root, path: "\(path).\(key)") }
            }
        case .string("array"):
            guard case .array(let array) = value, Double(array.count) >= number("minItems", 0), Double(array.count) <= number("maxItems", .infinity) else { try refuse() }
            if let child = rules["items"] { for (index, item) in array.enumerated() { try validate(item, schema: child, root: root, path: "\(path)[\(index)]") } }
        case .string("string"):
            guard case .string(let string) = value, Double(string.unicodeScalars.count) >= number("minLength", 0), Double(string.unicodeScalars.count) <= number("maxLength", .infinity) else { try refuse() }
            if case .string(let pattern)? = rules["pattern"], string.range(of: pattern, options: .regularExpression) == nil { try refuse() }
        case .string("integer"), .string("number"):
            guard case .number(let scalar) = value, scalar.isFinite, scalar >= number("minimum", -.infinity), scalar <= number("maximum", .infinity) else { try refuse() }
            if rules["type"] == .string("integer"), scalar.rounded() != scalar { try refuse() }
        default: break
        }
    }
}
