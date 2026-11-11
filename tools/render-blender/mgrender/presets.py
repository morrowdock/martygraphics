# SPDX-License-Identifier: Apache-2.0
"""Material preset choice from part names and glTF material values (no Blender needed)."""
import re

MATERIAL_PRESETS = ("polished_metal", "brushed_metal", "painted_metal", "anodised_aluminium",
                    "rubber", "carbon_fibre", "glass", "plastic")

# Ordered: the first match wins. Matched against the lower-case part name.
NAME_RULES = [
    ("glass", r"cover|window|glass|canopy|lens|visor|transparent|clear|dome"),
    ("rubber", r"rubber|tyre|tire|seal|gasket|belt|grommet|foot|feet|boot|o[-_]?ring|bumper"),
    ("carbon_fibre", r"carbon|cfrp|composite|(^|[^a-z])cf([^a-z]|$)"),
    ("polished_metal", r"polish|chrome|shaft|axle|spindle|(^|[^a-z])pin([^a-z]|$)|bolt|screw|bearing|race|journal"),
    ("brushed_metal", r"gear|pinion|blade|fan|rotor|stator|disc|disk|ring|sun|planet|carrier|spline|hub|vane|"
                      r"turbine|compressor|cam|crank|sprocket|worm"),
    ("anodised_aluminium", r"anodi[sz]|alu|bracket|(^|[^a-z])arm([^a-z]|$)|link|yoke|clevis"),
    ("painted_metal", r"paint|housing|casing|case|cowl|nacelle|body|frame|chassis|base|shell|plate|cover|spinner"),
]


def choose_preset(name, params, override=None, label=None):
    """Return (preset, reason).

    Order: the manifest preset, then the name rules on the readable part label
    (manifest parts[].label, for example "Sun gear 1"), then the name rules on the
    glTF node name (often a part id such as "sun1"), then the glTF material values.
    """
    if override:
        if override not in MATERIAL_PRESETS:
            raise ValueError(f"unknown material preset '{override}' for part '{name}'")
        return override, "manifest"
    for source, text in (("label", label), ("name", name)):
        if not text:
            continue
        low = text.lower()
        for preset, pattern in NAME_RULES:
            hit = re.search(pattern, low)
            if hit:
                return preset, f"{source} contains '{hit.group(0).strip('_- ')}'"
    if params["transmission"] > 0.5 or params["alpha"] < 0.6:
        return "glass", "material alpha/transmission"
    if params["metallic"] >= 0.5:
        return ("polished_metal", "material metallic+smooth") if params["roughness"] < 0.15 \
            else ("brushed_metal", "material metallic")
    if params["roughness"] > 0.75:
        return "rubber", "material rough dielectric"
    return "painted_metal", "material default"


def part_material(part):
    """The manifest material override of a part as a dict; empty (None, {} or "") means none."""
    value = part.get("material")
    return value if value else {}
