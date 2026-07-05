# Diagnóstico do estado atual — landing `nucleoia.vitormr.dev`

- **Status:** Diagnóstico (Fase 1 do redesign-alvo do Ciclo 4). **Sem prescrição** — só o estado real, com evidência visual.
- **Data:** 2026-06-19
- **Método:** Playwright + google-chrome, prod (`/?lang=pt-BR` forçado), desktop 1440×900 + mobile 390×844, captura full-page + por seção. Screenshots em `./screenshots/` (`{desktop,mobile}_NN_<id>.png`).
- **Relacionado:** plano `~/.claude/plans/ler-o-checkpoint-mutable-tiger.md`; brief `../cycle4_landing_value_prop.md` (6 blocos / checklist §7); checkpoint de drift.

> **Como ler:** primeiro a tabela seção-a-seção (estado + leitura pelas 5 lentes), depois os **achados estruturais** (a evidência do drift), depois a **jornada anon** e o **nav**. A disposição (cortar/fundir/promover) é decisão da Fase 3 — aqui só constato.

---

## 0. Inventário medido (ordem real, pt-BR)

16 seções em `src/pages/index.astro`, nesta ordem (altura desktop / mobile):

| # | id | Heading | Alt. desktop | Alt. mobile |
|---|-----|---------|----:|----:|
| 00 | `#hero` | Núcleo de Estudos e Pesquisa em IA & GP | 900 | 850 |
| 01 | `#nucleo` | O que é o Núcleo IA & GP? | 344 | 512 |
| 02 | `#capitulos` | 15 Capítulos PMI Integrados | 603 | 1283 |
| 03 | `#platform-stats` | A plataforma em números | 272 | 504 |
| 04 | `#quadrants` | 4 Quadrantes Estratégicos | 560 | 922 |
| 05 | `#verticals` | Verticais de comunidade, costuradas pela IA | 1303¹ | 2529 |
| 06 | `#partners` | Sua organização traz estratégia e talento… | 860 | 1317 |
| 07 | `#tribes` | Escolha sua Tribo | 1454 | 1731 |
| 08 | `#rules` | Regras do Jogo | 818 | 1049 |
| 09 | `#kpis` | Metas 2026 | 597 | 1051 |
| 10 | `#trail` | Trilha PMI AI | 1659 | 4413 |
| 11 | `#team` | Nosso Time | 382² | 5034 |
| 12 | `#cpmai` | Mural de Certificados PMI-CPMAI | 705 | 1115 |
| 13 | `#vision` | Para Onde Estamos Indo | 638 | 1127 |
| 14 | `#agenda` | Agenda da Semana | 485 | 499 |
| 15 | `#resources` | Próximos Passos | 683 | 1496 |

¹ Altura medida com a ilha carregada (`desktop_05_verticals_loaded.png`); a 1ª passada pegou o skeleton (ver §Achado V).
² Team mediu 382px porque a galeria de membros estava em "Carregando time…" no momento da captura (client-script). No mobile, carregada, mede 5034px.

**Soma aproximada de scroll:** desktop ~12.000px (≈13 telas de 900px); mobile ~24.000px (≈28 telas). **É uma página muito longa.**

---

## 1. Leitura seção-a-seção (5 lentes, condensada)

