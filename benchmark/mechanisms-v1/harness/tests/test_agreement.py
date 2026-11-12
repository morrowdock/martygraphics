# SPDX-License-Identifier: Apache-2.0
"""agreement.py against published values (and exact identities where no published value fits)."""

from fractions import Fraction as F
from math import sqrt
import unittest

import support  # noqa: F401  (puts harness/ on sys.path)
import agreement

N = None

# Krippendorff, K. (2011). Computing Krippendorff's Alpha-Reliability. Annenberg School for Communication,
# University of Pennsylvania. Section C: 4 observers, 12 units, values 1-5, missing data.
# Published: nominal alpha = 0.743, interval alpha = 0.849.
KRIPP_C = list(zip(
    [1, 2, 3, 3, 2, 1, 4, 1, 2, N, N, N],
    [1, 2, 3, 3, 2, 2, 4, 1, 2, 5, N, 3],
    [N, 3, 3, 3, 2, 3, 4, 2, 2, 5, 1, N],
    [1, 2, 3, 3, 2, 4, 4, 1, 2, 5, 1, N],
))
# Same source, section A: 2 observers, 10 units, binary data. Published: alpha = 0.095. For 0/1 data the interval
# metric equals the nominal one, so the interval alpha is 0.095 too.
KRIPP_A = list(zip([0, 1, 0, 0, 0, 0, 0, 0, 1, 0], [1, 1, 1, 0, 0, 1, 0, 0, 0, 0]))


class KrippendorffTest(unittest.TestCase):
    def test_published_four_observers_with_missing_data(self):
        self.assertEqual(round(float(agreement.krippendorff_alpha(KRIPP_C, "interval")), 3), 0.849)
        self.assertEqual(round(float(agreement.krippendorff_alpha(KRIPP_C, "nominal")), 3), 0.743)

    def test_published_two_observers(self):
        self.assertEqual(round(float(agreement.krippendorff_alpha(KRIPP_A, "interval")), 3), 0.095)
        self.assertEqual(agreement.krippendorff_alpha(KRIPP_A, "interval"), agreement.krippendorff_alpha(KRIPP_A, "nominal"))
        self.assertEqual(agreement.krippendorff_alpha(KRIPP_A, "interval"), F(2, 21))

    def test_perfect_agreement(self):
        self.assertEqual(agreement.krippendorff_alpha([(1, 1), (2, 2), (5, 5)]), 1)

    def test_unpairable_units_are_ignored(self):
        self.assertEqual(agreement.krippendorff_alpha(KRIPP_A + [(3, N), (N, N)]), agreement.krippendorff_alpha(KRIPP_A))

    def test_fractions_are_exact(self):
        units = [(F(5, 3), F(5, 3)), (F(10, 3), F(5, 2)), (0, 1)]
        self.assertIsInstance(agreement.krippendorff_alpha(units), F)

    def test_zero_denominators_are_undefined(self):
        self.assertIsNone(agreement.krippendorff_alpha([(2, 2), (2, 2)]))         # no variation: D_e = 0
        self.assertIsNone(agreement.krippendorff_alpha([(1, N), (N, 2)]))         # nothing pairable
        self.assertIsNone(agreement.krippendorff_alpha([]))

    def test_unknown_metric(self):
        with self.assertRaises(ValueError):
            agreement.krippendorff_alpha(KRIPP_A, "ordinal")


