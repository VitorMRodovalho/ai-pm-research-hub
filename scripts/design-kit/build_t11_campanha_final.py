"""Campanha da Tribo 11 nos DOIS tratamentos finalistas, para decisao com o time.

  v5  escada com fusao  -> assimetria: quem conduz aparece maior e mais alto
  v6  recorte           -> sujeito nitido sobre o fundo da marca, ancorado na base

Os dois saem nos tres formatos que circulam (story, post, linkedin), com a MESMA copy,
a MESMA escala e a MESMA paleta. A unica variavel entre as colunas e o tratamento do
retrato, senao a comparacao nao decide nada.

Tudo que ja foi aprendido e cobrado por guard, e cada regra veio de um defeito real:
  escala        corpo e retrato como FRACAO da menor dimensao, com piso
  contraste     medido no PNG, em janela local, contra a cor real do texto
  cobertura     o guard conta as imagens do HTML, senao "zero falhas" e vacuo
  base          degrade sob a legenda que cai na foto, como lower third de video

Retratos NAO versionados. Gere antes os derivados (3x4, -fade, -cut) e aponte NUCLEO_FOTOS.
"""
from brand import *
from build_t11_campanha import (TITULO_A, TITULO_B, SUB, QUANDO_CURTO, EYEBROW,
                                CSS_PROPOSTA, _fundo, px, DUO)

A, B = DUO[0], DUO[1]
BASE_GRAD = ("linear-gradient(to top, rgba(9,11,32,.99) 40%, rgba(9,11,32,.74) 66%,"
             " rgba(9,11,32,0) 100%)")


SUFIXO = {"v3": "3x4", "v5": "fade", "v6": "cut"}


def _uri(nome, trat):
    return img_uri(FOTOS / f"{nome}-{SUFIXO[trat]}.png")


def _moldura(trat):
    """v3 usa MOLDURA: retrato 3:4 com canto arredondado e uma regua de cor na lateral.
    E a opcao segura, porque nao depende de recorte: qualquer foto de palestrante entra,
    inclusive de fundo bagunçado, que e o limite das outras duas."""
    if trat != "v3":
        return ""
    return f"""
.p1, .p2 {{ overflow:hidden; border-radius:20px; }}
.p1 {{ border-left:6px solid {ORANGE}; }}
.p2 {{ border-left:6px solid {CYAN}; }}
.p1 .foto, .p2 .foto {{ border-radius:0; }}"""


def _cabeca(E, com_sub=False):
    sub = f'<div class="sub">{SUB}</div>' if com_sub else ""
    return f"""<div class="topo">
  <div class="selo">{EYEBROW}</div>
  <div class="premissa">{TITULO_A}</div>
  <div class="virada">{TITULO_B}</div>
  <span class="risco"></span>
  {sub}
  <div class="quando">{QUANDO_CURTO}</div>
  <div class="cta">online e gratuito · inscrição pelo Airmeet</div>
</div>"""


def _css_texto(E, largura_virada=None):
    mw = f"max-width:{largura_virada}px;" if largura_virada else ""
    return f"""
/* o bloco de texto precisa declarar CAMADA. sem isso ele fica no fluxo, as fotos sao
   absolutas e com z-index, e passam por cima: no post a foto cobria o CTA e a DATA.
   um retrato com resto de fundo aparecendo sobre a data e o pior lugar para o defeito. */
.topo {{ position:relative; z-index:6; }}
.selo {{ font-size:{E('micro')}px; }}
.premissa {{ font-size:{E('prem')}px; margin-top:26px; }}
.virada {{ font-size:{E('virada')}px; margin-top:26px; {mw} }}
.risco {{ width:120px; height:9px; margin-top:28px; }}
.sub {{ margin-top:26px; font-size:{E('dest')}px; line-height:1.4; color:{TEXT};
       max-width:900px; }}
.quando {{ margin-top:26px; font-size:{E('dest')}px; font-weight:800; color:{WHITE}; }}
.cta {{ margin-top:10px; font-size:{E('corpo')}px; color:{CYAN}; font-weight:700; }}
.nm {{ font-family:'InterD'; font-weight:900; font-size:{E('dest')}px; color:{WHITE};
      line-height:1.12; letter-spacing:-.02em; }}
.cg {{ font-size:{E('corpo')}px; color:{TEXT_DIM}; margin-top:8px; line-height:1.3; }}
.assina {{ font-size:{E('micro')}px; }}
"""


