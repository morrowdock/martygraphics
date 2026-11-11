# SPDX-License-Identifier: Apache-2.0
"""Grader agreement statistics for mechanisms-v1 (PROTOCOL.md section 10). Exploratory; Python standard library only.

- Krippendorff's alpha (interval metric; nominal is here only to check the code against published values),
- Spearman's rho (Pearson correlation of average ranks, so ties get their mean rank),
- Cohen's kappa (unweighted, and quadratic weights for the ordinal clarity scale) and percent agreement.

Every function returns None when its denominator is 0 (section 11, "Zero denominators"): the caller reports the
statistic as undefined, with its counts. Alpha and kappa are exact fractions when the inputs are integers or
fractions; rho is a float (it needs a square root).
"""

from fractions import Fraction
from math import sqrt


def _exact(value):
    return value if isinstance(value, Fraction) else Fraction(value)


def krippendorff_alpha(units, metric="interval"):
    """Krippendorff's alpha. `units`: one list of values per item, one entry per coder, None for a missing value.

    Coincidence-matrix form (Krippendorff 2011, "Computing Krippendorff's Alpha-Reliability"): only units with at
    least two values are pairable; each ordered pair of values in unit u adds 1 / (m_u - 1). alpha = 1 - D_o / D_e.
    """
    if metric == "interval":
        def delta(c, k):
            return (c - k) ** 2
    elif metric == "nominal":
        def delta(c, k):
            return 0 if c == k else 1
    else:
        raise ValueError("metric must be interval or nominal")
    coincidence = {}
    for unit in units:
        values = [_exact(v) for v in unit if v is not None]
        m = len(values)
        if m < 2:
            continue
        weight = Fraction(1, m - 1)
        for i, c in enumerate(values):
            for j, k in enumerate(values):
                if i != j:
                    coincidence[(c, k)] = coincidence.get((c, k), 0) + weight
    totals = {}
    for (c, _), o in coincidence.items():
        totals[c] = totals.get(c, 0) + o
    n = sum(totals.values())
    if n < 2:
        return None
    observed = sum(o * delta(c, k) for (c, k), o in coincidence.items()) / n
    expected = sum(totals[c] * totals[k] * delta(c, k) for c in totals for k in totals) / (n * (n - 1))
    if expected == 0:
        return None
    return 1 - observed / expected


def average_ranks(values):
    """Ranks 1..n; tied values get the mean of the ranks they span."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    ranks = [None] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        rank = Fraction(i + j + 2, 2)
        for t in range(i, j + 1):
            ranks[order[t]] = rank
        i = j + 1
    return ranks


def pearson(x, y):
    if len(x) != len(y):
        raise ValueError("x and y need the same length")
    n = len(x)
    if n < 2:
        return None
    x = [_exact(v) for v in x]
    y = [_exact(v) for v in y]
    mx, my = sum(x) / n, sum(y) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    sxx = sum((a - mx) ** 2 for a in x)
    syy = sum((b - my) ** 2 for b in y)
    if sxx == 0 or syy == 0:
        return None
    return float(sxy) / sqrt(float(sxx * syy))


def spearman_rho(x, y):
    """Spearman's rho over the paired items (both values present)."""
    pairs = [(a, b) for a, b in zip(x, y) if a is not None and b is not None]
    if len(pairs) < 2:
        return None
    return pearson(average_ranks([a for a, _ in pairs]), average_ranks([b for _, b in pairs]))


def percent_agreement(x, y):
    pairs = [(a, b) for a, b in zip(x, y) if a is not None and b is not None]
    if not pairs:
        return None
    return Fraction(sum(1 for a, b in pairs if a == b), len(pairs))


def cohen_kappa(x, y, categories, weights=None):
    """Cohen's kappa for two raters over `categories` (ordered, for weights). weights: None or "quadratic"."""
    pairs = [(a, b) for a, b in zip(x, y) if a is not None and b is not None]
    if not pairs:
        return None
    index = {c: i for i, c in enumerate(categories)}
    for a, b in pairs:
        if a not in index or b not in index:
            raise ValueError("a rating is not in the categories")
    k = len(categories)
    if weights is None:
        def w(i, j):
            return 0 if i == j else 1
    elif weights == "quadratic":
        if k < 2:
            return None
        def w(i, j):
            return Fraction((i - j) ** 2, (k - 1) ** 2)
    else:
        raise ValueError("weights must be None or quadratic")
    n = len(pairs)
    observed = {}
    for a, b in pairs:
        observed[(index[a], index[b])] = observed.get((index[a], index[b]), 0) + 1
    row = [sum(1 for a, _ in pairs if index[a] == i) for i in range(k)]
    col = [sum(1 for _, b in pairs if index[b] == j) for j in range(k)]
    disagree_observed = sum(Fraction(o, n) * w(i, j) for (i, j), o in observed.items())
    disagree_expected = sum(Fraction(row[i] * col[j], n * n) * w(i, j) for i in range(k) for j in range(k))
    if disagree_expected == 0:
        return None
    return 1 - disagree_observed / disagree_expected
