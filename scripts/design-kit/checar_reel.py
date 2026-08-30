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

LIMITE, dito de frente: isto NAO le texto. Mede DETALHE (variancia de Laplaciano) por
faixa. Detalhe na faixa cortada quer dizer "tem coisa ai que vai ser decepada", nao
"tem texto ai". Para capa, mede detalhe dentro do tile e ordena. As duas medidas
respondem bem as perguntas da #2068, e nenhuma delas substitui olhar o `grade.png`.
"""
import argparse, json, pathlib, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image

FAIXA = 0.125          # a grade corta isto em cima e embaixo
TILE = (242, 322)      # medido no perfil


def _run(*a):
    return subprocess.run(a, capture_output=True, text=True, check=True).stdout


def sonda(video):
    d = json.loads(_run("ffprobe", "-v", "error", "-select_streams", "v:0",
                        "-show_entries", "stream=width,height:format=duration",
                        "-of", "json", str(video)))
    s = d["streams"][0]
    return int(s["width"]), int(s["height"]), float(d["format"]["duration"])


def detalhe(a):
    """Variancia do Laplaciano: alto onde ha borda, baixo em area chapada."""
    g = np.asarray(Image.fromarray(a).convert("L"), dtype=float)
    if g.size == 0:
        return 0.0
    lap = (-4 * g[1:-1, 1:-1] + g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:])
    return float(lap.var())


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
    W, H, dur = sonda(video)
    saida = pathlib.Path(args.saida or video.with_suffix("").name + "-grade")
    saida.mkdir(parents=True, exist_ok=True)

    tmp = pathlib.Path(tempfile.mkdtemp())
    try:
        _run("ffmpeg", "-v", "error", "-i", str(video), "-vf",
             f"fps=1/{args.passo}", "-q:v", "2", str(tmp / "q%04d.jpg"))
        quadros = sorted(tmp.glob("q*.jpg"))
        if not quadros:
            sys.exit("ffmpeg nao extraiu quadro nenhum")

        topo_h = int(H * FAIXA)
        linhas = []
        for i, q in enumerate(quadros):
            im = Image.open(q).convert("RGB")
            a = np.asarray(im)
            linhas.append({
                "t": i * args.passo,
                "topo": detalhe(a[:topo_h]),
                "base": detalhe(a[H - topo_h:]),
                "miolo": detalhe(a[topo_h:H - topo_h]),
                "tile": detalhe(np.asarray(recorte_da_grade(im))),
            })

        print(f"\n{video.name}  {W}x{H}  razao {W/H:.3f}  {dur:.1f}s"
              f"  ({len(quadros)} quadros a cada {args.passo}s)")
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

        # ── defeito 2: a capa padrao (primeiro quadro) e pobre
        melhor = max(linhas, key=lambda l: l["tile"])
        primeiro = linhas[0]
        pos = sum(1 for l in linhas if l["tile"] <= primeiro["tile"]) / len(linhas)
        if primeiro["tile"] < melhor["tile"] * .55:
            falhas.append(
                f"capa padrao pobre: o 1o quadro tem {primeiro['tile']/melhor['tile']*100:.0f}% "
                f"do detalhe do melhor (percentil {pos*100:.0f}). "
                f"Defina a capa a mao em t={melhor['t']:.1f}s")

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

        capa = recorte_da_grade(Image.open(quadros[min(range(len(linhas)),
                key=lambda i: -linhas[i]["tile"])]).convert("RGB"))
        capa.save(saida / "capa-recomendada.png")
        recorte_da_grade(Image.open(quadros[0]).convert("RGB")).save(saida / "capa-atual.png")

        for f in falhas:
            print(f"  \033[31mFALHA\033[0m {f}")
        if not falhas:
            print("  \033[32mok\033[0m  conteudo dentro do miolo, e o primeiro quadro serve de capa")
        print(f"\n  olhe {saida}/grade.png antes de publicar: e o que o perfil mostra.\n")
        return 1 if falhas else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
