# Engine gaps found while authoring the drone and aviation explainers

The engine was frozen for this work (main `ca2218131e897f1138fa80c0cf23cf21cd23fa4d`): no engine source and no
vocabulary changed. This file lists what the author (a Claude agent, Claude Fable 5.2) could not show, with the
engine's exact refusal text where a probe document was run. The probe documents below are not explainers and are
not counted as explainer attempts.

## Topics

| Topic | Result | Reason |
| --- | --- | --- |
| Quadcopter steering | Authored | Poses and authored arrows carry the steering; the engine checks the spin directions and the weight direction. |
| Brushless outrunner motor | Authored | The engine solves the rotation and counts coils and magnets; the electromagnetics are words only. |
| Three-axis gimbal | Authored | One input drives all three body turns together; single axes are shown as checked poses. |
| Retractable landing gear, over-centre lock | Authored with poses | No linkage solver (gap 1); the engine checks each pose with two measured dimensions. |
| Payload position and centre of gravity | Authored | The engine computes the centre of the drawn shapes at each pose. A pose cannot slide the payload (gap 1), so the payload part turns by a small angle about a pivot far above the drone. |
| Helicopter swashplate | **Dropped** | Gaps 2, 3 and 4: the collective needs a part that slides in a pose or a second input, and the cyclic needs a tilting plate with ball links whose blade pitch changes during each rotor turn. A true model is not possible; a stand-in with the crank drives would show a motion that the engine did not solve as a swashplate. |
| Aircraft control surfaces | **Not authored** (time) | A parallelogram push-rod run is possible with `follow` drives, one axis for each document (gap 3). Not tried in this session. |

## Gaps with a probe document and the engine's exact answer

### 1. A step pose cannot slide a part

```json
{"v": 2, "kind": "assembly", "title": "Gap probe: a pose that slides a part", "units": "mm",
 "parts": [
  {"id": "mast", "shape": {"shaft": {"radius": 6, "length": 120}}},
  {"id": "swash", "parent": "mast", "at": [0, 0, 40], "shape": {"tube": {"inner": 7, "outer": 30, "length": 6}}}],
 "steps": [
  {"say": "Collective: the swashplate slides up the mast.", "pose": {"swash": {"at": [0, 0, 55]}}}]}
```

```text
Refused (step.pose.key), at swash: A `pose` entry is not an object of `with` and/or `rot`, gives a key its id does not take (an instance takes `with`, a part takes `rot`), or has a `rot` that is not [axisX, axisY, axisZ, degrees] with a non-zero axis and an angle in -360...360.
```

Effect: a pose can turn a part but not move it along a line. A collective slide, a shock strut that compresses and
an actuator rod that extends cannot be posed. (The landing gear's actuator is drawn as a rod inside a tube; each
is turned to point at the other, so the overlap changes without a slide.)

### 2. There is one input

```json
{"v": 2, "kind": "assembly", "title": "Gap probe: a second independent input", "units": "mm",
 "parts": [
  {"id": "rotor", "shape": {"shaft": {"radius": 6, "length": 120}}, "joint": {"revolute": [0, 0, 1]}, "drive": {"input": 1}},
  {"id": "swash", "at": [0, 0, 40], "shape": {"tube": {"inner": 7, "outer": 30, "length": 6}}, "joint": {"prismatic": [0, 0, 1]}, "drive": {"input2": 1}}],
 "steps": [{"say": "The rotor turns while the pilot raises the collective."}]}
```

```text
Refused (part.drive.unknown.input2), at swash: Unknown drive kind (input, follow, crankSlider, crankRod).
```

Effect: a rotor cannot spin while a control moves by itself. In the gimbal explainer the drone's pitch, roll and
yaw all follow the one input, so they always move together; the single axes are poses. Propeller speeds cannot
change from step to step, so "this pair speeds up" is shown with arrow lengths, not with motion.

### 3. There is no ball joint

```json
{"v": 2, "kind": "assembly", "title": "Gap probe: a ball joint for a tilting swashplate", "units": "mm",
 "parts": [
  {"id": "mast", "shape": {"shaft": {"radius": 6, "length": 120}}},
  {"id": "swash", "parent": "mast", "at": [0, 0, 40], "shape": {"tube": {"inner": 7, "outer": 30, "length": 6}}, "joint": {"spherical": [0, 0, 1]}}],
 "steps": [{"say": "Cyclic: the swashplate tilts on a ball."}]}
```

```text
Refused (part.joint.unknown.spherical), at swash: Unknown joint kind (revolute, prismatic).
```

### 4. Every part needs a shape

A part that is only a pivot frame is refused:

