# SPDX-License-Identifier: Apache-2.0
"""Draft Python mirror of `MGMLKit.check(data:mlKit: true)` for the ML explainer kit.

Ported from Sources/MartyGraphicsMLKit at main 5e4952e (MGMLKit, MGMLVision, MGMLProbabilities, MGMLAgent,
MLGeneration, MLMeaningMap). It returns the first refusal as (reason, location) like the strict report, plus
the facts the eval grader needs. PNG-bearing kinds (`pictureToNumbers`, `attention`, and `imagePNG` map
entries) are outside this mirror and raise `Unsupported`. Swift stays authoritative; parity is pending a Mac.
"""

import json
import math
import re
import sys
import unicodedata

MAX_BYTES = 16 * 1024
TOLERANCE = 1e-12
KIND_KEYS = {
    "visionPipeline": {"caption", "citation", "imageSize", "patchSize", "embeddingWidth",
                       "embeddingWidthCitation", "projectorLabel", "languageModelLabel", "textTokens", "stageFocus"},
    "nextTokenProbabilities": {"tokens", "candidates", "chosen", "temperature", "topK", "topP", "temperatures"},
    "pictureToNumbers": {"caption", "imagePNG", "patchSize", "highlight", "presentation"},
    "meaningMap": {"points", "vectors", "nearestNeighbors", "cluster", "vectorCitation"},
    "generationLoop": {"prompt", "stepCount", "steps", "selection", "seed"},
    "attention": {"imagePNG", "patchSize", "query", "scores"},
    "agentLoop": {"states", "requiresReview", "stepBudget"},
}
AGENT_STATES = ["plan", "toolCall", "toolResult", "review", "act", "revise", "stop"]
NEWLINES = {"\n", "\x0b", "\x0c", "\r", "\x85", " ", " "}


class Issue(Exception):
    def __init__(self, reason, path):
        super().__init__(reason)
        self.reason = reason
        self.path = path


class Unsupported(Exception):
    """The input needs a part of the Swift checker this mirror does not port (PNG decoding)."""


def is_number(value):
    return type(value) in (int, float)


class Obj:
    def __init__(self, value, path, keys):
        if not isinstance(value, dict):
            raise Issue("ml.object", path)
        if not set(value) <= set(keys):
            raise Issue("ml.unknown", path)
        self.values = value
        self.path = path

    def issue(self, reason, key):
        return Issue(reason, key if not self.path else self.path + "." + key)

    def text(self, key, limit, reason):
        if not safe_text(self.values.get(key), limit):
            raise self.issue(reason, key)
        return self.values[key]

    def optional_text(self, key, limit, reason):
        return None if key not in self.values else self.text(key, limit, reason)

    def integer(self, key, low, high, reason):
        result = integer(self.values.get(key), low, high)
        if result is None:
            raise self.issue(reason, key)
        return result

    def tokens(self, key):
        values = self.values.get(key)
        if not isinstance(values, list) or not 1 <= len(values) <= 12:
            raise self.issue("ml.tokens", key)
        for index, value in enumerate(values):
            if not isinstance(value, str) or not safe_text(value, 16):
                raise self.issue("ml.tokens", f"{key}[{index}]")
        return list(values)


def integer(value, low, high):
    if not is_number(value) or isinstance(value, bool) or not low <= value <= high:
        return None
    return int(value) if float(value).is_integer() else None


def safe_text(value, limit):
    if not isinstance(value, str) or not 1 <= len(value) <= limit or not value.strip():
        return False
    if "<" in value or ">" in value or "://" in value:
        return False
    return not any(unicodedata.category(c) in ("Cc", "Cf") or c in NEWLINES for c in value)


def normalize(weights, issue):
    total = 0.0
    for weight in weights:
        total += weight
    if not math.isfinite(total) or total <= 0:
        raise issue
    probabilities = [w / total for w in weights]
    check_sum(probabilities, issue)
    return probabilities


