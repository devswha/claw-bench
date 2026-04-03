#!/usr/bin/env python3
"""
Generate a professional SVG bar chart comparing Claw Code, Claude Code, and Codex CLI
benchmark results. No external dependencies required.
"""

import math
import os

# ── Data ─────────────────────────────────────────────────────────────────────

BENCHMARKS = [
    # (label, claw_value, competitor_value, competitor_name, unit, ratio_label)
    ("Startup Time",  1.2,   86.4, "Claude Code", "ms",  "73.2x faster"),
    ("Binary Size",   13.0,  218.0, "Claude Code", "MB",  "17x smaller"),
    ("Memory (idle)", 4.1,   191.5, "Claude Code", "MB",  "46.7x less"),
    ("Startup Time",  1.2,   34.5,  "Codex CLI",   "ms",  "29.2x faster"),
    ("Memory (idle)", 4.1,   46.0,  "Codex CLI",   "MB",  "11.2x less"),
]

# ── Colours ───────────────────────────────────────────────────────────────────

COLORS = {
    "Claw Code":   "#E8590C",   # rust-orange
    "Claude Code": "#6366F1",   # indigo/purple
    "Codex CLI":   "#10B981",   # emerald-green
}

BG_COLOR        = "#0F1117"   # near-black
PANEL_COLOR     = "#161B22"   # GitHub dark surface
GRID_COLOR      = "#21262D"   # subtle grid
TEXT_PRIMARY    = "#F0F6FC"   # near-white
TEXT_SECONDARY  = "#8B949E"   # muted
DIVIDER_COLOR   = "#30363D"   # section divider

# ── Layout constants ──────────────────────────────────────────────────────────

SVG_WIDTH   = 820
PADDING_L   = 24   # left edge
PADDING_R   = 24   # right edge
PADDING_T   = 70   # top (title + legend)
PADDING_B   = 36   # bottom

LABEL_W     = 175  # width of left metric label column
BAR_AREA_X  = PADDING_L + LABEL_W + 12   # where bars start
BAR_AREA_W  = SVG_WIDTH - BAR_AREA_X - PADDING_R - 90  # reserve space for ratio label

ROW_H       = 38   # height per bar row
ROW_GAP     = 10   # gap between bar pairs
SECTION_GAP = 22   # extra gap between Claude and Codex sections
BAR_H       = 14   # individual bar height
BAR_RADIUS  = 3    # rounded corners

# ── Helpers ───────────────────────────────────────────────────────────────────

def log_scale(value: float, min_val: float, max_val: float, width: float) -> float:
    """Map value onto [0, width] using a log10 scale."""
    log_min = math.log10(max(min_val, 1e-9))
    log_max = math.log10(max_val)
    log_val = math.log10(max(value, 1e-9))
    return width * (log_val - log_min) / (log_max - log_min)


def fmt_value(v: float, unit: str) -> str:
    if v >= 1000:
        return f"{v/1000:.1f}k {unit}"
    if v == int(v):
        return f"{int(v)} {unit}"
    return f"{v} {unit}"


def escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ── Section grouping ──────────────────────────────────────────────────────────

# Group benchmarks by competitor so we can draw section headers
sections = {}
for row in BENCHMARKS:
    competitor = row[3]
    sections.setdefault(competitor, []).append(row)

ordered_sections = [("Claude Code", sections["Claude Code"]),
                    ("Codex CLI",   sections["Codex CLI"])]

# ── Compute total SVG height ──────────────────────────────────────────────────

total_rows = 0
for _, rows in ordered_sections:
    total_rows += len(rows)   # 2 bars per benchmark row

section_headers = len(ordered_sections)
n_benchmarks    = len(BENCHMARKS)

# Each benchmark = 2 bars + ROW_GAP between them; sections separated by SECTION_GAP
HEIGHT_CONTENT = (
    n_benchmarks * (2 * BAR_H + ROW_GAP + ROW_H - 2 * BAR_H - ROW_GAP)
    # simpler: each benchmark gets ROW_H for both bars, plus inter-benchmark gap
)

# Recalculate properly
INTER_BENCHMARK_PAD = 8
SECTION_HEADER_H    = 28

content_h = 0
for _, rows in ordered_sections:
    content_h += SECTION_HEADER_H
    content_h += len(rows) * (2 * BAR_H + INTER_BENCHMARK_PAD + 14)  # bars + gap + label
    content_h += 16  # section bottom padding

SVG_HEIGHT = PADDING_T + content_h + PADDING_B + 10

# ── SVG builder ───────────────────────────────────────────────────────────────

parts: list[str] = []

def emit(s: str):
    parts.append(s)

# SVG header
emit(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{SVG_WIDTH}" height="{SVG_HEIGHT}" viewBox="0 0 {SVG_WIDTH} {SVG_HEIGHT}">
<defs>
  <style>
    text {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif; }}
  </style>
  <!-- Bar gradients -->
  <linearGradient id="grad-claw" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#E8590C"/>
    <stop offset="100%" stop-color="#F97316"/>
  </linearGradient>
  <linearGradient id="grad-claude" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#6366F1"/>
    <stop offset="100%" stop-color="#818CF8"/>
  </linearGradient>
  <linearGradient id="grad-codex" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#10B981"/>
    <stop offset="100%" stop-color="#34D399"/>
  </linearGradient>
</defs>

<!-- Background -->
<rect width="{SVG_WIDTH}" height="{SVG_HEIGHT}" fill="{BG_COLOR}" rx="12"/>

<!-- Title -->
<text x="{SVG_WIDTH//2}" y="32" text-anchor="middle"
      font-size="17" font-weight="700" fill="{TEXT_PRIMARY}" letter-spacing="0.3">
  Claw Code — Performance Benchmarks
