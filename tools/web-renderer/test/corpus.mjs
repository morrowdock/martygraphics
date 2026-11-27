// SPDX-License-Identifier: Apache-2.0
// The shared validation corpus: every input the parity tests and the Python capture look at, with the Swift result
// where one is known. Groups:
//   fixtures/*        docs/fixtures/v1 (every regular file, including patches, the lesson and statement streams)
//   showcase/*        Examples/Showcase scenes
//   schema-branch/*   copies from feat/scene-v1-json-schema (test/corpus/schema-branch/PROVENANCE.md)
//   swift-cases/*     byte recipes from schema-branch/invalid/swift-cases.json, plus the padded 16384-byte scene
//   boundary/*        canonical-size boundary scenes built from the recipe in SWIFT-PARITY.md
//   mgfixtures/*      MGFixtures.all and MGFixtures.invalid, read from Sources/MartyGraphics/MGFixtures.swift, with the
//                     reasons asserted in Tests/MartyGraphicsTests/TemplateExtensionTests.swift
//   regression/*      scene literals from Tests/MartyGraphicsTests/RegressionFixtures.swift
//   parser-tests/*    the port of ParserRegressionTests.swift (test/swift-parser-cases.mjs)
// `entry` is "validator" (SceneValidator.check: the 16 KiB raw bound is `input.too-large`, as the Python preflight
// does) or "parser" (MGParser.scene(data:) itself, as the Swift unit tests call it).

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parserRegressionCases } from "./swift-parser-cases.mjs";

export const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const REPO_ROOT = path.resolve(PACKAGE_ROOT, "..", "..");
const rel = (...p) => path.join(REPO_ROOT, ...p);

const recorded = JSON.parse(fs.readFileSync(path.join(PACKAGE_ROOT, "test", "expected", "swift-recorded.json"), "utf8")).results;

/** Swift multi-line raw string: drop the closing delimiter's indentation from every line. */
function swiftMultiline(body, indent) {
  return body.split("\n").map((l) => (l.startsWith(indent) ? l.slice(indent.length) : l.trimStart())).join("\n");
}