def check_sum(probabilities, issue):
    total = 0.0
    for p in probabilities:
        total += p
    if not all(0 <= p <= 1 for p in probabilities) or abs(total - 1) > TOLERANCE:
        raise issue


def softmax(logits, temperature, issue):
    if not logits:
        raise issue
    top = max(logits)
    return normalize([math.exp((l - top) / (temperature or 1)) for l in logits], issue)


def temperature_value(value):
    return value if is_number(value) and not isinstance(value, bool) and 0.01 <= value <= 100 else None


def read_candidates(obj, list_reason="ml.prob.candidates", logit_reason="ml.prob.logit"):
    raw = obj.values.get("candidates")
    if not isinstance(raw, list) or not 2 <= len(raw) <= 8:
        raise obj.issue(list_reason, "candidates")
    seen, out = set(), []
    for index, value in enumerate(raw):
        candidate = Obj(value, f"{obj.path}.candidates[{index}]", {"token", "logit"})
        token = candidate.text("token", 16, list_reason)
        if token in seen:
            raise candidate.issue(list_reason, "token")
        seen.add(token)
        logit = candidate.values.get("logit")
        if not is_number(logit) or isinstance(logit, bool) or abs(logit) > 1_000_000:
            raise candidate.issue(logit_reason, "logit")
        out.append((token, float(logit)))
    return out


def vision(obj):
    caption = obj.text("caption", 100, "ml.vision.caption")
    obj.optional_text("citation", 120, "ml.vision.citation")
    obj.optional_text("embeddingWidthCitation", 120, "ml.vision.citation")
    size = obj.values.get("imageSize")
    if not isinstance(size, list) or len(size) != 2:
        raise obj.issue("ml.vision.size", "imageSize")
    width, height = integer(size[0], 1, 8192), integer(size[1], 1, 8192)
    if width is None or height is None:
        raise obj.issue("ml.vision.size", "imageSize")
    patch = obj.integer("patchSize", 1, 8192, "ml.vision.size")
    if width % patch or height % patch:
        raise obj.issue("ml.vision.patch.division", "patchSize")
    columns, rows = width // patch, height // patch
    if columns > 128 or rows > 128 or columns * rows > 4096:
        raise obj.issue("ml.vision.patch.count", "patchSize")
    obj.integer("embeddingWidth", 1, 65536, "ml.vision.embeddingWidth")
    obj.optional_text("projectorLabel", 32, "ml.vision.label")
    obj.optional_text("languageModelLabel", 32, "ml.vision.label")
    tokens = obj.tokens("textTokens")
    if "stageFocus" in obj.values and not isinstance(obj.values["stageFocus"], bool):
        raise obj.issue("ml.vision.stageFocus", "stageFocus")
    return {"caption": caption, "patchGrid": [columns, rows], "patchCount": columns * rows,
            "textTokenCount": len(tokens), "illustrativeJoinedTokenCount": columns * rows + len(tokens)}


