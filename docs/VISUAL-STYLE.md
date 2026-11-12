# Visual style of the built-in renderer

Status: design, 2026-11-11. The defects it answers are in [VISUAL-AUDIT.md](VISUAL-AUDIT.md). Each part lands in its
own pull request with before and after images; the knobs named here are documented where they land
([SOLID-3D.md](SOLID-3D.md), [EXPLAINER.md](EXPLAINER.md)) and each has a default.

## Principles

1. **Pixels only.** The style never changes geometry, motion, solved values, checks, reason codes or any JSON output.
   What the picture shows is the checked model.
2. **The subject first.** Light, backdrop and type exist to make the mechanism and its motion easy to read.
3. **Honesty is part of the design.** Legends, tier marks and notes such as "not to scale" keep their place and
   contrast, and are drawn with the same care as the title.
4. **One look everywhere.** The live view, the stills and the videos use the same backdrop, light and type.
5. **Smooth on an iPad by default.** Costly effects sit behind a quality level.

## Two knobs

| Knob | Values | Default | What it sets |
| --- | --- | --- | --- |
| Look (`MGSolidLook`, `marty-solid render --look`) | `studio`, `paper`, `classic` | `studio` | Backdrop, exposure and tone, environment fill, shadow strength, ink and plate colours |
| Quality (`MGSolidQuality`) | `interactive`, `balanced`, `still` | `balanced` in the explainer view (until the levels are measured on an iPad), `still` in `marty-solid render` | Shadow map size and samples, occlusion, bloom, supersampling, jitter, depth of field |

`classic` is the renderer as it was, pixel for pixel in intent, and stays available.

A look is a renderer-only layer. `snapshot.json` keeps `MGStudioLighting.studio` and each part's
`MGMaterialParameters`, so a look scales the rig and maps colours inside the renderer and never edits those values.

## Palette

Neutrals carry a slight cool tint toward the brand navy (`#0A0F1F`), so the two looks and the 2D board belong together.
The Blender path uses a neutral studio bowl with AgX; these looks sit beside it without a colour clash.

| Token | `studio` (dark) | `paper` (light) | Use |
| --- | --- | --- | --- |
| Pool | `#454953` | `#EDEEF1` | Backdrop under the subject |
| Edge | `#0D0E12` | `#B8BDC4` | Backdrop far from the subject |
| Surface | `#0E1320` | `#FFFFFF` | Frame behind panes, bands |
| Plate | `#0A0F1F` at 86 % | `#FFFFFF` at 92 % | Label and legend plates |
| Ink | `#EEF2FF` | `#141A2B` | Text, leader lines |
| Subtle ink | `#9AA4C7` | `#5A6480` | Footer, secondary text |

Colour roles keep their hue and meaning (`warn`, `accent`, `good`, the part colours). On a surface, a role maps to a
calibrated colour of the same hue with a reflectance of at most about 0.8, so plastics read as moulded parts. On the
light look, role colours used as ink are darkened to keep 4.5:1.

## Materials

Metallic and roughness workflow, values in sRGB. The presets keep their names and their exported parameters; the
renderer adds surface detail that depends only on the part-local position, so it is stable under motion.

| Family | Presets | Metallic | Roughness | Detail |
| --- | --- | --- | --- | --- |
| Polished metal | `polishedSteel` | 1 | 0.12 to 0.16 | None; it lives on the environment |
| Brushed and turned metal | `brushedSteel`, `aluminum`, `titanium`, `brass`, `bronze`, `nickelAlloy` | 1 | 0.26 to 0.40 | Concentric turning marks per fragment (±0.035 roughness) |
| Dark metal | `darkSteel`, `blackOxide` | 0.85 to 1 | 0.38 to 0.45 | Fine grain |
| Anodised | `anodized(role)` | 0.75 | 0.30 | Clear layer 0.25 |
| Plastic | `plastic(role)` | 0 | 0.45 to 0.55 | Fine moulding grain, clear layer 0.15 |
| Rubber | `rubber` | 0 | 0.85 to 0.9 | Fine grain, no clear layer |
| Glass | `glass` | 0 | 0.03 | Strong Fresnel, clear specular layer, drawn after opaque parts |
| Carbon | `composite` | 0 | 0.40 | Twill weave under a clear layer 0.8 (still quality) |
| Ceramic | `ceramic` | 0 | 0.70 | None |

Ghosted parts are brighter at grazing angles and nearly clear face-on. A highlight keeps the material's shading: the
others dim mildly, and the highlighted parts gain a rim, not a flat glow. Section caps keep the part's hue, a step
lighter and matte, so a cut reads as a cut.

