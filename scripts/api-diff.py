#!/usr/bin/env python3
"""Summarizes what changed between two OpenAPI documents.

Lists operations added, removed or changed (parameters, request body,
responses) and schemas whose properties, required fields or enums changed,
so an API update can be read in one screen before it is committed.

Usage: api-diff.py <old openapi.json> <new openapi.json>
Exit code 0 always; the report is the output.
"""

import json
import sys


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

    old_ops, new_ops = operations(old), operations(new)
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

    old_schemas = old.get("components", {}).get("schemas", {})
    new_schemas = new.get("components", {}).get("schemas", {})
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

    print("\n".join(report) if report else "No contract changes.")


if __name__ == "__main__":
    main()