# ───────────────────────────────────────────────────────────── story 1080x1920
def story(trat):
    W, H = 1080, 1920
    E = lambda p: px("story", p, min(W, H))
    corpo_padrao = f"""<div class="palco">
  <div class="p2"><img class="foto" src="{_uri('rodrigo', trat)}"></div>
  <div class="p1"><img class="foto" src="{_uri('joao', trat)}"></div>
  <div class="base"></div>
  <div class="legendas">
    <div><div class="nm">{A['nome']}</div><div class="cg">{A['cargo']}</div></div>
    <div class="d"><div class="nm">{B['nome']}</div><div class="cg">{B['cargo']}</div></div>
  </div></div>"""
    if trat == "v3":
        palco = f"""
.palco {{ position:relative; height:800px; }}
.p1 {{ position:absolute; left:0; bottom:118px; width:404px; z-index:1; }}
.p2 {{ position:absolute; right:0; bottom:0; width:338px; z-index:1; }}"""
        corpo = corpo_padrao
    elif trat == "v6":
        palco = f"""
.palco {{ position:relative; height:800px; }}
.disco {{ position:absolute; left:50%; bottom:118px; transform:translateX(-50%);
         width:820px; height:820px; border-radius:50%;
         background:radial-gradient(circle at 50% 42%, rgba(62,208,233,.20) 0%,
                    rgba(62,208,233,.07) 46%, rgba(62,208,233,0) 68%); }}
.anel {{ position:absolute; left:50%; bottom:148px; transform:translateX(-50%);
        width:700px; height:700px; border-radius:50%;
        border:2px solid rgba(160,205,240,.16); }}
.p1 {{ position:absolute; left:-58px; bottom:0; width:624px; z-index:1; }}
.p2 {{ position:absolute; right:-46px; bottom:0; width:544px; z-index:0; }}"""
        corpo = f"""<div class="palco">
  <div class="disco"></div><div class="anel"></div>
  <div class="p2"><img class="foto" src="{_uri('rodrigo', trat)}"></div>
  <div class="p1"><img class="foto" src="{_uri('joao', trat)}"></div>
  <div class="base"></div>
  <div class="legendas">
    <div><div class="nm">{A['nome']}</div><div class="cg">{A['cargo']}</div></div>
    <div class="d"><div class="nm">{B['nome']}</div><div class="cg">{B['cargo']}</div></div>
  </div></div>"""
    else:
        palco = f"""
.palco {{ position:relative; height:800px; }}
.p1 {{ position:absolute; left:-40px; bottom:96px; width:524px; z-index:1; }}
.p2 {{ position:absolute; right:-24px; bottom:0; width:376px; z-index:0; }}"""
        corpo = f"""<div class="palco">
  <div class="p2"><img class="foto" src="{_uri('rodrigo', trat)}"></div>
  <div class="p1"><img class="foto" src="{_uri('joao', trat)}"></div>
  <div class="base"></div>
  <div class="legendas">
    <div><div class="nm">{A['nome']}</div><div class="cg">{A['cargo']}</div></div>
    <div class="d"><div class="nm">{B['nome']}</div><div class="cg">{B['cargo']}</div></div>
  </div></div>"""
    html = f"""<!doctype html><meta charset="utf-8"><style>{CSS_PROPOSTA}{_fundo(W,H)}
body {{ display:flex; flex-direction:column; justify-content:space-between;
       padding:92px 80px 58px; }}
{_css_texto(E)}{palco}
.foto {{ width:100%; display:block; }}{_moldura(trat)}
.base {{ position:absolute; left:-80px; right:-80px; bottom:-58px; height:326px; z-index:2;
        background:{BASE_GRAD}; }}
.legendas {{ position:absolute; left:0; right:0; bottom:-4px; z-index:3;
            display:flex; justify-content:space-between; align-items:flex-end; gap:20px; }}
.legendas > div {{ max-width:46%; }}
.legendas .d {{ text-align:right; }}
.rod {{ position:relative; z-index:4; }}
</style>{_cabeca(E)}{corpo}
<div class="rod assina">Realização <b>Núcleo IA &amp; GP</b> · Tribo PMO Inteligente</div>"""
    return render(f"t11-{trat}-story-1080x1920", html, W, H)


# ───────────────────────────────────────────────────────────── post 1080x1350
def post(trat):
    W, H = 1080, 1350
    E = lambda p: px("post", p, min(W, H))
    # a foto tem altura = largura x 4/3. no palco de 600 isso limita a largura, senao ela
    # sobe por cima do bloco de texto e cobre a DATA. camada resolve quem pinta na frente,
    # nao resolve o retrato ocupando o lugar do texto: a correcao e geometrica.
    if trat == "v3":
        dupla = f"""
.p1 {{ position:absolute; left:0; bottom:74px; width:352px; z-index:1; }}
.p2 {{ position:absolute; right:0; bottom:0; width:296px; z-index:1; }}"""
    elif trat == "v6":
        dupla = f"""
.p1 {{ position:absolute; left:-52px; bottom:0; width:444px; z-index:1; }}
.p2 {{ position:absolute; right:-40px; bottom:0; width:392px; z-index:0; }}"""
    else:
        dupla = f"""
.p1 {{ position:absolute; left:-34px; bottom:58px; width:398px; z-index:1; }}
.p2 {{ position:absolute; right:-20px; bottom:0; width:300px; z-index:0; }}"""
    html = f"""<!doctype html><meta charset="utf-8"><style>{CSS_PROPOSTA}{_fundo(W,H)}
body {{ display:flex; flex-direction:column; justify-content:space-between;
       padding:66px 74px 32px; }}
{_css_texto(E, largura_virada=940)}
.palco {{ position:relative; height:600px; }}{dupla}
.foto {{ width:100%; display:block; }}{_moldura(trat)}
.base {{ position:absolute; left:-74px; right:-74px; bottom:-46px; height:280px; z-index:2;
        background:{BASE_GRAD}; }}
.legendas {{ position:absolute; left:0; right:0; bottom:-2px; z-index:3;
            display:flex; justify-content:space-between; align-items:flex-end; gap:18px; }}
.legendas > div {{ max-width:46%; }}
.legendas .d {{ text-align:right; }}
.rod {{ position:relative; z-index:4; display:flex; justify-content:space-between; gap:26px; }}
</style>{_cabeca(E, com_sub=True)}
<div class="palco">
  <div class="p2"><img class="foto" src="{_uri('rodrigo', trat)}"></div>
  <div class="p1"><img class="foto" src="{_uri('joao', trat)}"></div>
  <div class="base"></div>
  <div class="legendas">
    <div><div class="nm">{A['nome']}</div><div class="cg">{A['cargo']}</div></div>
    <div class="d"><div class="nm">{B['nome']}</div><div class="cg">{B['cargo']}</div></div>
  </div></div>
<div class="rod"><span class="assina">Realização <b>Núcleo IA &amp; GP</b> · Tribo PMO Inteligente</span></div>"""
    return render(f"t11-{trat}-post-1080x1350", html, W, H)


