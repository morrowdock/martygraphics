# SPDX-License-Identifier: Apache-2.0
"""Inventory platform imports and symbols for the portability map (step 1 of the proposal).

Static text scan only: it never builds, imports or runs Swift. It strips comments and string
literals, reads `import` lines, counts platform symbols, follows MG/ML type references between
files and lists public declarations whose signatures name platform types.

  python3 tools/portability_map.py            print the generated Markdown
  python3 tools/portability_map.py --write    refresh the generated block in docs/PORTABILITY-MAP.md
  python3 tools/portability_map.py --check    exit 1 when that block is stale
"""

import argparse
import ast
from collections import Counter, defaultdict
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/PORTABILITY-MAP.md"
BEGIN = "<!-- BEGIN GENERATED: tools/portability_map.py -->"
END = "<!-- END GENERATED: tools/portability_map.py -->"
SCAN = ("Sources", "tools")
PACKAGE_MODULES = {"MartyGraphics", "MartyGraphicsMLKit", "MartyGraphicsPathTracer", "SceneValidatorCore"}
GROUPS = ("Foundation-only", "CoreGraphics", "SwiftUI", "SceneKit", "AppKit/UIKit", "simd", "Combine", "other")
# Most restrictive first: a file's primary group is the first group it imports.
PRECEDENCE = ("AppKit/UIKit", "SceneKit", "SwiftUI", "Combine", "simd", "CoreGraphics", "other", "Foundation-only")
FRAMEWORK_GROUP = {"Foundation": "Foundation-only", "CoreGraphics": "CoreGraphics", "SwiftUI": "SwiftUI",
                   "SceneKit": "SceneKit", "AppKit": "AppKit/UIKit", "UIKit": "AppKit/UIKit",
                   "simd": "simd", "Combine": "Combine"}

# Core candidates named by docs/PORTABILITY-PROPOSAL.md (model, parser, validation, grammar,
# patches/streams, timeline, templates/packs) plus the number formatter every label uses.
CORE = {
    "Sources/MartyGraphics/MGModel.swift": "model, limits-adjacent JSON value",
    "Sources/MartyGraphics/MGParser.swift": "parser, limits, validation",
    "Sources/MartyGraphics/MGGrammar.swift": "grammar document",
    "Sources/MartyGraphics/MGPatch.swift": "patch transactions",
    "Sources/MartyGraphics/MGStream.swift": "stream preview and finalization",
    "Sources/MartyGraphics/MGTimeline.swift": "timeline, blend",
    "Sources/MartyGraphics/MGTemplates.swift": "templates, parameter validation",
    "Sources/MartyGraphics/MGPack.swift": "pack registry and pack validation",
    "Sources/MartyGraphics/MGGraphPack.swift": "opt-in graph pack",
    "Sources/MartyGraphics/MGGeometryPack.swift": "opt-in geometry pack",
    "Sources/MartyGraphics/MGFixtures.swift": "built-in synthetic fixtures",
    "Sources/MartyGraphics/MGPhysics.swift": "closed-form values, number formatting",
}

