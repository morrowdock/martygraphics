// SPDX-License-Identifier: Apache-2.0
import CryptoKit
import Foundation
import MartyGraphics

/// The bundled turbofan assembly (`Models/turbofan.json`) with its source digest.
public struct TurbofanModel: Sendable {
    public let document: MGSolidDocument
    public let data: Data
    public let lines: Int
    public let sha256: String

    public enum LoadError: Error, CustomStringConvertible {
        case missing, rejected(MGSolidIssue)
        public var description: String {
            switch self {
            case .missing: return "Missing bundled model turbofan.json"
            case .rejected(let e): return "turbofan.json rejected: \(e)"
            }
        }
    }

    public static var url: URL? { Bundle.module.url(forResource: "turbofan", withExtension: "json", subdirectory: "Models") }

    public static func load() throws -> TurbofanModel {
        guard let url else { throw LoadError.missing }
        return try load(data: Data(contentsOf: url))
    }

    public static func load(data: Data) throws -> TurbofanModel {
        let doc: MGSolidDocument
        switch MGSolidParser.document(data: data) {
        case .success(let d): doc = d
        case .failure(let e): throw LoadError.rejected(e)
        }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
        return TurbofanModel(document: doc, data: data, lines: lines,
                             sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    /// Input scale authored on a part's `drive` in the source JSON (nil when the part has no input drive).
    public func authoredInputScale(_ id: String) -> Double? {
        guard case .object(let top) = document.source, case .array(let parts)? = top["parts"] else { return nil }
        for p in parts {
            guard case .object(let o) = p, o["id"] == .string(id), case .object(let d)? = o["drive"],
                  case .number(let s)? = d["input"] else { continue }
            return s
        }
        return nil
    }
}
