# Redesign-alvo da landing/site — Ciclo 4

- **Status:** Proposta de ALVO (Fase 3 do replanejamento holístico). **Aguarda aval do PM antes de qualquer código.**
- **Data:** 2026-06-19
- **Entradas cruzadas:** diagnóstico (`diagnosis/landing_current_state_diagnosis.md`) × benchmarks (`benchmarking_sites_catalog.md` §Síntese) × brief #680 (`cycle4_landing_value_prop.md`, 6 blocos / checklist §7) × pesquisa PMI (Standard for AI / PMI:Next / M.O.R.E.).
- **Travas (não-negociáveis):** no-rebrand (preservar `theme.css`/paleta); nada hardcoded (indicadores ao vivo); LGPD (agregação, sem PII sem opt-in).

> **O que este doc decide:** a estrutura/jornada/IA **alvo** da home e a disposição de cada seção atual — não a copy nem o pixel final. **O que NÃO faz:** código. A execução é um `/plan` separado, alimentado pela §6 (sequência).

---

## 1. O diagnóstico em uma frase

A home cresceu para **16 seções**; **7 não servem aos 6 blocos do #680** e quase tudo depois do pico de valor (`verticals`+`partners`) é **conteúdo de membro, gated ou repetido** — com 3 superfícies de números inconsistentes, 2 paredes de login no fluxo do anônimo e 5 CTAs primários competindo. O sistema visual é forte; o problema é **arquitetura de informação e foco**, não pele.

## 2. Princípios do alvo (destilados dos benchmarks)

1. **Valor concreto antes de ideologia** — parear a tese-costura a um ganho do protagonista (PM3/Inteli).
2. **Uma superfície de prova, denominador consistente** — fim do 47≠44, 15≠8≠5 (Inteli/CEIA).
3. **Prova por parceiros + áreas concretas**, não vaidade (CEIA tríplice-hélice).
4. **Um CTA primário repetido** ("Seja protagonista"); parceiro = porta de audiência secundária (Experience 2026/Cubo).
5. **Escada como progressão por tier**, não lista (Alura).
6. **Member-facing fora do fluxo de descoberta** — nenhum benchmark põe ferramenta logada no meio do funil.
7. **Menos seções, mais hierarquia** — valor → modelo → escada → prova → alcance → conversão.

---

## 3. Disposição das 16 seções atuais

> Legenda: **MANTER** · **FUNDIR** (em outra) · **REORDENAR** · **PROMOVER** · **REALOCAR** (sair do fluxo anon → login/`/workspace`/página própria/rodapé) · **CORTAR** (da home).

