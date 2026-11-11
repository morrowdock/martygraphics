# SPDX-License-Identifier: Apache-2.0
"""Build a small animated test mechanism in Blender and export it like a MartyGraphics export.

    blender -b --factory-startup -P selftest_scene.py -- <export-dir>

Two spur gears mesh at a 2:1 ratio (24 and 12 teeth, module 4 mm). The pinion
turns at exactly -2x the gear angle. The test fixture is NOT a MartyGraphics
verified mechanism: it only exercises the render pipeline (import, look-dev,
motion check, outputs). The manifest marks it with engine commit 0000000.
"""
import hashlib
import json
import math
import os
import sys

import bmesh
import bpy

FPS = 24
FRAMES = 48                      # 2 s
GEAR_TURN_DEG = 90.0             # the 24-tooth gear turns 90 deg; the pinion turns -180 deg
MODULE = 0.004                   # m
TEETH_A, TEETH_B = 24, 12
THICK = 0.012


def gear_mesh(name, teeth, bore):
    rp = MODULE * teeth / 2
    ra, rd = rp + MODULE, rp - 1.25 * MODULE
    pitch = 2 * math.pi / teeth
    # Trapezoid teeth with backlash: half-widths as fractions of the pitch angle.
    root_half, tip_half = 0.30 * pitch, 0.13 * pitch
    outline = []
    for k in range(teeth):
        c = k * pitch
        for ang, r in ((c - pitch / 2, rd), (c - root_half, rd), (c - tip_half, ra),
                       (c + tip_half, ra), (c + root_half, rd)):
            outline.append((r * math.cos(ang), r * math.sin(ang)))
    # Closed ring solid: the bore ring uses the same angles as the outline, so each
    # outline segment gets one quad on the top, the bottom and both side walls.
    n = len(outline)
    angles = [math.atan2(y, x) for x, y in outline]
    verts = []
    for zz in (-THICK / 2, THICK / 2):
        verts += [(x, y, zz) for x, y in outline]
        verts += [(bore * math.cos(a), bore * math.sin(a), zz) for a in angles]
    ob_, ib_, ot_, it_ = 0, n, 2 * n, 3 * n
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((ob_ + j, ob_ + i, ib_ + i, ib_ + j))      # bottom (normal -z)
        faces.append((ot_ + i, ot_ + j, it_ + j, it_ + i))      # top (normal +z)
        faces.append((ob_ + i, ob_ + j, ot_ + j, ot_ + i))      # outer wall
        faces.append((ib_ + j, ib_ + i, it_ + i, it_ + j))      # bore wall
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    return me


def add(name, mesh, loc=(0, 0, 0), parent=None):
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    if parent:
        ob.parent = parent
    return ob


def box(name, size, loc):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return add(name, me, loc)