SYMBOLS = {
    "CoreGraphics": r"\bCG[A-Z]\w*",
    "SwiftUI": r"\b(?:Color|Font|GraphicsContext|Canvas|Angle|Gradient|StrokeStyle|GeometryReader|TimelineView|"
               r"ViewBuilder|withAnimation)\b|@(?:State|Binding|StateObject|ObservedObject|Environment)\b|"
               r"\bsome View\b|:\s*View\b",
    "SceneKit": r"\bSCN\w+",
    "simd": r"\bsimd_\w+|\bSIMD[234]\b",
    "AppKit/UIKit": r"\b(?:NS|UI)(?:Color|Image|Font|View|ViewRepresentable|ViewController|Screen|Application|"
                    r"GestureRecognizer|Event|BezierPath|GraphicsImageRenderer)\w*",
    "Combine": r"\b(?:ObservableObject|AnyCancellable|PassthroughSubject|CurrentValueSubject|objectWillChange)\b|@Published\b",
    "CoreText": r"\bkCT\w+|\bCT[A-Z]\w*",
    "CoreFoundation bridge": r"\bkCF\w+|\bCF[A-Z]\w*",
    "Foundation bridge": r"\b(?:NSNumber|NSNull|NSString|NSAttributedString|NSRegularExpression|JSONSerialization|"
                         r"CharacterSet|NumberFormatter|autoreleasepool|Bundle)\b|\bString\(format:",
    "locks/global state": r"\b(?:NSLock|NSRecursiveLock|os_unfair_lock\w*|OSAllocatedUnfairLock|DispatchQueue)\b|"
                          r"\bnonisolated\(unsafe\)",
    "AVFoundation/ImageIO/UTType": r"\bAV[A-Z]\w*|\bCGImage(?:Source|Destination)\w*|\bUTType\b",
    "Metal": r"\bMTL\w+",
    "Darwin/os": r"\b(?:os_log|Logger|OSSignposter|mach_\w+)\b",
}
# Symbol categories that block a non-Apple build outright (CoreFoundation and Foundation bridges
# and locks exist in swift-corelibs-foundation but with different behavior; they are seams).
HARD = ("CoreGraphics", "SwiftUI", "SceneKit", "simd", "AppKit/UIKit", "Combine", "CoreText",
        "AVFoundation/ImageIO/UTType", "Metal", "Darwin/os")
PLATFORM_TYPE = re.compile("|".join(f"(?:{SYMBOLS[name]})" for name in HARD))
UNTYPED = re.compile(r"(?<![\w.])Any(?![\w.])")
LOCAL_DECL = re.compile(r"\b(?:struct|enum|class|protocol|actor|typealias)\s+(\w+)")
DECL = re.compile(r"\b(?:struct|enum|class|protocol|actor|typealias)\s+((?:MG|ML|Marty)\w*)")
SCOPE = re.compile(r"\b(?:struct|enum|class|protocol|actor|extension)\s+([A-Za-z_][\w.]*)")
IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+(?:(?:struct|class|enum|func|var|let|typealias|protocol)\s+)?(\w+)", re.M)


def norm(token):
    """`: View` and `some View` name the SwiftUI type `View`."""
    return re.sub(r"^(?::\s*|some\s+)", "", token)


def platform_tokens(signature, local):
    return {norm(t) for t in PLATFORM_TYPE.findall(signature)} - local


def strip_swift(source):
    """Blank comments and string literals, keeping newlines so line structure survives."""
    out, i, n = [], 0, len(source)
    while i < n:
        if source.startswith("//", i):
            j = source.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif source.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if source.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif source.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            out.append(re.sub(r"[^\n]", " ", source[i:j]))
            i = j
        elif source[i] in "#\"":
            match = re.match(r'(#*)("""|")', source[i:])
            if not match:
                out.append(source[i])
                i += 1
                continue
            hashes, quote = match.groups()
            close = quote + hashes
            j = i + len(hashes) + len(quote)
            while j < n and not source.startswith(close, j):
                j += 2 if source[j] == "\\" and not hashes else 1
            j = min(n, j + len(close))
            out.append('"' + re.sub(r"[^\n]", " ", source[i + 1:j - 1]) + '"')
            i = j
        else:
            out.append(source[i])
            i += 1
    return "".join(out)


def scanned(path):
    """False under a hidden folder: build outputs such as the generated Swift that `swift build --package-path
    tools/SceneValidator` leaves in tools/SceneValidator/.build, or a virtual environment. They are not sources, and
    counting them makes `--check` fail in any checkout where a package was built."""
    return not any(part.startswith(".") for part in path.relative_to(ROOT).parts[:-1])


def swift_files():
    # Sort by the POSIX path string: Windows Path ordering ignores case, which would change the output.
    return sorted((p for top in SCAN for p in (ROOT / top).rglob("*.swift") if scanned(p)), key=rel)