| # Seção | Bloco #680 | O que comunica (bem) | O que NÃO comunica / fricção | Público real |
|---|---|---|---|---|
| 00 Hero | **1 herói** | Tese-costura forte; 4 stats ao vivo (47/7/18/807h); 2 CTAs + badge capítulos; gradiente navy→roxo premium. | Dois CTAs concorrem ("Conhecer" vs "Entrar"); stats repetem-se logo abaixo. | Visitante ✅ |
| 01 Nucleo | (1, expansão) | Parágrafo "o que é" + gancho PMI:Next/M.O.R.E. | **Repete a tese do subtítulo do hero** quase literalmente; sem visual, sem CTA. Redundância imediata. | Visitante (fraco) |
| 02 Capítulos | 5 (parcial) | 15 capítulos PMI como pills; "integração multi-regional"; prova de alcance. | **Prova geográfica ANTES do "o que é o modelo"**; é lista plana, não mapa (bloco 5 real ausente). "15" conflita com "8" (KPIs) e "5" (Team). | Visitante ✅ |
| 03 Platform-stats | **2 prova viva** | 6 contadores ao vivo (47/7/5/18/339/68%). Limpo. | **Sobrepõe os 4 stats do hero** (47/7/18 repetidos a 3 seções de distância). | Visitante ✅ |
| 04 Quadrants | **3 modelo** | 4 quadrantes claros, cor-codificados, sem jargão. | "Cada quadrante se conecta…" mas não mostra como; estático. | Visitante ✅ |
| 05 Verticals | **3 modelo / 6 CTA** | Hub "Núcleo+IA / a costura" + espinha Champion→CPMAI + 5 verticais "EM FORMAÇÃO" com CTA "Seja protagonista" (ao vivo). | **Não é o diagrama radial do §5a** (é hub + grade de cards em flex-wrap); skeleton aparece em load lento (§Achado V). | Visitante ✅ (o melhor) |
| 06 Partners | **6 CTA** | Troca de valor 2-colunas + "Seja parceiro" + titularidade PMI-GO explícita + âncora ANSI. Forte e on-brief. | Denso de texto; 4º bullet longo. | Org/parceiro ✅ |
| 07 Tribes | — | Mecânica de tribos (8 tribos, líderes, vagas 0/10). | **"SELEÇÃO ENCERRADA / Faça login para escolher"** — UI de membro, inútil p/ anon, e é a **2ª maior seção** (1454px) bem no meio. | Membro ❌ p/ anon |
| 08 Rules | — | "Regras do Jogo" (carga 4-6h, dashboard, curadoria) + "Jornada de Valor 2026" (4 marcos). | Carga horária / processo = onboarding de membro; a timeline de marcos é boa mas enterrada aqui. | Membro |
| 09 KPIs | 2 (excesso) | "Metas 2026": 9 cards OKR com barras + splits Q2. | **Relatório operacional denso** (9 KPIs com 5/8, 0/3, Q2:…) — terceira superfície de números; "8 capítulos" colide com "15". | Interno/liderança |
| 10 Trail | **4 escada** | "Trilha PMI AI" (escada de certificação) — núcleo do bloco 4. | Embute **leaderboard do time inteiro** (Credly % por membro) = gamificação operacional; **maior seção mobile (4413px)**. | Misto |
| 11 Team | — | "Nosso Time" — 44 colaboradores, galeria por papel. | Pegou "**Carregando time…**" (latência client-script); **maior seção mobile real (5034px)**; "44" colide com "47". | Visitante (lento) |
| 12 Cpmai | (4, adjacente) | Mural CPMAI: anúncio (CPMAI em PT) + 2 certificados reais. | Sobrepõe a "escada" do Trail e o bloco-4; honesto mas fino (2 pessoas). | Visitante ✅ |
| 13 Vision | — | "Para Onde Estamos Indo": benchmarking intl, bimodal Eixo A/B, CPMAI, roadmap 2026-28. | **Bimodal já está no hero**; é "lore"/posicionamento enterrado fundo; "Consolidação Ciclo 3" (stale). | Visitante (fraco) |
| 14 Agenda | — | "Agenda da Semana": reunião geral + reuniões de tribo. | **"Faça login para ver o link" + "Nenhuma reunião agendada"** — vazio/gated p/ anon. | Membro ❌ p/ anon |
| 15 Resources | — | "Próximos Passos": 9 cards de link (playlist, manual, GitHub, vagas, volunteer.pmi.org). | Despejo de links de rodapé; vários **member-only** (Manual obrigatório, "Aceite sua posição"); "Ciclo 3" (stale). | Misto |

---

## 2. Achados estruturais (a evidência do drift)

