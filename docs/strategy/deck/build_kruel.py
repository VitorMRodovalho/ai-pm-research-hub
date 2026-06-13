#!/usr/bin/env python
# Build the COOPERATION pitch deck: Núcleo IA & GP × Grupo ALUN (interlocutor: Cristiano Kruel).
#   ~/.venvs/pmo/bin/python gen_assets_kruel.py && ~/.venvs/pmo/bin/python build_kruel.py
# Reuses deck_engine.py (branded clone/inject/guards/render) untouched. Content: deck_content_kruel.py.
# Photos: assets/people/{vitor,fabricio}.jpg. Covers (drop-in): assets/covers/{mckinsey,pmi_pulse,
# ansi_ai_standard,pmbok}.(png|jpg) -> placeholder box if missing. Diagram: assets/strategy_flow.png.
# 11 slides, PT-BR.
from pathlib import Path
from PIL import Image
from deck_engine import Deck, PURPLE, TEAL, BLUE, GREEN, RED, ORANGE, LILAC, DARK, GRAY
from deck_content_kruel import CONTENT

BASE = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck")
TEMPLATE = BASE / "build/pmi_template.pptx"
LOGO = "/home/vitormrodovalho/projects/_pmo/assets/pmi/brand/pmigo-logo-white.png"
PEOPLE = BASE / "assets/people"
COVERS = BASE / "assets/covers"
DIAGRAM = BASE / "assets/strategy_flow.png"
HUB = BASE / "assets/hub_spoke.png"   # only stored on the Deck; never used without an explicit path here
OUT = BASE / "Nucleo_IA_GP_Pitch_ALUN_Kruel.pptx"
PREVIEW = BASE / "preview_kruel"


def two_col(d, s, top, h1, l1, h2, l2, c1=PURPLE, c2=ORANGE, bh=3.5):
    d.add_box(s, 0.62, top, 5.95, bh, h1, l1, hcolor=c1)
    d.add_box(s, 6.95, top, 5.75, bh, h2, l2, hcolor=c2)


def caption(d, s, top, text, color=PURPLE, w=12.1):
    d.add_box(s, 0.62, top, w, 0.95, "", [text], hcolor=color, fs=13, body=color)


def place_fit(d, s, left, top, boxw, boxh, path):
    """Fit an image inside (boxw x boxh) preserving aspect, centered. For unknown-size drop-ins."""
    with Image.open(path) as im:
        iw, ih = im.size
    ar = iw / ih
    if boxw / boxh > ar:
        h = boxh; w = h * ar
    else:
        w = boxw; h = w / ar
    pic = s.shapes.add_picture(path, d.IN(left + (boxw - w) / 2), d.IN(top + (boxh - h) / 2),
                               width=d.IN(w), height=d.IN(h))
    d._track(s, pic)
    return pic


def cover_slot(d, s, left, top, w, h, slot, label):
    """A drop-in cover image (png/jpg) with a label below; placeholder box if the file is absent."""
    found = None
    for ext in (".png", ".jpg", ".jpeg"):
        p = COVERS / f"{slot}{ext}"
        if p.exists():
            found = p; break
    if found:
        place_fit(d, s, left, top, w, h, str(found))
    else:
        d.add_box(s, left, top, w, h, "[ Capa ]", [], hcolor=GRAY, hfs=12, body=GRAY)
    d.add_box(s, left, top + h + 0.04, w, 0.4, "", [label], fs=9, body=GRAY)


