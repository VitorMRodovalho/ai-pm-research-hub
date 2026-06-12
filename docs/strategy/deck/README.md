# Pitch Executivo — Núcleo IA & GP (marca PMIGO)

Deck executivo (~15 slides, 1 ideia por slide) para board do PMI / presidentes de capítulo /
parceiros de vertical. Construído com a skill `branded-deck-build`: clona o template PMI oficial
e injeta conteúdo por nome de shape, preservando a marca byte a byte.

## Arquitetura (engine compartilhado + conteúdo por idioma)

Três arquivos, responsabilidade separada. Adicionar um idioma = **só um dict** novo em
`deck_content.py` + uma linha em `EDITIONS` no `build.py`. Nada de duplicar engine ou layout.

| Arquivo | Responsabilidade |
|---------|------------------|
| `deck_engine.py` | Engine genérico (classe `Deck`): clone/inject por shape, caixas/tabelas/imagem/seta, guards, render. Agnóstico de conteúdo e idioma. |
| `deck_content.py` | Só as **strings**, por idioma (`CONTENT["pt"]`, `CONTENT["en"]`, ...). Cores e posições não ficam aqui. |
| `build.py` | O **layout** dos 15 slides (uma vez só) + orquestra as edições. |
| `gen_assets.py` | Gera os diagramas hub-and-spoke (um por idioma). |

O **nome do Núcleo é bilíngue**: "Núcleo IA & GP" é preservado como marca em todas as edições
(capa, centro do diagrama, corpo); a edição EN glosa na capa como "AI & PM Study and Research Hub".

| Edição | Saída | Diagrama |
|--------|-------|----------|
| PT-BR | `Nucleo_IA_GP_Pitch_Executivo.pptx` | `assets/hub_spoke.png` |
| EN-US | `Nucleo_IA_GP_Pitch_Executive_EN.pptx` | `assets/hub_spoke_en.png` |

## Como reconstruir

```bash
~/.venvs/pmo/bin/python gen_assets.py     # diagramas hub-and-spoke (PT + EN)
~/.venvs/pmo/bin/python build.py          # todas as edições (pt, en)
~/.venvs/pmo/bin/python build.py en       # só uma edição
```

Saídas por edição: o `.pptx` (nativamente editável no PowerPoint) + `.pdf` + `preview*/slide-*.png`.

O deck é uma função de `(template, content)`: toda edição vai em `deck_content.py`/`build.py`, nunca
no `.pptx` de saída (senão a reprodutibilidade quebra). Guards falham o build se houver em-dash,
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
