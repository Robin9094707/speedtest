#!/usr/bin/env python3
import json
from pathlib import Path

devices = json.loads(Path("build/simulators.json").read_text())["devices"]
options = []
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.split("iOS-")[1].split("-"))
    if version[0] < 26:
        continue
    for entry in entries:
        if entry.get("isAvailable") and entry["name"].startswith("iPhone"):
            score = ("Pro" in entry["name"], "Max" in entry["name"], version, entry["name"])
            options.append((score, entry["udid"]))
if not options:
    raise SystemExit("Kein verfügbarer iPhone-Simulator mit iOS 26 oder neuer gefunden.")
print("SIMULATOR_ID=" + max(options)[1])
