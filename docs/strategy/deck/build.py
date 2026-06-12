#!/usr/bin/env python
# Build the Núcleo executive pitch deck in any configured language.
#   python build.py            -> all editions (pt, en)
#   python build.py pt         -> just PT-BR
#   python build.py en         -> just EN-US
# Engine: deck_engine.py (branded clone/inject/guards/render). Content: deck_content.py (strings).
# This file holds the LAYOUT (positions, colors, slide order) ONCE; both languages share it.
# A new language = add a dict to deck_content.py + an entry to EDITIONS below. Nothing else.
import sys
from pathlib import Path
from deck_engine import Deck, PURPLE, TEAL, BLUE, GREEN, RED, ORANGE, LILAC, DARK
from deck_content import CONTENT

BASE = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck")
TEMPLATE = BASE / "build/pmi_template.pptx"
LOGO = "/home/vitormrodovalho/projects/19SGPL-PMIGO/MKT/Pending/pmi_chp_logo_goias_brazil_hrz_wht.png"

EDITIONS = {
    "pt": {"out": "Nucleo_IA_GP_Pitch_Executivo.pptx",   "preview": "preview",    "hub": "assets/hub_spoke.png"},
    "en": {"out": "Nucleo_IA_GP_Pitch_Executive_EN.pptx", "preview": "preview_en", "hub": "assets/hub_spoke_en.png"},
}

VCOLORS = [ORANGE, TEAL, BLUE, GREEN, RED]   # Construction, PMO, Agile, ESG, Business


def compose(d, C):
    """The 15-slide layout, shared by every language. Only strings come from C."""
    L = C["labels"]

    # 1 cover (dual-language brand: title kept verbatim, gloss in the subtitle)
    cov = C["cover"]
    d.cover(cov["title"], cov["sub"], cov["attr"], cov["note"])

    # 2 the problem (two columns)
    p = C["problem"]
    def b_prob(s, top):
        d.add_box(s, 0.62, top, 5.95, 4.3, p["h1"], p["l1"], hcolor=PURPLE)
        d.add_box(s, 6.95, top, 5.75, 4.3, p["h2"], p["l2"], hcolor=ORANGE)
    d.content(p["eyebrow"], p["title"], b_prob, p["note"])

    # 3 the tailwind (table + closing line) -- killer slide
    t = C["tailwind"]
    def b_tail(s, top):
        d.add_table(s, [t["head"]] + t["rows"], top, widths=[1.4, 6.8], fs=13)
        d.add_box(s, 0.62, top+2.95, 12.1, 1.1, t["caption"], [], hcolor=PURPLE, hfs=15)
    d.content(t["eyebrow"], t["title"], b_tail, t["note"])

    # 4 the model (hub-and-spoke image + caption)
    m = C["model"]
    def b_model(s, top):
        d.add_image(s, top-0.15, 9.7)
        d.add_box(s, 0.62, top+4.35, 12.1, 1.0, "", m["caption"], hcolor=PURPLE, fs=12, hfs=13, body=DARK)
    d.content(m["eyebrow"], m["title"], b_model, m["note"])

    # 5 the ladder (3 steps + arrows)
    lad = C["ladder"]
    def b_ladder(s, top):
        y = top + 0.35; h = 3.0
        (h1, l1), (h2, l2), (h3, l3) = lad["steps"]
        d.add_box(s, 0.62, y, 3.5, h, h1, l1, hcolor=BLUE)
        d.add_arrow(s, 4.25, y+1.0, color=LILAC)
        d.add_box(s, 4.85, y, 3.5, h, h2, l2, hcolor=TEAL)
        d.add_arrow(s, 8.5, y+1.0, color=LILAC)
        d.add_box(s, 9.1, y, 3.6, h, h3, l3, hcolor=PURPLE)
    d.content(lad["eyebrow"], lad["title"], b_ladder, lad["note"])

    # 6 reach & coverage
    r = C["reach"]
    def b_reach(s, top):
        d.add_box(s, 0.62, top, 5.95, 4.0, r["h1"], r["l1"], hcolor=PURPLE)
        d.add_box(s, 6.95, top, 5.75, 4.0, r["h2"], r["l2"], hcolor=TEAL)
        d.add_box(s, 0.62, top+4.15, 12.1, 0.55, r["lgpd"], [], hcolor=ORANGE, hfs=12)
    d.content(r["eyebrow"], r["title"], b_reach, r["note"])

    # 7..11 verticals (one layout, five contents). Construction carries the leadership band.
    for v, color in zip(C["verticals"], VCOLORS):
        def b_vert(s, top, v=v, color=color):
            bh = 3.4 if v["bordo"] else 4.1
            d.add_box(s, 0.62, top, 5.95, bh, L["audience_pain"], v["dor"], hcolor=color)
            d.add_box(s, 6.95, top, 5.75, bh, L["ai_thesis"], v["teses"], hcolor=PURPLE)
            if v["bordo"]:
                d.add_box(s, 0.62, top+bh+0.15, 12.1, 1.55, L["on_board"], v["bordo"],
                          hcolor=ORANGE, hfs=14, fs=12.5)
            else:
                d.add_box(s, 0.62, top+4.2, 12.1, 0.6, "",
                          [f'{L["timing"]} {v["timing"]}', f'{L["anchor_proof"]} {v["prova"]}'],
                          fs=11.5, body=DARK)
        d.content(v["eyebrow"], v["title"], b_vert, v["note"])

    # 12..14 the ask (3 swappable variations)
    for a in C["asks"]:
        def b_ask(s, top, a=a):
            d.add_box(s, 0.62, top, 12.1, 1.7, a["h1"], a["l1"], hcolor=PURPLE)
            d.add_box(s, 0.62, top+1.9, 12.1, 1.6, a["h2"], a["l2"], hcolor=TEAL)
        d.content(a["eyebrow"], a["title"], b_ask, a["note"])

    # 15 next steps (activation order table + CTA)
    nx = C["next"]
    def b_next(s, top):
        d.add_table(s, [nx["head"]] + nx["rows"], top, widths=[1.8, 4.8, 1.9], fs=12)
        d.add_box(s, 0.62, top+2.95, 12.1, 1.1, nx["cta_h"], nx["cta"], hcolor=ORANGE, hfs=15, fs=12.5)
    d.content(nx["eyebrow"], nx["title"], b_next, nx["note"])


def build(lang):
    if lang not in EDITIONS:
        raise SystemExit(f"unknown edition {lang!r}; known: {', '.join(EDITIONS)}")
    cfg = EDITIONS[lang]
    d = Deck(TEMPLATE, BASE / cfg["out"], BASE / cfg["preview"], BASE / cfg["hub"], LOGO)
    compose(d, CONTENT[lang])
    d.finalize()


if __name__ == "__main__":
    langs = sys.argv[1:] or list(EDITIONS)
    if langs == ["all"]: langs = list(EDITIONS)
    for lang in langs:
        build(lang)