```text
Refused (part.missing.shape), at a: Required keys are missing from an object. `<object>` names the object (see `closedObjects`); `<keys>` lists the missing keys.
```

Effect: the gimbal's two drone-turn pivots (`pivotP`, `pivotR`) carry a small sphere that is hidden inside the
camera body. Their names in the model say what they are.

## Gaps seen in the explainer attempts (real refusals and warnings)

5. **No linkage solver.** The engine solves gear meshes and the in-line slider-crank only (docs/SOLID-3D.md,
   "Limits"). The landing gear's four-bar angles were computed outside the engine. The engine checks two unsigned
   pin-to-leg distances at each shown pose (`step.pose.fact` refused the deliberate wrong pose). These distances alone
   do not prove that the pin is in its hole; a mirror solution exists (gap 14). It cannot check the blend between two poses in `story.mp4`.
6. **A displayed fact cannot belong to a hidden part** (`step.hide.fact`, motor attempt 2). This is a correct
   refusal, not a defect: the caption gave the magnet count while the cutaway step hid seven magnets. The count
   moved to a step that hides none.
7. **A measured dimension cannot show a value that a pose changes.** A tilt angle is 0 at rest and 18 degrees in the
   pose, so it cannot be a `dim` fact in the posed step (the same `step.pose.fact` rule), and rule N1 forbids a typed
   number. The quadcopter's tilt angles therefore have no number.
8. **Camera cuts near turning parts** (3 cuts: quadcopter beats 4 and 5, gimbal beat 2). The story's move
   test grows each turning part's box by the jump between the last frame of the move and the beat's end pose. For
   a propeller that turns during the beat this jump is large, so a close-up camera lies inside the grown box and
   the beat cuts (`"path": "cut"`, `"pathReason": "blocked"`). A close-up of a part that turns in its own beat
   always cuts.
9. **Thin parts fail the subject floors** (`framing.subject.small.step.<n>`, quadcopter attempts 1 to 7). A
   propeller blade covers few pixels, so every step whose arrows rode on the propellers warned. The arrows now ride
   on the frame, and the warning is gone. Labelled small parts in an exploded view warned in the same way; that
   step became a close-up.
10. **The centre of mass counts every part**, also scenery. The quadcopter's pad marking is 0.4 mm thick for this
    reason. A way to leave a part out of the centre of mass does not exist. After the fact check (C9), both
    quadcopter scenes say that the weight arrow starts at the volume centre of all drawn parts, with the ground
    marking, and that this is not the aircraft's centre of gravity.
11. **Authored force arrows are not checked** (by design). The landing gear's unlock arrow pointed the wrong way
    until the author saw it in the render (attempt 7).
12. **A highlight is the only way to mark some copies of a `repeat`.** The three motor phases cannot have their
    own colours while the coils stay one counted `repeat`; an energised coil cannot light up in one step only
    (`emissive` is for the whole document).

13. **A placement tie is decided by rounding, and the debug and release builds decide it differently** (landing
    gear, attempts 8 to 10). In the report's legacy `placements` section (the default camera, not the stills),
    two arrow texts of step 3 took opposite candidates in the two builds of the same source: `aSqueezeA` candidate 2
    (debug) and 6 (release), `aKnee` candidate 0 (debug) and 4 (release). Opposite candidates have the same leader
    length, so their scores tie and the last bit of `cos` and `sin` decides. `stillPlacements`, the stills and
    the videos were the same in both builds. The golden test runs the debug build, so the release build's golden
    file failed for this document. Attempt 10 highlights the two brace links in step 3; the highlight term of the
    score then separates the candidates, and both builds give the same report. The engine's determinism promise is
    for one build; a tie-break that does not depend on rounding would make it hold across builds.
14. **A measured dimension has no sign, so two distances do not fix a pin** (landing gear, found by the Sol fact
    check on 2026-11-11). `dim.pinA` and `dim.pinB` are unsigned lengths from the brace pin to two points of the leg.
    At the rest pose a second (mirror) place of the pin keeps both lengths. The check proves the two distances, not
    that the pin is in its hole. A signed coordinate check would close this; it is engine work and the engine is
    frozen, so the captions now say only what was checked.

## Gaps taken from the documentation, not tried

* A turn arrow on a joint below turning joints with other axes is refused (`arrow.turn.steady.<id>`), so the
  gimbal's motors have no turn arrows.
* There is no arrow for a torque on a part that does not turn. The quadcopter's reaction torque is a label.
* A drive cannot swing back and forth by an authored curve; only the crank drives reverse, and the engine labels
  them as a solved crank. The gimbal's drone therefore turns one way in each beat.
