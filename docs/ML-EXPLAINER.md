# ML explainer documents (2D)

`MartyGraphicsMLKit` is an opt-in SwiftPM library. A version 1 `ml-explainer` document contains one to four items
in playback order. Each item is strictly checked before the renderer receives it. The regular
[explainer format](EXPLAINER.md) and its tools keep their existing entry points.

See the [JSON schema](schemas/ml-explainer.schema.json), [examples](../Examples/Explainers/README.md) and
[refusal reasons](REASONS.md#ml-explainer-reasons). The schema checks the shape. Swift checks cross-field arithmetic
and references. Text is plain, single-line and bounded. Objects have closed keys. A UTF-8 file can be at most 16 KiB.

```json
{"v":1,"kind":"ml-explainer","title":"A patch grid","items":[
 {"id":"patches","kind":"visionPipeline","caption":"Illustrative input",
  "imageSize":[120,80],"patchSize":20,"embeddingWidth":64,"textTokens":["What","is","shown","?"]}
]}
```

| Key | Rule |
| --- | --- |
| `v`, `kind` | `1` and `"ml-explainer"`. |
| `title` | 1–64 Unicode scalars. |
| `items` | 1–4 items. Each `id` is unique, 1–24 ASCII letters, digits or underscores, starting with a letter. |

## Vision to language

| Key | Rule |
| --- | --- |
| `imageSize`, `patchSize` | Image width and height in pixels, then the square patch edge. Integers from 1 to 8192. Each image side must divide by the edge, with at most 128 rows, 128 columns and 4096 patches. |
| `embeddingWidth` | Integer from 1 to 65,536. The board labels it illustrative unless `embeddingWidthCitation` is given. |
| `textTokens` | 1–12 strings of 1–16 Unicode scalars. |
| `caption` | Required. 1–100 Unicode scalars. Shown in every frame of this item. |
| `citation` | Optional. 1–120 Unicode scalars. Author's source for the image dimensions, patch edge and named projector and language model. Without it, those inputs are marked illustrative. |
| `embeddingWidthCitation` | Optional. 1–120 Unicode scalars. Author's source for the embedding width. |
| `projectorLabel`, `languageModelLabel` | Optional. 1–32 Unicode scalars each. |

The drawing uses a procedural image and draws every grid division. Columns = image width ÷ patch edge. Rows =
image height ÷ patch edge. Their product is shown as derived. The embedding and projector icons are schematic.
The joined sequence groups one illustrative visual token per patch, then shows the authored text tokens. Output
tokens are drawn schematically. Citations carry the author's attribution. The check verifies divisibility and
counts, and the layout remains illustrative with a citation.

## Next-token probabilities

| Key | Rule |
| --- | --- |
| `tokens` | Context strip. 1–12 strings of 1–16 Unicode scalars. |
| `candidates` | 2–8 `{"token","logit"}` objects. Unique 1–16-scalar tokens. Finite logits in −1,000,000…1,000,000. |
| `chosen` | One candidate token with positive probability after all enabled stages. |
| `temperature` | Optional finite number in 0.01…100. |
| `topK` | Optional integer from 1 to the candidate count. |
| `topP` | Optional finite number greater than 0 and at most 1. |

The first stage subtracts the largest logit before exponentiating. Temperature recomputes softmax with the shifted
logits divided by the temperature. Top-k keeps the k highest-ranked candidates. Top-p keeps the smallest
highest-ranked prefix that reaches its threshold in the preceding distribution. A threshold of 1 keeps the entire
positive support. Ranking ties follow input order. Each filter renormalizes its retained entries. All computed
distributions must sum to 1 within an absolute tolerance of 10⁻¹². Probabilities in the report are unrounded.
The chart rounds its labels to one decimal place, animates the enabled steps and highlights the supplied choice.

## Agent loop

| Key | Rule |
| --- | --- |
| `states` | Unique states. `plan`, `toolCall`, `toolResult`, `act` and terminal `stop` are required. `review` is required when `requiresReview` is true. `revise` requires `review`. |
| `requiresReview` | Boolean. The presence of `review` routes the result through a human gate. |
| `stepBudget` | Integer from 1 to 32 and large enough to reach `stop` along the approval path. Each arrow uses one transition. |

The kit builds the arrows. A result goes to review if that state is present. Approve leads to act, then stop.
Reject can stop or, if revise is present, loop back to plan. Exhausting the step budget ends the loop at stop.
The arrows are a diagram for teaching.

## Strict check and export

```sh
swift build --package-path tools/SceneValidator
B=tools/SceneValidator/.build/debug
F=Examples/Explainers/ml-combined.json
$B/marty-scene-validate --ml-kit --strict "$F"
$B/marty-ml-render --ml-kit --size 1920x1080 "$F" combined.mp4
$B/marty-ml-render --ml-kit --size 1080x1080 --png-sequence "$F" combined-alpha
```

The strict check accepts one file. It prints sorted JSON with `ok`, `kind`, `version`, `strict` and either the
checked items or the first `reason` and its `location` (a document path or null). It exits 0 on acceptance,
1 on refusal, 2 on usage error and 3 on unreadable input. Two processes with the same build and input print
byte-identical JSON.

The render tool accepts the same checked document. It writes silent H.264 MP4 at 30 fps or, with
`--png-sequence`, transparent RGBA PNG files named `frame-00000.png`, `frame-00001.png` and so on. Use the same
30 fps when importing the sequence into Remotion. Accepted sizes are 1920×1080 (default), 1080×1080 and 1080×1920.
The output must be new and its parent must exist. The tool prints a JSON receipt with the dimensions, fps, frame
count and transparency. It exits 0 on success, 1 on a refused document, 2 on usage error and 3 on I/O or export failure.

In Swift, call `MGMLKit.check(data:mlKit: true)`, then `MGMLDocument.frame(_:size:theme:transparent:)` or
`MGMLDocument.export(to:size:format:theme:)` on the checked result. The board uses `MGTheme.board` unless a
theme is supplied. Any export error leaves the destination unpublished.
