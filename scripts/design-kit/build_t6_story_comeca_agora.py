"""Story do DIA do evento ("COMEÇA AGORA"), 1080x1920 - 1o Webinar da Tribo 6, 04/08/2026.

Por que existe (#1522): a copy I3 desta peca estava escrita em COPY_DIVULGACAO.md desde 26/07,
mas a ARTE nunca foi gerada. So apareceu ao montar o checklist datado das pecas manuais - o tipo
de buraco que se descobre as 18h45 do dia do evento.

DUAS VARIANTES, porque o CTA depende de COMO a peca e publicada, e uma peca errada por
construcao e pior que peca nenhuma:

  t6-story-comeca-agora-1080x1920.png          CTA "link na bio"      -> pode ser AGENDADA (API)
  t6-story-comeca-agora-sticker-1080x1920.png  CTA "toque para entrar" -> MANUAL, com sticker

Story publicado por API sai sem link tocavel. A variante default assume isso e manda para a bio,
entao a peca pode ir na fila e ninguem precisa estar com o celular na mao as 18h50 - que e
exatamente o horario em que todo mundo esta comecando o evento. A variante sticker existe para
quem estiver livre e quiser a conversao melhor.

Marca herdada de brand.py (amostrada dos assets reais do kit; nunca reconstruir de memoria).
Regra do PMO: sem travessao longo nem en-dash.
"""
from brand import *

TITULO = "Aplicações Práticas de IA"
SALA = "A sala já está aberta"
FER = img_uri(FOTOS / "fernando-900.png")
CLE = img_uri(FOTOS / "clendson-900.png")

DUPLA = [
    dict(foto=FER, nome="Fernando Carvalho", bloco="Análise de cenário e portfólio"),
    dict(foto=CLE, nome="Clendson Gonçalves, MSc.", bloco="Segurança da informação"),
]

ASSIN = ('Núcleo IA &amp; GP<br><span class="mini">iniciativa dos capítulos do PMI no '
         'Brasil, sediada no PMI-GO</span>')


def comeca_agora(cta_texto, nome_saida):
    W, H = 1080, 1920
    dupla = "".join(f"""<div class="p">{retrato(p['foto'], 190)}
        <div class="pn">{p['nome']}</div>
        <div class="pb">{p['bloco']}</div></div>""" for p in DUPLA)

    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
/* Story tem UI do Instagram por cima: linha de perfil no topo e barra de resposta
   embaixo, ~250px de cada lado. O rodape institucional pode ser parcialmente coberto
   sem perda; o CTA e o eyebrow NAO podem. Medido por qa_measure (ink, nao caixa):
   eyebrow em y=285 e CTA terminando em 1618, ambos com folga real. Uma versao anterior
   terminava o CTA em 1670 exatos, que passa no meu render e pode ser comido no aparelho. */
.wrap {{ padding:170px 76px 0; display:flex; flex-direction:column; align-items:flex-start; }}
.eyebrow {{ font-size:22px; }}
.aovivo {{
  display:inline-flex; align-items:center; gap:.6em; margin-top:30px;
  padding:16px 34px; border-radius:999px; background:{ORANGE}; color:#170c04;
  font-weight:800; font-size:25px; letter-spacing:.16em; text-transform:uppercase;
}}
.aovivo::before {{
  content:''; width:16px; height:16px; border-radius:50%; background:#170c04;
  box-shadow:0 0 0 6px rgba(23,12,4,.18);
}}
h1 {{ font-size:146px; margin-top:34px; }}
.evento {{
  margin-top:40px; padding-top:34px; border-top:1px solid rgba(160,205,240,.22);
  font-family:'InterD',sans-serif; font-weight:900; font-size:62px; line-height:1.02;
  color:{WHITE}; letter-spacing:-.02em;
}}
.sala {{ margin-top:26px; font-size:34px; color:{CYAN}; font-weight:700; }}
.dupla {{ display:flex; gap:56px; margin-top:64px; }}
.p {{ width:286px; }}
/* "Fernando Carvalho" cabe em 1 linha e "Clendson Goncalves, MSc." em 2: sem altura
   reservada, o cargo de um fica abaixo do cargo do outro e a dupla desalinha. */
.pn {{ font-family:'InterD'; font-weight:900; font-size:31px; color:{WHITE};
      margin-top:20px; line-height:1.1; letter-spacing:-.015em; text-wrap:balance;
      min-height:{round(31*1.1*2)}px; }}
.pb {{ font-size:21px; color:{TEXT_DIM}; margin-top:9px; line-height:1.34; }}
.cta {{
  margin-top:auto; margin-bottom:302px; align-self:stretch;
  display:flex; align-items:center; justify-content:center; gap:.6em;
  padding:30px 40px; border-radius:999px;
  background:rgba(62,208,233,.12); border:2px solid {CYAN};
  color:{WHITE}; font-family:'InterD',sans-serif; font-weight:900;
  font-size:40px; letter-spacing:.02em; text-align:center;
}}
.rodape {{ padding:30px 76px 44px; font-size:22px; }}
.mini {{ font-size:17px; color:{TEXT_DIM}; }}
.orb-a {{ width:1500px; height:1500px; right:-680px; top:900px; }}
.orb-b {{ width:900px; height:900px; left:-420px; top:250px; }}
.dot {{ width:84px; height:84px; right:104px; top:470px; }}
</style>
<div class="orb orb-a"></div><div class="orb orb-warm orb-b"></div>
<div class="dot-cyan dot"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="eyebrow">1º Webinar · Tribo ROI &amp; Portfólio</div>
  <div class="aovivo">Ao vivo</div>
  <h1>Começa<br><span class="accent">agora</span></h1>
  <div class="evento">{TITULO}</div>
  <div class="sala">{SALA}</div>
  <div class="dupla">{dupla}</div>
  <div class="cta">{cta_texto}</div>
</div>
<div class="rodape">
  <div>{ASSIN}</div>
</div>"""
    return render(nome_saida, html, W, H)


if __name__ == "__main__":
    a = comeca_agora("Link na bio", "t6-story-comeca-agora-1080x1920")
    b = comeca_agora("&#8593; Toque para entrar", "t6-story-comeca-agora-sticker-1080x1920")
    for p in (a, b):
        print(f"{p}  {p.stat().st_size:,} bytes")
