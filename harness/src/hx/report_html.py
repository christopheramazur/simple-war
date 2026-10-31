"""Static HTML dashboard for `hx report --html` (DESIGN.md §2, Q21). No server, no external assets.

Colours: reference data-viz palette, slots validated light + dark for up to 4 series.
Series colour follows the model (sorted name order), never its rank.
"""

from __future__ import annotations

import html
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from hx.output import _fmt
from hx.paths import data_dir

SLOTS = 8  # categorical slots defined in CSS; more models fold into "other"

CSS = """
:root { color-scheme: light;
  --page:#f9f9f7; --surface:#fcfcfb; --ink:#0b0b0b; --ink-2:#52514e; --muted:#898781;
  --grid:#e1e0d9; --axis:#c3c2b7; --ring:rgba(11,11,11,.10);
  --s1:#2a78d6; --s2:#eb6834; --s3:#1baf7a; --s4:#eda100; --s5:#e87ba4; --s6:#008300; --s7:#6250d6; --s8:#e34948;
  --critical:#d03b3b; --good:#006300; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { color-scheme: dark;
  --page:#0d0d0d; --surface:#1a1a19; --ink:#f0efec; --ink-2:#c3c2b7; --muted:#898781;
  --grid:#2c2c2a; --axis:#383835; --ring:rgba(255,255,255,.10);
  --s1:#3987e5; --s2:#d95926; --s3:#199e70; --s4:#c98500; --s5:#d55181; --s6:#008300; --s7:#9085e9; --s8:#e66767;
  --critical:#d03b3b; --good:#0ca30c; } }
:root[data-theme="dark"] { color-scheme: dark;
  --page:#0d0d0d; --surface:#1a1a19; --ink:#f0efec; --ink-2:#c3c2b7; --muted:#898781;
  --grid:#2c2c2a; --axis:#383835; --ring:rgba(255,255,255,.10);
  --s1:#3987e5; --s2:#d95926; --s3:#199e70; --s4:#c98500; --s5:#d55181; --s6:#008300; --s7:#9085e9; --s8:#e66767;
  --critical:#d03b3b; --good:#0ca30c; }
* { box-sizing: border-box; }
body { margin:0; background:var(--page); color:var(--ink); font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif; }
main { max-width:1100px; margin:0 auto; padding:24px 16px 48px; }
header { display:flex; justify-content:space-between; align-items:baseline; flex-wrap:wrap; gap:8px; }
h1 { font-size:20px; margin:0; } h2 { font-size:15px; margin:0 0 12px; }
.sub { color:var(--ink-2); font-size:13px; }
.tiles { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; margin:20px 0; }
.tile, .card { background:var(--surface); border:1px solid var(--ring); border-radius:10px; padding:14px 16px; }
.tile .k { color:var(--ink-2); font-size:12px; } .tile .v { font-size:24px; font-weight:600; margin-top:2px; }
.tile .n { color:var(--muted); font-size:12px; }
.grid2 { display:grid; grid-template-columns:repeat(auto-fit,minmax(min(100%,480px),1fr)); gap:16px; margin-bottom:16px; }
.legend { display:flex; flex-wrap:wrap; gap:14px; font-size:12px; color:var(--ink-2); margin-bottom:8px; }
.legend i { display:inline-block; width:10px; height:10px; border-radius:2px; margin-right:6px; vertical-align:-1px; }
svg { display:block; width:100%; height:auto; overflow:visible; }
svg text { fill:var(--muted); font-size:11px; font-variant-numeric:tabular-nums; }
svg .lbl { fill:var(--ink-2); }
.gl { stroke:var(--grid); stroke-width:1; } .base { stroke:var(--axis); stroke-width:1; }
.hit { fill:transparent; cursor:default; }
table { width:100%; border-collapse:collapse; font-size:13px; }
th { text-align:left; color:var(--ink-2); font-weight:500; border-bottom:1px solid var(--axis); padding:6px 8px; }
td { border-bottom:1px solid var(--grid); padding:6px 8px; } td.num, th.num { text-align:right; font-variant-numeric:tabular-nums; }
.scroll { overflow-x:auto; }
details { margin-top:10px; } summary { cursor:pointer; color:var(--ink-2); font-size:12px; }
#tip { position:fixed; pointer-events:none; background:var(--surface); color:var(--ink); border:1px solid var(--ring);
  border-radius:8px; padding:6px 10px; font-size:12px; box-shadow:0 4px 14px rgba(0,0,0,.15); display:none; white-space:pre; }
.pending { color:var(--muted); font-size:12px; margin-top:24px; }
"""

JS = """
const tip=document.getElementById('tip');
document.addEventListener('mousemove',e=>{const t=e.target.closest('[data-tip]');
 if(!t){tip.style.display='none';return;} tip.textContent=t.dataset.tip; tip.style.display='block';
 const x=Math.min(e.clientX+14, innerWidth-tip.offsetWidth-8); tip.style.left=x+'px'; tip.style.top=(e.clientY+14)+'px';});
"""


