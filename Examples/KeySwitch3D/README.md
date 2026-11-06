# Schematic key switch (3D inspection example)

An original, schematic key-switch assembly you can inspect on one MartyGraphics 3D board:
keycap, stem with an actuator leg, top and bottom housings, spring, and a normally open
contact pair, plus a reference line for the actuation level.

**This is a schematic teaching model, not physically validated mechanics.** Parts move to
positions computed from three parameters (kinematics only). Forces, spring rate, leaf
bending, timing, bounce, electrical behaviour and real product dimensions are not
modelled, and the proportions are not taken from any real switch.

The one geometric promise is drawing-level: parts that meet (the stem's leg and the moving
contact's tab, and the two contact tips) touch without passing through each other at every
slider position, measured on the 0.04 drawn tube radius. The leg runs 0.25 units in front of
the contact leaves and meets the moving leaf only at a short side tab: a slanted foot pushes
the tab closed and a straight flat then holds it there while the stem travels further.

From the repository root, with Swift 6 / macOS 14+:

```sh
swift test --package-path Examples/KeySwitch3D
swift run --package-path Examples/KeySwitch3D key-switch-3d --verify
swift run --package-path Examples/KeySwitch3D key-switch-3d --preview
```

`--verify` runs a scripted, windowless check through the real engine: press past the
actuation point, a refused out-of-range press, a slightly exploded view that keeps the
contacts closed (and says so), the full exploded view, selecting the stem from its leg,
and reset. It checks state, narration and validation only, not what the board looks like.

`--preview` opens a native window:

- **Orbit and zoom**: the engine's existing SceneKit camera control (`allowsCameraControl`).
  Its input handling is SceneKit's; this example adds none.
- **Select a part**: click it on the board or choose it in the parts list. The part's
  note appears in the panel. Its items glow and the rest are dimmed (the example opts in
  with `inspects3D([.selection, .emphasis, .dimming])`). The stem's two items (body and
  leg) light up together.
- **Press / Explode / Actuation** sliders send validated `params` patches in 0.05 steps.
  The exploded view lifts the stack apart. The narration and the panel are worded from the
  same state: a slightly exploded, fully pressed stem can still hold the contacts closed.
- **Reset** returns to rest parameters, clears the selection and restores the scene camera.

## What is example code and what is engine code

| Piece | Where | Reusable engine capability? |
| --- | --- | --- |
| Geometry, kinematics, narration, `key_switch` template | `KeySwitchModel.swift` | No. Example logic, registered as an opt-in pack by this example only. |
| Component list, item → component grouping, notes | `KeySwitchModel.swift` | No. The engine has no groups; the host maps items to components. |
| Session (patches, refused updates, reset) | `KeySwitchSession.swift` | No. It uses the public `MGSceneController` and `MGPatch`. |
| Tap → item id in 3D, emphasis glow and dimming in 3D | `MG3DView` + `MG3DInteraction` | Yes. Opt-in with `inspects3D(_:)`; it reuses the existing `selection`, `markers` and `emphasis` modifiers. Without it a 3D board ignores them, as before. |
| Keep orbit/zoom across updates; reset key | `preserves3DCamera(resetKey:)` | Yes. Opt-in; without it every 3D rebuild returns to the scene camera, as before. |
| Leg/tab contact geometry, tube clearance | `KeySwitchModel.swift` | No. Example geometry; the engine does no collision handling. |

## Known limits

- Parts are drawn with existing 3D kinds only: wireframe `path` boxes, a `path` helix and
  `path` contact leaves. There are no solid custom shapes, per-part materials, transparency,
  hierarchy/groups, rotations other than the body z-angle, or animated part transitions in 3D.
- Every parameter change rebuilds the whole 3D node tree. Its frame cost is not measured.
- Numbered marker badges are not drawn in 3D; the parts list carries the numbers.
- Board taps are not available to VoiceOver. The parts list and sliders are the accessible
  path; their VoiceOver behaviour has not been checked.
- Colour is not the only state cue (the panel and narration say open/closed), but colour
  choices have not been reviewed for colour-vision deficiency.
- On macOS, a click on the board selected a part, a drag orbited the camera while keeping
  the selection, and **Reset view and parts** restored the starting camera and cleared the
  selection. This was checked on screen with real mouse input on 2026-11-06. Slider dragging,
  keyboard use, iOS touch and VoiceOver were not checked. The unit tests call the selection
  code directly.
- The leg-in-front layout is a drawing choice that keeps the parts from crossing; it is not
  a claim about how any real switch is built. The tube clearance is checked on the example's
  own coordinates, not on SceneKit's rendered pixels.