function mgFixtures() {
  const src = fs.readFileSync(rel("Sources", "MartyGraphics", "MGFixtures.swift"), "utf8");
  const demos = [...src.matchAll(/\.init\(id: "([a-z_0-9]+)", title: "[^"]*", json: #"(.*?)"#\)/g)].map((m) => ({ id: m[1], json: m[2] }));
  const invalidBlock = src.slice(src.indexOf("public static let invalid"));
  const invalid = [...invalidBlock.matchAll(/\("([a-z_0-9]+)", #"(.*?)"#\)/g)].map((m) => ({ id: m[1], json: m[2] }));
  if (invalidBlock.includes('("wire_items_over_limit"')) {
    // `#"{"v":1,"items":["# + (1...25).map { ... }.joined(separator: ",") + "]}"` built the same way.
    const list = Array.from({ length: 25 }, (_, k) => k + 1).map((i) => `{"id":"n${i}","k":"node","at":[${1 + (i % 10)},${1 + (i % 6)}],"text":"${i}"}`);
    invalid.push({ id: "wire_items_over_limit", json: '{"v":1,"items":[' + list.join(",") + "]}" });
  }
  const tests = fs.readFileSync(rel("Tests", "MartyGraphicsTests", "TemplateExtensionTests.swift"), "utf8");
  const block = tests.slice(tests.indexOf("let expected: [String: String] = ["), tests.indexOf("XCTAssertEqual(Set(MGFixtures.invalid"));
  const expected = Object.fromEntries([...block.matchAll(/"([a-z_0-9]+)": "([^"]+)"/g)].map((m) => [m[1], m[2]]));
  return { demos, invalid, expected };
}

export function regressionFixtures() {
  const src = fs.readFileSync(rel("Tests", "MartyGraphicsTests", "RegressionFixtures.swift"), "utf8");
  const out = {};
  for (const m of src.matchAll(/static let (\w+) = #"""\n([\s\S]*?)\n( *)"""#/g)) out[m[1]] = swiftMultiline(m[2], m[3]);
  for (const m of src.matchAll(/static let (\w+) = #"(\{.*?)"#\n/g)) out[m[1]] = m[2];
  return out;
}

/** The three canonical-size boundary scenes (SWIFT-PARITY.md, "Byte boundaries"). */
export function boundaryScene(target, multibyte = false) {
  const tables = Array.from({ length: 14 }, (_, k) => ({ id: `grid${k}`, cells: Array.from({ length: 8 }, () => Array(6).fill("x")) }));
  const encode = () => '{"items":[' + tables.map((t) => `{"at":[1,1],"cells":${JSON.stringify(t.cells)},"id":"${t.id}","k":"table"}`).join(",") + '],"v":1}';
  let need = target - Buffer.byteLength(encode());
  if (need < 0) throw new Error("boundary recipe cannot reach the target");
  for (const t of tables) {
    for (const row of t.cells) {
      for (let c = 0; c < row.length && need > 0; c++) {
        const grow = Math.min(9, need);
        if (multibyte && grow >= 2) {
          // One é (2 bytes) in place of one x, the rest ASCII.
          row[c] = "é" + "x".repeat(grow - 1);
        } else {
          row[c] = "x".repeat(grow + 1);
        }
        need -= grow;
      }
    }
  }
  const text = encode();
  if (Buffer.byteLength(text) !== target) throw new Error(`boundary scene is ${Buffer.byteLength(text)} bytes, not ${target}`);
  return Buffer.from(text, "utf8");
}

/** Every corpus case: { name, group, bytes, entry, swift?: { expect: "accept" | reason, source } }. */
export function corpus() {
  const cases = [];
  const add = (name, bytes, extra = {}) => {
    const swift = extra.swift ?? (recorded[name] !== undefined ? { expect: recorded[name], source: "SWIFT-PARITY.md recorded run" } : undefined);
    cases.push({ name, group: name.split("/")[0], bytes, entry: "validator", ...extra, swift });
  };

  for (const f of fs.readdirSync(rel("docs", "fixtures", "v1")).sort()) {
    const file = rel("docs", "fixtures", "v1", f);
    if (fs.statSync(file).isFile()) add(`fixtures/${f}`, fs.readFileSync(file));
  }
  const showcase = rel("Examples", "Showcase", "Sources", "MartyShowcase", "Scenes");
  for (const f of fs.readdirSync(showcase).sort()) add(`showcase/${f}`, fs.readFileSync(path.join(showcase, f)));
  // Showcase registers the graph pack before parsing (Showcase.swift); the same scenes with the pack enabled:
  for (const f of ["shortest-path.json"]) add(`showcase+graphs/${f}`, fs.readFileSync(path.join(showcase, f)), { packs: ["graphs"] });
  add("fixtures+graphs/shortest-path.scene.json", fs.readFileSync(rel("docs", "fixtures", "v1", "shortest-path.scene.json")), { packs: ["graphs"] });

  const branch = path.join(PACKAGE_ROOT, "test", "corpus", "schema-branch");
  for (const f of fs.readdirSync(path.join(branch, "invalid")).sort()) add(`schema-branch/invalid/${f}`, fs.readFileSync(path.join(branch, "invalid", f)));
  add("schema-branch/math-label.scene.json", fs.readFileSync(path.join(branch, "math-label.scene.json")));
  add("schema-branch/studio-draft.json", fs.readFileSync(path.join(branch, "studio-draft.json")));

  const recipes = JSON.parse(fs.readFileSync(path.join(branch, "invalid", "swift-cases.json"), "utf8"));
  for (const [name, recipe] of Object.entries(recipes)) {
    if (!("raw" in recipe)) continue;
    let data = Buffer.from(recipe.raw, "utf8");
    if (recipe.padToBytes) data = Buffer.concat([data, Buffer.alloc(recipe.padToBytes - data.length, 0x20)]);
    add(`swift-cases/${name}`, data, { swift: { expect: recipe.reason, source: "swift-cases.json" } });
  }
  const padded = Buffer.from(recipes["over-limit.json"].raw, "utf8");
  add("swift-cases/padded-16384.json", Buffer.concat([padded, Buffer.alloc(16384 - padded.length, 0x20)]));

  add("boundary/canonical-8192.json", boundaryScene(8192));
  add("boundary/canonical-8193.json", boundaryScene(8193));
  add("boundary/canonical-8193-multibyte.json", boundaryScene(8193, true));

  const fx = mgFixtures();
  for (const d of fx.demos) add(`mgfixtures/demo/${d.id}`, Buffer.from(d.json, "utf8"), { entry: "parser", swift: { expect: "accept", source: "MGFixtures.all (MGPackTests validates the core pack fixtures)" } });
  for (const d of fx.invalid) {
    add(`mgfixtures/invalid/${d.id}`, Buffer.from(d.json, "utf8"), { entry: "parser", swift: { expect: fx.expected[d.id], source: "TemplateExtensionTests.testCorePackPatchesApplyAndInvalidCasesFailWithExpectedReasons" } });
  }

  const reg = regressionFixtures();
  for (const k of ["allKinds", "allKinds3D", "patchBase", "twoPointers", "singleNodeTree", "edgeFirst", "tricky", "timeline", "glide"]) {
    if (reg[k] === undefined) throw new Error(`RegressionFixtures.${k} not found`);
    add(`regression/${k}`, Buffer.from(reg[k], "utf8"), { entry: "parser", swift: { expect: "accept", source: `RegressionFixtures.${k} (parsed with R.scene in the Swift tests)` } });
  }

  for (const c of parserRegressionCases(reg.allKinds3D)) {
    add(`parser-tests/${c.name}`, c.bytes, { entry: "parser", swift: { expect: c.reason ?? "accept", source: `ParserRegressionTests.${c.fn}` } });
  }

  // Probes where the Python preflight and the Swift source disagree. Their Swift results come from reading the Swift
  // source (cited); no Swift run backs them, so they are labelled as such.
  const dotItem = '{"id":"dot","k":"body","at":[3,4]}';
  const probe = (name, json, expect, source) => add(`probes/${name}`, Buffer.from(json, "utf8"), { swift: { expect, source: `${source} (source reading; not run on Swift)` } });
  probe("non-finite-number", `{"v":1e400,"items":[${dotItem}]}`, "json", "MGModel.swift MGJSON(any:) returns nil for a non-finite number; MGParser.scene(object:) reports json");
  probe("five-unknown-keys", `{"v":1,"items":[${dotItem}],"a":1,"b":2,"c":3,"d":4,"e":5}`, "scene.unknown.a,b,c,d,e", "MGParser.closed joins every unknown key, sorted");
  probe("line-separator-in-title", `{"v":1,"title":"one two","items":[${dotItem}]}`, "accept", "MGParser.text refuses CharacterSet.controlCharacters (Cc, Cf) only; U+2028 is Zl");
  probe("line-feed-in-label", `{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"label":"one\\ntwo"}]}`, "accept", "MGParser.text allows a line feed in every text field");
  probe("tiny-plot-range", '{"v":1,"items":[{"id":"p","k":"plot","at":[1,1],"w":4,"h":3,"xr":[0,1e-9],"yr":[0,1],"pts":[[0,0],[1e-9,1]]}]}', "accept", "MGParser.range requires lo < hi only");
  return cases;
}

export function mgFixtureDemos() {
  return mgFixtures().demos;
}
