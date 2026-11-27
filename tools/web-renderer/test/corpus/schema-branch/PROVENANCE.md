# Provenance of the copied schema-branch fixtures

These files are byte copies from the MartyGraphics branch `feat/scene-v1-json-schema`
at commit `8882d387c3fe47c61434985aac020561784a18cb`. That branch is not merged into
`main`. The files are original synthetic test inputs from the same project, under
Apache-2.0.

| Copy | Source path on that branch |
| --- | --- |
| `invalid/*.json` (11 inputs and `swift-cases.json`) | `docs/fixtures/v1/invalid/` |
| `math-label.scene.json` | `docs/fixtures/v1/math-label.scene.json` |
| `studio-draft.json` | `docs/schemas/evidence/scene-v1/studio-draft.json` |

`swift-cases.json` names the reason that Swift's `marty-scene-validate` gave for each
invalid input. Five of its entries are byte recipes (`raw`, `padToBytes`), not files.
The test corpus (`test/corpus.mjs`) rebuilds those bytes the same way.

The recorded Swift results for the 40-input parity run
(`docs/schemas/evidence/scene-v1/SWIFT-PARITY.md` on that branch) are transcribed in
`../../expected/swift-recorded.json`.
