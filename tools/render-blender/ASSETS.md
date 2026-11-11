# Assets and tools used by the Blender render path

Every downloaded asset must be public domain or CC0. `setup.sh` downloads the
files listed in [assets.lock.json](assets.lock.json) into the asset cache
(`~/.cache/martygraphics-render/assets`, or `$MG_RENDER_ASSETS`) and refuses a
SHA-256 mismatch. No asset binary is committed to this repository.

## Assets (appear in rendered images)

| Asset | Use | Source | Author | Licence | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `studio_small_09_2k.hdr` (2K Radiance HDR, 6 312 947 bytes) | World lighting and reflections | <https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/studio_small_09_2k.hdr> (page <https://polyhaven.com/a/studio_small_09>) | Sergej Majboroda | CC0 1.0 (<https://polyhaven.com/license>) | `36724313c0fc66dab126ff90f081b85a0b1ef47be65eda1417bd20b033f0573f` |

Checked 2026-11-11: the downloaded file matched the MD5 that the Poly Haven API
publishes (`b056fea247bc84b81d2e0987d44c87d8`); the SHA-256 above was computed
from that file and is now the pin.

All other look-dev elements (backdrop, materials, carbon weave, lights,
camera rig) are procedural and made by `mgrender/lookdev.py` at render time.
The burned-in provenance caption uses the monospace font bundled with Blender
(DejaVu Sans Mono, Bitstream Vera licence, a permissive font licence).

## Tools (installed in user space, not redistributed)

| Tool | Version | Source | Licence | SHA-256 | Verification |
| --- | --- | --- | --- | --- | --- |
| Blender (Linux x64) | 5.2.4 LTS (build `cd5dc428cce1`, supported to 2028-07) | `blender-5.2.4-linux-x64.tar.xz`, Blender release directory `release/Blender5.2/`. Fetched from the official mirror <https://ftp.nluug.nl/pub/graphics/blender/release/Blender5.2/> | GPL-2.0-or-later | `2fd14c50987426897ba60237ee996edf2b4151f4b1a72a460ca20be58c1d2d86` | Matches the published `blender-5.2.4.sha256` from three official mirrors (ftp.nluug.nl, mirrors.ocf.berkeley.edu, mirror.clarkson.edu). On 2026-11-11 download.blender.org answered HTTP 403 (Cloudflare challenge) to non-browser clients, so `setup.sh` needs at least two agreeing mirrors. |

Blender's bundled FFmpeg writes the H.264 MP4. No system FFmpeg is used.
