#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# selftest.sh: end-to-end check that needs no MartyGraphics export.
#   1. builds a 24/12-tooth gear pair (2:1) in Blender and exports .glb + manifest
#   2. checks the 2:1 ratio and the frame grid from the .glb alone (pure Python)
#   3. checks that tampered exports are refused (SHA-256, fps, frame count)
#   4. renders the full pipeline in preview mode and reports time per frame
# Usage: tools/render-blender/selftest.sh [work-dir]   (default: a new temporary directory)
set -euo pipefail

# Exit codes: 127 = no Blender executable, 3 = Blender is not the pinned version, 1 = any other failure.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The documented pin (ASSETS.md, setup.sh). A pass attests to this version, so BLENDER and BLENDER_VERSION only say
# where to find it: `blender --version` must report it either way.
PINNED_BLENDER_VERSION="5.2.4"
BLENDER="${BLENDER:-$HOME/opt/blender-${BLENDER_VERSION:-$PINNED_BLENDER_VERSION}/blender}"
say() { printf 'selftest: %s\n' "$*"; }
die() { printf 'selftest: FAIL: %s\n' "$1" >&2; exit "${2:-1}"; }
[ -x "$BLENDER" ] || die "Blender not found at $BLENDER (run setup.sh)" 127
# Only the release itself: the first line of `blender --version` is exactly "Blender 5.2.4" or "Blender 5.2.4 LTS".
VERSION_STATUS=0
VERSION_TEXT="$("$BLENDER" --version 2>/dev/null)" || VERSION_STATUS=$?
[ "$VERSION_STATUS" -eq 0 ] \
  || die "\`$BLENDER --version\` exited $VERSION_STATUS, so it is not the pinned $PINNED_BLENDER_VERSION" 3
FOUND="${VERSION_TEXT%%$'\n'*}"
case "$FOUND" in
  "Blender $PINNED_BLENDER_VERSION" | "Blender $PINNED_BLENDER_VERSION LTS") ;;
  *) die "Blender at $BLENDER reports \"${FOUND:-nothing}\", not the pinned $PINNED_BLENDER_VERSION release" 3 ;;
esac
say "Blender $PINNED_BLENDER_VERSION (the pinned version) at $BLENDER"
WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/mg-render-selftest.XXXXXX")}"
EXPORT="$WORK/export"; OUT="$WORK/render-preview"
mkdir -p "$WORK"

# Optional busy guard (off unless BUSY_LOCK_PATH, BUSY_PROCESS_PATTERN or BUSY_COMMAND is set; see README).
(cd "$HERE" && python3 -E -s -m mgrender.busyguard) || die "host busy (busy guard) or bad busy-guard setting; try again later"

say "1. build and export the test mechanism"
nice -n 10 "$BLENDER" -b --factory-startup -P "$HERE/selftest_scene.py" -- "$EXPORT" >"$WORK/export.log" 2>&1 \
  || { tail -20 "$WORK/export.log"; die "export failed"; }
MANIFEST="$EXPORT/selftest-gears.manifest.json"

say "2. check the export with the pure-Python verifier and the 2:1 ratio"
(cd "$HERE" && python3 -E -s -m mgrender.manifest "$MANIFEST") || die "verifier refused the self-test export"
(cd "$HERE" && python3 -E -s - "$MANIFEST" <<'PY') || die "2:1 ratio check failed"
import math, sys
from mgrender import manifest as mf
c = mf.verify(sys.argv[1])
g, anim, fps = c["gltf"], c["animation"], c["fps"]
idx = {n["name"]: i for i, n in enumerate(g["nodes"])}
def angle(node, f):
    x, y, z, w = anim.sample(idx[node], "rotation", f / fps)
    return 2 * math.atan2(y, w)          # glTF Y up: the gear axis is +Y
a0, b0 = angle("gear_drive", 0), angle("pinion_driven", 0)
worst = 0.0
for f in range(c["frame_count"]):
    da = angle("gear_drive", f) - a0
    db = angle("pinion_driven", f) - b0
    db = (db + math.pi) % (2 * math.pi) - math.pi if abs(da) < 1e-9 else db
    worst = max(worst, abs(db + 2 * da) if abs(da) < math.pi / 2 else abs((db + 2 * da + math.pi) % (2 * math.pi) - math.pi))
print(f"ratio check: pinion = -2 x gear, max error {math.degrees(worst):.2e} deg over {c['frame_count']} frames")
sys.exit(0 if worst < 1e-4 else 1)
PY

