"""Pacote A (divulgacao): 1o Webinar da Tribo 6, 04/08/2026. VERSAO OFICIAL.

Promovida da v2 em 2026-07-26 com aval do owner: retratos maiores (post 186->268 px,
story 200->270, linkedin 150->196, mediador 92->132) reequilibrando padding e gaps.
A esfera ciano do story foi para a faixa livre entre o subtitulo e o 1o palestrante,
porque com o retrato maior a coluna de texto avanca ate x~970 e ela colidia com o nome.
Geometria provada por qa_measure.py: 0 colisoes, folga pill->rodape de 37 px.
A v1 (retratos menores) esta em build_t6_divulgacao_v1_ARQUIVADO.py.
"""
from brand import *

TITULO = "Aplicações Práticas de IA"
SUB = "IA na priorização, na análise de cenário e na segurança da informação"
QUANDO = "4 de agosto · 19h às 20h30 (Brasília)"
CTA_LINK = None          # <- colar aqui a URL da sala do Airmeet
CTA_TXT = "Online e gratuito · via Airmeet" if not CTA_LINK else CTA_LINK
ASSIN = ('Núcleo IA &amp; GP<br><span class="mini">iniciativa dos capítulos do PMI no '
         'Brasil, sediada no PMI-GO</span>')

FER = img_uri(FOTOS / "fernando-900.png")
CLE = img_uri(FOTOS / "clendson-900.png")
DEN = img_uri(FOTOS / "denis-400.png")

PALESTRANTES = [
    dict(key="fernando", foto=FER, nome="Fernando Carvalho",
         cargo="Diretor de Operações",
         papel="Convidado do 1º Webinar da tribo ROI &amp; Portfólio",
         bloco="Análise de cenário e gestão de portfólio com IA",
         hora="19h10 · 25 min"),
    dict(key="clendson", foto=CLE, nome="Clendson Gonçalves, MSc.",
         cargo="Arquiteto de Cibersegurança, Dados e IA | Professor Universitário",
         papel="Convidado do 1º Webinar da tribo ROI &amp; Portfólio",
         bloco="Segurança da informação no uso de IA",
         hora="19h45 · 25 min"),
]
MEDIADOR = dict(foto=DEN, nome="Denis Vasconcelos", cargo="Tribo ROI &amp; Portfólio",
                bloco="Mediação, abertura e fechamento", hora="19h00")


# ---------------------------------------------------------------- card 1200x1500
def card(p):
    W, H = 1200, 1500
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ display:flex; flex-direction:column; align-items:center; padding:0 84px; text-align:center; }}
.eyebrow {{ justify-content:center; margin-top:44px; font-size:21px; }}
.pill {{ margin-top:26px; padding:13px 30px; font-size:19px; }}
.nome {{ font-family:'InterD'; font-weight:900; font-size:82px; color:{WHITE};
        line-height:1; letter-spacing:-.03em; margin-top:40px; }}
.cargo {{ margin-top:18px; font-size:28px; font-weight:600; color:{CYAN}; }}
.papel {{ margin-top:9px; font-size:22px; color:{TEXT_DIM}; }}
.bloco {{ margin-top:34px; font-size:32px; line-height:1.34; color:{WHITE};
         font-weight:700; max-width:940px; }}
.rodape {{ padding:30px 84px 46px; font-size:22px; text-align:left; }}
.rodape .dir {{ text-align:right; }}
.mini {{ font-size:16px; color:{TEXT_DIM}; font-weight:400; }}
.orb-a {{ width:1500px; height:1500px; right:-680px; top:520px; }}
</style>
<div class="orb orb-a"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="eyebrow">1º Webinar · Tribo ROI &amp; Portfólio</div>
  <div class="pill">{p['hora']}</div>
  <div style="margin-top:44px">{retrato(p['foto'], 470)}</div>
  <div class="nome">{p['nome']}</div>
  <div class="cargo">{p['cargo']}</div>
  <div class="papel">{p['papel']}</div>
  <div class="bloco">{p['bloco']}</div>
</div>
<div class="rodape">
  <div>{QUANDO}<br><span class="mini">{CTA_TXT}</span></div>
  <div class="dir">{ASSIN}</div>