class SpearmanTest(unittest.TestCase):
    def test_published_without_ties(self):
        # Wikipedia, "Spearman's rank correlation coefficient", example: IQ against hours of TV per week.
        iq = [106, 100, 86, 101, 99, 103, 97, 113, 112, 110]
        tv = [7, 27, 2, 50, 28, 29, 20, 12, 6, 17]
        self.assertAlmostEqual(agreement.spearman_rho(iq, tv), -29 / 165, places=12)

    def test_ties_get_mean_ranks(self):
        self.assertEqual(agreement.average_ranks([1, 2, 2, 3]), [1, F(5, 2), F(5, 2), 4])
        self.assertEqual(agreement.average_ranks([3, 3, 3]), [2, 2, 2])
        # ranks x = 1, 2.5, 2.5, 4 against 1, 2, 3, 4: Pearson = 4.5 / sqrt(4.5 * 5) = 3 / sqrt(10).
        self.assertAlmostEqual(agreement.spearman_rho([1, 2, 2, 3], [1, 2, 3, 4]), 3 / sqrt(10), places=12)

    def test_missing_pairs_are_dropped(self):
        self.assertAlmostEqual(agreement.spearman_rho([1, 2, N, 3], [1, 2, 9, 4]), 1.0, places=12)

    def test_zero_denominators_are_undefined(self):
        self.assertIsNone(agreement.spearman_rho([1, 1, 1], [1, 2, 3]))
        self.assertIsNone(agreement.spearman_rho([1], [2]))
        self.assertIsNone(agreement.spearman_rho([1, N], [N, 2]))


class KappaTest(unittest.TestCase):
    @staticmethod
    def table(yy, yn, ny, nn):
        x = ["y"] * (yy + yn) + ["n"] * (ny + nn)
        y = ["y"] * yy + ["n"] * yn + ["y"] * ny + ["n"] * nn
        return x, y

    def test_published_values(self):
        # Wikipedia, "Cohen's kappa", worked examples: 20/5/10/15 gives 0.4; 45/15/25/15 gives 0.1304.
        self.assertEqual(agreement.cohen_kappa(*self.table(20, 5, 10, 15), ["y", "n"]), F(2, 5))
        self.assertEqual(round(float(agreement.cohen_kappa(*self.table(45, 15, 25, 15), ["y", "n"])), 4), 0.1304)
        self.assertEqual(agreement.percent_agreement(*self.table(20, 5, 10, 15)), F(7, 10))

    def test_quadratic_weights_identity(self):
        # With quadratic weights, kappa_w = 2 s_xy / (s_x^2 + s_y^2 + (mean x - mean y)^2) with 1/n moments
        # (Fleiss and Cohen 1973; Schuster 2004). Checked exactly on an ordinal 1-5 example.
        x = [5, 4, 4, 3, 2, 5, 1, 3, 4, 2, 3, 5]
        y = [4, 4, 3, 3, 1, 5, 2, 2, 5, 2, 4, 4]
        n = len(x)
        mx, my = F(sum(x), n), F(sum(y), n)
        sxy = sum((a - mx) * (b - my) for a, b in zip(x, y)) / n
        sxx = sum((a - mx) ** 2 for a in x) / n
        syy = sum((b - my) ** 2 for b in y) / n
        expected = 2 * sxy / (sxx + syy + (mx - my) ** 2)
        self.assertEqual(agreement.cohen_kappa(x, y, [1, 2, 3, 4, 5], weights="quadratic"), expected)

    def test_quadratic_equals_unweighted_for_two_categories(self):
        x, y = self.table(20, 5, 10, 15)
        self.assertEqual(agreement.cohen_kappa(x, y, ["y", "n"], "quadratic"), agreement.cohen_kappa(x, y, ["y", "n"]))

    def test_zero_denominators_are_undefined(self):
        self.assertIsNone(agreement.cohen_kappa(["y", "y"], ["y", "y"], ["y", "n"]))
        self.assertIsNone(agreement.cohen_kappa([], [], ["y", "n"]))
        self.assertIsNone(agreement.percent_agreement([N], [1]))

    def test_unknown_category(self):
        with self.assertRaises(ValueError):
            agreement.cohen_kappa(["y"], ["maybe"], ["y", "n"])


