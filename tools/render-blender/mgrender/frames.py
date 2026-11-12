# SPDX-License-Identifier: Apache-2.0
"""Which export and settings a frames folder was rendered from, so --resume never reuses foreign frames.

The record (frames/FRAMES-IDENTITY.json) holds the hashes of the verified export (GLB and manifest), its scene,
engine commit, fps and frame count, and every setting that changes the pixels of a frame. A resumed run may keep
existing frames only when the folder's record equals the new run's identity exactly; a missing, unreadable or
different record is refused, and frames without a record are never adopted.
"""
import json
import os

RECORD = "FRAMES-IDENTITY.json"
KIND = "martygraphics.render-frames/1"


PROCEDURAL_WORLD = "procedural-world/1"


def lighting_identity(hdri_path, hasher):
    """The effective lighting source: the HDRI's SHA-256, or the fixed id of the procedural fallback world. A resume
    must not mix frames lit by different worlds (re-check of 6f8a98fb)."""
    return {"hdri_sha256": hasher(hdri_path)} if hdri_path else {"fallback": PROCEDURAL_WORLD}


def identity(checked, manifest_sha256, settings):
    """The identity of a frame set: the verified export plus the pixel-affecting settings (a dict of JSON values)."""
    return {"kind": KIND, "glb_sha256": checked["glb_sha256"], "manifest_sha256": manifest_sha256,
            "scene_id": checked["scene_id"], "engine_commit": checked["engine_commit"], "fps": checked["fps"],
            "frame_count": checked["frame_count"], "settings": settings}


def prepare(frames_dir, ident, resume):
    """Check a frames folder before rendering and write its record. Returns None when the run may go on, or the
    reason to refuse. Never deletes or changes existing frames."""
    existing = sorted(n for n in os.listdir(frames_dir) if n.endswith(".png"))
    path = os.path.join(frames_dir, RECORD)
    if existing:
        if not resume:
            return f"{frames_dir} already holds {len(existing)} PNG frames; use --resume or a new out-dir"
        try:
            with open(path, encoding="utf-8") as f:
                recorded = json.load(f)
        except (OSError, ValueError):
            return f"{frames_dir} holds frames without a readable {RECORD}; they cannot be resumed (use a new out-dir)"
        if recorded != ident:
            changed = sorted(k for k in set(recorded) | set(ident) if recorded.get(k) != ident.get(k))
            return f"{frames_dir} holds frames of another export or other settings ({', '.join(changed)}); use a new out-dir"
        return None
    with open(path, "w", encoding="utf-8") as f:
        json.dump(ident, f, indent=2, sort_keys=True)
    return None
