# SPDX-License-Identifier: Apache-2.0
"""Tests for the Blender render path helpers that run without Blender (tools/render-blender/mgrender)."""
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "render-blender"))

from mgrender import busyguard, faststart, presets  # noqa: E402
from mgrender import manifest as mf  # noqa: E402

FPS = 24


def make_glb(times, angles, extra_animation=False, child=True):
    """One parent node turning about +Y (glTF up) with an optional child offset along +X."""
    tbytes = struct.pack(f"<{len(times)}f", *times)
    rbytes = b"".join(struct.pack("<4f", 0.0, math.sin(a / 2), 0.0, math.cos(a / 2)) for a in angles)
    binary = tbytes + rbytes
    nodes = [{"name": "gear", "children": [1] if child else []}]
    if child:
        nodes.append({"name": "tooth_marker", "translation": [1.0, 0.0, 0.0]})
    anim = {"name": "mechanism", "samplers": [{"input": 0, "output": 1, "interpolation": "LINEAR"}],
            "channels": [{"sampler": 0, "target": {"node": 0, "path": "rotation"}}]}
    gltf = {
        "asset": {"version": "2.0"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(tbytes)},
                        {"buffer": 0, "byteOffset": len(tbytes), "byteLength": len(rbytes)}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(times), "type": "SCALAR",
                       "min": [min(times)], "max": [max(times)]},
                      {"bufferView": 1, "componentType": 5126, "count": len(angles), "type": "VEC4"}],
        "animations": [anim] + ([dict(anim, name="other")] if extra_animation else []),
    }
    js = json.dumps(gltf).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binary), 0x004E4942) + binary
    return struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body


class ExportFixture:
    def __init__(self, tmp, frames=5, **glb_kwargs):
        self.dir = Path(tmp)
        times = [f / FPS for f in range(frames)]
        angles = [math.radians(10 * f) for f in range(frames)]
        self.glb = self.dir / "scene.glb"
        self.glb.write_bytes(make_glb(times, angles, **glb_kwargs))
        self.manifest = {
            "format": mf.FORMAT,
            "engine": {"name": "MartyGraphics", "commit": "a" * 40},
            "scene": {"id": "unit-gear"},
            "glb": {"file": "scene.glb", "sha256": hashlib.sha256(self.glb.read_bytes()).hexdigest()},
            "fps": FPS, "frameCount": frames,
            "parts": [{"name": "gear"}],
        }
        self.write()

    def write(self):
        self.path = self.dir / "scene.manifest.json"
        self.path.write_text(json.dumps(self.manifest))
        return str(self.path)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_valid_export_passes_and_labels(self):
        fx = ExportFixture(self.tmp.name)
        c = mf.verify(fx.write())
        self.assertEqual(c["frame_count"], 5)
        self.assertEqual(c["animated_nodes"], [0])
        self.assertEqual(mf.provenance_label(c), "Rendered in Blender Cycles from a verified MartyGraphics "
                         f"export (engine {'a' * 40}, scene unit-gear)")

    def test_refuses_sha_mismatch(self):
        fx = ExportFixture(self.tmp.name)
        data = bytearray(fx.glb.read_bytes())
        data[-1] ^= 1
        fx.glb.write_bytes(bytes(data))
        with self.assertRaisesRegex(mf.ExportError, "SHA-256 mismatch"):
            mf.verify(fx.write())

    def test_refuses_frame_count_mismatch(self):
        fx = ExportFixture(self.tmp.name)
        fx.manifest["frameCount"] = 6
        with self.assertRaisesRegex(mf.ExportError, "frame count mismatch"):
            mf.verify(fx.write())

    def test_refuses_fps_mismatch(self):
        fx = ExportFixture(self.tmp.name)
        fx.manifest["fps"] = 30          # keys at k/24 s are off the 30 fps grid
        with self.assertRaisesRegex(mf.ExportError, "frame grid"):
            mf.verify(fx.write())

    def test_refuses_non_integer_fps_and_bad_commit(self):
        fx = ExportFixture(self.tmp.name)
        fx.manifest["fps"] = 23.976
        with self.assertRaisesRegex(mf.ExportError, "fps"):
            mf.verify(fx.write())
        fx.manifest["fps"] = FPS
        fx.manifest["engine"]["commit"] = "main"
        with self.assertRaisesRegex(mf.ExportError, "engine.commit"):
            mf.verify(fx.write())

    def test_refuses_escaping_glb_path(self):
        fx = ExportFixture(self.tmp.name)
        fx.manifest["glb"]["file"] = "../scene.glb"
        with self.assertRaisesRegex(mf.ExportError, "relative path"):
            mf.verify(fx.write())

    def test_refuses_two_animations_and_unknown_part(self):
        fx = ExportFixture(self.tmp.name, extra_animation=True)
        with self.assertRaisesRegex(mf.ExportError, "exactly one animation"):
            mf.verify(fx.write())
        fx = ExportFixture(self.tmp.name)
        fx.manifest["parts"].append({"name": "missing_part"})
        with self.assertRaisesRegex(mf.ExportError, "missing_part"):
            mf.verify(fx.write())

    def test_part_fields_from_the_exporter(self):
        fx = ExportFixture(self.tmp.name)
        fx.manifest["parts"] = [{"name": "gear", "label": "Sun gear 1", "gltfMaterial": "steel", "material": {}}]
        mf.verify(fx.write())
        for empty in (None, "", {}):
            fx.manifest["parts"][0]["material"] = empty
            mf.verify(fx.write())
        bad = [({"label": 7}, "label must be a string"),
               ({"material": {"preset": "gold_leaf"}}, "unknown material preset"),
               ({"material": {"baseColor": [1, 0]}}, "baseColor"),
               ({"material": "glass"}, "material must be an object")]
        for extra, message in bad:
            fx.manifest["parts"] = [dict({"name": "gear"}, **extra)]
            with self.assertRaisesRegex(mf.ExportError, message):
                mf.verify(fx.write())

    def test_world_matrices_follow_parent_rotation(self):
        fx = ExportFixture(self.tmp.name)
        c = mf.verify(fx.write())
        world = mf.world_matrices(c["gltf"], c["animation"], 3 / FPS)      # gear at 30 deg about +Y
        x, y, z = (world[1][i][3] for i in range(3))
        self.assertAlmostEqual(x, math.cos(math.radians(30)), places=6)
        self.assertAlmostEqual(z, -math.sin(math.radians(30)), places=6)
        self.assertAlmostEqual(y, 0.0, places=6)
        # Halfway between keys: linear slerp gives 25 deg.
        world = mf.world_matrices(c["gltf"], c["animation"], 2.5 / FPS)
        self.assertAlmostEqual(world[1][0][3], math.cos(math.radians(25)), places=6)

    def test_axis_conversion_matches_blender_importer(self):
        m = mf.trs_matrix((1.0, 2.0, 3.0), (0, 0, 0, 1), (1, 1, 1))
        b = mf.to_blender(m)
        self.assertEqual([b[i][3] for i in range(3)], [1.0, -3.0, 2.0])


