# SPDX-License-Identifier: Apache-2.0
"""Pure-Python check of a MartyGraphics render export (.glb + manifest JSON).

No Blender and no third-party modules, so CI and any host can run it:

    python3 -m mgrender.manifest <manifest.json>

The check refuses (raises ExportError) when the .glb SHA-256, the fps or the
frame count do not match the manifest, or when the baked animation is not on
the frame grid. It also evaluates the glTF node world matrices at any frame, so
render.py can prove that Blender shows the exported motion unchanged.
"""
import hashlib
import json
import math
import os
import re
import struct
import sys

FORMAT = "martygraphics.render-export/1"
GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
GRID_TOLERANCE = 1e-3          # frames; a baked key must sit on t = k / fps
NAME_LIMIT = 63                 # Blender object-name byte limit


class ExportError(ValueError):
    """The export is not safe to render. The message says why."""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 20:
        raise ExportError("GLB is too short")
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC or version != 2:
        raise ExportError("not a glTF 2.0 binary (.glb)")
    if length != len(data):
        raise ExportError(f"GLB header length {length} differs from file size {len(data)}")
    gltf, binary, offset = None, b"", 12
    while offset + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + clen]
        if ctype == CHUNK_JSON and gltf is None:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == CHUNK_BIN and not binary:
            binary = chunk
        offset += 8 + clen
    if gltf is None:
        raise ExportError("GLB has no JSON chunk")
    if not str(gltf.get("asset", {}).get("version", "")).startswith("2."):
        raise ExportError("glTF asset.version is not 2.x")
    return gltf, binary


_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
_CTYPES = {5126: ("f", 4, None), 5120: ("b", 1, 127.0), 5121: ("B", 1, 255.0),
           5122: ("h", 2, 32767.0), 5123: ("H", 2, 65535.0)}


def read_accessor(gltf, binary, index):
    """Return the accessor as a list of tuples of floats (normalized ints decoded)."""
    acc = gltf["accessors"][index]
    if "sparse" in acc or "bufferView" not in acc:
        raise ExportError(f"accessor {index}: sparse or bufferless accessors are not supported")
    view = gltf["bufferViews"][acc["bufferView"]]
    if view.get("buffer", 0) != 0 or "uri" in gltf["buffers"][view.get("buffer", 0)]:
        raise ExportError(f"accessor {index}: data must be in the GLB binary chunk")
    fmt, size, norm = _CTYPES.get(acc["componentType"], (None, 0, None))
    if fmt is None:
        raise ExportError(f"accessor {index}: unsupported component type {acc['componentType']}")
    if norm is not None and not acc.get("normalized", False):
        raise ExportError(f"accessor {index}: integer data must be normalized")
    n = _COMPONENTS[acc["type"]]
    stride = view.get("byteStride") or n * size
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        vals = struct.unpack_from("<" + fmt * n, binary, base + i * stride)
        out.append(tuple(max(v / norm, -1.0) if norm else float(v) for v in vals))
    return out