def rel(path):
    return path.relative_to(ROOT).as_posix()


def module_of(name):
    parts = name.split("/")
    if parts[0] == "Sources":
        return parts[1]
    if parts[:2] == ["tools", "SceneValidator"]:
        return "tools/SceneValidator/" + ("Tests" if "Tests" in parts else parts[3] if len(parts) > 4 else "Package.swift")
    return "/".join(parts[:2])


def groups_of(imports):
    found = {FRAMEWORK_GROUP.get(name, "package" if name in PACKAGE_MODULES else "other") for name in imports}
    return found - {"package"}


def primary(imports):
    found = groups_of(imports)
    for group in PRECEDENCE:
        if group in found:
            return group
    return "other"


def public_decls(code):
    """(scope, signature) for each public/open declaration, attributed to its enclosing type."""
    stack, pending, depth, out = [], None, 0, []
    i, n = 0, len(code)
    while i < n:
        char = code[i]
        if char == "{":
            depth += 1
            if pending is not None:
                stack.append((pending, depth))
                pending = None
        elif char == "}":
            if stack and stack[-1][1] == depth:
                stack.pop()
            depth -= 1
        elif (char.isalpha() or char == "_") and (i == 0 or not (code[i - 1].isalnum() or code[i - 1] in "_.@")):
            word = re.match(r"\w+", code[i:]).group()
            if word in ("struct", "enum", "class", "protocol", "actor", "extension"):
                match = SCOPE.match(code, i)
                if match and not (word == "class" and re.match(r"class\s+(?:func|var|let)\b", code[i:])):
                    pending = match.group(1)
            if word in ("public", "open"):
                sig, j, parens = [], i, 0
                while j < n:
                    c = code[j]
                    if c in "([<":
                        parens += 1
                    elif c in ")]>" and parens:
                        parens -= 1
                    elif parens == 0 and (c == "{" or c == "\n" or (c == "=" and code[j + 1:j + 2] != "=")):
                        break
                    sig.append(c)
                    j += 1
                text = re.sub(r"\s+", " ", "".join(sig)).strip()
                scope = ".".join(name for name, _ in stack)
                head = DECL.search(text) or SCOPE.search(text)
                if head and re.match(r"(?:public|open)\s+(?:final\s+|indirect\s+)*(?:struct|enum|class|protocol|actor|typealias|extension)\b", text):
                    scope = ".".join(filter(None, (scope, head.group(1))))
                out.append((scope or "(top level)", text))
            i += len(word)
            continue
        i += 1
    return out


def scan():
    files = []
    declared = {}
    for path in swift_files():
        raw = path.read_text(encoding="utf-8")
        code = strip_swift(raw)
        name = rel(path)
        imports = sorted(set(IMPORT.findall(code)))
        conditional = sorted(set(re.findall(r"#if\s+canImport\((\w+)\)", raw)))
        local = set(LOCAL_DECL.findall(code))
        symbols = {cat: sorted({norm(hit) for hit in re.findall(rx, code)} - local) for cat, rx in SYMBOLS.items()}
        symbols = {cat: hits for cat, hits in symbols.items() if hits}
        types = sorted(set(DECL.findall(code)))
        for t in types:
            declared.setdefault(t, name)
        files.append({"path": name, "module": module_of(name), "imports": imports, "conditional": conditional,
                      "code": code, "symbols": symbols, "types": types, "local": local, "public": public_decls(code)})
    for f in files:
        refs = defaultdict(set)
        for token in set(re.findall(r"\b(?:MG|ML|Marty)\w+", f["code"])):
            owner = declared.get(token)
            if owner and owner != f["path"]:
                refs[owner].add(token)
        f["refs"] = {k: sorted(v) for k, v in refs.items()}
    return files


def hard_symbols(f):
    return {cat: f["symbols"][cat] for cat in HARD if cat in f["symbols"]}


def blocked(f):
    """True when the file imports a non-Foundation framework or uses a hard platform symbol."""
    non_foundation = groups_of(f["imports"]) - {"Foundation-only"}
    return bool(non_foundation or hard_symbols(f))


