#!/usr/bin/env python3
"""check-localization.py: every String(localized:defaultValue:) key used in the Swift sources
exists in App/OffMyPlate/Localizable.xcstrings (T28, AC-15 / localisation completeness).

Checks (exit 1 on any):
  - a key used in code but missing from the catalog;
  - an interpolated defaultValue whose catalog value has a different number of format
    specifiers (%@, %lld, ...) than the call has interpolations;
  - the same key used with two different defaultValues;
  - a String(localized:) call this script cannot parse (key or defaultValue not a plain literal).
A catalog value that differs from the code's defaultValue is only reported (the catalog is the
copy deck and wins at runtime).

Usage: scripts/check-localization.py [--root DIR] [--fix]
  --fix   add the missing entries (English source = the defaultValue; keys stay sorted, the file
          keeps the Xcode layout). Interpolation types are GUESSED (%lld for counts, else %@):
          review the generated values.
Needs only python3 (no Swift toolchain). Sources: Packages/Apple/Sources and App, tests excluded.
"""
import argparse
import json
import os
import re
import sys

CATALOG = "App/OffMyPlate/Localizable.xcstrings"
SOURCE_DIRS = ["Packages/Apple/Sources", "App"]
SKIP_DIR_PARTS = {"OffMyPlateUITests", ".build", "DerivedData"}
INT_HINT = re.compile(r"(count|index|number|total|minutes|days|\bn\b|\bi\b|Int|lld)", re.I)
SPEC = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:l|ll|h|hh|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSp]")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


class ParseError(Exception):
    pass


def read_string(src, i):
    """src[i] == '"': returns (parts, next_index); parts = text pieces and ('interp', expr)."""
    if src.startswith('"""', i):
        return read_multiline(src, i)
    if src[i] != '"':
        raise ParseError("non-literal string")
    i += 1
    parts, buf = [], []
    while i < len(src):
        c = src[i]
        if c == '"':
            if buf:
                parts.append("".join(buf))
            return parts, i + 1
        if c == "\\":
            n = src[i + 1]
            if n == "(":
                depth, j = 1, i + 2
                while j < len(src) and depth:
                    if src[j] == "(":
                        depth += 1
                    elif src[j] == ")":
                        depth -= 1
                    elif src[j] == '"':
                        _, j = read_string(src, j)
                        continue
                    j += 1
                if buf:
                    parts.append("".join(buf))
                    buf = []
                parts.append(("interp", src[i + 2 : j - 1]))
                i = j
                continue
            if n == "u" and src[i + 2] == "{":
                end = src.index("}", i)
                buf.append(chr(int(src[i + 3 : end], 16)))
                i = end + 1
                continue
            if n not in ESCAPES:
                raise ParseError("unknown escape")
            buf.append(ESCAPES[n])
            i += 2
            continue
        if c == "\n":
            raise ParseError("newline in string")
        buf.append(c)
        i += 1
    raise ParseError("unterminated string")


def read_multiline(src, i):
    """A \"\"\" literal without interpolation: strips the closing delimiter's indentation and
    honours a trailing backslash as a line continuation. Returns (parts, next_index)."""
    if src[i + 3] != "\n":
        raise ParseError("multi-line literal must start on a new line")
    start = i + 4
    end = start
    while True:
        end = src.find('"""', end)
        if end < 0:
            raise ParseError("unterminated multi-line string")
        if src[end - 1] != "\\":
            break
        end += 3
    body = src[start:end]
    last_nl = body.rfind("\n")
    indent = body[last_nl + 1 :]
    if indent.strip():
        raise ParseError("closing delimiter must be on its own line")
    lines = body[: last_nl if last_nl >= 0 else 0].split("\n") if last_nl >= 0 else []
    stripped = []
    for line in lines:
        if line.strip() and not line.startswith(indent):
            raise ParseError("bad indentation in multi-line string")
        stripped.append(line[len(indent) :] if line.strip() else "")
    text = "\n".join(stripped)
    if "\\(" in text:
        raise ParseError("interpolation in a multi-line literal")
    out, j = [], 0
    while j < len(text):
        if text[j] == "\\":
            n = text[j + 1]
            if n == "\n":
                j += 2
                continue
            if n not in ESCAPES:
                raise ParseError("unknown escape")
            out.append(ESCAPES[n])
            j += 2
            continue
        out.append(text[j])
        j += 1
    return ["".join(out)], end + 3


