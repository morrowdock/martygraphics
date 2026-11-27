// SPDX-License-Identifier: Apache-2.0
// Acceptance and reason codes against Swift's own results: the recorded 40-input Swift run, the reasons the Swift
// test suite asserts (ParserRegressionTests, TemplateExtensionTests) and the fixtures the Swift tests parse.

import assert from "node:assert/strict";
import { test } from "node:test";
import { corpus } from "./corpus.mjs";
import { MG, swiftOutcome } from "./helpers.mjs";

const cases = corpus().filter((c) => c.swift);

test("the corpus carries Swift expectations for every group", () => {
  const groups = new Set(cases.map((c) => c.group));
  for (const g of ["fixtures", "showcase", "schema-branch", "swift-cases", "boundary", "mgfixtures", "regression", "parser-tests"]) {
    assert.ok(groups.has(g), `group ${g} has Swift expectations`);
  }
  assert.ok(cases.length >= 200, `at least 200 Swift-backed cases (have ${cases.length})`);
});

for (const c of cases) {
  test(`${c.name} → ${c.swift.expect} (${c.swift.source})`, () => {
    assert.equal(swiftOutcome(c), c.swift.expect);
  });
}

test("MGParser.scene(data:) bounds raw input at 16 KiB with `json`; the validator says `input.too-large`", () => {
  const big = Buffer.alloc(16385, 0x20);
  big.write('{"v":1,"items":[{"id":"dot","k":"body","at":[3,4]}]}');
  assert.equal(MG.checkSceneBytes(big).reason, "input.too-large");
  assert.throws(() => MG.parseSceneBytes(big), (e) => e.reason === "json");
});
