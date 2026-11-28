# MartyGraphics visual language v2 phase plan

Phase 1 introduces the 2D board palettes, original Classic styling, bundled fonts, bounded transitions, an
out-of-band palette selector, and hosted review stills. The grammar gate is 562c1edca6aa489c at 4416 bytes.
The design package supplies six mock subjects, three of which are 2D. The review job captures eight fixed
views of those three subjects in both palettes. The ramp stills use the authored forces from the cookbook example.

## Phase 2 · ML boards

Migrate the full-frame and presenter layouts to the Studio and Paper tokens, keeping the ML Classic look
selectable. Use the shared fonts, scope chip and neutral text. Restyle the patch grid and attention board with
tile gaps and a weight-dependent scrim, link width and endpoint dots, direct labels, and the three largest
weights. Keep input images, scores, softmax, timing, and validation semantics.

Gates: ML and core unit tests, original weight and image fixtures, both palettes at 9:16 and 16:9, presenter and
transparent output review, and colour-blind and phone-scale review of the same frames.

## Phase 3 · 3D plates and annotated stills

Place the current 3D render on a dark Studio plate inside Paper. Use shared chrome, scope and hero readout,
part labels and cased leaders with checked anchors. Review the gearbox at the specified stage occupancy and
preserve the geometry, camera, physical claims and renderer checks.

Gates: Solid3D checks and manifest parity, representative Classic and Studio/Paper stills, anchor and occlusion
checks, and human review of composition and contrast on hosted macOS.

## Phase 4 · Export framing and captions

Set destination defaults to 1:1 for X, 16:9 for lessons and 9:16 for Shorts, preserving explicitly supplied
dimensions. Add the Shorts caption bar with an off switch, a step count, safe areas, and wrapping at the type
floor. Reuse the existing spoken caption export and verify WebVTT uses exact step boundaries. Include text
alternatives composed from title, checked scope, captions and displayed values.

Gates: preset and override tests, unchanged explicit layout and timing, frame and cue boundary checks,
caption-off renders, phone-size review in all three formats and checks for sound-off and reduced-motion use.

## Phase 5 · Shared frame and renderer parity

Finish the shared title, grid, caption and readout placement, line casing, focus dimming, direct status glyphs,
scaled typography and motion choreography from the design spec. Add the before-and-after component with a
shared camera and axis scale. Reflow portrait boards within the safe area and handle series beyond the seven
hues with grouped data or small multiples. Align the web renderer once its independent
release is integrated. Compare finished exports across backends and refresh the public showcase.

Gates: fixture and grammar parity, sampled frame comparisons, label collision and text-floor checks,
deuteranopia and protanopia comparisons, Reduce Motion playback, and approval of hosted stills and clips.
