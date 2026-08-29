"""Campanha do 1o Webinar da Tribo 11 (PMO Inteligente), 08/09/2026.

Este arquivo existe para uma comparacao, nao so para gerar arte. O kit aplica UM layout
a dez formatos (eyebrow > titulo > subtitulo > retratos em circulo > pilula > rodape),
redimensionado. Isso garante consistencia e custa projecao: a peca que a pessoa PASSA
carrega a mesma densidade da peca que ela LE.

Cada formato sai em duas versoes, lado a lado, para o dono decidir por comparacao:

  padrao_*   o layout de hoje, so trocando o conteudo para a T11
  proposta_* a direcao alternativa

O que muda na proposta, e por que:

1. HIERARQUIA POR FORMATO. O titulo tem 60 caracteres e e uma pergunta de duas oracoes.
   No story ele vira duas vozes: a primeira oracao pequena (a premissa que o leitor aceita)
   e a segunda gigante (a virada). A pergunta E o ativo da peca; o que faltava era ritmo.
2. UMA IDEIA POR PECA. Story nao leva subtitulo, cargo, horario e rodape institucional.
   Leva a virada, quem fala e quando.
3. A FOTO COMPOE. Em vez de circulo pequeno e centrado, retrato grande sangrando na base.
4. A MARCA SAI DO TOPO. A faixa institucional ocupa 11,5% da altura de TODA peca hoje.
   Em peca de circulacao ela vira assinatura discreta no rodape; a faixa fica onde ha
   tempo de leitura (landing, backdrop, recepcao).

Retratos: NAO versionados (repo publico, pessoas reais). Aponte NUCLEO_FOTOS.
"""
from brand import *

TITULO_A = "Sua área entrega bem."
TITULO_B = "Isso garante que ela continue existindo?"
TITULO = f"{TITULO_A} {TITULO_B}"
SUB = "Como fazer stakeholders enxergarem o valor do seu PMO por meio de services e outcomes"
QUANDO = "8 de setembro · 20h às 21h (Brasília)"
QUANDO_CURTO = "8 de setembro · 20h BRT"
EYEBROW = "1º Webinar · PMO Inteligente"
ASSIN = ('Núcleo IA &amp; GP<br><span class="mini">iniciativa dos capítulos do PMI no '
         'Brasil, sediada no PMI-GO</span>')
CTA = "Online e gratuito · inscrição pelo Airmeet"

DUO = [
    dict(foto="joao-900.png", nome="João Henrique Jacinto",
         cargo="Diretor da Zieger<br>PMI Rising Leader Latam 2025"),
    dict(foto="rodrigo-900.png", nome="Rodrigo Santa Rita",
         cargo="Gerente de Projetos Sênior<br>Delivery Manager"),
]
def uri(p): return img_uri(FOTOS / p)

# ── ESCALA ────────────────────────────────────────────────────────────────────
# Auditoria de 28/08: o menor texto das pecas estava em 1,4% a 1,9% da menor dimensao,
# e o retrato do post em 11,7%. Numa tela de celular isso vira corpo de 5 a 7 px reais.
# O piso de legibilidade em peca social fica por volta de 2,6%, e retrato so e reconhecido
# de relance acima de ~17%. Por isso os corpos deixam de ser valor absoluto e passam a ser
# FRACAO da menor dimensao: quem muda de formato nao precisa relembrar de reescalar, e o
# guard cobra o piso em qualquer tamanho novo.
PISO_TEXTO = 0.026        # cobrado no QA
PISO_RETRATO_RELANCE = 0.26
PISO_RETRATO_LEITURA = 0.17