def box(kind, payload):
    return struct.pack(">I4s", 8 + len(payload), kind) + payload


class FaststartTests(unittest.TestCase):
    def test_moves_moov_and_fixes_offsets(self):
        ftyp = box(b"ftyp", b"isom\0\0\0\0isom")
        media = b"FRAME-ONE" + b"FRAME-TWO"
        mdat = box(b"mdat", media)
        first = len(ftyp) + 8
        stco = lambda offsets: box(b"stco", struct.pack(">II", 0, len(offsets)) +  # noqa: E731
                                   b"".join(struct.pack(">I", o) for o in offsets))
        moov = box(b"moov", box(b"trak", box(b"mdia", box(b"minf", box(b"stbl", stco([first, first + 9]))))))
        data = ftyp + mdat + moov
        self.assertFalse(faststart.is_faststart(data))
        out = faststart.faststart_bytes(data)
        self.assertTrue(faststart.is_faststart(out))
        self.assertEqual(len(out), len(data))
        idx = out.index(b"stco")
        o1, o2 = struct.unpack_from(">II", out, idx + 4 + 8)
        self.assertEqual(out[o1:o1 + 9], b"FRAME-ONE")
        self.assertEqual(out[o2:o2 + 9], b"FRAME-TWO")
        self.assertIs(faststart.faststart_bytes(out), out)


