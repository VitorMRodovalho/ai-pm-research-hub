# Auditoria — cards de tribo fora da visão do portfólio (2026-08-20)

**Escopo:** todos os quadros de iniciativas `kind = 'research_tribe'` (14 tribos, 15
quadros — T3 e o "Notion Backlog - Tribo 8" estão vazios), cards não arquivados.
**Fonte:** `audit_portfolio_flag_tag_gaps()` (migration `20260820215416`), executada
contra produção em 2026-08-20. Os quadros estavam sendo editados durante a auditoria
— duas coletas com 10 min de diferença já divergiram em 3 cards. **Os números abaixo
são um retrato daquele instante; re-rode o script antes de citá-los.**

## Por que esses cards somem do /admin/portfolio

O dashboard (`get_portfolio_dashboard`) só considera `board_items` com
`is_portfolio_item = true`. E o filtro "Todos os Tipos" (bloco `by_type`) só enxerga
os que carregam uma tag `tier='system' AND domain='board_item'` — as sete do catálogo:
`publicacao`, `framework`, `poc`, `ferramenta`, `webinar`, `workshop_artifact`,
`pesquisa`. Faltando qualquer uma das duas coisas, o entregável existe no quadro da
tribo e não existe no portfólio.

## Retrato

| Métrica | Valor |
| --- | ---: |
| Cards de tribo não arquivados | 181 |
| Marcados como item de portfólio | 61 |
| **Gap A** — entregável sem o flag | **67** |
| ↳ com data-base pactuada ou entrega registrada (confiança alta) | 34 |
| **Gap B** — item de portfólio sem tag de tipo | **30** |
| Itens com flag mas fora do ciclo consultado pelo dashboard | 0 |

Duas leituras que mudam a prioridade:

- **`entregavel_lider` não é o problema.** Os 31 cards com a tag "Entregável do Líder"
  estão todos com o flag ligado. O que escapou foi o trabalho que nasceu *depois* da
  pactuação do Ciclo 3 — sprints, artigos, webinars criados ao longo do ciclo.
- **O gap se concentra em poucas tribos.** T5 (14 de 17 cards), T11 (18 de 27) e T8
  (8 de 23) respondem por 40 dos 67. T5 e T11 planejaram o ciclo inteiro em sprints
  com data-base, e nenhum sprint foi marcado como entregável — é omissão sistemática
  de processo, não card a card.

### Por tribo

| Tribo | Iniciativa | Cards | Com flag | Gap A | Gap B |
| --- | --- | ---: | ---: | ---: | ---: |
| T1 | Radar Tecnológico | 15 | 3 | 6 | 1 |
| T2 | Agentes Autônomos | 10 | 3 | 6 | 0 |
| T4 | Cultura & Change | 27 | 16 | 4 | 7 |
| T5 | Talentos & Upskilling | 17 | 1 | 14 | 1 |
| T6 | ROI & Portfólio | 12 | 11 | 1 | 7 |
| T7 | Governança & Trustworthy AI | 14 | 10 | 1 | 2 |
| T8 | Inclusão & Colaboração & Comunicação | 23 | 11 | 8 | 6 |
| T9 | IA em Projetos & Ind. da Construção | 6 | 1 | 1 | 1 |
| T10 | Governança Assistida | 7 | 1 | 2 | 1 |
| T11 | PMO Inteligente | 27 | 1 | 18 | 1 |
| T12 | Produtividade Aumentada | 5 | 1 | 1 | 1 |
| T13 | Dados em Projetos de IA | 6 | 1 | 3 | 1 |
| T14 | Fluência em IA | 12 | 1 | 2 | 1 |

## Como ler a coluna "confiança" (Gap A)

- **alta** — o card tem data-base pactuada **ou** entrega registrada. Já é tratado
  como entregável em tudo, menos no flag. É aqui que a correção é quase mecânica.
- **media** — só previsão (forecast), sem base nem entrega.
- **baixa** — nenhuma data; apenas o título/tags sugerem artefato. Muitos são cards
  de alocação individual ("Pesquisa de Services — <nome>"), que provavelmente devem
  continuar fora do portfólio: são tarefas de contribuinte, não entregáveis da tribo.
  **Decisão do líder, não da heurística.**

## Gap A — entregáveis sem flag de portfólio (67)

