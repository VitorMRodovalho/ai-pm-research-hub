# Pitch Executivo — Núcleo IA & GP (marca PMIGO)

Deck executivo (~15 slides, 1 ideia por slide) para board do PMI / presidentes de capítulo /
parceiros de vertical. Construído com a skill `branded-deck-build`: clona o template PMI oficial
e injeta conteúdo por nome de shape, preservando a marca byte a byte.

## Como reconstruir

```bash
~/.venvs/pmo/bin/python gen_assets.py        # gera o diagrama hub-and-spoke (assets/hub_spoke.png)
~/.venvs/pmo/bin/python build_nucleo_deck.py # pptx -> PDF -> preview PNGs num run só (QA não envelhece)
```

Saídas:
- `Nucleo_IA_GP_Pitch_Executivo.pptx` — nativamente editável no PowerPoint
- `Nucleo_IA_GP_Pitch_Executivo.pdf` + `preview/slide-*.png` + `preview/contact_sheet.png` (QA visual)

O deck é uma função de `(template, specs)`: toda edição vai no `build_nucleo_deck.py`, nunca no
`.pptx` de saída (senão a reprodutibilidade quebra). Guards no build falham se houver em-dash,
overflow de canvas, boilerplate sobrevivente ou linha divisória cruzando conteúdo.

## Fonte do conteúdo (sem pesquisa nova — é transposição)

- `../verticals_x_quadrants_model.md` — o fio, modelo de 3 eixos, §1.1 "PMI absorvendo os silos"
- `../vertical_pitch_kit.md` — 1 slide por vertical (números ESG conferidos: 55% vs 33% etc.)
- `../cycle4_landing_value_prop.md` — cobertura Brasil+LatAm, chamada de protagonistas
- `deck_outline.md` (no diretório-pai `../`) — mapa slide-a-slide

## Slide "O pedido" = swap-set por audiência (slides 12, 13, 14)

O deck contém as **3 variações** do pedido; apresente a que casa com a plateia e oculte/exclua as
outras duas:
- **12 — Board PMI** (Mario Trentim): endorsement estratégico + Núcleo como leitura prática de PMI:Next / M.O.R.E.
- **13 — Presidentes de capítulo**: adesão, indicação de protagonistas, validação do discurso.
- **14 — Parceiros de vertical** (GPM / Construction Ambassadors / PMOGA): co-curadoria + acesso à comunidade.

## Check de marca (gate humano antes de externalizar ao board)

O rodapé da capa traz a frase de atribuição de marcas PMI. **Antes de enviar ao board**, validar com
as diretrizes de marca de capítulo vigentes: uso do logo PMIGO, wording da atribuição e cores. Isto é
um gate humano — não foi verificado contra a versão atual do brand book do PMI.

## Assets (fora do git)

`build/pmi_template.pptx` (18 MB, marca PMI) e os renders ficam no `.gitignore` — não versionar
template/​logos/​PDF (guardrail da skill). O logo PMIGO vem de `19SGPL-PMIGO/MKT/`.
