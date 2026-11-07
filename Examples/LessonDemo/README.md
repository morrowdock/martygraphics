# Rotation lesson (beat-by-beat lesson example)

A short lesson on the public MartyGraphics lesson API: triangle ABC turns about the origin O. Five beats, one angle
slider, and coordinate labels that the engine computes from the rotated vertices. The lesson is synthetic example
content. The same JSON is in [`docs/fixtures/v1`](../../docs/fixtures/v1/rotation.lesson.json); a test keeps the copies equal.

| Beat | Line (filled by the engine) | Board |
| --- | --- | --- |
| 1 | This is triangle ABC. Each label shows a corner's coordinates. | `hiA` highlight added |
| 2 | Now we turn the triangle about the origin O by 90°. | angle 0 → 90°, 18 engine keyframes |
| 3 | A moved from (2, 1) to (-1, 2). Its distance to O is still 2.24. | three checks pass first |
| 4 | Your turn. Drag the slider. The engine moves the triangle and updates every label. | `angle` slider bound |
| 5 | At 180° every coordinate changes sign. A is now at (-2, -1). | angle → 180° from the learner's value; two checks |

From the repository root, with Swift 6 / macOS 14+:

```sh
swift test --package-path Examples/LessonDemo
swift run --package-path Examples/LessonDemo lesson-demo --verify
swift run -c release --package-path Examples/LessonDemo lesson-demo --timing
swift run --package-path Examples/LessonDemo lesson-demo --preview
swift run --package-path Examples/LessonDemo lesson-demo --render /tmp/lesson-beats
swift run -c release --package-path Examples/LessonDemo lesson-demo --capture /tmp/lesson-capture 1024x640
```

- `--verify` runs a scripted, windowless check through the real engine: every beat's line and labels, the slider at
  every 5° against a reference rotation computed in the example, slider and script giving the same state, refused values
  and commands keeping the state, a snapshot round trip, and the streamed lesson showing the figure after its second
  statement. It checks state, narration and validation only, not what the board looks like.
- `--timing` prints the core timing receipts on this machine (see [docs/LESSONS.md](../../docs/LESSONS.md#measured-timing-this-mac-only)).
- `--preview` opens a window. **Play lesson** loads the document; **Stream it** feeds the statements one at a time,
  120 ms apart, as a model reply would arrive. The pause, next-beat and show-all buttons are the lesson view's own.
- `--render` writes PNGs of the live view at each beat (1366 × 1024 and 1024 × 768) from an offscreen window.
- `--capture <new directory> [WIDTHxHEIGHT]` (default 1366x1024) records one timed run for a GIF. It plans the run
  headless on the demo's default pacing (`.estimate(wordsPerSecond: 2.5)`) on an injected clock: each beat's state when
  it is presented, every frame of each `animate` segment (the start scene, then engine keyframes at most 5° apart) at
  the time the view reaches it,
  and a scripted learner who moves the slider during beat 4 from 85° to 45° in 5° steps, 0.1 s apart, through the
  controller's `control` (the call the slider makes). The live demo view in an offscreen window then shows each
  planned frame and is recorded after it settles. It writes `frames/*.png`, `frames.json` (planned time, beat, kind,
  angle, caption, labels) and `loop.gif` (640 px wide; each frame lasts until the next planned time; the last frame
  is held 2 s after `lessonComplete`). The live view also blends between neighbouring keyframes and draws new items
  on over 0.55 s; the capture shows only the settled frames at the planned times. Code: `LessonDemoKit/Capture.swift`.

On iPadOS, embed `LessonDemoKit.LessonDemoView` (or the engine's `MartyGraphicsLessonView`) in an app. The example's
tests run on an iPad simulator:

```sh
cd Examples/LessonDemo
xcodebuild test -scheme LessonDemo-Package -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## What is example code and what is engine code

| Piece | Where | Engine? |
| --- | --- | --- |
| Lesson document, verify, timing, capture plan and GIF writer, demo buttons, state fingerprint | `LessonDemoKit` | No. Example code. |
| Lesson parse, statement stream, commands, checks, pacing, events, snapshot | `MGLesson*.swift` | Yes, Foundation only. |
| `rotate2d` template and its maths | `MGGeometryPack.swift` | Yes, opt-in pack. |
| Board, caption, slider, play bar, timing marks | `MartyGraphicsLessonView.swift` | Yes, SwiftUI. |

## Known limits

- No XCUITest UI test: the package has no iOS app target. The simulator tests render the view offscreen and call the
  controller directly; they do not send real touches. A UI-test plan is in the proposal's group UI and stays pending.
- Timing numbers are from an Apple M1 Mac. No iPad device numbers.
- Offscreen windows have no display link, so `--render` waits for each transition to settle and captures the settled
  frame. `--capture` shows the in-between frames by putting each engine keyframe scene on the board itself.
- VoiceOver, Dynamic Type and Reduce Motion were not checked by hand.
