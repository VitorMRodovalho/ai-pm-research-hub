"""Lounge banner do Airmeet: 960x120 (8:1).

O slot pedia 960x120 e estava com a peca de divulgacao 1440x810 (16:9) dentro, o que renderiza
achatado. Nesta razao NAO cabe a faixa institucional inteira (a faixa sozinha teria 111px de altura
num canvas de 120), entao a marca entra pelo badge da NIA + wordmark, e o fundo replica o gradiente
do kit sem o recorte da faixa.
"""
from brand import (ROOT, OUT, img_uri, render, ORANGE, CYAN_SOFT, TEXT, TEXT_DIM, WHITE,
                   NAVY_DEEP, NAVY_EDGE, TEAL_CORE, TEAL_MID, PURPLE_BASE)

W, H = 960, 120
LOGO = img_uri(ROOT / "kit" / "logo-512.png")
TITULO = "Aplicações Práticas de IA"
QUANDO = "4 de agosto · 19h"

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
  display:flex; align-items:center; gap:22px; padding:0 30px;
}}
body::before {{
  content:''; position:absolute; inset:0; pointer-events:none;
  background-image:linear-gradient(rgba(255,255,255,.03) 1px,transparent 1px),
                   linear-gradient(90deg,rgba(255,255,255,.03) 1px,transparent 1px);
  background-size:40px 40px;
}}
.orb {{ position:absolute; border:1px solid rgba(160,205,240,.14); border-radius:50%;
       width:420px; height:420px; right:-120px; top:-170px; pointer-events:none; }}
.logo {{ width:74px; height:74px; border-radius:50%; flex:none; display:block; }}
.txt {{ flex:1; min-width:0; }}
.eyebrow {{ font-size:11px; font-weight:700; letter-spacing:.22em; text-transform:uppercase;
           color:{CYAN_SOFT}; display:flex; align-items:center; gap:.6em; }}
.eyebrow::before {{ content:''; width:.5em; height:.5em; border-radius:50%; background:{ORANGE}; flex:none; }}
h1 {{ font-family:'InterD',sans-serif; font-weight:900; font-size:27px; color:{WHITE};
     line-height:1.04; letter-spacing:-.025em; margin-top:5px; white-space:nowrap; }}
.pill {{ flex:none; display:inline-flex; align-items:center; border-radius:999px; background:{ORANGE};
        color:#170c04; font-weight:800; letter-spacing:.07em; text-transform:uppercase;
        font-size:14px; padding:10px 20px; white-space:nowrap; }}
.assin {{ flex:none; text-align:right; font-size:12px; color:{TEXT_DIM}; line-height:1.35; }}
.assin b {{ color:{TEXT}; font-weight:700; }}
</style>
<div class="orb"></div>
<img class="logo" src="{LOGO}">
<div class="txt">
  <div class="eyebrow">1º Webinar · Tribo ROI &amp; Portfólio</div>
  <h1 class="tit">{TITULO}</h1>
</div>
<span class="pill">{QUANDO}</span>
<div class="assin">online e gratuito<br>com gravação</div>"""

if __name__ == "__main__":
    p = render("t6-airmeet-05-lounge-960x120", html, W, H)
    from PIL import Image
    im = Image.open(p)
    assert im.size == (W, H), f"dimensao errada: {im.size}"
    assert "—" not in html and "–" not in html, "travessao na peca"
    print("ok", p, im.size)
