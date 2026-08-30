"""Ambientes Airmeet do webinar da Tribo 11 (PMO Inteligente), 08/09/2026.

Copiado de build_airmeet_t6.py conforme o README manda ("copie, troque o conteudo").
Mesma geometria das pecas da T6, que ja passaram por qa_measure: so o conteudo muda.

Contexto medido em 27/08: o evento no Airmeet foi DUPLICADO do webinar da T6 e herdou
a arte antiga em QUATRO slots (capa, welcome illustration, waiting screen e lounge
banner), todos anunciando "4 de agosto" e outro tema; o stage backdrop estava VAZIO.
Este arquivo cobre os cinco.

Formatos espelham o kit real (pasta "3 - Ambiente Airmeet" do kit-midia):
  banner 1440x810 · welcome 1440x720 · backdrop de palco 1920x1080
  · waiting screen 1280x720 · lounge 960x120

Retratos: NAO versionados (repo publico, pessoas reais). Aponte NUCLEO_FOTOS para a
pasta do evento, com joao-400.png e rodrigo-400.png dentro.
"""
import math

from brand import *
import build_t11_campanha as K

TITULO = "Sua área entrega bem. Isso garante que ela continue existindo?"
SUB = "Como fazer stakeholders enxergarem o valor do seu PMO por meio de services e outcomes"
QUANDO = "8 de setembro · 20h às 21h (Brasília)"
QUANDO_CURTO = "8 de setembro · 20h"
EYEBROW = "Webinar · PMO Inteligente"
ASSIN = 'Realização <b>Núcleo IA &amp; GP</b> · Capítulos PMI do Brasil'

# Nome, cargo e ordem vem de `build_t11_campanha.DUO`, que e a fonte unica de como estas
# duas pessoas sao apresentadas em publico. Aqui havia uma SEGUNDA copia da lista, e ela
# ficou para tras: a correcao de 29/08 (nome e cargo lidos do perfil do proprio Rodrigo)
# entrou nas pecas de campanha e nao entrou nestas telas, que seguiam anunciando o nome
# errado no ar. Uma lista so, e a divergencia deixa de ser possivel.
# O derivado e o `-circ`, o MESMO que as pecas v7 usam, e nao o `-400`. Medido em
# 29/08/2026: os derivados `-3x4`, `-400` e `-900` de um dos palestrantes chegaram com uma
# MASCARA PRETA de canto arredondado chapada na propria imagem (canto RGB 0,0,0), herdada
# da foto que ele entregou. Num recorte circular ela fica fora e ninguem ve; num retangulo
# ela aparece como cunhas pretas dentro do canto arredondado do CSS. O `-circ` sai do
# `preparar_circulo.py` e e limpo nos dois (canto 169 e 176).
TIME = [(FOTOS / p["foto"].replace("-900", "-circ"), p["nome"],
         p["cargo"].replace("<br>", " · ")) for p in K.DUO]


PAD_LATERAL = 76   # o `.wrap` e a conta da faixa leem o MESMO valor


def faixa_time(com_cargo=True):
    """Nome e cargo vem envolvidos num `.qt` porque nesta tela eles sentam ao LADO do
    retrato, nao embaixo. Soltos, eram irmaos do retrato e o flex os empilhava.

    O retrato NAO usa o `retrato()` do brand: aquele helper desenha um circulo com aneis
    concentricos e fixa largura e altura no style INLINE do <img>, entao virar retangulo
    exigiria vencer o inline com `!important`. Aqui a marcacao e propria e a forma mora
    inteira no CSS de `_espera`, onde da para ler."""
    return "".join(f'<div class="qi">'
                   f'<div class="retrato"><img src="{img_uri(f)}"></div>'
                   f'<div class="qt"><div class="qn">{n}</div>'
                   + (f'<div class="qc">{c}</div>' if com_cargo else '') + '</div></div>'
                   for f, n, c in TIME)


# ---------------------------------------------------------------- banner 1440x810
def banner():
    """Capa da landing, e tambem a MINIATURA que todo link compartilhado do evento carrega.

    Os retratos entram aqui por causa dessa segunda funcao. Medido em 29/08/2026: o card do
    link do Airmeet no WhatsApp mostrava titulo, data e nada de quem fala, e a decisao de
    clicar num convite de webinar passa por reconhecer quem esta no palco. A peca estava
    correta como capa e incompleta como miniatura, que e a superficie onde ela e de fato vista.

    O texto passa a ocupar uma coluna a esquerda em vez da largura toda, e os dois retratos
    ocupam a direita, no mesmo retangulo de canto arredondado das outras telas.
    """
    W, H = 1440, 810
    lado = 210                       # o retrato; dois deles mais a folga cabem na coluna direita
    col = lado * 2 + 34
    duo = "".join(
        f'''<div class="dd"><div class="rt"><img src="{img_uri(f)}"></div>
        <div class="nm">{n}</div><div class="cg">{c}</div></div>'''
        for f, n, c in TIME)
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:52px 84px 130px; display:flex; flex-direction:column; justify-content:center;
        max-width:{W - col - 200}px; }}
