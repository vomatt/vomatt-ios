#!/usr/bin/env python3
"""Summarizes what changed between two OpenAPI documents.

Lists operations added, removed or changed (parameters, request body,
responses) and schemas whose properties, required fields or enums changed,
so an API update can be read in one screen before it is committed.

Only what the app can call is reported: operations tagged with one of the
tags in openapi-generator-config.yaml (`filter.tags`) or listed in
`filter.operations`, and the schemas they reach. Other operations sharing a
tag with a listed one are named with `?`, so a new one isn't missed. The
admin endpoints belong to the admin console, so their changes are counted on
stderr, not reported.

Usage: api-diff.py <old openapi.json> <new openapi.json>
Exit code 0 always; the report is the output.
"""

import json
import os
import sys

CONFIG = os.path.join(os.path.dirname(__file__), "..", "Packages", "VomattKit", "Sources", "VomattAPI",
                      "openapi-generator-config.yaml")


def app_filter():
    """The `filter.tags` and `filter.operations` lists of the generator config (plain YAML lists, so no
    YAML parser)."""
    lists, in_filter, current = {"tags": set(), "operations": set()}, False, None
    for line in open(CONFIG):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            in_filter, current = stripped == "filter:", None
        elif in_filter and stripped.rstrip(":") in lists:
            current = lists[stripped.rstrip(":")]
        elif current is not None and stripped.startswith("- "):
            current.add(stripped[2:].strip().strip("'\""))
        elif in_filter:
            current = None
    return lists


def is_app_op(op, app):
    return bool(app["tags"] & set(op.get("tags", []))) or op.get("operationId") in app["operations"]


def reachable_schemas(doc, app):
    """Schema names referenced, directly or through other schemas, by the app's operations."""
    schemas = doc.get("components", {}).get("schemas", {})
    found, stack = set(), []

    def refs(node):
        if isinstance(node, dict):
            ref = node.get("$ref", "")
            if ref.startswith("#/components/schemas/"):
                stack.append(ref.rsplit("/", 1)[-1])
            for value in node.values():
                refs(value)
        elif isinstance(node, list):
            for value in node:
                refs(value)

    for op in operations(doc).values():
        if is_app_op(op, app):
            refs(op)
    while stack:
        name = stack.pop()
        if name not in found and name in schemas:
            found.add(name)
            refs(schemas[name])
    return found


def operations(doc):
    ops = {}
    for path, item in doc.get("paths", {}).items():
        for method, op in item.items():
            if method in {"get", "post", "put", "patch", "delete"}:
                ops[f"{method.upper()} {path}"] = op
    return ops


def op_shape(op):
    params = sorted(
        f"{p.get('in')}:{p.get('name')}{'!' if p.get('required') else ''}"
        for p in op.get("parameters", [])
    )
    body = json.dumps(op.get("requestBody", {}).get("content", {}), sort_keys=True)
    responses = sorted(op.get("responses", {}).keys())
    return {"params": params, "body": body, "responses": responses}


def schema_shape(schema):
    props = schema.get("properties", {})
    return {
        "properties": {
            name: (prop.get("type") or prop.get("$ref", "").rsplit("/", 1)[-1],
                   prop.get("format"), bool(prop.get("nullable")), tuple(prop.get("enum", [])))
            for name, prop in props.items()
        },
        "required": sorted(schema.get("required", [])),
        "enum": schema.get("enum"),
    }


def main():
    old, new = (json.load(open(path)) for path in sys.argv[1:3])
    report = []
    app = app_filter()

    all_old_ops, all_new_ops = operations(old), operations(new)
    old_ops = {key: op for key, op in all_old_ops.items() if is_app_op(op, app)}
    new_ops = {key: op for key, op in all_new_ops.items() if is_app_op(op, app)}
    for key in sorted(new_ops.keys() - old_ops.keys()):
        report.append(f"+ operation  {key}  ({new_ops[key].get('operationId')})")
    for key in sorted(old_ops.keys() - new_ops.keys()):
        report.append(f"- operation  {key}  ({old_ops[key].get('operationId')})")
    for key in sorted(old_ops.keys() & new_ops.keys()):
        before, after = op_shape(old_ops[key]), op_shape(new_ops[key])
        for field in before:
            if before[field] != after[field]:
                detail = ""
                if field != "body":
                    added = sorted(set(after[field]) - set(before[field]))
                    removed = sorted(set(before[field]) - set(after[field]))
                    detail = f" +{added} -{removed}"
                report.append(f"~ operation  {key}  {field} changed{detail}")
        if old_ops[key].get("description") != new_ops[key].get("description"):
            report.append(f"~ operation  {key}  description changed")

    used = reachable_schemas(old, app) | reachable_schemas(new, app)
    old_schemas = {k: v for k, v in old.get("components", {}).get("schemas", {}).items() if k in used}
    new_schemas = {k: v for k, v in new.get("components", {}).get("schemas", {}).items() if k in used}
    for name in sorted(new_schemas.keys() - old_schemas.keys()):
        report.append(f"+ schema     {name}")
    for name in sorted(old_schemas.keys() - new_schemas.keys()):
        report.append(f"- schema     {name}")
    for name in sorted(old_schemas.keys() & new_schemas.keys()):
        before, after = schema_shape(old_schemas[name]), schema_shape(new_schemas[name])
        for prop in sorted(after["properties"].keys() - before["properties"].keys()):
            report.append(f"+ property   {name}.{prop}  {after['properties'][prop]}")
        for prop in sorted(before["properties"].keys() - after["properties"].keys()):
            report.append(f"- property   {name}.{prop}")
        for prop in sorted(before["properties"].keys() & after["properties"].keys()):
            if before["properties"][prop] != after["properties"][prop]:
                report.append(
                    f"~ property   {name}.{prop}  {before['properties'][prop]} -> {after['properties'][prop]}"
                )
        if before["required"] != after["required"]:
            report.append(f"~ required   {name}  {before['required']} -> {after['required']}")
        if before["enum"] != after["enum"]:
            report.append(f"~ enum       {name}  {before['enum']} -> {after['enum']}")

    skipped = [key for key in all_old_ops.keys() | all_new_ops.keys()
               if key not in old_ops and key not in new_ops
               and json.dumps(all_old_ops.get(key), sort_keys=True) != json.dumps(all_new_ops.get(key), sort_keys=True)]
    # Tags included op by op (Auth): their other operations may be new ones the app needs, so name them
    listed_tags = {tag for op in {**old_ops, **new_ops}.values() for tag in op.get("tags", [])} - app["tags"]
    for key in sorted(skipped):
        op = all_new_ops.get(key) or all_old_ops[key]
        tags = listed_tags & set(op.get("tags", []))
        if tags:
            report.append(f"? operation  {key}  ({op.get('operationId')}) tagged {', '.join(sorted(tags))},"
                          " not in filter.operations")
    skipped = [key for key in skipped if not listed_tags & set((all_new_ops.get(key) or all_old_ops[key]).get("tags", []))]

    print("\n".join(report) if report else "No contract changes.")
    if skipped:
        print(f"({len(skipped)} admin operation(s) changed; not used by the app, skipped)", file=sys.stderr)


if __name__ == "__main__":
    main()
