#!/usr/bin/env python
# Deck curto (pré-leitura async) Núcleo IA & GP -> PMI-LATAM, para Natália Tavares
# (Regional Head of Community, LATAM). Tema CLARO (brand PMI). 7 slides, PT-BR.
#   ~/.venvs/pmo/bin/python build_latam.py
# Reusa deck_engine.py + helpers/acervo do build_kruel (covers ANSI, badges, fotos).
# Ângulo: o Núcleo é um motor dos KPIs que ela lidera (engajamento, retenção,
# vitalidade de capítulos, valor pro membro, inovação/IA). Ask ABERTO (reunião).
# Números = dashboard operacional (Ciclo 3, 2026/1), NÃO o RPC público (que soma
# pré-onboarding). 47 ativos C3 + 25 pré-onboarding -> ~90 projetado no Ciclo 4 (1º/jul).
# Sem travessao (guard). Sem Mário/seminário (regra: só o ALUN usa).
from pathlib import Path
from pathlib import Path as _P
from deck_engine import Deck, PURPLE, TEAL, ORANGE, LIGHT, GRAY, FONT
from build_kruel import (two_col, caption, linked_line, cover_slot, place_fit,
                         A1, A2, A3, COVERS, CERTS_PROC, PEOPLE)

BASE = Path("/home/vitormrodovalho/projects/ai-pm-research-hub/docs/strategy/deck")
TEMPLATE = BASE / "build/pmi_template.pptx"
LOGO = "/home/vitormrodovalho/projects/_pmo/assets/pmi/brand/pmigo-logo-white.png"
OUT = BASE / "Nucleo_IA_GP_PMI_LATAM_Natalia.pptx"
PREVIEW = BASE / "preview_latam"
HUB = BASE / "assets/hub_spoke.png"

