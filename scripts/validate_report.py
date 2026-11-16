"""Validates the PBIR files against Microsoft's JSON schemas and every field binding against the semantic model."""
import glob
import json
import os
import re
import tempfile
import urllib.request
from jsonschema import Draft7Validator
from referencing import Registry, Resource

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(PROJECT, "microdrama-market-study.Report", "definition")
TABLES = os.path.join(PROJECT, "microdrama-market-study.SemanticModel", "definition", "tables")
CACHE = os.path.join(tempfile.gettempdir(), "pbir_schema_cache"); os.makedirs(CACHE, exist_ok=True)
SUB = {"visualContainer/2.14.0": "visualContainer/2.13.0"}


def fetch(uri):
    for a, b in SUB.items(): uri = uri.replace(a, b)
    raw = uri.replace("https://developer.microsoft.com/json-schemas/", "https://raw.githubusercontent.com/microsoft/json-schemas/main/")
    fn = os.path.join(CACHE, raw.split("/main/")[1].replace("/", "_"))
    if not os.path.exists(fn): urllib.request.urlretrieve(raw, fn)
    return json.load(open(fn, encoding="utf-8"))


registry = Registry(retrieve=lambda u: Resource.from_contents(fetch(u)))
files = sorted(set(glob.glob(os.path.join(ROOT, "**", "*.json"), recursive=True))); bad = 0
for f in files:
    doc = json.load(open(f, encoding="utf-8")); uri = doc.get("$schema")
    if not uri: continue
    for a, b in SUB.items(): uri = uri.replace(a, b)
    doc["$schema"] = uri
    errs = list(Draft7Validator(fetch(uri), registry=registry).iter_errors(doc))
    if errs:
        bad += 1; print("SCHEMA FAIL", f.replace(ROOT, ""))
        for e in errs[:5]: print("   ", "/".join(map(str, e.path)), "->", e.message[:200])
print(f"schema: {len(files)} files, {bad} with errors")

model = {}
for t in glob.glob(os.path.join(TABLES, "*.tmdl")):
    name = os.path.basename(t)[:-5]; txt = open(t, encoding="utf-8").read()
    names = set()
    for m in re.finditer(r"^\t(?:column|measure) ('[^']+'|[^\s=]+)", txt, re.M): names.add(m.group(1).strip("'"))
    model[name] = names


def walk(o):
    if isinstance(o, dict):
        for k in ("Column", "Measure"):
            if k in o and isinstance(o[k], dict) and "Property" in o[k] and "SourceRef" in o[k].get("Expression", {}) and "Entity" in o[k]["Expression"]["SourceRef"]:
                yield o[k]["Expression"]["SourceRef"]["Entity"], o[k]["Property"]
        for v in o.values(): yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)


vis = glob.glob(os.path.join(ROOT, "pages", "*", "visuals", "*", "visual.json")); n = miss = 0; names = {}
for f in vis:
    d = json.load(open(f, encoding="utf-8")); names[d["name"]] = f
    for e, p in walk(d):
        n += 1
        if p not in model.get(e, ()):
            miss += 1; print("BINDING FAIL", e, p, os.path.basename(os.path.dirname(f)))
print(f"bindings: {n} checked, {miss} missing, across {len(vis)} visuals")
for p in glob.glob(os.path.join(ROOT, "pages", "*", "page.json")):
    d = json.load(open(p, encoding="utf-8"))
    for i in d.get("visualInteractions", []):
        if i["source"] not in names or i["target"] not in names: print("INTERACTION FAIL", i)
    w = [json.load(open(x, encoding="utf-8"))["position"] for x in glob.glob(os.path.join(os.path.dirname(p), "visuals", "*", "visual.json"))]
    off = [q for q in w if q["x"] + q["width"] > 1280 or q["y"] + q["height"] > 720]
    print(d["displayName"], len(w), "visuals", "OFF CANVAS: " + str(off) if off else "in bounds")
