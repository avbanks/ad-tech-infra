#!/usr/bin/env python3
"""Strictly validate rendered custom resources against CRD schemas (unknown fields fail).

    helm template x k8s/charts/kafka-cluster --set vnetListener.ipPrefix=10.10.17 > /tmp/k.yaml
    scripts/validate-crs.py /tmp/k.yaml path/to/strimzi/crds/*.yaml

Requires: pip install pyyaml jsonschema
"""
import sys

import jsonschema
import yaml


def strict(schema):
    """Drop x-kubernetes-* keywords and forbid unknown properties unless the CRD preserves them."""
    if isinstance(schema, list):
        return [strict(s) for s in schema]
    if not isinstance(schema, dict):
        return schema
    out = {k: strict(v) for k, v in schema.items() if not k.startswith("x-kubernetes")}
    if "properties" in out and "additionalProperties" not in out and not schema.get("x-kubernetes-preserve-unknown-fields"):
        out["additionalProperties"] = False
    return out


def main(manifest, crd_files):
    schemas = {}
    for f in crd_files:
        for d in yaml.safe_load_all(open(f)):
            if d and d.get("kind") == "CustomResourceDefinition":
                for v in d["spec"]["versions"]:
                    schemas[(f'{d["spec"]["group"]}/{v["name"]}', d["spec"]["names"]["kind"])] = v["schema"]["openAPIV3Schema"]

    failed = False
    for doc in yaml.safe_load_all(open(manifest)):
        if not doc:
            continue
        key = (doc["apiVersion"], doc["kind"])
        if key not in schemas:
            continue  # built-in kind
        schema = strict(schemas[key])
        schema.setdefault("properties", {})["metadata"] = {"type": "object"}
        body = {k: v for k, v in doc.items() if k not in ("apiVersion", "kind")}
        try:
            jsonschema.validate(body, schema)
            print(f"OK    {doc['kind']}/{doc['metadata']['name']}")
        except jsonschema.ValidationError as e:
            failed = True
            print(f"FAIL  {doc['kind']}/{doc['metadata']['name']}: {e.message} at {list(e.absolute_path)}")
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2:]))
