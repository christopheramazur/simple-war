from datetime import datetime, timezone

from hx.gateway import budget
from hx.providers import Provider

T0 = datetime(2026, 10, 31, 23, 0, tzinfo=timezone.utc).timestamp()


def roster(**over):
    base = {
        "or": Provider(id="or", name="OR", kind="api", limits={"rpd": 3, "rpm": 2}, reset_tz="UTC"),
        "gem": Provider(id="gem", name="G", kind="api", limits={"tpd": 1000}, reset_tz="America/Los_Angeles"),
        "paid": Provider(id="paid", name="P", kind="api", monthly_budget_usd=1.0, hard_stop=True),
        "soft": Provider(id="soft", name="S", kind="api", monthly_budget_usd=0.0, hard_stop=False),
        "pro": Provider(id="pro", name="Pro", kind="subscription"),
    }
    base.update(over)
    return base


def test_rpm_then_rpd():
    t = budget.Tracker(roster())
    t.record("or", T0)
    t.record("or", T0 + 1)
    d = t.check("or", T0 + 2)
    assert not d.allowed and "rpm 2" in d.reason
    assert t.check("or", T0 + 61).allowed  # minute window rolled
    t.record("or", T0 + 61)
    d = t.check("or", T0 + 130)
    assert not d.allowed and "rpd 3" in d.reason


def test_day_resets_in_provider_timezone():
    t = budget.Tracker(roster())
    t.record("or", T0, tokens=0)
    t.record("or", T0 + 1)
    t.record("or", T0 + 2)
    assert not t.check("or", T0 + 1800).allowed  # 23:30 UTC: same day, rpd 3 used
    assert t.check("or", T0 + 3600).allowed  # 00:00 UTC Nov 1: new day
    t.record("gem", T0, tokens=1000)  # 16:00 in Los Angeles, Oct 31
    assert not t.check("gem", T0 + 3 * 3600).allowed  # 19:00 LA, same day
    assert t.check("gem", T0 + 9 * 3600).allowed  # 01:00 LA, Nov 1


def test_budget_hard_stop_and_soft():
    t = budget.Tracker(roster())
    t.record("paid", T0, usd=0.6)
    assert t.check("paid", T0 + 1).allowed
    t.record("paid", T0 + 2, usd=0.6)
    d = t.check("paid", T0 + 3)
    assert not d.allowed and "approval" in d.reason
    t.record("soft", T0, usd=5)
    assert t.check("soft", T0 + 1).allowed  # hard_stop = false: tracked, not enforced


def test_refuses_subscription_and_unknown():
    t = budget.Tracker(roster())
    assert "subscription" in t.check("pro", T0).reason
    assert "not in config" in t.check("nope", T0).reason


def test_log_roundtrip_and_seed(tmp_path, monkeypatch):
    monkeypatch.setenv("HX_DATA_DIR", str(tmp_path))
    now = datetime.now(timezone.utc)
    for i in range(3):
        budget.append_log({"ts": now.isoformat(), "provider": "or", "status": "success",
                           "prompt_tokens": 5, "completion_tokens": 5, "cost_usd": 0.0})
    budget.append_log({"ts": now.isoformat(), "provider": "or", "status": "failure"})
    rows = budget.read_log()
    assert len(rows) == 4
    t = budget.Tracker(roster(**{"or": Provider(id="or", name="OR", kind="api", limits={"rpd": 3}, reset_tz="UTC")}))
    assert t.seed(rows) == 3  # failures don't count against quota
    assert not t.check("or", now.timestamp()).allowed