</div>"""
    return render(f"t6-card-{p['key']}", html, W, H)


def _pessoa(p, size, com_bloco=True):
    bloco = f'<div class="pp">{p["bloco"]}</div>' if com_bloco else ""
    return f"""<div class="pessoa">{retrato(p['foto'], size)}
      <div class="pn">{p['nome']}</div><div class="ptr">{p['cargo']}</div>
      <div class="pt">{p['hora']}</div>{bloco}</div>"""


# ---------------------------------------------------------------- post 1080x1350
def post():
    W, H = 1080, 1350
    cols = "".join(_pessoa(p, 268) for p in PALESTRANTES)
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:26px 72px 104px; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:19px; }}
h1 {{ font-size:68px; margin-top:12px; }}
.sub {{ margin-top:14px; font-size:25px; line-height:1.4; color:{TEXT}; max-width:880px; }}
.duo {{ display:flex; gap:40px; margin-top:10px; justify-content:center; }}
.pessoa {{ flex:1; display:flex; flex-direction:column; align-items:center;
          text-align:center; max-width:400px; }}
.pn {{ font-family:'InterD'; font-weight:900; font-size:36px; color:{WHITE};
      margin-top:14px; letter-spacing:-.02em; text-wrap:balance; }}
.ptr {{ font-size:18px; color:{TEXT_DIM}; margin-top:6px; }}
.pt {{ font-size:20px; color:{CYAN}; font-weight:700; margin-top:6px; }}
.pp {{ font-size:17px; line-height:1.35; color:{TEXT}; margin-top:9px; }}
.med {{ display:flex; align-items:center; gap:22px; margin-top:22px; padding-top:22px;
       border-top:1px solid rgba(160,205,240,.18); }}
.med .mn {{ font-family:'InterD'; font-weight:900; font-size:28px; color:{WHITE}; }}
.med .mc {{ font-size:19px; color:{TEXT_DIM}; margin-top:4px; }}
.quando {{ display:inline-flex; margin-top:16px; padding:14px 30px; font-size:21px; }}
.rodape {{ padding:22px 72px 34px; font-size:19px; gap:40px; }}
.rodape > div {{ max-width:56%; }}
.rodape .dir {{ text-align:right; }}
.mini {{ font-size:15px; color:{TEXT_DIM}; }}
.orb-a {{ width:1250px; height:1250px; right:-560px; top:340px; }}
.dot {{ width:70px; height:70px; right:92px; top:392px; }}
</style>
<div class="orb orb-a"></div><div class="dot-cyan dot"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="eyebrow">1º Webinar · Tribo ROI &amp; Portfólio</div>
  <h1>{TITULO}</h1>
  <div class="sub">{SUB}</div>
  <div class="duo">{cols}</div>
  <div class="med">{retrato(MEDIADOR['foto'], 132)}
    <div><div class="mn">{MEDIADOR['nome']}</div>
    <div class="mc">{MEDIADOR['bloco']} · {MEDIADOR['cargo']}</div></div>
  </div>
  <div><span class="pill quando">{QUANDO}</span></div>
</div>
<div class="rodape">
  <div>{CTA_TXT}<br><span class="mini">Público interno PMI e externo · com gravação</span></div>
  <div class="dir">{ASSIN}</div>
</div>"""
    return render("t6-post-1080x1350", html, W, H)


# ---------------------------------------------------------------- story 1080x1920
def story():
    W, H = 1080, 1920
    linhas = "".join(f"""<div class="linha">{retrato(p['foto'], 270)}
      <div class="txt"><div class="pn">{p['nome']}</div>
      <div class="ptr">{p['cargo']}</div><div class="pt">{p['hora']}</div>
      <div class="pp">{p['bloco']}</div></div></div>""" for p in PALESTRANTES)
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:52px 76px 0; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:21px; }}
h1 {{ font-size:92px; margin-top:24px; }}
.sub {{ margin-top:22px; font-size:30px; line-height:1.42; color:{TEXT}; }}
.linha {{ display:flex; align-items:center; gap:36px; margin-top:30px; }}
.txt {{ flex:1; }}
.pn {{ font-family:'InterD'; font-weight:900; font-size:46px; color:{WHITE}; letter-spacing:-.02em; text-wrap:balance; }}
.ptr {{ font-size:21px; color:{TEXT_DIM}; margin-top:6px; }}
.pt {{ font-size:22px; color:{CYAN}; font-weight:700; margin-top:6px; }}
.pp {{ font-size:22px; line-height:1.38; color:{TEXT}; margin-top:10px; }}
.med {{ display:flex; align-items:center; gap:26px; margin-top:30px; padding-top:28px;
       border-top:1px solid rgba(160,205,240,.18); }}
