# SPDX-License-Identifier: Apache-2.0
"""Cosmetic look-dev for an imported export (runs inside Blender).

Rule: this module adds new objects (world, backdrop, lights, camera rig) and
replaces material slots. It never changes an imported object's transform,
animation, parenting or mesh data. render.py proves that after setup.
"""
import math

import bpy
from mathutils import Matrix, Vector

PRESETS = {
    "preview": {"resolution": (1280, 720), "samples": 48, "adaptive_threshold": 0.05, "min_samples": 8,
                "look": "AgX - Base Contrast", "orbit_degrees": 40.0, "elevation_deg": 22.0, "lens_mm": 50.0,
                "shutter": 0.5, "bounces": 8, "transmission_bounces": 8},
    "hero": {"resolution": (1920, 1080), "samples": 512, "adaptive_threshold": 0.01, "min_samples": 32,
             "look": "AgX - Medium High Contrast", "orbit_degrees": 40.0, "elevation_deg": 22.0, "lens_mm": 65.0,
             "shutter": 0.5, "bounces": 12, "transmission_bounces": 12},
}
RESOLUTIONS = {"720p": (1280, 720), "1080p": (1920, 1080), "1440p": (2560, 1440), "4k": (3840, 2160)}

from .presets import MATERIAL_PRESETS, NAME_RULES, choose_preset, part_material  # noqa: F401 (re-exported)


# ----------------------------------------------------------------- helpers
def _set(node, name, value):
    sock = node.inputs.get(name)
    if sock is not None:
        sock.default_value = value


def _principled_params(mat):
    """Read base colour, metallic, roughness, alpha, transmission and texture use from an imported material."""
    out = {"color": None, "metallic": 0.0, "roughness": 0.5, "alpha": 1.0, "transmission": 0.0, "textured": False}
    if not mat or not mat.node_tree:
        return out
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            out["textured"] = True
        if n.type == "BSDF_PRINCIPLED":
            out["color"] = tuple(n.inputs["Base Color"].default_value)[:3]
            out["metallic"] = n.inputs["Metallic"].default_value
            out["roughness"] = n.inputs["Roughness"].default_value
            out["alpha"] = n.inputs["Alpha"].default_value
            t = n.inputs.get("Transmission Weight")
            out["transmission"] = t.default_value if t else 0.0
    return out


def _new_material(name):
    m = bpy.data.materials.new(name)
    if not m.node_tree:
        m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m, nt, bsdf


def _noise_roughness(nt, bsdf, lo, hi, scale):
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = 6.0
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], tex.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = lo
    ramp.inputs["To Max"].default_value = hi
    nt.links.new(tex.outputs["Fac"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], bsdf.inputs["Roughness"])


