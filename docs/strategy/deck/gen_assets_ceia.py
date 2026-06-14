#!/usr/bin/env python
# Generate the CEIA-UFG cooperation thesis infographic (the "encaixe" bridge).
#   ~/.venvs/pmo/bin/python gen_assets_ceia.py
# A 3-stage horizontal flow that IS the wedge: CEIA constrói/transfere IA ->
# Núcleo/PMI traz gestão (CPMAI) + padrão (ANSI) -> a IA vira valor (M.O.R.E.).
# The middle stage is the elo that 95% dos pilotos perdem. Transparent PNG, PMI palette, no em-dash.
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

OUT = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck/assets")
OUT.mkdir(parents=True, exist_ok=True)

TEAL = "#44789B"; PURPLE = "#461DA3"; ORANGE = "#E0611F"
LILAC = "#9B8FC4"; INK = "#242016"; SOFT = "#D9CEF6"

# (x_center, fill, header, line1, line2)
STAGES = [
    (2.15, TEAL,   "CEIA",         "constrói e transfere IA",   "unidade EMBRAPII · pesquisa"),
    (6.25, PURPLE, "Núcleo / PMI", "gestão (CPMAI) + padrão",   "o standard de IA (ANSI)"),
    (10.35, ORANGE, "IA vira valor", "projeto entregue",        "M.O.R.E."),
]


def rbox(ax, cx, cy, w, h, fill):
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.02,rounding_size=0.18",
                 linewidth=0, facecolor=fill, zorder=2))


def build():
    fig = plt.figure(figsize=(12.5, 3.4), dpi=200)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 12.5)
    ax.set_ylim(0, 3.4)
    ax.axis("off")

    bw, bh, cy = 3.5, 1.78, 2.05

    # connector arrows behind the boxes
    for x0, x1 in ((3.95, 4.55), (8.05, 8.65)):
        ax.add_patch(FancyArrowPatch((x0, cy), (x1, cy), arrowstyle="-|>",
                     mutation_scale=22, lw=3, color=LILAC, zorder=1))

    for cx, fill, head, l1, l2 in STAGES:
        rbox(ax, cx, cy, bw, bh, fill)
        ax.text(cx, cy + 0.46, head, ha="center", va="center",
                fontsize=18, fontweight="bold", color="white", zorder=3)
        ax.text(cx, cy - 0.10, l1, ha="center", va="center",
                fontsize=12.5, color="white", zorder=3)
        ax.text(cx, cy - 0.52, l2, ha="center", va="center",
                fontsize=10.5, color=SOFT, zorder=3)

    ax.text(6.25, 0.42,
            "O elo que decide se a IA vira valor é a gestão do projeto: 95% dos pilotos travam aí.",
            ha="center", va="center", fontsize=11.5, color=INK, style="italic", zorder=3)

    fig.savefig(OUT / "ceia_bridge.png", transparent=True)
    plt.close(fig)
    print("saved", OUT / "ceia_bridge.png")


if __name__ == "__main__":
    build()