def short(items, limit=6):
    items = list(items)
    text = ", ".join(f"`{x}`" for x in items[:limit])
    return text + (f" +{len(items) - limit}" if len(items) > limit else "")


def closure(start, by_path):
    """Files reachable from `start` through MG/ML type references, with one witness path each."""
    seen, queue = {start: [start]}, [start]
    while queue:
        current = queue.pop(0)
        for target in sorted(by_path[current]["refs"]):
            if target not in seen:
                seen[target] = seen[current] + [target]
                queue.append(target)
    return seen


def python_rows():
    rows = []
    for path in sorted((p for p in (ROOT / "tools").rglob("*.py") if scanned(p)), key=rel):
        code = ast.parse(path.read_text(encoding="utf-8"), filename=rel(path))
        names = set()
        for node in ast.walk(code):
            if isinstance(node, ast.Import):
                names.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    names.add("." * node.level + node.module.split(".")[0])
                else:
                    names.update("." * node.level + alias.name for alias in node.names)
        rows.append((rel(path), sorted(names)))
    return rows


def render():
    files = scan()
    by_path = {f["path"]: f for f in files}
    lines = [BEGIN, "", "_Generated by `python3 tools/portability_map.py --write`; a static text scan, not a build._", ""]

    sources = [f for f in files if f["path"].startswith("Sources/")]
    tool_files = [f for f in files if not f["path"].startswith("Sources/")]
    lines += ["### Counts", "",
              "Each Swift file counts once under its most restrictive import (AppKit/UIKit, SceneKit, SwiftUI, Combine,",
              "simd, CoreGraphics, other, Foundation-only). `other` covers AVFoundation, CoreText, ImageIO,",
              "UniformTypeIdentifiers, Metal, os, Darwin, XCTest, PackageDescription and files that import only a",
              "package module or nothing. Package imports do not affect the primary group.",
              "The second count is every file importing the group at all.", "",
              "| Group | Sources (primary) | Sources (any import) | tools (primary) | tools (any import) |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for group in GROUPS:
        def count(rows, any_import):
            return sum(1 for f in rows if (group in groups_of(f["imports"]) if any_import else primary(f["imports"]) == group))
        lines.append(f"| {group} | {count(sources, False)} | {count(sources, True)} | {count(tool_files, False)} | {count(tool_files, True)} |")
    foundation_only = [f for f in sources if primary(f["imports"]) == "Foundation-only"]
    leaky = [f for f in foundation_only if hard_symbols(f)]
    lines += ["", f"Swift files scanned: {len(sources)} under `Sources/`, {len(tool_files)} under `tools/`. "
              f"Foundation-only files that still use a hard platform symbol: {len(leaky)} "
              "(Darwin Foundation re-exports CoreGraphics geometry types).", ""]

    lines += ["### Core candidates", "",
              "Direct = what the file itself names. Via = the first package file with a non-Foundation import or",
              "hard platform symbol that the candidate reaches through MG/ML type references (witness path shown).",
              "Foundation and CoreFoundation bridges are seams, not hard blockers: swift-corelibs-foundation has",
              "most of them, with behavior that has not been compared here.", "",
              "| File | Role | Direct hard symbols | Foundation / CF / lock seams | Reaches platform code via |",
              "| --- | --- | --- | --- | --- |"]
    for path, role in CORE.items():
        f = by_path[path]
        direct = "; ".join(f"{cat}: {short(hits, 4)}" for cat, hits in hard_symbols(f).items()) or "none"
        seams = "; ".join(f"{cat}: {short(f['symbols'][cat], 4)}"
                          for cat in ("CoreFoundation bridge", "Foundation bridge", "locks/global state")
                          if cat in f["symbols"]) or "none"
        reach = closure(path, by_path)
        hops = []
        for target, trail in sorted(reach.items(), key=lambda kv: (len(kv[1]), kv[0])):
            if target != path and blocked(by_path[target]) and not any(t in trail[:-1] and blocked(by_path[t]) for t in trail[1:-1]):
                prev = by_path[trail[-2]]
                via = short(prev["refs"][target], 3)
                hops.append(f"`{Path(target).name}` ({via}; {' → '.join(Path(t).stem for t in trail)})")
        lines.append(f"| `{Path(path).name}` | {role} | {direct} | {seams} | {'<br>'.join(hops[:4]) or 'none found'}"
                     f"{' +' + str(len(hops) - 4) if len(hops) > 4 else ''} |")
    lines.append("")

    lines += ["### Public declarations that name platform types", "",
              "The scan counts explicit `public` or `open` declarations in `Sources/`. It matches known",
              "platform names and `Any` in the signature text. This is a partial API inventory.", "",
              "| Module | Public declarations | Name platform types | Name `Any` |", "| --- | ---: | ---: | ---: |"]
    by_module = defaultdict(list)
    for f in sources:
        for scope, sig in f["public"]:
            by_module[f["module"]].append((f["path"], scope, sig, platform_tokens(sig, f["local"])))
    for module in sorted(by_module):
        decls = by_module[module]
        plat = sum(1 for *_, tokens in decls if tokens)
        untyped = sum(1 for _, _, s, _ in decls if UNTYPED.search(s))
        lines.append(f"| {module} | {len(decls)} | {plat} | {untyped} |")
    lines.append("")
    for module in sorted(by_module):
        rows = defaultdict(lambda: [0, Counter(), set()])
        for path, scope, sig, tokens in by_module[module]:
            entry = rows[(scope, Path(path).name)]
            entry[0] += 1
            entry[1].update(tokens)
            if UNTYPED.search(sig):
                entry[2].add("Any")
        exposing = {k: v for k, v in rows.items() if v[1] or v[2]}
        lines += [f"#### {module}: public scopes with matching signatures", "",
                  f"{len(rows)} scope/file pairs scanned, of which {len(exposing)} match.", ""]
        if exposing:
            lines += ["| Type (scope) | File | Public decls | Platform tokens | Untyped |", "| --- | --- | ---: | --- | --- |"]
            for (scope, fname), (total, tokens, untyped) in sorted(exposing.items()):
                lines.append(f"| `{scope}` | `{fname}` | {total} | {short(sorted(tokens), 5) or '—'} | {'`Any`' if untyped else '—'} |")
            lines.append("")

    lines += ["### Imports per Swift file", "",
              "| File | Primary group | Imports | `#if canImport` | Hard platform symbols (sample) |",
              "| --- | --- | --- | --- | --- |"]
    for f in files:
        hard = hard_symbols(f)
        sample = "; ".join(f"{cat}: {short(hits, 3)}" for cat, hits in hard.items()) or "—"
        lines.append(f"| `{f['path']}` | {primary(f['imports'])} | {', '.join(f['imports']) or '—'} | "
                     f"{', '.join(f['conditional']) or '—'} | {sample} |")
    lines += ["", "### Python tooling imports", "",
              "Python files under `tools/` are listed with their static Python imports.", "",
              "| File | Imports |", "| --- | --- |"]
    for name, imports in python_rows():
        lines.append(f"| `{name}` | {', '.join(imports) or '—'} |")
    lines += ["", END]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    block = render()
    if not (args.write or args.check):
        sys.stdout.buffer.write(block.encode("utf-8"))
        return 0
    doc = DOC.read_text(encoding="utf-8")
    start, end = doc.find(BEGIN), doc.find(END)
    if start < 0 or end < start:
        print("Generated markers missing in " + rel(DOC), file=sys.stderr)
        return 1
    updated = doc[:start] + block.rstrip("\n") + doc[end + len(END):]
    if args.check:
        if updated != doc:
            print("Stale generated block in " + rel(DOC) + "; run tools/portability_map.py --write", file=sys.stderr)
            return 1
        print("PASS: portability map is current")
        return 0
    DOC.write_text(updated, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