def write(d: dict, since: str, now: datetime, out: Path | None = None) -> Path:
    out = out or data_dir() / "reports" / "report.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(d, since, now), encoding="utf-8")
    return out


def render(d: dict, since: str, now: datetime) -> str:
    e = html.escape
    models = sorted({r["model"] for r in d["by_model"] if r["model"]})
    color = {m: f"var(--s{i + 1})" for i, m in enumerate(models[:SLOTS])}
    t, tm, f = d["totals"], d["time"], d["friction"]
    tiles = [
        ("Est. API-price spend", f"${t['est_usd']:,.2f}", f"{t['calls']:,} calls, {t['sessions']} sessions"),
        ("Cache hit rate", _pct(t["cache_hit"]), "cache read ÷ all prompt tokens"),
        ("Cost per closed task", f"${t['usd_per_closed_task']:,.2f}" if t["usd_per_closed_task"] else "–",
         f"{t['tasks_closed']} task(s) closed"),
        ("Agent working", f"{tm['agent_work_h']} h", f"{tm['turns']} turns"),
        ("Waiting on you", f"{tm['human_wait_h']} h", f"+ {tm['away_h']} h away (gaps over 30 min)"),
        ("Friction", str(sum(f.values())), ", ".join(f"{k.replace('_', ' ')} {v}" for k, v in f.items() if v) or "none"),
    ]
    body = [
        f"<header><h1>Agent harness report</h1><span class='sub'>window: {e(since)} · generated "
        f"{e(now.strftime('%Y-%m-%d %H:%M %Z'))}</span></header>",
        "<section class='tiles'>" + "".join(
            f"<div class='tile'><div class='k'>{e(k)}</div><div class='v'>{e(v)}</div><div class='n'>{e(n)}</div></div>"
            for k, v, n in tiles) + "</section>",
        "<div class='grid2'>",
        _card("Daily spend by model (est. USD)", _legend(models, color) + _day_bars(d["by_day"], models, color),
              _table(d["by_day"])),
        _card("Tool output (est. tokens)", _hbars(d["tools"][:10], "tool", "output_tokens_est"),
              _table(d["tools"])),
        "</div><div class='grid2'>",
        _card("By model", _table(d["by_model"])),
        _card("By task", _table(d["by_task"])),
        "</div>",
        _card("Subscription quota (latest window)", _table(d["quota"])),
        "<div style='height:16px'></div>",
        _card("Top commands (mining candidates)", _table(d["commands"][:25])),
        "<div style='height:16px'></div>",
        _card("Sessions", _table(d["by_session"][:50])),
        f"<p class='pending'>Not yet measured: {e(', '.join(d['pending']))}.</p>",
    ]
    return ("<!doctype html><html lang='en'><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>Harness Report</title><style>{CSS}</style></head><body><main>"
            + "".join(body) + f"</main><div id='tip'></div><script>{JS}</script></body></html>")


def _pct(x) -> str:
    return f"{x * 100:.1f}%" if x is not None else "–"


def _card(title: str, content: str, table_view: str | None = None) -> str:
    extra = f"<details><summary>Table view</summary><div class='scroll'>{table_view}</div></details>" if table_view else ""
    return f"<section class='card'><h2>{html.escape(title)}</h2>{content}{extra}</section>"


def _legend(models, color) -> str:
    if len(models) < 2:
        return ""
    return "<div class='legend'>" + "".join(
        f"<span><i style='background:{color.get(m, 'var(--muted)')}'></i>{html.escape(m)}</span>" for m in models) + "</div>"


def _table(rows: list[dict]) -> str:
    if not rows:
        return "<p class='sub'>No data.</p>"
    cols = list(rows[0])
    num = {c for c in cols if all(isinstance(r.get(c), (int, float)) and not isinstance(r.get(c), bool)
                                  or r.get(c) is None for r in rows)}
    head = "".join(f"<th class='{'num' if c in num else ''}'>{html.escape(c.replace('_', ' '))}</th>" for c in cols)
    body = "".join("<tr>" + "".join(f"<td class='{'num' if c in num else ''}'>{html.escape(_fmt(r.get(c)))}</td>"
                                    for c in cols) + "</tr>" for r in rows)
    return f"<div class='scroll'><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>"


def _nice_max(v: float) -> float:
    if v <= 0:
        return 1
    import math
    mag = 10 ** math.floor(math.log10(v))
    return next(m * mag for m in (1, 2, 2.5, 5, 10) if m * mag >= v)


