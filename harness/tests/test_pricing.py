import pytest

from hx import pricing


@pytest.fixture(scope="module")
def prices():
    return pricing.load()


def test_longest_prefix_wins(prices):
    assert pricing.match(prices, "claude-opus-5-5").rates["input"] == 4.0
    assert pricing.match(prices, "claude-opus-5-20260101").rates["input"] == 5.0
    assert pricing.match(prices, "Ternary-Bonsai-2-27B-PQ2_0.gguf").provider == "local"
    assert pricing.match(prices, "gpt-something") is None
    assert pricing.match(prices, None) is None


def test_estimate_all_categories(prices):
    p = pricing.match(prices, "claude-opus-5-5")
    toks = {"input": 1_000_000, "cache_write_5m": 1_000_000, "cache_write_1h": 1_000_000,
            "cache_read": 1_000_000, "output": 1_000_000}
    assert pricing.estimate(p, toks) == pytest.approx(4 + 5 + 8 + 0.2 + 20)


def test_haiku_long_context_tier(prices):
    p = pricing.match(prices, "claude-haiku-5-5")
    short = pricing.estimate(p, {"input": 100_000, "output": 1_000_000})
    long = pricing.estimate(p, {"input": 60_000, "cache_read": 50_000, "output": 1_000_000})
    assert short == pytest.approx(0.01 + 0.5)
    assert long == pytest.approx((60_000 * 0.5 + 50_000 * 0.05) / 1e6 + 2.5)


def test_unpriced_is_none():
    assert pricing.estimate(None, {"input": 5}) is None