class WeightedFormsTest(unittest.TestCase):
    """The bootstrap (weighted) forms equal the plain functions on the expanded data, row by row."""

    @classmethod
    def setUpClass(cls):
        import numpy as np
        import random
        cls.np = np
        rng = random.Random(7)
        cls.a = [rng.choice([0, 1, 2, F(5, 3), 3, 5, None]) for _ in range(14)]
        cls.b = [rng.choice([0, 1, 2, F(10, 3), 4, 5, None]) for _ in range(14)]
        cls.rows = [[rng.randint(0, 3) for _ in range(14)] for _ in range(6)] + [[1] * 14, [5] + [0] * 13]

    def expand(self, row, *columns):
        return [[c[i] for i, w in enumerate(row) for _ in range(w)] for c in columns]

    def floats(self, values):
        return self.np.array([self.np.nan if v is None else float(v) for v in values])

    def test_alpha(self):
        weights = self.np.array(self.rows, dtype=float)
        got = agreement.alpha_interval_weighted(self.floats(self.a), self.floats(self.b), weights)
        for row, value in zip(self.rows, got):
            x, y = self.expand(row, self.a, self.b)
            expected = agreement.krippendorff_alpha(list(zip(x, y)), "interval")
            if expected is None:
                self.assertTrue(self.np.isnan(value))
            else:
                self.assertAlmostEqual(value, float(expected), places=10)

    def test_spearman(self):
        weights = self.np.array(self.rows, dtype=float)
        got = agreement.spearman_weighted(self.floats(self.a), self.floats(self.b), weights)
        for row, value in zip(self.rows, got):
            x, y = self.expand(row, self.a, self.b)
            expected = agreement.spearman_rho(x, y)
            if expected is None:
                self.assertTrue(self.np.isnan(value))
            else:
                self.assertAlmostEqual(value, expected, places=10)

    def test_kappa_and_agreement(self):
        cats = [1, 2, 3, 4, 5]
        x = [1, 2, 2, 3, 5, 4, 4, 1, 3, 5]
        y = [1, 3, 2, 3, 4, 4, 5, 2, 3, 5]
        item_cells = agreement.cells([[(cats.index(a), cats.index(b))] for a, b in zip(x, y)], 5)
        rows = [r[:10] for r in self.rows]
        weights = self.np.array(rows, dtype=float)
        for kind in (None, "quadratic"):
            got = agreement.kappa_weighted(item_cells, weights, kind)
            for row, value in zip(rows, got):
                ex, ey = self.expand(row, x, y)
                expected = agreement.cohen_kappa(ex, ey, cats, weights=kind) if ex else None
                if expected is None:
                    self.assertTrue(self.np.isnan(value))
                else:
                    self.assertAlmostEqual(value, float(expected), places=10)
        got = agreement.agreement_weighted(item_cells, weights)
        for row, value in zip(rows, got):
            ex, ey = self.expand(row, x, y)
            self.assertAlmostEqual(value, float(agreement.percent_agreement(ex, ey)), places=12)

    def test_several_pairs_per_item(self):
        pairs = [[(0, 0), (0, 1)], [(1, 1)], [], [(1, 0), (0, 0), (1, 1)]]
        item_cells = agreement.cells(pairs, 2)
        got = agreement.kappa_weighted(item_cells, self.np.array([[1, 2, 5, 1]], dtype=float))[0]
        flat = [p for p in pairs[0]] + [p for p in pairs[1]] * 2 + [p for p in pairs[3]]
        expected = agreement.cohen_kappa([a for a, _ in flat], [b for _, b in flat], [0, 1])
        self.assertAlmostEqual(got, float(expected), places=12)

    def test_undefined_rows_are_nan(self):
        weights = self.np.array([[0, 0, 0], [3, 0, 0]], dtype=float)
        values = self.np.array([1.0, 2.0, 3.0])
        self.assertTrue(self.np.isnan(agreement.alpha_interval_weighted(values, values, weights)).all())
        self.assertTrue(self.np.isnan(agreement.spearman_weighted(values, values, weights)).all())


if __name__ == "__main__":
    unittest.main()
