// SPDX-License-Identifier: Apache-2.0
// Accept/reject and reason parity with the Python draft preflight (tools/scene_v1_check.py, branch
// feat/scene-v1-json-schema), using the verdicts captured in test/expected/python-checker.json
// (scripts/capture-python-results.mjs). The comparison uses the validator entry point, as the Python checker does
// (`input.too-large` for raw inputs over 16 KiB). Where the two differ, Swift decides: every allowed divergence below
// is a case whose Swift result is known (asserted by the Swift tests) and which this port reproduces.

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { PACKAGE_ROOT, corpus } from "./corpus.mjs";
import { MG } from "./helpers.mjs";

const captured = JSON.parse(fs.readFileSync(path.join(PACKAGE_ROOT, "test", "expected", "python-checker.json"), "utf8"));
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");

/** Documented divergences: the Python preflight is coarser or defers to Swift; Swift's asserted result wins. */
const DIVERGENCES = {
  "mgfixtures/invalid/title_unknown_value": "python defers template expansion; Swift fills {total} from template values and refuses it",
  "parser-tests/testBytesAndEnvelopeFailClosed#23": "python reports the camera object (`camera`); Swift names the unknown key",
  "parser-tests/testEveryKindRejectsItsOwnMalformedSlots#13": "python reports `body.move`; Swift checks the closed move object (`body.move.missing`)",
  "parser-tests/testEveryKindRejectsItsOwnMalformedSlots#14": "python reports `body.move`; Swift reports the duration (`body.move.t`)",
  "parser-tests/testStepsCamerasAndEditsAreValidatedCumulatively#3": "python reports `steps`; Swift reports the step (`step`)",
  "parser-tests/testStepsCamerasAndEditsAreValidatedCumulatively#4": "python reports `steps`; Swift reports `step.missing`",
  "parser-tests/testStepsCamerasAndEditsAreValidatedCumulatively#5": "python reports `steps`; Swift reports `step.unknown.wait`",
  "parser-tests/testStepsCamerasAndEditsAreValidatedCumulatively#10": "python reports `step.cam`; Swift reports `camera.zoom`",
  "parser-tests/testStepsCamerasAndEditsAreValidatedCumulatively#17": "python reports `step.do`; Swift reports `edit.unknown.x`",
  "parser-tests/testStepsCamerasAndEditsAreValidatedCumulatively#18": "python reports `step.do`; Swift reports `edit.missing`",
  "parser-tests/testPlainTextSanitizerAndPlaceholders#10": "python refuses a line feed in a title; Swift accepts it (the Swift test asserts it)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#9": "python defers expansion; Swift's bst build refuses depth 7 (`template.build`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#12": "python defers expansion; the expanded 3D two_pointers holds an array (`3d.kind.array`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#13": "python defers expansion; `nope` is not a template item (`hide.ref`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#14": "python reports `hide`; Swift reports the entry (`hide.ref`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#18": "python defers expansion; `ghost` is not a template item (`over.ref`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#19": "python defers expansion; the override's text is checked on the built item (`text.text`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#23": "python defers expansion; hiding the only item leaves none (`items.total`)",
  "parser-tests/testTemplateEnvelopeParamsHideAndOverFailClosed#24": "python defers expansion; 43 resolved items exceed 40 (`items.total`)",
  // Source-reading probes (no Swift run): see the `probes` group in test/corpus.mjs.
  "probes/non-finite-number": "python reports `scene.number`; bytes with 1e400 never become an MGJSON value in Swift (`json`)",
  "probes/five-unknown-keys": "python names the first four unknown keys; Swift's closed-key reason lists all of them",
  "probes/line-separator-in-title": "python refuses U+2028 (Zl); Swift refuses only Cc and Cf",
  "probes/line-feed-in-label": "python refuses a line feed outside text items and narration; Swift allows it in every text field",
  "probes/tiny-plot-range": "python requires a span of 1e-6; Swift requires lo < hi",
};

function tsVerdict(c) {
  const o = MG.checkSceneBytes(c.bytes, { packs: c.packs ?? [] });
  if (o.status !== "valid") return { status: "fail", reason: o.reason };
  return { status: o.template ? "pass-deferred" : "pass" };
}

const label = (v) => (v.status === "fail" ? `fail ${v.reason}` : v.status);
const cases = corpus();

test("the captured Python verdicts cover the current corpus byte for byte", () => {
  for (const c of cases) {
    const r = captured.results[c.name];
    assert.ok(r, `${c.name}: no captured Python verdict (run scripts/capture-python-results.mjs)`);
    assert.equal(r.sha256, sha256(c.bytes), `${c.name}: input changed since the capture`);
  }
});

for (const c of cases) {
  test(`python parity: ${c.name}`, () => {
    const py = captured.results[c.name];
    const ts = tsVerdict(c);
    // Python's "pass-deferred" means "shape OK, Swift must expand": a template scene that expands is consistent.
    const same = label(ts) === label(py);
    if (same) {
      assert.ok(!DIVERGENCES[c.name], `${c.name} now matches Python: drop it from DIVERGENCES`);
      return;
    }
    const why = DIVERGENCES[c.name];
    assert.ok(why, `${c.name}: TS ${label(ts)} vs Python ${label(py)} is not a documented divergence`);
    assert.ok(c.swift, `${c.name}: a divergence needs a known Swift result`);
    const expected = c.swift.expect;
    const tsAtSwiftEntry = ts.status === "fail" ? ts.reason : "accept";
    assert.equal(tsAtSwiftEntry, expected, `${c.name}: diverges from Python but does not match Swift either`);
  });
}

test("on every fixture, Showcase scene and schema-branch input the port and the Python preflight agree", () => {
  const fixtureGroups = new Set(["fixtures", "fixtures+graphs", "showcase", "showcase+graphs", "schema-branch", "swift-cases", "boundary"]);
  const scoped = cases.filter((c) => fixtureGroups.has(c.group));
  assert.ok(scoped.length >= 40);
  for (const c of scoped) assert.equal(label(tsVerdict(c)), label(captured.results[c.name]), c.name);
});