def split_args(src, start):
    """src[start] is just after '(' of the call; returns list of (label, expr_text, end_index)."""
    args, depth, i, begin = [], 1, start, start
    while i < len(src):
        c = src[i]
        if c == '"':
            _, i = read_string(src, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                args.append(src[begin:i].strip())
                return args, i
        elif c == "," and depth == 1:
            args.append(src[begin:i].strip())
            begin = i + 1
        elif src.startswith("//", i):
            i = src.index("\n", i)
            continue
        i += 1
    raise ParseError("unterminated call")


def literal(expr):
    expr = expr.strip()
    if not expr.startswith('"'):
        raise ParseError("not a plain string literal: " + expr[:40])
    parts, end = read_string(expr, 0)
    if expr[end:].strip():
        raise ParseError("literal followed by more code: " + expr[:40])
    return parts


def catalog_value(parts):
    """The catalog string for a defaultValue: interpolations become format specifiers."""
    out, count = [], 0
    for p in parts:
        if isinstance(p, tuple):
            count += 1
            out.append("%lld" if INT_HINT.search(p[1]) else "%@")
        else:
            out.append(p.replace("%", "%%"))
    return "".join(out), count


def calls_in(path, text):
    found, problems = [], []
    for m in re.finditer(r"String\(\s*localized:", text):
        line = text.count("\n", 0, m.start()) + 1
        # skip commented-out lines
        ls = text.rfind("\n", 0, m.start()) + 1
        if text[ls : m.start()].lstrip().startswith("//"):
            continue
        try:
            args, _ = split_args(text, text.index("(", m.start()) + 1)
            fields = {}
            for a in args:
                label, _, rest = a.partition(":")
                fields[label.strip()] = rest.strip()
            if fields["localized"].startswith("String.LocalizationValue("):
                continue  # dynamic key (a key looked up by name at runtime): not checkable here
            key_parts = literal(fields["localized"])
            if any(isinstance(p, tuple) for p in key_parts):
                raise ParseError("key must not be interpolated")
            key = "".join(key_parts)
            if "defaultValue" not in fields:
                problems.append(f"{path}:{line}: '{key}' has no defaultValue")
                continue
            value, n = catalog_value(literal(fields["defaultValue"]))
            comment = ""
            if "comment" in fields:
                comment = "".join(p for p in literal(fields["comment"]) if isinstance(p, str))
            found.append((key, value, n, comment, f"{path}:{line}"))
        except (ParseError, KeyError, ValueError) as e:
            problems.append(f"{path}:{line}: cannot parse String(localized:) call ({e})")
    return found, problems


def swift_files(root):
    for d in SOURCE_DIRS:
        for base, dirs, files in os.walk(os.path.join(root, d)):
            dirs[:] = [x for x in dirs if x not in SKIP_DIR_PARTS]
            for f in sorted(files):
                if f.endswith(".swift"):
                    yield os.path.join(base, f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    ap.add_argument("--fix", action="store_true")
    opts = ap.parse_args()
    root = os.path.abspath(opts.root)
    catalog_path = os.path.join(root, CATALOG)
    with open(catalog_path, encoding="utf-8") as fh:
        catalog = json.load(fh)
    strings = catalog["strings"]

    used, problems = {}, []
    for path in swift_files(root):
        with open(path, encoding="utf-8") as fh:
            found, errs = calls_in(os.path.relpath(path, root), fh.read())
        problems += errs
        for key, value, n, comment, where in found:
            if key in used and used[key][0] != value:
                problems.append(f"{where}: key '{key}' also used with a different defaultValue at {used[key][3]}")
            used.setdefault(key, (value, n, comment, where))

    missing = sorted(k for k in used if k not in strings)
    notes = []
    for key, (value, n, _comment, where) in sorted(used.items()):
        if key in strings:
            have = strings[key]["localizations"]["en"]["stringUnit"]["value"]
            specs = len(SPEC.findall(have.replace("%%", "")))
            if specs != n:
                problems.append(f"{where}: '{key}' has {n} interpolation(s) but the catalog value has {specs} specifier(s)")
            elif have != value:
                notes.append(f"note: '{key}' catalog text differs from the code's defaultValue (catalog wins)")

    if opts.fix and missing:
        for key in missing:
            value, _n, comment, _where = used[key]
            entry = {}
            if comment:
                entry["comment"] = comment
            entry["extractionState"] = "manual"
            entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": value}}}
            strings[key] = entry
        catalog["strings"] = {k: strings[k] for k in sorted(strings)}
        with open(catalog_path, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
        print(f"check-localization: added {len(missing)} entries to {CATALOG} (review interpolation types)")
        missing = []

    for n in notes:
        print(n)
    for key in missing:
        problems.append(f"{used[key][3]}: key '{key}' is missing from {CATALOG}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        print(f"check-localization: FAILED with {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"check-localization: OK ({len(used)} keys used, {len(strings)} in the catalog)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
