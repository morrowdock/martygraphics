# Arrow-visibility test input (synthetic)

One synthetic explainer for `ArrowVisibilityTests`. It uses the built-in `mannequin` and `microTurbojet` components
with neutral names and makes no real-world claims. It reproduces the geometry problem of an AI authoring round
(round 2g) in which a thrust arrow could not be seen, without its text:

| File | What it holds |
| --- | --- |
| `arrow-in-casing.explainer.json` | A figure with one engine on its back. Beat 2 shows a force arrow from the engine's nozzle to its intake lip: the arrow runs inside the closed casing, so the casing hides it. |

The test checks that `marty-solid check --strict` refuses `annotation.arrow.hidden.push` in beat 2, names
`engine.casing`, and that the `suggest` it gives, applied to a copy, passes strict with no arrow or anchor issue.