def probabilities(obj):
    obj.tokens("tokens")
    candidates = read_candidates(obj)
    choice = obj.text("chosen", 16, "ml.prob.chosen")
    tokens = [token for token, _ in candidates]
    if choice not in tokens:
        raise obj.issue("ml.prob.chosen", "chosen")
    chosen = tokens.index(choice)
    logits = [logit for _, logit in candidates]
    sum_issue = obj.issue("ml.prob.sum", "candidates")
    stages = []
    if "temperatures" in obj.values:
        values = obj.values["temperatures"]
        if not isinstance(values, list) or not 2 <= len(values) <= 4 or any(
                key in obj.values for key in ("temperature", "topK", "topP")):
            raise obj.issue("ml.prob.sweep", "temperatures")
        seen = set()
        for index, value in enumerate(values):
            temperature = temperature_value(value)
            if temperature is None or float(temperature) in seen:
                raise obj.issue("ml.prob.sweep", f"temperatures[{index}]")
            seen.add(float(temperature))
            stages.append(("temperature", temperature, softmax(logits, temperature, sum_issue)))
        if stages[-1][2][chosen] <= 0:
            raise obj.issue("ml.prob.chosen", "chosen")
    else:
        current = softmax(logits, None, sum_issue)
        stages.append(("softmax", None, current))
        if "temperature" in obj.values:
            temperature = temperature_value(obj.values["temperature"])
            if temperature is None:
                raise obj.issue("ml.prob.temperature", "temperature")
            current = softmax(logits, temperature, sum_issue)
            stages.append(("temperature", temperature, current))
        ranked = sorted(range(len(logits)), key=lambda i: (-logits[i], i))
        if "topK" in obj.values:
            k = obj.integer("topK", 1, len(candidates), "ml.prob.topK")
            keep = set(ranked[:k])
            current = normalize([current[i] if i in keep else 0.0 for i in range(len(logits))], sum_issue)
            stages.append(("topK", k, current))
        if "topP" in obj.values:
            p = obj.values["topP"]
            if not is_number(p) or isinstance(p, bool) or not 0 < p <= 1:
                raise obj.issue("ml.prob.topP", "topP")
            cumulative, keep = 0.0, set()
            for i in ranked:
                if current[i] <= 0:
                    continue
                keep.add(i)
                cumulative += current[i]
                if p < 1 and cumulative >= p:
                    break
            current = normalize([current[i] if i in keep else 0.0 for i in range(len(logits))], sum_issue)
            stages.append(("topP", p, current))
        if current[chosen] <= 0:
            raise obj.issue("ml.prob.chosen", "chosen")
    final = stages[-1][2]
    return {"chosen": choice, "candidates": tokens, "logits": logits,
            "distributions": [{"step": s, "parameter": p, "probabilities": d} for s, p, d in stages],
            "retained": [tokens[i] for i in range(len(tokens)) if final[i] > 0]}


def agent(obj):
    review_flag = obj.values.get("requiresReview")
    if not isinstance(review_flag, bool):
        raise obj.issue("ml.agent.review", "requiresReview")
    raw = obj.values.get("states")
    if not isinstance(raw, list) or len(raw) > len(AGENT_STATES):
        raise obj.issue("ml.agent.states", "states")
    present = set()
    for value in raw:
        if not isinstance(value, str) or value not in AGENT_STATES or value in present:
            raise obj.issue("ml.agent.states", "states")
        present.add(value)
    if "stop" not in present:
        raise obj.issue("ml.agent.stop", "states")
    has_review = "review" in present
    if review_flag and not has_review:
        raise obj.issue("ml.agent.review", "states")
    if not {"plan", "toolCall", "toolResult", "act"} <= present or (not has_review and "revise" in present):
        raise obj.issue("ml.agent.states", "states")
    edges = [("plan", "toolCall"), ("toolCall", "toolResult")]
    if has_review:
        edges += [("toolResult", "review"), ("review", "act"), ("review", "stop")]
        if "revise" in present:
            edges += [("review", "revise"), ("revise", "plan")]
    else:
        edges.append(("toolResult", "act"))
    edges.append(("act", "stop"))
    budget = obj.integer("stepBudget", 1, 32, "ml.agent.budget")
    current, steps = "plan", 0
    while current != "stop" and steps < budget:
        approve = [b for a, b in edges if a == current and not (a == "review" and b != "act")]
        if not approve:
            break
        current, steps = approve[0], steps + 1
    if current != "stop":
        raise obj.issue("ml.agent.budget", "stepBudget")
    return {"states": [s for s in AGENT_STATES if s in present], "minimumApprovalSteps": steps,
            "edges": [list(edge) for edge in edges]}


class SplitMix64:
    def __init__(self, seed):
        self.state = seed & (2**64 - 1)

    def next(self):
        mask = 2**64 - 1
        self.state = (self.state + 0x9E3779B97F4A7C15) & mask
        bits = self.state
        bits = ((bits ^ (bits >> 30)) * 0xBF58476D1CE4E5B9) & mask
        bits = ((bits ^ (bits >> 27)) * 0x94D049BB133111EB) & mask
        bits ^= bits >> 31
        return (bits >> 11) / 9_007_199_254_740_992