def build_material(preset, color, size):
    """Make one preset material. size is the subject size in metres (sets texture scales)."""
    m, nt, bsdf = _new_material(f"mg_{preset}")
    c = tuple(color) if color else None
    feature = max(size, 1e-4)
    if preset == "polished_metal":
        _set(bsdf, "Base Color", (*(c or (0.92, 0.92, 0.93)), 1))
        _set(bsdf, "Metallic", 1.0)
        _set(bsdf, "Roughness", 0.06)
    elif preset == "brushed_metal":
        _set(bsdf, "Base Color", (*(c or (0.70, 0.70, 0.72)), 1))
        _set(bsdf, "Metallic", 1.0)
        _set(bsdf, "Anisotropic", 0.65)
        tan = nt.nodes.new("ShaderNodeTangent")
        tan.direction_type = "RADIAL"
        tan.axis = "Z"
        nt.links.new(tan.outputs["Tangent"], bsdf.inputs["Tangent"])
        _noise_roughness(nt, bsdf, 0.22, 0.34, 40.0 / feature)
    elif preset == "painted_metal":
        _set(bsdf, "Base Color", (*(c or (0.10, 0.22, 0.48)), 1))
        _set(bsdf, "Metallic", 0.0)
        _set(bsdf, "Roughness", 0.42)
        _set(bsdf, "Coat Weight", 0.6)
        _set(bsdf, "Coat Roughness", 0.06)
    elif preset == "anodised_aluminium":
        _set(bsdf, "Base Color", (*(c or (0.30, 0.42, 0.62)), 1))
        _set(bsdf, "Metallic", 1.0)
        _noise_roughness(nt, bsdf, 0.18, 0.26, 25.0 / feature)
    elif preset == "rubber":
        _set(bsdf, "Base Color", (*(c or (0.025, 0.025, 0.025)), 1))
        _set(bsdf, "Metallic", 0.0)
        _set(bsdf, "Roughness", 0.85)
        _set(bsdf, "Specular IOR Level", 0.3)
        _set(bsdf, "Sheen Weight", 0.15)
    elif preset == "carbon_fibre":
        # Twill-like weave: a checker in object space, about 60 cells per subject size.
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(45))
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
        chk = nt.nodes.new("ShaderNodeTexChecker")
        chk.inputs["Scale"].default_value = 60.0 / feature
        chk.inputs["Color1"].default_value = (0.012, 0.012, 0.013, 1)
        chk.inputs["Color2"].default_value = (0.045, 0.045, 0.05, 1)
        nt.links.new(mapping.outputs["Vector"], chk.inputs["Vector"])
        nt.links.new(chk.outputs["Color"], bsdf.inputs["Base Color"])
        _set(bsdf, "Metallic", 0.0)
        _set(bsdf, "Roughness", 0.35)
        _set(bsdf, "Anisotropic", 0.5)
        _set(bsdf, "Coat Weight", 1.0)
        _set(bsdf, "Coat Roughness", 0.03)
    elif preset == "glass":
        _set(bsdf, "Base Color", (*(c or (0.97, 0.98, 1.0)), 1))
        _set(bsdf, "Metallic", 0.0)
        _set(bsdf, "Roughness", 0.02)
        _set(bsdf, "IOR", 1.5)
        _set(bsdf, "Transmission Weight", 1.0)
    else:  # plastic
        _set(bsdf, "Base Color", (*(c or (0.5, 0.5, 0.5)), 1))
        _set(bsdf, "Roughness", 0.4)
    m["mg_preset"] = preset
    return m


def assign_materials(objects, parts, size):
    """Replace material slots (object-linked) with preset materials.

    parts maps a node name to its manifest part (with optional 'label' and 'material').
    Return {object name: [(preset, reason), ...]}."""
    cache, report = {}, {}
    for ob in objects:
        if ob.type != "MESH":
            continue
        part = parts.get(ob.name, {})
        override = part_material(part)
        label = part.get("label")
        if not ob.material_slots:
            # A mesh without materials gets one slot. This changes the material list only,
            # never vertex positions (render.py hashes the vertices before and after).
            ob.data.materials.append(None)
        slots = ob.material_slots
        decisions = []
        for i, slot in enumerate(slots):
            params = _principled_params(slot.material)
            if params["textured"] and not override.get("preset"):
                decisions.append(("imported_textured", "kept imported textured material"))
                continue
            gltf_material = part.get("gltfMaterial") or (slot.material.name if slot.material else None)
            preset, reason = choose_preset(ob.name, params, override.get("preset"), label, gltf_material)
            color = override.get("baseColor")
            if color is None and preset not in ("glass", "carbon_fibre", "rubber"):
                color = params["color"]       # keep the exported colour coding (e.g. N1 blue, N2 orange)
            key = (preset, tuple(round(v, 4) for v in color) if color else None)
            if key not in cache:
                cache[key] = build_material(preset, color, size)
            slot.link = "OBJECT"
            slot.material = cache[key]
            decisions.append((preset, reason))
        report[ob.name] = decisions
    return report


# ----------------------------------------------------------------- bounds
def subject_bounds(objects, scene, frames):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    meshes = [o for o in objects if o.type == "MESH"]
    for f in frames:
        scene.frame_set(f)
        for ob in meshes:
            for corner in ob.bound_box:
                p = ob.matrix_world @ Vector(corner)
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
    if not meshes:
        raise ValueError("export has no mesh objects")
    return lo, hi


