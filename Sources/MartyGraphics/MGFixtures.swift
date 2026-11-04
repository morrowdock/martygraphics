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

    public static let all: [Demo] = [
        .init(id: "moving_dot", title: "Moving dot", json: #"{"v":1,"title":"Moving dot","world":{"w":12,"h":8},"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1,"move":{"to":[7,4],"t":2}},{"id":"caption","k":"text","at":[6,7],"text":"Synthetic motion"}],"steps":[{"say":"A dot moves across the board."}]}"#),
        .init(id: "graph", title: "Two nodes", json: #"{"v":1,"items":[{"id":"left","k":"node","at":[3,4],"text":"A"},{"id":"right","k":"node","at":[8,4],"text":"B"},{"id":"link","k":"edge","a":"left","b":"right","dir":true}]}"#),
        .init(id: "tree", title: "Synthetic tree", json: #"{"v":1,"template":"bst","params":{"values":[12,5,19,2,8],"find":8}}"#),
        .init(id: "pointers", title: "Synthetic array", json: #"{"v":1,"template":"two_pointers","params":{"vals":[2,5,9,14],"target":14}}"#),
        .init(id: "dot_3d", title: "Synthetic 3D dot", json: #"{"v":1,"dim":"3d","items":[{"id":"dot","k":"body","at":[4,4,1],"shape":"ball","size":1}]}"#)
    ]
}