# ───────────────────────────────────────────────────────────── linkedin 1200x627
def linkedin(trat):
    W, H = 1200, 627
    E = lambda p: px("linkedin", p, min(W, H))
    # ATENCAO: string NORMAL, nao f-string. Chave dupla aqui vira chave dupla LITERAL no
    # CSS, o navegador descarta a regra em silencio e as duas fotos empilham. Foi o que
    # aconteceu, e o guard so passou a pegar depois de proibir "{{" no HTML final.
    # 1200x627 e BAIXO: o retrato 3:4 nao cabe inteiro e precisa sangrar. O corte tem de
    # cair no TORSO, nunca no queixo, e o rosto precisa ficar dentro da metade superior,
    # que e a parte que sobrevive ao recorte do LinkedIn em alguns clientes.
    # os dois sobem: no ajuste anterior o corte passava rente ao queixo do Rodrigo, que
    # e o pior lugar para cortar um retrato. agora o corte cai no torso nos dois.
    if trat == "v3":
        dupla = """
.p1 { position:absolute; right:196px; bottom:34px; width:236px; z-index:2; }
.p2 { position:absolute; right:22px; bottom:14px; width:198px; z-index:1; }"""
    elif trat == "v6":
        dupla = """
.p1 { position:absolute; right:186px; bottom:-96px; width:376px; z-index:2; }
.p2 { position:absolute; right:-22px; bottom:-104px; width:330px; z-index:1; }"""
    else:
        dupla = """
.p1 { position:absolute; right:150px; bottom:-40px; width:330px; z-index:2; }
.p2 { position:absolute; right:-24px; bottom:-58px; width:280px; z-index:1; }"""
    html = f"""<!doctype html><meta charset="utf-8"><style>{CSS_PROPOSTA}{_fundo(W,H)}
{_css_texto(E)}
.topo {{ position:absolute; left:56px; top:48px; width:640px; z-index:3; }}
.premissa {{ margin-top:16px; }} .virada {{ margin-top:14px; }}
.risco {{ width:84px; height:7px; margin-top:20px; }}
.quando {{ margin-top:20px; }}
.dir {{ position:absolute; right:0; top:0; bottom:0; width:520px; }}
.foto {{ width:100%; display:block; }}{_moldura(trat)}{dupla}
.veu {{ position:absolute; right:0; top:0; bottom:0; width:230px; z-index:0;
       background:linear-gradient(to right, rgba(13,16,48,.92), rgba(13,16,48,0)); }}
/* a peca e baixa e os dois sangram na base; sem isso o recorte termina num corte reto
   contra a borda inferior, que denuncia a montagem */
.pe {{ position:absolute; left:0; right:0; bottom:0; height:120px; z-index:3;
      background:linear-gradient(to top, rgba(13,16,48,.98) 24%, rgba(13,16,48,0) 100%); }}
.legendas {{ position:absolute; right:24px; bottom:16px; z-index:3; text-align:right; }}
.legendas .cg {{ margin-top:4px; }}
.legendas .par2 {{ margin-top:12px; }}
.rod {{ position:absolute; left:56px; bottom:26px; z-index:3; }}
</style>
<div class="dir">
  <div class="p2"><img class="foto" src="{_uri('rodrigo', trat)}"></div>
  <div class="p1"><img class="foto" src="{_uri('joao', trat)}"></div>
</div>
<span class="veu"></span><span class="pe"></span>
{_cabeca(E)}
<div class="rod assina">Realização <b>Núcleo IA &amp; GP</b> · Tribo PMO Inteligente</div>"""
    return render(f"t11-{trat}-linkedin-1200x627", html, W, H)


PECAS = [(t, f) for t in ("v3", "v5", "v6") for f in (story, post, linkedin)]

if __name__ == "__main__":
    from PIL import Image
    for trat, fn in PECAS:
        p = fn(trat); print("ok", p.name, Image.open(p).size)
