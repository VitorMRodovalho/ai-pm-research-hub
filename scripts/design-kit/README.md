# design-kit — toolchain de peças gráficas do Núcleo IA & GP

Gera as peças de divulgação (Instagram, LinkedIn, stories, cards) e as telas de evento do Airmeet,
a partir de HTML renderizado por Chrome headless. Reproduz **byte-idêntico**: a mesma entrada gera o
mesmo PNG, o que torna verificável a afirmação "esta peça veio deste gerador".

## Por que isto está versionado (#1523)

Antes de 29/07/2026 a toolchain vivia em scratchpad de sessão, efêmero, com três cópias divergentes.
O que existia versionado era `build_lounge_banner.py` dentro de `.claude/skills/airmeet-event-ops/`,
e **ele não rodava**: importava `brand.py` e `kit/logo-512.png`, nenhum dos dois presente ali. Uma
cópia versionada que não executa é pior que ausência, porque parece cobertura.

Medição que definiu o escopo: dos 13 assets do kit-mídia (15 MB), apenas **2 são lidos em runtime**
(658 KB). Os outros 11 foram fonte de amostragem de cor, consumida uma vez; a paleta já está literal
em `brand.py`.

## O que está aqui

| arquivo | o quê |
| --- | --- |
| `brand.py` | base da marca: paleta amostrada dos assets reais, CSS comum, render por Chrome, retrato circular |
| `qa_measure.py` | mede geometria real via `getBoundingClientRect` **e o ink do texto** (`Range`) |
| `kit/` | os 2 assets lidos em runtime: faixa institucional e logo |
| `build_t6_divulgacao.py` | post 1080x1350, story 1080x1920, LinkedIn 1200x627, 2 cards 1200x1500 |
| `build_t6_story_comeca_agora.py` | story do dia do evento, 2 variantes de CTA |
| `build_airmeet_t6.py` | as 4 telas do Airmeet (banner, recepção, palco, boas-vindas) |
| `build_lounge_banner.py` | lounge banner 960x120 (a razão em que a faixa institucional não cabe) |

Os `build_t6_*` são do webinar de 04/08/2026. Servem como **template da próxima edição**: copie,
troque os dados no topo, rode.

## O que NÃO está aqui, e por quê

**Retratos de palestrante.** São entrada por evento, não toolchain, e este repositório é público —
são fotos de pessoas, várias externas. Passe a pasta por variável de ambiente:

```bash
NUCLEO_FOTOS=/caminho/para/retratos python3 build_t6_divulgacao.py
```

Sem ela, só rodam os geradores que não usam retrato (`build_lounge_banner.py`).

**Os outros 11 assets do kit-mídia.** Não são lidos em runtime. O SSOT da marca continua sendo a
pasta do Drive `1P6VYGO3nyPKfPiVDuKlKUGixd5i3OzA6`; nunca reconstrua a marca de memória.

## Uso

```bash
cd scripts/design-kit
NUCLEO_FOTOS=... python3 build_t6_story_comeca_agora.py   # escreve em ./out (git-ignorado)
```

Requer `google-chrome-stable` e as fontes Inter Display em
`/usr/share/fonts/opentype/inter/` (`InterDisplay-Black.otf`, `InterDisplay-Bold.otf`).

## A regra de QA: medir o ink, não a caixa

Colisão de texto se prova por número, não a olho. `qa_measure.rects()` devolve, para cada folha de
texto, a caixa **e** o retângulo real da tinta — a caixa `.pn` de um nome pode ter 526 px de largura
com o texto ocupando só 410, e é o segundo que colide.

Dois erros reais que só a medição pegou:

- **story de divulgação (26/07):** ampliar o retrato de 200 para 270 px empurrou a coluna de texto até
  x≈970, e a esfera ciano de `right/top` fixos caiu por cima de "Fernando Carvalho";
- **story "começa agora" (29/07):** o CTA terminava em y=1670 **exatos**, o limite da zona segura do
  story. Passa no render e pode ser comido pela barra de resposta no aparelho. A zona segura do
  Instagram Stories é ~250 px em cima e embaixo; deixe folga real.

Regra do PMO que vale para toda peça: **sem travessão longo nem en-dash.**