| Conf. | Tribo | Card | Status | Base | Entregue | Tipo sugerido |
| --- | --- | --- | --- | --- | --- | --- |
| alta | T1 | Confeccção Ebook - Cartilha | done | — | 2026-08-13 | publicacao |
| alta | T1 | Preparação apresentação Ebook Cartilha | done | — | 2026-08-13 | publicacao |
| alta | T1 | Relatório - PMI Infinity | done | — | 2026-07-20 | publicacao |
| alta | T5 | SPRINT 1  - Problema de Pesquisa Formal | in_progress | 2026-06-07 | — | pesquisa |
| alta | T5 | SPRINT 1 - Síntese de Lacuna e Impacto | in_progress | 2026-06-05 | — | pesquisa |
| alta | T5 | SPRINT 1 - Síntese de Limitações e Transformações | review | 2026-06-05 | — | pesquisa |
| alta | T5 | SPRINT 10 - Artigo Científico | backlog | 2026-08-10 | — | publicacao |
| alta | T5 | SPRINT 10 - Relatório Final Consolidado | backlog | 2026-08-10 | — | publicacao |
| alta | T5 | SPRINT 3 - Taxonomia de Power Skills | backlog | 2026-06-21 | — | framework |
| alta | T5 | SPRINT 3 - Validação da Taxonomia | backlog | 2026-07-22 | — | framework |
| alta | T5 | SPRINT 4 - Matriz de Competências (Parte 1) | backlog | 2026-06-28 | — | framework |
| alta | T5 | SPRINT 5 - Matriz de Competências (Conclusão) | backlog | 2026-07-05 | — | framework |
| alta | T5 | SPRINT 6 - Rubricas de Proficiência | backlog | 2026-07-12 | — | framework |
| alta | T5 | SPRINT 7 - Checklist de Evidências (Gate A) | backlog | 2026-07-19 | — | ferramenta |
| alta | T5 | SPRINT 8 - Demonstração do Toolkit | backlog | 2026-07-27 | — | ferramenta |
| alta | T5 | SPRINT 8 - Toolkit v1.0 (Gate B) | backlog | 2026-07-26 | — | ferramenta |
| alta | T5 | SPRINT 9 - Relatório de Avaliação | backlog | 2026-08-03 | — | publicacao |
| alta | T6 | Artigo LinkedIn Newsletter - Junho | done | — | 2026-07-09 | publicacao |
| alta | T7 | PMI LATAM Conference 2026 — Proposta submetida (Evilásio + Marcos) | done | — | 2026-08-06 | webinar |
| alta | T8 | AI Community Day - Webinar | done | — | 2026-07-27 | webinar |
| alta | T8 | Artigo I Newsletter — Neurodiversidade (PT) | done | — | 2026-07-04 | publicacao |
| alta | T8 | Artigo II Newsletter — Neurodiversidade (PT) | done | 2026-07-08 | 2026-07-08 | publicacao |
| alta | T8 | Podcast Tribo 8 — resumos de artigos (Spotify) | review | — | 2026-07-30 | publicacao |
| alta | T8 | Submissão — Congresso PMI CE  (artigo Neuro-Advantage) | done | — | 2026-08-19 | publicacao |
| alta | T8 | Submissão — Congresso PMI Goiás (artigo Neuro-Advantage) | done | — | 2026-07-30 | publicacao |
| alta | T8 | Submissão — PMI Global Summit 2026 | done | — | 2026-07-30 | publicacao |
| alta | T10 | Arquiteturas de referência - Sprint 2 | todo | 2026-09-30 | — | framework |
| alta | T10 | Manual de Governança | done | 2026-07-30 | 2026-08-06 | framework |
| alta | T11 | Curadoria inicial de referências — PMO Inteligente | in_progress | 2026-08-10 | — | pesquisa |
| alta | T11 | Exploração inicial — Simulação de Services e Outcomes com IA | in_progress | 2026-08-31 | — | poc |
| alta | T11 | Matriz inicial — Services x Outcomes de PMO | in_progress | 2026-08-03 | — | framework |
| alta | T11 | Nivelamento inicial — PMO Services e Outcomes | done | 2026-07-24 | — | pesquisa |
| alta | T11 | Primeiro conteúdo público — PMO Inteligente, Services e Outcomes | in_progress | 2026-08-17 | — | webinar |
| alta | T13 | Análise caps 1 e 3 DAMA DMBOK | done | — | 2026-08-04 | pesquisa |
| media | T1 | Rodada semanal — Rodolfo: revisão das pesquisas e história da tribo | review | — | — | pesquisa |
| media | T11 | Primeiro Artigo — Tribo 11 (PMO Inteligente) | backlog | — | — | webinar |
| baixa | T1 | Organizar Pesquisa Qualitativa Pesquisa Quantitativa - Uso de IA para apoio ao GP | todo | — | — | pesquisa |
| baixa | T1 | Pesquisa Quantitativa - Uso de IA para apoio ao GP | review | — | — | pesquisa |
| baixa | T2 | Artigo Discussão sobre Framework de IAs Agenticas | in_progress | — | — | publicacao |
| baixa | T2 | Ferramenta de validação do Framework | in_progress | — | — | ferramenta |
| baixa | T2 | Implementação da Arquitetura no Framework SDK Anthropic + MCP | in_progress | — | — | framework |
| baixa | T2 | ModelScope‑Agent – Framework Agentic baseado em LLMs open‑source | todo | — | — | framework |
| baixa | T2 | Resolver doc PI com Débora — webinar 31/05 adiado | backlog | — | — | webinar |
| baixa | T2 | Revisão do Artigo | in_progress | — | — | publicacao |
| baixa | T4 | Criar o GuIA Cultura & Change | backlog | — | — | ferramenta |
| baixa | T4 | Estudo de caso - gestao de mudanca em empresa de tecnologia | todo | — | — | pesquisa |
| baixa | T4 | Integração da Plataforma com Agente de IA | todo | — | — | poc |
| baixa | T4 | Publicação para Linkedin: É possível promover publicações compartilhando estudos…? | in_progress | — | — | publicacao |
| baixa | T8 | Artigo - Newsletter | review | — | — | publicacao |
| baixa | T9 | Diagnostico Ecossitema de Construção | backlog | — | — | pesquisa |
| baixa | T11 | Apoio à Matriz (pesos) — João Leite | backlog | — | — | framework |
| baixa | T11 | Apoio à Revisão de Artigos — Ártico | backlog | — | — | publicacao |
| baixa | T11 | Curadoria de Referências — Thayanne | backlog | — | — | pesquisa |
| baixa | T11 | Matriz Services x Outcomes — Rodrigo | backlog | — | — | framework |
| baixa | T11 | Pesquisa de Services — Ártico | backlog | — | — | pesquisa |
| baixa | T11 | Pesquisa de Services — Gerson | backlog | — | — | pesquisa |
| baixa | T11 | Pesquisa de Services — João Leite | backlog | — | — | pesquisa |
| baixa | T11 | Pesquisa de Services — Marcio | backlog | — | — | pesquisa |
| baixa | T11 | Pesquisa de Services — Mery | backlog | — | — | pesquisa |
| baixa | T11 | Pesquisa de Services — Rodrigo | backlog | — | — | pesquisa |
| baixa | T11 | Pesquisa de Services — Thayanne | backlog | — | — | pesquisa |
| baixa | T11 | Simulação/Piloto — João Leite | backlog | — | — | poc |
| baixa | T12 | Apresentação pública do projeto (webinar ou slot em Reunião Geral) | backlog | — | — | webinar |
| baixa | T13 | Análise - Linhagem e Rastreabilidade dos Dados | todo | — | — | pesquisa |
| baixa | T13 | Matriz RACI - Análise por Fases | in_progress | — | — | framework |
| baixa | T14 | Sprint 0 - Plano de Aprendizado v0 (MVP) | in_progress | — | — | poc |
| baixa | T14 | Sprint 3 - Principais ferramentas de IA | backlog | — | — | ferramenta |

