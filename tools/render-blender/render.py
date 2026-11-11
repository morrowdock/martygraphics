# SPDX-License-Identifier: Apache-2.0
"""Film-quality render of a verified MartyGraphics export in Blender Cycles.

    nice -n 10 blender -b --factory-startup -P render.py -- <manifest.json> <out-dir> [options]

Options:
  --preset preview|hero       preview: 720p, low samples. hero: 1080p, high samples (default preview)
  --resolution 720p|1080p|1440p|4k|WxH   override the preset resolution (hero 4K: --resolution 4k)
  --samples N                 override the preset maximum samples
  --camera auto|export|NAME   auto: hero orbit; export: first manifest camera; NAME: that camera.
                              Default: export when the manifest lists a camera, else auto
  --backdrop studio|shadow    studio cyclorama (default) or a shadow catcher over a plain background
  --frames A-B                render only frames A..B (inclusive); the whole export is still verified
  --no-motion-blur            frame-exact stills (motion blur is on by default)
  --no-burn-in                no burned-in provenance caption on the MP4 and poster
  --resume                    keep frames that already exist in <out-dir>/frames
  --wait-for-simulator SEC    wait up to SEC seconds for the landing-lab simulator to stop (default 0: refuse)
  --allow-cpu                 render on the CPU when no OptiX/CUDA device exists

Exit codes: 0 done, 1 export refused (manifest/SHA-256/fps/frames), 2 usage,
3 simulator running, 4 motion check failed, 5 render/encode failure.

The render is cosmetic. The script never changes exported motion, timing or
geometry, and proves that: it compares every imported object's world matrix at
every frame with the glTF evaluation, and again after look-dev.
"""
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from mgrender import device, faststart, lookdev, simguard  # noqa: E402
from mgrender import manifest as mf  # noqa: E402

ASSET_DIR = os.environ.get("MG_RENDER_ASSETS") or os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "martygraphics-render", "assets")
BACKDROP = (0.62, 0.63, 0.65)
SHADOW_BG = (0.80, 0.81, 0.83)


