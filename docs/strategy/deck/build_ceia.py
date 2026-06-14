#!/usr/bin/env python
# Short 6-slide cooperation brief: Núcleo IA & GP × CEIA-UFG (P&D / Research archetype) — LIGHT theme.
#   ~/.venvs/pmo/bin/python build_ceia.py
# Reuses deck_engine.py + the layout helpers from build_kruel.py. Content is inline (one-off, 6 slides).
# Grounding: CEIA = UFG AI Center of Excellence, EMBRAPII unit, 30+ companies, GPAI (UFG/EMBRAPII/FAPEG).
# Numbers do Núcleo = get_public_impact_data; ANSI 26-007 = selo da capa oficial. Sem travessao (guard).
from pathlib import Path
from pathlib import Path as _P
from deck_engine import Deck, PURPLE, TEAL, ORANGE, LIGHT, GRAY, FONT
from build_kruel import (two_col, caption, linked_line, cover_slot, place_fit,
                         A1, A2, A3, COVERS, CERTS_PROC, PEOPLE)

BASE = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck")
TEMPLATE = BASE / "build/pmi_template.pptx"
LOGO = "/home/vitormrodovalho/projects/_pmo/assets/pmi/brand/pmigo-logo-white.png"
OUT = BASE / "Nucleo_IA_GP_CEIA_UFG_PnD.pptx"
PREVIEW = BASE / "preview_ceia"
HUB = BASE / "assets/hub_spoke.png"
BRIDGE = BASE / "assets/ceia_bridge.png"   # 3-stage thesis infographic (gen_assets_ceia.py)