## Light

- **Environment.** The procedural equirectangular studio stays (no shipped image, nothing to license): a vertical
  gradient plus soft boxes. A look raises the gradient so that metals reflect a room, with floor bounce for the
  undersides, and lowers the soft boxes so highlights are broad and soft.
- **Key, fill, rim.** The rig's three directional lights keep their directions (key from the upper front left, cool
  fill from the right, rim from behind). A look scales them: a little less key, a little more fill.
- **Shadows.** A soft key shadow on a shadow catcher plus a contact shadow under the subject, both visible on the lit
  floor. Strength per look (`studio` 0.50 and 0.55, `paper` 0.30 and 0.30).
- **Ambient occlusion.** Screen space, intensity 0.45 to 0.6, radius tied to the camera distance.
- **Tone.** HDR rendering in linear light, then SceneKit's tone mapping with a white point above 1 (1.4 to 1.5) so
  whites roll off, a small exposure offset, contrast +0.10 and saturation 1.04. The new looks use no bloom. Output is sRGB; videos are tagged BT.709.
- **Anti-aliasing.** 4× multisampling everywhere; 2× supersampling at `still`; jitter on a resting live view.
- **Depth of field.** Stills only, at `still`, and only on a hero shot with no labels. Never in a step still or a
  video: every labelled part stays sharp.

## Backdrop

A studio sweep: a pool of light on the floor under the subject that falls off to the edge colour, with a vignette on
the backdrop only. The pool follows the ground point under the subject and widens with the subject's size on screen,
and it flattens as the camera lowers, like a lit floor. It is computed per pixel on the CPU with a fixed half-level
dither, so it never bands and is byte-identical in every run. The live view uses the same function.

## Quality levels

| | `interactive` | `balanced` | `still` |
| --- | --- | --- | --- |
| Shadow map, samples | 2048, 8 | 4096, 16 | 4096, 24 |
| Ambient occlusion | off | on | on |
| Bloom | off | on | on |
| Supersampling | 1× | 1× | 2× |
| Jitter at rest | on | on | not needed |
| Surface detail (weave, grain) | off | on | on |
| Depth of field | never | never | hero only |

## Type, labels and callouts

All sizes derive from one font size `f` (`MGAnnotationLayout.fontSize`, 11 to 20 px by frame height). Every drawn
metric is a multiple of `f`, so a later label scale of 1 to 2× scales plates, strokes and leaders together.

- **Typeface.** The system UI font (SF Pro on Apple platforms): no shipped font. Tabular numerals for values.
- **Scale.** Title `1.75 f` semibold; caption `1.25 f` regular, at most about 70 characters a line; label `f` medium;
  legend and footer `0.8 f` medium.
- **Plates.** Inside the layout's box (the box is engine data and does not move): corner radius `0.45 f`, plate fill
  from the palette, a hairline edge of `0.06 f`, and the tier mark as a rounded bar `0.2 f` wide on the leading edge
  (solved = good, built = warn, described = muted).
- **Leaders.** A light line `0.09 f` wide over a dark casing `0.22 f` wide, so it reads over white and black parts;
  dashed when the anchor is hidden. The anchor is a dot of radius `0.3 f` with a casing ring.
- **Callouts.** A numbered disc of radius `0.7 f` with the tier colour as its ring.
- **Legend and notes.** One group in the legend corner: tier dots with their counts, then the notes ("Arrow lengths
  are not to scale", "author's arrow") at the same size and full ink. They are never smaller than `0.8 f`.
- **Bands.** The title and caption keep their bands and safe areas. Each band is a scrim from the surface colour, not
  a black bar, strong enough that thin text keeps 4.5:1 over a white or lit render (the existing contrast tests stay).
  The step number is a small badge before the caption.

## Board and table

- The board keeps its dark surface in `studio` and gains a light surface in `paper`.
- Strokes are crisp. Glow is kept for emphasis only (a highlighted row, a pulsing target).
- Type scales with the pane, with a floor of 12 px at 1280 × 800. Table cells use tabular numerals and a row height
  of `2.2 ×` the text size; the header is semibold on a tinted row.
- Panes share one surface colour, a corner radius of 14 px at 1280 wide, a hairline edge and 12 px spacing.

## Motion

- Camera moves keep the story plan's timing and easing. Nothing in the plan or the manifest changes.
- Captions, labels and highlight dimming fade over about 0.2 s at the start of a hold instead of popping.
- A move the plan records as a cut dips through the backdrop over a few frames.
- In the live view, a beat change eases the camera over the same 0.6 s as the story video.
