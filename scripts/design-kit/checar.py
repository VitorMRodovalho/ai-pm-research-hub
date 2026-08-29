"""Roda as dez checagens sobre as pecas geradas.

Use DEPOIS de alterar qualquer coisa. Cada checagem aqui nasceu de um defeito que passou
despercebido e so apareceu quando alguem olhou a peca pronta; a ideia e que o proximo
defeito da mesma familia seja pego pela maquina, nao pelo olho.

    python3 checar.py
"""
import re, sys
import build_t11_campanha_final as C
import build_t11_campanha as K
from qa_measure import rects, overlaps
from _qa_contraste import ilegiveis

TOPO = {"quando", "cta", "virada", "premissa", "selo", "sub"}

capt = {}
_orig = C.render
C.render = lambda n, h, w, ht: (capt.__setitem__(n, (h, w, ht)), _orig(n, h, w, ht))[1]

# As pecas de REPLAY e de DIA DO EVENTO ficavam FORA do conjunto checado: o guard olhava
# so `PECAS`. Isso e o mesmo vacuo que a checagem 2 pega dentro de uma peca, um nivel acima:
# passar verde porque nao esta olhando. Com a direcao escolhida elas entram.
#   python3 checar.py --extra v7
alvos = list(C.PECAS)
if "--extra" in sys.argv:
    _t = sys.argv[sys.argv.index("--extra") + 1]
    assert _t in ("v3", "v5", "v6", "v7"), f"direcao invalida: {_t}"
    alvos += [(_t, fn) for fn in C.EXTRA]

saidas = {}
for trat, fn in alvos:
    p = fn(trat)
    saidas[p.stem] = (p, trat)

total = 0
for nome, (png, trat) in saidas.items():
    html, w, h = capt[nome]
    rs = rects(html, w, h)
    menor = min(w, h)
    falhas = set()

    # 1. f-string esquecida deixa a chave literal e o Chrome DESCARTA a regra em silencio
    if "{{" in html or "}}" in html:
        falhas.add("CSS com chave literal: alguma f-string perdeu o prefixo f")

    # 2. cobertura: o probe ignora elemento sem class, e ai "zero falhas" e vacuo
    no_html = len(re.findall(r"<img\b", html))
    fotos = [r for r in rs if r["tag"] == "img"]
    if len(fotos) != no_html:
        falhas.add(f"o guard so viu {len(fotos)} das {no_html} imagens: de class a todas")

    # 3. foto sobre o bloco de texto do topo
    for a in [r for r in rs if r.get("ink") and r["cls"].strip() in TOPO]:
        for ft in fotos:
            if overlaps(ft, a["ink"]):
                falhas.add(f"foto por cima de {a['cls'].strip()!r}")

    # 4. os dois palestrantes dentro do canvas  5. retrato grande o bastante
    for i, r in enumerate(fotos):
        vx = max(0, min(w, r["x"] + r["w"]) - max(0, r["x"]))
        vy = max(0, min(h, r["y"] + r["h"]) - max(0, r["y"]))
        if vx * vy / max(1, r["w"] * r["h"]) < .45:
            falhas.add(f"palestrante {i} quase fora do canvas")
        if r["w"] / menor < .17:
            falhas.add(f"retrato pequeno demais: {r['w']/menor*100:.1f}% (piso 17%)")

    # 10. retrato sobre retrato. Nasceu do v7: os dois medalhoes do story se sobrepunham
    # em 8px, e com o anel laranja de 9px de cada lado a colisao virava 26px visiveis. A
    # peca passava verde porque havia checagem de foto sobre TEXTO e de foto FORA do
    # canvas, e nenhuma de foto contra foto. O piso e uma folga real entre as caixas.
    FOLGA_MIN = 24
    for i2 in range(len(fotos)):
        for j in range(i2 + 1, len(fotos)):
            X, Y = fotos[i2], fotos[j]
            gx = max(X["x"], Y["x"]) - min(X["x"] + X["w"], Y["x"] + Y["w"])
            gy = max(X["y"], Y["y"]) - min(X["y"] + X["h"], Y["y"] + Y["h"])
            # so cobra folga de quem se cruza no outro eixo, e SO no medalhao: retrato em
            # escada encosta de proposito, e a v5 e a v6 dependem disso.
            # O gate vem do CATALOGO (`trat`), nao de string no html. Duas tentativas
            # erradas, medidas em 29/08/2026: procurar "circ" no html devolve sempre False
            # (o retrato entra como data URI, entao a checagem fica VAZIA, nao vermelha), e
            # procurar "border-radius:50%" acusa TODA peca, porque e tambem o pontinho do
            # selo. So o tratamento diz se o retrato e um medalhao.
            if gx < FOLGA_MIN and gy < FOLGA_MIN and trat == "v7":
                falhas.add(f"retratos colados: folga de {max(gx, gy):.0f}px (piso {FOLGA_MIN})")

    # 6. contraste real do texto, medido no PNG
    for t, cr, piso, onde in ilegiveis(png, html, w, h):
        falhas.add(f"texto ilegivel {t[:26]!r}: contraste {cr}, piso {piso}")

    txt = [r for r in rs if r.get("ink") and r["ink"]["w"] and r["txt"].strip()]
    # 7. transbordo  8. texto sobre texto
    for r in txt:
        i = r["ink"]
        if i["x"] < -1 or i["y"] < -1 or i["x"] + i["w"] > w + 1 or i["y"] + i["h"] > h + 1:
            falhas.add(f"texto fora da peca: {r['txt'][:24]!r}")
    for i2 in range(len(txt)):
        for j in range(i2 + 1, len(txt)):
            X, Y = txt[i2], txt[j]
            if X["cls"] == Y["cls"] and X["txt"] == Y["txt"]:
                continue
            if overlaps(X["ink"], Y["ink"]):
                falhas.add(f"texto sobre texto: {X['txt'][:18]!r}")

    # 9. piso de legibilidade do menor corpo
    from _qa_contraste import blocos_de_texto
    menores = [b for b in blocos_de_texto(html, w, h) if b["h"] > 0]
    if menores:
        mn = min(menores, key=lambda b: b["h"])
        # o corpo real e aproximado pela altura da caixa de uma linha
        if mn["h"] / menor < K.PISO_TEXTO * .85:
            falhas.add(f"corpo abaixo do piso: {mn['txt'][:20]!r}")

    total += len(falhas)
    marca = "\033[32mok\033[0m " if not falhas else "\033[31mFALHA\033[0m"
    print(f"{marca} {nome}")
    for f in sorted(falhas):
        print(f"        - {f}")

print()
if total:
    print(f"\033[31m{total} problema(s).\033[0m\n")
    sys.exit(1)
print("\033[32mAs dez checagens passaram em todas as pecas.\033[0m\n")