</text>
<text x="{SVG_WIDTH//2}" y="52" text-anchor="middle"
      font-size="12" fill="{TEXT_SECONDARY}">
  Startup time · Binary size · Memory usage  (log scale)
</text>

<!-- Legend -->''')

# Legend items
legend_items = [
    ("Claw Code",   "url(#grad-claw)"),
    ("Claude Code", "url(#grad-claude)"),
    ("Codex CLI",   "url(#grad-codex)"),
]
legend_total_w = 280
legend_x_start = (SVG_WIDTH - legend_total_w) // 2
legend_y = 64

for i, (name, fill) in enumerate(legend_items):
    lx = legend_x_start + i * 95
    emit(f'<rect x="{lx}" y="{legend_y}" width="12" height="12" rx="3" fill="{fill}"/>')
    emit(f'<text x="{lx + 16}" y="{legend_y + 10}" font-size="11" fill="{TEXT_SECONDARY}">{escape(name)}</text>')

emit("")

# ── Draw sections ─────────────────────────────────────────────────────────────

cursor_y = PADDING_T + 14   # current vertical position

for s_idx, (competitor_name, rows) in enumerate(ordered_sections):

    if s_idx > 0:
        # Horizontal divider between sections
        emit(f'<line x1="{PADDING_L}" y1="{cursor_y - 8}" x2="{SVG_WIDTH - PADDING_R}" y2="{cursor_y - 8}" stroke="{DIVIDER_COLOR}" stroke-width="1"/>')

    # Section header
    emit(f'<text x="{PADDING_L}" y="{cursor_y + 14}" font-size="12" font-weight="600" '
         f'fill="{TEXT_SECONDARY}" letter-spacing="0.5">'
         f'CLAW vs {escape(competitor_name.upper())}</text>')
    cursor_y += SECTION_HEADER_H

    # Find global min/max for log scale across this section
    all_vals = []
    for row in rows:
        all_vals.extend([row[1], row[2]])
    log_min = min(all_vals)
    log_max = max(all_vals)

    competitor_fill = f"url(#grad-{'claude' if competitor_name == 'Claude Code' else 'codex'})"

    for b_idx, (metric, claw_val, comp_val, _, unit, ratio) in enumerate(rows):
        bar_y_claw = cursor_y
        bar_y_comp = cursor_y + BAR_H + 4

        # Row background (subtle)
        row_total_h = 2 * BAR_H + 4 + 14 + INTER_BENCHMARK_PAD
        if b_idx % 2 == 0:
            emit(f'<rect x="{PADDING_L}" y="{cursor_y - 4}" '
                 f'width="{SVG_WIDTH - PADDING_L - PADDING_R}" height="{row_total_h}" '
                 f'fill="{PANEL_COLOR}" rx="6" opacity="0.5"/>')

        # Metric label
        emit(f'<text x="{PADDING_L + LABEL_W - 8}" y="{cursor_y + BAR_H - 2}" '
             f'text-anchor="end" font-size="12" fill="{TEXT_PRIMARY}">{escape(metric)}</text>')

        # ── Claw bar ──
        claw_w = log_scale(claw_val, log_min, log_max, BAR_AREA_W)
        claw_w = max(claw_w, 4)
        emit(f'<rect x="{BAR_AREA_X}" y="{bar_y_claw}" width="{claw_w:.1f}" height="{BAR_H}" '
             f'rx="{BAR_RADIUS}" fill="url(#grad-claw)"/>')
        # Claw value label
        emit(f'<text x="{BAR_AREA_X + claw_w + 5}" y="{bar_y_claw + BAR_H - 2}" '
             f'font-size="10" fill="{TEXT_PRIMARY}" font-weight="600">'
             f'{fmt_value(claw_val, unit)}</text>')

        # ── Competitor bar ──
        comp_w = log_scale(comp_val, log_min, log_max, BAR_AREA_W)
        comp_w = max(comp_w, 4)
        emit(f'<rect x="{BAR_AREA_X}" y="{bar_y_comp}" width="{comp_w:.1f}" height="{BAR_H}" '
             f'rx="{BAR_RADIUS}" fill="{competitor_fill}"/>')
        # Competitor value label
        emit(f'<text x="{BAR_AREA_X + comp_w + 5}" y="{bar_y_comp + BAR_H - 2}" '
             f'font-size="10" fill="{TEXT_SECONDARY}">'
             f'{fmt_value(comp_val, unit)}</text>')

        # ── Ratio badge ──
        ratio_x = SVG_WIDTH - PADDING_R - 4
        ratio_mid_y = cursor_y + BAR_H + 2
        # Badge background
        badge_w = 90
        badge_h = 18
        badge_x = ratio_x - badge_w
        badge_y = ratio_mid_y - badge_h // 2
        emit(f'<rect x="{badge_x}" y="{badge_y}" width="{badge_w}" height="{badge_h}" '
             f'rx="9" fill="#E8590C" opacity="0.18"/>')
        emit(f'<text x="{ratio_x - badge_w//2}" y="{badge_y + 12}" text-anchor="middle" '
             f'font-size="10" font-weight="700" fill="#E8590C">{escape(ratio)}</text>')

        cursor_y += row_total_h

    cursor_y += 14  # section bottom padding

# Closing tag
emit("</svg>")

# ── Write output ──────────────────────────────────────────────────────────────

SVG_OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets", "benchmark-chart.svg"
)
os.makedirs(os.path.dirname(SVG_OUTPUT), exist_ok=True)

with open(SVG_OUTPUT, "w", encoding="utf-8") as f:
    f.write("\n".join(parts))

print(f"Generated: {SVG_OUTPUT}")
print(f"Dimensions: {SVG_WIDTH} x {SVG_HEIGHT} px")