ESCALA = {
    # peca de RELANCE: menos itens, corpos maiores
    "story":    dict(micro=.026, corpo=.030, dest=.044, prem=.050, virada=.120, rt=.300),
    # peca de LEITURA: mais itens, corpos ainda acima do piso
    "post":     dict(micro=.026, corpo=.029, dest=.036, prem=.038, virada=.086, rt=.175),
    "linkedin": dict(micro=.027, corpo=.031, dest=.040, prem=.043, virada=.095, rt=.270),
    # MINIATURA de YouTube: e vista PEQUENA, entao os corpos sao os maiores de todos e o
    # texto e o mais curto. O piso de 2,6% nao basta aqui; o que manda e caber poucas
    # palavras grandes ao lado de rostos reconheciveis.
    "thumb":    dict(micro=.034, corpo=.040, dest=.058, prem=.052, virada=.108, rt=.62),
    # CARD individual de palestrante: a peca existe para a PESSOA repostar, entao o rosto
    # e o nome dominam e o tema entra em corpo de leitura.
    "card":     dict(micro=.022, corpo=.027, dest=.042, prem=.034, virada=.064, rt=.42),
}


def px(formato, papel, menor):
    """TETO, nao arredondamento: a fracao e um PISO, e `round` a puxava para baixo
    (0,026 x 1080 = 28,08 -> 28 -> 2,593%, que reprova no proprio guard que a definiu)."""
    import math
    return math.ceil(ESCALA[formato][papel] * menor)



# ═══════════════════════════════════════════════════ PADRAO (o layout de hoje)
def _padrao_pessoa(p, size):
    return (f'<div class="pessoa">{retrato(uri(p["foto"]), size)}'
            f'<div class="pn">{p["nome"]}</div><div class="ptr">{p["cargo"]}</div></div>')


def padrao_post():
    W, H = 1080, 1350
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:26px 72px 104px; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:19px; }}
h1 {{ font-size:56px; margin-top:12px; }}
.sub {{ margin-top:14px; font-size:25px; line-height:1.4; color:{TEXT}; max-width:880px; }}
.duo {{ display:flex; gap:40px; margin-top:26px; justify-content:center; }}
.pessoa {{ flex:1; display:flex; flex-direction:column; align-items:center;
          text-align:center; max-width:400px; }}
.pn {{ font-family:'InterD'; font-weight:900; font-size:34px; color:{WHITE};
      margin-top:14px; letter-spacing:-.02em; text-wrap:balance; }}
.ptr {{ font-size:18px; color:{TEXT_DIM}; margin-top:6px; }}
.quando {{ display:inline-flex; margin-top:26px; padding:14px 30px; font-size:21px; }}
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
  <div class="eyebrow">{EYEBROW}</div>
  <h1>{TITULO}</h1>
  <div class="sub">{SUB}</div>
  <div class="duo">{"".join(_padrao_pessoa(p,240) for p in DUO)}</div>
  <div><span class="pill quando">{QUANDO}</span></div>
</div>
<div class="rodape">
  <div>{CTA}<br><span class="mini">Público interno PMI e externo · com gravação</span></div>
  <div class="dir">{ASSIN}</div>
</div>"""
    return render("t11-A-padrao-post-1080x1350", html, W, H)


def padrao_story():
    W, H = 1080, 1920
    linhas = "".join(f"""<div class="linha">{retrato(uri(p['foto']), 250)}
      <div class="txt"><div class="pn">{p['nome']}</div>
      <div class="ptr">{p['cargo']}</div></div></div>""" for p in DUO)
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:40px 76px 150px; display:flex; flex-direction:column; }}
.eyebrow {{ font-size:22px; }}
h1 {{ font-size:76px; margin-top:22px; }}
.sub {{ margin-top:22px; font-size:30px; line-height:1.4; color:{TEXT}; }}
.linha {{ display:flex; align-items:center; gap:30px; margin-top:44px; }}
.pn {{ font-family:'InterD'; font-weight:900; font-size:40px; color:{WHITE};
      letter-spacing:-.02em; }}
.ptr {{ font-size:22px; color:{TEXT_DIM}; margin-top:8px; }}
.quando {{ display:inline-flex; margin-top:52px; padding:18px 38px; font-size:27px; }}
.rodape {{ padding:30px 76px 60px; font-size:23px; gap:40px; }}
.rodape .dir {{ text-align:right; }}
.mini {{ font-size:17px; color:{TEXT_DIM}; }}
.orb-a {{ width:1500px; height:1500px; right:-700px; top:900px; }}
</style>
<div class="orb orb-a"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="eyebrow">{EYEBROW}</div>
  <h1>{TITULO}</h1>
  <div class="sub">{SUB}</div>
  {linhas}
  <div><span class="pill quando">{QUANDO}</span></div>
</div>
<div class="rodape">
  <div>{CTA}</div>
  <div class="dir">{ASSIN}</div>
</div>"""
    return render("t11-A-padrao-story-1080x1920", html, W, H)