.med .mn {{ font-family:'InterD'; font-weight:900; font-size:34px; color:{WHITE}; }}
.med .mc {{ font-size:21px; color:{TEXT_DIM}; margin-top:5px; }}
.quando {{ display:inline-flex; margin-top:34px; padding:18px 36px; font-size:26px; }}
.rodape {{ padding:34px 76px 60px; font-size:23px; flex-direction:column;
          align-items:stretch; gap:18px; }}
.rodape .dir {{ text-align:left; }}
.mini {{ font-size:18px; color:{TEXT_DIM}; }}
.orb-a {{ width:1500px; height:1500px; right:-660px; top:820px; }}
/* a esfera acompanha o retrato: com foto de 270px a coluna de texto avanca ate
   x~970, entao a esfera saiu da altura do nome e foi para a faixa livre entre o
   subtitulo e o primeiro palestrante (mesmo lugar logico que ela ocupa no post). */
.dot {{ width:88px; height:88px; right:96px; top:524px; }}
</style>
<div class="orb orb-a"></div><div class="dot-cyan dot"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="eyebrow">1º Webinar · Tribo ROI &amp; Portfólio</div>
  <h1>{TITULO}</h1>
  <div class="sub">{SUB}</div>
  {linhas}
  <div class="med">{retrato(MEDIADOR['foto'], 104)}
    <div><div class="mn">{MEDIADOR['nome']}</div>
    <div class="mc">{MEDIADOR['bloco']}</div></div>
  </div>
  <div><span class="pill quando">{QUANDO}</span></div>
</div>
<div class="rodape">
  <div>{CTA_TXT}<br><span class="mini">Público interno PMI e externo · com gravação</span></div>
  <div class="dir">{ASSIN}</div>
</div>"""
    return render("t6-story-1080x1920", html, W, H)


# ---------------------------------------------------------------- linkedin 1200x627
def linkedin():
    W, H = 1200, 627
    duo = "".join(f"""<div class="pessoa">{retrato(p['foto'], 196)}
      <div class="pn">{p['nome']}</div><div class="pt">{p['hora'].split(' · ')[0]}</div>
      </div>""" for p in PALESTRANTES)
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:16px 62px 66px; display:flex; gap:40px; align-items:center; }}
.col {{ flex:1; }}
.eyebrow {{ font-size:16px; }}
h1 {{ font-size:54px; margin-top:14px; }}
.sub {{ margin-top:16px; font-size:20px; line-height:1.4; color:{TEXT}; }}
.quando {{ display:inline-flex; margin-top:20px; padding:12px 24px; font-size:17px; }}
.duo {{ display:flex; gap:30px; }}
.pessoa {{ text-align:center; }}
.pn {{ font-family:'InterD'; font-weight:900; font-size:23px; color:{WHITE};
      margin-top:12px; letter-spacing:-.02em; }}
.pt {{ font-size:16px; color:{CYAN}; font-weight:700; margin-top:5px; }}
.rodape {{ padding:14px 62px 22px; font-size:15px; gap:34px; }}
.rodape > div {{ max-width:54%; }}
.rodape .dir {{ text-align:right; }}
.mini {{ font-size:13px; color:{TEXT_DIM}; }}
.orb-a {{ width:900px; height:900px; right:-330px; top:140px; }}
</style>
<div class="orb orb-a"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="col">
    <div class="eyebrow">1º Webinar · Tribo ROI &amp; Portfólio</div>
    <h1>{TITULO}</h1>
    <div class="sub">{SUB}</div>
    <div><span class="pill quando">{QUANDO}</span></div>
  </div>
  <div class="duo">{duo}</div>
</div>
<div class="rodape">
  <div>{CTA_TXT}<br><span class="mini">Mediação: {MEDIADOR['nome']}</span></div>
  <div class="dir">{ASSIN}</div>
</div>"""
    return render("t6-linkedin-1200x627", html, W, H)


if __name__ == "__main__":
    for p in PALESTRANTES:
        print("ok", card(p))
    for f in (post, story, linkedin):
        print("ok", f())
