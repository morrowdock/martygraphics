# Round-2f refused documents (anchor-suggestion test inputs)

These five explainer documents are test inputs only. They are not lessons. Do not show them to learners.

* Source: one AI authoring round (round 2f, 2026-11-09 UTC). Four model runs answered the public question
  "How does the Gravity jet suit work?". The engine at `a765ead` (PR #40, strict label anchors) refused all four runs.
* These are the five tries that the strict check refused only for label anchors (`annotation.anchor.off.<id>` and
  `annotation.anchor.hidden.<id>`). Each file is a byte-for-byte copy of the refused try's `document`.
* The text was not fact-checked for this repository, and the grading found fact errors in it. The tests use only the
  geometry, the views and the anchors.
* `SolidAnchorSuggestTests` checks that every `suggest` the check report gives for these files clears that anchor's
  issues when it is applied to a copy. It also checks what a `suggest: null` names (the part fully hidden in a beat).

| File | Run, try | Refusal at `a765ead` |
| --- | --- | --- |
| `opus-1-try-2.explainer.json` | opus 1, try 2 (repair 1) | `annotation.anchor.off.lSuit` (+16 more anchor issues) |
| `opus-1-try-3.explainer.json` | opus 1, try 3 (repair 2) | `annotation.anchor.hidden.lExample` (+4) |
| `opus-1-try-4.explainer.json` | opus 1, try 4 (repair 3) | `annotation.anchor.hidden.lExample` (+1) |
| `opus-2-try-4.explainer.json` | opus 2, try 4 (repair 3) | `annotation.anchor.off.lVer` (+19) |
| `sonnet-2-try-4.explainer.json` | sonnet 2, try 4 (repair 3) | `annotation.anchor.off.lSuit` (+11) |
