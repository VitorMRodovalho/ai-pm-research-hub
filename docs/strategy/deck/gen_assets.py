#!/usr/bin/env python
# Generate the hub-and-spoke anchor diagram for the Núcleo pitch deck (PT + EN).
# The IA/AI (center) sews the PMI credential silos (spokes = verticais) together.
# The Núcleo name is kept verbatim ("Núcleo IA & GP") in BOTH languages (dual-language brand);
# only the tagline and node labels localize. Transparent PNG, PMI palette. No em-dash.
import math, sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyArrowPatch, Ellipse

OUT = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck/assets")
OUT.mkdir(parents=True, exist_ok=True)

PURPLE = "#461DA3"
CREDS = ["PMI-CP", "PMI-PMOCP", "PMI-ACP", "CSPP", "PfMP · PgMP · PMI-PBA"]
FILLS = ["#E0611F", "#44789B", "#6CBEDE", "#3E8E5A", "#B83713"]
TCS   = ["white", "white", "#242016", "white", "white"]

LANGS = {
    "pt": {
        "labels": ["Construção", "PMO", "Ágil", "ESG", "Negócio"],
        "tagline": "a IA costura\nos silos",
        "file": "hub_spoke.png",
    },
    "en": {
        "labels": ["Construction", "PMO", "Agile", "ESG", "Business"],
        "tagline": "AI sews\nthe silos",
        "file": "hub_spoke_en.png",
    },
}


def build(lang):
    cfg = LANGS[lang]
    nodes = list(zip(cfg["labels"], CREDS, FILLS, TCS))

    fig = plt.figure(figsize=(12.5, 5.7), dpi=200)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(-0.3, 12.3)
    ax.set_ylim(-0.95, 6.2)
    ax.set_aspect("equal")
    ax.axis("off")

    cx, cy = 6.0, 2.55
    hub_r = 1.28
    rx, ry = 4.3, 2.0
    angles = [90, 162, 234, 306, 18]
    pos = [(cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a)))
           for a in angles]

    node_r = 0.92
    for (nx, ny) in pos:
        dx, dy = nx - cx, ny - cy
        d = math.hypot(dx, dy)
        ux, uy = dx / d, dy / d
        ax.add_patch(FancyArrowPatch((cx + ux * hub_r, cy + uy * hub_r),
                     (nx - ux * node_r, ny - uy * node_r), arrowstyle="-",
                     lw=2.4, color="#9B8FC4", zorder=1))

    ax.add_patch(Ellipse((cx, cy), 2 * (rx + node_r + 0.55), 2 * (ry + node_r + 0.55),
                 fill=False, lw=1.4, ls=(0, (5, 4)), edgecolor="#B9AEDD", zorder=0))

    for (nx, ny), (label, cred, fill, tc) in zip(pos, nodes):
        ax.add_patch(Circle((nx, ny), node_r, facecolor=fill, edgecolor="white",
                     lw=2.2, zorder=3))
        ax.text(nx, ny, label, ha="center", va="center", fontsize=15,
                fontweight="bold", color=tc, zorder=4)
        cyy = (ny + node_r + 0.28) if (abs(nx - cx) < 1.0 and ny > cy) \
              else (ny - node_r - 0.26)
        ax.text(nx, cyy, cred, ha="center", va="center",
                fontsize=11, fontweight="bold", color="#242016", zorder=4)

    ax.add_patch(Circle((cx, cy), hub_r, facecolor=PURPLE, edgecolor="white",
                 lw=3, zorder=3))
    ax.text(cx, cy + 0.32, "Núcleo IA & GP", ha="center", va="center",
            fontsize=17, fontweight="bold", color="white", zorder=4)
    ax.text(cx, cy - 0.30, cfg["tagline"], ha="center", va="center",
            fontsize=11.5, color="#D9CEF6", zorder=4)

    fig.savefig(OUT / cfg["file"], transparent=True)
    plt.close(fig)
    print("saved", OUT / cfg["file"])


if __name__ == "__main__":
    which = sys.argv[1:] or ["pt", "en"]
    for lang in which:
        build(lang)
