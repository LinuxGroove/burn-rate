#!/usr/bin/env python3
"""Draws the game's icon: a pilot climbing out of the tower at night on a
long curl of jetpack flame, skimming a zapper, with the windows of the
city behind. Writes icon.svg, the snap's copy and icon.png:

    python3 tools/make_icon.py [--out=file.svg]

icon.png is drawn from the SVG by Godot itself (tools/svg_to_png.gd), so it
matches what the game shows. Glows are layered strokes and gradients rather
than SVG filters, so Godot's SVG importer draws it as a browser does. The
seed is fixed, so the output only changes when this script does.
"""

import math
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUTS = [ROOT / "icon.svg", ROOT / "snap/gui/burn-rate.svg"]

FLAME = ["#ff3d1f", "#ff7a1a", "#ffb02e", "#ffe27a", "#fffbe8"]


def smooth(pts: list) -> str:
    """A Catmull-Rom curve through the points, as cubic Béziers."""
    d = "M %.1f %.1f" % pts[0]
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += " C %.1f %.1f %.1f %.1f %.1f %.1f" % (c1 + c2 + p2)
    return d


def ribbon(path: list, w0: float, w1: float) -> str:
    """A tapered band along a path: w0 wide at the start, w1 at the end."""
    left, right = [], []
    n = len(path)
    for i, (x, y) in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        t = i / (n - 1)
        w = (w0 + (w1 - w0) * t ** 0.8) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    pts = left + list(reversed(right))
    return "M " + " L ".join("%.1f %.1f" % p for p in pts) + " Z"


def trail() -> list:
    """The flame's path, from off the bottom left up to the pack."""
    pts = []
    for k in range(60):
        t = k / 59
        x = -30 + 295 * t
        y = 520 - 378 * t - 120 * math.sin(math.pi * t) * (1 - t) + 30 * t * t
        pts.append((x, y))
    return pts


