"""Benchmark ladder (DESIGN.md §8): frozen tasks, automatic checkers, model adapters, runner."""

from pathlib import Path

from hx.paths import HARNESS_ROOT

BENCH_ROOT = HARNESS_ROOT / "bench"
TASKS_DIR = BENCH_ROOT / "tasks"
SUITE_VERSION = "1"
