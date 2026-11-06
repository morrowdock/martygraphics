// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Public scene grammar and protocol examples. The parser enforces semantic constraints.
/// No model instructions, routing policy, or generation recipes are distributed.
public enum MGGrammar {
    public static let version = 1

    /// Structural grammar derived from the validator tables. This is not a complete
    /// JSON Schema: ranges and cross-field constraints remain in MGParser/MGPatch.
    public static func document() -> [String: Any] {
        [
            "version": version,
            "sceneKeys": MGParser.topKeys.sorted(),
            "kinds": MGKind.allCases.map { kind -> [String: Any] in
                ["name": kind.rawValue,
                 "allowedKeys": MGParser.allowedKeys(kind).sorted(),
                 "requiredKeys": MGParser.required(kind).union(["id", "k"]).sorted()]
            },
            "colors": MGColorRole.allCases.map(\.rawValue),
            "templates": MGPacks.all.flatMap(\.templates).map { template -> [String: Any] in
                var entry: [String: Any] = ["name": template.name, "parameters": template.params.map(\.name)]
                // Only templates with record-list parameters gain this key, so the default document is unchanged.
                let records = template.params.filter(\.isRecordList)
                if !records.isEmpty { entry["records"] = records.map(recordShape) }
                return entry
            },
            "limits": ["sceneBytes": MGLimits.sceneBytes, "patchBytes": MGLimits.patchBytes,
                       "items": MGLimits.items, "steps": MGLimits.steps,
                       "templateSteps": MGLimits.templateSteps]
        ]
    }

    /// A record-list parameter's wire shape: `{"name", "count": [min, max], "fields": [{"name", "range": [lo, hi],
    /// "integer"}]}`. Cross-field rules (for example graph connectivity or layout) are not expressed here; the template's
    /// `reject`/`check` and `MGParser` remain authoritative.
    static func recordShape(_ spec: MGParamSpec) -> [String: Any] {
        ["name": spec.name,
         "count": [spec.count?.lowerBound ?? 0, spec.count?.upperBound ?? 0],
         "fields": (spec.fields ?? []).map { field -> [String: Any] in
             ["name": field.name, "range": [field.range.lowerBound, field.range.upperBound], "integer": field.integer]
         }]
    }

    public static let sceneExample = #"{"type":"scene","scene":{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}}"#
    public static let patchExample = #"{"type":"scenePatch","patch":{"v":1,"rev":0,"ops":[{"op":"title","title":"Synthetic dot"}]}}"#
}
