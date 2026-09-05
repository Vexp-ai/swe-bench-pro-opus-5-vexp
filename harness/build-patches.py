#!/usr/bin/env python3
"""Collect preds/*.patch into patches.json, the official harness's input."""
import glob, json, os
k = os.path.dirname(os.path.abspath(__file__))
out = []
for p in sorted(glob.glob(f"{k}/preds/*.patch")):
    patch = open(p, encoding="utf-8", errors="replace").read()
    if patch.strip():
        out.append({"instance_id": os.path.basename(p)[:-6], "patch": patch})
json.dump(out, open(f"{k}/patches.json", "w"))
print(f"{len(out)} non-empty patches -> patches.json")