say "3. tampered exports must be refused"
T="$WORK/tamper"; mkdir "$T" || die "use a fresh self-test directory"
tamper() { # name, python edit of the manifest dict m / glb bytes
  local d="$T/$1"; mkdir -p "$d"; cp "$EXPORT"/* "$d/"
  python3 -I - "$d/selftest-gears.manifest.json" "$2" <<'PY'
import json, sys
p, edit = sys.argv[1], sys.argv[2]
m = json.load(open(p))
if edit == "sha":
    g = p.replace(".manifest.json", ".glb"); b = bytearray(open(g, "rb").read()); b[-1] ^= 1; open(g, "wb").write(b)
elif edit == "fps":
    m["fps"] = 30
elif edit == "frames":
    m["frameCount"] += 1
json.dump(m, open(p, "w"))
PY
  if nice -n 10 "$BLENDER" -b --factory-startup -P "$HERE/render.py" -- "$d/selftest-gears.manifest.json" "$d/out" \
      >"$d/log" 2>&1; then die "render accepted a tampered export ($1)"; fi
  grep -q "REFUSED (1)" "$d/log" || { tail -5 "$d/log"; die "tampered export ($1) failed for another reason"; }
  [ ! -e "$d/out/frames/frame_0000.png" ] || die "tampered export ($1) produced frames"
  say "   refused as expected: $1 ($(grep -o 'export refused: .*' "$d/log" | cut -c1-90))"
}
tamper sha sha; tamper fps fps; tamper frames frames

say "4. full pipeline, preview preset"
(cd "$HERE" && python3 -E -s -m mgrender.busyguard) || die "host became busy (busy guard); stopping before the render"
ENCODE=()
if [[ -n "${FFMPEG:-}" ]]; then
  ENCODE=(--nvenc --ffmpeg "$FFMPEG" --no-burn-in)
fi
nice -n 10 "$BLENDER" -b --factory-startup -P "$HERE/render.py" -- "$MANIFEST" "$OUT" --preset preview --camera auto "${ENCODE[@]}" \
  2>&1 | tee "$WORK/render.log" | grep -E '^render: (PASS|motion|look-dev|Cycles|DONE|poster|frames|time)|REFUSED|FAILED' || true
grep -q '^MG_RENDER_REPORT ' "$WORK/render.log" || die "render did not finish (see $WORK/render.log)"
REPORT="$(sed -n 's/^MG_RENDER_REPORT //p' "$WORK/render.log")"
python3 -I - "$REPORT" <<'PY' || die "report check failed"
import json, sys
r = json.load(open(sys.argv[1]))
t = r["timing_s"]
print(f"selftest: report {sys.argv[1]}")
print(f"selftest: device {r['device']}; {r['resolution'][0]}x{r['resolution'][1]}, {r['samples_max']} max samples")
print(f"selftest: first frame {t['first_frame']} s, mean after first {t['mean_after_first']} s/frame, "
      f"encode {t['encode']} s, total {t['total']} s")
print(f"selftest: motion max error {r['motion_check']['max_error']:.3g} (tol {r['motion_check']['tolerance']:.3g}), "
      f"look-dev drift {r['motion_check']['lookdev_drift']}")
mats = {k: v[0] for k, v in r["materials"].items()}
want = {"base_housing": ["carbon_fibre", "label contains 'carbon'"],       # label beats the node name rules
        "gear_drive": ["brushed_metal", "gltfMaterial contains 'steel'"],  # material name beats the label
        "pinion_driven": ["anodised_aluminium", "manifest"],
        "rubber_foot_0": ["rubber", "gltfMaterial contains 'rubber'"]}   # material: null = no override
bad = {k: (mats.get(k), v) for k, v in want.items() if mats.get(k) != v}
print(f"selftest: material presets (manifest, gltfMaterial, label): {'OK' if not bad else 'WRONG ' + str(bad)}")
sys.exit(1 if bad else 0)
PY
say "5. portrait, turntable and transparent film"
ALPHA="$WORK/render-alpha"
nice -n 10 "$BLENDER" -b --factory-startup -P "$HERE/render.py" -- "$MANIFEST" "$ALPHA" \
  --resolution 9:16 --turntable --alpha --ffmpeg "${FFMPEG:-ffmpeg}" --frames 0-1 --samples 4 --no-motion-blur \
  >"$WORK/alpha.log" 2>&1 || { tail -20 "$WORK/alpha.log"; die "alpha render failed"; }
python3 -I - "$ALPHA" <<'PY' || die "portrait/alpha report check failed"
import json, struct, sys
from pathlib import Path
out = Path(sys.argv[1])
report = json.loads((out / "render-report.json").read_text())
assert report["resolution"] == [1080, 1920]
assert report["turntable"] and report["camera"]["sweep_deg"] == 360
assert report["alpha"] and report["motion_check"]["lookdev_drift"] == 0
assert report["frames_rendered"] == [0, 1] and "mp4" not in report["outputs"]
assert (out / "PROVENANCE.txt").read_bytes() == (out / "frames" / "PROVENANCE.txt").read_bytes()
for name in ("frame_0000.png", "frame_0001.png"):
    with (out / "frames" / name).open("rb") as f:
        header = f.read(26)
    assert struct.unpack(">IIBB", header[16:26]) == (1080, 1920, 8, 6)
PY
if nice -n 10 "$BLENDER" -b --factory-startup -P "$HERE/render.py" -- "$MANIFEST" "$ALPHA" \
    --resolution 9:16 --alpha --resume --frames 0-1 --samples 4 --no-motion-blur >"$WORK/resume.log" 2>&1; then
  die "resume accepted frames rendered with a different camera preset"
fi
grep -q 'other settings (settings)' "$WORK/resume.log" \
  || { tail -10 "$WORK/resume.log"; die "resume failed for another reason"; }
say "PASS. outputs in $OUT and $ALPHA"
