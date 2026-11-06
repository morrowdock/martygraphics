// SPDX-License-Identifier: Apache-2.0
import Foundation
@testable import MartyGraphics

/// Deterministic synthetic regression fixtures and helpers shared by the regression test classes.
/// Original data only: no lesson, course, prompt or learner content.
enum MGRegression {
    /// The smallest valid item, reused by envelope and step cases.
    static let dot = #"{"id":"dot","k":"body","at":[3,4]}"#

    /// A minimal non-template scene holding the given item objects.
    static func items(_ list: String...) -> String { #"{"v":1,"items":["# + list.joined(separator: ",") + "]}" }

    /// A valid scene with `dot` plus extra top-level members, e.g. `"steps":[...]`.
    static func withDot(_ members: String) -> String { #"{"v":1,"items":["# + dot + "]," + members + "}" }

    /// A patch document holding the given op objects (no `rev`).
    static func ops(_ list: [String]) -> String { #"{"v":1,"ops":["# + list.joined(separator: ",") + "]}" }

    static func reason(_ json: String) -> String? { reason(MGParser.scene(data: Data(json.utf8))) }
    static func reason(data: Data) -> String? { reason(MGParser.scene(data: data)) }
    static func reason(_ result: Result<MGScene, MGError>) -> String? {
        if case .failure(let error) = result { return error.reason }
        return nil
    }
    static func patchReason(_ json: String) -> String? {
        if case .failure(let error) = MGPatch.parse(data: Data(json.utf8)) { return error.reason }
        return nil
    }
    static func scene(_ json: String) throws -> MGScene { try MGParser.scene(data: Data(json.utf8)).get() }
    static func patch(_ json: String) throws -> MGPatch { try MGPatch.parse(data: Data(json.utf8)).get() }

    /// All 19 item kinds, each valid in the default 12 x 8 world, with optional keys exercised (plus a `code` text line).
    static let allKinds = #"""
    {"v":1,"title":"Every kind","items":[
     {"id":"b","k":"body","at":[2,2],"shape":"ball","size":1.5,"angle":30,"label":"Body","move":{"to":[4,2],"t":1.5}},
     {"id":"inc","k":"incline","at":[1,1],"base":4,"angle":25,"label":"Ramp"},
     {"id":"ln","k":"line","from":[0,0.5],"to":[12,0.5],"style":"ground"},
     {"id":"vec","k":"vector","on":"b","angle":45,"len":2,"label":"F","dashed":true},
     {"id":"vfree","k":"vector","from":[6,6],"angle":-90,"len":1.5},
     {"id":"ax","k":"axes","at":[7,1],"w":4,"h":3,"xl":"t","yl":"x"},
     {"id":"pl","k":"plot","at":[7,1],"w":4,"h":3,"xr":[0,2],"yr":[-1,1],"pts":[[0,0],[1,1],[2,-1]],"xl":"t","yl":"y","label":"Curve"},
     {"id":"sp","k":"spring","from":[1,6],"to":[3,6],"coils":10,"label":"k"},
     {"id":"pu","k":"pulley","at":[10,7],"r":0.5},
     {"id":"rp","k":"rope","pts":[[10,7],[10,5],[9,4]]},
     {"id":"orb","k":"orbit","at":[3,4],"r":1.2,"label":"Path"},
     {"id":"tx","k":"text","at":[6,7.5],"text":"Every kind","style":"callout"},
     {"id":"hl","k":"highlight","target":"b","label":"Look"},
     {"id":"br","k":"bars","at":[9,2],"w":2,"h":2,"bars":[{"label":"KE","value":3},{"label":"PE","value":-1,"color":"potential"}],"unit":"J","label":"Energy"},
     {"id":"pa","k":"path","pts":[[1,7],[2,7.5],[3,7]],"dashed":true},
     {"id":"arr","k":"array","at":[6,3],"vals":[1,2.5,"x"],"cell":0.8,"ptrs":[{"i":0,"label":"L"},{"i":2,"label":"R"}],"marked":[1],"label":"Cells"},
     {"id":"na","k":"node","at":[4,5],"text":"A","r":0.4},
     {"id":"nb","k":"node","at":[5,6],"text":"B"},
     {"id":"ed","k":"edge","a":"na","b":"nb","dir":true,"label":"next"},
     {"id":"tb","k":"table","at":[9,6],"cells":[["k","v"],["a",1]],"header":true,"cw":1.2,"rh":0.5,"marked":[[1,1]],"label":"Cells"},
     {"id":"rg","k":"region","pts":[[0.5,0.5],[2,0.5],[1.2,1.5]],"dashed":true,"label":"Zone"},
     {"id":"cd","k":"text","at":[0.5,6.5],"text":"  i < n","style":"code"}
    ]}
    """#

    /// 3D-only slots: three-component points, a z of zero and a unit `dir` vector.
    static let allKinds3D = #"""
    {"v":1,"dim":"3d","items":[
     {"id":"b","k":"body","at":[4,4,1]},
     {"id":"v","k":"vector","on":"b","dir":[0,0.6,0.8],"len":2},
     {"id":"p","k":"path","pts":[[1,1,0],[2,2,2]]}
    ]}
    """#

    /// Non-template patch base: two nodes joined by an edge, a note and two steps.
    static let patchBase = #"""
    {"v":1,"title":"Patch base","items":[
     {"id":"na","k":"node","at":[3,4],"text":"A"},
     {"id":"nb","k":"node","at":[8,4],"text":"B"},
     {"id":"ab","k":"edge","a":"na","b":"nb"},
     {"id":"note","k":"text","at":[6,7],"text":"Base"}
    ],"steps":[{"say":"One."},{"say":"Two.","show":["note"]}]}
    """#

    /// Template scene: items `arr` (step-edited) and `goal`; three steps (2 + 7 = 9 on the second move).
    static let twoPointers = #"{"v":1,"template":"two_pointers","params":{"vals":[1,2,4,7],"target":9}}"#

    /// Template scene with exactly one template item (`n0`) and one step.
    static let singleNodeTree = #"{"v":1,"template":"bst","params":{"values":[5]}}"#

    /// The edge arrives before both of its nodes.
    static let edgeFirst = #"{"v":1,"items":[{"id":"ab","k":"edge","a":"na","b":"nb"},{"id":"na","k":"node","at":[3,4],"text":"A"},{"id":"nb","k":"node","at":[8,4],"text":"B"}]}"#

    /// Escaped quotes and JSON structural characters inside strings.
    static let tricky = #"{"v":1,"title":"Say \"hi\", [ok] : yes","items":[{"id":"t","k":"text","at":[6,4],"text":"a,b]c\"d"}]}"#

    /// Step gating, anchor hiding and cumulative step edits.
    static let timeline = #"""
    {"v":1,"items":[
     {"id":"ball","k":"body","at":[2,4],"shape":"ball"},
     {"id":"push","k":"vector","on":"ball","angle":0,"len":2},
     {"id":"na","k":"node","at":[6,4],"text":"A"},
     {"id":"nb","k":"node","at":[9,4],"text":"B"},
     {"id":"ab","k":"edge","a":"na","b":"nb"},
     {"id":"mark","k":"highlight","target":"na"},
     {"id":"arr","k":"array","at":[6,1.5],"vals":[1,2,3],"ptrs":[{"i":0,"label":"p"}]}
    ],"steps":[
     {"say":"Start."},
     {"say":"Show the ball.","show":["ball"],"do":[{"id":"arr","key":"ptrs","value":[{"i":1,"label":"p"}]}]},
     {"say":"Show the graph.","show":["nb","mark"],"do":[{"id":"arr","key":"marked","value":[1]}]}
    ]}
    """#

    /// A body gliding 2 -> 6 over two seconds with a vector attached to it.
    static let glide = #"{"v":1,"items":[{"id":"b","k":"body","at":[2,4],"move":{"to":[6,4],"t":2}},{"id":"f","k":"vector","on":"b","angle":90,"len":1}]}"#

    /// Deterministic chunk lengths 1...maxLength from a 64-bit LCG, so streaming tests never depend on randomness.
    static func chunks(_ text: String, seed: UInt64, maxLength: Int = 17) -> [String] {
        var state = seed
        var out: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let length = Int((state >> 33) % UInt64(maxLength)) + 1
            let piece = rest.prefix(length)
            out.append(String(piece))
            rest = rest.dropFirst(piece.count)
        }
        return out
    }
}