def generation(obj):
    obj.tokens("prompt")
    count = obj.integer("stepCount", 1, 8, "ml.generation.count")
    mode = obj.text("selection", 6, "ml.generation.selection")
    if mode not in ("greedy", "sample"):
        raise obj.issue("ml.generation.selection", "selection")
    seed = None
    if mode == "sample":
        seed = obj.integer("seed", 0, 2**32 - 1, "ml.generation.selection")
    elif "seed" in obj.values:
        raise obj.issue("ml.generation.selection", "seed")
    raw = obj.values.get("steps")
    if not isinstance(raw, list) or len(raw) != count:
        raise obj.issue("ml.generation.logits", "steps")
    random = SplitMix64(seed or 0)
    generated, steps = [], []
    for index, value in enumerate(raw):
        step = Obj(value, f"{obj.path}.steps[{index}]", {"candidates", "temperature", "chosen"})
        candidates = read_candidates(step, "ml.generation.logits", "ml.generation.logits")
        temperature = None
        if "temperature" in step.values:
            temperature = temperature_value(step.values["temperature"])
            if temperature is None:
                raise step.issue("ml.prob.temperature", "temperature")
        logits = [logit for _, logit in candidates]
        distribution = softmax(logits, temperature, step.issue("ml.prob.sum", "candidates"))
        if mode == "greedy":
            chosen = 0
            for i in range(len(logits)):
                if logits[i] > logits[chosen]:
                    chosen = i
        else:
            unit, cumulative, chosen = random.next(), 0.0, 0
            for i, p in enumerate(distribution):
                if p <= 0:
                    continue
                chosen = i
                cumulative += p
                if unit < cumulative:
                    break
        expected = step.optional_text("chosen", 16, "ml.generation.chosen")
        if expected is not None and expected != candidates[chosen][0]:
            raise step.issue("ml.generation.chosen", "chosen")
        generated.append(candidates[chosen][0])
        steps.append({"candidates": [t for t, _ in candidates], "probabilities": distribution})
    return {"generated": generated, "steps": steps, "selection": mode, "seed": seed}


def dot(a, b):
    total = 0.0
    for x, y in zip(a, b):
        total += x * y
    return total


def project(vectors, issue):
    count, dimensions = len(vectors), len(vectors[0])
    scale = max(abs(v) for row in vectors for v in row)
    if scale <= 0:
        return [[0.0, 0.0] for _ in range(count)]
    scaled = [[v / scale for v in row] for row in vectors]
    means = []
    for column in range(dimensions):
        total = 0.0
        for row in scaled:
            total += row[column]
        means.append(total / count)
    centered = [[v - m for v, m in zip(row, means)] for row in scaled]
    gram = [[dot(row, other) for other in centered] for row in centered]
    matrix = [row[:] for row in gram]
    basis = [[1.0 if r == c else 0.0 for c in range(count)] for r in range(count)]
    energy = 0.0
    for i in range(count):
        energy += gram[i][i]
    epsilon = energy * 1e-14
    for _ in range(40):
        rotated = False
        for p in range(count - 1):
            for q in range(p + 1, count):
                off = matrix[p][q]
                if not abs(off) > epsilon:
                    continue
                rotated = True
                tau = (matrix[q][q] - matrix[p][p]) / (2 * off)
                tangent = (-1.0 if tau < 0 else 1.0) / (abs(tau) + math.hypot(1, tau))
                c = 1 / math.sqrt(1 + tangent * tangent)
                s = tangent * c
                matrix[p][p] -= tangent * off
                matrix[q][q] += tangent * off
                matrix[p][q] = matrix[q][p] = 0.0
                for i in range(count):
                    if i != p and i != q:
                        left, right = matrix[i][p], matrix[i][q]
                        matrix[i][p] = c * left - s * right
                        matrix[i][q] = s * left + c * right
                        matrix[p][i] = matrix[i][p]
                        matrix[q][i] = matrix[i][q]
                    left, right = basis[i][p], basis[i][q]
                    basis[i][p] = c * left - s * right
                    basis[i][q] = s * left + c * right
        if not rotated:
            break
    leading = sorted(range(count), key=lambda i: (-matrix[i][i], i))[:2]
    axes = []
    for column in leading:
        eigenvalue = matrix[column][column]
        if not eigenvalue > epsilon:
            axes.append([0.0] * count)
            continue
        vector = [row[column] for row in basis]
        residual = [abs(dot(gram[i], vector) - eigenvalue * vector[i]) for i in range(count)]
        if not all(r <= energy * 1e-10 for r in residual):
            raise issue
        loadings = [dot([row[j] for row in centered], vector) for j in range(dimensions)]
        largest = 0.0
        for loading in loadings:
            if abs(loading) > abs(largest):
                largest = loading
        magnitude = math.sqrt(eigenvalue) * (-scale if largest < 0 else scale)
        axes.append([v * magnitude for v in vector])
    positions = [[a, b] for a, b in zip(axes[0], axes[1])]
    if not all(math.isfinite(v) for row in positions for v in row):
        raise issue
    return positions


