# MartyGraphics

MartyGraphics is an **early preview** of a standalone Swift scene engine: validated
JSON scenes, drawing primitives, parametric templates, layout, animation, patches,
streaming, and SwiftUI / SceneKit rendering. It has no external Swift package dependencies.

Requires Swift 6 and macOS 14+ (or iOS 17+ when embedded in an app). From this checkout:

```sh
swift build && swift test
```

Add the package as a local Swift package dependency and use it from a SwiftUI view:

```swift
import Foundation
import MartyGraphics

let json = #"{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}"#
let scene = try MGParser.scene(data: Data(json.utf8)).get()
// Inside your SwiftUI view:
MartyGraphicsView(scene: scene)
```

`MGTemplates.all` lists the binary-search-tree and two-pointer array templates; `MGTemplates.library` includes registered packs.
`MGPacks.register` validates and adds domain packs through the public template API.
`MGGrammar.document()` exposes structural grammar from the parser tables.
See [the protocol](docs/PROTOCOL.md) and [Mac verification](docs/VERIFY-ON-MAC.md).
Packs are code registered by a host; no catalog, remote downloader, or trust store is bundled.

APIs and the wire format may change. Windows and Linux builds are unsupported because
the renderers use Apple frameworks. Mac build/test execution is required before release;
the Ubuntu workflow checks repository hygiene and DCO only.

Examples and test fixtures are original synthetic data. No screenshots, generated art,
course lessons, application adapters, generation prompts, or routing policies are bundled.

Apache-2.0; see LICENSE and NOTICE. Contributions require DCO sign-off (CONTRIBUTING.md).
Report vulnerabilities privately to **admin@morrowdock.app** (SECURITY.md).