# ═══════════════════════════════════════════════════ PROPOSTA
CSS_PROPOSTA = f"""
@font-face {{ font-family:'InterD'; src:url('file:///usr/share/fonts/opentype/inter/InterDisplay-Black.otf'); font-weight:900; }}
@font-face {{ font-family:'InterD'; src:url('file:///usr/share/fonts/opentype/inter/InterDisplay-Bold.otf'); font-weight:700; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
.premissa {{ font-weight:600; color:{TEXT_DIM}; letter-spacing:-.01em; }}
/* line-height abaixo de 1 puxa a 1a linha para cima e os glifos encostam na premissa.
   Medido: 3px de sobreposicao no story, 2 no post, 1 no linkedin. O margin-top de cada
   peca abre folga real, provada em qa_measure com piso de 8px. */
.virada {{ font-family:'InterD',sans-serif; font-weight:900; color:{WHITE};
          line-height:.92; letter-spacing:-.035em; text-wrap:balance; }}
.risco {{ display:block; background:{ORANGE}; border-radius:99px; }}
.selo {{ display:inline-flex; align-items:center; gap:.5em; font-weight:800;
        letter-spacing:.16em; text-transform:uppercase; color:{CYAN}; }}
.selo::before {{ content:''; width:.45em; height:.45em; border-radius:50%; background:{ORANGE}; }}
.assina {{ color:{TEXT_DIM}; }}
.assina b {{ color:{TEXT}; font-weight:700; }}
"""


def _fundo(w, h):
    """Mesma paleta do kit, composicao diferente: a luz vem de BAIXO e de um lado so,
    para abrir espaco escuro no topo, onde a tipografia grande precisa de contraste."""
    return f"""
html,body {{ width:{w}px; height:{h}px; overflow:hidden; }}
body {{ font-family:'Inter',sans-serif; color:{TEXT}; position:relative;
  background:
    radial-gradient(80% 55% at 8% 104%, {TEAL_CORE} 0%, {TEAL_MID} 30%, rgba(21,31,71,0) 68%),
    radial-gradient(70% 45% at 108% 88%, {PURPLE_BASE} 0%, rgba(36,22,64,0) 62%),
    linear-gradient(178deg, #0d1030 0%, {NAVY_DEEP} 58%, #191338 100%); }}
body::before {{ content:''; position:absolute; inset:0; pointer-events:none;
  background-image:linear-gradient(rgba(255,255,255,.022) 1px,transparent 1px),
                   linear-gradient(90deg,rgba(255,255,255,.022) 1px,transparent 1px);
  background-size:{max(w,h)//22}px {max(w,h)//22}px; }}
"""


