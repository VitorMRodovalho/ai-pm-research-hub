"""Pacote A (parcial): ambientes Airmeet do 1o Webinar da Tribo 6, 04/08/2026.

Nao dependem da URL da sala nem do sobrenome do Fernando: por isso a programacao aparece
por horario e TEMA, sem nomes incompletos. Os cards de palestrante vem depois.

Formatos espelham o kit real (pasta "3 - Ambiente Airmeet" do kit-midia):
  banner 1440x810 · recepcao 1440x720 · backdrop de palco 1920x1080 · boas-vindas 1280x720
"""
from brand import *

FER = img_uri(FOTOS / "fernando-900.png")
CLE = img_uri(FOTOS / "clendson-900.png")
DEN = img_uri(FOTOS / "denis-400.png")
TIME = [(DEN, "Denis Vasconcelos", "Mediação"),
        (FER, "Fernando Carvalho", "Análise de cenário e portfólio"),
        (CLE, "Clendson Gonçalves, MSc.", "Segurança da informação")]


def faixa_time(size, com_cargo=True):
    return "".join(f'<div class="qi">{retrato(f, size)}<div class="qn">{n}</div>'
                   + (f'<div class="qc">{c}</div>' if com_cargo else '') + '</div>'
                   for f, n, c in TIME)

TITULO = "Aplicações Práticas de IA"
SUB = "IA na priorização, na análise de cenário e na segurança da informação"
QUANDO = "4 de agosto · 19h às 20h30 (Brasília)"
ASSIN = 'Realização <b>Núcleo IA &amp; GP</b> · Tribo ROI &amp; Portfólio'

GRADE = [
    ("19h00", "Abertura"),
    ("19h05", "Apresentação da Tribo 6"),
    ("19h10", "Análise de cenário e gestão de portfólio"),
    ("19h35", "Perguntas"),
    ("19h45", "Segurança da informação no uso de IA"),
    ("20h10", "Perguntas e discussão"),
    ("20h25", "Fechamento"),
]


def head(eyebrow, titulo, sub=None, extra=""):
    s = f'<div class="eyebrow">{eyebrow}</div><h1>{titulo}</h1>'
    if sub:
        s += f'<div class="sub">{sub}</div>'
    return s + extra


# ---------------------------------------------------------------- banner 1440x810
def banner():
    W, H = 1440, 810
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:52px 84px 130px; display:flex; flex-direction:column; justify-content:center; }}
.eyebrow {{ font-size:20px; }}
h1 {{ font-size:88px; margin-top:22px; max-width:1250px; }}
.sub {{ margin-top:24px; font-size:31px; line-height:1.4; color:{TEXT}; max-width:930px; }}
.quando {{ display:inline-flex; margin-top:34px; padding:16px 34px; font-size:24px; }}
.rodape {{ padding:22px 84px 34px; font-size:20px; }}
.orb-a {{ width:1150px; height:1150px; right:-430px; top:130px; }}
.dot {{ width:86px; height:86px; right:130px; top:560px; }}
</style>
<div class="orb orb-a"></div><div class="dot-cyan dot"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  {head("1º Webinar · Tribo ROI &amp; Portfólio", TITULO, SUB)}
  <div><span class="pill quando">{QUANDO}</span></div>
</div>
<div class="rodape"><div>{ASSIN}</div><div>Airmeet · aberto ao público</div></div>"""
    return render("t6-airmeet-01-banner-1440x810", html, W, H)


# ---------------------------------------------------------------- recepcao 1440x720
def recepcao():
    W, H = 1440, 720
    itens = "".join(f'<div class="li"><span class="hh">{h}</span>'
                    f'<span class="tt">{t}</span></div>' for h, t in GRADE)
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:30px 84px 92px; display:flex; gap:54px; }}
.col {{ flex:1; }}
.eyebrow {{ font-size:18px; }}
h1 {{ font-size:50px; margin-top:14px; }}
.sub {{ margin-top:14px; font-size:20px; line-height:1.35; color:{TEXT}; }}
.quando {{ display:inline-flex; margin-top:18px; padding:11px 22px; font-size:17px; }}
.grade {{ flex:1; padding-top:16px; }}
.gt {{ font-size:15px; font-weight:700; letter-spacing:.22em; text-transform:uppercase;
      color:{CYAN_SOFT}; margin-bottom:16px; }}
.li {{ display:flex; gap:18px; padding:7px 0; border-bottom:1px solid rgba(160,205,240,.12); }}
.hh {{ font-weight:800; color:{CYAN}; font-size:18px; width:66px; flex:none; }}
.tt {{ font-size:18px; color:{TEXT}; }}
.rodape {{ padding:20px 84px 30px; font-size:18px; }}
.time {{ display:flex; gap:14px; margin-top:20px; }}
.qi {{ text-align:center; width:178px; }}
.qn {{ font-weight:800; font-size:15px; color:{WHITE}; margin-top:8px; white-space:nowrap; }}
.orb-a {{ width:900px; height:900px; left:-380px; top:180px; }}
</style>
<div class="orb orb-a"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="col">
    {head("Seja bem-vindo", TITULO, SUB)}
    <div><span class="pill quando">{QUANDO}</span></div>
    <div class="time">{faixa_time(66, com_cargo=False)}</div>
  </div>
  <div class="grade"><div class="gt">Programação</div>{itens}</div>
</div>
<div class="rodape"><div>{ASSIN}</div><div>Começamos às 19h em ponto</div></div>"""
    return render("t6-airmeet-02-recepcao-1440x720", html, W, H)


