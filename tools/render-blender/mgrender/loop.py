# SPDX-License-Identifier: Apache-2.0
"""Seamless loops in the render path (docs/ENGINE.md, "Seamless loops"). No Blender imports.

`marty-solid export-gltf --seamless` records a `loop` object in the manifest: frames 0..frames-1 are exactly one
period of the motion, and the glTF holds one more key, the closing frame (frame `frames`: the same scene as frame 0,
with the motion continued). These helpers decide how to render such an export so the video loops without a seam:

* render frames 0..frames-1 only (the closing frame is frame 0 again; rendering it would show frame 0 twice at the
  wrap, a held frame);
* open the motion-blur shutter at the frame (START): the last loop frame then blurs toward the closing key, exactly as
  frame 0 blurs toward frame 1 (a CENTER shutter would sample before key 0, where the motion is clamped);
* complete a turntable's 360 degrees at frame `frames`, and let an automatic camera sway out and back over the loop
  instead of sweeping one way (a one-way sweep jumps back at the wrap).

An export without a `loop` object renders exactly as before.
"""
import math


class LoopError(ValueError):
    """A malformed manifest `loop` object."""


def _count(value):
    return isinstance(value, int) and not isinstance(value, bool)


def loop_info(manifest, frame_count):
    """The checked `loop` object of a manifest as a dict, or None when there is none. Raises LoopError."""
    loop = manifest.get("loop")
    if loop is None:
        return None
    if not isinstance(loop, dict):
        raise LoopError("manifest loop must be an object")
    seamless = loop.get("seamless")
    if not isinstance(seamless, bool):
        raise LoopError("manifest loop.seamless must be true or false")
    frames = loop.get("frames")
    if not _count(frames) or frames < 1:
        raise LoopError("manifest loop.frames must be a positive integer")
    closing = loop.get("closingFrame")
    if closing is not None:
        if not _count(closing) or closing != frames:
            raise LoopError("manifest loop.closingFrame must equal loop.frames")
        if frame_count != frames + 1:
            raise LoopError(f"a loop with a closing frame needs frameCount {frames + 1}, the manifest says {frame_count}")
    elif frames > frame_count:
        raise LoopError(f"manifest loop.frames {frames} exceeds frameCount {frame_count}")
    turns = loop.get("inputTurns")
    if turns is not None and not isinstance(turns, str):
        raise LoopError("manifest loop.inputTurns must be a string such as \"49/6\"")
    return {"seamless": seamless, "frames": frames, "closing": closing is not None, "input_turns": turns}


def is_seamless(info):
    return bool(info and info["seamless"])


def render_range(info, frame_count):
    """Frames to render when --frames is not given (inclusive): the loop frames of a seamless loop, else all."""
    if is_seamless(info):
        return 0, info["frames"] - 1
    return 0, frame_count - 1


def blur_position(info):
    """The motion-blur shutter position: START for a seamless loop with a closing key, else CENTER (as before)."""
    return "START" if is_seamless(info) and info["closing"] else "CENTER"


def camera_end_frame(info, frame_count):
    """The last frame the automatic camera spans; a turntable completes its turn one frame later."""
    return info["frames"] - 1 if is_seamless(info) else frame_count - 1


def sway_frames(info):
    """The period (frames) of the automatic camera's out-and-back sway, or None for the one-way sweep."""
    return info["frames"] if is_seamless(info) else None


def sway(start, sweep, frames):
    """Azimuth keys (frame, radians) of a camera that swings out by `sweep` and back once over `frames` frames:
    a raised cosine, so the key at `frames` equals the key at 0 and the camera slows to rest at both turns."""
    if not _count(frames) or frames < 1:
        raise LoopError("sway needs a positive frame count")
    return [(f, start + sweep * (1 - math.cos(2 * math.pi * f / frames)) / 2) for f in range(frames + 1)]