C = {
    "cover": {
        "title": "Núcleo IA & GP  ×  CEIA-UFG",
        "sub": "Proposta de Cooperação em P&D  ·  PMI-GO  ·  Junho de 2026",
        "attr": "PMI, o logotipo PMI, PMP, PMI-CPMAI e CPMAI são marcas do Project Management Institute, Inc. "
                "Uso conforme as diretrizes de marca para capítulos. Dados do CEIA: fontes públicas (UFG/EMBRAPII), jun/2026.",
        "note": "Brief curto (6 slides) p/ o CEIA-UFG (centro de IA da UFG, fundado 2019, unidade EMBRAPII; "
                "+100 projetos, ~1.100-1.150 pesquisadores; internacional: ONU AI for Good, NVIDIA AI Nations, GPAI). "
                "Arquetipo P&D/Research. Decisores: Telma Woerle (diretora-executiva), Anderson Soares (cientifico/GPAI).",
    },
    "fit": {
        "eyebrow": "O encaixe",
        "title": "Pesquisa de IA que vira projeto entregue",
        "caption": "Complementar, não concorrente: o CEIA constrói e transfere a IA; o Núcleo/PMI traz a disciplina de entrega (CPMAI) e o padrão (ANSI). Mesmo estado, em Goiás.",
    },
    "synergy": {
        "eyebrow": "A sinergia",
        "title": "Onde CEIA e PMI se encontram",
        "h1": "O CEIA traz",
        "l1": ["Pesquisa aplicada de IA: +100 projetos, ~1.100-1.150 pesquisadores; sede própria em 2026.",
               "Trilho de fomento da Lei 10.973 (EMBRAPII) e empresas parceiras (Copel, iFood, Falconi).",
               "Internacional: ONU AI for Good, NVIDIA AI Nations, GPAI, Vale do Silício."],
        "h2": "O Núcleo / PMI traz",
        "l2": ["Execução e o método CPMAI; o standard ANSI de IA.",
               "Funil de certificação global e comunidade de 15 capítulos.",
               "Tribos de pesquisa, exposição (SGPL, webinars) e PI conjunta."],
        "caption": "No encontro: pesquisa que vira projeto, carreira e case. Ativa a arena de conhecimento e pesquisa do PMI:Next.",
    },
    "ansi": {
        "eyebrow": "A autoridade",
        "title": "O PMI não só usa IA: escreve o padrão",
        "head": ["Padrão (ANSI)", "O que o PMI define"],
        "rows": [
            ["ANSI/PMI 26-007 · 2026", "Standard for AI in Portfolio, Program and Project Mgmt: 1º standard de IA aprovado pela ANSI; alinhado a EU AI Act e ISO 42001."],
            ["ANSI/PMI 99-001", "Standard for Project Management (PMBOK Guide 7ª ed.)."],
            ["ANSI/PMI 08-002", "Standard for Program Management (2024)."],
            ["ANSI/PMI 08-003", "Standard for Portfolio Management (2017)."],
        ],
        "caption": "E não só padrão: um roadmap de carreira do PMP às especializações, até a fronteira (a IA). PMIxAI: 4 cursos de IA (+350 mil inscritos), AI Practice Guide e PMI Infinity.",
        "covers": [
            {"slot": "ansi_ai_standard", "label": "Standard de IA · ANSI/PMI 26-007 (2026)"},
        ],
        "certs": [
            {"file": "PMP.png", "label": "PMP", "desc": "Gerenciamento de projetos"},
            {"file": "PMI-ACP.png", "label": "PMI-ACP", "desc": "Práticas ágeis"},
            {"file": "PMI-PMOCP.png", "label": "PMI-PMOCP", "desc": "Gestão de PMO"},
            {"file": "PMI-CP.png", "label": "PMI-CP", "desc": "Construção"},
            {"file": "PMI CSPP.png", "label": "CSPP", "desc": "Sustentabilidade · ESG"},
            {"file": "PMI-CPMAI.png", "label": "PMI-CPMAI", "desc": "Gestão de IA", "hero": True},
        ],
    },
    "managers": {
        "eyebrow": "Quem conduz",
        "title": "Gestores do projeto",
        "people": [
            {"name": "Vitor Maia Rodovalho", "role": "Idealizador e líder · Núcleo IA & GP",
             "sub": "Senior Cost Manager na Linesight (grupo Berkshire Hathaway), em projetos de data centers para a Google.",
             "photo": "vitor.jpg", "linkedin": "linkedin.com/in/vitor-rodovalho-pmp",
             "phone": "+1 267-874-8329"},
            {"name": "Fabrício Costa", "role": "Co-gestor · Núcleo IA & GP",
             "sub": "Program Manager de Design e Engenharia na AWS; doutorando em Business.",
             "photo": "fabricio.jpg", "linkedin": "linkedin.com/in/fabriciorcc",
             "phone": "+1 503-544-7898"},
        ],
        "links": [
            ("Plataforma do Núcleo", "nucleoia.pmigo.org.br", "https://nucleoia.pmigo.org.br"),
            ("PMI", "pmi.org", "https://www.pmi.org"),
        ],
    },
    "how": {
        "eyebrow": "Como cooperar",
        "title": "Três jeitos leves de começar",
        "cols": [
            ["1 · Co-pesquisa", ["A lente de gestão (CPMAI) sobre um caso de IA do CEIA.", "Vira artigo e case para os dois lados.", "Sem acordo, começa já."]],
            ["2 · Mesa-redonda", ["Seminário conjunto sobre IA aplicada à gestão.", "Palco e marca compartilhados.", "Formato ao vivo, com transmissão."]],
            ["3 · Tribo de pesquisa", ["Pesquisadores do CEIA numa tribo do Núcleo.", "Pesquisa aplicada, com PI conjunta.", "Funil para certificação e comunidade."]],
        ],
        "caption": "Mesmo estado (Goiás), sem MoU, mensurável. Horizonte (não a abertura): acordo-âncora de P&D como ICT sob a Lei de Inovação (10.973).",
    },
    "ask": {
        "eyebrow": "O convite",
        "title": "Vamos fechar o ciclo da IA, em Goiás",
        "h1": "O pedido",
        "l1": ["Escolher 1 das 3 frentes para um primeiro movimento.",
               "Um café de 30 min ou async, no seu tempo.",
               "Mesmo estado: PMI-GO e CEIA-UFG, lado a lado."],
        "h2": "Pontes já abertas",
        "l2": ["SGPL 24-26/set (Goiânia) como primeiro palco.",
               "Janela quente: standard de IA recém-publicado; sede do CEIA inaugura set/2026."],
        "cta_h": "CEIA + PMI",
        "cta": "Pesquisa que entrega valor. Vamos fechar o ciclo.",
        "links": [("Plataforma do Núcleo", "nucleoia.pmigo.org.br", "https://nucleoia.pmigo.org.br"),
                  ("PMI", "pmi.org", "https://www.pmi.org")],
    },
}


