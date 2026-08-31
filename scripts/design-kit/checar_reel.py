"""Confere um reel na GRADE DO PERFIL, que e onde ele e de fato lido.

O player mostra 9:16 inteiro e esconde os dois defeitos que a #2068 mediu no perfil
`@nucleo.ia.gp` em 29/08/2026:

  tile da grade      242x322, razao 0,75
  reel na fonte      1080x1920, razao 0,563
  altura visivel     0,563 / 0,75 = 75%  ->  corta 12,5% em cima e 12,5% embaixo

  defeito 1  a manchete comeca por volta de 10% da altura, DENTRO da faixa cortada
  defeito 2  a capa e um frame do inicio, quando a caixa de conteudo ainda esta vazia

Uso:
    python3 checar_reel.py <video.mp4> [--passo 0.5] [--saida pasta]

O que sai: um veredito por defeito, a recomendacao de capa com o instante em segundos,
e um contato visual `grade.png` com os quadros JA RECORTADOS como a grade recorta. O
ponto e olhar a superficie certa, nao o arquivo.

LIMITE, dito de frente: isto NAO le texto. Para o defeito 1 mede DETALHE (variancia de
Laplaciano) por faixa: detalhe na faixa cortada quer dizer "tem coisa ai que vai ser
decepada", nao "tem texto ai". Para o defeito 2 mede DISPERSAO DE LUMINANCIA na caixa
de conteudo (ver abaixo por que nao e detalhe). Nenhuma das duas substitui olhar o
`grade.png`.

## Por que o defeito 2 exigiu outra medida e outra amostragem (medido em 31/08/2026)

Sobre os 41 shorts do ciclo, com gabarito montado a olho (14 com a caixa vazia no
quadro 0, 27 cheias), a versao anterior deste script acusava 2. Errava por DOIS
motivos independentes, e consertar so um nao resolvia:

1. **Lia o quadro errado.** `ffmpeg -vf fps=1/passo` NAO entrega o quadro 0. A caixa
   vazia dura 2 quadros (83 ms a 24 fps) e o primeiro quadro que o filtro devolvia ja
   vinha cheio. Justamente o quadro 0 e o que vira capa padrao. Os quadros do inicio
   passam a ser extraidos sem filtro, e `capa-atual.png` passa a ser o quadro 0 de
   verdade: antes o contato visual tambem mentia, mostrando a caixa cheia.

2. **Media a grandeza errada.** Variancia de Laplaciano nao serve aqui: a caixa vazia
   deixa ver o fundo da marca, que tem listras diagonais de borda nitida, enquanto um
   rosto de webcam e suave. Vazio mede MAIS detalhe que cheio. Na razao contra a
   propria mediana as 14 vazias iam de 0,13 a 1,42, embaralhadas com as cheias: nao ha
   limiar possivel. Dispersao de luminancia separa sem ambiguidade, porque conteudo
   (rosto, slide, retrato) sempre alarga a distribuicao sobre o fundo chapado:

       vazias   razao <= 0,52        cheias   razao >= 0,95

   O limiar mora no vao, no meio geometrico. A medida e RELATIVA a mediana do proprio
   video de proposito: limiar absoluto amarraria o detector a este fundo de marca.

A causa dos 14 esta no gerador, nao no reel: os `_trim.mp4` comecam em `start_time`
0,020996 enquanto o fundo em `-loop 1 -framerate 24` tem PTS exatos, entao o `overlay`
fica sem quadro de card nos dois primeiros, e a borda laranja (`drawbox`, aplicada
depois) e desenhada de qualquer jeito. Da o retangulo vazio. Ver #2068 e #2118.
"""
import argparse, json, pathlib, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image

FAIXA = 0.125          # a grade corta isto em cima e embaixo
TILE = (242, 322)      # medido no perfil

# A CAIXA DE CONTEUDO, em fracao da altura. Vem das constantes que os tres geradores
# de short compartilham (`TOP_SCRIM_H=520` e `BOT_SCRIM_Y=1400` sobre `H=1920`): acima
# dela mora a manchete, abaixo a legenda queimada. E a faixa onde o card do orador
# (500..1380), o card de slide (648..1175) e o audiograma (540..1390) sao compostos.
CAIXA = (0.271, 0.729)

