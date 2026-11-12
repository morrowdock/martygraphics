#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Renders the fixed visual showcase set with `marty-solid render` (stills only), once per look.
# Evidence for visual-quality work: run by .github/workflows/showcase.yml on a hosted Mac, or by
# hand on a Mac. It never gates a merge and never writes into the repository.
#
#   tools/showcase.sh OUT_DIR [LOOK ...]
#
# With no LOOK the renderer's default is used and no --look flag is passed (so the script also
# works on a build that has no looks). MARTY_SOLID names the built tool.
set -euo pipefail
out=${1:?usage: tools/showcase.sh OUT_DIR [LOOK ...]}
shift
looks=("$@")
[ ${#looks[@]} -gt 0 ] || looks=(default)
bin=${MARTY_SOLID:-Examples/Solid3D/.build/release/marty-solid}
[ -x "$bin" ] || { echo "Build first: swift build -c release --package-path Examples/Solid3D --product marty-solid" >&2; exit 2; }

# name=path: the turbofan, the robot-joint gearbox, the five drone and aviation explainers, and one
# mixed 2D/3D explainer (board, table and solid panes).
set_=(
  "turbofan=Examples/Turbofan/Sources/TurbofanKit/Models/turbofan.json"
  "robot-joint=docs/assets/from-a-prompt/robot-joint/robot-joint-gearbox.json"
  "quadcopter=docs/assets/drone-aviation/quadcopter/quadcopter.json"
  "brushless-motor=docs/assets/drone-aviation/brushless-motor/motor.json"
  "gimbal=docs/assets/drone-aviation/gimbal/gimbal.json"
  "landing-gear=docs/assets/drone-aviation/landing-gear/landing-gear.json"
  "payload-cg=docs/assets/drone-aviation/payload-cg/payload-cg.json"
  "gears-mixed=Examples/Explainers/gears-mixed.explainer.json"
)
mkdir -p "$out"
fail=0
for look in "${looks[@]}"; do
  mkdir -p "$out/$look"
  for item in "${set_[@]}"; do
    name=${item%%=*}; path=${item#*=}
    args=(render "$path" "$out/$look/$name" --size 1280x800 --no-loop --no-story)
    [ "$look" = default ] || args+=(--look "$look")
    t=$SECONDS
    if "$bin" "${args[@]}" > "$out/$look/$name.log" 2>&1; then
      echo "PASS $look/$name $((SECONDS - t))s" | tee -a "$out/summary.txt"
    else
      echo "FAIL $look/$name $((SECONDS - t))s" | tee -a "$out/summary.txt"; tail -5 "$out/$look/$name.log" || true; fail=1
    fi
  done
done
# Pixels are the evidence; the JSON next to them is the same for every look and stays out of the artifact.
find "$out" -name 'snapshot*.json' -delete
exit $fail
