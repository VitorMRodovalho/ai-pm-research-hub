#!/usr/bin/env python
# Branded diagrams for the ALUN/Kruel deck. Transparent PNGs, PMI palette.
#   ~/.venvs/pmo/bin/python gen_assets_kruel.py
# strategy_flow.png: Vitor's sketch cleaned up — Estrategia -> Execucao -> Valor,
# with Gestao de Projetos (CPMAI) as the bridge and the point where AI projects stall.
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from pathlib import Path

BASE = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck")
PURPLE = "#461DA3"; ORANGE = "#E0611F"; RED = "#B83713"; TEAL = "#44789B"; DARK = "#242016"


def box(ax, x, y, w, h, text, fc, tc="white", fs=16):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                 boxstyle="round,pad=0.02,rounding_size=0.08",
                 linewidth=0, facecolor=fc))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            color=tc, fontsize=fs, fontweight="bold")


def arrow(ax, x1, y1, x2, y2, color, lw=3):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw,
                                shrinkA=0, shrinkB=0))


def strategy_flow():
    fig, ax = plt.subplots(figsize=(12, 3.3), dpi=200)
    ax.set_xlim(0, 12); ax.set_ylim(0, 3.3); ax.axis("off")

    box(ax, 0.2, 1.55, 3.0, 1.0, "ESTRATÉGIA", PURPLE)
    box(ax, 4.5, 1.55, 3.0, 1.0, "EXECUÇÃO", PURPLE)
    box(ax, 8.8, 1.55, 3.0, 1.0, "VALOR\nENTREGUE", TEAL)

    arrow(ax, 3.25, 2.05, 4.45, 2.05, DARK)
    arrow(ax, 7.55, 2.05, 8.75, 2.05, DARK)

    # bridge: project management / CPMAI feeds execution
    box(ax, 4.2, 0.25, 3.6, 0.8, "Gestão de Projetos · CPMAI", ORANGE, fs=13)
    arrow(ax, 6.0, 1.05, 6.0, 1.5, ORANGE, lw=2.5)

    # the failure point, on the strategy -> execution gap
    ax.text(3.85, 3.02, "projetos de IA travam aqui", ha="center", va="center",
            color=RED, fontsize=12, fontweight="bold")
    arrow(ax, 3.85, 2.78, 3.85, 2.18, RED, lw=2)

    fig.savefig(BASE / "assets/strategy_flow.png", transparent=True,
                bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)
    print("wrote assets/strategy_flow.png")


if __name__ == "__main__":
    strategy_flow()
