# Solid 3D refusal reasons

Every stable reason the Solid 3D formats give, in one table. A reason is one token
(ASCII letters, digits, `_`, `.` and `,`) with one meaning; hosts and model harnesses can
branch on it. The machine-readable catalog is the same table:

* `marty-solid reasons` prints it as JSON (`{"catalog": "martygraphics.solid.reasons/1", "placeholder", "closedObjects", "formats", "reasons": [{"pattern", "meaning", "formats", "kind", "strict"}]}`).
* In Swift: `MGSolidReasons.catalog` (typed entries), `MGSolidReasons.json`, and
  `MGSolidReasons.lookup(_:)`, which returns the entry for a concrete reason such as
  `part.gear.bore` (the matching pattern with the most fixed characters).

The table in this page is generated from `Sources/MartyGraphics/Solid/MGSolidReasons.swift`;
a test fails when a pattern is missing here.

## Patterns

`<…>` marks one variable part of a reason:

| Placeholder | Holds |
| --- | --- |
| `<n>` | A 1-based number (a step). |
| `<kind>`, `<field>`, `<key>`, `<op>`, `<modifier>` | One name without dots (ASCII letters, digits, `_`): a shape kind, a field, a step list key, an expression operator, a placeholder modifier. |
| `<id>`, `<name>` | An author name passed through `MGSolidParser.token`: ASCII letters, digits, `_` and `.` (anything else becomes `_`), at most 32 characters. Component part ids keep their dots (`stage1.pinion`). |
| `<object>` | One of the closed objects listed below. |
| `<keys>` | The missing or unknown keys as tokens, sorted and joined with commas (`assembly.missing.kind,parts,v`). |

Closed objects (`<object>.missing.<keys>`, `<object>.unknown.<keys>`): `assembly`,
`params`, `part`, `part.<kind>` (a shape body), `part.emissive`, `part.expect`,
`part.repeat`, `part.drive.follow`, `part.drive.<kind>` (`crankSlider`, `crankRod`),
`constraint.gearMesh`, `step`, `step.check`, `step.section`, `component`,
`component.param.<name>`, `component.use`.

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

Warnings are not refusals in the plain API: they are listed in the check report's
`warnings`. The strict profile (`MGSolidProfile.strict`, `marty-solid check --strict`)
refuses the two marked "strict refuses".

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

`SolidReasonCatalogTests` scans the Solid sources and the `marty-solid` tool. Every
reason-shaped string literal (a dotted token, with `\(…)` interpolations as wildcards),
every single-word reason passed to `MGSolidIssue`, and every reason that the key and
frame helpers compose (`closed` gives `.missing.` and `.unknown.`, `transform` gives
`.at` and `.rot`) must match a pattern here. Every pattern must match something in
the sources; a literal made only of interpolations (`\(a).\(b)`) matches broadly, so this
direction finds only entries that nothing could produce. A short list in the test names
the dotted literals that are not reasons (output file names, fact-name and material
prefixes). Scene, patch and lesson reasons of the 2D protocol are not in this catalog;
see [PROTOCOL.md](PROTOCOL.md) and [LESSONS.md](LESSONS.md).

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
| `assembly.budget` | assembly | Part meshes plus step cuts would exceed 1,500,000 triangles or 1,000,000 vertices (counted before any mesh is built). |
| `assembly.invalid` | assembly | The compiled assembly failed its structural validation (a parent, drive source or explode window the earlier checks did not refuse). |
| `<object>.missing.<keys>` | assembly, component | Required keys are missing from an object. `<object>` names the object (see `closedObjects`); `<keys>` lists the missing keys. |
| `<object>.unknown.<keys>` | assembly, component | An object has keys it does not allow (in a v1 document this includes every v2 key). `<object>` names the object (see `closedObjects`); `<keys>` lists the keys. |
| `part.at` | assembly | A part's `at` is not three coordinates in -4000...4000 mm. |
| `part.rot` | assembly | A part's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis (each value in -1000...1000) and an angle in -360...360. |
| `part.<kind>.at` | assembly | A shape's `at` is not three coordinates in -4000...4000 mm. |
| `part.<kind>.rot` | assembly | A shape's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360. |
| `component.use.at` | assembly, component | A `use` entry's `at` is not three coordinates in -4000...4000 mm. |
| `component.use.rot` | assembly, component | A `use` entry's `rot` is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360. |
| `tier.key` | assembly | A v2 document has a key named `tier` somewhere (tiers are computed by the engine, never authored). |

### Parameters