.eyebrow {{ font-size:20px; }}
h1 {{ font-size:58px; margin-top:20px; }}
.sub {{ margin-top:20px; font-size:25px; line-height:1.4; color:{TEXT}; }}
.quando {{ display:inline-flex; margin-top:28px; padding:15px 30px; font-size:22px; }}
.rodape {{ padding:22px 84px 34px; font-size:20px; }}
.orb-a {{ width:900px; height:900px; right:-380px; top:180px; }}
.duo {{ position:absolute; right:84px; top:calc(var(--fh) + 46px); display:flex; gap:34px; z-index:5; }}
.dd {{ width:{lado}px; text-align:center; }}
.rt {{ width:{lado}px; height:{lado}px; border-radius:22px; overflow:hidden;
      box-shadow:0 0 0 5px {ORANGE}, 0 22px 50px rgba(0,0,0,.42); }}
.rt img {{ width:100%; height:100%; object-fit:cover; object-position:50% 42%;
          border-radius:0; display:block; }}
.nm {{ font-weight:800; font-size:19px; color:{WHITE}; margin-top:14px; line-height:1.2; }}
.cg {{ font-size:15px; color:{TEXT_DIM}; margin-top:5px; line-height:1.3; }}
</style>
<div class="orb orb-a"></div>
<img class="faixa" src="{FAIXA}">
<div class="duo">{duo}</div>
<div class="wrap">
  <div class="eyebrow">{EYEBROW}</div>
  <h1>{TITULO}</h1>
  <div class="sub">{SUB}</div>
  <div><span class="pill quando">{QUANDO}</span></div>