def meaning_map(obj):
    explicit = "points" in obj.values
    if explicit == ("vectors" in obj.values):
        raise obj.issue("ml.map.coordinates", "points")
    key, coordinate = ("points", "position") if explicit else ("vectors", "vector")
    entries = obj.values.get(key)
    if not isinstance(entries, list) or not 3 <= len(entries) <= 12:
        raise obj.issue("ml.map.count", key)
    labels, vectors, seen = [], [], set()
    for index, entry in enumerate(entries):
        point = Obj(entry, f"{obj.path}.{key}[{index}]", {"label", coordinate, "imagePNG"})
        label = point.text("label", 16, "ml.map.coordinates")
        if label in seen:
            raise point.issue("ml.map.word.duplicate", "label")
        seen.add(label)
        labels.append(label)
        numbers = point.values.get(coordinate)
        size_ok = isinstance(numbers, list) and (len(numbers) == 2 if explicit else 3 <= len(numbers) <= 32)
        if not size_ok or (vectors and len(vectors[0]) != len(numbers)):
            raise point.issue("ml.map.vector.length", coordinate)
        row = []
        for j, value in enumerate(numbers):
            if not is_number(value) or isinstance(value, bool) or not math.isfinite(value) or abs(value) > 1e12:
                raise point.issue("ml.map.coordinates", f"{coordinate}[{j}]")
            row.append(float(value))
        vectors.append(row)
        if "imagePNG" in point.values:
            raise Unsupported("imagePNG map entries need the Swift PNG decoder")
    citation = obj.optional_text("vectorCitation", 120, "ml.map.coordinates")
    if citation is not None and explicit:
        raise obj.issue("ml.map.coordinates", "vectorCitation")
    positions = vectors if explicit else project(vectors, obj.issue("ml.map.coordinates", key))
    neighbors = []
    if "nearestNeighbors" in obj.values:
        setting = obj.values["nearestNeighbors"]
        if not isinstance(setting, bool):
            raise obj.issue("ml.map.cosine", "nearestNeighbors")
        if setting and explicit:
            for a in range(len(positions)):
                best, distance = a, math.inf
                for b in range(len(positions)):
                    if b != a:
                        d = math.hypot(positions[a][0] - positions[b][0], positions[a][1] - positions[b][1])
                        if d < distance:
                            best, distance = b, d
                neighbors.append([labels[a], labels[best], distance])
        elif setting:
            unit = []
            for vector in vectors:
                top = max(abs(v) for v in vector)
                if not top > 0:
                    raise obj.issue("ml.map.cosine", key)
                scaled = [v / top for v in vector]
                norm = math.sqrt(dot(scaled, scaled))
                unit.append([v / norm for v in scaled])
            for a in range(len(unit)):
                best = None
                for b in range(len(unit)):
                    if a == b:
                        continue
                    cosine = max(-1.0, min(1.0, dot(unit[a], unit[b])))
                    if cosine > 0 and (best is None or cosine > best[1]):
                        best = (b, cosine)
                if best:
                    neighbors.append([labels[a], labels[best[0]], best[1]])
    cluster = []
    if "cluster" in obj.values:
        raw = obj.values["cluster"]
        if not isinstance(raw, list):
            raise obj.issue("ml.map.cluster", "cluster")
        selected = {w for w in raw if isinstance(w, str) and w in seen}
        if not selected or len(selected) != len(raw):
            raise obj.issue("ml.map.cluster", "cluster")
        cluster = [label for label in labels if label in selected]
    return {"mode": key, "labels": labels, "positions": positions, "neighbors": neighbors, "cluster": cluster}