class BusyguardTests(unittest.TestCase):
    def test_off_unless_configured(self):
        cfg = busyguard.Config.from_env(env={})
        self.assertFalse(cfg.enabled)
        self.assertEqual(busyguard.status(cfg), (True, []))

    def test_env_and_options_combine(self):
        env = {"BUSY_LOCK_PATH": os.pathsep.join(["/a.lock", "/b.lock"]), "BUSY_PROCESS_PATTERN": "x"}
        cfg = busyguard.Config.from_env(["/c.lock"], None, "true", env=env)
        self.assertEqual(cfg.locks, ["/a.lock", "/b.lock", "/c.lock"])
        self.assertEqual((cfg.pattern, cfg.command), ("x", "true"))

    def test_detects_matching_processes(self):
        with tempfile.TemporaryDirectory() as proc:
            for pid, cmd in ((101, b"/opt/sim/bin/heavy-sim\0--world\0a"),
                             (102, b"python3\0/usr/lib/heavy-sim/runner.py\0--fast"),
                             (103, b"blender\0-b\0-P\0render.py"),
                             (104, b"grep\0-rn\0heavy-simulation-notes")):
                os.makedirs(f"{proc}/{pid}")
                Path(f"{proc}/{pid}/cmdline").write_bytes(cmd)
            pids = sorted(p for p, _ in busyguard.running_processes(r"(^|/)heavy-sim(/|\b(?!-))", proc))
            self.assertEqual(pids, [101, 102])

    def test_reads_held_lock_without_locking(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "busy.lock"
            lock.write_text("")
            st = os.stat(lock)
            dev = f"{os.major(st.st_dev):02x}:{os.minor(st.st_dev):02x}:{st.st_ino}"
            table = Path(tmp) / "locks"
            table.write_text(f"1: FLOCK  ADVISORY  WRITE 4242 {dev} 0 EOF\n")
            self.assertEqual(busyguard.held_locks([str(lock)], str(table)), [str(lock)])
            table.write_text("1: FLOCK  ADVISORY  WRITE 4242 00:01:1 0 EOF\n")
            self.assertEqual(busyguard.held_locks([str(lock)], str(table)), [])

    def test_command_exit_status(self):
        busy, why = busyguard.command_busy(f"{sys.executable} -c \"print('job running')\"")
        self.assertTrue(busy)
        self.assertIn("job running", why)
        busy, _ = busyguard.command_busy(f"{sys.executable} -c \"import sys; sys.exit(1)\"")
        self.assertFalse(busy)

    def test_bad_settings_are_refused_not_ignored(self):
        self.assertTrue(busyguard.Config(pattern="(").problems())
        with tempfile.TemporaryDirectory() as tmp:
            no_proc = os.path.join(tmp, "missing")
            self.assertTrue(busyguard.Config(locks=["/x.lock"]).problems(proc=no_proc))
            self.assertEqual(busyguard.Config(command="true").problems(proc=no_proc), [])


class PresetTests(unittest.TestCase):
    PARAMS = {"color": None, "metallic": 0.0, "roughness": 0.5, "alpha": 1.0, "transmission": 0.0,
              "textured": False}

    def test_name_rules(self):
        cases = {"cover_window": "glass", "rubber_foot_2": "rubber", "carbon_back_panel": "carbon_fibre",
                 "lp_shaft": "polished_metal", "bearing_outer": "polished_metal", "fan_blade_03": "brushed_metal",
                 "motor_arm": "anodised_aluminium", "nacelle": "painted_metal"}
        for name, want in cases.items():
            self.assertEqual(presets.choose_preset(name, self.PARAMS)[0], want, name)

    def test_label_comes_before_the_node_name(self):
        # Exporter node names are part ids; the readable name is the manifest label.
        self.assertEqual(presets.choose_preset("p07", self.PARAMS, label="Output shaft"),
                         ("polished_metal", "label contains 'shaft'"))
        self.assertEqual(presets.choose_preset("cover_3", self.PARAMS, label="Sun gear 1"),
                         ("brushed_metal", "label contains 'sun'"))
        # No rule in the label: the node name rules still apply.
        self.assertEqual(presets.choose_preset("planet1a", self.PARAMS, label="Part 12"),
                         ("brushed_metal", "name contains 'planet'"))
        self.assertEqual(presets.choose_preset("sun1", self.PARAMS, label=None)[0], "brushed_metal")
        # The manifest preset still wins over the label.
        self.assertEqual(presets.choose_preset("sun1", self.PARAMS, "glass", label="Sun gear 1"),
                         ("glass", "manifest"))

    def test_exporter_material_name_comes_before_the_label(self):
        # The exporter colour-codes the spools: the material name must win over "shaft" in the label.
        self.assertEqual(presets.choose_preset("lpShaft", self.PARAMS, label="LP shaft (N1)",
                                               gltf_material="anodized.blue"),
                         ("anodised_aluminium", "gltfMaterial contains 'anodiz'"))
        cases = {"polishedSteel": "polished_metal", "darkSteel": "brushed_metal", "brass": "brushed_metal",
                 "titanium": "brushed_metal", "composite": "carbon_fibre", "ceramic": "plastic",
                 "plastic.white": "plastic"}
        for material, want in cases.items():
            self.assertEqual(presets.choose_preset("n", self.PARAMS, label="Nacelle (inlet and fan cowl)",
                                                   gltf_material=material)[0], want, material)
        # A material name without a rule falls through to the label.
        self.assertEqual(presets.choose_preset("n", self.PARAMS, label="Nacelle", gltf_material="mat_07"),
                         ("painted_metal", "label contains 'nacelle'"))

    def test_empty_material_means_no_override(self):
        for empty in (None, "", {}):
            self.assertEqual(presets.part_material({"name": "x", "material": empty}), {})
        self.assertEqual(presets.part_material({"name": "x"}), {})
        self.assertEqual(presets.part_material({"name": "x", "material": {"preset": "rubber"}}),
                         {"preset": "rubber"})

    def test_manifest_override_and_material_fallback(self):
        self.assertEqual(presets.choose_preset("gear", self.PARAMS, "glass"), ("glass", "manifest"))
        with self.assertRaises(ValueError):
            presets.choose_preset("gear", self.PARAMS, "gold_leaf")
        self.assertEqual(presets.choose_preset("x1", dict(self.PARAMS, metallic=1.0, roughness=0.1))[0],
                         "polished_metal")
        self.assertEqual(presets.choose_preset("x1", dict(self.PARAMS, alpha=0.3))[0], "glass")


if __name__ == "__main__":
    unittest.main()
