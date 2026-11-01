import argparse
import json

from hx.commands import godot as godot_cmd
from hx.commands import task


def test_godot_errors_keep_location_and_dedupe():
    lines = [
        "Godot Engine v4.7.2",
        "SCRIPT ERROR: Parse Error: Identifier \"GUIDE\" not declared in the current scope.",
        "          at: GDScript::reload (res://addons/guide/x.gd:149)",
        "WARNING: something harmless",
        "SCRIPT ERROR: Parse Error: Identifier \"GUIDE\" not declared in the current scope.",
        "          at: GDScript::reload (res://addons/guide/x.gd:149)",
        "ERROR: Failed to load script \"res://a.gd\"",
    ]
    assert godot_cmd.errors(lines) == [
        'SCRIPT ERROR: Parse Error: Identifier "GUIDE" not declared in the current scope.  '
        "(GDScript::reload (res://addons/guide/x.gd:149))",
        'ERROR: Failed to load script "res://a.gd"',
    ]


def ns(**kw):
    return argparse.Namespace(json=False, verbose=False, **kw)


def test_task_adapter_maps_to_bd(monkeypatch):
    calls = []

    def fake(*args):
        calls.append(args)
        if args[0] == "ready":
            return 0, json.dumps([{"id": "sw-1", "title": "T", "priority": 1, "issue_type": "task", "status": "open"},
                                  {"id": "sw-e", "title": "E", "priority": 1, "issue_type": "epic", "status": "open"}])
        if args[0] == "create":
            return 0, "sw-9"
        return (1, "boom") if args[1] == "bad" else (0, "✓ ok")
    monkeypatch.setattr(task, "bd", fake)
    assert [r["id"] for r in task.run(ns(action="ready")).tables["ready"]] == ["sw-1"]  # epics hidden
    assert task.run(ns(action="claim", id="sw-1")).data["ok"] == "✓ ok"
    assert task.run(ns(action="new", title="X", description="d", priority="3", type="bug", labels="a",
                       parent=None)).data["id"] == "sw-9"
    assert calls[-1] == ("create", "X", "-t", "bug", "-p", "3", "-d", "d", "-l", "a", "--silent")
    assert task.run(ns(action="close", id="bad", reason="")).exit_code == 1