## Gap B — itens de portfólio sem tag de tipo (30)

Estes já contam no total do portfólio, mas o filtro de tipo e o gráfico `by_type`
não os classificam.

| Tribo | Card | Status | Entregável do líder | Tipo sugerido |
| --- | --- | --- | --- | --- |
| T1 | Webinar em Inglês sobre iniciativas da Tribo. | backlog | — | webinar |
| T4 | Elaborar artigo para submissão ao SINGEP - IA EM SERVIÇOS PUBLICOS | done | — | publicacao |
| T4 | Palestra 19o SGPL PMI Goias | in_progress | — | webinar |
| T4 | Pilulas fase 1 - Publicar pilula 2 | done | — | publicacao |
| T4 | Pilulas fase 1 - Publicar pilula 3 | done | — | publicacao |
| T4 | Pilulas fase 1 - Publicar pilula 4 | done | — | publicacao |
| T4 | Pilulas fase 1 - Publicar pilula 5 (extra) | done | — | publicacao |
| T4 | Webinar Series - PMI GO | done | — | webinar |
| T5 | SPRINT 10 - Webinário | backlog | — | webinar |
| T6 | Artigo LinkedIn Newsletter - Agosto | in_progress | — | publicacao |
| T6 | Artigo LinkedIn Newsletter - Julho | done | — | publicacao |
| T6 | Artigo LinkedIn Newsletter - Maio | done | — | publicacao |
| T6 | Artigo LinkedIn Newsletter - Novembro | backlog | — | publicacao |
| T6 | Artigo LinkedIn Newsletter - Outubro | backlog | — | publicacao |
| T6 | Artigo LinkedIn Newsletter - Setembro | backlog | — | publicacao |
| T6 | Dry Run T6 — 5 apresentações + integração MCP (20/mai 19:30) | done | — | **revisar** |
| T7 | Artigo Cientifico PMI-MG | in_progress | — | publicacao |
| T7 | Webnair workshop online | todo | — | webinar |
| T8 | Convidar psicólogo para participar de webnar | todo | — | webinar |
| T8 | Pilar IV - Criar um modelo de análise estatística | review | — | framework |
| T8 | Pilar IV - Formulário: Questionário V1 | review | — | ferramenta |
| T8 | Pilar IV - landing page | review | — | ferramenta |
| T8 | Target Pilar I— Conferência de Inovação em GP (Harrisburg University) | done | — | publicacao |
| T8 | Target Pilar IV - Estudo de campo Neuro-Advantage com IA | backlog | — | pesquisa |
| T9 | 1ª webinar - Industria da Construção | in_progress | — | webinar |
| T10 | Webinar | backlog | — | webinar |
| T11 | Apoio ao Planejamento do Webinar — Rodrigo | backlog | — | webinar |
| T12 | Webinar | backlog | — | webinar |
| T13 | Webinar | backlog | — | webinar |
| T14 | Sprint 5 - Webinar | backlog | — | webinar |