C = {
    "cover": {
        "title": "Núcleo IA & GP",
        "sub": "Aproximação ao PMI-LATAM  ·  Para Natália Tavares, Regional Head of Community  ·  Junho de 2026",
        "attr": "PMI, o logotipo PMI, PMP, PMI-ACP, PMI-CP, PMI-PMOCP, PMI-CPMAI, CSPP e CPMAI são marcas do "
                "Project Management Institute, Inc. Uso conforme as diretrizes de marca para capítulos. "
                "Números do Núcleo: dashboard da plataforma, Ciclo 3 (2026/1), jun/2026.",
        "note": "Pré-leitura async p/ a Natália Tavares (Regional Head of Community, LATAM). Aberta por Fabrício "
                "via LATAM Construction Ambassadors; Vitor já teve conversa inicial. Objetivo: tangibilizar a "
                "iniciativa e garantir a reunião. Ângulo: somos um motor dos KPIs que ela lidera.",
    },
    "who": {
        "eyebrow": "Quem somos",
        "title": "Comunidade de prática federada de IA e GP",
        "lead": "Iniciativa federada de Communities of Practice (CoP, conceito do próprio PMI), nascida no PMI-GO, "
                "voluntária, com foco único: IA aplicada à gestão de projetos.",
        "h1": "Pessoas e cultura",
        "l1": ["Time voluntário selecionado por critério: mestres, doutores, C-level, professores, gestores.",
               "Segunda onda de protagonismo dentro da comunidade PMI.",
               "Começou no PMI-GO; hoje engaja capítulos do PMI no Brasil por cooperação."],
        "h2": "O que o Núcleo gera",
        "l2": ["Verticais de pesquisa e tribos temáticas de IA.",
               "Upskilling, networking e oportunidades na comunidade PMI.",
               "Produção aplicada: artigos, pilotos e conteúdo para os capítulos."],
        "proof_h": "Onde estamos · Ciclo 3 (2026/1) · dados da plataforma",
        "proof": ["47 pesquisadores ativos · 7 tribos · 8 iniciativas · 324 eventos realizados.",
                  "5 capítulos PMI com pesquisadores (GO, CE, MG, RS, DF) e 15 capítulos engajados.",
                  "68% de taxa de retenção dos pesquisadores."],
    },
    "growth": {
        "eyebrow": "Tração e reconhecimento",
        "title": "Crescendo e reconhecido na LATAM",
        "h1": "Para onde vamos (Ciclo 4, 2026/2)",
        "l1": ["O Ciclo 4 começa em 1º de julho de 2026.",
               "25 pesquisadores aprovados em pré-onboarding, com nova onda de seleção a caminho.",
               "Projeção de aproximadamente 90 pesquisadores conectados no hub."],
        "h2": "Reconhecimento que conta",
        "l2": ["Finalista do Prêmio Carlos Novello (Voluntário do Ano), PMI LATAM Excellence Awards 2025.",
               "Sessão aceita no LIM LATAM 2026.",
               "4 artigos publicados no ProjectManagement.com e 1 piloto de IA em curso."],
        "caption": "Metas 2026: chegar a 8 capítulos PMI, avançar a trilha PMI AI e as certificações CPMAI, e firmar parcerias acadêmicas e de pesquisa.",
    },
    "value": {
        "eyebrow": "Por que ao PMI-LATAM",
        "title": "Um motor dos seus KPIs regionais",
        "boxes": [
            ("Engajamento e retenção", ["68% de retenção; voluntários ativos por critério.",
                                        "Comunidade viva em 5 capítulos, 15 engajados."], A1),
            ("Vitalidade de capítulos", ["Energiza capítulos e gera protagonismo local.",
                                         "Modelo replicável na LATAM, inclusive hispano."], A2),
            ("Valor pro membro e eventos", ["324 eventos, artigos no PM.com, webinars.",
                                            "Conteúdo e upskilling que aumentam a adoção."], A3),
            ("Inovação e IA · PMI:Next", ["IA aplicada à gestão: a fronteira do PMI.",
                                          "Alinhado ao standard ANSI de IA e ao PMI-CPMAI."], A1),
        ],
        "caption": "Exatamente o que a comunidade LATAM precisa medir e crescer: engajamento, retenção, vitalidade de capítulos e inovação.",
    },
    "ansi": {
        "eyebrow": "A fronteira",
        "title": "Operamos na fronteira que o PMI define",
        "head": ["Padrão (ANSI)", "O que o PMI define"],
        "rows": [
            ["ANSI/PMI 26-007 · 2026", "Standard for AI in Portfolio, Program and Project Mgmt: 1º standard de IA aprovado pela ANSI; alinhado a EU AI Act e ISO 42001."],
            ["ANSI/PMI 99-001", "Standard for Project Management (PMBOK Guide 7ª ed.)."],
            ["ANSI/PMI 08-002", "Standard for Program Management (2024)."],
            ["ANSI/PMI 08-003", "Standard for Portfolio Management (2017)."],
        ],
        "caption": "O Núcleo trabalha onde o PMI está escrevendo o padrão: IA. Um roadmap de carreira do PMP à fronteira (PMI-CPMAI).",
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
            {"name": "Fabrício Costa", "role": "Co-gestor · Núcleo IA & GP · LATAM Construction Ambassador",
             "sub": "Program Manager de Design e Engenharia na AWS; doutorando em Business.",
             "photo": "fabricio.jpg", "linkedin": "linkedin.com/in/fabriciorcc",
             "phone": "+1 503-544-7898"},
        ],
        "links": [
            ("Plataforma do Núcleo", "nucleoia.pmigo.org.br", "https://nucleoia.pmigo.org.br"),
            ("PMI", "pmi.org", "https://www.pmi.org"),
        ],
    },
    "ask": {
        "eyebrow": "O convite",
        "title": "Vamos nos aproximar do PMI-LATAM",
        "h1": "O pedido",
        "l1": ["Uma reunião curta para nos conhecermos e explorarmos o alinhamento.",
               "No seu tempo: async por aqui ou uma call de 30 min.",
               "Um ponto de contato no PMI-LATAM para seguirmos juntos."],
        "h2": "Pontes já abertas",
        "l2": ["Fabrício Costa, via LATAM Construction Ambassadors (do qual faz parte).",
               "Conversa inicial já iniciada com você, apresentando a iniciativa.",
               "Janela: novo ciclo começa 1º/jul e o standard de IA do PMI foi recém-publicado."],
        "cta_h": "Núcleo + PMI-LATAM",
        "cta": "Uma comunidade que cresce, engaja e inova. Queremos fazer isso com o PMI-LATAM.",
        "links": [("Plataforma do Núcleo", "nucleoia.pmigo.org.br", "https://nucleoia.pmigo.org.br"),
                  ("PMI", "pmi.org", "https://www.pmi.org")],
    },
}


def compose(d):
    cov = C["cover"]; d.cover(cov["title"], cov["sub"], cov["attr"], cov["note"])

    w = C["who"]
    def b_who(s, top):
        d.add_box(s, 0.62, top, 12.1, 0.7, "", [w["lead"]], hcolor=A1, fs=12.5)
        two_col(d, s, top + 0.8, w["h1"], w["l1"], w["h2"], w["l2"], c1=A1, c2=A2, bh=2.4)
        d.add_box(s, 0.62, top + 3.35, 12.1, 1.5, w["proof_h"], w["proof"], hcolor=A3, hfs=14, fs=10.5)
    d.content(w["eyebrow"], w["title"], b_who, "")

    g = C["growth"]
    def b_growth(s, top):
        top += 0.35
        two_col(d, s, top, g["h1"], g["l1"], g["h2"], g["l2"], c1=A1, c2=A2, bh=2.9)
        caption(d, s, top + 3.05, g["caption"], color=A2)
    d.content(g["eyebrow"], g["title"], b_growth, "")

    v = C["value"]
    def b_value(s, top):
        top += 0.4
        xs = (0.62, 6.95); ys = (top, top + 1.95)
        for i, (head, lines, ac) in enumerate(v["boxes"]):
            x = xs[i % 2]; y = ys[i // 2]
            d.add_box(s, x, y, 5.75, 1.8, head, lines, hcolor=ac, hfs=14, fs=11.5)
        caption(d, s, top + 3.95, v["caption"], color=A2)
    d.content(v["eyebrow"], v["title"], b_value, "")

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