# ----------------------------------------------------------------- world and stage
def setup_world(scene, hdri_path, backdrop_color, strength=1.0, hide_hdri_from_camera=True):
    world = bpy.data.worlds.new("mg_world")
    scene.world = world
    if not world.node_tree:
        world.use_nodes = True
    nt = world.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    env_bg = nt.nodes.new("ShaderNodeBackground")
    env_bg.inputs["Strength"].default_value = strength
    if hdri_path:
        env = nt.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(hdri_path, check_existing=True)
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Rotation"].default_value = (0, 0, math.radians(120))
        coord = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
        nt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
        nt.links.new(env.outputs["Color"], env_bg.inputs["Color"])
    else:
        sky = nt.nodes.new("ShaderNodeTexGradient")
        sky.gradient_type = "SPHERICAL"
        nt.links.new(sky.outputs["Color"], env_bg.inputs["Color"])
    if hide_hdri_from_camera:
        cam_bg = nt.nodes.new("ShaderNodeBackground")
        cam_bg.inputs["Color"].default_value = (*backdrop_color, 1)
        cam_bg.inputs["Strength"].default_value = 1.0
        lp = nt.nodes.new("ShaderNodeLightPath")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
        nt.links.new(env_bg.outputs["Background"], mix.inputs[1])
        nt.links.new(cam_bg.outputs["Background"], mix.inputs[2])
        nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    else:
        nt.links.new(env_bg.outputs["Background"], out.inputs["Surface"])
    return world


def _link(scene, ob):
    scene.collection.objects.link(ob)
    return ob