def proposta_story():
    """Uma ideia. A premissa em corpo de texto, a virada em display gigante, e os dois
    retratos grandes o bastante para reconhecer de relance.

    O ar e DISTRIBUIDO (coluna flex de altura cheia, space-between), nao concentrado:
    na primeira versao o posicionamento absoluto deixou um vazio no meio que lia como
    erro de montagem, e nao como respiro."""
    W, H = 1080, 1920
    m = min(W, H)
    E = lambda papel: px("story", papel, m)
    duo = "".join(f'''<div class="p"><img class="rt" src="{uri(p["foto"])}">
      <div class="nm">{p["nome"]}</div><div class="cg">{p["cargo"]}</div></div>''' for p in DUO)
    html = f"""<!doctype html><meta charset="utf-8"><style>{CSS_PROPOSTA}{_fundo(W,H)}
body {{ display:flex; flex-direction:column; justify-content:space-between;
       padding:96px 80px 62px; }}
.selo {{ font-size:{E('micro')}px; }}
.premissa {{ font-size:{E('prem')}px; margin-top:36px; }}
.virada {{ font-size:{E('virada')}px; margin-top:34px; }}
.risco {{ width:140px; height:10px; margin-top:40px; }}
.quando {{ margin-top:34px; font-size:{E('dest')}px; font-weight:800; color:{WHITE}; }}
.cta {{ margin-top:12px; font-size:{E('corpo')}px; color:{CYAN}; font-weight:700; }}
.duo {{ display:flex; gap:44px; justify-content:center; }}
.p {{ flex:1; max-width:430px; text-align:center; }}
.rt {{ width:{E('rt')}px; height:{E('rt')}px; border-radius:50%; object-fit:cover;
      border:6px solid rgba(62,208,233,.5); }}
/* min-height de 2 linhas: o nome mais longo quebra e o mais curto nao, e sem isso os
   cargos dos dois saem em alturas diferentes. Mesma armadilha das pecas do Airmeet. */
.nm {{ font-family:'InterD'; font-weight:900; font-size:{E('dest')}px; color:{WHITE};
      margin-top:20px; line-height:1.12; letter-spacing:-.02em; text-wrap:balance;
      min-height:2.24em; }}
.cg {{ font-size:{E('corpo')}px; color:{TEXT_DIM}; margin-top:9px; line-height:1.3; }}
.rod {{ display:flex; justify-content:space-between; align-items:flex-end;
       font-size:{E('micro')}px; }}
</style>
<div>
  <div class="selo">{EYEBROW}</div>
  <div class="premissa">{TITULO_A}</div>
  <div class="virada">{TITULO_B}</div>
  <span class="risco"></span>
  <div class="quando">{QUANDO_CURTO}</div>
  <div class="cta">online e gratuito</div>
</div>
<div class="duo">{duo}</div>
<div class="rod"><div class="assina">Realização <b>Núcleo IA &amp; GP</b></div>
<div class="assina">inscrição pelo Airmeet</div></div>"""
    return render("t11-B-proposta-story-1080x1920", html, W, H)


def proposta_post():
    """Uma ideia mais a prova. Aqui cabe o subtitulo, porque post de feed e LIDO.
    Ar distribuido por space-between, pela mesma razao do story."""
    W, H = 1080, 1350
    m = min(W, H)
    E = lambda papel: px("post", papel, m)
    duo = "".join(f"""<div class="p"><img class="rt" src="{uri(p['foto'])}">
      <div><div class="nm">{p['nome']}</div><div class="cg">{p['cargo']}</div></div></div>"""
                  for p in DUO)
    html = f"""<!doctype html><meta charset="utf-8"><style>{CSS_PROPOSTA}{_fundo(W,H)}
body {{ display:flex; flex-direction:column; justify-content:space-between;
       padding:70px 74px 34px; }}
.selo {{ font-size:{E('micro')}px; }}
.premissa {{ font-size:{E('prem')}px; margin-top:26px; }}
.virada {{ font-size:{E('virada')}px; margin-top:26px; max-width:940px; }}
.risco {{ width:120px; height:9px; margin-top:30px; }}
.sub {{ margin-top:28px; font-size:{E('dest')}px; line-height:1.4; color:{TEXT}; max-width:900px; }}
.duo {{ display:flex; flex-direction:column; gap:24px; }}
.p {{ display:flex; align-items:center; gap:26px; }}
.rt {{ width:{E('rt')}px; height:{E('rt')}px; border-radius:50%; object-fit:cover; flex:none;
      border:5px solid rgba(62,208,233,.45); }}
.nm {{ font-family:'InterD'; font-weight:900; font-size:{E('dest')}px; color:{WHITE};
      letter-spacing:-.02em; }}
.cg {{ font-size:{E('corpo')}px; color:{TEXT_DIM}; margin-top:6px; }}
.faixa-data {{ margin:0 -74px; padding:22px 74px;
              background:rgba(62,208,233,.1); border-top:1px solid rgba(62,208,233,.3);
              border-bottom:1px solid rgba(62,208,233,.3);
              display:flex; justify-content:space-between; align-items:center; }}
.dt {{ font-family:'InterD'; font-weight:900; font-size:{E('dest')}px; color:{WHITE};
      letter-spacing:-.02em; }}
.ct {{ font-size:{E('corpo')}px; color:{CYAN}; font-weight:700; }}
/* uma linha so: com o corpo no piso de legibilidade, a linha institucional longa quebrava
   em duas e competia com o conteudo. Ela continua inteira na landing, que e onde ha tempo
   de leitura. Subir o piso obriga a tirar texto, e o que sai e o que menos rende. */
.rod {{ display:flex; justify-content:space-between; font-size:{E('micro')}px; gap:30px; }}
</style>
<div class="top">
  <div class="selo">{EYEBROW}</div>
  <div class="premissa">{TITULO_A}</div>
  <div class="virada">{TITULO_B}</div>
  <span class="risco"></span>
  <div class="sub">{SUB}</div>
</div>
<div class="duo">{duo}</div>
<div class="faixa-data"><span class="dt">{QUANDO_CURTO}</span>
<span class="ct">online e gratuito · pelo Airmeet</span></div>
<div class="rod"><div class="assina">Realização <b>Núcleo IA &amp; GP</b> · Tribo PMO Inteligente</div></div>"""
    return render("t11-B-proposta-post-1080x1350", html, W, H)


