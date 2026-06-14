#!/usr/bin/env python
# Branded diagrams for the ALUN/Kruel deck (LIGHT theme). Transparent PNGs, PMI palette,
# dark text/strokes so they read on the light (cream F7F4EF) slides.
#   ~/.venvs/pmo/bin/python gen_assets_kruel.py
# strategy_flow.png : Estrategia -> Execucao -> Valor, ponte CPMAI, ponto onde a IA trava (slide 8).
# synergy.png       : interseccao dos dois ecossistemas, valor compartilhado no centro (slide 4).
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle
from pathlib import Path
from PIL import Image, ImageDraw

BASE = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck")
PURPLE = "#461DA3"; LILAC = "#A98EEC"; TEAL = "#44789B"; BLUE = "#6CBEDE"
ORANGE = "#E0611F"; RED = "#B83713"; DARK = "#242016"


def box(ax, x, y, w, h, text, fc, tc="white", fs=16):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.10",
                 linewidth=0, facecolor=fc))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            color=tc, fontsize=fs, fontweight="bold")


def arrow(ax, x1, y1, x2, y2, color, lw=3):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw, shrinkA=0, shrinkB=0))


def strategy_flow():
    fig, ax = plt.subplots(figsize=(12, 3.4), dpi=200)
    ax.set_xlim(0, 12); ax.set_ylim(0, 3.4); ax.axis("off")
    box(ax, 0.2, 1.55, 3.0, 1.0, "ESTRATÉGIA", PURPLE)
    box(ax, 4.5, 1.55, 3.0, 1.0, "EXECUÇÃO", PURPLE)
    box(ax, 8.8, 1.55, 3.0, 1.0, "VALOR\nENTREGUE", TEAL)
    arrow(ax, 3.25, 2.05, 4.45, 2.05, DARK)
    arrow(ax, 7.55, 2.05, 8.75, 2.05, DARK)
    box(ax, 4.0, 0.20, 4.0, 0.8, "Gestão de Projetos · CPMAI", ORANGE, fs=13)
    arrow(ax, 6.0, 1.05, 6.0, 1.5, ORANGE, lw=2.5)
    ax.text(3.85, 3.12, "projetos de IA travam aqui", ha="center", va="center",
            color=RED, fontsize=12, fontweight="bold")
    arrow(ax, 3.85, 2.88, 3.85, 2.18, RED, lw=2)
    fig.savefig(BASE / "assets/strategy_flow.png", transparent=True, bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)
    print("wrote assets/strategy_flow.png")


def synergy():
    fig, ax = plt.subplots(figsize=(11, 5.2), dpi=200)
    ax.set_xlim(0, 11); ax.set_ylim(0, 5.2); ax.axis("off")
    ax.set_aspect("equal")
    r = 2.35
    cxl, cxr, cy = 3.7, 7.3, 2.7
    ax.add_patch(Circle((cxl, cy), r, facecolor=LILAC, alpha=0.45, edgecolor=PURPLE, linewidth=2.5))
    ax.add_patch(Circle((cxr, cy), r, facecolor=BLUE, alpha=0.40, edgecolor=TEAL, linewidth=2.5))
    ax.text(2.55, cy + 0.15, "ALUN", ha="center", va="center", color=PURPLE, fontsize=20, fontweight="bold")
    ax.text(2.55, cy - 0.5, "forma o talento\nem IA, em escala", ha="center", va="center", color=DARK, fontsize=11)
    ax.text(8.45, cy + 0.15, "Núcleo / PMI", ha="center", va="center", color=TEAL, fontsize=18, fontweight="bold")
    ax.text(8.45, cy - 0.55, "ambiente, execução\ne certificação", ha="center", va="center", color=DARK, fontsize=11)
    ax.text(5.5, cy + 0.35, "Profissionais\nde IA que\nentregam projetos", ha="center", va="center",
            color=DARK, fontsize=12.5, fontweight="bold")
    fig.savefig(BASE / "assets/synergy.png", transparent=True, bbox_inches="tight", pad_inches=0.06)
    plt.close(fig)
    print("wrote assets/synergy.png")


def prep_certs():
    """Make the uniform background of cert badges (white for PMP/CP, dark for CPMAI/PMOCP) transparent,
    so they float cleanly on any slide bg. Flood-fills from the 4 corners with the corner's own color."""
    src = BASE / "assets/inbox_r1"
    out = BASE / "assets/certs_proc"; out.mkdir(exist_ok=True)
    for f in ("PMI-CPMAI.png", "PMI-PMOCP.png", "PMP.jpeg", "PMI-ACP.png", "PMI-CP.png", "PMI CSPP.jpeg"):
        p = src / f
        if not p.exists():
            continue
        im = Image.open(p).convert("RGBA")
        w, h = im.size
        for c in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            seed = im.getpixel(c)
            ImageDraw.floodfill(im, c, (seed[0], seed[1], seed[2], 0), thresh=50)
        im.save(out / (Path(f).stem + ".png"))
    print("wrote assets/certs_proc/*.png")


if __name__ == "__main__":
    strategy_flow()
    synergy()
    prep_certs()
