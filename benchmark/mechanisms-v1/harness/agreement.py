# SPDX-License-Identifier: Apache-2.0
"""Grader agreement statistics for mechanisms-v1 (PROTOCOL.md section 10). Exploratory; Python standard library only.

- Krippendorff's alpha (interval metric; nominal is here only to check the code against published values),
- Spearman's rho (Pearson correlation of average ranks, so ties get their mean rank),
- Cohen's kappa (unweighted, and quadratic weights for the ordinal clarity scale) and percent agreement.

Every function returns None when its denominator is 0 (section 11, "Zero denominators"): the caller reports the
statistic as undefined, with its counts. Alpha and kappa are exact fractions when the inputs are integers or
fractions; rho is a float (it needs a square root).

The *_weighted functions compute the same statistics for many bootstrap resamples at once (NumPy, imported only
when they are called): `weights` is a (resamples, items) array of how often each item is in each resample. With
integer weights they equal the plain functions applied to the expanded data (tested). They return NaN where a
resample's denominator is 0.
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


# ------------------------------------------------------------------------------------ bootstrap (NumPy) forms

def _np():
    import numpy
    return numpy


def alpha_interval_weighted(a, b, weights):
    """Krippendorff's interval alpha for two coders, per resample. a, b: float arrays, NaN for a missing value.

    For two coders and pairable units only, D_o = mean (a - b)^2 and D_e = 2 SS / (2N - 1), where SS is the sum of
    squares of the 2N pooled values around their mean (the coincidence-matrix form reduced to two coders)."""
    np = _np()
    mask = ~(np.isnan(a) | np.isnan(b))
    a, b, w = a[mask], b[mask], weights[:, mask]
    units = w.sum(axis=1)
    values = 2 * units
    with np.errstate(divide="ignore", invalid="ignore"):
        observed = (w @ (a - b) ** 2) / units
        centre = (w @ (a + b)) / values
        squares = w @ (a ** 2 + b ** 2) - values * centre ** 2
        expected = 2 * squares / (values - 1)
        alpha = 1 - observed / expected
    return np.where((units >= 1) & (expected > 1e-12), alpha, np.nan)


def spearman_weighted(a, b, weights):
    """Spearman's rho per resample: weighted mean ranks (ties and repeated items share their mean rank)."""
    np = _np()
    mask = ~(np.isnan(a) | np.isnan(b))
    a, b, w = a[mask], b[mask], weights[:, mask]

    def ranks(x):
        less = (x[None, :] < x[:, None]).astype(float)
        equal = (x[None, :] == x[:, None]).astype(float)
        return w @ less.T + (w @ equal.T + 1) / 2
    ra, rb = ranks(a), ranks(b)
    total = w.sum(axis=1)
    with np.errstate(divide="ignore", invalid="ignore"):
        ma = (w * ra).sum(axis=1) / total
        mb = (w * rb).sum(axis=1) / total
        da, db = ra - ma[:, None], rb - mb[:, None]
        sab, saa, sbb = (w * da * db).sum(axis=1), (w * da * da).sum(axis=1), (w * db * db).sum(axis=1)
        rho = sab / np.sqrt(saa * sbb)
    return np.where((total >= 2) & (saa > 1e-12) & (sbb > 1e-12), rho, np.nan)


def cells(pairs_per_item, k):
    """(items, k, k) counts of rating pairs (category indices) per item; an item may hold several pairs."""
    np = _np()
    out = np.zeros((len(pairs_per_item), k, k))
    for n, pairs in enumerate(pairs_per_item):
        for i, j in pairs:
            out[n, i, j] += 1
    return out


def kappa_weighted(item_cells, weights, kind=None):
    """Cohen's kappa per resample from per-item rating-pair counts; kind None (unweighted) or "quadratic"."""
    np = _np()
    n, k, _ = item_cells.shape
    counts = (weights @ item_cells.reshape(n, k * k)).reshape(-1, k, k)
    total = counts.sum(axis=(1, 2))
    i, j = np.meshgrid(np.arange(k), np.arange(k), indexing="ij")
    w = (i != j).astype(float) if kind is None else ((i - j) ** 2) / float((k - 1) ** 2)
    with np.errstate(divide="ignore", invalid="ignore"):
        p = counts / total[:, None, None]
        observed = (p * w).sum(axis=(1, 2))
        expected = (p.sum(axis=2)[:, :, None] * p.sum(axis=1)[:, None, :] * w).sum(axis=(1, 2))
        kappa = 1 - observed / expected
    return np.where((total > 0) & (expected > 1e-12), kappa, np.nan)


def agreement_weighted(item_cells, weights):
    """Percent agreement per resample from per-item rating-pair counts."""
    np = _np()
    n, k, _ = item_cells.shape
    counts = (weights @ item_cells.reshape(n, k * k)).reshape(-1, k, k)
    total = counts.sum(axis=(1, 2))
    with np.errstate(divide="ignore", invalid="ignore"):
        share = np.trace(counts, axis1=1, axis2=2) / total
    return np.where(total > 0, share, np.nan)