def proposta_linkedin():
    """Horizontal 1200x627: a virada ocupa a esquerda, os retratos ancoram a direita."""
    W, H = 1200, 627
    m = min(W, H)
    E = lambda papel: px("linkedin", papel, m)
    fotos = "".join(f'<img class="rt" src="{uri(p["foto"])}">' for p in DUO)
    html = f"""<!doctype html><meta charset="utf-8"><style>{CSS_PROPOSTA}{_fundo(W,H)}
.esq {{ position:absolute; left:58px; top:52px; width:690px; }}
.selo {{ font-size:{E('micro')}px; }}
.premissa {{ font-size:{E('prem')}px; margin-top:18px; }}
.virada {{ font-size:{E('virada')}px; margin-top:16px; }}
.risco {{ width:86px; height:7px; margin-top:22px; }}
.quando {{ margin-top:22px; font-family:'InterD'; font-weight:900; font-size:{E('dest')}px;
          color:{WHITE}; letter-spacing:-.02em; }}
.cta {{ margin-top:7px; font-size:{E('corpo')}px; color:{CYAN}; font-weight:700; }}
.dir {{ position:absolute; right:48px; top:0; bottom:0; width:420px;
       display:flex; flex-direction:column; align-items:center; justify-content:center; gap:16px; }}
.linha {{ display:flex; align-items:center; }}
.rt {{ width:{E('rt')}px; height:{E('rt')}px; border-radius:50%; object-fit:cover;
      border:5px solid rgba(62,208,233,.45); }}
.rt:last-child {{ margin-left:-34px; }}
.nomes {{ text-align:center; font-family:'InterD'; font-weight:900; font-size:{E('corpo')}px;
         color:{WHITE}; line-height:1.42; letter-spacing:-.01em; }}
.rod {{ position:absolute; left:58px; bottom:28px; font-size:{E('micro')}px; }}
</style>
<div class="esq">
  <div class="selo">{EYEBROW}</div>
  <div class="premissa">{TITULO_A}</div>
  <div class="virada">{TITULO_B}</div>
  <span class="risco"></span>
  <div class="quando">{QUANDO_CURTO}</div>
  <div class="cta">online e gratuito · inscrição pelo Airmeet</div>
</div>
<div class="dir">
  <div class="linha">{fotos}</div>
  <div class="nomes">{DUO[0]['nome']}<br>{DUO[1]['nome']}</div>
</div>
<div class="rod assina">Realização <b>Núcleo IA &amp; GP</b> · Tribo PMO Inteligente</div>"""
    return render("t11-B-proposta-linkedin-1200x627", html, W, H)


PECAS = [padrao_post, padrao_story, proposta_story, proposta_post, proposta_linkedin]

if __name__ == "__main__":
    from PIL import Image
    for f in PECAS:
        p = f()
        print("ok", p.name, Image.open(p).size)