def build() -> str:
    rng = random.Random(41)
    svg = []
    add = svg.append
    add('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">')
    add("  <defs>")
    add('    <linearGradient id="night" x1="0" y1="0" x2="0.3" y2="1">')
    add('      <stop offset="0" stop-color="#140f3a"/>')
    add('      <stop offset="0.55" stop-color="#1c1450"/>')
    add('      <stop offset="1" stop-color="#3a1640"/>')
    add("    </linearGradient>")
    add('    <radialGradient id="glow" cx="0.62" cy="0.36" r="0.55">')
    add('      <stop offset="0" stop-color="#ff8a2a" stop-opacity="0.55"/>')
    add('      <stop offset="0.5" stop-color="#ff5a2a" stop-opacity="0.16"/>')
    add('      <stop offset="1" stop-color="#ff5a2a" stop-opacity="0"/>')
    add("    </radialGradient>")
    add('    <linearGradient id="beam" x1="0" y1="0" x2="1" y2="0">')
    add('      <stop offset="0" stop-color="#5fe3ff"/>')
    add('      <stop offset="0.5" stop-color="#e9fbff"/>')
    add('      <stop offset="1" stop-color="#5fe3ff"/>')
    add("    </linearGradient>")
    add('    <clipPath id="tile"><rect x="0" y="0" width="512" height="512" rx="104"/></clipPath>')
    add("  </defs>")
    add('  <g clip-path="url(#tile)">')
    add('  <rect width="512" height="512" fill="url(#night)"/>')
    # The city: towers of windows, some lit.
    x = -10
    while x < 520:
        w = rng.uniform(52, 92)
        top = rng.uniform(250, 380)
        add('  <rect x="%.0f" y="%.0f" width="%.0f" height="%.0f" fill="#0c0a26" opacity="0.9"/>' % (x, top, w - 6, 512 - top))
        wy = top + 12
        while wy < 500:
            wx = x + 8
            while wx < x + w - 18:
                r = rng.random()
                if r < 0.32:
                    col = rng.choice(["#ffc65a", "#ffd98a", "#7fe0ff", "#ff9a5a"])
                    add('  <rect x="%.0f" y="%.0f" width="7" height="9" fill="%s" opacity="%.2f"/>' % (wx, wy, col, rng.uniform(0.35, 0.8)))
                wx += 13
            wy += 17
        x += w
    add('  <rect width="512" height="512" fill="url(#glow)"/>')
    # The zapper the pilot just skimmed.
    zx0, zy0, zx1, zy1 = 300, 70, 470, 235
    add('  <line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#3fd0ff" stroke-width="40" stroke-linecap="round" opacity="0.22"/>' % (zx0, zy0, zx1, zy1))
    add('  <line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#7fe8ff" stroke-width="20" stroke-linecap="round" opacity="0.6"/>' % (zx0, zy0, zx1, zy1))
    add('  <line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#f2fdff" stroke-width="8" stroke-linecap="round"/>' % (zx0, zy0, zx1, zy1))
    for (cx, cy) in [(zx0, zy0), (zx1, zy1)]:
        add('  <circle cx="%d" cy="%d" r="24" fill="#2a2d3a" stroke="#7fe8ff" stroke-width="6"/>' % (cx, cy))
        add('  <circle cx="%d" cy="%d" r="9" fill="#e9fbff"/>' % (cx, cy))
    # The flame, widest and darkest outside, white hot inside.
    path = trail()
    for col, w0, w1, op in [(FLAME[0], 150, 34, 0.35), (FLAME[1], 112, 28, 0.7), (FLAME[2], 76, 22, 0.9), (FLAME[3], 44, 15, 1.0), (FLAME[4], 18, 8, 1.0)]:
        add('  <path d="%s" fill="%s" opacity="%.2f"/>' % (ribbon(path, w0, w1), col, op))
    # Sparks off the near miss.
    for k in range(9):
        a = math.radians(-160 + k * 22 + rng.uniform(-6, 6))
        r0, r1 = 26, rng.uniform(46, 70)
        sx, sy = 352, 168
        add('  <line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="#fff3b0" stroke-width="5" stroke-linecap="round" opacity="0.9"/>' % (sx + math.cos(a) * r0, sy + math.sin(a) * r0, sx + math.cos(a) * r1, sy + math.sin(a) * r1))
    # The pilot: leaning into the climb, pack on the back, legs trailing.
    add('  <g transform="translate(330 176) rotate(-38)">')
    add('    <path d="M -64 18 C -96 30 -118 46 -134 70 L -122 80 C -102 58 -82 46 -56 40 Z" fill="#0b0a18"/>')
    add('    <path d="M -60 6 C -92 8 -120 14 -142 30 L -134 42 C -112 30 -86 26 -58 26 Z" fill="#0b0a18"/>')
    add('    <rect x="-66" y="-30" width="78" height="52" rx="22" fill="#0b0a18"/>')
    add('    <rect x="-52" y="-62" width="44" height="40" rx="10" fill="#ff7a1a"/>')
    add('    <rect x="-46" y="-56" width="12" height="28" rx="4" fill="#ffd27a" opacity="0.8"/>')
    add('    <circle cx="34" cy="-8" r="25" fill="#0b0a18"/>')
    add('    <path d="M 40 -20 L 60 -14 L 58 -4 L 38 -8 Z" fill="#7fe8ff"/>')
    add('    <path d="M 6 4 C 26 14 46 30 58 52 L 46 60 C 34 42 18 30 0 22 Z" fill="#0b0a18"/>')
    add('    <path d="M -64 -30 C -40 -40 -8 -40 12 -30" stroke="#ff9a3a" stroke-width="4" fill="none" opacity="0.8"/>')
    add("  </g>")
    add("  </g>")
    add('  <rect x="3" y="3" width="506" height="506" rx="102" fill="none" stroke="#ff8a2a" stroke-opacity="0.35" stroke-width="6"/>')
    add("</svg>")
    return "\n".join(svg) + "\n"


def main() -> None:
    svg = build()
    outs = [Path(a[6:]).resolve() for a in sys.argv if a.startswith("--out=")] or OUTPUTS
    for path in outs:
        path.write_text(svg)
        print("wrote", path)
    if not any(a.startswith("--out=") for a in sys.argv):
        subprocess.run(["godot", "--headless", "--path", str(ROOT), "-s", "tools/svg_to_png.gd", "--", "icon.svg", "icon.png", "512"], check=False)


if __name__ == "__main__":
    main()