def _day_bars(rows: list[dict], models: list[str], color: dict) -> str:
    """Stacked columns per day; 2px surface gaps between segments; 4px rounded top."""
    days: dict = defaultdict(dict)
    for r in rows:
        days[str(r["day"])][r["model"]] = r["est_usd"] or 0
    if not days:
        return "<p class='sub'>No calls in window.</p>"
    names = sorted(days)
    W, H, L, B, T = 520, 220, 44, 24, 8
    ymax = _nice_max(max(sum(v.values()) for v in days.values()))
    plot_w = W - L - 8
    step = plot_w / len(names)
    bw = min(48, step * 0.6)
    y = lambda v: T + (H - T - B) * (1 - v / ymax)  # noqa: E731
    parts = []
    for i in range(5):
        v = ymax * i / 4
        parts.append(f"<line class='gl' x1='{L}' x2='{W - 8}' y1='{y(v):.1f}' y2='{y(v):.1f}'/>"
                     f"<text x='{L - 6}' y='{y(v) + 4:.1f}' text-anchor='end'>${v:,.2f}</text>")
    for i, day in enumerate(names):
        x = L + step * i + (step - bw) / 2
        base = H - B
        segs = [(m, days[day].get(m, 0)) for m in models if days[day].get(m, 0) > 0]
        for j, (m, v) in enumerate(segs):
            h = (H - T - B) * v / ymax
            top = j == len(segs) - 1
            gap = 0 if j == 0 else 2
            parts.append(_rect(x, base - h, bw, max(h - gap, 0.5), color.get(m, "var(--muted)"), top,
                               f"{day}\n{m}: ${v:,.4f}"))
            base -= h
        total = sum(days[day].values())
        parts.append(f"<rect class='hit' x='{L + step * i:.1f}' y='{T}' width='{step:.1f}' height='{H - T - B}' "
                     f"data-tip='{html.escape(day)}\ntotal: ${total:,.4f}'/>" if not segs else "")
        if len(names) <= 14 or i % max(1, len(names) // 10) == 0:
            parts.append(f"<text x='{x + bw / 2:.1f}' y='{H - 6}' text-anchor='middle'>{day[5:]}</text>")
    parts.append(f"<line class='base' x1='{L}' x2='{W - 8}' y1='{H - B}' y2='{H - B}'/>")
    return f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Daily spend by model'>{''.join(parts)}</svg>"


def _rect(x, y, w, h, fill, rounded_top, tip) -> str:
    tip = html.escape(tip, quote=True)
    if rounded_top and h > 4:
        r = 4
        d = (f"M{x:.1f},{y + h:.1f} V{y + r:.1f} Q{x:.1f},{y:.1f} {x + r:.1f},{y:.1f} H{x + w - r:.1f} "
             f"Q{x + w:.1f},{y:.1f} {x + w:.1f},{y + r:.1f} V{y + h:.1f} Z")
        return f"<path d='{d}' fill='{fill}' data-tip='{tip}'/>"
    return f"<rect x='{x:.1f}' y='{y:.1f}' width='{w:.1f}' height='{h:.1f}' fill='{fill}' data-tip='{tip}'/>"


def _hbars(rows: list[dict], label: str, value: str) -> str:
    """Single-series horizontal bars, rounded data end, value label at the end."""
    rows = [r for r in rows if r.get(value)]
    if not rows:
        return "<p class='sub'>No tool output in window.</p>"
    W, row_h, L = 520, 24, 150
    vmax = max(r[value] for r in rows)
    bar_w = W - L - 70
    parts = []
    for i, r in enumerate(rows):
        y0 = i * row_h + 4
        w = max(bar_w * r[value] / vmax, 2)
        name = str(r[label])
        short = name if len(name) <= 22 else name[:21] + "…"
        tip = html.escape(f"{name}\n{r[value]:,} est. tokens over {r.get('uses', '?')} uses", quote=True)
        rr = min(4, w / 2)
        d = (f"M{L},{y0} H{L + w - rr:.1f} Q{L + w:.1f},{y0} {L + w:.1f},{y0 + rr} V{y0 + 16 - rr} "
             f"Q{L + w:.1f},{y0 + 16} {L + w - rr:.1f},{y0 + 16} H{L} Z")
        parts.append(f"<text class='lbl' x='{L - 8}' y='{y0 + 12}' text-anchor='end'>{html.escape(short)}</text>"
                     f"<path d='{d}' fill='var(--s1)' data-tip='{tip}'/>"
                     f"<rect class='hit' x='0' y='{y0 - 4}' width='{W}' height='{row_h}' data-tip='{tip}'/>"
                     f"<text x='{L + w + 6:.1f}' y='{y0 + 12}'>{r[value]:,}</text>")
    H = len(rows) * row_h + 8
    parts.append(f"<line class='base' x1='{L}' x2='{L}' y1='0' y2='{H - 4}'/>")
    return f"<svg viewBox='0 0 {W} {H}' role='img' aria-label='Tool output by tool'>{''.join(parts)}</svg>"