## Sobre `tipo sugerido`

`portfolio_suggest_item_type(title, tags)` é uma heurística determinística sobre
título + tags legadas, **consultiva e nunca aplicada automaticamente** — a
tipificação do entregável é conteúdo do líder da tribo.

Calibração (2026-08-20): dos 31 cards de tribo que humanos já tipificaram, a
heurística concorda com 30. Ela erra de forma previsível quando o vocabulário do
card aponta para o canal e não para o artefato — o exemplo vivo é
*"PMI LATAM Conference 2026 — Proposta submetida"*, sugerido como `webinar` porque
carrega a tag legada `palestra`, quando o artefato é uma submissão (`publicacao`).
Trate a coluna como ponto de partida da conversa com o líder, não como resposta.

## O que fazer com isto

1. **T5 e T11 primeiro** — são 32 dos 67. Ambas planejaram o ciclo em sprints com
   data-base e nenhum entrou no portfólio; resolver com o líder de uma vez vale mais
   que 32 decisões individuais.
2. **Os 34 de confiança alta** já têm data pactuada ou entrega registrada: são o
   subconjunto onde ligar o flag é registro do que já aconteceu, não julgamento novo.
3. **Gap B é mais barato** — 30 cards que já estão no portfólio e só precisam da tag;
   26 deles têm sugestão inequívoca (`webinar` ou `publicacao`).
4. **Os `baixa` de T11** ("Pesquisa de Services — <nome>") são alocação individual de
   contribuinte. A recomendação é deixá-los fora do portfólio e marcar o card-mãe.

## Reproduzir

```bash
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  node scripts/audit-portfolio-flags-tags.mjs --out=/tmp/portfolio-gaps.md

# incluir workgroups/comitês/congressos além das tribos
node scripts/audit-portfolio-flags-tags.mjs --all
```

O botão **"Data sanity"** em `/admin/portfolio` também passa a mostrar os dois
contadores (`tribe_cards_missing_portfolio_flag`,
`tribe_portfolio_items_missing_type_tag`), gravados no ledger
`portfolio_data_sanity_runs` a cada execução — dá para acompanhar a curva.

## Fora do escopo pedido (registrado, não corrigido)

- **Iniciativas não-tribo.** Com `--all` (workgroups, comitês, congressos,
  grupos de estudo) o retrato vai a 369 cards, 63 com flag, **127** no Gap A e 32
  no Gap B. Ou seja: quase todo o trabalho operacional do Núcleo está fora do
  portfólio. Isso pode ser intencional (o portfólio é de pesquisa) — mas é uma
  decisão que não está escrita em lugar nenhum.
- **`PortfolioDashboard` fixa `usePortfolio(3)`.** O ciclo 3 está hardcoded em
  `src/components/portfolio/PortfolioDashboard.tsx:30`, e `loadKpiHealth` chama
  `get_annual_kpis` com `p_cycle: 3`. Nas tribos isso hoje é inofensivo — os 61
  cards com flag são todos do ciclo 3 (`flagged_outside_dashboard_cycle = 0`).
  Fora das tribos já há 2 cards com flag invisíveis por esse motivo. Quando o
  Ciclo 4 virar o ciclo corrente, o dashboard esvazia.