def cylinder(name, radius, depth, loc, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=radius, radius2=radius, depth=depth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return add(name, me, loc, parent)


def material(name, color, metallic, roughness, alpha=1.0):
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
    if bsdf is None:
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    return m


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    sc = bpy.context.scene
    sc.render.fps, sc.render.fps_base = FPS, 1.0
    sc.frame_start, sc.frame_end = 0, FRAMES - 1

    center = MODULE * (TEETH_A + TEETH_B) / 2     # 72 mm
    z = 0.030
    gear_a = add("gear_drive", gear_mesh("gear_drive", TEETH_A, 0.008), (0, 0, z))
    gear_b = add("pinion_driven", gear_mesh("pinion_driven", TEETH_B, 0.006), (center, 0, z))
    # Pinion phase: a gap of the pinion faces the gear tooth on the line of centres.
    phase_b = math.pi / TEETH_B
    shaft_a = cylinder("shaft_drive", 0.008, 0.050, (0, 0, 0), parent=gear_a)
    shaft_b = cylinder("shaft_driven", 0.006, 0.050, (0, 0, 0), parent=gear_b)
    base = box("base_housing", (0.18, 0.09, 0.008), (center / 2, 0, 0.004))
    cover = box("cover_window", (0.17, 0.08, 0.003), (center / 2, 0, 0.062))
    feet = [box(f"rubber_foot_{i}", (0.014, 0.014, 0.006), (x, y, -0.003))
            for i, (x, y) in enumerate([(-0.04, -0.035), (-0.04, 0.035), (0.112, -0.035), (0.112, 0.035)])]
    panel = box("carbon_back_panel", (0.18, 0.004, 0.06), (center / 2, 0.047, 0.034))

    mats = {gear_a: material("steel", (0.62, 0.62, 0.64), 1.0, 0.35),
            gear_b: material("bronze", (0.80, 0.55, 0.30), 1.0, 0.30),
            shaft_a: material("chrome", (0.9, 0.9, 0.9), 1.0, 0.05),
            shaft_b: material("chrome2", (0.9, 0.9, 0.9), 1.0, 0.05),
            base: material("paint_blue", (0.06, 0.18, 0.45), 0.0, 0.5),
            cover: material("cover", (0.9, 0.95, 1.0), 0.0, 0.05, alpha=0.2),
            panel: material("carbon", (0.03, 0.03, 0.03), 0.0, 0.3)}
    rubber = material("rubber", (0.02, 0.02, 0.02), 0.0, 0.9)
    for f in feet:
        mats[f] = rubber
    for ob, m in mats.items():
        ob.data.materials.append(m)

    # Motion: linear in time. The pinion angle is exactly -2x the gear angle.
    for ob, ratio, phase in ((gear_a, 1.0, 0.0), (gear_b, -2.0, phase_b)):
        ob.rotation_mode = "QUATERNION"
        for f in range(FRAMES):
            ang = phase + ratio * math.radians(GEAR_TURN_DEG) * f / (FRAMES - 1)
            ob.rotation_quaternion = (math.cos(ang / 2), 0, 0, math.sin(ang / 2))
            ob.keyframe_insert("rotation_quaternion", frame=f)

    cam_data = bpy.data.cameras.new("cam_export")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam_export", cam_data)
    sc.collection.objects.link(cam)
    cam.location = (0.30, -0.30, 0.22)
    cam.rotation_euler = (math.radians(62), 0, math.radians(45))

    glb = os.path.join(out_dir, "selftest-gears.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb, export_format="GLB", export_cameras=True, export_animations=True,
        export_animation_mode="SCENE", export_force_sampling=True, export_frame_step=1,
        export_frame_range=True, export_optimize_animation_size=False, export_anim_slide_to_zero=True,
        export_anim_scene_split_object=False, export_nla_strips_merged_animation_name="mechanism",
        export_apply=False, export_yup=True, export_extras=False, export_lights=False)
    sha = hashlib.sha256(open(glb, "rb").read()).hexdigest()
    parts = [{"name": ob.name} for ob in mats]
    # One explicit preset to exercise the manifest override path.
    for p in parts:
        if p["name"] == "pinion_driven":
            p["material"] = {"preset": "anodised_aluminium", "baseColor": [0.75, 0.42, 0.12]}
    manifest = {
        "format": "martygraphics.render-export/1",
        "engine": {"name": "MartyGraphics", "commit": "0000000",
                   "note": "self-test fixture built in Blender; not a MartyGraphics verified scene"},
        "scene": {"id": "selftest-gears-2to1", "title": "Self-test: 24/12 spur gears, 2:1"},
        "glb": {"file": os.path.basename(glb), "sha256": sha},
        "fps": FPS,
        "frameCount": FRAMES,
        "units": "meters",
        "upAxis": "Y",
        "posterFrame": FRAMES // 2,
        "parts": parts,
        "cameras": [{"name": "cam_export"}],
        "checks": {"ratio": "pinion angle = -2 x gear angle", "frames": FRAMES},
    }
    path = os.path.join(out_dir, "selftest-gears.manifest.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"MG_SELFTEST_EXPORT {path}")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) != 1:
        sys.exit("usage: blender -b --factory-startup -P selftest_scene.py -- <export-dir>")
    main(os.path.abspath(argv[0]))
