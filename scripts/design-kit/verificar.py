"""Confere as dependencias ANTES de gerar, e diz o que falta e como resolver.

Existe porque as tres dependencias deste pacote falham de formas diferentes e nenhuma
delas com mensagem util: Chrome ausente da um traceback de subprocess, fonte ausente
NAO da erro nenhum (o Chrome cai para uma fonte substituta e a peca sai com a tipografia
errada, silenciosamente), e Pillow ausente quebra so na hora de medir.
"""
import shutil, subprocess, sys, pathlib

RAIZ = pathlib.Path(__file__).parent
FONTES = ["InterDisplay-Black.otf", "InterDisplay-Bold.otf"]
DESTINO = pathlib.Path("/usr/share/fonts/opentype/inter")

def ok(t): print(f"  \033[32mok\033[0m   {t}")
def falta(t, como): print(f"  \033[31mFALTA\033[0m {t}\n         -> {como}")

print("\nVerificando o que este pacote precisa:\n")
problemas = 0

chrome = next((c for c in ("google-chrome-stable", "google-chrome", "chromium",
                           "chromium-browser") if shutil.which(c)), None)
if chrome: ok(f"Chrome headless ({chrome})")
else:
    problemas += 1
    falta("Chrome ou Chromium", "instale o Google Chrome, ou 'sudo apt install chromium'")

try:
    import PIL; ok(f"Pillow {PIL.__version__}")
except ImportError:
    problemas += 1
    falta("Pillow", "pip install pillow")

try:
    import numpy; ok(f"numpy {numpy.__version__}")
except ImportError:
    problemas += 1
    falta("numpy", "pip install numpy")

sem = [f for f in FONTES if not (DESTINO / f).exists()]
if not sem:
    ok("fontes Inter Display no caminho esperado")
else:
    problemas += 1
    falta(f"fontes {', '.join(sem)} em {DESTINO}",
          f"sudo mkdir -p {DESTINO} && sudo cp fontes/*.otf {DESTINO}/")
    print("         ATENCAO: sem as fontes o Chrome NAO da erro. Ele substitui por outra")
    print("         e a peca sai com a tipografia errada, sem aviso nenhum.")

for p in ("kit/faixa-institucional-fade-1920x300.png", "kit/logo-512.png"):
    (ok if (RAIZ / p).exists() else lambda t: falta(t, "arquivo ausente no pacote"))(p)

fotos = ["joao-cut.png", "rodrigo-cut.png", "joao-fade.png", "rodrigo-fade.png",
         "joao-3x4.png", "rodrigo-3x4.png"]
sem_foto = [f for f in fotos if not (RAIZ / "fotos" / f).exists()]
if sem_foto:
    problemas += 1
    falta(f"retratos derivados: {', '.join(sem_foto)}",
          "rode: python3 recortar.py . && python3 fundir.py .")
else:
    ok("retratos derivados (recorte e fusao)")

print()
if problemas:
    print(f"\033[31m{problemas} pendencia(s).\033[0m Resolva e rode de novo.\n")
    sys.exit(1)
print("\033[32mTudo pronto.\033[0m Gere com:  ./gerar.sh\n")