def cyclorama(scene, lo, hi, color, camera_positions):
    """A round studio bowl: a flat floor that curves up into a wall all around the subject.

    It is sized so that every camera position of the shot stays inside the flat floor, so
    an orbiting or swinging camera (export or auto) always sees the wall behind the subject.
    The bowl shows only to camera and transmission rays and casts no shadow: it does not
    block the exported lights, and reflections still see the HDRI. It still receives the
    subject's shadows (contact shadows on the floor).
    """
    import bmesh
    size = max((hi - lo).length, 1e-4)
    c = (lo + hi) / 2
    z0 = lo.z - 0.002 * size
    reach = max([(Vector((p.x, p.y)) - Vector((c.x, c.y))).length for p in camera_positions] + [size])
    top = max([p.z for p in camera_positions] + [hi.z])
    floor_r = 1.25 * reach + 0.5 * size
    curve_r = 0.35 * floor_r
    wall = max(2.0 * (top - z0), 1.5 * floor_r)
    profile = [(0.0, z0), (floor_r, z0)]
    for i in range(1, 17):
        a = math.radians(90 * i / 16)
        profile.append((floor_r + curve_r * math.sin(a), z0 + curve_r * (1 - math.cos(a))))
    profile.append((floor_r + curve_r, z0 + curve_r + wall))
    seg = 96
    bm = bmesh.new()
    rings = []
    for r, z in profile[1:]:
        rings.append([bm.verts.new((c.x + r * math.cos(2 * math.pi * k / seg),
                                    c.y + r * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)])
    centre = bm.verts.new((c.x, c.y, z0))
    for k in range(seg):
        bm.faces.new((centre, rings[0][k], rings[0][(k + 1) % seg]))
    for ra, rb in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((ra[k], rb[k], rb[(k + 1) % seg], ra[(k + 1) % seg]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:            # normals point inward, towards the subject
        if f.normal.dot(Vector((c.x, c.y, z0 + curve_r)) - f.calc_center_median()) < 0:
            f.normal_flip()
    me = bpy.data.meshes.new("mg_backdrop")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = _link(scene, bpy.data.objects.new("mg_backdrop", me))
    ob.visible_shadow = False
    ob.visible_glossy = False
    ob.visible_diffuse = False
    ob.visible_volume_scatter = False
    m, nt, bsdf = _new_material("mg_backdrop")
    _set(bsdf, "Base Color", (*color, 1))
    _set(bsdf, "Roughness", 0.6)
    _set(bsdf, "Specular IOR Level", 0.2)
    me.materials.append(m)
    return ob, {"floor_radius_m": floor_r, "wall_height_m": wall}


def camera_positions(scene, cam, frames):
    out = []
    for f in frames:
        scene.frame_set(f)
        out.append(cam.matrix_world.translation.copy())
    return out


def shadow_catcher(scene, lo, hi):
    size = max((hi - lo).length, 1e-4)
    bpy.ops.mesh.primitive_plane_add(size=40 * size, location=((lo.x + hi.x) / 2, (lo.y + hi.y) / 2,
                                                                 lo.z - 0.002 * size))
    ob = bpy.context.active_object
    ob.name = "mg_shadow_catcher"
    ob.is_shadow_catcher = True
    # Reflections and refractions of a catcher show its holdout as dark smudges in glass and metal.
    ob.visible_glossy = False
    ob.visible_transmission = False
    return ob


def key_light(scene, center, size, camera_dir):
    """A soft area key light, up and to the camera's left."""
    data = bpy.data.lights.new("mg_key", "AREA")
    data.shape = "DISK"
    data.size = 2.0 * size
    data.energy = 900.0 * size * size
    ob = _link(scene, bpy.data.objects.new("mg_key", data))
    side = camera_dir.cross(Vector((0, 0, 1))).normalized()
    ob.location = center - camera_dir * 2.5 * size + side * 2.5 * size + Vector((0, 0, 3.0 * size))
    ob.rotation_euler = (center - ob.location).to_track_quat("-Z", "Y").to_euler()
    return ob


# ----------------------------------------------------------------- camera
def _focus_fstop(lens_mm, distance_m, depth_m, sensor_mm=36.0):
    """Aperture that keeps about depth_m in focus at distance_m (thin-lens approximation)."""
    coc = 0.03 * sensor_mm / 36.0
    s, f = distance_m * 1000.0, lens_mm
    n = depth_m * 1000.0 * f * f / (2.0 * coc * s * s)
    return max(1.4, min(22.0, n))


def fit_distance(lo, hi, hfov, vfov, elev, azimuths, fill=0.86):
    """Smallest camera distance at which all 8 corners of the motion bounds stay inside
    `fill` of the frame for every sampled orbit azimuth (camera aimed at the bounds centre)."""
    center = (lo + hi) / 2
    corners = [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    tx, ty = math.tan(hfov / 2) * fill, math.tan(vfov / 2) * fill

    def fits(d):
        for az in azimuths:
            # Camera offset before the pivot rotation is (0, -cos e, sin e) * d.
            off = Matrix.Rotation(az, 3, "Z") @ Vector((0.0, -math.cos(elev), math.sin(elev)))
            pos = center + off * d
            fwd = (center - pos).normalized()
            right = fwd.cross(Vector((0, 0, 1))).normalized()
            up = right.cross(fwd)
            for c in corners:
                v = c - pos
                z = v.dot(fwd)
                if z <= 0 or abs(v.dot(right) / z) > tx or abs(v.dot(up) / z) > ty:
                    return False
        return True

    radius = max((hi - lo).length / 2, 1e-4)
    a, b = 0.05 * radius, 200.0 * radius
    if not fits(b):
        return b
    for _ in range(60):
        mid = (a + b) / 2
        a, b = (a, mid) if fits(mid) else (mid, b)
    return b


def auto_orbit_camera(scene, lo, hi, frame_start, frame_end, preset):
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1e-4)
    res_x, res_y = scene.render.resolution_x, scene.render.resolution_y
    data = bpy.data.cameras.new("mg_orbit_camera")
    data.lens = preset["lens_mm"]
    data.sensor_fit = "HORIZONTAL"
    data.sensor_width = 36.0
    hfov = 2 * math.atan(18.0 / data.lens)
    vfov = 2 * math.atan(math.tan(hfov / 2) * res_y / res_x)
    elev = math.radians(preset["elevation_deg"])
    start_az = math.radians(-35.0)
    sweep = math.radians(preset["orbit_degrees"])
    azimuths = [start_az + sweep * i / 8 for i in range(9)]
    distance = fit_distance(lo, hi, hfov, vfov, elev, azimuths)
    data.clip_start = max(distance - 4 * radius, distance * 0.01)
    data.clip_end = distance + 60 * radius
    pivot = _link(scene, bpy.data.objects.new("mg_orbit_pivot", None))
    pivot.location = center
    cam = _link(scene, bpy.data.objects.new("mg_orbit_camera", data))
    cam.parent = pivot
    cam.location = (0.0, -distance * math.cos(elev), distance * math.sin(elev))
    track = cam.constraints.new("TRACK_TO")
    track.target = pivot
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    pivot.rotation_euler = (0, 0, start_az)
    pivot.keyframe_insert("rotation_euler", index=2, frame=frame_start)
    pivot.rotation_euler = (0, 0, start_az + sweep)
    pivot.keyframe_insert("rotation_euler", index=2, frame=max(frame_end, frame_start + 1))
    _linear(pivot)
    scene.camera = cam
    focus = _link(scene, bpy.data.objects.new("mg_focus", None))
    focus.location = center
    data.dof.use_dof = True
    data.dof.focus_object = focus
    data.dof.aperture_fstop = _focus_fstop(data.lens, distance, 1.3 * 2 * radius)
    view_dir = (center - (Matrix.Rotation(start_az, 4, "Z") @ Vector(cam.location) + center)).normalized()
    return cam, {"mode": "auto-orbit", "distance_m": distance, "fstop": data.dof.aperture_fstop,
                 "lens_mm": data.lens, "sweep_deg": preset["orbit_degrees"]}, view_dir


def _linear(ob):
    ad = ob.animation_data
    if not ad or not ad.action:
        return
    try:
        curves = ad.action.fcurves
    except AttributeError:   # slotted actions (Blender 4.4+)
        from bpy_extras import anim_utils
        curves = anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def export_camera(scene, cam, lo, hi, lens_override=None):
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1e-4)
    scene.camera = cam
    focus = _link(scene, bpy.data.objects.new("mg_focus", None))
    focus.location = center
    data = cam.data
    data.dof.use_dof = True
    data.dof.focus_object = focus
    distance = (cam.matrix_world.translation - center).length
    data.dof.aperture_fstop = _focus_fstop(data.lens, distance, 1.3 * 2 * radius, data.sensor_width)
    view_dir = (center - cam.matrix_world.translation).normalized()
    return cam, {"mode": "export", "name": cam.name, "distance_m": distance,
                 "fstop": data.dof.aperture_fstop, "lens_mm": data.lens}, view_dir


# ----------------------------------------------------------------- render settings
def configure_render(scene, preset, resolution, device_info, motion_blur, samples=None):
    scene.render.engine = "CYCLES"
    from . import device
    device.apply_to_scene(scene, device_info)
    cy = scene.cycles
    cy.samples = samples or preset["samples"]
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = preset["adaptive_threshold"]
    cy.adaptive_min_samples = preset["min_samples"]
    cy.use_denoising = True
    cy.denoiser = "OPTIX" if device_info["backend"] == "OPTIX" else "OPENIMAGEDENOISE"
    try:
        cy.denoising_input_passes = "RGB_ALBEDO_NORMAL"
        cy.denoising_use_gpu = device_info["backend"] != "CPU"
    except (AttributeError, TypeError):
        pass
    cy.max_bounces = preset["bounces"]
    cy.transmission_bounces = preset["transmission_bounces"]
    cy.blur_glossy = 1.0
    cy.caustics_reflective = False
    cy.caustics_refractive = False
    cy.seed = 0
    cy.use_animated_seed = True
    scene.render.use_persistent_data = True
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.use_motion_blur = motion_blur
    scene.render.motion_blur_shutter = preset["shutter"]
    scene.render.motion_blur_position = "CENTER"
    vs = scene.view_settings
    vs.view_transform = "AgX"
    vs.look = preset["look"]
    vs.exposure = 0.0
    vs.gamma = 1.0
    scene.display_settings.display_device = "sRGB"
    ims = scene.render.image_settings
    ims.media_type = "IMAGE"
    ims.file_format = "PNG"
    ims.color_mode = "RGBA" if scene.render.film_transparent else "RGB"
    ims.color_depth = "16" if preset is PRESETS["hero"] else "8"
    ims.compression = 15


def provenance_metadata(scene, label):
    """PNG text metadata: only the provenance note (no date, host, file path or other stamp fields)."""
    r = scene.render
    for attr in dir(r):
        if attr.startswith("use_stamp") and attr not in ("use_stamp",):
            try:
                setattr(r, attr, False)
            except (AttributeError, TypeError):
                pass
    r.use_stamp = False          # metadata only; no burn-in on the master frames
    r.use_stamp_note = True
    r.stamp_note_text = label
