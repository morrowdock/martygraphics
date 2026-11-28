# SPDX-License-Identifier: Apache-2.0
"""Check the seven Swift hue families using the design spec's full-severity simulations."""
import itertools
import math
from pathlib import Path
import re
import unittest


# Machado, Oliveira and Fernandes (2009), severity 1.0, in linear sRGB.
MATRICES = (
    ((0.152286, 1.052583, -0.204868), (0.114503, 0.786281, 0.099216),
     (-0.003882, -0.048116, 1.051998)),
    ((0.367322, 0.860646, -0.227968), (0.280085, 0.672501, 0.047413),
     (-0.01182, 0.04294, 0.968881)),
)


def linear(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def simulated_channel(value):
    value = min(1, max(0, value))
    srgb = 12.92 * value if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055
    return linear(round(srgb * 255) / 255)


def simulated_lab(rgb, matrix):
    channels = [linear(int(rgb[i:i + 2], 16) / 255) for i in (0, 2, 4)]
    r, g, b = [simulated_channel(sum(x * y for x, y in zip(row, channels))) for row in matrix]
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s)


class DesignPaletteTests(unittest.TestCase):
    def test_role_hue_families_stay_distinct_in_both_simulations(self):
        source = Path(__file__).resolve().parents[2] / "Sources/MartyGraphics/MGTheme.swift"
        declarations = re.findall(
            r"static let (studio|paper) = modern\([^[]+hues: \[([^]]+)\]", source.read_text(encoding="utf-8")
        )
        self.assertEqual({theme for theme, _ in declarations}, {"studio", "paper"})
        for theme, values in declarations:
            hues = re.findall(r"0x([0-9A-F]{6})", values)
            self.assertEqual(len(hues), 7)
            for i, j in itertools.combinations(range(len(hues)), 2):
                with self.subTest(theme=theme, left=hues[i], right=hues[j]):
                    gap = min(100 * math.dist(simulated_lab(hues[i], matrix), simulated_lab(hues[j], matrix))
                              for matrix in MATRICES)
                    # Paper green/red uses the spec's exception for status with word and glyph.
                    floor = 6 if theme == "paper" and (i, j) == (4, 6) else 8
                    self.assertGreaterEqual(gap, floor)