</div>
<div class="rodape"><div>{ASSIN}</div><div>Airmeet · aberto ao público</div></div>"""
    return render("t11-airmeet-01-banner-1440x810", html, W, H)


# ------------------------------------------- tela de espera (welcome e waiting screen)
def _espera(nome, W, H, eyebrow, h1px, subpx, rodape_dir, aviso=None):
    """Os dois slots tem a MESMA funcao (tela antes de comecar) e so mudam de proporcao,
    entao dividem o layout: centrado, sem grade de programacao (nao ha agenda aprovada,
    e inventar horario numa peca publica seria afirmar o que ninguem decidiu).

    O RETRATO deixou de ser valor absoluto. Ele sai da largura do cartao, e o piso da
    campanha vira uma assercao, nao o alvo. Medido em 29/08/2026, as telas que estavam NO
    AR tinham rosto a 10,6% (welcome) e 9,4% (waiting) contra um piso de 17%: existia no
    arquivo e nao existia para quem olhava a tela. Cuidado ao medir isto de novo: o
    `retrato()` do brand desenha uma caixa de foto + 96 por causa dos aneis, entao medir a
    caixa em vez do <img> da um numero quase o dobro do real."""
    # O texto sai de BAIXO do retrato e vai para o LADO. Enquanto ficava embaixo, a altura
    # da faixa era retrato + nome + cargo dentro de uma fatia fixa da tela, e o retrato era
    # o unico item que podia ceder: ele saia em 17,0% da menor dimensao, colado no piso,
    # enquanto 47% da LARGURA do canvas ficava vazia nos dois lados (medido em 29/08/2026,
    # 1008px de faixa num canvas de 1920). Ao lado, o texto para de disputar altura com o
    # rosto e a largura ociosa vira tamanho de retrato.
    gap_cartoes = W // 18
    cartao = (W - 2 * PAD_LATERAL - gap_cartoes) // 2
    lado = int(cartao * 0.44)    # o retrato e um quadrado de canto arredondado: a caixa E a foto
    txt_w = cartao - lado - subpx
    # O piso continua cobrado, mas agora e um MINIMO verificado, nao o alvo.
    assert lado / min(W, H) >= K.PISO_RETRATO_LEITURA, (
        f"{nome}: retrato a {lado / min(W, H) * 100:.1f}% da menor dimensao, "
        f"abaixo do piso de {K.PISO_RETRATO_LEITURA * 100:.0f}%")
    extra = f'<div class="aviso">{aviso}</div>' if aviso else ""
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:26px {PAD_LATERAL}px 86px; display:flex; flex-direction:column;
        align-items:center; justify-content:center; text-align:center; }}
.eyebrow {{ justify-content:center; font-size:{max(15, W//80)}px; }}
h1 {{ font-size:{h1px}px; margin-top:14px; max-width:{W-220}px; line-height:1.0; }}
.sub {{ margin-top:14px; font-size:{subpx}px; line-height:1.35; color:{TEXT}; max-width:{W-380}px; }}
.quando {{ display:inline-flex; margin-top:18px; padding:12px 26px; font-size:{subpx-2}px; }}
.aviso {{ margin-top:14px; font-size:{subpx-4}px; color:{TEXT_DIM}; }}
.time {{ display:flex; gap:{gap_cartoes}px; margin-top:26px; justify-content:center; }}
.qi {{ display:flex; align-items:center; gap:{subpx}px; text-align:left; }}
/* RETANGULO de canto arredondado, escolhido pelo PM em 29/08/2026 contra o circulo. Ele
   mostra 27% mais imagem na mesma caixa e a pessoa aparece de corpo, com postura. O custo,
   medido e aceito: expoe o fundo dos dois retratos, que nao sao o mesmo cinza (distancia
   RGB 34 entre as medias de canto), e expoe a vinheta escura nos cantos de um deles. */
.retrato {{ flex:none; width:{lado}px; height:{lado}px; border-radius:26px; overflow:hidden;
           box-shadow:0 0 0 5px {ORANGE}, 0 24px 54px rgba(0,0,0,.42); }}
/* `border-radius:0` NAO e redundante: o css_base da marca traz
   `.retrato img {{ border-radius:50% }}`, e sem desfazer isso o retrato continua um CIRCULO
   dentro do retangulo, com o fundo da pagina aparecendo nos quatro cantos. Levei uma
   rodada nisso: as fontes estavam limpas e eu quase acusei os retratos. */
.retrato img {{ width:100%; height:100%; object-fit:cover; object-position:50% 42%;
               border-radius:0; display:block; }}
/* o texto ganha largura PROPRIA, calculada do cartao. Cargo em duas linhas ao lado de um
   retrato alto e composicao, nao defeito: era defeito quando ficava embaixo e empurrava. */
.qt {{ width:{txt_w}px; }}
.qn {{ font-weight:800; font-size:{subpx}px; color:{WHITE}; line-height:1.2; }}
.qc {{ font-size:{subpx-5}px; color:{TEXT_DIM}; margin-top:9px; line-height:1.35; }}
.rodape {{ padding:18px 76px 26px; font-size:{subpx-3}px; }}
.orb-a {{ width:{W-300}px; height:{W-300}px; right:-{W//4}px; top:150px; }}
</style>
<div class="orb orb-a"></div>
<img class="faixa" src="{FAIXA}">
<div class="wrap">
  <div class="eyebrow">{eyebrow}</div>
  <h1>{TITULO}</h1>
  <div class="sub">{SUB}</div>
  <div><span class="pill quando">{QUANDO}</span></div>
  <div class="time">{faixa_time()}</div>
  {extra}
</div>
<div class="rodape"><div>{ASSIN}</div><div>{rodape_dir}</div></div>"""
    return render(nome, html, W, H)


def welcome():
    return _espera("t11-airmeet-02-welcome-1440x720", 1440, 720, "Seja bem-vindo",
                   h1px=42, subpx=21, rodape_dir="Começamos às 20h em ponto")


def waiting():
    """1920x1080, e nao os 1280x720 da T6: o proprio modal do slot pede
    "Dimensions: 1920x1080 px" (lido na tela em 27/08). Mesma razao 16:9, mais resolucao."""
    return _espera("t11-airmeet-04-waiting-1920x1080", 1920, 1080, "Estamos começando",
                   h1px=58, subpx=28, rodape_dir="Sessão gravada",
                   aviso="Deixe seu microfone fechado. As perguntas ficam no chat.")


# ---------------------------------------------------------------- backdrop de palco 1920x1080
def backdrop():
    """Canvas reutilizavel durante todo o evento: centro VAZIO para as cameras,
    identidade so no topo e no rodape (mesma logica do backdrop do kit)."""
    W, H = 1920, 1080
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.barra {{ position:absolute; left:0; right:0; top:var(--fh); padding:16px 64px;
         display:flex; align-items:baseline; gap:26px; }}
.bt {{ font-family:'InterD'; font-weight:900; font-size:34px; color:{WHITE};
      letter-spacing:-.02em; }}
.bq {{ font-size:22px; font-weight:700; color:{CYAN}; white-space:nowrap; }}
.rodape {{ padding:20px 64px 30px; font-size:21px; border-top:none; }}
.rodape .dir {{ text-align:right; }}
.orb-a {{ width:1500px; height:1500px; right:-620px; top:200px; }}
.orb-b {{ width:1150px; height:1150px; left:-500px; top:340px; }}
</style>
<div class="orb orb-a"></div><div class="orb orb-warm orb-b"></div>
<img class="faixa" src="{FAIXA}">
<div class="barra">
  <span class="bt">{TITULO}</span>
  <span class="bq">{QUANDO_CURTO}</span>
