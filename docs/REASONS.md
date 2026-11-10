# Solid 3D refusal reasons

Every stable reason the Solid 3D formats give, in one table. A reason is one token
(ASCII letters, digits, `_`, `.` and `,`) with one meaning; hosts and model harnesses can
branch on it. The machine-readable catalog is the same table:

* `marty-solid reasons` prints it as JSON (`{"catalog": "martygraphics.solid.reasons/1", "slots", "closedObjects", "formats", "reasons": [{"pattern", "meaning", "formats", "kind", "strict", "limit"}]}`). `limit` is true for a limit reason ([Limit details](#limit-details)).
* In Swift: `MGSolidReasons.catalog` (typed entries), `MGSolidReasons.json`,
  `MGSolidReasons.matches(_:)` (every matching entry) and `MGSolidReasons.lookup(_:)`,
  which returns the entry for a concrete reason such as `part.gear.bore`. Reasons longer
  than 128 KiB or with non-ASCII characters match nothing.

The table in this page is generated from `Sources/MartyGraphics/Solid/MGSolidReasons.swift`;
a test fails when a pattern is missing here.

## Patterns

`<…>` is a typed slot: it matches only values of its own domain (`MGSolidReasons.slots`
gives each as a regular expression). So a reason the engine gives fits exactly one
pattern, or a specific pattern and the general one it refines (`part.gear.bore` and
`part.<shape>.<field>`); `lookup` then picks the pattern whose slots hold the fewest
characters. A test builds sample reasons for every pattern (author names included that
contain `.missing.` or `.unknown.`) and checks that each resolves to its own pattern.

| Slot | Holds |
| --- | --- |
| `<n>` | A step number from 1. |
| `<id>`, `<name>` | An author name passed through `MGSolidParser.token`: 1–32 ASCII letters, digits, `_` and `.` (anything else becomes `_`). Component part ids keep their dots (`stage1.pinion`). |
| `<ident>` | An identifier: an ASCII letter, then up to 23 letters, digits or `_` (component parameter and check names). |
| `<shape>` | A shape kind: gear, ringGear, shaft, tube, box, hex, plate, carrier, extrudedProfile, revolvedProfile, blade, bladeRow. |
| `<crank>` | `crankSlider` or `crankRod`. |
| `<field>` | A field name: an ASCII letter, then letters or digits. |
| `<list>` | `focus`, `highlight`, `hide` or `show`. |
| `<direction>` | `axisWorld` or `upWorld`. |
| `<modifier>` | A placeholder modifier token: 1–32 ASCII letters, digits or `_`. |
| `<op>` | An expression operator other than `div` and `param` (they have their own entries). |
| `<keys>` | Key tokens, sorted and joined with commas (`assembly.missing.kind,parts,v`). |
| `<object>` | One of the closed objects below. |

Closed objects (`<object>.missing.<keys>`, `<object>.unknown.<keys>`): `assembly`,
`params`, `part`, `part.<shape>` (a shape body), `part.emissive`, `part.expect`,
`part.repeat`, `part.drive.follow`, `part.drive.<crank>`, `constraint.gearMesh`, `step`,
`step.check`, `step.section`, `component`, `component.param.<ident>`, `component.use`,
`annotations`, `label`, `arrow`, `dimension`.

### One string, two causes

The engine gives the same string for two causes in three places. The catalog has one
entry for each, and its meaning names both causes:

* `component.unknown.<keys>`: a `use` names a component that is not in the library, or a
  component definition has unknown top-level keys.
* `component.expr.div`: division by zero, or `div` without exactly two operands.
* `step.ghost`: `ghost` is not a non-empty array, or it has more than 16 entries or a
  non-string entry.

A component parameter named `unknown` or `name` can also make a parameter-spec reason
read like another reason (`component.param.unknown.missing.x` is also a `with` key
`missing.x` that names no parameter); `lookup` then picks the parameter-spec reason.

## Formats

| Format | Where the reason comes from |
| --- | --- |
| assembly | `MGSolidParser.document` and every compile of an assembly. A patch recompiles the whole document and a component definition compiles on its own, so these reasons can also answer a patch or a component. |
| patch | `MGSolidParser.applying` (only patches give these). |
| component | Component definitions (`MGSolidLibrary.register`, `validate`, `instantiate`) and `use` entries. |
| check | `MGSolidReport` and `marty-solid check`: refusals after the document compiles. |
| snapshot | `MGSolidSnapshot.decode(data:)`. |
| section | `MGSolidSection.cut` and `estimate` called directly; an assembly reports the same problems with `.<id>`. |
| cli | The `marty-solid` tool. |
| explainer | Explainer documents and streams (`MGExplainer`, `MGExplainerSession`, `MGExplainerReport`): the explainer's own reasons, and the lesson and solid reasons it names itself ([EXPLAINER.md](EXPLAINER.md)). |

Warnings are not refusals in the plain API: they are listed in the check report's
`warnings`. The strict profile (`MGSolidProfile.strict`, `marty-solid check --strict`)
refuses the warnings marked "strict refuses". An explainer's strict check (`marty-solid check --strict` on an explainer)
also refuses `notes.unused.<id>` (`MGSolidReasons.explainerStrictPrefixes`). The anchor view rules
`annotation.anchor.hidden.<id>` and `annotation.anchor.untested.<id>`, and the arrow rules
`annotation.arrow.hidden.<id>` and `annotation.arrow.untested.<id>`, need the camera of each step or beat still, so
only the check report gives them (`MGSolidReport`, `MGExplainerReport`, `marty-solid check`;
`MGSolidReasons.reportStrictPrefixes`): a compile with `MGSolidParser.document(profile: .strict)` does not refuse them
([SOLID-3D.md](SOLID-3D.md), "Anchor checks" and "Arrow visibility"). The arrow drop warning
`annotation.arrow.dropped.<id>` also needs each still's camera; no profile refuses it, because the still does not draw
the arrow ([SOLID-3D.md](SOLID-3D.md), "Arrow drop").

## Order

A document gets one reason: the first check that fails. The parser checks the
input text (size, UTF-8, nesting), then the document in order (top-level keys and the
title, `params`, component expansion, parts, constraints and drives, the gear checks and
the mesh solve, steps, meshes and step cuts, `expect`, then text and claim checks). The
order does not depend on dictionary order (lists of keys are sorted). After the
document compiles, the check report refuses `check.meshOpen`, then
`check.gearsInterpenetrate`, then the strict refusals. `marty-solid` refuses a file over
64 KiB as `assembly.bytes` (or `component.bytes`, `patch.bytes`) before it reads it.

## What the catalog test checks

`SolidReasonCatalogTests` scans the Solid sources, the explainer sources (`Sources/MartyGraphics/Explainer`) and
the `marty-solid` tool. Every
reason-shaped string literal (a dotted token, with `\(…)` interpolations as wildcards),
every single-word reason passed to `MGSolidIssue`, and every reason that the key and
frame helpers compose (`closed` gives `.missing.` and `.unknown.`, the explainer's `closedKeys` gives `.missing` and `.unknown.`, `transform` gives
`.at` and `.rot`) must match a pattern here. Every pattern must match something in
the sources; a literal made only of interpolations (`\(a).\(b)`) matches broadly, so this
direction finds only entries that nothing could produce. A short list in the test names
the dotted literals that are not reasons (output file names, fact-name and material
prefixes). Scene, patch and lesson reasons of the 2D protocol are not in this catalog;
see [PROTOCOL.md](PROTOCOL.md) and [LESSONS.md](LESSONS.md).

## Limit details

A refusal from a length, count or size limit reports its numbers in the check report's `limit`
(`MGSolidLimitDetail`), and every refused report carries `repair`, one line built from them:

```json
"limit": {"field": "annotations.labels[0].text", "actual": 69, "limit": 60, "unit": "characters", "minimum": 1},
"repair": "annotations.labels[0].text has 69 characters; the limit is 60. Shorten it to at most 60 characters (9 fewer)."
```

* `field` is a path into the document: object keys joined by `.`, array entries as `[i]` with a 0-based index
  (`steps[2].say`, `beats[0].view.ghost`). An explainer's solid is under `solid.` (`solid.annotations.labels[4].text`),
  a beat view's step list under `beats[i].view.`, a note under `notes.<id>.<kind>`, a component's own fields
  (`title`, `about`, `params`, `anchorAbout.<name>`) at its top level, a whole file as `document` and a stream as
  `stream`. A part made by a component is `parts[id=<id>]`. At most 128 characters of ASCII letters, digits, `_`,
  `.`, `[`, `]` and `=`.
* `actual` is the value the engine measured: Unicode scalars for text (after placeholders are filled when the rule
  counts the filled text), entries, bytes, triangles, vertices and so on (`unit`).
* `minimum` is set for a `1–N` rule (an empty or blank text has `actual` 0).
* A number the engine does not hold exactly is given as a bound, never as `actual`: `actualAtLeast` when it stopped
  counting at the first value over the limit (component expansion, expression nodes, nesting, a stream, a file read
  only to one byte past the limit), or for a document number above 2^53; `actualAtMost` for one below −2^53. `repair`
  then says "at least" (or "at most"). A whole number up to 2^53 is `actual` as given (`repeat.count: 1e12` is
  1,000,000,000,000). An integer the JSON parser keeps exactly but a double cannot hold (2^53 + 1, 2^63 − 1) is read
  rounded away from zero, so it is reported as a bound (`actualAtLeast: 9007199254740992`), never as a different
  exact number.
* A shape inside a part's `shape` list is `parts[i].shape[j].<kind>.<field>`; a single shape object is
  `parts[i].shape.<kind>.<field>`. An explainer's solid prefixes every path with `solid.`, `parts.resolved` included
  (`solid.parts`).
* `parts.resolved` keeps its `count` and `top`; `annotations.visible`, `step.annotate.count` and `view.annotate.count`
  keep `visibility` and add `limit`.
* The same reason for another cause (not an array, a markup character, an unknown key) has no `limit`; `repair` then
  gives the catalog meaning: `Refused (<reason>), at <part>: <meaning>`.
* `repair` is at most 400 Unicode scalars and deterministic. For an anchor reason it is the anchor issue's own
  `repair` ([SOLID-3D.md](SOLID-3D.md#anchor-suggestions)).

The limit patterns (`MGSolidReasons.limitPatterns`; `SolidLimitDetailTests` triggers each one over its limit and checks
`limit` and `repair`): `assembly.bytes`, `assembly.title`, `assembly.budget`, `text.grapheme`, `parts.count`,
`parts.resolved`, `part.name`, `part.shape.count`, `part.repeat.count`, `part.<shape>.holes`,
`part.bladeRow.triangles`, `constraints.count`, `steps.count`, `step.say`, `step.<list>`, `step.pose`,
`step.unchecked`, `step.check`, `step.ghost`, `step.section.parts`, `labels.count`, `arrows.count`,
`dimensions.count`, `annotations.visible`, `label.text.<id>`, `label.unchecked.<id>`, `arrow.text.<id>`,
`arrow.unchecked.<id>`, `dimension.text.form.<id>`, `step.annotate.count`, `patch.bytes`, `component.bytes`,
`component.title`, `component.about`, `component.params`, `component.parts.count`, `component.depth`,
`component.constraints`, `component.anchors`, `component.anchorAbout`, `component.checks`, `component.expr.size`,
`component.id.length`, `explainer.bytes`, `explainer.title`, `explainer.statements.count`, `explainer.beats.count`,
`notes.count`, `notes.text.<id>`, `beat.unchecked.<n>`, `beat.ops.count`, `beat.checks.count`,
`beat.highlight.count`, `stmt.bytes`, `stmt.say`, `view.focus`, `view.ghost`, `view.section.parts`,
`view.annotate.count`, `view.pose`, `view.hide`, `view.show`, `names.count`, `names.text.<n>`.

Bounds without `limit` (`MGSolidReasons.limitExempt`; a test fails when a meaning that names a bound is in neither
list):

| Why no `limit` | Reasons |
| --- | --- |
| Not a limit: invalid text. | `json`, `patch.json`, `explainer.json`, `solidSnapshot.json` |
| Nesting: the walk stops at the first level over the limit, so no depth is measured. | `assembly.depth`, `explainer.depth`, `component.expr.depth` |
| Value ranges, not a length, count or size of the document. | `part.<shape>.<field>`, `part.drive.<crank>.rod`, `part.blade.twist`, `part.bladeRow.twist`, `constraint.ratio`, `component.expr.range`, `annotations.input` |
| Shape, geometry and reference rules. | `part.revolvedProfile.axis`, `part.bladeRow.count`, `part.shape.gears`, `anchor.ambiguous.<id>`, `constraint.gearMesh.carrier`, `constraint.gearMesh.repeat` |
| Geometric and angle tolerances. | `constraint.gearMesh.distance`, `constraint.gearMesh.interference`, `check.gearsInterpenetrate`, `expect.axis.<id>`, `expect.up.<id>`, `arrow.expect.<id>`, `arrow.gravity.<id>`, `dimension.over.still.<id>` |
| Fact and pose rules. | `step.pose.fact`, `view.pose.fact`, `view.pose.with` |
| A placeholder format rule; its length is one of several causes. | `text.placeholder` |
| An internal work budget of the step cuts. | `section.budget` |
| Their own detail: the report's `anchor` (distance, tolerance, budget, `suggest`). | `annotation.anchor.off.<id>`, `annotation.anchor.untested.<id>` |
| Their own detail: the report's `arrow` (visible share, head, view, `suggest`). | `annotation.arrow.hidden.<id>`, `annotation.arrow.untested.<id>` |
| Host snapshots, not author documents. | `solidSnapshot.bytes`, `solidSnapshot.number`, `snapshot.bytes`, `snapshot.shown`, `snapshot.presented` |
| A host value; the refusal carries nothing else by design. | `report.engine` |
| The render tool's story plan, not a check report. | `story.beats`, `story.frames` |

## Reasons

### Input text and document shape

| Reason | Formats | Meaning |
| --- | --- | --- |
| `json` | assembly, component | The bytes are not UTF-8 JSON text (invalid UTF-8, a raw NUL byte, or text the JSON parser rejects). |
| `unknown` | assembly, component | An unexpected internal error. Please report it with the input. |
| `assembly.bytes` | assembly, patch | The document is over 64 KiB (`MGSolidLimits.bytes`): its bytes, or its canonical JSON after a patch. |
| `assembly.depth` | assembly, patch | The document nests deeper than 64 levels (`MGLimits.depth`). |
| `assembly.object` | assembly | The document is not a JSON object. |
| `assembly.kind` | assembly | `kind` is not "assembly". |
| `assembly.version` | assembly | `v` is not 1 or 2. |
| `assembly.units` | assembly | `units` is present and is not "mm". |
| `assembly.title` | assembly | The title is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 80 characters, also after placeholders are filled. |
| `assembly.budget` | assembly | Part meshes plus step cuts and annotation pieces would exceed 1,500,000 triangles or 1,000,000 vertices (counted before any mesh is built). |
| `assembly.invalid` | assembly | The compiled assembly failed its structural validation (a parent, drive source or explode window the earlier checks did not refuse). |
| `<object>.missing.<keys>` | assembly, component | Required keys are missing from an object. `<object>` names the object (see `closedObjects`); `<keys>` lists the missing keys. |
| `<object>.unknown.<keys>` | assembly, component | An object has keys it does not allow (in a v1 document this includes every v2 key). `<object>` names the object (see `closedObjects`; a component definition's own unknown keys give `component.unknown.<keys>`); `<keys>` lists the keys. |
| `part.at` | assembly | A part's `at` is not three coordinates in -4000...4000 mm. |
| `part.rot` | assembly | A part's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis (each value in -1000...1000) and an angle in -360...360. |
| `part.<shape>.at` | assembly | A shape's `at` is not three coordinates in -4000...4000 mm. |
| `part.<shape>.rot` | assembly | A shape's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360. |
| `component.use.at` | assembly, component | A `use` entry's `at` is not three coordinates in -4000...4000 mm. |
| `component.use.rot` | assembly, component | A `use` entry's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360. |
| `text.grapheme` | assembly | An annotation's text (label, arrow or dimension) has a character (grapheme cluster) of more than 8 Unicode scalars. `part` names the annotation. |
| `component.use.explode` | assembly | A top-level `use` entry's `explode` (v2) is not three coordinates in -4000...4000 mm, or a root part's own explode is not. |
| `tier.key` | assembly, explainer | A v2 document has a key named `tier` somewhere (tiers are computed by the engine, never authored). |

### Parameters

| Reason | Formats | Meaning |
| --- | --- | --- |
| `params` | assembly | `params` is not an object. |
| `params.input` | assembly | `params.input` is not a number in -1e6...1e6. |
| `params.explode` | assembly | `params.explode` is not a number in 0...1. |

### Parts

| Reason | Formats | Meaning |
| --- | --- | --- |
| `parts.count` | assembly, component | `parts` is not an array of 1–48 entries, or component expansion makes more than 96 wire parts (before `repeat`). |
| `parts.resolved` | assembly | More than 96 parts after `use` and `repeat` expansion. The report's `limit` gives the resolved part count (`count`), the limit (`limit`, 96) and the component instances that add the most parts (`top`: up to 5 `{"id", "use", "parts"}`, most parts first, ties by id). |
| `id.duplicate.<id>` | assembly, component | Two parts, `repeat` copies, component instances or anchors share an id, or an annotation id is taken (they share one namespace). |
| `ref.unknown.<id>` | assembly, patch | A reference names no part: a `parent`, a drive `source` or `crank`, a constraint, a step id list, a section part, or a patch part id. |
| `part.object` | assembly | A part entry is not an object. |
| `part.id` | assembly, component | A part id is not an identifier (an ASCII letter, then up to 23 ASCII letters, digits or `_`). |
| `part.name` | assembly | A part name is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 60 characters. |
| `part.parent` | assembly | `parent` is not an identifier. |
| `part.parent.cycle` | assembly | Parents form a cycle. |
| `part.parent.repeat` | assembly | A repeated child of a repeated parent does not repeat the same number of times (copies pair by instance). |
| `part.shape` | assembly | A shape entry is not an object with exactly one shape kind. |
| `part.shape.count` | assembly | A part has no shape or more than 8. |
| `part.shape.gears` | assembly | A part has more than one `gear` or `ringGear` shape. |
| `part.shape.unknown.<name>` | assembly | Unknown shape kind (gear, ringGear, shaft, tube, box, hex, plate, carrier, extrudedProfile, revolvedProfile, blade, bladeRow). |
| `part.material` | assembly | Unknown material: not a preset name, `anodized.<role>` or `plastic.<role>`. |
| `part.joint` | assembly | `joint` is not an object with exactly one kind. |
| `part.joint.unknown.<name>` | assembly | Unknown joint kind (revolute, prismatic). |
| `joint.axis` | assembly | A joint axis is not three coordinates, or it is zero. |
| `part.explode` | assembly | `explode` is not three coordinates in -4000...4000 mm. |
| `part.explodeWindow` | assembly | `explodeWindow` is not [lo, hi] with 0 ≤ lo < hi ≤ 1. |
| `part.phase` | assembly | `phase` is not a number of degrees in -360...360. |
| `part.smooth` | assembly | `smooth` is not a crease angle in 0...180 degrees. |
| `part.offAxis` | assembly | `offAxis` is not a boolean (v2). |
| `part.opacity` | assembly | `opacity` is not a number in 0.1...1 (v2). |
| `part.emissive` | assembly | `emissive` is not an object, or its `intensity` is not in 0...4 (v2). |
| `part.emissive.role` | assembly | `emissive.role` is not a colour role (v2). |
| `part.expect` | assembly | `expect` is not a non-empty object (v2). |
| `part.expect.<direction>` | assembly | `expect.axisWorld` or `expect.upWorld` is not a non-zero direction of three coordinates (v2). |
| `part.repeat` | assembly | `repeat` is not an object. |
| `part.repeat.count` | assembly | `repeat.count` is not a whole number in 2...12. |
| `part.repeat.axis` | assembly | `repeat.axis` is not a non-zero direction of three coordinates. |
| `part.repeat.angle` | assembly | `repeat.angle` is not in -360...360 degrees. |

### Shapes

| Reason | Formats | Meaning |
| --- | --- | --- |
| `part.<shape>` | assembly | A shape's body is not an object. |
| `part.<shape>.<field>` | assembly | A shape field is missing, not a number, out of its range, or not a whole number where one is needed (teeth, arms, counts), or a size derived from it fails (a ring gear's teeth: tip radius not above base radius; a box `size`). |
| `part.<shape>.chamfer` | assembly | The chamfer is too large for the shape (for example half the width or more), or the chamfered cap outlines would cross. |
| `part.<shape>.tip` | assembly | A gear or ring gear tooth has no real tip land (too few teeth for the pressure angle and backlash). |
| `part.<shape>.profile` | assembly | The sampled tooth outline of a gear or ring gear crosses itself, or a ring's tooth spaces close at the root. |
| `part.<shape>.outer` | assembly | A ring gear's `outer` radius is less than one module beyond its root circle, or a tube's `outer` is not larger than its `inner`. |
| `part.gear.bore` | assembly | The bore reaches the tooth root (it must stay half a module inside the root circle). |
| `part.gear.keyway` | assembly | `keyway` is not [width, depth] in 0.1...1000, has no bore, is not narrower than the bore, or reaches the root. |
| `part.<shape>.holes` | assembly | Holes are not a list of valid entries: a plate takes at most 32 [x, y, radius]; an extruded profile at most 16 simple loops inside its outline. |
| `part.plate.holes.outside` | assembly | A plate hole (grown by the chamfers) leaves less than 0.5 mm of rim. |
| `part.<shape>.holes.overlap` | assembly | Two plate holes are closer than 0.5 mm (after chamfers), or two profile holes cross or nest. |
| `part.carrier.armWidth` | assembly | Carrier arms are wider than twice the boss radius, or the hub reaches beyond radius + boss. |
| `part.<shape>.points` | assembly | Profile points are not 3–256 [x, y] pairs (2–256 for a revolved profile), enclose no area, or cross themselves. |
| `part.revolvedProfile.points.radius` | assembly | A revolved profile point has x < 0 (x is the radius). |
| `part.revolvedProfile.axis` | assembly | An open revolved profile has fewer than 3 points, or it does not start and end on the axis (x = 0). |
| `part.revolvedProfile.sweep` | assembly | `sweep` is not in 1...360 degrees. |
| `part.revolvedProfile.start` | assembly | `start` is not in -360...360 degrees. |
| `part.blade.twist` | assembly | \|`pitch` + `twist`\| exceeds 85 degrees. |
| `part.bladeRow.twist` | assembly | \|`stagger` + `twist`\| exceeds 85 degrees. |
| `part.bladeRow.triangles` | assembly | The blade row would have more than 250,000 triangles. |
| `part.bladeRow.chord` | assembly | A blade section reaches half a turn of its cylinder (the chord is too large for the radius). |
| `part.bladeRow.count` | assembly | Neighbouring blades touch (too many blades for the chord). |

### Drives

| Reason | Formats | Meaning |
| --- | --- | --- |
| `part.drive.joint` | assembly | A part without a joint has a drive. |
| `part.drive` | assembly | `drive` is not an object with exactly one kind. |
| `part.drive.input` | assembly | `drive.input` is not a number in -1000...1000. |
| `part.drive.follow` | assembly | `drive.follow` is not an object. |
| `part.drive.follow.source` | assembly | `follow.source` is not a string, or it names the part itself. |
| `part.drive.follow.ratio` | assembly | `follow.ratio` is not a number in -1000...1000. |
| `part.drive.<crank>` | assembly | A `crankSlider` or `crankRod` body is not an object. |
| `part.drive.<crank>.crank` | assembly | A crank drive's `crank` is not a string, or it names the part itself. |
| `part.drive.<crank>.radius` | assembly | A crank drive's `radius` is not a length in 0.05...4000 mm. |
| `part.drive.<crank>.rod` | assembly | A crank drive's `rod` is not a length in 0.05...4000 mm, or it is not longer than the crank radius. |
| `part.drive.crankSlider.joint` | assembly | A `crankSlider` part does not have a prismatic joint. |
| `part.drive.unknown.<name>` | assembly | Unknown drive kind (input, follow, crankSlider, crankRod). |
| `part.drive.cycle` | assembly | Drives depend on each other in a cycle. |

### Constraints

| Reason | Formats | Meaning |
| --- | --- | --- |
| `constraints.count` | assembly, component | `constraints` is not an array of at most 128 entries (component constraints included). |
| `constraint.object` | assembly | A constraint is not an object with exactly one kind. |
| `constraint.unknown.<name>` | assembly | Unknown constraint kind (fixed, gearMesh). |
| `constraint.fixed` | assembly | `fixed` is not a part id string. |
| `constraint.gearMesh` | assembly | A `gearMesh` body is not an object. |
| `constraint.gearMesh.ref` | assembly | `a` or `b` is not a string. |
| `constraint.gearMesh.repeat` | assembly | `a` and `b` name repeated parts with different counts. |
| `constraint.gearMesh.carrier` | assembly | The carrier is unknown, its axis is not parallel to the mesh, neither gear is under it, a gear outside it is off its axis, or it does more than spin about that axis. |
| `constraint.gearMesh.gear` | assembly | A meshed part has no `gear` or `ringGear` shape. |
| `constraint.gearMesh.self` | assembly | A gear meshes with itself. |
| `constraint.gearMesh.module` | assembly | The two gears have different modules. |
| `constraint.gearMesh.kind` | assembly | `b` is a ring gear (a ring gear can only be `a`). |
| `constraint.gearMesh.pressureAngle` | assembly | The two gears have different pressure angles. |
| `constraint.gearMesh.joint` | assembly | A gear's joint axis does not run along the gear axis through its centre, or a meshed gear cannot turn. |
| `constraint.gearMesh.axis` | assembly | The two gear axes are not parallel. |
| `constraint.gearMesh.distance` | assembly | The centre distance differs from the standard distance by more than 0.02 module. |
| `constraint.gearMesh.parentMoves` | assembly | A moving ancestor of a gear has no revolute axis, so the gear centre would move. |
| `constraint.gearMesh.parentRotates` | assembly | A moving ancestor of a gear turns about an axis that is not the mesh axis through the gear centre. |
| `constraint.gearMesh.parentDrive` | assembly | A turning ancestor of a gear has its own drive. |
| `constraint.gearMesh.interference` | assembly | The tooth outlines overlap by more than 0.01 module over one pitch (undercut or too small a tooth difference). |
| `constraint.gearMesh.phase` | assembly | The teeth cannot be phased to mesh around a loop of gears. |
| `constraint.gearMesh.motion` | assembly | Replaying the compiled motion breaks a mesh (axis, centre distance, tooth phase or tooth ratio). |
| `constraint.underdetermined` | assembly | A gear's speed is not fixed by the inputs, `fixed` constraints and meshes. |
| `constraint.ratio` | assembly | A solved joint ratio exceeds 1000 per input radian. |
| `constraint.conflict` | assembly | Inputs, `fixed` constraints and meshes contradict each other. |
| `constraint.conflict.drive` | assembly | A part that the mesh solve moves also has its own drive. |

### Steps

| Reason | Formats | Meaning |
| --- | --- | --- |
| `steps.count` | assembly | `steps` is not an array of at most 16 entries. |
| `step.object` | assembly | A step is not an object. |
| `step.say` | assembly | A step's `say` is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 240 characters, also after placeholders are filled. |
| `step.<list>` | assembly, component | A step id list (`focus`, `highlight`; v2 `hide`, `show`) is not an array of at most 16 strings (a component instance id is one entry); `hide` and `show` must not be empty. |
| `step.pose` | assembly | A step's `pose` is not an object of 1–16 entries (v2). |
| `step.pose.ref` | assembly | A `pose` entry names neither a component instance (a top-level `use` id), an authored part nor a part inside an instance (by id or anchor), names a `repeat` copy, or names one part twice. `part` gives the id. |
| `step.pose.key` | assembly | A `pose` entry is not an object of `with` and/or `rot`, gives a key its id does not take (an instance takes `with`, a part takes `rot`), or has a `rot` that is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360. |
| `step.pose.with` | assembly | A `pose` entry's `with` is not an object of the component's parameters in range, or the change alters something other than placements (a shape, a material, a parent, an explode vector). |
| `step.pose.solved` | assembly | The pose moves a part of a gear solve or a constrained mechanism (a gear pair or carrier, a gear-mesh or crank drive or its source, a part held by `fixed` or `gearMesh`), or it would change the compiled motion or an engine fact. `part` gives the first such part when there is one. |
| `step.hide.both` | assembly | A step lists one part in both `hide` and `show` (v2). |
| `step.hide.use` | assembly | A step focuses, highlights, ghosts or cuts a part it hides (its `hide`, or a show-only part it does not `show`). |
| `step.hide.claim` | assembly | An annotation a step shows is anchored on a part the step hides. |
| `step.hide.fact` | assembly | A view displays a fact of a part it hides: the text of an annotation it shows, or a step's caption or `check`; or the title shows a fact of a part that any view hides. `part` names the fact. |
| `step.pose.fact` | assembly | A `dim.<id>` fact does not hold over a step's whole motion domain at its pose (every input its `spin` plays, at its explode value and placements): one of its `check` claims, or for a posed step its caption, the title or the text of an annotation it shows. `part` names the fact. |
| `step.show.claim` | assembly | The plain view shows an annotation anchored on a show-only part (a part some step lists in `show`), which the plain view hides. |
| `step.camera` | assembly | `camera` is not a camera preset name (`hero`, `front`, `side`, `top`, `low`, `back`, `iso`, `backLeft` or `backRight`). |
| `step.explode` | assembly | `explode` is not a number in 0...1. |
| `step.orbit` | assembly | `orbit` is not in -360...360 degrees. |
| `step.spin` | assembly | `spin` is not in -20...20 input turns. |
| `step.unchecked` | assembly | `unchecked` is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 60 characters (v2). |
| `step.check` | assembly | `check` is not an array of 1–8 claim checks (v2). |
| `step.ghost` | assembly | `ghost` is not a non-empty array of at most 16 part id strings (v2). |
| `step.section` | assembly | `section` is not an object (v2). |
| `step.section.normal` | assembly | `section.normal` is not a non-zero direction of three coordinates. |
| `step.section.offset` | assembly | `section.offset` is not in -4000...4000 mm. |
| `step.section.parts` | assembly | `section.parts` is not 1–16 part id strings. |

### Claim checks and text

| Reason | Formats | Meaning |
| --- | --- | --- |
| `check.object` | assembly, explainer | A claim check is not an object. |
| `check.value` | assembly, explainer | A claim check's `value` is not a fact name. |
| `check.comparison` | assembly, explainer | A claim check does not have exactly one of `eq`, `lt`, `gt`. |
| `check.eq` | assembly, explainer | The `eq` target is not a number in -1e6...1e6. |
| `check.lt` | assembly, explainer | The `lt` target is not a number in -1e6...1e6. |
| `check.gt` | assembly, explainer | The `gt` target is not a number in -1e6...1e6. |
| `check.tol` | assembly, explainer | `tol` is given without `eq`, or it is not in 0...1e6. |
| `check.fact.<name>` | assembly, explainer | A claim check names a fact that does not exist. |
| `check.failed.<name>` | assembly, explainer | A claim check is false for the engine's value. |
| `text.brace` | assembly | A `{` or `}` in the title or a caption is unbalanced or nested. |
| `text.placeholder` | assembly | A placeholder is malformed: no valid fact name, too many modifiers, too long, or a modifier with a dot. |
| `text.placeholder.<name>` | assembly | A placeholder names no fact. |
| `text.modifier.<modifier>` | assembly, explainer | Unknown placeholder modifier (abs, inv, pct, deg, frac). |
| `text.modifier.<modifier>.<name>` | assembly, explainer | A modifier cannot apply to this fact: a value with a unit, `pct` or `deg` on a fact that is not a turn rate, a modifier after a terminal one, `inv` of 0, or no exact fraction. |
| `text.range.<name>` | assembly | A placeholder value overflows or underflows, or would print as 0 although it is not 0. |
| `text.rounding.<name>` | assembly | A placeholder would show a non-zero value as "0"; use `frac` or `inv`. |
| `text.number.step.<n>` | assembly | A v2 caption has a number character outside a placeholder and the step is not marked `unchecked` (rule N1). |
| `text.sign.<name>` | assembly, explainer | `abs` hides a sign that no strict-inequality check in the same step proves (the title can never use `abs`). |
| `expect.axis.<id>` | assembly | The part's world turn axis differs from `expect.axisWorld` by more than 1 degree (v2). |
| `expect.up.<id>` | assembly | The part's local +Z in the world differs from `expect.upWorld` by more than 1 degree (v2). |

### Step section cuts

| Reason | Formats | Meaning |
| --- | --- | --- |
| `section.miss.<id>` | assembly | A step's section plane misses a listed part. |
| `section.empty.<id>` | assembly | A step's section plane removes a listed part completely. |
| `section.open.<id>` | assembly | A built cut fails the consistency check (closed, outward, caps without overlap). |
| `section.loops.<id>` | assembly | The open edges of a cut do not chain into closed loops (the part mesh is not closed). |
| `section.nesting.<id>` | assembly | A hole loop of a cut has no outer loop that contains it. |
| `section.mesh.<id>` | assembly | The part mesh is malformed or the plane is not finite. |
| `section.budget` | assembly, section | The step cuts exceed the section work budget (part triangles read, or cap work). |
| `section.miss` | section | The plane misses the mesh. |
| `section.empty` | section | The plane removes the whole mesh. |
| `section.loops` | section | The open edges of the cut do not chain into closed loops. |
| `section.nesting` | section | A hole loop has no outer loop that contains it. |
| `section.mesh` | section | The mesh is malformed or the plane is not finite. |

### Honesty warnings

| Reason | Formats | Meaning |
| --- | --- | --- |
| `joint.idle.<id>` | assembly | (warning; strict refuses) A jointed part that no drive or constraint moves, so it never moves. |
| `frame.axis.off.<id>` | assembly | (warning; strict refuses) A revolute part's axis line misses its own mesh bounds (mark an intended outside axis with `"offAxis": true`, v2). |
| `frame.child.absolute.<id>` | assembly | (warning) A child placed as if its `at` / `rot` were world values (the double offset), confirmed by bounds. |
| `frame.child.far.<id>` | assembly | (warning) A child's bounds miss its parent's bounds grown by 1.5 parent sizes. |
| `annotation.unused.<id>` | assembly | (warning; strict refuses) Some step uses `annotate`, but no step shows this annotation. |
| `annotation.cut.<id>` | assembly | (warning) A part anchor of an annotation that a step shows lies in the half that the step's `section` removes from that part. |
| `annotation.anchor.off.<id>` | assembly | (warning; strict refuses) A label's anchor (`at`) or a pointer's tip (`to`) lies farther from the box of the part it names, in that part's own frame, than max(5 % of that box's diagonal, 0.5 % of the diagonal of the parts the views showing it draw); or, at the pose of a view that shows it, another part's solid (its surface, or its inside by watertight parity) comes nearer to it than that box by more than the precision epsilon at the dot (1e-6 × max(1, |p − anchor|) + 1e-4 mm, in anchor-relative coordinates). The nearer-part search is exact and budgeted; when its budget runs out the anchor is `annotation.anchor.untested.<id>`, never off. The report's `anchor` gives the distance, the tolerance, the view, the nearer part (`closer`) and a fix. |
| `annotation.anchor.hidden.<id>` | check, explainer | (warning; the strict check report refuses) A step or beat still shows a label or pointer whose anchor point it does not show: the anchor's part is hidden or ghosted in that view, the point is off screen, or another part is the first surface on the line of sight (a cut part's inside does not count). The report's `anchor` gives the step or beat, the cause, the part in the way and a fix. |
| `annotation.anchor.untested.<id>` | check, explainer | (warning; the strict check report refuses) A step or beat still shows a label or pointer that was not fully tested: the view's 3,000,000 line-of-sight triangle tests, or the document's 3,000,000 nearer-part tests, ran out first. The strict check report refuses it, because strict does not pass what it did not check. |
| `annotation.arrow.hidden.<id>` | check, explainer | (warning; the strict check report refuses) A step or beat still shows an arrow (force, flow, motion or pointer) of which less than half of the sample points along its drawn shaft and head, or fewer than two of its three head samples, are visible from the still's camera: off screen, or behind another part by the line-of-sight rule of the anchor checks (the parts the arrow is anchored on hide it too; a cut part's inside does not count). The report's `arrow` gives the step or beat, the visible share, the part in the way and a suggested move. |
| `annotation.arrow.untested.<id>` | check, explainer | (warning; the strict check report refuses) A step or beat still shows an arrow that was not fully tested: the view's 3,000,000 arrow sample tests ran out first. The strict check report refuses it, because strict does not pass what it did not check. |
| `annotation.arrow.dropped.<id>` | check, explainer | (warning) A step or beat still does not draw a force or flow arrow that its view lists: the arrow's tail is on its part, and another part (outside that part's unit) hides the tail from the still's camera, so the part the arrow acts on is hidden there. The still and its story frames leave the arrow out (a snapshot, which has no camera, keeps it); it is not moved and not refused. The report's `arrowDrops` gives the view, the tail's part and the part in the way. |

### Annotations (v2)

| Reason | Formats | Meaning |
| --- | --- | --- |
| `annotations.object` | assembly | `annotations` is not an object (v2). |
| `labels.count` | assembly | `labels` is not an array of at most 32 labels. |
| `arrows.count` | assembly | `arrows` is not an array of at most 32 arrows. |
| `dimensions.count` | assembly | `dimensions` is not an array of at most 16 dimensions. |
| `annotations.input` | assembly | A document with annotations has a default input beyond 10,000 turns (`MGSolidAnnotationLimits.input`), so its poses would lose precision. |
| `annotations.visible` | assembly | No step uses `annotate`, so every annotation shows at once, and there are more than 12. The report's `visibility` names the first annotation over the limit, the count, the limit and the cause (`nosteps` or `unannotated`). An explainer solid never gives it: there the limit applies to each beat's own list (`view.annotate.count`). |
| `label.object` | assembly | A label is not an object. |
| `arrow.object` | assembly | An arrow is not an object. |
| `dimension.object` | assembly | A dimension is not an object. |
| `label.id` | assembly | A label id is not an identifier. |
| `arrow.id` | assembly | An arrow id is not an identifier. |
| `dimension.id` | assembly | A dimension id is not an identifier. |
| `anchor.form` | assembly | An anchor is not a part id, `{"part"}` (the part's centre), `{"part", "offset"}`, `{"part", "point"}` or `{"world"}`. |
| `anchor.offset` | assembly | An anchor `offset` is not three coordinates in -4000...4000 mm. |
| `anchor.point` | assembly | An anchor `point` is not "centre". |
| `anchor.world` | assembly | An anchor `world` point is not three coordinates in -4000...4000 mm. |
| `anchor.ref.<id>` | assembly | An annotation anchor or turn arrow `on` names no part, copy or component anchor. |
| `anchor.ambiguous.<id>` | assembly | An annotation anchor names a `repeat` base with copies or a component instance (more than one part). |
| `label.text.<id>` | assembly | A label's text is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 240 characters, or of 1–60 characters after placeholders are filled. |
| `label.unchecked.<id>` | assembly | A label's `unchecked` is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 60 characters. |
| `names.count` | assembly, explainer | `names` is not an array of strings, or it has fewer than 1 or more than 24 entries (`MGSolidFacts.namesCount`). |
| `names.text.<n>` | assembly, explainer | Declared name `<n>` (1-based) is not 1–24 characters long (`MGSolidFacts.nameText`). |
| `names.token.<n>` | assembly, explainer | Declared name `<n>` is not one token (a run of letters, number characters and "-" with no space or punctuation) or has no number character, so no text could match it. |
| `names.number.<n>` | assembly, explainer | Declared name `<n>` is a number, or a number joined to a unit or quantity word ("Mach2", "USD120", "RPM120", "120km", "4th"): a quantity is a claim, not a name. |
| `text.number.label.<id>` | assembly | A label has a number character outside a placeholder and is not marked `unchecked` (rule N1). |
| `arrow.meaning.<id>` | assembly | An arrow's `meaning` is not force, flow, motion or pointer. |
| `arrow.style.<id>` | assembly | A motion arrow's `style` is not line or turn. |
| `arrow.key.<field>.<id>` | assembly | An arrow has a key that its meaning (and style) does not take. |
| `arrow.on.<id>` | assembly | A turn arrow's `on` is not a string. |
| `arrow.from.<id>` | assembly | A motion line arrow starts at a world point; it needs a part anchor. |
| `arrow.sense.form.<id>` | assembly | A turn arrow's `sense` is not "cw" or "ccw". |
| `arrow.expect.form.<id>` | assembly | A motion arrow's `expect` is not a non-zero direction of three coordinates. |
| `arrow.length.form.<id>` | assembly | A motion arrow's `length` is not a number in 10...4000 mm or `{"fact", "scale"}` with a fact name and a scale in 0.001...1000. |
| `arrow.cause.<id>` | assembly | A force arrow's `cause` is not "gravity". |
| `arrow.text.<id>` | assembly | An arrow's text is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 240 characters, or of 1–60 characters after placeholders are filled. |
| `arrow.unchecked.<id>` | assembly | An arrow's `unchecked` is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 60 characters. |
| `arrow.unchecked.text.<id>` | assembly | An arrow has `unchecked` but no `text` for it to mark. |
| `text.number.arrow.<id>` | assembly | An arrow's text has a number character outside a placeholder and is not marked `unchecked` (rule N1). |
| `arrow.turn.joint.<id>` | assembly | A turn arrow's part has no revolute joint. |
| `arrow.turn.steady.<id>` | assembly | A turn arrow's part has no single world turn rate: a turning joint above it turns about an axis that is not parallel to its own. |
| `annotation.motion.nonlinear.<id>` | assembly | A motion arrow, a turn arrow or a dimension shown in a moving step sits on a motion chain that is not linear in the input: some moving joint above it has a crank-slider or crank-rod drive (or follows one), so the motion reverses or changes speed. Show it in a still step, or use a turn arrow on a steady part. |
| `arrow.still.<id>` | assembly | A turn arrow's part has no own turning joint (it may still ride a turning parent), or a motion line arrow's anchor has no velocity at the default input. |
| `arrow.sense.<id>` | assembly | A turn arrow's stated `sense` is the opposite of the engine's (seen from the tip of the joint axis). |
| `arrow.expect.<id>` | assembly | A motion arrow's stated `expect` is more than 30° from the engine's direction, sign included. |
| `arrow.length.fact.<id>` | assembly | A motion arrow's `length` names no fact. |
| `arrow.length.<id>` | assembly | A force, flow or pointer arrow is shorter than 0.5 mm at the default input. |
| `arrow.gravity.<id>` | assembly | A force arrow with `"cause": "gravity"` points more than 10° away from world -Z at the default input. |
| `dimension.kind.<id>` | assembly | A dimension's `kind` is not distance or angle. |
| `dimension.along.<id>` | assembly | A dimension's `along` is not x, y or z, or the dimension is an angle. |
| `dimension.over.form.<id>` | assembly | A dimension's `over` is not "input". |
| `dimension.vertex.<id>` | assembly | An angle dimension has no `vertex`, or a distance dimension has one. |
| `dimension.text.form.<id>` | assembly | A dimension's text is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 240 characters, or of 1–60 characters after placeholders are filled. |
| `dimension.zero.<id>` | assembly | A distance below 0.01 mm at the default input, or an angle arm below 0.01 mm (at the default input, or at any sample with `over`). |
| `dimension.over.still.<id>` | assembly | A dimension with `over` changes by less than 0.01 mm (or 0.01°) over one input turn. |
| `annotation.pose.<id>` | assembly | A shown annotation's claim does not hold at every pose its view can show (a step's `spin` range at its explode value, or the plain view's default pose), decided exactly: a shown dimension, or a `dim.<id>` fact its text shows, that changes during the view or differs at the view's pose; a gravity arrow that turns or does not point down; a motion line arrow that rides a turning joint in a moving step, or whose `expect` fails at some pose; a stated `sense` that a backwards step reverses. |
| `dimension.over.motion.<id>` | assembly | A dimension with `over` is not one whose exact range the engine has: a distance (optionally along an axis) with exactly one anchor that moves, by one prismatic joint with a linear drive or a crank-slider, the other anchor staying where it is. |
| `text.pose.step.<n>` | assembly | A step caption shows a `dim.<id>` fact that does not hold at every pose the step can show. |
| `text.pose.title` | assembly, explainer | The title shows a `dim.<id>` fact that does not hold at every pose of every view. |
| `dimension.over.<id>` | assembly | A dimension has `over` but no anchor that moves. |
| `dimension.fact.<id>` | assembly | The fact name `dim.<id>` already exists (for example a part named `dim`). |
| `dimension.text.<id>` | assembly | A dimension's text does not show its own value `{dim.<id>}`. |
| `text.number.dimension.<id>` | assembly | A dimension's text has a number character outside a placeholder (rule N1; no `unchecked`). |
| `step.annotate` | assembly | A step's `annotate` is not an array of strings (v2). |
| `step.annotate.count` | assembly | A step's `annotate` lists more than 12 annotations. The report's `visibility` names the step (1-based), the 13th id, the count and the limit (cause `step`). |
| `step.annotate.ref.<id>` | assembly | A step's `annotate` names no annotation. |

### Patches

| Reason | Formats | Meaning |
| --- | --- | --- |
| `patch.bytes` | patch | The patch text is over 64 KiB. |
| `patch.json` | patch | The patch bytes are not UTF-8 JSON text (invalid UTF-8, a raw NUL byte, or text the JSON parser rejects). |
| `patch.depth` | patch | The patch nests deeper than 64 levels. |
| `patch.object` | patch | The patch is not a JSON object. |
| `patch.unknown.<keys>` | patch | The patch has keys other than params, parts, constraints, steps and title (`<keys>` lists them). |
| `patch.unknown.` | patch | The patch is an empty object. |
| `patch.source` | patch | The document has no object source to patch. |
| `patch.parts` | patch | `parts` is not an object of edits by id, or the document has no parts array. |
| `patch.parts.object` | patch | A part edit is not an object. |
| `patch.parts.id` | patch | A part edit sets `id` (ids are stable). |
| `patch.parts.set` | patch | An edit of a part inside a component instance cannot merge into that `use` entry's `set`. |

### Components

| Reason | Formats | Meaning |
| --- | --- | --- |
| `component.bytes` | component, cli | A definition is over 16 KiB (its bytes, or its canonical JSON). |
| `component.nesting` | component | A definition nests deeper than 64 levels. |
| `component.object` | component | A definition is not a JSON object. |
| `component.version` | component | `v` is not 1. |
| `component.kind` | component | `kind` is not "component". |
| `component.id` | component | The component id is not an identifier. |
| `component.title` | component | The title is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 80 characters. |
| `component.about` | component | `about` is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 160 characters. |
| `component.params` | component | `params` is not an object of at most 16 parameters. |
| `component.param.name.<name>` | component | A parameter name is not an identifier, or it is an expression operator name. |
| `component.param.<ident>` | component | A parameter is not an object with numbers min ≤ default ≤ max in ±1e6, a boolean `integer` (whole bounds and default when true) and an `about` of valid text. |
| `component.parts.count` | component | `parts` is not an array of 1–24 entries. |
| `component.part` | component | A part entry is not an object with a string id (after parameters are substituted). |
| `component.use` | component | A nested `use` is not a string. |
| `component.use.parent` | component | A `use` entry's `parent` is not a string. |
| `component.cycle.<id>` | component | A component uses itself, directly or through other components. |
| `component.unknown.<keys>` | assembly, component | `use` names a component that is not in the library (`<keys>` is then its id). The same string also answers a component definition with unknown top-level keys: one string, two causes. |
| `component.depth` | assembly, component | `use` nests more than 3 levels deep. |
| `component.constraints` | component | `constraints` is not an array of at most 32 entries. |
| `component.anchors` | component | `anchors` is not an object of at most 8 anchors. |
| `component.anchorAbout` | component | `anchorAbout` is not an object, names a key that is not an anchor, or has a text that is not 1–120 scalars of plain text (no `<`, `>`, `://` or control characters). |
| `component.anchor.<name>` | component | An anchor name is not an identifier or is taken, or its target is not a part, copy or nested anchor of the component. |
| `component.checks` | component | `checks` is not an object of at most 8 checks. |
| `component.check.name.<name>` | component | A check name is not an identifier. |
| `component.check` | component | A check is not `{"lt": [a, b]}`, `{"le": [a, b]}` or `{"int": a}`. |
| `component.check.<ident>` | assembly, component | A component check is false for the parameters of an instance. |
| `component.expr` | component | An expression has an unknown operator or is not a number or an expression. |
| `component.expr.<op>` | component | An expression operator (add, mul, min, max, sub, neg, pi, sin, cos) has the wrong operands (`<op>` names it). |
| `component.expr.depth` | component | An expression nests deeper than 8 levels. |
| `component.expr.size` | component | An instance evaluates more than 4,096 expression nodes. |
| `component.expr.param` | component | `param` does not take a string. |
| `component.expr.param.<name>` | component | `param` names no parameter. |
| `component.expr.div` | component | Division by zero, or `div` without exactly two operands (one string, two causes). |
| `component.expr.range` | component | An expression result is not finite or exceeds ±1e6. |
| `component.param.unknown.<name>` | assembly, component | `with` names no parameter of the component. |
| `component.param.value.<ident>` | assembly, component | A `with` value is not a finite number. |
| `component.param.range.<ident>` | assembly, component | A `with` value is outside the parameter's min...max. |
| `component.param.integer.<ident>` | assembly, component | A `with` value is not whole for an integer parameter. |
| `component.with` | assembly, component | `with` is not an object. |
| `component.set` | assembly, component | `set` is not an object. |
| `component.set.repeat.<id>` | assembly, component | `set` names one copy of a repeated part; edit the base id (every copy). |
| `component.set.unknown.<id>` | assembly, component | `set` names no part of the instance. |
| `component.set.id` | assembly, component | A `set` entry is not an object, or it sets `id` or `use`. |
| `component.id.length` | assembly, component | A resolved part id (`stage1.gears.pinion`, with any `repeat` suffix) is longer than 64 characters. |
| `component.ref.unknown.<id>` | component | A reference inside a component names no inner part, copy or anchor. |
| `ref.component.<id>` | assembly | A part reference names a component instance (a group); only steps may name an instance. |
| `component.duplicate.<id>` | component | The library already has a component with this id. |
| `component.library.count` | component | The library already holds 128 components. |

### Check report

| Reason | Formats | Meaning |
| --- | --- | --- |
| `check.meshOpen` | check | A part mesh or a step cut is not closed (`checks.openMeshes` lists them; a cut as `step.<n>.<part>`). |
| `check.gearsInterpenetrate` | check | The gear tooth sweep over one input turn overlaps more than `checks.toleranceMM` (0.01 of the smallest module). |

### Snapshots

| Reason | Formats | Meaning |
| --- | --- | --- |
| `solidSnapshot.bytes` | snapshot | The snapshot text is over 256 MiB (`MGSolidSnapshot.maxBytes`). |
| `solidSnapshot.json` | snapshot | The snapshot bytes are not valid UTF-8, or they hold a raw NUL byte. |
| `solidSnapshot.depth` | snapshot | The snapshot text nests deeper than 64 levels. |
| `solidSnapshot.number` | snapshot | A number literal is longer than 64 characters or does not read as a finite number (for example `1e999`). |
| `solidSnapshot.invalid` | snapshot | The JSON decoder or a validating initialiser refused the snapshot (format, slot sizes, ranges, v2 fields in /1). |

### Explainer documents

See [EXPLAINER.md](EXPLAINER.md). These come from explainer documents and streams; the explainer also gives
`tier.key`, `check.fact.<name>`, `check.failed.<name>`, `text.sign.<name>` and the `text.modifier` reasons above, and
passes inner scene, lesson and assembly reasons through unchanged.

| Reason | Formats | Meaning |
| --- | --- | --- |
| `explainer.json` | explainer | The document bytes are not UTF-8 JSON text. |
| `explainer.object` | explainer | The document, or a header statement's value, is not a JSON object. |
| `explainer.number` | explainer | A document or statement built in code holds NaN or an infinity. |
| `explainer.depth` | explainer | The document nests deeper than 63 levels, or a stream statement deeper than 64. |
| `explainer.bytes` | explainer | The raw document is over 128 KiB, its flattened statement stream is over 64 KiB, or a stream received more than 64 KiB. |
| `explainer.version` | explainer | `v` is not 1 (the explainer format version). |
| `explainer.kind` | explainer | `kind` is not "explainer". |
| `explainer.missing` | explainer | A header statement has no `v`. |
| `explainer.unknown.<keys>` | explainer | The document or a header statement has keys it does not allow (`<keys>`: sorted author segments). |
| `explainer.title` | explainer | The title is not plain text of 1–80 characters after 3D facts fill it, or it names a 2D value. |
| `explainer.primary` | explainer | `primary` is not "board" or "solid", or it names a view the explainer does not have. |
| `explainer.empty` | explainer | The explainer has neither a `board` nor a `solid`. |
| `explainer.header` | explainer | A new stream does not start with an explainer header (or `keep`). |
| `explainer.statements.count` | explainer | A stream holds more than 256 statements (terminal). |
| `explainer.board` | explainer | `board` is not an object. |
| `explainer.board.steps` | explainer | The board has `steps` (beats replace them). |
| `explainer.board.title` | explainer | The board has a `title` (the explainer has one title). |
| `explainer.board.dim` | explainer | The board is `"dim": "3d"` (3D belongs in `solid`). |
| `explainer.board.missing` | explainer | A beat command needs a board, and the explainer has none. |
| `explainer.solid` | explainer | `solid` is not an object. |
| `explainer.solid.version` | explainer | The solid is not an assembly v2. |
| `explainer.solid.steps` | explainer | The solid has `steps` (beats replace them). |
| `explainer.solid.title` | explainer | The solid has a `title` (the explainer has one title). |
| `explainer.solid.missing` | explainer | A beat `view` needs a solid, and the explainer has none. |
| `explainer.beats` | explainer | `beats` is missing, not an array, or empty. |
| `explainer.beats.count` | explainer | More than 16 beats in one explainer, over all its streams. |
| `explainer.op.title` | explainer | A beat command is `title` (the explainer has one title). |
| `explainer.id.duplicate.<id>` | explainer | A 2D item or control id equals a 3D part, copy, `repeat` base, instance or anchor id, or a control id equals a 2D item id (one namespace). |
| `explainer.id.view.<id>` | explainer | A 2D command (`set`, `remove`) names a 3D id. |
| `notes.object` | explainer | `notes` is not an object. |
| `notes.count` | explainer | `notes` has no entry or more than 24. |
| `notes.entry.<id>` | explainer | A note key is not an item id, or its value is not exactly one of `basis` and `unchecked`. |
| `notes.text.<id>` | explainer | A note's text is not plain text of 1–60 characters. |
| `notes.view.<id>` | explainer | A note key names a 3D id (notes mark 2D items only). |
| `notes.unused.<id>` | explainer | (warning; the explainer strict check refuses) A note names no 2D item the board ever has. |
| `beat.object` | explainer | A beat is not an object. |
| `beat.missing` | explainer | A beat has no `say`. |
| `beat.unknown.<keys>` | explainer | A beat or a `say` statement has keys it does not allow. |
| `beat.unchecked.<n>` | explainer | Beat `<n>`'s `unchecked` is not plain text of 1–60 characters. |
| `beat.ops` | explainer | A beat's `ops` is not an array. |
| `beat.ops.count` | explainer | A beat has more than 12 commands. |
| `beat.check` | explainer | A beat's `check` is not an array. |
| `beat.checks.count` | explainer | A beat has more than 8 checks, 2D and 3D together. |
| `beat.refused` | explainer | A statement belongs to a beat that a failed check already refused (a cascade). |
| `beat.highlight` | explainer | A `highlight` is not an array of strings. |
| `beat.highlight.count` | explainer | A `highlight` has no id or more than 16. |
| `beat.highlight.ref.<id>` | explainer | A highlight id names no 2D item, control, 3D member or table row or cell of the board at that beat. |
| `beat.highlight.stale.<id>` | explainer | (warning) At presentation a highlight id no longer resolves; it is dropped and recorded in `hostIssues` (nothing is refused). |
| `stmt.json` | explainer | A stream statement is not UTF-8 JSON text, or non-whitespace text between statements was skipped. |
| `stmt.kind` | explainer | A stream statement is not one of the explainer statement kinds. |
| `stmt.order` | explainer | A statement comes out of order (a view after the first beat or twice, a beat statement with no open beat, a header mid-stream). |
| `stmt.bytes` | explainer | A statement other than `solid` is over 4 KiB. |
| `stmt.say` | explainer | A caption is not a string of 1–200 characters. |
| `stmt.view.twice` | explainer | A beat has a second `view` statement. |
| `stmt.highlight.twice` | explainer | A beat has a second `highlight` statement. |
| `lesson.depth` | explainer | A statement other than `solid` nests deeper than 59 levels (the lesson statement cap). |
| `view.object` | explainer | A beat `view` is not an object. |
| `view.unknown.<keys>` | explainer | A beat `view` has keys that are not view keys (focus, explode, camera, orbit, spin, section, ghost, annotate, pose, hide, show). |
| `view.focus` | explainer | A beat view's `focus` is not an array of at most 16 strings. |
| `view.camera` | explainer | A beat view's `camera` is not a camera preset name (`hero`, `front`, `side`, `top`, `low`, `back`, `iso`, `backLeft` or `backRight`). |
| `view.explode` | explainer | A beat view's `explode` is not a number in 0...1. |
| `view.orbit` | explainer | A beat view's `orbit` is not a number of degrees in -360...360. |
| `view.spin` | explainer | A beat view's `spin` is not a number of input turns in -20...20. |
| `view.ghost` | explainer | A beat view's `ghost` is not a non-empty array, or it has more than 16 entries or a non-string entry. |
| `view.section` | explainer | A beat view's `section` is not an object. |
| `view.section.normal` | explainer | A beat view's section normal is not three coordinates, or it is zero. |
| `view.section.offset` | explainer | A beat view's section offset is not in -4000...4000 mm. |
| `view.section.parts` | explainer | A beat view's section `parts` is not an array of 1–16 strings. |
| `view.section.missing.<keys>` | explainer | A beat view's `section` has no `normal` or no `parts`. |
| `view.section.unknown.<keys>` | explainer | A beat view's `section` has keys it does not allow. |
| `view.annotate` | explainer | A beat view's `annotate` is not an array of strings (the assembly's `step.annotate`). |
| `view.annotate.count` | explainer | A beat view's `annotate` lists more than 12 annotations. The report's `visibility` names the beat (1-based), the 13th id, the count and the limit (cause `beat`). |
| `view.annotate.ref.<id>` | explainer | A beat view's `annotate` names no annotation. |
| `view.hide.fact` | explainer | A beat's caption, a 3D check or the text of an annotation it shows displays a fact of a part its view hides, or the title or the board text shows a fact of a part that any view hides (the assembly's `step.hide.fact`). `id` names the fact. |
| `view.pose.fact` | explainer | A `dim.<id>` fact does not hold over a beat's whole motion domain at its pose: a 3D check of the beat, or for a beat with a `pose` its caption, the title, the board text or annotation text (the assembly's `step.pose.fact`). `id` names the fact. |
| `view.pose` | explainer | A beat view's `pose` is not an object of 1–16 entries (the assembly's `step.pose`). |
| `view.pose.ref` | explainer | A beat view's `pose` names nothing it can pose, or one part twice (the assembly's `step.pose.ref`). |
| `view.pose.key` | explainer | A beat view's `pose` entry has a key its id does not take or a bad `rot` (the assembly's `step.pose.key`). |
| `view.pose.with` | explainer | A beat view's `pose` `with` is not valid or changes more than placements (the assembly's `step.pose.with`). |
| `view.pose.solved` | explainer | A beat view's `pose` moves a solved mechanism or changes an engine fact (the assembly's `step.pose.solved`). |
| `view.hide` | explainer | A beat view's `hide` is not a non-empty array of at most 16 strings. |
| `view.show` | explainer | A beat view's `show` is not a non-empty array of at most 16 strings. |
| `view.hide.both` | explainer | A beat view lists one part in both `hide` and `show`. |
| `view.hide.use` | explainer | A beat view focuses, highlights, ghosts or cuts a part it hides. |
| `view.hide.claim` | explainer | A part a beat view hides carries an annotation the beat shows (the assembly's `step.hide.claim`). |
| `view.show.claim` | explainer | The plain view shows an annotation on a show-only part (the assembly's `step.show.claim`). |
| `text.pose.beat.<n>` | explainer | Beat `<n>`'s caption shows a `dim.<id>` fact that does not hold at every pose its view can show (the assembly's `text.pose.step.<n>` rule). |
| `text.pose.board` | explainer | 2D board text shows a `dim.<id>` fact that does not hold at every pose of every view (the rule for shown text). |
| `check.unknown.<keys>` | explainer | A 3D check (dotted `value`) has keys it does not allow (the assembly's `step.check.unknown.<keys>`). |
| `text.number.beat.<n>` | explainer | Beat `<n>`'s caption types a number character outside a placeholder and has no `unchecked` (rule N1). |
| `text.number.item.<id>` | explainer | A 2D item without a note shows a typed number: in its text, a table or array cell, a bar value or a plot range (rule N1). |
| `text.number.control.<id>` | explainer | A control label types a number character (rule N1; a label takes no placeholder). |
| `text.number.template` | explainer | A raw template's params carry a string with a typed number (rule N1). |
| `snapshot.bytes` | explainer | An explainer snapshot is over its size cap. |
| `snapshot.number` | explainer | An explainer snapshot holds NaN or an infinity. |
| `snapshot.json` | explainer | Explainer snapshot text is not UTF-8 JSON. |
| `snapshot.setup` | explainer | The explainer snapshot's set-up commands are not valid. |
| `snapshot.controls` | explainer | A saved control is not one that a checked `bind` of the script or the host made (its label is learner-visible text). |
| `snapshot.depth` | explainer | An explainer snapshot nests deeper than 64 levels. |
| `snapshot.kind` | explainer | The value is not an explainer snapshot. |
| `snapshot.version` | explainer | The explainer snapshot version is not 1. |
| `snapshot.header` | explainer | The explainer snapshot has no header object. |
| `snapshot.header.missing` | explainer | The explainer snapshot header has no `v`. |
| `snapshot.header.unknown.<keys>` | explainer | The explainer snapshot header has keys it does not allow. |
| `snapshot.frozen` | explainer | The explainer snapshot's `frozen` flag is not a boolean. |
| `snapshot.beats` | explainer | The explainer snapshot's beat records are not valid, or a kept beat is neither shown nor queued in the lesson. |
| `snapshot.next` | explainer | The explainer snapshot's statement position is not valid. |
| `snapshot.board` | explainer | The explainer snapshot's board is not valid, or the board and the boardless lesson disagree. |
| `snapshot.solid` | explainer | The explainer snapshot's solid is not valid JSON text, or 3D beat data has no solid. |
| `snapshot.lesson` | explainer | The explainer snapshot's lesson snapshot is not JSON text. |
| `snapshot.pending` | explainer | A beat the restored lesson still queues does not match the explainer's beat, or a queued command breaks the explainer's command rules. |
| `snapshot.presented` | explainer | The explainer snapshot's presented beats are not valid: one is not a kept beat, comes after the lesson's beat, or is still queued. |
| `snapshot.shown` | explainer | The explainer snapshot's record of shown 2D item, beat, annotation or motion claims is not valid: not an array of at most 1024 `{"id", "tiers"}` (or 16 `{"beat", "caption", "checks"}`, or 80 `{"id", "tier"}`) entries, an id or beat twice, an id the id history does not hold, a 3D id, a beat that was not presented, an unknown tier, a tier twice or a tier the text cannot have, or it misses an item or presented beat, or what the state shown now shows; `shownAnnotations` is present while the show-all rule applies, or names something that is not an annotation with a claim at its tier, or misses an annotation a presented beat displays; `shownMotion` (at most 96 `{"id", "tier"}`) is present while no view hides parts, or names something that is not a motion claim at its tier, or misses the motion of a part a presented beat displays. |
| `snapshot.labels` | explainer | The explainer snapshot's `chooseLabels` (the label-selection mode) is present but not `true` (`false` included). |
| `snapshot.beat` | explainer | The explainer snapshot's presented beat names no kept beat, or not the lesson's presented beat. |
| `snapshot.stream` | explainer | The explainer snapshot's stream status is not valid. |

### Tool

| Reason | Formats | Meaning |
| --- | --- | --- |
| `report.encoding` | check, cli | A value given to `MGSolidReport.text` or as render manifest outputs is not finite or nests too deep, so it is not encoded (reports the engine builds never are). |
| `report.engine` | check, explainer | The host's `engine` value is not finite, nests deeper than 8 levels or is larger than 4,096 bytes (`MGSolidReport.engineDepth`, `engineBytes`). |
| `story.rate` | cli | `marty-solid render --story-fps` is not one of the story rates (10 or 30). |
| `story.beats` | cli | A story plan got no beat, more than 16 beats, or a different number of captions and spins. |
| `story.frames` | cli | The story video would have more than 3,600 frames (`MGStoryTiming.maxFrames`); the render is refused before any file is written (`--no-story` renders without it). |
| `kind.unsupported` | cli | `marty-solid check` or `render` got a lesson document (`"kind": "lesson"`), a format the tool does not take. |
