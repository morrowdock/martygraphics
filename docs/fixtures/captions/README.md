# Caption export golden files

The output of `marty-solid export-captions` (`MGCaptionExport`, see
[Captions and transcript export](../../EXPLAINER.md#captions-and-transcript-export)) at the defaults (1280x800, 30 fps)
for two shipped documents:

| Files | Input |
| --- | --- |
| `slider-crank.vtt`, `.srt`, `.txt` | [`slider-crank.json`](../../../Examples/Solid3D/Sources/MartySolid3D/Models/slider-crank.json) (an assembly: four steps, spins, long narration) |
| `gears-mixed.vtt`, `.srt`, `.txt` | [`gears-mixed.explainer.json`](../../../Examples/Explainers/gears-mixed.explainer.json) (an explainer: a board and a solid, filled placeholders) |

`CaptionExportTests` (library) and `CaptionExportCLITests` (`marty-solid`) compare their output byte for byte with
these files. To write them again after a deliberate change, run `CaptionExportTests` with `MG_WRITE_CAPTION_GOLDEN=1`
and review the diff.
