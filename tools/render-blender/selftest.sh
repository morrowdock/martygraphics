#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# selftest.sh: end-to-end check that needs no MartyGraphics export.
#   1. builds a 24/12-tooth gear pair (2:1) in Blender and exports .glb + manifest
#   2. checks the 2:1 ratio and the frame grid from the .glb alone (pure Python)
#   3. checks that tampered exports are refused (SHA-256, fps, frame count)
#   4. renders the full pipeline in preview mode and reports time per frame
# Usage: tools/render-blender/selftest.sh [work-dir]   (default: a new temporary directory)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER="${BLENDER:-$HOME/opt/blender-${BLENDER_VERSION:-5.2.4}/blender}"
WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/mg-render-selftest.XXXXXX")}"
EXPORT="$WORK/export"; OUT="$WORK/render-preview"
say() { printf 'selftest: %s\n' "$*"; }
die() { printf 'selftest: FAIL: %s\n' "$*" >&2; exit 1; }
[ -x "$BLENDER" ] || die "Blender not found at $BLENDER (run setup.sh)"
mkdir -p "$WORK"

# Simulator priority: never start a heavy render while the landing-lab simulator runs.
(cd "$HERE" && python3 -E -s -m mgrender.simguard) || die "landing-lab simulator is running; try again later"

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
T="$WORK/tamper"; rm -rf "$T"; mkdir -p "$T"
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
(cd "$HERE" && python3 -E -s -m mgrender.simguard) || die "landing-lab simulator started; stopping before the render"
nice -n 10 "$BLENDER" -b --factory-startup -P "$HERE/render.py" -- "$MANIFEST" "$OUT" --preset preview --camera auto \
  2>&1 | tee "$WORK/render.log" | grep -E '^render: (PASS|motion|look-dev|Cycles|DONE|poster|frames|time)|REFUSED|FAILED' || true
grep -q '^MG_RENDER_REPORT ' "$WORK/render.log" || die "render did not finish (see $WORK/render.log)"
REPORT="$(sed -n 's/^MG_RENDER_REPORT //p' "$WORK/render.log")"
python3 -I - "$REPORT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
t = r["timing_s"]
print(f"selftest: report {sys.argv[1]}")
print(f"selftest: device {r['device']}; {r['resolution'][0]}x{r['resolution'][1]}, {r['samples_max']} max samples")
print(f"selftest: first frame {t['first_frame']} s, mean after first {t['mean_after_first']} s/frame, "
      f"encode {t['encode']} s, total {t['total']} s")
print(f"selftest: motion max error {r['motion_check']['max_error']:.3g} (tol {r['motion_check']['tolerance']:.3g}), "
      f"look-dev drift {r['motion_check']['lookdev_drift']}")
PY
say "PASS. outputs in $OUT"
