# Peças do 1º Webinar da Tribo PMO Inteligente

**8 de setembro de 2026, 20h.** Este pacote contém tudo para gerar e alterar as peças
deste webinar: a toolchain, os assets de marca, os retratos já tratados e as peças prontas.

As peças são geradas a partir de **HTML renderizado por Chrome headless**. A vantagem é que
a mesma entrada gera sempre o mesmo PNG, então dá para versionar a *receita* em vez do
arquivo final, e a alteração é feita editando CSS, não arrastando caixa.

---

## Comece por aqui

```bash
python3 verificar.py     # diz o que falta e como resolver
./gerar.sh               # gera tudo em ./out
python3 checar.py        # roda as nove checagens depois que voce alterar algo
```

`verificar.py` existe por um motivo específico: **fonte ausente não dá erro**. O Chrome
substitui por outra e a peça sai com a tipografia errada, em silêncio. Rode antes.

Se as fontes estiverem faltando:

```bash
sudo mkdir -p /usr/share/fonts/opentype/inter
sudo cp fontes/*.otf /usr/share/fonts/opentype/inter/
```

---

## O que tem aqui

| pasta / arquivo | o quê |
| --- | --- |
| `build_t11_campanha_final.py` | **as três direções** (v3, v5, v6) nos três formatos |
| `build_t11_airmeet.py` | as cinco telas do Airmeet, já publicadas no evento |
| `build_t11_campanha.py` | copy, escala tipográfica e paleta compartilhadas |
| `brand.py` | base da marca: cores amostradas dos assets reais, CSS comum, render |
| `recortar.py` | recorta o fundo do retrato (usado pela v6) |
| `fundir.py` | dissolve o retrato no fundo por alpha (usado pela v5) |
| `checar.py` | roda as nove checagens sobre o que você gerou |
| `verificar.py` | confere as dependências antes de gerar |
| `qa_measure.py`, `_qa_contraste.py` | o motor das checagens |
| `kit/` | os dois assets lidos em runtime: faixa institucional e logo |
| `fotos/` | retratos: originais e todos os derivados |
| `pecas/` | as 14 peças já geradas, para referência |
| `fontes/` | Inter Display (OFL-1.1, redistribuível) |

---

## As três direções

O que muda entre elas é **só o tratamento do retrato**. Copy, escala e paleta são idênticas.

- **v3, moldura** — retrato em card de canto arredondado, em escada. Não depende de recorte:
  qualquer foto entra, inclusive de fundo bagunçado.
- **v5, fusão** — mesma escada, sem moldura: o retrato dissolve no fundo por transparência.
- **v6, recorte** — os dois nítidos, recortados, ancorados na base. Exige foto com fundo
  tratável.

Para gerar só uma:

```python
import build_t11_campanha_final as C
C.story("v6"); C.post("v6"); C.linkedin("v6")
```

---

## Mexer no conteúdo

Quase tudo o que se quer mudar está no topo de `build_t11_campanha.py`:

```python
TITULO_A = "Sua área entrega bem."          # a premissa, em corpo de texto
TITULO_B = "Isso garante que ela continue existindo?"   # a virada, em display
SUB      = "Como fazer stakeholders enxergarem..."
QUANDO_CURTO = "8 de setembro · 20h"
DUO = [...]                                  # nome e cargo de cada palestrante
```

**A ordem de `DUO` é a ordem nas peças.** Quem conduz vem primeiro.

---

## Mexer na escala (leia antes de mudar tamanho de fonte)

Os corpos **não são valores absolutos**. São fração da menor dimensão da peça, em
`build_t11_campanha.py`:

```python
PISO_TEXTO = 0.026            # piso de legibilidade, cobrado pelo guard
ESCALA = {
    "story":    dict(micro=.026, corpo=.030, dest=.044, prem=.050, virada=.120, rt=.300),
    ...
}
```

Isso existe porque a versão anterior tinha texto a **1,4%** da menor dimensão, o que vira
corpo de uns 5 px reais na tela do celular: existe no arquivo, não existe para o leitor.
Mexer na fração muda todos os formatos de uma vez e mantém a proporção.

---

## Foto nova de palestrante

1. Coloque a original em `fotos/` e gere o corte 3:4 (900 × 1200), com a cabeça no terço
   superior.
2. Rode `python3 recortar.py .` e `python3 fundir.py .` para gerar os derivados.
3. **Confira a franja** que o `recortar.py` imprime. Acima de 6% o recorte não presta e o
   parâmetro precisa de ajuste.

O `limiar` é **por foto**, porque depende de como o fundo do estúdio foi iluminado. Foto de
fundo liso recorta quase sozinha; fundo com gradiente ou com painéis exige limiar maior.
Se a foto não permitir recorte, use a **v3**, que não depende dele.

---

## As nove checagens automáticas

Cada uma nasceu de um defeito real que passou despercebido:

| checagem | o defeito que ela pega |
| --- | --- |
| piso de corpo e de retrato | texto pequeno demais para tela de celular |
| contraste real, medido no PNG | legenda sobre camisa clara, ilegível |
| foto sobre o bloco de texto | retrato cobrindo o CTA e a data |
| transbordo do canvas | texto saindo da peça |
| texto contra texto | blocos sobrepostos |
| presença dos dois no canvas | palestrante fora do enquadramento |
| chave literal de CSS | f-string esquecida, regra descartada em silêncio |
| cobertura do guard | elemento que o guard não enxerga, e passa verde por vácuo |
| resíduo do recorte | véu de alpha que vira caixa quando a peça reduz a foto |

> As duas últimas são as mais importantes de entender: um guard pode passar verde **porque
> não está olhando**. A de cobertura conta quantas imagens existem no HTML e reprova se não
> tiver visto todas.

---

## Uma nota sobre os retratos

As fotos das pessoas **não são versionadas no repositório**, que é público. Elas vivem fora
dele e entram por variável de ambiente. Se você levar este material para um repositório,
mantenha `fotos/` fora do controle de versão.
