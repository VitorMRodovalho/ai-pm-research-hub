"""Contraste REAL do texto contra o que ficou embaixo dele, medido no PNG renderizado.

Duas armadilhas ja pagas neste arquivo:

1. Checagem GEOMETRICA ("imagem sobre texto") e a pergunta errada em peca com camadas: la
   o texto fica sobre a foto de proposito. A pergunta util e se DA PARA LER.
2. Percentil na caixa INTEIRA mascara o defeito. A caixa de "Lider da Tribo PMO" cobre
   terno escuro e camisa clara ao mesmo tempo; o terno puxava o percentil do fundo para
   baixo e o contraste saia alto enquanto metade da frase estava ilegivel. Injecao de
   defeito passou verde, que foi como isso apareceu.

Por isso: JANELA LOCAL, e o fundo e medido descontando os pixels da propria letra, cuja
cor vem do CSS e nao de chute.
"""
import re, json, subprocess, tempfile, pathlib
import numpy as np
from PIL import Image

PROBE = """
<script>window.addEventListener('load',function(){var o=[];
document.querySelectorAll('*').forEach(function(e){
 if(e.children.length||!(e.textContent||'').trim())return;
 var g=document.createRange();g.selectNodeContents(e);var b=g.getBoundingClientRect();
 if(!b.width||!b.height)return;
 o.push({x:Math.round(b.left),y:Math.round(b.top),w:Math.round(b.width),
  h:Math.round(b.height),cor:getComputedStyle(e).color,
  txt:(e.textContent||'').trim().slice(0,40)});});
var p=document.createElement('pre');p.id='QC';p.textContent=JSON.stringify(o);
document.body.appendChild(p);});</script>"""


def blocos_de_texto(html, w, h):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(html + PROBE); src = pathlib.Path(f.name)
    try:
        p = subprocess.run(["google-chrome-stable", "--headless", "--disable-gpu",
            "--no-sandbox", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--window-size={w},{h}", "--virtual-time-budget=4000", "--dump-dom",
            f"file://{src}"], capture_output=True, text=True)
    finally:
        src.unlink()
    m = re.search(r'<pre id="QC">(.*?)</pre>', p.stdout, re.S)
    raw = m.group(1).replace("&quot;", '"').replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return json.loads(raw)


def _lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= .03928, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def _L(rgb):
    c = _lin(rgb)
    return .2126 * c[..., 0] + .7152 * c[..., 1] + .0722 * c[..., 2]


def _cr(a, b):
    a, b = _L(a), _L(b)
    return (np.maximum(a, b) + .05) / (np.minimum(a, b) + .05)


def ilegiveis(png, html, w, h, piso_grande=3.0, piso_normal=4.5, corpo_grande=24, jan=26):
    im = np.asarray(Image.open(png).convert("RGB")).astype(float)
    fora = []
    for b in blocos_de_texto(html, w, h):
        cor = np.array([int(v) for v in re.findall(r"\d+", b["cor"])[:3]], float)
        piso = piso_grande if b["h"] >= corpo_grande else piso_normal
        pior, ondej = 1e9, None
        for yy in range(b["y"], b["y"] + b["h"], jan):
            for xx in range(b["x"], b["x"] + b["w"], jan):
                reg = im[max(0, yy):yy + jan, max(0, xx):xx + jan]
                if reg.size < 3 * jan:
                    continue
                px = reg.reshape(-1, 3)
                # descarta o que e a propria letra; o resto e fundo local
                dist = np.sqrt(((px - cor) ** 2).sum(axis=1))
                fundo = px[dist > 60]
                # a janela precisa ser REPRESENTATIVA: se quase tudo e letra, o pouco que
                # sobra e anti-aliasing e o contraste sai falsamente baixo (foi assim que
                # o titulo, branco sobre navy, apareceu com 1,49). Se quase nada e letra,
                # a janela caiu num vao entre palavras e nao mede nada.
                frac = len(fundo) / len(px)
                if frac < .25 or frac > .92 or len(fundo) < 40:
                    continue
                c = _cr(cor, np.median(fundo, axis=0))
                if c < pior:
                    pior, ondej = c, (xx, yy)
        if ondej and pior < piso:
            fora.append((b["txt"], round(float(pior), 2), piso, ondej))
    return fora
