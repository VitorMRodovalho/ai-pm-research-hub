"""Gera a derivada `-circ.png`: retrato quadrado COM folga acima da cabeca.

Por que existe. As derivadas de retrato do evento chegam sem headroom: medido em 29/08,
o topo da cabeca fica a 1,00% da altura no Joao e a 1,67% no Rodrigo. Num medalhao
circular isso e fatal, porque `object-fit:cover` num quadrado so mostra a partir de
`object-position Y / 4` da altura da fonte. Com Y=14% a janela comeca em 3,5% e come a
cabeca. Recuar Y para 0 resolve o corte e cria outro problema: a cabeca encosta no apice
do circulo, que e o ponto mais estreito da mascara.

A saida e nao brigar com o enquadramento e sim FABRICAR a folga, estendendo o proprio
fundo do retrato para cima. Como o fundo desses estudios e liso ou um gradiente suave na
horizontal, replicar uma amostra por coluna e imperceptivel.

De quebra conserta a cunha preta que a foto do Rodrigo carrega nos cantos superiores,
resto de alguma transformacao anterior. Ela ficaria visivel dentro do circulo depois que
o conteudo desce.

    python3 preparar_circulo.py            # usa NUCLEO_FOTOS
"""
import pathlib
from PIL import Image
from brand import FOTOS

FOLGA = 0.11          # onde o topo da cabeca deve cair, em fracao do lado do quadrado
BANDA = (2, 14)       # faixa de linhas usada para amostrar o fundo por coluna
ESCURO = 95           # luminancia abaixo disso e cabelo, nao fundo


def _lum(c):
    return .299 * c[0] + .587 * c[1] + .114 * c[2]


def topo_da_cabeca(px, w, h, seguidos=6):
    """Primeira linha com cabelo escuro na faixa central. Exige pixels SEGUIDOS para nao
    confundir ruido, e ignora as bordas para nao pegar cunha de canto."""
    for y in range(h):
        seq = 0
        for x in range(int(w * .32), int(w * .68)):
            seq = seq + 1 if _lum(px[x, y]) < ESCURO else 0
            if seq >= seguidos:
                return y
    return 0


def fundo_por_coluna(px, w):
    """Uma cor de fundo por coluna, mediana da banda do topo, descartando pixel escuro
    (cabelo e cunha preta). Coluna sem amostra valida herda a vizinha, para nao abrir
    buraco onde a cunha cobre a banda inteira."""
    cores = []
    for x in range(w):
        amostras = [px[x, y] for y in range(*BANDA) if _lum(px[x, y]) >= ESCURO]
        cores.append(amostras[len(amostras) // 2] if amostras else None)
    ultima = next((c for c in cores if c), (170, 170, 172))
    for i, c in enumerate(cores):
        if c is None:
            cores[i] = ultima
        else:
            ultima = c
    return cores


def preparar(origem: pathlib.Path, destino: pathlib.Path):
    im = Image.open(origem).convert("RGB")
    w, h = im.size
    px = im.load()

    topo = topo_da_cabeca(px, w, h)
    fundo = fundo_por_coluna(px, w)

    # a cunha escura dos cantos some antes de descer o conteudo, senao ela reaparece
    # dentro do circulo em vez de ficar fora do quadro
    for y in range(0, BANDA[1]):
        for x in range(w):
            if _lum(px[x, y]) < ESCURO and not (int(w * .30) < x < int(w * .70)):
                px[x, y] = fundo[x]

    lado = w                                  # o quadrado do medalhao tem o lado da largura
    alvo = int(lado * FOLGA)                  # onde o topo da cabeca deve cair
    desce = max(0, alvo - topo)

    tela = Image.new("RGB", (w, h + desce))
    for y in range(desce):                    # a folga e o fundo estendido, coluna a coluna
        for x in range(w):
            tela.putpixel((x, y), fundo[x])
    tela.paste(im, (0, desce))

    quad = tela.crop((0, 0, lado, lado))
    quad.save(destino)
    conferido = topo_da_cabeca(quad.load(), lado, lado)
    return topo, desce, conferido / lado * 100


if __name__ == "__main__":
    for nome in ("joao", "rodrigo"):
        o = FOTOS / f"{nome}-3x4.png"
        d = FOTOS / f"{nome}-circ.png"
        topo, desce, agora = preparar(o, d)
        print(f"{nome}: topo estava em {topo}px, desceu {desce}px, "
              f"agora em {agora:.1f}% do quadrado -> {d.name}")