class Refused(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def log(msg):
    print(f"render: {msg}", flush=True)


# ----------------------------------------------------------------- arguments
def parse_args(argv):
    if len(argv) < 2 or argv[0].startswith("-") or argv[1].startswith("-"):
        raise Refused(2, "usage: blender -b -P render.py -- <manifest.json> <out-dir> [--preset hero|preview] ...")
    a = {"manifest": argv[0], "out": argv[1], "preset": "preview", "resolution": None, "samples": None,
         "camera": None, "backdrop": "studio", "frames": None, "motion_blur": True, "burn_in": True,
         "resume": False, "wait": 0, "allow_cpu": False}
    it = iter(argv[2:])
    for opt in it:
        def val():
            try:
                return next(it)
            except StopIteration:
                raise Refused(2, f"{opt} needs a value")
        if opt == "--preset":
            a["preset"] = val()
        elif opt == "--resolution":
            v = val()
            if v in lookdev.RESOLUTIONS:
                a["resolution"] = lookdev.RESOLUTIONS[v]
            else:
                try:
                    w, h = (int(x) for x in v.lower().split("x"))
                except ValueError:
                    raise Refused(2, f"bad --resolution {v}")
                a["resolution"] = (w, h)
        elif opt == "--samples":
            a["samples"] = int(val())
        elif opt == "--camera":
            a["camera"] = val()
        elif opt == "--backdrop":
            a["backdrop"] = val()
        elif opt == "--frames":
            v = val()
            try:
                lo, hi = (int(x) for x in v.split("-"))
            except ValueError:
                raise Refused(2, f"bad --frames {v} (use A-B)")
            a["frames"] = (lo, hi)
        elif opt == "--no-motion-blur":
            a["motion_blur"] = False
        elif opt == "--no-burn-in":
            a["burn_in"] = False
        elif opt == "--resume":
            a["resume"] = True
        elif opt == "--wait-for-simulator":
            a["wait"] = int(val())
        elif opt == "--allow-cpu":
            a["allow_cpu"] = True
        else:
            raise Refused(2, f"unknown option {opt}")
    if a["preset"] not in lookdev.PRESETS:
        raise Refused(2, f"--preset must be one of {sorted(lookdev.PRESETS)}")
    if a["backdrop"] not in ("studio", "shadow"):
        raise Refused(2, "--backdrop must be studio or shadow")
    w, h = a["resolution"] or lookdev.PRESETS[a["preset"]]["resolution"]
    if w % 2 or h % 2 or w < 16 or h < 16:
        raise Refused(2, "resolution must be even and at least 16x16 (H.264 yuv420p)")
    return a


# ----------------------------------------------------------------- simulator priority
def wait_for_simulator(max_wait, phase):
    deadline = time.time() + max_wait
    while True:
        clear, reasons = simguard.status()
        if clear:
            return
        if time.time() >= deadline:
            raise Refused(3, f"landing-lab simulator is running ({phase}); render not started/continued: "
                          + "; ".join(reasons[:3]))
        log(f"simulator running ({reasons[0]}); waiting ...")
        time.sleep(min(30, max(1, deadline - time.time())))


def be_nice():
    try:
        current = os.nice(0)
        if current < 10:
            os.nice(10 - current)
    except OSError:
        pass
    return os.nice(0)


# ----------------------------------------------------------------- motion proof
def matrix_rows(m):
    return [[float(m[i][j]) for j in range(4)] for i in range(4)]


def blender_snapshot(scene, objects, frames):
    snap = {}
    for f in frames:
        scene.frame_set(f)
        snap[f] = {ob.name: matrix_rows(ob.matrix_world) for ob in objects}
    return snap


def mesh_digest(objects):
    h = hashlib.sha256()
    for ob in sorted((o for o in objects if o.type == "MESH"), key=lambda o: o.name):
        me = ob.data
        co = [0.0] * (len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        h.update(ob.name.encode())
        h.update(repr([round(c, 9) for c in co]).encode())
    return h.hexdigest()


def compare_with_gltf(checked, snap, objects):
    """Max deviation between Blender world matrices and the glTF evaluation (in Blender space)."""
    gltf, anim, fps = checked["gltf"], checked["animation"], checked["fps"]
    by_name = {ob.name: ob for ob in objects}
    nodes = gltf.get("nodes", [])
    matched, worst = [], (0.0, None, None)
    span = 0.0
    for idx, node in enumerate(nodes):
        name = node.get("name")
        if not name:
            continue
        ob = by_name.get(name)
        if ob is None:
            if idx in checked["animated_nodes"]:
                raise Refused(4, f"animated glTF node '{name}' has no Blender object after import")
            continue
        matched.append((idx, ob))
    if not matched:
        raise Refused(4, "no glTF node matched a Blender object after import")
    for f, objs in snap.items():
        world = mf.world_matrices(gltf, anim, f / fps)
        for idx, ob in matched:
            g = mf.to_blender(world[idx])
            b = objs[ob.name]
            span = max(span, max(abs(g[i][3]) for i in range(3)))
            only_position = ob.type in ("CAMERA", "LIGHT")   # the importer adds a fixed axis correction
            rows = range(3)
            cols = (3,) if only_position else range(4)
            err = max(abs(g[i][j] - b[i][j]) for i in rows for j in cols)
            if err > worst[0]:
                worst = (err, ob.name, f)
    tol = 1e-5 * max(span, 1e-3) + 1e-6
    return {"max_error": worst[0], "worst_object": worst[1], "worst_frame": worst[2], "tolerance": tol,
            "objects_checked": len(matched), "frames_checked": len(snap), "pass": worst[0] <= tol}


def compare_bounds(checked, objects):
    """Mesh local bounds after import against the glTF POSITION min/max (axis-converted)."""
    gltf = checked["gltf"]
    by_name = {ob.name: ob for ob in objects if ob.type == "MESH"}
    worst = 0.0
    for node in gltf.get("nodes", []):
        ob = by_name.get(node.get("name"))
        if ob is None or "mesh" not in node:
            continue
        lo, hi = [float("inf")] * 3, [float("-inf")] * 3
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            if "min" in acc and "max" in acc:
                lo = [min(a, b) for a, b in zip(lo, acc["min"])]
                hi = [max(a, b) for a, b in zip(hi, acc["max"])]
        if lo[0] == float("inf"):
            continue
        # glTF (x, y, z) -> Blender (x, -z, y)
        g_lo = (lo[0], -hi[2], lo[1])
        g_hi = (hi[0], -lo[2], hi[1])
        corners = [Vector(c) for c in ob.bound_box]
        b_lo = [min(c[i] for c in corners) for i in range(3)]
        b_hi = [max(c[i] for c in corners) for i in range(3)]
        worst = max(worst, *(abs(a - b) for a, b in zip(g_lo, b_lo)), *(abs(a - b) for a, b in zip(g_hi, b_hi)))
    return worst


# ----------------------------------------------------------------- encode
def build_encode_scene(src, frames_dir, frame_files, label, burn_in, background):
    enc = bpy.data.scenes.new("mg_encode")
    enc.render.resolution_x, enc.render.resolution_y = src.render.resolution_x, src.render.resolution_y
    enc.render.resolution_percentage = 100
    enc.render.fps, enc.render.fps_base = src.render.fps, 1.0
    enc.frame_start, enc.frame_end = 1, len(frame_files)
    # The frames already carry the AgX view transform: the encode pass must not apply it again.
    enc.view_settings.view_transform = "Standard"
    enc.view_settings.look = "None"
    enc.sequencer_colorspace_settings.name = "sRGB"
    ed = enc.sequence_editor_create()
    channel = 1
    if background is not None:
        bg = ed.strips.new_effect(name="bg", type="COLOR", channel=channel, frame_start=1, length=len(frame_files))
        bg.color = background
        channel += 1
    img = ed.strips.new_image(name="frames", filepath=os.path.join(frames_dir, frame_files[0]),
                              channel=channel, frame_start=1)
    for name in frame_files[1:]:
        img.elements.append(name)
    img.colorspace_settings.name = "sRGB"
    if background is not None:
        img.blend_type = "ALPHA_OVER"
    channel += 1
    if burn_in:
        txt = ed.strips.new_effect(name="provenance", type="TEXT", channel=channel, frame_start=1,
                                   length=len(frame_files))
        txt.text = label
        txt.font_size = max(12, round(enc.render.resolution_y * 0.020))
        txt.color = (1, 1, 1, 0.95)
        txt.use_box = True
        txt.box_color = (0, 0, 0, 0.45)
        txt.box_margin = 0.004
        txt.location = (0.5, 0.025)
        txt.anchor_x, txt.anchor_y = "CENTER", "BOTTOM"
        txt.alignment_x = "CENTER"
        txt.wrap_width = 0.96
    lookdev.provenance_metadata(enc, label)
    return enc


def encode_mp4(enc, path, fps):
    r = enc.render
    r.image_settings.media_type = "VIDEO"
    r.image_settings.file_format = "FFMPEG"
    r.ffmpeg.format = "MPEG4"
    r.ffmpeg.codec = "H264"
    r.ffmpeg.constant_rate_factor = "HIGH"
    r.ffmpeg.ffmpeg_preset = "GOOD"
    r.ffmpeg.gopsize = fps
    r.ffmpeg.audio_codec = "NONE"
    r.use_file_extension = False
    r.filepath = path
    bpy.ops.render.render(animation=True, scene=enc.name)
    if not os.path.isfile(path):
        raise Refused(5, f"FFmpeg output not found at {path}")
    changed = faststart.faststart_file(path)
    with open(path, "rb") as f:
        if not faststart.is_faststart(f.read()):
            raise Refused(5, "MP4 is not fast start after the rewrite")
    return changed


def write_poster(enc, path, frame_index):
    """Render one encode-scene frame to path. A still render of a scene that is not the
    context scene uses the context scene's frame, so render a one-frame animation instead."""
    r = enc.render
    r.image_settings.media_type = "IMAGE"
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGB"
    r.image_settings.color_depth = "8"
    enc.frame_start = enc.frame_end = frame_index
    stem = path[:-4] if path.endswith(".png") else path
    r.use_file_extension = True
    r.filepath = stem + ".tmp-####"
    bpy.ops.render.render(animation=True, scene=enc.name)
    produced = f"{stem}.tmp-{frame_index:04d}.png"
    if not os.path.isfile(produced):
        raise Refused(5, f"poster frame not written ({produced})")
    os.replace(produced, path)


def sha(path):
    return mf.sha256_file(path)


# ----------------------------------------------------------------- main
def run(argv):
    t_start = time.time()
    args = parse_args(argv)
    nice = be_nice()
    try:
        checked = mf.verify(args["manifest"])
    except (mf.ExportError, OSError, ValueError, KeyError) as e:
        raise Refused(1, f"export refused: {e}")
    label = mf.provenance_label(checked)
    log(f"PASS export check: scene {checked['scene_id']}, engine {checked['engine_commit']}, "
        f"{checked['frame_count']} frames at {checked['fps']} fps, glb {checked['glb_sha256'][:16]}...")
    wait_for_simulator(args["wait"], "before start")

    out = os.path.abspath(args["out"])
    frames_dir = os.path.join(out, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    existing = [n for n in os.listdir(frames_dir) if n.endswith(".png")]
    if existing and not args["resume"]:
        raise Refused(2, f"{frames_dir} already holds {len(existing)} PNG frames; use --resume or a new out-dir")

    preset = lookdev.PRESETS[args["preset"]]
    resolution = args["resolution"] or preset["resolution"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    dev = device.select_device(allow_cpu=args["allow_cpu"])
    if dev["backend"] == "CPU" and not args["allow_cpu"]:
        raise Refused(5, "no GPU device")
    log(f"Cycles device: {dev['summary']}; process nice {nice}")

    scene = bpy.context.scene
    fps, count = checked["fps"], checked["frame_count"]
    scene.render.fps, scene.render.fps_base = fps, 1.0
    scene.frame_start, scene.frame_end = 0, count - 1
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=checked["glb_path"], merge_vertices=False, import_shading="NORMALS",
                              import_select_created_objects=False)
    imported = [ob for ob in bpy.data.objects if ob not in before]
    if not imported:
        raise Refused(1, "the glTF importer created no objects")
    all_frames = list(range(count))

    # Proof 1: Blender shows the exported motion (every object, every frame).
    snap = blender_snapshot(scene, imported, all_frames)
    motion = compare_with_gltf(checked, snap, imported)
    bounds_err = compare_bounds(checked, imported)
    motion["mesh_bounds_max_error"] = bounds_err
    log(f"motion check: {motion['objects_checked']} objects x {motion['frames_checked']} frames, "
        f"max error {motion['max_error']:.3g} (tolerance {motion['tolerance']:.3g}), bounds error {bounds_err:.3g}")
    if not motion["pass"] or bounds_err > motion["tolerance"] * 10:
        raise Refused(4, f"imported motion differs from the export: {motion}")
    digest_before = mesh_digest(imported)

    # Look-dev (cosmetic only).
    stride = max(1, count // 120)
    lo, hi = lookdev.subject_bounds(imported, scene, all_frames[::stride] + [count - 1])
    size = (hi - lo).length
    scene.render.resolution_x, scene.render.resolution_y = resolution
    hdri = os.path.join(ASSET_DIR, "studio_small_09_2k.hdr")
    if not os.path.isfile(hdri):
        log("WARNING: HDRI asset missing (run setup.sh); using a procedural world")
        hdri = None
    if args["backdrop"] == "studio":
        lookdev.setup_world(scene, hdri, BACKDROP, hide_hdri_from_camera=True)
        lookdev.cyclorama(scene, lo, hi, BACKDROP)
        scene.render.film_transparent = False
        encode_bg = None
    else:
        lookdev.setup_world(scene, hdri, SHADOW_BG, hide_hdri_from_camera=False)
        lookdev.shadow_catcher(scene, lo, hi)
        scene.render.film_transparent = True
        scene.cycles.film_transparent_glass = True   # glass over a transparent film must not darken
        encode_bg = SHADOW_BG
    overrides = {p["name"]: p.get("material", {}) for p in checked["manifest"].get("parts", [])}
    mat_report = lookdev.assign_materials(imported, overrides, size)

    cam_choice = args["camera"] or ("export" if checked["manifest"].get("cameras") else "auto")
    cams = {ob.name: ob for ob in imported if ob.type == "CAMERA"}
    if cam_choice == "auto":
        cam, cam_info, view_dir = lookdev.auto_orbit_camera(scene, lo, hi, 0, count - 1, preset)
    else:
        name = (checked["manifest"].get("cameras") or [{}])[0].get("name") if cam_choice == "export" else cam_choice
        if name not in cams:
            raise Refused(2, f"camera '{name}' is not an imported export camera (have {sorted(cams)})")
        cam, cam_info, view_dir = lookdev.export_camera(scene, cams[name], lo, hi)
    lookdev.key_light(scene, (lo + hi) / 2, size, view_dir)
    lookdev.configure_render(scene, preset, resolution, dev, args["motion_blur"], args["samples"])
    lookdev.provenance_metadata(scene, label)

    # Proof 2: look-dev changed no imported transform, animation or vertex.
    snap_after = blender_snapshot(scene, imported, all_frames)
    drift = max(abs(a - b) for f in all_frames for n in snap[f] for ra, rb in zip(snap[f][n], snap_after[f][n])
                for a, b in zip(ra, rb))
    if drift != 0.0 or mesh_digest(imported) != digest_before:
        raise Refused(4, f"look-dev changed exported motion or geometry (max drift {drift})")
    motion["lookdev_drift"] = drift
    log("look-dev check: imported transforms and vertices unchanged")

    # Render the PNG master frames.
    first, last = args["frames"] or (0, count - 1)
    if not (0 <= first <= last < count):
        raise Refused(2, f"--frames must be within 0-{count - 1}")
    times = {}
    for f in range(first, last + 1):
        path = os.path.join(frames_dir, f"frame_{f:04d}.png")
        if args["resume"] and os.path.isfile(path):
            continue
        wait_for_simulator(args["wait"] if f == first else max(args["wait"], 3600), f"frame {f}")
        scene.frame_set(f)
        scene.render.filepath = path
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        times[f] = time.time() - t0
        log(f"frame {f} ({f - first + 1}/{last - first + 1}) {times[f]:.2f} s")
    frame_files = [f"frame_{f:04d}.png" for f in range(first, last + 1)]
    missing = [n for n in frame_files if not os.path.isfile(os.path.join(frames_dir, n))]
    if missing:
        raise Refused(5, f"missing frames after render: {missing[:3]}")
    with open(os.path.join(frames_dir, "PROVENANCE.txt"), "w", encoding="utf-8") as f:
        f.write(label + "\n")

    # Encode MP4 and poster from the master frames (no re-render).
    t_enc = time.time()
    enc = build_encode_scene(scene, frames_dir, frame_files, label, args["burn_in"], encode_bg)
    sid = checked["scene_id"]
    mp4 = os.path.join(out, f"{sid}-{args['preset']}.mp4")
    rewrote = encode_mp4(enc, mp4, fps)
    poster_frame = min(max(checked["poster_frame"], first), last)
    poster = os.path.join(out, f"{sid}-{args['preset']}-poster.png")
    write_poster(enc, poster, poster_frame - first + 1)
    t_enc = time.time() - t_enc

    rendered = sorted(times)
    steady = [times[f] for f in rendered[1:]] or [times[f] for f in rendered]
    report = {
        "provenance": label,
        "scene_id": sid,
        "engine_commit": checked["engine_commit"],
        "manifest": os.path.basename(checked["manifest_path"]),
        "manifest_sha256": sha(checked["manifest_path"]),
        "glb_sha256": checked["glb_sha256"],
        "fps": fps, "frame_count": count, "frames_rendered": [first, last],
        "blender": {"version": bpy.app.version_string, "build_hash": bpy.app.build_hash.decode()},
        "device": dev["summary"], "nice": nice,
        "preset": args["preset"], "resolution": list(resolution),
        "samples_max": scene.cycles.samples, "adaptive_threshold": scene.cycles.adaptive_threshold,
        "denoiser": scene.cycles.denoiser, "view_transform": scene.view_settings.view_transform,
        "look": scene.view_settings.look, "motion_blur": args["motion_blur"], "backdrop": args["backdrop"],
        "camera": cam_info, "materials": mat_report, "motion_check": motion,
        "timing_s": {"per_frame": {str(k): round(v, 3) for k, v in times.items()},
                     "first_frame": round(times[rendered[0]], 3) if rendered else None,
                     "mean_after_first": round(sum(steady) / len(steady), 3) if steady else None,
                     "encode": round(t_enc, 2), "total": round(time.time() - t_start, 2)},
        "outputs": {"frames_dir": "frames", "mp4": os.path.basename(mp4), "mp4_faststart_rewritten": rewrote,
                    "poster": os.path.basename(poster), "poster_frame": poster_frame,
                    "sha256": {os.path.basename(p): sha(p) for p in (mp4, poster)}},
    }
    with open(os.path.join(out, "render-report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    with open(os.path.join(out, "PROVENANCE.txt"), "w", encoding="utf-8") as f:
        f.write(label + "\n")
    log(f"DONE {mp4}")
    log(f"poster {poster}")
    log(f"frames {frames_dir} ({len(frame_files)} PNG)")
    if rendered:
        log(f"time per frame: first {report['timing_s']['first_frame']} s, "
            f"mean after first {report['timing_s']['mean_after_first']} s; total {report['timing_s']['total']} s")
    print("MG_RENDER_REPORT " + os.path.join(out, "render-report.json"), flush=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    try:
        run(argv)
    except Refused as e:
        print(f"render: REFUSED ({e.code}): {e}", file=sys.stderr, flush=True)
        sys.stdout.flush()
        os._exit(e.code)   # Blender ignores sys.exit codes from -P scripts in some paths
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        print(f"render: FAILED: {e}", file=sys.stderr, flush=True)
        os._exit(5)
    sys.stdout.flush()
    os._exit(0)


if __name__ == "__main__":
    main()