</div>
<div class="rodape">
  <div>{ASSIN}</div>
  <div class="dir">iniciativa dos capítulos do PMI no Brasil, sediada no PMI-GO</div>
</div>"""
    return render("t11-airmeet-03-palco-backdrop-1920x1080", html, W, H)


# ---------------------------------------------------------------- lounge 960x120
def lounge():
    """Nesta razao (8:1) a faixa institucional inteira NAO cabe, entao a marca entra
    pelo badge da NIA. E o titulo do evento tem 60 caracteres: numa linha ele nao cabe
    ao lado do pill, entao vai em duas, medido em vez de chutado."""
    W, H = 960, 120
    LOGO = img_uri(ROOT / "kit" / "logo-512.png")
    html = f"""<!doctype html><meta charset="utf-8"><style>
@font-face {{ font-family:'InterD'; src:url('file:///usr/share/fonts/opentype/inter/InterDisplay-Black.otf'); font-weight:900; }}
@font-face {{ font-family:'InterD'; src:url('file:///usr/share/fonts/opentype/inter/InterDisplay-Bold.otf'); font-weight:700; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{
  font-family:'Inter',sans-serif; color:{TEXT}; position:relative;
  background:
    radial-gradient(120% 260% at 22% 0%, {TEAL_CORE} 0%, {TEAL_MID} 26%, rgba(21,31,71,0) 66%),
    radial-gradient(90% 220% at 100% 100%, {PURPLE_BASE} 0%, rgba(36,22,64,0) 62%),
    linear-gradient(100deg, {NAVY_DEEP} 0%, {NAVY_EDGE} 52%, #1b1440 100%);
  display:flex; align-items:center; gap:20px; padding:0 28px;
}}
body::before {{
  content:''; position:absolute; inset:0; pointer-events:none;
  background-image:linear-gradient(rgba(255,255,255,.03) 1px,transparent 1px),
                   linear-gradient(90deg,rgba(255,255,255,.03) 1px,transparent 1px);
  background-size:40px 40px;
}}
.orb {{ position:absolute; border:1px solid rgba(160,205,240,.14); border-radius:50%;
       width:420px; height:420px; right:-120px; top:-170px; pointer-events:none; }}
.logo {{ width:66px; height:66px; border-radius:50%; flex:none; display:block; }}
.txt {{ flex:1; min-width:0; }}
.eyebrow {{ font-size:10px; font-weight:700; letter-spacing:.2em; text-transform:uppercase;
           color:{CYAN_SOFT}; display:flex; align-items:center; gap:.6em; }}
.eyebrow::before {{ content:''; width:.5em; height:.5em; border-radius:50%; background:{ORANGE}; flex:none; }}
h1 {{ font-family:'InterD',sans-serif; font-weight:900; font-size:19px; color:{WHITE};
     line-height:1.14; letter-spacing:-.02em; margin-top:5px; }}
.pill {{ flex:none; display:inline-flex; align-items:center; border-radius:999px; background:{ORANGE};
        color:#170c04; font-weight:800; letter-spacing:.06em; text-transform:uppercase;
        font-size:13px; padding:9px 17px; white-space:nowrap; }}
.assin {{ flex:none; text-align:right; font-size:11px; color:{TEXT_DIM}; line-height:1.35; }}
</style>
<div class="orb"></div>
<img class="logo" src="{LOGO}">
<div class="txt">
  <div class="eyebrow">{EYEBROW}</div>
  <h1 class="tit">{TITULO}</h1>
</div>
<span class="pill">{QUANDO_CURTO}</span>
<div class="assin">online e gratuito<br>com gravação</div>"""
    return render("t11-airmeet-05-lounge-960x120", html, W, H)


if __name__ == "__main__":
    from PIL import Image
    esperado = {
        "t11-airmeet-01-banner-1440x810": (1440, 810),
        "t11-airmeet-02-welcome-1440x720": (1440, 720),
        "t11-airmeet-03-palco-backdrop-1920x1080": (1920, 1080),
        "t11-airmeet-04-waiting-1920x1080": (1920, 1080),
        "t11-airmeet-05-lounge-960x120": (960, 120),
    }
    for f in (banner, welcome, backdrop, waiting, lounge):
        p = f()
        got = Image.open(p).size
        assert got == esperado[p.stem], f"{p.stem}: {got} != {esperado[p.stem]}"
        print("ok", p, got)
