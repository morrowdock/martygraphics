# Anchor-suggestion test inputs (synthetic)

Two synthetic explainers for `SolidAnchorSuggestTests`. They use the built-in `mannequin` and `microTurbojet`
components with neutral names and make no real-world claims. They reproduce the geometry problems that made strict
label anchors refuse an AI authoring round (round 2f), without its text:

| File | What it holds |
| --- | --- |
| `figure-engines.explainer.json` | Off-part dots on component instance parts (`figure.skull`, `figure.body`), a label on a posed part (beat 2), labels on inner parts behind a closed casing (`unitL1.shaft`, `unitL1.combustor`), a part seen only as a sliver through a cutaway (`unitL1.diffuser`), and a pointer tip off its part. |
| `cut-engine.explainer.json` | A casing cut by a beat's section, with labels placed beside the parts inside it; a component anchor name (`unitA.mount`) shown in two beats; an off-part dot on a plain part. |

The test applies every `suggest` that the strict check gives to a copy, and checks that the copy parses and that each
annotation with a suggestion has no anchor issue left. Each annotation without a suggestion must name a part fully
hidden in a beat, and a denser search must find no visible point either.
