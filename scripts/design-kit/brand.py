"""Base de marca Núcleo IA & GP, amostrada dos assets reais do kit-midia (Drive 1P6VYGO3...).

Cores medidas com PIL a partir de backdrop-1920x1080.png / acd-quadrado.png, nao de tokens de memoria.
Faixa institucional (badge NIA + logos dos capitulos PMI + regua laranja) e recorte do backdrop real.
Regra do PMO: sem travessao longo nem en-dash em entregaveis.
"""
import base64, os, subprocess, pathlib

ROOT = pathlib.Path(__file__).parent
OUT = ROOT / "out"
OUT.mkdir(exist_ok=True)

# Retratos de palestrante sao ENTRADA POR EVENTO, nao toolchain, e por isso NAO sao
# versionados: o repo e publico e as fotos sao de pessoas (varias externas). Aponte
# NUCLEO_FOTOS para a pasta de retratos do evento; o default `./fotos` atende um
# workdir montado a mao. Sem isso, so os geradores que nao usam retrato rodam.
FOTOS = pathlib.Path(os.environ.get("NUCLEO_FOTOS", ROOT / "fotos"))

# --- paleta REAL (amostrada) ---
NAVY_DEEP = "#191a43"
NAVY_EDGE = "#151f47"
TEAL_CORE = "#073e5e"
TEAL_MID = "#113b5e"
WINE = "#542330"
PURPLE_BASE = "#241640"
ORANGE = "#fc6110"
CYAN = "#3ed0e9"
CYAN_SOFT = "#7fc8e8"
TEXT = "#cfe0f5"
TEXT_DIM = "#93a9c9"
WHITE = "#f4f7fc"


def b64(path):
    return base64.b64encode(pathlib.Path(path).read_bytes()).decode()


def img_uri(path, mime="image/png"):
    return f"data:{mime};base64,{b64(path)}"


FAIXA = img_uri(ROOT / "kit" / "faixa-institucional-fade-1920x300.png")


def css_base(w, h):
    """Fundo replicando o do kit: petroleo no centro-alto, navy nas bordas,
    vinheta vinho inferior-esquerda, roxo inferior-direito, grid sutil e orbitas."""
    fh = round(w * 222 / 1920)  # altura real da faixa institucional nesta largura
    return f"""
@font-face {{ font-family:'InterD'; src:url('file:///usr/share/fonts/opentype/inter/InterDisplay-Black.otf'); font-weight:900; }}
@font-face {{ font-family:'InterD'; src:url('file:///usr/share/fonts/opentype/inter/InterDisplay-Bold.otf'); font-weight:700; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
:root {{ --fh:{fh}px; }}
html,body {{ width:{w}px; height:{h}px; overflow:hidden; }}
/* o conteudo NUNCA invade a faixa institucional (badge NIA + logos dos capitulos) */
.wrap {{ position:absolute; left:0; right:0; top:var(--fh); bottom:0; }}
body {{
  font-family:'Inter',sans-serif;
  color:{TEXT};
  background:
    radial-gradient(120% 90% at 50% 8%, {TEAL_CORE} 0%, {TEAL_MID} 22%, rgba(21,31,71,0) 62%),
    radial-gradient(90% 70% at 0% 100%, {WINE} 0%, rgba(84,35,48,0) 55%),
    radial-gradient(90% 70% at 100% 100%, {PURPLE_BASE} 0%, rgba(36,22,64,0) 60%),
    linear-gradient(160deg, {NAVY_DEEP} 0%, {NAVY_EDGE} 45%, #1b1440 100%);
  position:relative;
}}
/* grid tecnico sutil, como no kit */
body::before {{
  content:''; position:absolute; inset:0;
  background-image:linear-gradient(rgba(255,255,255,.028) 1px,transparent 1px),
                   linear-gradient(90deg,rgba(255,255,255,.028) 1px,transparent 1px);
  background-size:{max(w,h)//24}px {max(w,h)//24}px;
  pointer-events:none;
}}
.faixa {{ position:absolute; top:0; left:0; width:100%; display:block; }}
.eyebrow {{
  font-size:{max(15, w//54)}px; font-weight:700; letter-spacing:.26em; text-transform:uppercase;
  color:{CYAN_SOFT}; display:flex; align-items:center; gap:.7em;
}}
.eyebrow::before {{ content:''; width:.5em; height:.5em; border-radius:50%; background:{ORANGE}; flex:none; }}
h1 {{ font-family:'InterD',sans-serif; font-weight:900; color:{WHITE}; line-height:.94; letter-spacing:-.025em; }}
.accent {{ color:{ORANGE}; }}
.pill {{
  display:inline-flex; align-items:center; gap:.55em; border-radius:999px;
  background:{ORANGE}; color:#170c04; font-weight:800; letter-spacing:.11em; text-transform:uppercase;
}}
.pill-ghost {{
  display:inline-flex; align-items:center; gap:.55em; border-radius:999px;
  border:1.5px solid rgba(160,205,240,.35); color:{TEXT}; font-weight:600;
}}
.rodape {{
  position:absolute; left:0; right:0; bottom:0;
  display:flex; align-items:flex-end; justify-content:space-between;
  border-top:1px solid rgba(160,205,240,.18);
}}
.rodape b {{ color:{WHITE}; }}
.orb {{ position:absolute; border:1px solid rgba(160,205,240,.16); border-radius:50%; pointer-events:none; }}
.orb-warm {{ border-color:rgba(252,97,16,.22); }}
.dot-cyan {{
  position:absolute; border-radius:50%;
  background:radial-gradient(circle at 35% 30%, #8fe6f7 0%, {CYAN} 45%, #17a9c9 100%);
  box-shadow:0 0 60px rgba(62,208,233,.35);
}}
/* retrato circular com anel, padrao dos cards de convidado do kit */
.retrato {{ position:relative; display:grid; place-items:center; }}
.retrato .ring {{ position:absolute; border-radius:50%; border:1.5px solid rgba(62,208,233,.38); }}
.retrato .ring2 {{ position:absolute; border-radius:50%; border:1px solid rgba(160,205,240,.16); }}
.retrato .marca {{ position:absolute; border-radius:50%; background:{ORANGE}; }}
.retrato img {{ border-radius:50%; object-fit:cover; display:block; }}
"""


def render(name, html, w, h):
    src = OUT / f"_{name}.html"
    src.write_text(html, encoding="utf-8")
    dst = OUT / f"{name}.png"
    subprocess.run([
        "google-chrome-stable", "--headless", "--disable-gpu", "--no-sandbox",
        "--hide-scrollbars", "--force-device-scale-factor=1",
        f"--window-size={w},{h}", f"--screenshot={dst}", f"file://{src}",
    ], check=True, capture_output=True)
    src.unlink()
    return dst


def retrato(foto, size, ring=True):
    """Retrato circular com aneis concentricos + marca laranja no topo,
    replicando o padrao dos cards de convidado do kit."""
    r1, r2 = size + 44, size + 96
    rings = ""
    if ring:
        rings = (f'<div class="ring" style="width:{r1}px;height:{r1}px"></div>'
                 f'<div class="ring2" style="width:{r2}px;height:{r2}px"></div>'
                 f'<div class="marca" style="width:15px;height:15px;'
                 f'transform:translateY(-{r2//2}px)"></div>')
    return (f'<div class="retrato" style="width:{r2}px;height:{r2}px">{rings}'
            f'<img src="{foto}" style="width:{size}px;height:{size}px"></div>')