# Quadros do INICIO lidos sem filtro. A capa padrao sai daqui, e o filtro `fps` pula o
# quadro 0. 24 quadros = 1 s a 24 fps, folga larga sobre os 2 quadros medidos.
QUADROS_CAPA = 24

# Vao medido entre vazias (<=0,52) e cheias (>=0,95); o meio geometrico da 0,706.
LIMIAR_CAIXA = 0.70


def _run(*a):
    return subprocess.run(a, capture_output=True, text=True, check=True).stdout


def sonda(video):
    d = json.loads(_run("ffprobe", "-v", "error", "-select_streams", "v:0",
                        "-show_entries", "stream=width,height,r_frame_rate:format=duration",
                        "-of", "json", str(video)))
    s = d["streams"][0]
    num, den = (s.get("r_frame_rate") or "24/1").split("/")
    fps = float(num) / float(den or 1)
    return int(s["width"]), int(s["height"]), float(d["format"]["duration"]), fps


def detalhe(a):
    """Variancia do Laplaciano: alto onde ha borda, baixo em area chapada."""
    g = np.asarray(Image.fromarray(a).convert("L"), dtype=float)
    if g.size == 0:
        return 0.0
    lap = (-4 * g[1:-1, 1:-1] + g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:])
    return float(lap.var())


def dispersao(a):
    """Desvio da luminancia: alto quando ha conteudo sobre o fundo, baixo no fundo nu.
    Ao contrario do Laplaciano, nao se deixa enganar pelas listras do fundo."""
    g = np.asarray(Image.fromarray(a).convert("L"), dtype=float)
    return float(g.std()) if g.size else 0.0


def faixa_caixa(a):
    H = a.shape[0]
    return a[int(H * CAIXA[0]):int(H * CAIXA[1])]


