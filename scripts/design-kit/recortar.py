"""Recorte do sujeito: a pessoa NITIDA sobre o fundo da marca.

Best practice de campanha de evento e o sujeito recortado, sem fade. Fade existe para
ASSENTAR o sujeito, e quando existe e DIRECIONAL, quase sempre so na base. Fade nos
quatro lados apaga o sujeito por todos os lados e produz uma foto lavada.

O recorte usa distancia a cor do fundo amostrada nos CANTOS SUPERIORES (as laterais ja
sao o corpo), com tres refinos que decidem se o resultado presta:

  protecao de pele    vermelho dominante nunca e fundo
  descontaminacao     pixel semitransparente carrega a cor do fundo antigo; sem remover,
                      o contorno do cabelo fica com halo cinza sobre fundo escuro
  fronteira suave     blur curto no alpha, senao o contorno serrilha
"""
import numpy as np
from PIL import Image, ImageFilter


def recortar(entrada, saida, limiar=78, rampa=46, desconta=.85, suavizar=1.6,
             base_fade=0.0):
    im = Image.open(entrada).convert("RGB")
    a = np.asarray(im).astype(float)
    H, W, _ = a.shape

    # ESTIMATIVA DO FUNDO. Quatro tentativas antes desta, e cada falha ensinou algo:
    #   cor unica       nao descreve gradiente; 25% da imagem em franja
    #   faixa superior  a cabeca do Rodrigo comeca no topo do crop, entao a "amostra de
    #                   fundo" da coluna central era CABELO e sobrava coluna cinza opaca
    #   coluna inteira  abaixo de ~55% da altura a lateral ja e terno; franja do Joao 3%->25%
    #   linear esq->dir alisa demais: o fundo do Rodrigo tem FAIXAS VERTICAIS de brilhos
    #                   diferentes, e a reta passava por cima delas deixando listras claras
    # Aqui: perfil POR COLUNA, medido no alto (onde a coluna e fundo), com as colunas
    # contaminadas pela cabeca DESCARTADAS e reconstruidas a partir das vizinhas validas.
    alto = max(8, int(H * .16))
    perfil = np.median(a[:alto], axis=0)                     # (W,3)
    lum = perfil.mean(axis=1)
    # coluna valida = clara o bastante para ser fundo; a cabeca derruba a luminancia
    ref = np.median(lum[np.r_[0:int(W * .12), int(W * .88):W]])
    ok = lum > ref - 34
    if ok.sum() < W * .12:                                   # fundo escuro: nao descarta nada
        ok = np.ones(W, bool)
    idx = np.arange(W)
    perfil = np.stack([np.interp(idx, idx[ok], perfil[ok, c]) for c in range(3)], axis=1)
    k = max(3, W // 60) | 1                                  # alisa so o ruido, nao as faixas
    pad = np.pad(perfil, ((k // 2, k // 2), (0, 0)), mode="edge")
    perfil = np.stack([np.convolve(pad[:, c], np.ones(k) / k, "valid") for c in range(3)], 1)
    cor = perfil[None, :, :]
    d = np.sqrt(((a - cor) ** 2).sum(axis=2))
    fundo = np.clip((limiar - d) / rampa, 0, 1)
    pele = np.clip((a[:, :, 0] - a[:, :, 2] - 8) / 18, 0, 1)
    fundo = fundo * (1 - pele)

    # SEGUNDA PASSADA, por difusao. O perfil por coluna ainda deixava uma faixa clara ao
    # lado da cabeca: aquelas colunas sao contaminadas e a reconstrucao por interpolacao
    # atravessa a cabeca inteira, sem enxergar a faixa. Aqui o fundo ja CONHECIDO (o que a
    # primeira passada classificou com confianca) e PROPAGADO para dentro da regiao da
    # pessoa por difusao, o que preserva estrutura vertical em vez de alisar.
    conhecido = fundo > .85
    if conhecido.mean() > .04:
        esc = 8
        pe = (H // esc, W // esc)
        red = np.stack([np.asarray(Image.fromarray(a[:, :, c].astype(np.uint8))
                                   .resize((pe[1], pe[0]), Image.BOX)) for c in range(3)], -1).astype(float)
        mk = np.asarray(Image.fromarray((conhecido * 255).astype(np.uint8))
                        .resize((pe[1], pe[0]), Image.BOX)).astype(float) / 255 > .5
        est = red.copy()
        est[~mk] = np.nan
        for _ in range(220):
            pad = np.pad(est, ((1, 1), (1, 1), (0, 0)), mode="edge")
            viz = np.nanmean(np.stack([pad[:-2, 1:-1], pad[2:, 1:-1],
                                       pad[1:-1, :-2], pad[1:-1, 2:]]), axis=0)
            est = np.where(mk[:, :, None], red, viz)
        est = np.nan_to_num(est, nan=float(np.nanmedian(red)))
        cor2 = np.stack([np.asarray(Image.fromarray(est[:, :, c].astype(np.uint8))
                                    .resize((W, H), Image.BICUBIC)) for c in range(3)], -1).astype(float)
        cor = cor2
        d = np.sqrt(((a - cor) ** 2).sum(axis=2))
        fundo = np.clip((limiar - d) / rampa, 0, 1) * (1 - pele)

    al = 1 - fundo
    # CORTE do alpha baixo. Um veu de 2 a 8% e invisivel no retrato isolado e vira uma
    # CAIXA quando a peca reduz a foto (900px -> 346px no linkedin): o downscale espalha o
    # semitransparente e o retangulo aparece atenuando o grid do fundo. Medido pela
    # diferenca entre a peca com e sem as fotos: 3,77 de residuo nas laterais.
    # A rampa preserva o contorno do cabelo; o piso zera o veu.
    al = np.clip((al - .10) / .82, 0, 1)
    al = np.asarray(Image.fromarray((al * 255).astype(np.uint8))
                    .filter(ImageFilter.GaussianBlur(suavizar))).astype(float) / 255

    # descontaminacao: onde o pixel e parcialmente transparente ele mistura a cor do
    # fundo antigo. remove essa contribuicao para o contorno nao ficar com halo.
    with np.errstate(divide="ignore", invalid="ignore"):
        limpo = (a - (1 - al)[:, :, None] * cor) / np.clip(al, .02, 1)[:, :, None]
    a = a * (1 - desconta) + np.clip(limpo, 0, 255) * desconta

    if base_fade > 0:                      # fade DIRECIONAL, so na base, se pedido
        y = np.linspace(0, 1, H)[:, None]
        al = al * np.clip((1 - y) / base_fade, 0, 1)

    Image.fromarray(np.dstack([np.clip(a, 0, 255), al * 255]).astype(np.uint8),
                    "RGBA").save(saida)
    return al


if __name__ == "__main__":
    import sys, pathlib
    base = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".") / "fotos"
    # o limiar e POR FOTO: depende de como o fundo do estudio foi iluminado.
    # foto nova de palestrante quase sempre pede ajuste aqui.
    for n, kw in (("joao", dict(limiar=76, rampa=42)),
                  ("rodrigo", dict(limiar=92, rampa=64))):
        al = recortar(base / f"{n}-3x4.png", base / f"{n}-cut.png", **kw)
        franja = ((al > .05) & (al < .95)).mean()
        print(f"{n:8s} sujeito={al.mean()*100:5.1f}%  franja={franja*100:.2f}%"
              f"   {'ok' if franja < .06 else 'ATENCAO: franja alta, ajuste limiar/rampa'}")