| # Seção | Disposição | Justificativa (diagnóstico × benchmark × brief) |
|---|---|---|
| 00 `hero` | **MANTER + refinar** | Bloco 1, forte. Resolver CTA-duplo → **1 primário "Seja protagonista"** + secundário "Entrar"; 1 número ao vivo (não 4); corrigir "Ciclo 03". |
| 01 `nucleo` | **FUNDIR → hero/modelo** | Repete a tese-costura logo abaixo do hero (Achado B). Gancho PMI:Next/M.O.R.E. migra p/ o hero ou o modelo. Some como seção. |
| 02 `capitulos` | **REORDENAR (↓) + REFRAME** | Bloco 5. Prova geográfica vinha **antes** do modelo (Achado D). Vira **banda de cobertura/credibilidade** (modelo CEIA), depois do modelo. |
| 03 `platform-stats` | **MANTER + virar a ÚNICA prova viva** | Bloco 2. Absorve o papel de números do hero e um subconjunto curado dos KPIs; **denominador consistente** (Achado C). |
| 04 `quadrants` | **FUNDIR → "O modelo"** | Bloco 3. Quadrante (o quê) + Vertical (pra quem) são os 2 eixos — apresentar **juntos**, não em seções separadas. |
| 05 `verticals` | **MANTER + PROMOVER** | Bloco 3+6, a peça-central. **Elevar o hub-and-spoke ao radial do §5a** (hoje é hub + grade de cards, Achado G). CTA primário mora aqui. |
| 06 `partners` | **MANTER + REORDENAR** | Bloco 6. Forte e on-brief. Posicionar como **porta secundária de audiência**, depois do protagonista. |
| 07 `tribes` | **DEMOVER (↓ fim da home)** | UI de seleção "encerrada/login", no meio do funil anon (Achado E). **Decisão PM: manter na home, mover p/ o fim** (não realocar p/ login). Sai do caminho de conversão sem sumir. |
| 08 `rules` | **FUNDIR + DEMOVER (↓)** | "Jornada de Valor 2026" (timeline) → funde no modelo/escada. "Carga horária/regras" = onboarding → **demover p/ o fim da home** (bloco de membro). |
| 09 `kpis` | **DEMOVER (↓) + curar topo** | 9 KPIs com splits Q2 = relatório interno (Achado C). Subconjunto curado (2-3) alimenta a prova viva no topo; **painel completo demovido p/ o fim** (transparência), não removido. |
| 10 `trail` | **MANTER (escada) + SPLIT** | Bloco 4. Manter a trilha de certificação como **escada por tier**. **Leaderboard de Credly** (operacional) → demover p/ o bloco de membro no fim. |
| 11 `team` | **MANTER (enxuto)** | Credibilidade por rostos nomeados (benchmarks #5/#16). Enxugar; corrigir "Carregando…" e o 44≠47. Promover alguns protagonistas mais acima. |
| 12 `cpmai` | **FUNDIR → escada (bloco 4)** | Mural CPMAI pertence à escada Champion→CPMAI. Une com `trail` numa seção "A escada". |
| 13 `vision` | **CORTAR + FUNDIR** *(travado)* | "Lore"; bimodal repetido 3ª vez. Melhor parte (bimodal Eixo A/B, roadmap) → hero/modelo ou página "Sobre". **Some da home.** |
| 14 `agenda` | **REFRAME público (R-AGENDA-HOME)** *(travado)* | Gated/vazia p/ anon (Achado E). Reenquadrar no padrão landing-de-evento (#2: outcome + passado→futuro, eventos públicos). Deixa de ser parede de login. |
| 15 `resources` | **SPLIT → rodapé + DEMOVER (↓)** | Públicos (YouTube/biblioteca/blog) → **rodapé real**; member-only (Manual/GitHub/"aceite posição"/vagas) → **bloco de membro no fim da home**. |

**Resumo (com decisões travadas):** o tratamento do drift é por **reordenação/demoção**, não remoção (decisão PM). A home mantém o conteúdo de membro, mas em **duas zonas**: (1) **zona anon no topo** — valor → modelo → escada → prova → cobertura → conversão → agenda; (2) **zona de membro no fim** — tribos, regras/carga, painel KPI completo, leaderboard, links de membro. Só `vision` é cortada; só os links públicos de `resources` vão ao rodapé.

---

## 4. Estrutura-alvo da home (ordem canônica — pt/en/es idênticas)

> Decisão PM: **duas zonas na mesma home** — zona anon no topo (converte o visitante), zona de membro no fim (mantida, não removida).

### Zona ANON (topo — o funil)
| Ordem | Seção-alvo | Bloco #680 | Origem (funde) | Papel na jornada |
|------:|-----------|:---:|---|---|
| 1 | **Herói** | 1 | hero + nucleo | Tese-costura + ganho do protagonista + **CTA primário** + 1 fato ao vivo |
| 2 | **O modelo** | 3 | quadrants + verticals | Quadrante × vertical, IA-costura, **hub-and-spoke radial** = o pitch; CTA repetido |
| 3 | **A escada** | 4 | trail(escada) + cpmai | Champion → Grupo CPMAI → PMI-CPMAI por **tier**; certificados reais |
| 4 | **Prova viva** | 2 | platform-stats + KPIs(curado 2-3) | **Um** bloco de números, denominador consistente |
| 5 | **Cobertura & alcance** | 5 | capitulos(reframe) | Banda capítulos + legenda internacional → **mapa Brasil/LatAm depois** (§6) |
| 6 | **Protagonistas & Parceiros** | 6 | verticals-CTA + partners | **Roteador de 2 portas** (padrão triplamente corroborado): protagonista (primário) · parceiro (secundário, PMI-GO dono) |
| 7 | **Agenda / Acontece** | (emergente) | agenda(**reframe público**) | Eventos públicos, padrão landing-de-evento (R-AGENDA-HOME) |
| 8 | **Time** | (credibilidade) | team(enxuto) | Rostos nomeados |

### Zona MEMBRO (fim da home — demovida, mantida)
| Ordem | Seção | Origem | Observação |
|------:|-------|--------|-----------|
| 9 | **Tribos** | tribes | UI de seleção/login, fora do funil |
| 10 | **Como trabalhamos** | rules | Carga/regras + (timeline de marcos pode subir p/ a escada) |
| 11 | **Metas (painel completo)** | kpis | 9 KPIs c/ splits Q2 = transparência |
| 12 | **Leaderboard / links de membro** | trail(leaderboard) + resources(member) | Operacional |
| — | **Rodapé** | resources(público) | Links públicos + governança + blog + contato |

**Cortado da home:** `vision` (bimodal/roadmap fundem no modelo/hero ou "Sobre").

**Primeira dobra (hero):** carrega só 4 coisas — (1) **o quê** (costura), (2) **ganho concreto do protagonista**, (3) **um CTA primário**, (4) **um número ao vivo**. O cluster de 4 stats sai do hero e vai para a Prova viva.

**Funil:** CTA "Seja protagonista" repetido em hero → modelo → portas (3 toques, padrão Experience 2026). Parceiro = porta secundária. **Com a agenda reframada e as tribos demovidas, não há parede de login antes da conversão** — as paredes ficam na zona de membro, no fim.

## 5. Nav-alvo (IA pública)

`O Núcleo` (sobre+modelo) · `Verticais` · `Parceiros` · `Agenda` · `Blog` · busca · idioma · **[Seja protagonista]** (botão primário) · `Entrar`.
- **Adicionar** as âncoras que convertem (`#verticals`, `#partners`) — hoje ausentes do menu (Achado nav).
- **Remover** do menu público as âncoras de membro (`#kpis`, `#rules`, `#tribes`).
- Corrigir "Ciclo 03" no logo. Ordem/itens **idênticos nos 3 locales**.

## 6. Decisão do bloco 5 (mapa) — **fasear** → ✅ RESOLVIDO no R9

> **Atualização R9 (2026-06-21):** ao aterrar o dado ao vivo antes de codar, o footprint
> é **100% Brasil** (15 capítulos, 1 por estado) + membros internacionais **só em US (5) e
> PT (1)** — **ZERO presença na LatAm**. Logo, o "mapa Brasil/LatAm" da proposta original
> não se sustenta no dado; pelo princípio anti-vaporware, o R9 entregou um **mapa do Brasil
> por estado** (estados-capítulo destacados ao vivo, Goiás=fundador) + a legenda internacional
> nomeada do R6 (US/PT). Sem pins individuais (cobertura agregada por estado via
> `get_active_chapters`), FE-puro, sem migration. A redação abaixo fica como histórico da decisão.

O mapa Brasil/LatAm é net-new (sem componente reusável) e já adiado várias vezes. CEIA mostra que **credibilidade geográfica funciona por banda de parceiros/capítulos**, sem mapa.
- **Agora:** a seção "Cobertura & alcance" é cumprida pela **banda de capítulos + legenda internacional nomeada** (dado já existe; satisfaz "internacional visível" do §7; barato).
- **Depois (slice dedicada):** o **mapa Brasil/LatAm** SVG (LGPD: agrega por capítulo/estado/país, pins só opt-in via precedente `set_my_gamification_visibility`). Não bloqueia o redesign. → **Entregue no R9 como mapa do Brasil por estado (sem LatAm — ver nota acima).**

## 7. Sequência de execução (alto nível — input do próximo `/plan`)

> Cada slice: **branch → QA visual → prod** (decisão PM travada). No-rebrand preservado; toda slice toca as 3 páginas de locale.

| Slice | Conteúdo | Risco |
|---|---|---|
| **R1** ✅ | Herói: absorver `nucleo`, 1 CTA primário, 1 número, corrigir "Ciclo 03" | Baixo (copy/i18n) — feito na branch @ `bf69ca1e` |
| **R2** ✅ | Prova viva única: consolidar stats, **denominador consistente** (decisão de verdade-do-dado) | Médio (dado+FE) — feito na branch @ `2691df90`. Conjunto curado forte (5 cards): pesquisadores 47 · horas 807h · eventos 340 · retenção 68% · capítulos ativos 5. `impact_hours` canônico no `get_public_platform_stats` (fonte única herói+prova). Denominador canônico: 47=`active_members`, 807=`round(get_impact_hours_canonical())`, 5=`get_chapter_metrics->>'signed'`. |
| **R3** | "O modelo": fundir quadrants+verticals; **hub-and-spoke radial** (§5a) | Médio (visual net-new) |
| **R4** | "A escada": fundir trail(escada)+cpmai como progressão por tier | Baixo-médio |
| **R5** | **Reordenar member-facing p/ a zona de fim da home** (tribos/KPI-board/regras/leaderboard/links-membro demovidos, não realocados); cortar `vision`; links públicos de `resources` → rodapé | Médio (ordem + nav + rodapé) |
| **R6** | Cobertura: banda capítulos + legenda internacional | Baixo |
| **R7** | Portas protagonista/parceiro + roteador; funil de CTA único | Baixo-médio |
| **R8** (opc.) | Agenda/Acontece reframe (R-AGENDA-HOME) + notícias (R-NEWS) | Médio |
| **R9** (depois) | Mapa Brasil/LatAm SVG (LGPD agregado) | Alto (net-new) |
| **R0** (transversal) | Reconciliar ordem canônica pt/en/es a cada slice | — |

## 8. Verificação contra o checklist §7 do brief

| Item §7 | Estado no alvo |
|---|---|
| Nada hardcoded | ✅ mantido como trava (consolidação fica ao vivo) |
| Verticais de `community_vertical` | ✅ já; preservado |
| CTA protagonista por `status='forming'` | ✅ já; vira o funil único |
| Mapa agrega; pins opt-in | ⚠️ faseado (R9); banda cobre o interino |
| Internacional visível | ✅ legenda nomeada (R6) |
| Paleta/identidade preservadas | ✅ no-rebrand; mudança é só IA/estrutura |
| Hub-and-spoke sem jargão | ✅ **melhora** (radial, R3) |

## 9. Decisões TRAVADAS (PM, 2026-06-20)

1. **Member-facing = DEMOVER, não realocar.** Tribos, painel KPI completo, regras/carga, leaderboard, links de membro **ficam na home, movidos p/ a zona de fim** (§4). Não vão p/ `/workspace`. Anti-drift por reordenação.
2. **`vision` = CORTAR + fundir** o útil (bimodal Eixo A/B, roadmap) no modelo/hero ou página "Sobre".
3. **Mapa (bloco 5) = FASEAR** — banda de capítulos + legenda internacional agora; mapa SVG Brasil/LatAm = slice dedicada (R9) depois.
4. **`agenda` = REFRAME público (R-AGENDA-HOME)** — eventos públicos no padrão landing-de-evento; deixa de ser parede de login.
5. **Verdade-do-dado dos contadores = resolver no R2**, aterrando o denominador canônico em **query ao vivo** (regra de grounding) — não decidir de memória. Unificar rótulos+fontes ("pesquisadores ativos" 47 vs "colaboradores" 44 vs "capítulos" 15/8/5) ali.

> **Alvo travado.** A execução de código abre num `/plan` separado a partir da sequência §7 (R1→R9). Próxima sessão: `/plan` de execução — não recomeçar pela pesquisa (já está em disco).