def compose(d):
    cov = C["cover"]; d.cover(cov["title"], cov["sub"], cov["attr"], cov["note"])

    f = C["fit"]
    def b_fit(s, top):
        top += 0.55
        # the thesis infographic (constrói -> gestão+padrão -> valor) carries this slide
        d.add_image(s, top, 11.4, path=str(BRIDGE))   # aspect 12.5:3.4 -> h ~3.10 at w 11.4
        caption(d, s, top + 3.3, f["caption"])
    d.content(f["eyebrow"], f["title"], b_fit, "")

    sy = C["synergy"]
    def b_syn(s, top):
        top += 0.35
        two_col(d, s, top, sy["h1"], sy["l1"], sy["h2"], sy["l2"], c1=A1, c2=A2, bh=2.9)
        caption(d, s, top + 3.05, sy["caption"], color=A2)
    d.content(sy["eyebrow"], sy["title"], b_syn, "")

    a = C["ansi"]
    def b_ansi(s, top):
        d.add_table(s, [a["head"]] + a["rows"], top + 0.05, left=0.62, width=7.1, widths=[2.1, 5.0], fs=10)
        cv = a["covers"][0]
        cover_slot(d, s, 8.2, top + 0.05, 4.3, 2.2, cv["slot"], cv["label"], framed=True)
        d.add_box(s, 0.62, top + 2.55, 12.1, 0.5, "", [a["caption"]], hcolor=A2, fs=11.5)
        n = len(a["certs"]); cw = 12.1 / n; bw = 1.05
        for i, c in enumerate(a["certs"]):
            cx = 0.62 + i * cw + (cw - bw) / 2
            proc = CERTS_PROC / (_P(c["file"]).stem + ".png")
            if proc.exists():
                place_fit(d, s, cx, top + 3.0, bw, 1.0, str(proc))
            else:
                d.add_box(s, cx, top + 3.0, bw, 1.0, "[ " + c["label"] + " ]", [], hcolor=GRAY, hfs=10, body=GRAY)
            hc = A3 if c.get("hero") else A1
            d.add_box(s, 0.62 + i * cw + 0.05, top + 4.05, cw - 0.1, 0.75, c["label"], [c["desc"]], hcolor=hc, hfs=10.5, fs=9)
    d.content(a["eyebrow"], a["title"], b_ansi, "")

    h = C["how"]
    def b_how(s, top):
        top += 0.5
        (h1, l1), (h2, l2), (h3, l3) = h["cols"]
        d.add_box(s, 0.62, top, 3.85, 2.9, h1, l1, hcolor=A1)
        d.add_box(s, 4.74, top, 3.85, 2.9, h2, l2, hcolor=A2)
        d.add_box(s, 8.86, top, 3.85, 2.9, h3, l3, hcolor=A3)
        caption(d, s, top + 3.05, h["caption"], color=A1)
    d.content(h["eyebrow"], h["title"], b_how, "")

    mg = C["managers"]
    def b_mgr(s, top):
        pw, txw = 2.0, 3.6
        for left, person in ((0.7, mg["people"][0]), (6.9, mg["people"][1])):
            photo = PEOPLE / person["photo"]
            if photo.exists():
                d.add_image(s, top + 0.05, pw, left=left, path=str(photo))
            else:
                d.add_box(s, left, top + 0.05, pw, pw, "[ FOTO ]", [person["photo"]],
                          hcolor=GRAY, hfs=14, fs=10, body=GRAY)
            tx = left + pw + 0.3
            d.add_box(s, tx, top + 0.05, txw, 1.9, person["name"],
                      [person["role"], person["sub"]], hcolor=A1, hfs=15, fs=11)
            linked_line(d, s, tx, top + 2.05, txw, 0.4,
                        [("LinkedIn: " + person["linkedin"], "https://" + person["linkedin"], A2)], fs=11)
            linked_line(d, s, tx, top + 2.45, txw, 0.4,
                        [("Tel: ", None, GRAY), (person["phone"], "tel:" + person["phone"].replace(" ", ""), A2)], fs=11)
        segs = []
        for i, (lbl, shown, url) in enumerate(mg["links"]):
            if i: segs.append(("    ·    ", None, GRAY))
            segs.append((lbl + ": ", None, GRAY)); segs.append((shown, url, A2))
        linked_line(d, s, 0.62, top + 4.05, 12.1, 0.5, segs, fs=11)
    d.content(mg["eyebrow"], mg["title"], b_mgr, "")

    ak = C["ask"]
    def b_ask(s, top):
        top += 0.4
        two_col(d, s, top, ak["h1"], ak["l1"], ak["h2"], ak["l2"], c1=A1, c2=A2, bh=2.7)
        d.add_box(s, 0.62, top + 2.9, 12.1, 0.85, ak["cta_h"], [ak["cta"]], hcolor=A3, hfs=15, fs=13)
        segs = []
        for i, (lbl, shown, url) in enumerate(ak["links"]):
            if i: segs.append(("    ·    ", None, GRAY))
            segs.append((lbl + ": ", None, GRAY)); segs.append((shown, url, A2))
        linked_line(d, s, 0.62, top + 3.95, 12.1, 0.4, segs, fs=11)
    d.content(ak["eyebrow"], ak["title"], b_ask, "")


def main():
    d = Deck(TEMPLATE, OUT, PREVIEW, HUB, LOGO, dark=False)
    compose(d)
    d.finalize()


if __name__ == "__main__":
    main()