def check(data):
    """Return (document, item facts) or raise Issue / Unsupported."""
    if len(data) > MAX_BYTES:
        raise Issue("ml.bytes", "")
    if b"\x00" in data:
        raise Issue("ml.json", "")
    try:
        source = data.decode("utf-8")
        root_value = json.loads(source, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (UnicodeError, ValueError, RecursionError) as error:
        raise Issue("ml.json", "") from error
    if depth(root_value) > 64:
        raise Issue("ml.json", "")
    root = Obj(root_value, "", {"v", "kind", "title", "items"})
    if not (is_number(root.values.get("v")) and not isinstance(root.values.get("v"), bool) and root.values["v"] == 1):
        raise root.issue("ml.version", "v")
    if root.values.get("kind") != "ml-explainer":
        raise root.issue("ml.kind", "kind")
    root.text("title", 64, "ml.title")
    raw_items = root.values.get("items")
    if not isinstance(raw_items, list) or not 1 <= len(raw_items) <= 4:
        raise root.issue("ml.items", "items")
    ids, facts = set(), []
    for index, value in enumerate(raw_items):
        path = f"items[{index}]"
        if not isinstance(value, dict):
            raise Issue("ml.object", path)
        kind = value.get("kind")
        if not isinstance(kind, str) or kind not in KIND_KEYS:
            raise Issue("ml.item.kind", path + ".kind")
        obj = Obj(value, path, KIND_KEYS[kind] | {"id", "kind"})
        identifier = obj.text("id", 24, "ml.item.id")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", identifier):
            raise obj.issue("ml.item.id", "id")
        if identifier in ids:
            raise obj.issue("ml.item.id.duplicate", "id")
        ids.add(identifier)
        if kind in ("pictureToNumbers", "attention"):
            raise Unsupported(kind + " needs the Swift PNG decoder")
        builder = {"visionPipeline": vision, "nextTokenProbabilities": probabilities, "agentLoop": agent,
                   "meaningMap": meaning_map, "generationLoop": generation}[kind]
        facts.append({"id": identifier, "kind": kind, "facts": builder(obj)})
    return root_value, facts


def depth(value):
    deepest, pending = 0, [(value, 1)]
    while pending:
        current, level = pending.pop()
        if isinstance(current, (list, dict)):
            deepest = max(deepest, level)
            children = current.values() if isinstance(current, dict) else current
            pending.extend((child, level + 1) for child in children)
    return deepest


def main(argv):
    if len(argv) != 2:
        print("usage: ml_check.py FILE", file=sys.stderr)
        return 2
    with open(argv[1], "rb") as stream:
        data = stream.read(MAX_BYTES + 1)
    try:
        _, facts = check(data)
    except Issue as issue:
        print(json.dumps({"ok": False, "reason": issue.reason, "location": issue.path or None}, sort_keys=True))
        return 1
    except Unsupported as error:
        print(json.dumps({"ok": None, "unsupported": str(error)}, sort_keys=True))
        return 3
    print(json.dumps({"ok": True, "items": facts}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
