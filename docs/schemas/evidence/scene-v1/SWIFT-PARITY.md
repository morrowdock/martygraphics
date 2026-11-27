# Swift and Python scene v1 parity

In the original run on 2026-11-26, the standalone Swift SceneValidator and
Python draft preflight agreed on **38 of 40 inputs**, including the rejection
reason where both rejected. The two differences involved opt-in
`shortest_path` scenes. The updated checker subsequently matched all 40
recorded Swift results in default mode.

## Current follow-up

On 2026-11-26, the Python checks below used Windows Python **3.12.13** and
WSL Python **3.10.12**. The decoder policies for a UTF-8 byte-order mark and
duplicate keys come from static inspection of the current Python checker.
Those rows have no runtime evidence from this pass.

| Case | Input bytes | Swift evidence | Current Python evidence |
| --- | ---: | --- | --- |
| [Math label](../../../fixtures/v1/math-label.scene.json) | 105 | Native check pending | Accepted on both Python versions |
| `scene.json` with `"v":1` | 77 | Accepted in the original run | Accepted on both Python versions |
| Same scene with `"v":1.0` | 79 | Native check pending | Accepted on both Python versions, with integer spelling for size accounting |
| UTF-8 byte-order mark | — | Unmeasured | Policy rejects with `json` |
| Duplicate object keys | — | Unmeasured | Policy rejects with `json` |

## Original run

- Source commit `2c92469b521e4d7bcf7ea44db9a508544e8e46ce` on `feat/scene-v1-json-schema`.
- The macOS build used Apple Swift 6.4.2 on arm64 and
  `swift build -j 2 --package-path tools/SceneValidator --product marty-scene-validate`.
- Both validators ran on macOS. Swift ran with `--json --` and Python ran
  `python3 tools/scene_v1_check.py` once per input. Swift reported zero unreadable
  files. Python version on macOS was not recorded. Two rejections match only
  when their reason codes agree.
- The table includes every regular file under `docs/fixtures/v1` (including
  patches, the lesson, statement streams, and the case manifest as standalone
  scene inputs), seven Showcase scenes, the Studio draft, five inputs
  materialized from the manifest, the 16,384-byte padded test scene, and
  three canonical-size boundary cases.
- The [Studio draft](studio-draft.json) is original synthetic content authored
  for this branch.

## Differences

- `docs/fixtures/v1/shortest-path.scene.json` and
  `Examples/Showcase/Sources/MartyShowcase/Scenes/shortest-path.json`
  both received Swift `template.unknown` and Python draft acceptance with
  expansion deferred. The standalone CLI leaves the graph pack unregistered.
  Showcase registers it with `MGPacks.register(MGGraphPack.pack)` in
  [`Showcase.main()`](../../../../Examples/Showcase/Sources/MartyShowcase/Showcase.swift).
  The current [draft checker](../../../../tools/scene_v1_check.py) returns
  `template.unknown` for both inputs by default and accepts them with
  `--pack graphs`, with expansion deferred to Swift.

The updated Python checker was replayed in WSL against the 40 recorded Swift
results. All 40 matched in default mode, including rejection reasons. Both
`shortest_path` inputs passed Python preflight with `--pack graphs`.

## Byte boundaries

The three compact fixtures use 14 tables (`grid0` through `grid13`) at
`[1,1]`, each with eight rows and six cells. Begin with `x` in every cell, then
grow cells in item, row, and column order by up to nine bytes per cell until the
target length is reached. The multibyte case uses U+00E9 in place of one ASCII
`x` in each grown cell where at least two extra bytes remain, and adjusts ASCII
padding to reach the byte target. Serialize sorted keys as compact UTF-8 using
literal Unicode and no trailing newline.

Both accepted 8,192 ASCII bytes and rejected 8,193 ASCII bytes with
`scene.bytes`. Both also rejected the 8,193-byte multibyte case, whose character
count was below 8,192. Both accepted the 16,384-byte space-padded scene and
rejected the 16,385-byte raw input with `input.too-large`.

## Original results