**A. 7 das 16 seções não mapeiam aos 6 blocos do north-star (#680).** Sem casa no brief: `nucleo`, `tribes`, `rules`, `team`, `vision`, `agenda`, `resources`. É exatamente a hipótese de acúmulo do PM — quase metade da página é conteúdo que cresceu fora da espinha de valor.

**B. Tese-costura dita 2× seguidas.** O subtítulo do hero ("A costura entre os silos do PMI… com a IA como o fio") e o parágrafo de `nucleo` dizem a mesma coisa em sequência. `vision` repete o bimodal pela 3ª vez.

**C. Números aparecem em 3 superfícies + denominadores inconsistentes.** Hero (47/7/18/807h) → platform-stats (47/7/5/18/339/68%) → KPIs (8 cap 5/8 … 1.800h/807h). E a "mesma" grandeza tem valores diferentes conforme a seção: **pesquisadores 47 (stats) vs colaboradores 44 (team)**; **capítulos 15 (capítulos) vs 8 meta 5/8 (KPIs) vs 5 (team/stats)**. O visitante não consegue ancorar "qual é o número".

**D. Ordem inverte a lógica de venda.** Prova de alcance (`capitulos`, #02) vem **antes** do modelo de valor (`quadrants`/`verticals`, #04-05). Mostra-se "onde estamos" antes de "o que somos".

**E. Conteúdo de membro, gated, alto na página.** `tribes` (#07, "seleção encerrada/login", 2ª maior seção) e `agenda` (#14, "login/nenhuma reunião") são paredes de login para o anônimo — e `tribes` está no meio do fluxo de descoberta. O visitante esbarra repetidamente em "Faça login".

**F. O bloco 5 (mapa Brasil/LatAm) não existe.** `capitulos` (pills) é o substituto atual; não há mapa nem a leitura LatAm-como-recado-de-expansão do brief §5b.

**G. A peça-central (§5a) sob-entrega.** O "hub-and-spoke" é, no código, um círculo central + linha + **grade de cards em flex-wrap** (`VerticalsSection.tsx:293-319`) — não o **diagrama radial de raios** ("cada raio uma comunidade") que o brief diz ser *o* pitch.

**H. Página longa demais.** ~13 telas desktop / ~28 mobile. `trail` (4413px) e `team` (5034px) são gigantes no mobile; scroll-fatigue real antes de chegar aos CTAs de conversão que ficam dispersos.

**I. Staleness de ciclo.** Nav diz "**Ciclo 03**"; `resources`/`reuniões` e `vision` citam "Ciclo 3" — embora isto seja a preparação do **Ciclo 4**. A virada não chegou à copy de superfície.

**J. CTAs primários competem sem hierarquia.** Hero (Conhecer/Entrar), Verticals (Seja protagonista), Partners (Seja parceiro), Tribes (login), Agenda (login), Resources (Candidatar-se ×2). Cinco "ações principais" diferentes sem um funil único visível.

**K. Divergência de ordem entre locales.** PT-BR segue a ordem acima; EN-US reposiciona `Chapters`/`Kpi` (mapeado na exploração de código). Os 3 locales precisam de uma ordem canônica única.

---

## 3. Jornada do visitante anônimo (o caminho real)

Hoje o anônimo desce: tese → tese repetida → prova geográfica → números → modelo → **verticais (única conversão clara: "Seja protagonista")** → parceiros → **parede de login (tribos)** → regras de membro → relatório de OKR → trilha+leaderboard → galeria carregando → mural CPMAI → lore → **agenda vazia/login** → despejo de links com vagas.

- **Pico de valor** = `verticals` + `partners` (#05-06): é onde o anônimo entende o convite e pode agir. Ficam relativamente cedo — bom.
- **Vales** = tudo de `tribes` (#07) em diante é majoritariamente member-facing ou repetição, com 2 paredes de login e 1 estado vazio. O funil "perde" o visitante depois do pico.
- **Conversões dispersas:** os 2 CTAs que importam p/ o anônimo (protagonista, parceiro) estão isolados; não há um fechamento de jornada ("você viu o modelo → entre como protagonista/parceiro") no fim.

---

## 4. Auditoria do nav (IA pública)

- Topbar: marca "**Núcleo IA & GP — Ciclo 03**" (stale) · "**Seções ▾**" (dropdown de âncoras) · "**Blog**" · busca (⌘K) · seletor de idioma · "**Entrar**".
- Itens públicos do dropdown (de `navigation.config.ts`): âncoras `#quadrants #tribes #kpis #breakout #rules #trail #team #vision #resources` + `/governance/documents` + `/blog`.
- **Achados:** (1) o dropdown lista `#kpis`, `#rules`, `#tribes` (member-facing) como destinos públicos, mas **não** lista `#verticals` nem `#partners` — i.e. as âncoras que mais convertem o anônimo **não estão no menu**, enquanto conteúdo de membro está. (2) "Ciclo 03" no logo. (3) IA do menu = lista plana de âncoras, sem agrupamento (Sobre / Comunidade / Entrar).

---

## 5. O que está forte (não quebrar no redesign)

- **Sistema visual** (paleta PMI navy/orange/teal/roxo/esmeralda, tokens em `theme.css`): coeso e premium. No-rebrand é acertado.
- **Hero**: primeira dobra clara e com fato ao vivo.
- **Verticals + Partners**: as duas seções mais on-brief e que convertem — a base do Ciclo 4 já shipada.
- **Quadrants**: explicação limpa do "o quê".
- **Honestidade fact-driven**: nada vaporware (verticais "EM FORMAÇÃO", CPMAI com 2 reais, KPIs com progresso real). Princípio a preservar.

---

## Apêndice — screenshots
`./screenshots/desktop_NN_<id>.png` e `./screenshots/mobile_NN_<id>.png` (16 seções × 2 viewports) + `desktop_full.png` / `mobile_full.png` + `desktop_05_verticals_loaded.png` (verticais com ilha carregada). Scripts de captura: `./_capture.mjs`, `./_recap_verticals.mjs`.
