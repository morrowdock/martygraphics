// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Original synthetic protocol fixtures. No lesson, assignment, or prompt corpus.
public enum MGFixtures {
    public struct Demo: Identifiable {
        public let id: String
        public let title: String
        public let json: String
        public init(id: String, title: String, json: String) {
            self.id = id; self.title = title; self.json = json
        }
        public var scene: MGScene? { try? MGParser.scene(data: Data(json.utf8)).get() }
    }

    /// A follow-up patch on one fixture: `scene` names the fixture id, `ask` is a short description of the change and
    /// `json` is the exact wire patch.
    public struct PatchDemo: Identifiable {
        public let id: String
        public let scene: String
        public let ask: String
        public let json: String
        public init(id: String, scene: String, ask: String, json: String) {
            self.id = id; self.scene = scene; self.ask = ask; self.json = json
        }
    }

    public static let all: [Demo] = [
        .init(id: "moving_dot", title: "Moving dot", json: #"{"v":1,"title":"Moving dot","world":{"w":12,"h":8},"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1,"move":{"to":[7,4],"t":2}},{"id":"caption","k":"text","at":[6,7],"text":"Synthetic motion"}],"steps":[{"say":"A dot moves across the board."}]}"#),
        .init(id: "graph", title: "Two nodes", json: #"{"v":1,"items":[{"id":"left","k":"node","at":[3,4],"text":"A"},{"id":"right","k":"node","at":[8,4],"text":"B"},{"id":"link","k":"edge","a":"left","b":"right","dir":true}]}"#),
        .init(id: "tree", title: "Synthetic tree", json: #"{"v":1,"template":"bst","params":{"values":[12,5,19,2,8],"find":8}}"#),
        .init(id: "pointers", title: "Synthetic array", json: #"{"v":1,"template":"two_pointers","params":{"vals":[2,5,9,14],"target":14}}"#),
        .init(id: "dot_3d", title: "Synthetic 3D dot", json: #"{"v":1,"dim":"3d","items":[{"id":"dot","k":"body","at":[4,4,1],"shape":"ball","size":1}]}"#),
        .init(id: "cells", title: "Synthetic table, region and code", json: #"{"v":1,"title":"Cells, region and code","items":[{"id":"zone","k":"region","pts":[[1,1],[5,1],[5,4],[1,4]],"dashed":true,"label":"Zone","color":"teal"},{"id":"grid","k":"table","at":[8.5,5.5],"cells":[["key","value"],["a",1],["b",2]],"header":true,"marked":[[2,1]],"cw":1.4,"rh":0.6,"label":"Lookup"},{"id":"line1","k":"text","at":[1.2,6.8],"text":"while i < n:","style":"code"},{"id":"line2","k":"text","at":[1.2,6.2],"text":"    i += 1","style":"code"}],"steps":[{"say":"A region shades an area.","focus":"zone"},{"say":"A table holds short cells; one cell is marked.","focus":"grid"}]}"#)
    ]

    /// Synthetic follow-up patches on the fixtures above. Each one applies to its named fixture.
    public static let patches: [PatchDemo] = [
        .init(id: "tree_find_other", scene: "tree", ask: "Find 19 instead.",
              json: #"{"v":1,"rev":0,"ops":[{"op":"params","params":{"find":19}}]}"#),
        .init(id: "pointers_new_target", scene: "pointers", ask: "Look for a pair that adds to 11.",
              json: #"{"v":1,"rev":0,"ops":[{"op":"params","params":{"target":11}}]}"#),
        .init(id: "pointers_hide_goal", scene: "pointers", ask: "Hide the goal note.",
              json: #"{"v":1,"rev":0,"ops":[{"op":"remove","id":"goal"}]}"#),
        .init(id: "dot_caption", scene: "moving_dot", ask: "Change the caption.",
              json: #"{"v":1,"rev":0,"ops":[{"op":"set","id":"caption","key":"text","value":"Synthetic motion, again"}]}"#),
        .init(id: "graph_table", scene: "graph", ask: "Add a table of the link.",
              json: #"{"v":1,"rev":0,"ops":[{"op":"add","item":{"id":"facts","k":"table","at":[6,1.5],"cells":[["from","to"],["A","B"]],"header":true}}]}"#),
        .init(id: "cells_mark_other", scene: "cells", ask: "Mark the other value.",
              json: #"{"v":1,"rev":0,"ops":[{"op":"set","id":"grid","key":"marked","value":[[1,1]]}]}"#)
    ]

    /// Fail-safe cases (name, wire scene), written for this package. Every one must be refused; the comment after
    /// each names the reason the current parser gives.
    public static let invalid: [(String, String)] = [
        ("root_extra_member", #"{"v":1,"items":[{"id":"p1","k":"node","at":[2,2],"text":"x"}],"mood":"calm"}"#),        // scene.unknown.mood
        ("wire_version_three", #"{"v":3,"items":[{"id":"p1","k":"node","at":[2,2],"text":"x"}]}"#),                    // scene.version
        ("tree_value_too_big", #"{"v":1,"template":"bst","params":{"values":[7,1500,3]}}"#),                             // template.values
        ("pointers_without_vals", #"{"v":1,"template":"two_pointers","params":{"target":6}}"#),                          // template.vals
        ("pointers_descending", #"{"v":1,"template":"two_pointers","params":{"vals":[9,4,2],"target":6}}"#),             // template.check
        ("tree_repeated_key", #"{"v":1,"template":"bst","params":{"values":[5,9,5]}}"#),                                 // template.check
        ("template_not_registered", #"{"v":1,"template":"heap_sift","params":{"vals":[1]}}"#),                           // template.unknown
        ("tree_find_as_text", #"{"v":1,"template":"bst","params":{"values":[3,1],"find":"1"}}"#),                        // template.find
        ("title_unknown_value", #"{"v":1,"template":"two_pointers","params":{"vals":[1,4],"target":5},"title":"sum {total}"}"#), // title.placeholder.total
        ("edge_missing_node", #"{"v":1,"items":[{"id":"n1","k":"node","at":[2,2],"text":"a"},{"id":"e1","k":"edge","a":"n1","b":"n9"}]}"#), // edge.nodes
        ("node_id_reused", #"{"v":1,"items":[{"id":"q","k":"node","at":[2,2],"text":"a"},{"id":"q","k":"node","at":[5,2],"text":"b"}]}"#), // id.duplicate.q
        ("label_with_link", #"{"v":1,"items":[{"id":"b1","k":"body","at":[5,5],"label":"ftp://files"}]}"#),            // item.label
        ("caption_with_tag", #"{"v":1,"items":[{"id":"c1","k":"text","at":[4,6],"text":"press <kbd>"}]}"#),            // text.text
        ("code_line_with_tag", #"{"v":1,"items":[{"id":"c1","k":"text","at":[1,6],"text":"x = <i>y</i>","style":"code"}]}"#), // text.text
        ("caption_blank_lines", #"{"v":1,"items":[{"id":"c1","k":"text","at":[4,6],"text":"\n\n"}]}"#),                // text.text
        ("node_far_left", #"{"v":1,"items":[{"id":"n1","k":"node","at":[-9,3],"text":"a"}]}"#),                        // node.at
        ("orbit_with_depth", #"{"v":1,"items":[{"id":"o1","k":"orbit","at":[6,4,2],"r":1}]}"#),                        // orbit.at
        ("array_in_3d", #"{"v":1,"dim":"3d","items":[{"id":"a1","k":"array","at":[2,2],"vals":[1,2]}]}"#),              // 3d.kind.array
        ("table_in_3d", #"{"v":1,"dim":"3d","items":[{"id":"t","k":"table","at":[1,1],"cells":[["a"]]}]}"#),            // 3d.kind.table
        ("code_in_3d", #"{"v":1,"dim":"3d","items":[{"id":"c1","k":"text","at":[2,2],"text":"i += 1","style":"code"}]}"#), // 3d.text.code
        ("ragged_table", #"{"v":1,"items":[{"id":"t","k":"table","at":[4,4],"cells":[["a"],["b","c"]]}]}"#),           // table.cells
        ("region_two_points", #"{"v":1,"items":[{"id":"r","k":"region","pts":[[1,1],[2,2]]}]}"#),                       // region.pts
        ("focus_on_missing_item", #"{"v":1,"items":[{"id":"n1","k":"node","at":[2,2],"text":"a"}],"steps":[{"say":"Look.","focus":"n2"}]}"#), // step.focus
        ("wire_items_over_limit", #"{"v":1,"items":["# + (1...25).map { #"{"id":"n\#($0)","k":"node","at":[\#(1 + $0 % 10),\#(1 + $0 % 6)],"text":"\#($0)"}"# }.joined(separator: ",") + "]}") // items.count
    ]
}
