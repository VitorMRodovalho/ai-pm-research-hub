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

import numpy as np
from PIL import Image, ImageFilter

from brand import FOTOS

FOLGA = 0.11          # onde o topo da cabeca deve cair, em fracao do lado do quadrado
BANDA = (2, 14)       # faixa de linhas usada para amostrar o fundo por coluna
ESCURO = 95           # luminancia abaixo disso e cabelo, nao fundo

# NORMALIZACAO DO FUNDO (autorizada pelo dono em 29/08/2026). Lado a lado num medalhao
# pequeno a diferenca de fundo entre os dois retratos passava. No retangulo grande, que
# mostra 27% mais fundo, viram dois cinzas diferentes colados. Por isso a correcao entrou
# junto com a escolha do retangulo.
#
# O QUE FOI MEDIDO, e a medicao que eu errei primeiro. Perfilando so a faixa ESQUERDA por
# altura, os dois fundos parecem planos: Joao 172, Rodrigo 134,146,156 do topo ao ombro.
# Dai eu concluiria um offset constante. Errado: comparando esquerda com DIREITA, o fundo
# do Rodrigo vai de (134,146,156) a (192,197,199), 51 niveis de gradiente HORIZONTAL,
# enquanto o do Joao e chapado nos dois lados. Perfilar um eixo so nao mede planura.
# Por isso a correcao e POR COLUNA, nao por cor unica: uma cor unica acertaria a media e
# deixaria as duas pontas erradas, uma clara demais e outra escura demais.
#
# A correcao mexe SO NO FUNDO, por mascara de distancia. Duas alternativas globais foram
# descartadas por contas feitas antes de escrever isto:
#   ganho global      preserva preto mas estoura o realce: o p99 do Rodrigo esta em 209 e
#                     o ganho no vermelho o jogaria acima de 255.
#   gamma global      nao estoura, mas levanta a sombra: a camiseta preta dele sairia de
#                     ~25 para ~61, virando cinza morno. E a pessoa, nao o fundo.
ALVO_FUNDO = (171, 171, 173)   # neutro, onde o fundo do Joao ja estava
TOL, RAMPA = 30, 30            # distancia ate a cor da COLUNA: dentro de TOL corrige 100%


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


def perfil_do_fundo(a):
    """Uma cor de fundo POR COLUNA, medida no terco superior, onde ainda nao ha ombro.

    Mediana e nao media, para um fio de cabelo que escape do descarte nao mover a amostra.
    Coluna tomada pela cabeca fica sem amostra suficiente e e reconstruida por
    interpolacao das vizinhas validas; no fim um alisamento curto tira o ruido sem tirar
    o gradiente, que aqui e o sinal, nao o ruido."""
    H, W, _ = a.shape
    alto = a[int(H * .02):int(H * .45)]
    # Descarta escuro (cabelo, cunha preta do canto) E PELE. O filtro de luminancia sozinho
    # nao basta: pele e CLARA, entao as colunas do rosto passavam por fundo valido e
    # puxavam o ajuste para o rosado. Medido: com elas dentro, o fundo do Joao saia
    # (177,158,157) em vez de neutro.
    val = (alto.mean(axis=2) >= ESCURO) & ((alto[:, :, 0] - alto[:, :, 2]) < 8)
    perfil = np.full((W, 3), np.nan)
    minimo = alto.shape[0] * .25
    # O dominio do ajuste sao as colunas LATERAIS, que sao fundo em toda a altura da banda.
    # A pessoa ocupa o miolo; ali o valor e extrapolado, e e justamente onde ela cobre.
    margem = int(W * .25)
    for x in list(range(margem)) + list(range(W - margem, W)):
        col = alto[val[:, x], x]
        if len(col) >= minimo:
            perfil[x] = np.median(col, axis=0)
    ok = ~np.isnan(perfil[:, 0])
    if ok.sum() < 8:
        return np.tile(np.array(ALVO_FUNDO, float), (W, 1))
    idx = np.arange(W, dtype=float)
    # AJUSTE POLINOMIAL, e nao interpolacao mais alisamento. A primeira versao interpolava
    # coluna a coluna e alisava com janela curta: no Rodrigo funcionou, mas no Joao, cujo
    # fundo ja estava certo e o deslocamento e de ~1 nivel, o RUIDO do perfil virou LISTRA
    # VERTICAL na peca, porque cada coluna recebeu um deslocamento ligeiramente diferente.
    # Iluminacao de estudio e um campo suave e de baixa frequencia: um polinomio de grau 2
    # descreve o gradiente e, por construcao, nao consegue produzir listra. Grau 1, nao 2:
    # com o dominio limitado as laterais, grau 2 fica sub-determinado no miolo e oscila.
    return np.stack([np.polyval(np.polyfit(idx[ok], perfil[ok, c], 1), idx)
                     for c in range(3)], axis=1)


