# SPDX-License-Identifier: Apache-2.0
"""Cycles device selection (runs inside Blender). GPU first: OptiX, then CUDA, then CPU."""
import bpy


def select_device(allow_cpu=True):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    chosen = None
    for backend in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = backend
        except TypeError:
            continue
        prefs.refresh_devices()
        gpus = [d for d in prefs.devices if d.type == backend]
        if gpus:
            chosen = backend
            for d in prefs.devices:
                d.use = d.type == backend   # GPU only; leave the CPU free for other work
            break
    if chosen is None:
        if not allow_cpu:
            raise RuntimeError("No OptiX or CUDA device found")
        prefs.compute_device_type = "NONE"
        return {"backend": "CPU", "devices": [], "summary": "CPU (no OptiX/CUDA device found)"}
    names = [d.name for d in prefs.devices if d.use]
    return {"backend": chosen, "devices": names, "summary": f"{chosen}: {', '.join(names)}"}


def apply_to_scene(scene, info):
    scene.cycles.device = "CPU" if info["backend"] == "CPU" else "GPU"
