# Changelog

## Unreleased

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