def normalizar_fundo(im: Image.Image, alvo=ALVO_FUNDO):
    """Leva o FUNDO para `alvo` e deixa a pessoa intacta.

    O deslocamento e o mesmo para todo pixel de fundo, entao a textura e o ruido do estudio
    sobrevivem: nao e pintar por cima, e transladar. A mascara vem da distancia ate a cor
    amostrada, com rampa e um blur curto para o contorno do cabelo nao serrilhar, e com a
    protecao de pele do `recortar.py`, porque vermelho dominante nunca e fundo.
    """
    a = np.asarray(im).astype(float)
    perfil = perfil_do_fundo(a)                 # (W,3)
    cor = perfil[None, :, :]                    # difunde por linha
    delta = np.array(alvo, float)[None, None, :] - cor

    d = np.sqrt(((a - cor) ** 2).sum(axis=2))
    m = np.clip((TOL + RAMPA - d) / RAMPA, 0, 1)
    pele = np.clip((a[:, :, 0] - a[:, :, 2] - 8) / 18, 0, 1)
    m = m * (1 - pele)
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8))
                   .filter(ImageFilter.GaussianBlur(1.4))).astype(float) / 255

    fora = np.clip(a + m[:, :, None] * delta, 0, 255)
    return (Image.fromarray(fora.astype(np.uint8)),
            perfil[0], perfil[-1], m.mean())


def preparar(origem: pathlib.Path, destino: pathlib.Path):
    im = Image.open(origem).convert("RGB")
    # A normalizacao vem ANTES de fabricar a folga, e a ordem importa: rodando depois, ela
    # mediria a PROPRIA folga em vez do fundo real. No Rodrigo isso dava 176 no lugar de
    # 145, porque a folga nasce de uma amostra das linhas 2 a 14, que nos cantos dele caem
    # dentro da cunha preta e sao descartadas. Antes, a folga ja nasce da cor corrigida e
    # emenda nenhuma aparece.
    im, borda_esq, borda_dir, cobertura = normalizar_fundo(im)
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
    return topo, desce, conferido / lado * 100, borda_esq, borda_dir, cobertura


if __name__ == "__main__":
    for nome in ("joao", "rodrigo"):
        o = FOTOS / f"{nome}-3x4.png"
        d = FOTOS / f"{nome}-circ.png"
        topo, desce, agora, esq, dir_, cob = preparar(o, d)
        print(f"{nome}: topo estava em {topo}px, desceu {desce}px, "
              f"agora em {agora:.1f}% do quadrado -> {d.name}")
        print(f"    fundo medido: coluna 0 {esq.round(0).astype(int)}, "
              f"ultima coluna {dir_.round(0).astype(int)} "
              f"(gradiente de {dir_.mean()-esq.mean():+.0f} niveis) -> alvo {ALVO_FUNDO}; "
              f"{cob*100:.0f}% do quadro tratado como fundo")