def recorte_da_grade(im):
    """O MESMO recorte que a grade aplica: centro, na razao do tile."""
    W, H = im.size
    alvo = TILE[0] / TILE[1]
    h = min(H, int(W / alvo))
    y = (H - h) // 2
    return im.crop((0, y, W, y + h))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("video")
    p.add_argument("--passo", type=float, default=0.5, help="segundos entre quadros")
    p.add_argument("--saida", default=None)
    args = p.parse_args()

    video = pathlib.Path(args.video)
    if not video.exists():
        sys.exit(f"nao achei {video}")
    W, H, dur, fps = sonda(video)
    saida = pathlib.Path(args.saida or video.with_suffix("").name + "-grade")
    saida.mkdir(parents=True, exist_ok=True)

    tmp = pathlib.Path(tempfile.mkdtemp())
    try:
        # (a) serie amostrada: descreve o video inteiro
        _run("ffmpeg", "-v", "error", "-i", str(video), "-vf",
             f"fps=1/{args.passo}", "-q:v", "2", str(tmp / "q%04d.jpg"))
        quadros = sorted(tmp.glob("q*.jpg"))
        if not quadros:
            sys.exit("ffmpeg nao extraiu quadro nenhum")

        # (b) os primeiros quadros REAIS, sem filtro: e de la que sai a capa padrao
        _run("ffmpeg", "-v", "error", "-i", str(video), "-frames:v", str(QUADROS_CAPA),
             "-q:v", "2", str(tmp / "z%03d.jpg"))
        inicio = sorted(tmp.glob("z*.jpg"))
        if not inicio:
            sys.exit("ffmpeg nao extraiu os quadros do inicio")

        topo_h = int(H * FAIXA)
        linhas = []
        for i, q in enumerate(quadros):
            im = Image.open(q).convert("RGB")
            a = np.asarray(im)
            linhas.append({
                "i": i,
                "t": i * args.passo,
                "topo": detalhe(a[:topo_h]),
                "base": detalhe(a[H - topo_h:]),
                "miolo": detalhe(a[topo_h:H - topo_h]),
                "tile": detalhe(np.asarray(recorte_da_grade(im))),
                "caixa": dispersao(faixa_caixa(a)),
            })
        inicio_caixa = [dispersao(faixa_caixa(np.asarray(Image.open(z).convert("RGB"))))
                        for z in inicio]

        print(f"\n{video.name}  {W}x{H}  razao {W/H:.3f}  {dur:.1f}s"
              f"  ({len(quadros)} quadros a cada {args.passo}s"
              f"; {len(inicio)} quadros do inicio sem filtro)")
        visivel = (W / H) / (TILE[0] / TILE[1])
        print(f"na grade sobra {visivel*100:.0f}% da altura: "
              f"corta {(1-visivel)/2*100:.1f}% em cima e embaixo\n")

        falhas = []

        # ── defeito 1: conteudo mora na faixa que sera cortada
        med_miolo = np.median([l["miolo"] for l in linhas]) or 1.0
        piso = med_miolo * .18                       # 18% do detalhe do miolo
        quentes = [l for l in linhas if l["topo"] > piso or l["base"] > piso]
        if quentes:
            pior = max(quentes, key=lambda l: max(l["topo"], l["base"]))
            onde = "topo" if pior["topo"] >= pior["base"] else "base"
            falhas.append(
                f"conteudo na faixa CORTADA: {len(quentes)} de {len(linhas)} quadros; "
                f"pior em t={pior['t']:.1f}s no {onde} "
                f"({max(pior['topo'], pior['base'])/med_miolo*100:.0f}% do detalhe do miolo)")

        # ── defeito 2: a capa padrao e um quadro com a CAIXA DE CONTEUDO ainda vazia
        # A mediana e a referencia; com serie curta demais ela vira quase uma amostra
        # so, e se essa amostra cair num quadro vazio a razao da 1,0 e o portao fica
        # QUIETO. Avisa em vez de aprovar em silencio.
        if len(linhas) < 3:
            print(f"  \033[33maviso\033[0m so {len(linhas)} quadro(s) amostrados: a mediana "
                  f"da caixa nao e confiavel e o defeito 2 pode passar batido. "
                  f"Use --passo menor.")
        med_caixa = np.median([l["caixa"] for l in linhas]) or 1e-9
        razao0 = inicio_caixa[0] / med_caixa
        vazios = 0
        for c in inicio_caixa:
            if c / med_caixa < LIMIAR_CAIXA:
                vazios += 1
            else:
                break
        if vazios:
            enche = vazios / fps
            falhas.append(
                f"caixa de conteudo VAZIA na capa: o quadro 0 tem {razao0*100:.0f}% da "
                f"dispersao mediana da caixa (limiar {LIMIAR_CAIXA*100:.0f}%); "
                f"{vazios} quadro(s) iniciais vazios, enche em t={enche:.3f}s. "
                f"Defina a capa a mao em t>={enche:.3f}s, ou corte os {vazios} primeiros quadros")

        # ── recomendacao de capa: melhor tile ENTRE os quadros com a caixa ja cheia
        cheios = [l for l in linhas if l["caixa"] / med_caixa >= LIMIAR_CAIXA]
        melhor = max(cheios or linhas, key=lambda l: l["tile"])

        # ── contato visual: os quadros JA RECORTADOS como a grade recorta
        n = min(9, len(quadros))
        idx = np.linspace(0, len(quadros) - 1, n).astype(int)
        cols = 3
        linhas_n = (n + cols - 1) // cols
        folha = Image.new("RGB", (cols * TILE[0] + (cols + 1) * 8,
                                  linhas_n * TILE[1] + (linhas_n + 1) * 8), (18, 20, 32))
        for k, j in enumerate(idx):
            t = recorte_da_grade(Image.open(quadros[j]).convert("RGB")).resize(TILE, Image.LANCZOS)
            folha.paste(t, (8 + (k % cols) * (TILE[0] + 8), 8 + (k // cols) * (TILE[1] + 8)))
        folha.save(saida / "grade.png")

        recorte_da_grade(Image.open(quadros[melhor["i"]]).convert("RGB")).save(
            saida / "capa-recomendada.png")
        # a capa ATUAL e o quadro 0 REAL, nao o primeiro da serie amostrada
        recorte_da_grade(Image.open(inicio[0]).convert("RGB")).save(saida / "capa-atual.png")

        for f in falhas:
            print(f"  \033[31mFALHA\033[0m {f}")
        if not falhas:
            print("  \033[32mok\033[0m  conteudo dentro do miolo, e o quadro 0 serve de capa")
        else:
            print(f"\n  melhor capa com a caixa cheia: t={melhor['t']:.1f}s")
        print(f"\n  olhe {saida}/grade.png e {saida}/capa-atual.png antes de publicar: "
              f"e o que o perfil mostra.\n")
        return 1 if falhas else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
