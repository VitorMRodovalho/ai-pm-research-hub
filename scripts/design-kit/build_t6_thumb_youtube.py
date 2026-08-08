"""Miniatura do YouTube (1280x720) da gravação do 1o Webinar da Tribo 6, 04/08/2026.

Por que não reaproveitar o banner 1440x810 do Airmeet: o texto dele é convite
("4 de agosto · 19h às 20h30"), tempo futuro, e a miniatura do replay é lida depois
do evento. Aqui a pílula diz gravação e data, e os dois palestrantes aparecem, que é
o que ajuda o reconhecimento numa miniatura vista pequena.

As fotos vêm do kit do webinar no Drive:
  NUCLEO_FOTOS="<kit>/fotos-palestrantes" python build_t6_thumb_youtube.py
"""
from brand import *

FER = img_uri(FOTOS / "fernando-900.png")
CLE = img_uri(FOTOS / "clendson-900.png")

TITULO = "Aplicações Práticas de IA"
SUB = "IA na priorização, na análise de cenário e na segurança da informação"
QUANDO = "Gravação · 4 de agosto de 2026"
ASSIN = 'Realização <b>Núcleo IA &amp; GP</b> · Tribo ROI &amp; Portfólio'

TIME = [(FER, "Fernando Carvalho"), (CLE, "Clendson Gonçalves, MSc.")]


def thumb():
    W, H = 1280, 720
    retratos = "".join(
        f'<div class="qi">{retrato(f, 132)}<div class="qn">{n}</div></div>'
        for f, n in TIME
    )
    html = f"""<!doctype html><meta charset="utf-8"><style>{css_base(W,H)}
.wrap {{ padding:44px 72px 104px; display:flex; align-items:center; gap:36px; }}
.col {{ display:flex; flex-direction:column; justify-content:center; flex:1; }}
.eyebrow {{ font-size:18px; }}
h1 {{ font-size:74px; margin-top:16px; max-width:720px; }}
.sub {{ margin-top:18px; font-size:24px; line-height:1.35; color:{TEXT}; max-width:660px; }}
.quando {{ display:inline-flex; margin-top:26px; padding:14px 28px; font-size:21px; }}
.time {{ display:flex; gap:14px; }}
.qi {{ text-align:center; width:230px; }}
.qn {{ font-weight:800; font-size:18px; color:{WHITE}; margin-top:6px; line-height:1.25; }}
.rodape {{ padding:20px 72px 30px; font-size:18px; }}
.orb-a {{ width:1000px; height:1000px; right:-380px; top:120px; }}
/* sem dot ciano: no 1280x720 ele cai exatamente atrás da pílula (medido) */
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
  <div class="time">{retratos}</div>
</div>
<div class="rodape"><div>{ASSIN}</div><div>youtube.com/@nucleo_ia</div></div>"""
    return render("t6-youtube-thumb-1280x720", html, W, H)


if __name__ == "__main__":
    print("ok", thumb())
