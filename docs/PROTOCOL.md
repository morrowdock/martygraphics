# Scene protocol v1

This is a serialization contract, not a model prompt. `MGParser` and `MGPatch`
are the authoritative validators. `MGGrammar.document()` exposes allowed/required
item keys, colors, limits, and the template registry directly from their tables;
it is a structural grammar inventory, not a complete JSON Schema validator.

A transport may wrap scenes as `{"type":"scene","scene":{...}}` and patches
as `{"type":"scenePatch","patch":{...}}`. Pass the inner object to the engine.

```json
{"v":1,"items":[{"id":"dot","k":"body","at":[3,4],"shape":"ball","size":1}]}
```

A scene requires `v: 1` and either a registered `template` with `params`, or an
`items` array. Optional fields include `title`, `dim` (`2d` / `3d`), `world`,
`camera`, and `steps`. Template scenes also support `hide` and `over`.
World coordinates point right/up, with the origin at bottom-left; 3D adds z
toward the viewer. The default world is 12 by 8.

Kinds: body, incline, line, vector, axes, plot, spring, pulley, rope, orbit,
text, highlight, bars, path, array, node, edge. The model types expose their
geometry. In 3D the supported subset is body, incline, line, vector, axes,
orbit, text, highlight, path.

The engine rejects unknown keys, broken references, invalid parameter ranges,
invalid text, duplicate identifiers, and unsupported kinds. Limits include
8 KiB canonical scene JSON, 4 KiB patches, 24 full-scene items, 10 template
extras, 40 resolved items, and 8 wire-authored steps (up to 48 template-built steps). Limits apply to canonical JSON; the
input decoder allows up to twice the scene byte limit before canonicalization.

```json
{"v":1,"rev":0,"ops":[{"op":"title","title":"Synthetic dot"}]}
```

Patch operations: params, add, remove, set, steps, step, camera, title, dim.
A patch revalidates the entire resulting scene. Supply the current `rev` and
use `requireRevision: true` when applying updates from untrusted transports;
stale revisions are rejected. A direct engine caller can omit the revision
when performing a trusted local edit. Failed patches preserve the old value.

`MGStreamParser` offers provisional previews while receiving scene JSON;
`finish()` performs strict final validation. `MGSceneController` restores the
previous scene if final validation fails.

Packs use `MGPack`, `MGTemplate`, `MGTemplateBuild`, and `MGFixtures.Demo`.
`MGPacks.validate` reports invalid identifiers, duplicate names, missing template
fixtures, invalid fixture scenes, and broken example references. `register` is
atomic and serializes concurrent registrations. Every template-built item,
world, title, step, and camera is revalidated with the wire rules. Optional
`MGFewShot` records are reference metadata; the built-in public pack provides
no model instructions or generation examples.

Highlight chains must terminate at a non-highlight item. Cycles, self-targets,
and missing targets are rejected, including after each cumulative step edit.
Layout also resolves chains iteratively with a visited set to protect callers
that construct items directly without parsing.

The built-in templates are `bst` and `two_pointers`. Mechanics drawing
primitives and standard math helpers remain available; mechanics walkthrough
templates are not included.