| File | Input bytes | Swift result | Python result | Match? |
| --- | ---: | --- | --- | --- |
| `docs/fixtures/v1/explainer-mixed.statements.ndjson` | 776 | Reject `json` | Reject `json` | Yes |
| `docs/fixtures/v1/highlight-cycle.scene.json` | 98 | Reject `highlight.cycle` | Reject `highlight.cycle` | Yes |
| `docs/fixtures/v1/invalid/array.json` | 3 | Reject `scene.object` | Reject `scene.object` | Yes |
| `docs/fixtures/v1/invalid/duplicate.json` | 88 | Reject `id.duplicate.dot` | Reject `id.duplicate.dot` | Yes |
| `docs/fixtures/v1/invalid/markup.json` | 84 | Reject `text.text` | Reject `text.text` | Yes |
| `docs/fixtures/v1/invalid/missing-version.json` | 3 | Reject `scene.missing` | Reject `scene.missing` | Yes |
| `docs/fixtures/v1/invalid/ragged.json` | 78 | Reject `table.cells` | Reject `table.cells` | Yes |
| `docs/fixtures/v1/invalid/region.json` | 62 | Reject `region.pts` | Reject `region.pts` | Yes |
| `docs/fixtures/v1/invalid/report-version.json` | 8 | Reject `scene.version` | Reject `scene.version` | Yes |
| `docs/fixtures/v1/invalid/swift-cases.json` | 1131 | Reject `scene.missing` | Reject `scene.missing` | Yes |
| `docs/fixtures/v1/invalid/table3d.json` | 79 | Reject `3d.kind.table` | Reject `3d.kind.table` | Yes |
| `docs/fixtures/v1/invalid/template.json` | 48 | Reject `template.unknown` | Reject `template.unknown` | Yes |
| `docs/fixtures/v1/invalid/unknown-key.json` | 68 | Reject `scene.unknown.unknown` | Reject `scene.unknown.unknown` | Yes |
| `docs/fixtures/v1/invalid/version.json` | 53 | Reject `scene.version` | Reject `scene.version` | Yes |
| `docs/fixtures/v1/rotation.lesson.json` | 1267 | Reject `scene.unknown.beats,kind,scene` | Reject `scene.unknown.beats,kind,scene` | Yes |
| `docs/fixtures/v1/rotation.statements.ndjson` | 1186 | Reject `json` | Reject `json` | Yes |
| `docs/fixtures/v1/scene.json` | 77 | Accept | Accept | Yes |
| `docs/fixtures/v1/shortest-path-edges.patch.json` | 85 | Reject `scene.unknown.ops,rev` | Reject `scene.unknown.ops,rev` | Yes |
| `docs/fixtures/v1/shortest-path-null.patch.json` | 65 | Reject `scene.unknown.ops,rev` | Reject `scene.unknown.ops,rev` | Yes |
| `docs/fixtures/v1/shortest-path.scene.json` | 97 | Reject `template.unknown` | Accept | No |
| `docs/fixtures/v1/table-region-code.scene.json` | 589 | Accept | Accept | Yes |
| `docs/fixtures/v1/title.patch.json` | 63 | Reject `scene.unknown.ops,rev` | Reject `scene.unknown.ops,rev` | Yes |
| `docs/fixtures/v1/unknown-key.scene.json` | 68 | Reject `scene.unknown.unknown` | Reject `scene.unknown.unknown` | Yes |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/counts.json` | 748 | Accept | Accept | Yes |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/function.json` | 910 | Accept | Accept | Yes |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/handoff.json` | 1607 | Accept | Accept | Yes |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/motion.json` | 1053 | Accept | Accept | Yes |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/shortest-path.json` | 251 | Reject `template.unknown` | Accept | No |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/tree.json` | 163 | Accept | Accept | Yes |
| `Examples/Showcase/Sources/MartyShowcase/Scenes/two-pointers.json` | 174 | Accept | Accept | Yes |
| `docs/schemas/evidence/scene-v1/studio-draft.json` | 808 | Accept | Accept | Yes |
| `generated-parity/truncated.json` | 16 | Reject `json` | Reject `json` | Yes |
| `generated-parity/empty.json` | 0 | Reject `json` | Reject `json` | Yes |
| `generated-parity/not-json.json` | 8 | Reject `json` | Reject `json` | Yes |
| `generated-parity/over-limit.json` | 16385 | Reject `input.too-large` | Reject `input.too-large` | Yes |
| `generated-parity/huge.json` | 1048576 | Reject `input.too-large` | Reject `input.too-large` | Yes |
| `generated-parity/padded-16384.json` | 16384 | Accept | Accept | Yes |
| `generated-parity/canonical-8192.json` | 8192 | Accept | Accept | Yes |
| `generated-parity/canonical-8193.json` | 8193 | Reject `scene.bytes` | Reject `scene.bytes` | Yes |
| `generated-parity/canonical-8193-multibyte.json` | 8193 | Reject `scene.bytes` | Reject `scene.bytes` | Yes |
