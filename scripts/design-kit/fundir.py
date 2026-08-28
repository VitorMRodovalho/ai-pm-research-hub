"""Retrato que DISSOLVE na peca, em vez de terminar num corte duro.

Duas operacoes independentes, e as duas sao necessarias:

  tom    o fundo de ESTUDIO e puxado para o fundo da PECA. Sem isso, dissolver so revela
         um retangulo cinza claro flutuando atras da cabeca.
  alpha  as bordas do retrato somem em rampa, para nao existir aresta em lugar nenhum.

O discriminador do fundo e a DISTANCIA a cor amostrada nos cantos SUPERIORES, nunca
"neutro e claro": esse criterio tambem pegaria uma camisa branca. Amostrar as quatro
bordas tambem nao serve, porque as laterais ja sao o terno (foi o que fez a primeira
medicao dizer que o fundo nao era recortavel).
"""
import numpy as np
from PIL import Image, ImageFilter

FUNDO_PECA = np.array([13, 16, 48], float)


def fundir(entrada, saida, limiar=80, rampa=55, tom=.92, dessat=.22,
           base=.40, lados=.15, topo=.09):
    im = Image.open(entrada).convert("RGB")
    a = np.asarray(im).astype(float)
    H, W, _ = a.shape

    cantos = np.concatenate([a[0:60, 0:90].reshape(-1, 3), a[0:60, -90:].reshape(-1, 3)])
    cor = cantos.mean(axis=0)
    d = np.sqrt(((a - cor) ** 2).sum(axis=2))
    peso = np.clip((limiar - d) / rampa, 0, 1)          # 1 = fundo, 0 = pessoa
    # PROTECAO DE PELE: tom de pele tem vermelho dominante; o fundo cinza-azulado do
    # estudio nao tem. Sem isso, o limiar mais alto necessario para o fundo com gradiente
    # alcanca o rosto e ele sai azulado, que foi exatamente o que aconteceu.
    pele = np.clip((a[:, :, 0] - a[:, :, 2] - 8) / 18, 0, 1)
    peso = peso * (1 - pele)
    # suaviza a fronteira para nao serrilhar o contorno do cabelo
    peso = np.asarray(Image.fromarray((peso * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(2.5))).astype(float) / 255

    cinza = a.mean(axis=2, keepdims=True)
    a = a * (1 - dessat) + cinza * dessat
    k = (peso * tom)[:, :, None]
    a = a * (1 - k) + FUNDO_PECA * k

    y = np.linspace(0, 1, H)[:, None]
    x = np.linspace(0, 1, W)[None, :]
    r = lambda t, l: np.clip(t / l, 0, 1)
    al = r(1 - y, base) * r(y, topo) * r(x, lados) * r(1 - x, lados)
    al = al ** 1.3
    al = np.minimum(al, 1 - peso * .55)   # o proprio fundo tambem fica mais transparente

    Image.fromarray(np.dstack([np.clip(a, 0, 255), al * 255]).astype(np.uint8),
                    "RGBA").save(saida)
    return peso.mean()


if __name__ == "__main__":
    import sys, pathlib
    base = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "fotos"
    for n, kw in (("joao", dict(limiar=78, rampa=50)),
                  ("rodrigo", dict(limiar=95, rampa=70))):
        f = fundir(base / f"{n}-3x4.png", base / f"{n}-fade.png", **kw)
        print(f"{n:8s} fracao tratada como fundo: {f*100:.1f}%")