# ---------------------------------------------------------------- matrices
def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def trs_matrix(t, r, s):
    x, y, z, w = r
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    rot = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
           [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
           [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    m = [[rot[i][j] * s[j] for j in range(3)] + [t[i]] for i in range(3)]
    return m + [[0.0, 0.0, 0.0, 1.0]]


def column_major(values):
    return [[values[c * 4 + r] for c in range(4)] for r in range(4)]


# Blender's glTF importer maps glTF (Y up) to Blender (Z up): (x, y, z) -> (x, -z, y).
GLTF_TO_BLENDER = [[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]]
BLENDER_TO_GLTF = [[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]]


def to_blender(m):
    return mat_mul(mat_mul(GLTF_TO_BLENDER, m), BLENDER_TO_GLTF)


# ---------------------------------------------------------------- animation
def _slerp(a, b, u):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = tuple(-v for v in b), -dot
    if dot > 0.9995:
        q = tuple(x + u * (y - x) for x, y in zip(a, b))
    else:
        th = math.acos(min(dot, 1.0))
        sa, sb = math.sin((1 - u) * th) / math.sin(th), math.sin(u * th) / math.sin(th)
        q = tuple(sa * x + sb * y for x, y in zip(a, b))
    n = math.sqrt(sum(v * v for v in q)) or 1.0
    return tuple(v / n for v in q)


class Animation:
    """One glTF animation, decoded: per node, per path, (times, values, interpolation)."""

    def __init__(self, gltf, binary, index):
        anim = gltf["animations"][index]
        self.name = anim.get("name", f"animation_{index}")
        self.channels = {}
        self.times = set()
        for ch in anim["channels"]:
            target = ch["target"]
            path = target.get("path")
            if "node" not in target or path not in ("translation", "rotation", "scale"):
                raise ExportError(f"animation '{self.name}': only node TRS channels are supported (got {path})")
            sampler = anim["samplers"][ch["sampler"]]
            interp = sampler.get("interpolation", "LINEAR")
            times = [v[0] for v in read_accessor(gltf, binary, sampler["input"])]
            values = read_accessor(gltf, binary, sampler["output"])
            if interp == "CUBICSPLINE":
                values = values[1::3]   # keep the value, drop the tangents
            if len(values) != len(times) or not times:
                raise ExportError(f"animation '{self.name}': sampler key/value count mismatch")
            if any(b < a for a, b in zip(times, times[1:])):
                raise ExportError(f"animation '{self.name}': key times are not increasing")
            self.channels.setdefault(target["node"], {})[path] = (times, values, interp)
            self.times.update(times)

    def sample(self, node, path, t):
        times, values, interp = self.channels[node][path]
        if t <= times[0]:
            return values[0]
        if t >= times[-1]:
            return values[-1]
        lo, hi = 0, len(times) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            lo, hi = (mid, hi) if times[mid] <= t else (lo, mid)
        if interp == "STEP":
            return values[lo]
        u = (t - times[lo]) / (times[hi] - times[lo])
        if path == "rotation":
            return _slerp(values[lo], values[hi], u)
        return tuple(a + u * (b - a) for a, b in zip(values[lo], values[hi]))


def local_matrix(gltf, node_index, anim=None, t=0.0):
    node = gltf["nodes"][node_index]
    if "matrix" in node:
        if anim and node_index in anim.channels:
            raise ExportError(f"node {node_index}: animated nodes must use TRS, not 'matrix'")
        return column_major(node["matrix"])
    trs = {"translation": tuple(node.get("translation", (0.0, 0.0, 0.0))),
           "rotation": tuple(node.get("rotation", (0.0, 0.0, 0.0, 1.0))),
           "scale": tuple(node.get("scale", (1.0, 1.0, 1.0)))}
    if anim and node_index in anim.channels:
        for path in anim.channels[node_index]:
            trs[path] = anim.sample(node_index, path, t)
    return trs_matrix(trs["translation"], trs["rotation"], trs["scale"])


def world_matrices(gltf, anim=None, t=0.0):
    """Return {node index: 4x4 world matrix in glTF space} for the default scene."""
    scene = gltf.get("scenes", [{}])[gltf.get("scene", 0)] if gltf.get("scenes") else {}
    roots = scene.get("nodes", list(range(len(gltf.get("nodes", [])))))
    out, stack = {}, [(r, None) for r in roots]
    identity = trs_matrix((0, 0, 0), (0, 0, 0, 1), (1, 1, 1))
    while stack:
        idx, parent = stack.pop()
        m = mat_mul(parent if parent else identity, local_matrix(gltf, idx, anim, t))
        out[idx] = m
        stack.extend((c, m) for c in gltf["nodes"][idx].get("children", []))
    return out


# ---------------------------------------------------------------- manifest
def _require(cond, message):
    if not cond:
        raise ExportError(message)


def load_manifest(path):
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    _require(isinstance(m, dict), "manifest is not a JSON object")
    _require(m.get("format") == FORMAT, f"manifest format must be '{FORMAT}' (got {m.get('format')!r})")
    engine = m.get("engine") or {}
    _require(re.fullmatch(r"[0-9a-f]{7,40}", str(engine.get("commit", ""))) is not None,
             "manifest engine.commit must be a hex Git commit")
    scene = m.get("scene") or {}
    _require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", str(scene.get("id", ""))) is not None,
             "manifest scene.id must be a short identifier")
    _require(isinstance(m.get("fps"), int) and not isinstance(m.get("fps"), bool) and 1 <= m["fps"] <= 240,
             "manifest fps must be an integer 1..240")
    _require(isinstance(m.get("frameCount"), int) and not isinstance(m.get("frameCount"), bool)
             and m["frameCount"] >= 1, "manifest frameCount must be a positive integer")
    glb = m.get("glb") or {}
    rel = str(glb.get("file", ""))
    _require(rel and not os.path.isabs(rel) and ".." not in rel.replace("\\", "/").split("/"),
             "manifest glb.file must be a relative path inside the export directory")
    _require(re.fullmatch(r"[0-9a-f]{64}", str(glb.get("sha256", ""))) is not None,
             "manifest glb.sha256 must be 64 lowercase hex digits")
    return m


def verify(manifest_path):
    """Check the export. Return a dict that render.py uses. Raise ExportError on any mismatch."""
    manifest_path = os.path.abspath(manifest_path)
    m = load_manifest(manifest_path)
    glb_path = os.path.join(os.path.dirname(manifest_path), m["glb"]["file"])
    _require(os.path.isfile(glb_path), f"GLB not found next to the manifest: {m['glb']['file']}")
    actual = sha256_file(glb_path)
    _require(actual == m["glb"]["sha256"],
             f"GLB SHA-256 mismatch: file {actual}, manifest {m['glb']['sha256']}")
    gltf, binary = read_glb(glb_path)
    nodes = gltf.get("nodes", [])
    names = [n.get("name") for n in nodes]

    anims = gltf.get("animations", [])
    wanted = m.get("animation")
    if wanted is None:
        _require(len(anims) == 1, f"the GLB must hold exactly one animation (has {len(anims)}); "
                 "or name one in manifest 'animation'")
        anim_index = 0
    else:
        hits = [i for i, a in enumerate(anims) if a.get("name") == wanted]
        _require(len(hits) == 1, f"manifest animation '{wanted}' is not exactly one GLB animation")
        anim_index = hits[0]
        _require(anim_index == 0, "the named animation must be the first GLB animation "
                 "(Blender's importer makes only the first one active)")
    anim = Animation(gltf, binary, anim_index)

    fps, count = m["fps"], m["frameCount"]
    times = sorted(anim.times)
    _require(abs(times[0]) < GRID_TOLERANCE / fps, f"animation starts at t={times[0]}, not 0")
    for t in times:
        k = t * fps
        _require(abs(k - round(k)) < GRID_TOLERANCE,
                 f"key at t={t:.6f}s is not on the {fps} fps frame grid (frame {k:.4f})")
    derived = int(round(times[-1] * fps)) + 1
    _require(derived == count, f"frame count mismatch: GLB animation spans {derived} frames "
             f"at {fps} fps, manifest says {count}")

    animated = sorted(anim.channels)
    for node in animated:
        _require(names[node], f"animated node {node} has no name")
    named = [n for n in names if n]
    _require(len(named) == len(set(named)), "GLB node names must be unique")
    _require(all(len(n.encode("utf-8")) <= NAME_LIMIT for n in named),
             f"GLB node names must be at most {NAME_LIMIT} bytes (Blender truncates longer names)")
    parts = m.get("parts", [])
    for p in parts:
        _require(p.get("name") in names, f"manifest part '{p.get('name')}' is not a GLB node")
    cameras = m.get("cameras", [])
    for c in cameras:
        hit = [n for n in nodes if n.get("name") == c.get("name")]
        _require(hit and "camera" in hit[0], f"manifest camera '{c.get('name')}' is not a GLB camera node")
    poster = m.get("posterFrame", count // 2)
    _require(isinstance(poster, int) and 0 <= poster < count, "manifest posterFrame is outside the frames")

    return {"manifest": m, "manifest_path": manifest_path, "glb_path": glb_path, "glb_sha256": actual,
            "gltf": gltf, "binary": binary, "animation": anim, "animation_index": anim_index,
            "fps": fps, "frame_count": count, "animated_nodes": animated, "poster_frame": poster,
            "engine_commit": m["engine"]["commit"], "scene_id": m["scene"]["id"]}


def provenance_label(checked):
    return ("Rendered in Blender Cycles from a verified MartyGraphics export "
            f"(engine {checked['engine_commit']}, scene {checked['scene_id']})")


def main(argv):
    if len(argv) != 1:
        print("usage: python3 -m mgrender.manifest <manifest.json>", file=sys.stderr)
        return 2
    try:
        c = verify(argv[0])
    except (ExportError, OSError, json.JSONDecodeError, KeyError, struct.error) as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 1
    print(f"PASS: {c['scene_id']} engine {c['engine_commit']} {c['frame_count']} frames "
          f"at {c['fps']} fps, {len(c['animated_nodes'])} animated nodes, glb sha256 {c['glb_sha256']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
