#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup.sh: install the official Blender LTS Linux build in user space, verify it,
# fetch the pinned CC0 assets and report the Cycles GPU device.
# No sudo. No system packages. Safe to run again (it skips verified work).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER_VERSION="${BLENDER_VERSION:-5.2.4}"          # Blender 5.2 LTS (supported to 2028-07)
SERIES="${BLENDER_VERSION%.*}"
OPT_DIR="${OPT_DIR:-$HOME/opt}"
PREFIX="$OPT_DIR/blender-$BLENDER_VERSION"
ASSET_DIR="${MG_RENDER_ASSETS:-${XDG_CACHE_HOME:-$HOME/.cache}/martygraphics-render/assets}"
TARBALL="blender-$BLENDER_VERSION-linux-x64.tar.xz"
SUMS="blender-$BLENDER_VERSION.sha256"
# The primary site comes first. Its Cloudflare challenge can refuse non-browser
# clients; the others are official mirrors listed on blender.org/download.
SOURCES=(
  "https://download.blender.org/release/Blender$SERIES"
  "https://ftp.nluug.nl/pub/graphics/blender/release/Blender$SERIES"
  "https://mirrors.ocf.berkeley.edu/blender/release/Blender$SERIES"
  "https://mirror.clarkson.edu/blender/release/Blender$SERIES"
)
MIN_AGREEING_SOURCES=2

say() { printf 'setup: %s\n' "$*"; }
die() { printf 'setup: ERROR: %s\n' "$*" >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || die "do not run as root"
for tool in curl sha256sum tar xz; do command -v "$tool" >/dev/null || die "$tool not found"; done

fetch() { curl -fsSL --retry 2 --connect-timeout 20 --max-time "${2:-60}" -o "$3" "$1"; }

install_blender() {
  if [ -x "$PREFIX/blender" ] && [ -f "$PREFIX/INSTALL-RECORD.json" ]; then
    say "Blender $BLENDER_VERSION is already installed in $PREFIX (record: INSTALL-RECORD.json)"
    return
  fi
  DL_DIR="$(mktemp -d "$OPT_DIR/.blender-dl.XXXXXX")"
  trap 'rm -rf "$DL_DIR"' EXIT
  local dl="$DL_DIR"
  # 1. Published checksum from every reachable source; all must agree.
  local expected="" agree=0 src sum used_sums=()
  for src in "${SOURCES[@]}"; do
    if fetch "$src/$SUMS" 30 "$dl/sums" 2>/dev/null; then
      sum="$(awk -v f="$TARBALL" '$2==f {print $1}' "$dl/sums")"
      [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || { say "no $TARBALL line in $src/$SUMS"; continue; }
      if [ -z "$expected" ]; then expected="$sum"; elif [ "$sum" != "$expected" ]; then
        die "published checksums disagree ($src): $sum vs $expected"; fi
      agree=$((agree + 1)); used_sums+=("$src/$SUMS")
      say "checksum $sum from $src"
    else
      say "cannot read $src/$SUMS (skipped)"
    fi
  done
  [ "$agree" -ge "$MIN_AGREEING_SOURCES" ] || die "need $MIN_AGREEING_SOURCES agreeing checksum sources, got $agree"
  # 2. The tarball from the first source that serves it.
  local url=""
  for src in "${SOURCES[@]}"; do
    say "download $src/$TARBALL"
    if fetch "$src/$TARBALL" 1800 "$dl/$TARBALL"; then url="$src/$TARBALL"; break; fi
  done
  [ -n "$url" ] || die "no source served $TARBALL"
  local actual; actual="$(sha256sum "$dl/$TARBALL" | awk '{print $1}')"
  [ "$actual" = "$expected" ] || die "SHA-256 mismatch: got $actual, published $expected"
  say "SHA-256 OK: $actual"
  # 3. Extract to a staging directory, then move it in place.
  mkdir -p "$dl/x"
  tar -xJf "$dl/$TARBALL" -C "$dl/x" --strip-components=1 --no-same-owner
  [ -x "$dl/x/blender" ] || die "archive has no blender executable"
  rm -rf "$PREFIX"; mv "$dl/x" "$PREFIX"
  python3 -I - "$PREFIX/INSTALL-RECORD.json" "$BLENDER_VERSION" "$url" "$actual" "${used_sums[@]}" <<'PY'
import json, sys, datetime
out, version, url, sha, *sums = sys.argv[1:]
json.dump({"version": version, "url": url, "sha256": sha, "sha256_verified_against": sums,
           "installed_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
          open(out, "w"), indent=2)
PY
  say "installed Blender $BLENDER_VERSION in $PREFIX"
}

fetch_assets() {
  mkdir -p "$ASSET_DIR"
  python3 -I - "$HERE/assets.lock.json" <<'PY' | while IFS=$'\t' read -r file url sha; do
import json, sys
for a in json.load(open(sys.argv[1]))["assets"]:
    print(a["file"], a["url"], a["sha256"], sep="\t")
PY
    local dst="$ASSET_DIR/$file"
    if [ -f "$dst" ] && [ "$(sha256sum "$dst" | awk '{print $1}')" = "$sha" ]; then
      say "asset OK: $file"; continue; fi
    fetch "$url" 600 "$dst.part"
    local got; got="$(sha256sum "$dst.part" | awk '{print $1}')"
    [ "$got" = "$sha" ] || { rm -f "$dst.part"; die "asset $file SHA-256 $got differs from pin $sha"; }
    mv "$dst.part" "$dst"; say "asset fetched and verified: $file"
  done
}

check_gpu() {
  "$PREFIX/blender" -b --factory-startup --python "$HERE/mgrender/gpu_probe.py" 2>/dev/null \
    | sed -n 's/^MG_GPU //p'
}

mkdir -p "$OPT_DIR"
install_blender
fetch_assets
say "Blender: $("$PREFIX/blender" --version 2>/dev/null | head -1)"
say "Cycles device: $(check_gpu)"
say "run renders with: $PREFIX/blender -b -P $HERE/render.py -- <manifest.json> <out-dir> [--preset preview|hero]"
