#!/usr/bin/env python
# Infográfico da oportunidade PMI-CPMAI no Brasil, para o deck PMI-LATAM.
#   ~/.venvs/pmo/bin/python gen_assets_latam.py
# A tese visual: o Brasil é potência em PMP (#10 mundial, 16.167) mas quase
# invisível em PMI-CPMAI (#19, 27 certificados) -> espaço gigante, que o Núcleo
# endereça com a Comunidade PMI-CPMAI Brasil. Fonte: rankings PMP/PMI-CPMAI (mai/2026).
# Transparente, paleta PMI, sem travessao.
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

OUT = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck/assets")
OUT.mkdir(parents=True, exist_ok=True)

TEAL = "#44789B"; ORANGE = "#E0611F"; PURPLE = "#461DA3"
LILAC = "#9B8FC4"; INK = "#242016"; SOFT = "#F2EAD9"

# (x_center, fill, sigla, rank, linha_br)
TILES = [
    (3.05, TEAL,   "PMP",       "#10", "16.167 certificados no Brasil"),
    (9.45, ORANGE, "PMI-CPMAI", "#19", "27 certificados no Brasil"),
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

    bw, bh, cy = 4.6, 2.0, 2.05

    for cx, fill, sigla, rank, br in TILES:
        rbox(ax, cx, cy, bw, bh, fill)
        ax.text(cx - bw / 2 + 0.5, cy + 0.02, rank, ha="left", va="center",
                fontsize=40, fontweight="bold", color="white", zorder=3)
        ax.text(cx + 0.55, cy + 0.42, sigla, ha="left", va="center",
                fontsize=17, fontweight="bold", color="white", zorder=3)
        ax.text(cx + 0.55, cy - 0.02, "no mundo", ha="left", va="center",
                fontsize=11, color=SOFT, zorder=3)
        ax.text(cx, cy - 0.72, br, ha="center", va="center",
                fontsize=11, color="white", zorder=3)

    # the gap, between the tiles
    ax.add_patch(FancyArrowPatch((5.5, cy), (7.0, cy), arrowstyle="-|>",
                 mutation_scale=24, lw=3, color=LILAC, zorder=1))
    ax.text(6.25, cy + 0.45, "o espaço", ha="center", va="center",
            fontsize=11.5, fontweight="bold", color=PURPLE, zorder=3)
    ax.text(6.25, cy + 0.12, "a ocupar", ha="center", va="center",
            fontsize=11.5, fontweight="bold", color=PURPLE, zorder=3)

    ax.text(6.25, 0.42,
            "Potência em PMP, espaço gigante em PMI-CPMAI: a Comunidade PMI-CPMAI Brasil fecha esse gap.",
            ha="center", va="center", fontsize=11.5, color=INK, style="italic", zorder=3)

    fig.savefig(OUT / "cpmai_gap.png", transparent=True)
    plt.close(fig)
    print("saved", OUT / "cpmai_gap.png")


if __name__ == "__main__":
    build()