| Reason | Formats | Meaning |
| --- | --- | --- |
| `params` | assembly | `params` is not an object. |
| `params.input` | assembly | `params.input` is not a number in -1e6...1e6. |
| `params.explode` | assembly | `params.explode` is not a number in 0...1. |

### Parts

| Reason | Formats | Meaning |
| --- | --- | --- |
| `parts.count` | assembly, component | `parts` is not an array of 1–48 entries, or component expansion makes more than 48 wire parts. |
| `parts.resolved` | assembly | More than 96 parts after `repeat` expansion. |
| `id.duplicate.<id>` | assembly, component | Two parts, `repeat` copies, component instances or anchors share an id (they share one namespace). |
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
| `part.expect.<key>` | assembly | `expect.axisWorld` or `expect.upWorld` is not a non-zero direction of three coordinates (v2). |
| `part.repeat` | assembly | `repeat` is not an object. |
| `part.repeat.count` | assembly | `repeat.count` is not a whole number in 2...12. |
| `part.repeat.axis` | assembly | `repeat.axis` is not a non-zero direction of three coordinates. |
| `part.repeat.angle` | assembly | `repeat.angle` is not in -360...360 degrees. |

### Shapes

| Reason | Formats | Meaning |
| --- | --- | --- |
| `part.<kind>` | assembly | A shape's body is not an object (`<kind>` is the shape kind). |
| `part.<kind>.<field>` | assembly | A shape field is missing, not a number, out of its range, or not a whole number where one is needed (teeth, arms, counts), or a size derived from it fails (a ring gear's teeth: tip radius not above base radius; a box `size`). |
| `part.<kind>.chamfer` | assembly | The chamfer is too large for the shape (for example half the width or more), or the chamfered cap outlines would cross. |
| `part.<kind>.tip` | assembly | A gear or ring gear tooth has no real tip land (too few teeth for the pressure angle and backlash). |
| `part.<kind>.profile` | assembly | The sampled tooth outline of a gear or ring gear crosses itself, or a ring's tooth spaces close at the root. |
| `part.<kind>.outer` | assembly | A ring gear's `outer` radius is less than one module beyond its root circle, or a tube's `outer` is not larger than its `inner`. |
| `part.gear.bore` | assembly | The bore reaches the tooth root (it must stay half a module inside the root circle). |
| `part.gear.keyway` | assembly | `keyway` is not [width, depth] in 0.1...1000, has no bore, is not narrower than the bore, or reaches the root. |
| `part.<kind>.holes` | assembly | Holes are not a list of valid entries: a plate takes at most 32 [x, y, radius]; an extruded profile at most 16 simple loops inside its outline. |
| `part.plate.holes.outside` | assembly | A plate hole (grown by the chamfers) leaves less than 0.5 mm of rim. |
| `part.<kind>.holes.overlap` | assembly | Two plate holes are closer than 0.5 mm (after chamfers), or two profile holes cross or nest. |
| `part.carrier.armWidth` | assembly | Carrier arms are wider than twice the boss radius, or the hub reaches beyond radius + boss. |
| `part.<kind>.points` | assembly | Profile points are not 3–256 [x, y] pairs (2–256 for a revolved profile), enclose no area, or cross themselves. |
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
| `part.drive.<kind>` | assembly | A `crankSlider` or `crankRod` body is not an object. |
| `part.drive.<kind>.crank` | assembly | A crank drive's `crank` is not a string, or it names the part itself. |
| `part.drive.<kind>.radius` | assembly | A crank drive's `radius` is not a length in 0.05...4000 mm. |
| `part.drive.<kind>.rod` | assembly | A crank drive's `rod` is not a length in 0.05...4000 mm, or it is not longer than the crank radius. |
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
| `step.<key>` | assembly, component | A step id list (`focus`, `highlight`, `ghost`) is not an array of at most 16 strings. |
| `step.camera` | assembly | `camera` is not a camera preset name. |
| `step.explode` | assembly | `explode` is not a number in 0...1. |
| `step.orbit` | assembly | `orbit` is not in -360...360 degrees. |
| `step.spin` | assembly | `spin` is not in -20...20 input turns. |
| `step.unchecked` | assembly | `unchecked` is not valid text (not empty after trimming, no `<`, `>`, `://` or control characters) of at most 60 characters (v2). |
| `step.check` | assembly | `check` is not an array of 1–8 claim checks (v2). |
| `step.ghost` | assembly | `ghost` is not a non-empty array (v2). |
| `step.section` | assembly | `section` is not an object (v2). |
| `step.section.normal` | assembly | `section.normal` is not a non-zero direction of three coordinates. |
| `step.section.offset` | assembly | `section.offset` is not in -4000...4000 mm. |
| `step.section.parts` | assembly | `section.parts` is not 1–16 part id strings. |

### Claim checks and text

| Reason | Formats | Meaning |
| --- | --- | --- |
| `check.object` | assembly | A claim check is not an object. |
| `check.value` | assembly | A claim check's `value` is not a fact name. |
| `check.comparison` | assembly | A claim check does not have exactly one of `eq`, `lt`, `gt`. |
| `check.eq` | assembly | The `eq` target is not a number in -1e6...1e6. |
| `check.lt` | assembly | The `lt` target is not a number in -1e6...1e6. |
| `check.gt` | assembly | The `gt` target is not a number in -1e6...1e6. |
| `check.tol` | assembly | `tol` is given without `eq`, or it is not in 0...1e6. |
| `check.fact.<name>` | assembly | A claim check names a fact that does not exist. |
| `check.failed.<name>` | assembly | A claim check is false for the engine's value. |
| `text.brace` | assembly | A `{` or `}` in the title or a caption is unbalanced or nested. |
| `text.placeholder` | assembly | A placeholder is malformed: no valid fact name, too many modifiers, too long, or a modifier with a dot. |
| `text.placeholder.<name>` | assembly | A placeholder names no fact. |
| `text.modifier.<modifier>` | assembly | Unknown placeholder modifier (abs, inv, pct, deg, frac). |
| `text.modifier.<modifier>.<name>` | assembly | A modifier cannot apply to this fact: a value with a unit, `pct` or `deg` on a fact that is not a turn rate, a modifier after a terminal one, `inv` of 0, or no exact fraction. |
| `text.range.<name>` | assembly | A placeholder value overflows or underflows, or would print as 0 although it is not 0. |
| `text.rounding.<name>` | assembly | A placeholder would show a non-zero value as "0"; use `frac` or `inv`. |
| `text.number.step.<n>` | assembly | A v2 caption has a number character outside a placeholder and the step is not marked `unchecked` (rule N1). |
| `text.sign.<name>` | assembly | `abs` hides a sign that no strict-inequality check in the same step proves (the title can never use `abs`). |
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
| `component.param.<name>` | component | A parameter is not an object with numbers min ≤ default ≤ max in ±1e6, a boolean `integer` (whole bounds and default when true) and an `about` of valid text. |
| `component.parts.count` | component | `parts` is not an array of 1–24 entries. |
| `component.part` | component | A part entry is not an object with a string id (after parameters are substituted). |
| `component.use` | component | A nested `use` is not a string. |
| `component.use.parent` | component | A `use` entry's `parent` is not a string. |
| `component.cycle.<id>` | component | A component uses itself, directly or through other components. |
| `component.unknown.<id>` | assembly, component | `use` names a component that is not in the library. |
| `component.depth` | assembly, component | `use` nests more than 3 levels deep. |
| `component.constraints` | component | `constraints` is not an array of at most 32 entries. |
| `component.anchors` | component | `anchors` is not an object of at most 8 anchors. |
| `component.anchor.<name>` | component | An anchor name is not an identifier or is taken, or its target is not a part, copy or nested anchor of the component. |
| `component.checks` | component | `checks` is not an object of at most 8 checks. |
| `component.check.name.<name>` | component | A check name is not an identifier. |
| `component.check` | component | A check is not `{"lt": [a, b]}`, `{"le": [a, b]}` or `{"int": a}`. |
| `component.check.<name>` | assembly, component | A component check is false for the parameters of an instance. |
| `component.expr` | component | An expression has an unknown operator or is not a number or an expression. |
| `component.expr.<op>` | component | An expression operator has the wrong number of operands (`<op>` names it). |
| `component.expr.depth` | component | An expression nests deeper than 8 levels. |
| `component.expr.size` | component | An instance evaluates more than 4,096 expression nodes. |
| `component.expr.param` | component | `param` does not take a string. |
| `component.expr.param.<name>` | component | `param` names no parameter. |
| `component.expr.div` | component | Division by zero. |
| `component.expr.range` | component | An expression result is not finite or exceeds ±1e6. |
| `component.param.unknown.<name>` | assembly, component | `with` names no parameter of the component. |
| `component.param.value.<name>` | assembly, component | A `with` value is not a finite number. |
| `component.param.range.<name>` | assembly, component | A `with` value is outside the parameter's min...max. |
| `component.param.integer.<name>` | assembly, component | A `with` value is not whole for an integer parameter. |
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

### Tool

| Reason | Formats | Meaning |
| --- | --- | --- |
| `report.encoding` | cli | The report could not be encoded as JSON (never expected: reports hold only finite numbers and shallow nesting). |
