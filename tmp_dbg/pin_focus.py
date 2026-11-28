"""Adds focus_<id> gate probes (variants ["focus"]) pinned to the measured focus values."""
import json, subprocess, sys

ROOT = "C:/Users/chris/Documents/simple-war-worktrees/ap-sw-pd2l.4"
IDS = sys.argv[1:]
KINDS = ["first_kill", "mean_kill", "wipe", "waste", "victims"]
for sid in IDS:
    out = subprocess.run(["C:/Program Files/Git/bin/bash.exe", "harness/bin/hx", "godot", "run", "res://src/api/workshop/workshop_cli.gd", "--",
                          "--scenario", sid, "--variant", "focus", "--json"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    out = out.stdout + out.stderr
    body = out[out.index("WORKSHOP_JSON_BEGIN") + len("WORKSHOP_JSON_BEGIN"):out.index("WORKSHOP_JSON_END")]
    body = "\n".join(l.strip() for l in body.splitlines())
    rep = json.loads(body)["scenarios"][0]
    vals = {}
    for var in rep.get("variants", []):
        if var.get("variant") == "focus" or var.get("name") == "focus":
            for p in var.get("probes", []):
                vals[p["id"]] = p.get("value")
    if not vals:
        print("no focus values", sid, json.dumps(rep)[:800]); continue
    path = f"{ROOT}/data/sim/workshop/{sid}.json"
    d = json.load(open(path, encoding="utf-8"))
    new = []
    for p in d["probes"]:
        if "variants" in p or p["id"].startswith("focus_"):
            continue
        kind = next((k for k in KINDS if k in p), None)
        if kind is None or p.get(kind) is None:
            continue
        v = vals.get(p["id"])
        if kind == "victims" and isinstance(v, dict):
            v = {k: int(x) for k, x in v.items()}
        elif isinstance(v, float) and v.is_integer() and kind != "waste":
            v = int(v)
        q = {k: p[k] for k in ("over", "squad", "target") if k in p}
        np = {"id": "focus_" + p["id"], **q, kind: v, "variants": ["focus"]}
        new.append(np)
    d["probes"] = [p for p in d["probes"] if not p["id"].startswith("focus_")] + new
    open(path, "w", encoding="utf-8", newline="").write(json.dumps(d, indent="\t", ensure_ascii=False) + "\n")
    print(sid, [(p["id"], p[next(k for k in KINDS if k in p)]) for p in new])
