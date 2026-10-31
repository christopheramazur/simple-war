"""Local LLM gateway (DESIGN.md §4, Q19): LiteLLM proxy in front of Bonsai and free-tier APIs.

Claude Pro traffic never goes through it. Every call is logged raw to
data/raw/gateway/<date>.jsonl and checked against config/providers.toml budgets/limits.
"""
