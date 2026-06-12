#!/usr/bin/env python
# Generate the hub-and-spoke anchor diagram for the Núcleo pitch deck.
# The IA (center) sews the PMI credential silos (spokes = verticais) together.
# Transparent PNG, PMI palette, sits on the light content slide. No em-dash.
import math
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyArrowPatch, Ellipse

OUT = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck/assets")
OUT.mkdir(parents=True, exist_ok=True)

PURPLE = "#461DA3"
NODES = [
    # label (inside), credential (below circle), fill, textcolor
    ("Construção", "PMI-CP",                 "#E0611F", "white"),
    ("PMO",        "PMI-PMOCP",              "#44789B", "white"),
    ("Ágil",       "PMI-ACP",                "#6CBEDE", "#242016"),
    ("ESG",        "CSPP",                   "#3E8E5A", "white"),
    ("Negócio",    "PfMP · PgMP · PMI-PBA",  "#B83713", "white"),
]

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

pos = []
for a in angles:
    rad = math.radians(a)
    pos.append((cx + rx * math.cos(rad), cy + ry * math.sin(rad)))

# spokes first (behind), drawn from hub edge to node edge
node_r = 0.92
for (nx, ny) in pos:
    dx, dy = nx - cx, ny - cy
    d = math.hypot(dx, dy)
    ux, uy = dx / d, dy / d
    x0, y0 = cx + ux * hub_r, cy + uy * hub_r
    x1, y1 = nx - ux * node_r, ny - uy * node_r
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-",
                 lw=2.4, color="#9B8FC4", zorder=1))

# outer ring = the credential ladder (common spine across all spokes)
ax.add_patch(Ellipse((cx, cy), 2 * (rx + node_r + 0.55), 2 * (ry + node_r + 0.55),
             fill=False, lw=1.4, ls=(0, (5, 4)), edgecolor="#B9AEDD", zorder=0))

# vertical nodes (label inside; credential outside, above the top node, below the rest)
for (nx, ny), (label, cred, fill, tc) in zip(pos, NODES):
    ax.add_patch(Circle((nx, ny), node_r, facecolor=fill, edgecolor="white",
                 lw=2.2, zorder=3))
    ax.text(nx, ny, label, ha="center", va="center", fontsize=15,
            fontweight="bold", color=tc, zorder=4)
    cyy = (ny + node_r + 0.28) if (abs(nx - cx) < 1.0 and ny > cy) \
          else (ny - node_r - 0.26)
    ax.text(nx, cyy, cred, ha="center", va="center",
            fontsize=11, fontweight="bold", color="#242016", zorder=4)

# central hub = Núcleo + IA (the seam)
ax.add_patch(Circle((cx, cy), hub_r, facecolor=PURPLE, edgecolor="white",
             lw=3, zorder=3))
ax.text(cx, cy + 0.32, "Núcleo IA & GP", ha="center", va="center",
        fontsize=17, fontweight="bold", color="white", zorder=4)
ax.text(cx, cy - 0.30, "a IA costura\nos silos", ha="center", va="center",
        fontsize=11.5, color="#D9CEF6", zorder=4)

fig.savefig(OUT / "hub_spoke.png", transparent=True)
print("saved", OUT / "hub_spoke.png")
