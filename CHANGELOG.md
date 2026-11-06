# Changelog

## Unreleased

- Source-compatibility change: the new `MGPackError.badParamSpec` case
  requires external exhaustive switches to be updated. `MGTemplate` also gains
  an optional `reject:` initializer argument.
- Add record-list template parameters (`MGParamSpec.records`), checked at
  pack registration, with specific cross-field rejection reasons and record
  shapes in the grammar for templates that use them; plus an opt-in
  `MGGraphPack` with a locally computed `shortest_path` (Dijkstra) walkthrough
  with semantic edge ids. Narration notes equal-cost relaxations into unsettled
  nodes, and the summary counts tied shortest simple paths. New bounds apply to
  the new shape only; no existing limit or wire format changes. Known limits:
  edge status is shown by colour only, dense automatic layouts are not
  visually accepted, and visual, accessibility and frame-cost acceptance
  have not been done.
- Refuse numeric array cells whose displayed text is longer than the
  6-character cell limit (for example `-123456` or `999999.5`) with
  `array.val` at first parse. Such scenes used to parse and then fail every
  later step edit or patch of that array. Values are never altered.
- Fix three engine round-trip bugs. Default node radius and array cell size
  are now capped to the maximum their own keys accept, so a defaulted item's
  wire form re-parses when the world's larger side is under 3 (node) or 4
  (array) units. In those tiny worlds such items draw smaller than before (at
  a larger side of 2, the default radius is 1/3 instead of 0.5 and the cell
  0.5 instead of 1); other worlds are unchanged. A highlight whose anchor
  chain leads to a hidden item is now hidden too, not only one level deep.
  Streaming previews are refused for any complete scene version other than 1,
  matching `finish()`.
- Add synthetic regression suites for parser limits, streaming previews,
  timeline visibility, patch atomicity and controller rollback.
- Add `marty-scene-validate` in `tools/SceneValidator`, a macOS-only command that
  checks named scene JSON files with the engine parser and reports text or JSON
  results with documented exit codes. It does not render scenes or judge visual
  quality. Native-source receipt reuse now also requires fresh evidence when the
  validator package, sources or tests change.
- Add a guarded post-approval remote-SPM smoke command and offline guard tests,
  with exact tag/commit/pin checks and private evidence. Remote-install acceptance
  remains pending a real reviewed release; add DocC/SPI preparation gates only.
- Expand the v1 Markdown protocol/API reference with developer error reasons,
  limits/platform tables and synthetic JSON fixtures; document reviewed release,
  remote-install and package-discovery gates without inventing a release tag.
- Clarify local preview package setup and live-scene revision handling; add a
  complete title-change example and a first-edit guide for showcase scenes.
- Add a local native showcase for original algorithm, system-diagram, plot,
  synthetic-data and motion examples, with interactive preview and frame export.
- Add a guided API tutorial, public/app capability matrix, quality evidence plan,
  portable-core/browser architecture proposal and reviewed public-sync process.
- Improve README navigation and direct links to example source.
- Include original native PNG/GIF captures with pinned source and measured stored timing.
- Check DCO against explicit PR base/head SHAs, including contributor merges;
  provide reproducible local validation receipts and manual-only hosted checks.

New example execution, accepted capture assets and review are recorded at the
candidate revision; an unreleased entry is not a new published release or tag.
