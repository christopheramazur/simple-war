"""hx human: the owner's queue and where an answer is routed."""

from __future__ import annotations

from types import SimpleNamespace

from hx import human
from hx.commands import human as cmd

ROWS = [
    {"id": "sw-a", "title": "plain work", "priority": 1, "status": "open", "labels": ["u1"]},
    {"id": "sw-b", "title": "blocked run", "priority": 2, "status": "in_progress", "labels": ["autopilot-blocked"]},
    {"id": "sw-c", "title": "sign-off", "priority": 2, "status": "open", "labels": ["needs-human", "u1"]},
    {"id": "sw-d", "title": "incident", "priority": 0, "status": "open", "labels": ["human"]},
]


class FakeBd:
    def __init__(self):
        self.calls: list[tuple] = []

    def __call__(self, *args):
        self.calls.append(args)
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    def notes(self, bead):
        return [a[2] for a in self.calls if a[:2] == ("update", bead) and a[2].startswith("--append-notes=")]


def test_queue_keeps_waiting_beads_by_priority_decisions_first():
    q = human.queue(lambda *a: ROWS)
    assert [i.id for i in q] == ["sw-d", "sw-c", "sw-b"]
    assert [i.kind for i in q] == ["decision", "decision", "blocked"]


def test_default_action_closes_decisions_others_wait_on():
    d = human.Item("sw-c", "t", 2, "open", "decision", ["needs-human"])
    assert human.default_action(d) == "release"
    d.blocks = [{"id": "sw-x", "title": "x"}]
    assert human.default_action(d) == "close"
    b = human.Item("sw-b", "t", 2, "open", "blocked", ["autopilot-blocked"], blocks=[{"id": "sw-x", "title": "x"}])
    assert human.default_action(b) == "release"


def test_mentioned_finds_other_beads_once():
    assert human.mentioned("see sw-txnj.20 and sw-l87e, also sw-txnj.20; not sw-c", "sw-c") == ["sw-txnj.20", "sw-l87e"]


def test_release_drops_waiting_labels_unclaims_and_resets_autopilot():
    bd, reset = FakeBd(), []
    i = human.Item("sw-b", "t", 2, "in_progress", "blocked", ["autopilot-blocked", "u1"])
    done = human.apply(i, "vendor it as plain files", "release", bd=bd, reset=lambda b, a: reset.append(b) or True)
    assert bd.notes("sw-b")[0].startswith("--append-notes=OWNER ") and "vendor it" in bd.notes("sw-b")[0]
    assert ("update", "sw-b", "--remove-label=autopilot-blocked") in bd.calls
    assert ("update", "sw-b", "--remove-label=u1") not in bd.calls
    assert ("unclaim", "sw-b") in bd.calls
    assert reset == ["sw-b"] and "autopilot attempts reset" in done[-1]


def test_close_notes_dependents_and_mentions_then_closes():
    bd = FakeBd()
    i = human.Item("sw-c", "t", 2, "open", "decision", ["needs-human"],
                   blocks=[{"id": "sw-x", "title": "x"}, {"id": "sw-y", "title": "y"}])
    human.apply(i, "flip it on; sw-y and sw-z should know", "close", bd=bd, reset=lambda b, a: False)
    assert bd.notes("sw-x") and "decided sw-c" in bd.notes("sw-x")[0]
    assert len(bd.notes("sw-y")) == 1 and "answering sw-c" in bd.notes("sw-y")[0]   # mentioned: once, not twice
    assert bd.notes("sw-z")
    assert bd.calls[-1][:2] == ("close", "sw-c") and "owner decided: flip it on" in bd.calls[-1][2]
    assert not any(a[0] == "unclaim" for a in bd.calls)


def test_note_only_changes_nothing_else():
    bd = FakeBd()
    i = human.Item("sw-c", "t", 2, "open", "decision", ["needs-human"])
    human.apply(i, "thinking about it", "note", bd=bd, reset=lambda b, a: 1 / 0)
    assert [a[0] for a in bd.calls] == ["update"]


def test_empty_answer_or_bad_action_is_refused():
    i = human.Item("sw-c", "t", 2, "open", "decision", ["needs-human"])
    for ans, act in (("  ", "note"), ("x", "merge")):
        try:
            human.apply(i, ans, act, bd=FakeBd())
        except ValueError:
            continue
        raise AssertionError((ans, act))


def test_log_answer_appends_quoted_entries(tmp_path, monkeypatch):
    monkeypatch.setattr(human.paths, "main_root", lambda: tmp_path)
    i = human.Item("sw-c", "Flip separation on", 2, "open", "decision", ["needs-human"])
    human.log_answer(i, "yes\nbut measure first", "close", commit=False)
    human.log_answer(i, "again", "note", commit=False)
    s = (tmp_path / human.LOG).read_text(encoding="utf-8")
    assert s.startswith("# Owner answers") and s.count("· sw-c ·") == 2
    assert "> yes\n> but measure first" in s and "**Flip separation on**" in s


def test_answer_subcommand_refuses_a_bead_not_waiting(monkeypatch):
    monkeypatch.setattr(human, "queue", lambda: [])
    r = cmd.run(SimpleNamespace(action="answer", bead="sw-a", text="x", then=None, no_commit=True, list=False))
    assert r.exit_code == 1


def test_interactive_walk_answers_skips_and_quits(monkeypatch):
    items = [human.Item("sw-c", "t", 2, "open", "decision", ["needs-human"]),
             human.Item("sw-b", "t", 2, "open", "blocked", ["autopilot-blocked"]),
             human.Item("sw-e", "t", 3, "open", "blocked", ["autopilot-blocked"])]
    routed = []
    monkeypatch.setattr(human, "queue", lambda: items)
    monkeypatch.setattr(human, "load", lambda i: i)
    monkeypatch.setattr(cmd, "_route", lambda i, a, act, commit: routed.append((i.id, a, act)) or ["ok"])
    monkeypatch.setattr(cmd.sys.stdin, "isatty", lambda: True, raising=False)
    # leading blank lines (stray Enters) are ignored, not a skip; :s skips; :q quits
    answers = iter(["", "", "go ahead", "and test it", "", "n", "", ":s", ":q"])
    monkeypatch.setattr("builtins.input", lambda *_: next(answers))
    r = cmd.run(SimpleNamespace(action=None, list=False, no_commit=True))
    assert routed == [("sw-c", "go ahead\nand test it", "note")]
    assert "1 answered, 1 skipped, 1 left" in r.checks[-1].detail