def compose(d, C):
    # warn on titles likely to wrap (template title is ~1 line up to ~44 chars)
    for k, v in C.items():
        t = v.get("title", "") if isinstance(v, dict) else ""
        if len(t) > 44:
            print(f"  WARN: title may wrap ({len(t)} chars): {t!r}")

    # 1 cover
    cov = C["cover"]
    d.cover(cov["title"], cov["sub"], cov["attr"], cov["note"])

    # 2 the fit (MAIVP wedge)
    f = C["fit"]
    def b_fit(s, top):
        two_col(d, s, top, f["h1"], f["l1"], f["h2"], f["l2"], bh=3.5)
        caption(d, s, top + 3.7, f["caption"])
    d.content(f["eyebrow"], f["title"], b_fit, f["note"])

    # 3 the problem (Vitor's strategy-flow diagram + drop-in source covers)
    p = C["problem"]
    def b_prob(s, top):
        d.add_image(s, top + 0.15, 7.2, left=0.4, path=str(DIAGRAM))
        d.add_box(s, 0.5, top + 2.45, 7.1, 2.0, "", [p["caption"]], hcolor=PURPLE, fs=12.5, body=DARK)
        cv = p["covers"]
        cover_slot(d, s, 8.1, top + 0.2, 4.2, 1.85, cv[0]["slot"], cv[0]["label"])
        cover_slot(d, s, 8.1, top + 2.55, 4.2, 1.85, cv[1]["slot"], cv[1]["label"])
    d.content(p["eyebrow"], p["title"], b_prob, p["note"])

    # 4 who we are + proof band (LIM LATAM, SESTEC, Carlos Novello)
    w = C["who"]
    def b_who(s, top):
        two_col(d, s, top, w["h1"], w["l1"], w["h2"], w["l2"], c2=TEAL, bh=3.3)
        d.add_box(s, 0.62, top + 3.5, 12.1, 1.15, w["proof_h"], w["proof"], hcolor=ORANGE, hfs=14, fs=11.5)
    d.content(w["eyebrow"], w["title"], b_who, w["note"])

    # 5 ANSI authority (table + drop-in standard covers)
    a = C["ansi"]
    def b_ansi(s, top):
        d.add_table(s, [a["head"]] + a["rows"], top + 0.1, left=0.62, width=7.0, widths=[2.0, 5.0], fs=11)
        d.add_box(s, 0.62, top + 3.5, 7.0, 1.0, a["caption"], [], hcolor=PURPLE, hfs=14)
        cv = a["covers"]
        cover_slot(d, s, 8.0, top + 0.1, 4.3, 1.7, cv[0]["slot"], cv[0]["label"])
        cover_slot(d, s, 8.0, top + 2.35, 4.3, 1.7, cv[1]["slot"], cv[1]["label"])
    d.content(a["eyebrow"], a["title"], b_ansi, a["note"])

    # 6 the gap
    g = C["gap"]
    def b_gap(s, top):
        two_col(d, s, top, g["h1"], g["l1"], g["h2"], g["l2"], bh=3.5)
        caption(d, s, top + 3.7, g["caption"])
    d.content(g["eyebrow"], g["title"], b_gap, g["note"])

    # 7 the value exchange
    e = C["exchange"]
    def b_exch(s, top):
        d.add_box(s, 0.62, top, 5.95, 3.6, e["h1"], e["l1"], hcolor=TEAL)
        d.add_box(s, 6.95, top, 5.75, 3.6, e["h2"], e["l2"], hcolor=PURPLE)
        d.add_box(s, 0.62, top + 3.8, 12.1, 0.9, "", [e["caption"]], hcolor=TEAL, fs=13, body=DARK)
    d.content(e["eyebrow"], e["title"], b_exch, e["note"])

    # 8 three fronts (3 columns)
    fr = C["fronts"]
    def b_fronts(s, top):
        (h1, l1), (h2, l2), (h3, l3) = fr["cols"]
        y = top + 0.2
        d.add_box(s, 0.62, y, 3.85, 4.0, h1, l1, hcolor=BLUE)
        d.add_box(s, 4.74, y, 3.85, 4.0, h2, l2, hcolor=TEAL)
        d.add_box(s, 8.86, y, 3.85, 4.0, h3, l3, hcolor=PURPLE)
    d.content(fr["eyebrow"], fr["title"], b_fronts, fr["note"])

    # 9 the path (3 steps + arrows)
    pa = C["path"]
    def b_path(s, top):
        y = top + 0.4; h = 3.0
        (h1, l1), (h2, l2), (h3, l3) = pa["steps"]
        d.add_box(s, 0.62, y, 3.5, h, h1, l1, hcolor=BLUE)
        d.add_arrow(s, 4.25, y + 1.0, color=LILAC)
        d.add_box(s, 4.85, y, 3.5, h, h2, l2, hcolor=TEAL)
        d.add_arrow(s, 8.5, y + 1.0, color=LILAC)
        d.add_box(s, 9.1, y, 3.6, h, h3, l3, hcolor=PURPLE)
    d.content(pa["eyebrow"], pa["title"], b_path, pa["note"])

    # 10 project managers (photos + LinkedIn + Credly)
    mg = C["managers"]
    def b_mgr(s, top):
        pw = 2.4
        for left, person in ((2.0, mg["people"][0]), (8.7, mg["people"][1])):
            photo = PEOPLE / person["photo"]
            if photo.exists():
                d.add_image(s, top + 0.05, pw, left=left, path=str(photo))
            else:
                d.add_box(s, left, top + 0.05, pw, pw, "[ FOTO ]", [person["photo"]],
                          hcolor=GRAY, hfs=14, fs=10, body=GRAY)
            d.add_box(s, left - 0.4, top + 2.6, pw + 0.8, 1.3,
                      person["name"],
                      [person["role"], person["sub"],
                       f'in/{person["linkedin"].split("/in/")[-1]}  ·  {person["credly"]}'],
                      hcolor=PURPLE, hfs=14, fs=11)
        d.add_box(s, 0.62, top + 4.0, 12.1, 0.75, "", [mg["link"], mg["mentor"]],
                  hcolor=TEAL, fs=12, body=DARK)
    d.content(mg["eyebrow"], mg["title"], b_mgr, mg["note"])

    # 11 the ask
    ak = C["ask"]
    def b_ask(s, top):
        two_col(d, s, top, ak["h1"], ak["l1"], ak["h2"], ak["l2"], c2=TEAL, bh=3.6)
        d.add_box(s, 0.62, top + 3.8, 12.1, 0.9, ak["cta_h"], [ak["cta"]],
                  hcolor=ORANGE, hfs=15, fs=13)
    d.content(ak["eyebrow"], ak["title"], b_ask, ak["note"])


def main():
    d = Deck(TEMPLATE, OUT, PREVIEW, HUB, LOGO)
    compose(d, CONTENT["pt"])
    d.finalize()


if __name__ == "__main__":
    main()