# ---------------------------------------------------------------- backdrop de palco 1920x1080
def backdrop():
    """Canvas reutilizavel durante todo o evento: centro VAZIO para as cameras,
    identidade so no topo e no rodape (mesma logica do backdrop do kit)."""
    W, H = 1920, 1080
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.barra {{ position:absolute; left:0; right:0; top:var(--fh); padding:16px 64px;
         display:flex; align-items:baseline; gap:26px; }}
.bt {{ font-family:'InterD'; font-weight:900; font-size:34px; color:{WHITE}; letter-spacing:-.02em; }}
.bq {{ font-size:22px; font-weight:700; color:{CYAN}; }}
.rodape {{ padding:20px 64px 30px; font-size:21px; border-top:none; }}
.rodape .dir {{ text-align:right; }}
.orb-a {{ width:1500px; height:1500px; right:-620px; top:200px; }}
.orb-b {{ width:1150px; height:1150px; left:-500px; top:340px; }}
</style>
<div class="orb orb-a"></div><div class="orb orb-warm orb-b"></div>
<img class="faixa" src="{FAIXA}">
<div class="barra">
  <span class="bt">{TITULO}</span>
  <span class="bq">{QUANDO}</span>
</div>
<div class="rodape">
  <div>{ASSIN}</div>
  <div class="dir">iniciativa dos capítulos do PMI no Brasil, sediada no PMI-GO</div>
</div>"""
    return render("t6-airmeet-03-palco-backdrop-1920x1080", html, W, H)


# ---------------------------------------------------------------- boas-vindas 1280x720
def boasvindas():
    W, H = 1280, 720
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:22px 76px 92px; display:flex; flex-direction:column;
        align-items:center; justify-content:center; text-align:center; }}
.eyebrow {{ justify-content:center; font-size:17px; }}
h1 {{ font-size:56px; margin-top:12px; }}
.sub {{ margin-top:14px; font-size:21px; line-height:1.35; color:{TEXT}; max-width:840px; }}
.quando {{ display:inline-flex; margin-top:18px; padding:12px 26px; font-size:18px; }}
.aviso {{ margin-top:16px; font-size:16px; color:{TEXT_DIM}; }}
.time {{ display:flex; gap:40px; margin-top:20px; }}
.qi {{ text-align:center; width:150px; }}
.qn {{ font-weight:800; font-size:16px; color:{WHITE}; margin-top:8px; }}
.qc {{ font-size:13px; color:{TEXT_DIM}; margin-top:3px; line-height:1.3; }}
.rodape {{ padding:18px 76px 28px; font-size:17px; }}
.orb-a {{ width:980px; height:980px; right:-360px; top:150px; }}
.dot {{ width:64px; height:64px; left:96px; top:496px; }}
</style>
<div class="orb orb-a"></div><div class="dot-cyan dot"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  {head("Estamos começando", TITULO, SUB)}
  <div><span class="pill quando">{QUANDO}</span></div>
  <div class="time">{faixa_time(64)}</div>
  <div class="aviso">Deixe seu microfone fechado. As perguntas ficam no chat.</div>
</div>
<div class="rodape"><div>{ASSIN}</div><div>Sessão gravada</div></div>"""
    return render("t6-airmeet-04-boas-vindas-1280x720", html, W, H)


if __name__ == "__main__":
    for f in (banner, recepcao, backdrop, boasvindas):
        print("ok", f())
