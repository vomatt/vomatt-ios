#!/usr/bin/env python3
"""Fails when the app looks up a string key that no locale defines.

The shared strings are copies of vomatt-web's, so a web change can delete a key the app still
shows, or rename a `{placeholder}`, which then shows as written. Checks every literal `t("key")`
in App/ against en.json + ios.en.json and zh.json + ios.zh.json, and that a call passing values on
the same line passes every placeholder its English string has.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCALES = ROOT / "App/Resources/Locales"
CALL = re.compile(r'\bt\("([^"\\]+)"(?:,\s*\[(.*))?')
PLACEHOLDER = re.compile(r"\{(\w+)\}")


def flatten(node, prefix=""):
    out = {}
    for key, value in node.items():
        path = f"{prefix}.{key}" if prefix else key
        out.update(flatten(value, path) if isinstance(value, dict) else {path: value})
    return out


def table(language):
    strings = {}
    for name in (f"{language}.json", f"ios.{language}.json"):
        strings |= flatten(json.loads((LOCALES / name).read_text()))
    return strings


used = {}
calls = []
for path in sorted((ROOT / "App").rglob("*.swift")):
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        for key, values in CALL.findall(line):
            where = f"{path.relative_to(ROOT)}:{line_number}"
            used.setdefault(key, where)
            if values:
                calls.append((key, set(re.findall(r'"(\w+)"\s*:', values)), where))

status = 0
english = table("en")
for key, passed, where in calls:
    missing = set(PLACEHOLDER.findall(english.get(key, ""))) - passed
    if missing:
        print(f"{where}: '{key}' needs {sorted(missing)}, passes {sorted(passed)}")
        status = 1
for language in ("en", "zh"):
    known = table(language)
    for key, where in sorted(used.items()):
        if key not in known:
            print(f"{where}: '{key}' is missing from {language}.json and ios.{language}.json")
            status = 1
if status == 0:
    print(f"All {len(used)} string keys the app uses exist in en and zh")
sys.exit(status)
