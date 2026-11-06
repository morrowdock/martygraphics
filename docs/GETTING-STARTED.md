# From a JSON scene to a native board

Start with the [runnable showcase](../Examples/Showcase/README.md). It has no remote
dependency or credential requirement. The steps below explain the APIs it uses.

No versioned package release exists yet. To try the engine in your own app now,
depend on a local checkout the way the showcase does:
`.package(name: "MartyGraphics", path: "PATH_TO_CHECKOUT")` and
`.product(name: "MartyGraphics", package: "MartyGraphics")`. In Xcode, add the
checkout as a local package. This is an unversioned early preview, not a
release install; see [scope and status](../README.md#scope-and-status).

## 1. Choose a scene

```json
{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}
```

World coordinates point right/up. The default world is 12 by 8. `id` is the
stable reference used by highlights, edits and patches. `k` selects a primitive.
The [seven example files](../Examples/Showcase/Sources/MartyShowcase/Scenes) show
full scenes, the compact tree/array template form and an opt-in graph-pack scene.

## 2. Parse before presenting

```swift
let scene = try MGParser.scene(data: Data(json.utf8)).get()
```

Import Foundation and MartyGraphics. Handle a parse error in the host; retain the
previous valid board rather than presenting partial unvalidated input.
`MGGrammar.document()` inventories structural keys; `MGParser` additionally
enforces ranges, references, cycles and cross-field rules.

In a SwiftUI view body, use `MartyGraphicsView(scene: scene)`.
For host-driven updates, own an `MGSceneController` and pass it to
`MartyGraphicsView(controller: controller)`. The native example's
[`InteractiveGallery`](../Examples/Showcase/Sources/MartyShowcase/Showcase.swift)
shows scene selection and the actual view initializer.

## 3. Update with an atomic patch

```json
{"v":1,"rev":0,"ops":[{"op":"title","title":"A labeled marker"}]}
```

```swift
let patch = try MGPatch.parse(data: Data(patchJSON.utf8)).get()
let accepted = controller.apply(patch: patch, requireRevision: true)
```

Use the **current controller scene revision**, not a permanently hard-coded 0.
A replacement scene also receives a fresh revision. Unknown references, cycles,
bad limits and stale revisions refuse the update. `accepted == false` leaves
the prior controller scene in place.

Read that value from `controller.scene?.revision`. `controller.revision` is a
different counter. It tells SwiftUI that something changed, and it also advances
on `show(_:)` and when a refused stream restores the earlier scene. A patch built
from `controller.revision` can be refused as stale, even the first time.

A complete host that shows one scene and changes its visible title:

```swift
import Foundation
import SwiftUI
import MartyGraphics

struct FirstBoard: View {
    @StateObject private var controller = MGSceneController()
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading) {
            MartyGraphicsView(controller: controller)
            Button("Rename the board", action: rename)
            Text(status)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard controller.scene == nil else { return }
        let json = #"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}"#
        switch MGParser.scene(data: Data(json.utf8)) {
        case .success(let scene): controller.show(scene)
        case .failure(let error): status = "Scene refused: \(error.reason)"
        }
    }

    private func rename() {
        guard let current = controller.scene?.revision else { return }
        let edit: [String: Any] = ["v": 1, "rev": current,
                                   "ops": [["op": "title", "title": "A labeled marker"]]]
        guard case .success(let patch) = MGPatch.parse(object: edit) else { return }
        let accepted = controller.apply(patch: patch, requireRevision: true)
        status = accepted ? "Title updated" : "Refused; the previous board stays"
    }
}
```

The untitled scene first shows a generic heading. After the button, the heading
reads "A labeled marker". The view draws nothing until a scene is shown, so
keep a visible message for a refused scene. `error.reason` is a developer
diagnostic; show your own wording to learners.

## 4. Stream, then finish strictly

```swift
controller.beginStream()
controller.feed(chunk)
let accepted = controller.endStream()
```

Feed raw chunks of the inner scene JSON, not a transport wrapper. Previews are
provisional. `endStream()` runs final validation and restores the prior scene
on failure. The lower-level `MGStreamParser.finish()` has the same strict-final
role when a host does not use the controller.

## 5. Render a known frame

```swift
let visible = MGTimeline.items(scene, step: step)
let items = MGTimeline.frame(scene, items: visible, time: time)
let viewport = MGViewport(size: size, width: scene.width, height: scene.height, camera: scene.camera)
let input = MGRenderInput(scene: scene, items: items, viewport: viewport, time: time)
```

Inside SwiftUI `Canvas`, call `MGCanvasRenderer.draw(input, in: context)`.
The [exporter](../Examples/Showcase/Sources/MartyShowcase/Showcase.swift) is the
complete executable example. A frame export does not prove real-time frame
rate, user input, or accessibility; measure those separately.

## 6. Add a template when repetition earns it

`MGTemplate` accepts validated parameters and returns `MGTemplateBuild`.
Register templates with `MGPacks.register`. Every template needs a valid
fixture, unique identifiers and public-use provenance. Built output is checked
again by the parser. See the synthetic dot template in
[MGPackTests](../Tests/MartyGraphicsTests/MGPackTests.swift).
Structured inputs such as weighted edges use record-list parameters; their
declarations are checked at registration and their patch semantics are in
[template parameters](PROTOCOL.md#template-parameters-and-what-if-patches).

Prefer a full scene for a one-off explanation; do not publish a course-derived
walkthrough just to fill a template slot. The [public sync process](PUBLIC-SYNC.md)
also applies to externally contributed packs.

For complete fields, limits and transport wrappers, use [PROTOCOL.md](PROTOCOL.md).
