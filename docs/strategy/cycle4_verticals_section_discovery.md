# Discovery — Seção de Verticais da Landing (Ciclo 4, theme-first)

- **Status:** Discovery / alinhamento (pré-build). NÃO é a copy final nem o design final.
- **Data:** 2026-06-19 · Autor: Vitor (PM) + Claude (PMO)
- **Decisões PM desta rodada (2026-06-19):** (1) ghost-cards "em breve" **ancorados no TEMA** (provocação da IA no domínio), **não** na certificação; (2) **theme-first em todos os cards** — a credencial vira selo discreto; (3) doc de discovery primeiro, build só depois dos benchmarks de UX; (4) mapa Brasil/LatAm (B3) fica para sessão dedicada.
- **Relacionado:** `cycle4_landing_value_prop.md` (brief §3 nada-hardcoded / §6 sistema visual), `verticals_x_quadrants_model.md`, ADR-0103, PR #810 (Fatia B B1+B2 — base já no ar).

> **Para que serve este doc.** A Fatia B (PR #810) já entregou a base técnica: `get_public_verticals()` ao vivo + `VerticalsSection` com 1 vertical real (Construção). Este discovery define a CAMADA seguinte — os ghost-cards temáticos + o bloco de posicionamento — para alinharmos **direção, copy e princípios visuais ANTES** de construir o visual pesado (evita retrabalho, já que design/UX é o eixo e o PM trará benchmarks).

---

## 1. Posicionamento da seção (a mensagem)

A seção não vende "entre numa vertical". Ela provoca: **a IA está reescrevendo cada domínio da gestão de projetos — venha pesquisar a fronteira.**

E deixa explícito o contrato de protagonismo:

> **Mais que uma comunidade: um programa de protagonismo.** Parte do resultado é a **transformação de gestores de projeto em líderes** — que assumem responsabilidade por gerar valor real, não só por entregar. É a leitura prática de **PMI:Next**, do **M.O.R.E.** e do **Pulse of the Profession**: liderança que decide **com** a IA, não apesar dela.

> ⚠️ Grounding: PMI:Next / M.O.R.E. / Pulse of the Profession entram como âncoras qualitativas de alinhamento. Se a copy final citar um dado específico do Pulse (ano, %, achado), a fonte precisa ser fornecida e verificada — não inventar número.

---

## 2. Os 7 temas (theme-first)

Cada card lidera pela **provocação** (a IA naquele domínio) + um **convite de pesquisa**. A credencial, quando existir, é selo discreto — não o título.

| # | Tema | Estado | Provocação (draft — refinar) | Convite |
|---|------|--------|------------------------------|---------|
| 1 | **Construção / MegaProjetos** | 🟢 REAL (ativa, piloto) | IA em megaprojetos: gêmeos digitais, risco e logística que se replanejam sozinhos. Onde o gestor decide e onde o modelo decide? | Vertical-piloto aberta → **Seja protagonista** |
| 2 | **Projetos Ágeis** | 🔜 em breve | Se o sprint vira **horas e não dias**, o que o gestor decide e o que delega ao agente? Repensar o modelo de gestão e o **human-in-the-loop** nas decisões estratégicas. | Fronteira aberta → **Proponha pesquisa** |
| 3 | **Escritório de Projetos (PMO)** | 🔜 em breve | Um PMO que **orquestra agentes** — de guardião de processo a **curador de decisão**. | Fronteira aberta → **Proponha pesquisa** |
| 4 | **Gestão de Produtos** | 🔜 em breve | IA do discovery ao delivery: o PM/PO como **orquestrador de agentes** + dono das escolhas estratégicas. | Fronteira aberta → **Proponha pesquisa** |
| 5 | **Portfólios** | 🔜 em breve | Seleção e priorização de portfólio assistidas por IA: do orçamento anual ao **steering estratégico contínuo**. | Fronteira aberta → **Proponha pesquisa** |
| 6 | **ESG** | 🔜 em breve | IA medindo impacto socioambiental em tempo real: o que muda na **governança do portfólio** e na prestação de contas? | Fronteira aberta → **Proponha pesquisa** |
| 7 | **Negócios** | 🔜 em breve | A IA reescreve o **business case**, a noção de valor e a ponte estratégia↔entrega. Quem lidera essa ponte? | Fronteira aberta → **Proponha pesquisa** |

> Copy acima = **rascunho de tom** (pt-BR). en/es entram depois. Refinar com a liderança. A ordem dos cards pode seguir a ordem de ativação do `vertical_pitch_kit.md` (Construção → PMO → ESG → Ágil → Negócio) ou uma ordem editorial — decidir com benchmarks.

---

## 3. Real vs ghost — a diferença honesta (sem vaporware)

| | Vertical REAL (Construção) | Ghost temático (6 demais) |
|---|---|---|
| Fonte | DB (`get_public_verticals`, ao vivo) | **Config estática no FE** (editorial, não-métrica) |
| Selo de estado | "Em formação" | "Em breve" / "Fronteira de pesquisa" |
| Credencial | Selo discreto (PMI-CP) | **Nenhuma** (é tema, não credencial) |
| CTA | **Seja protagonista** → form de fundador (`capture_visitor_lead` com `target_vertical`) | **Proponha pesquisa / Demonstre interesse** → captura leve (a definir: `capture_visitor_lead` com `target_theme`, ou só informativo) |

**Por que ghost = config estática e não seed no DB:** evita criar `community_vertical` `forming` falsas (sem líder/parceiro) que poluiriam o catálogo curado e exigiriam `anchor_credential` (ADR-0103). Os temas são **conteúdo de roadmap editorial** — mesmo padrão do arquivo estático `QUADRANTS` que já alimenta a `QuadrantsSection`. A regra "nada hardcoded" do brief §3 vale para **indicadores/números** (esses continuam ao vivo); provocações temáticas são copy curada, não métrica.

---

## 4. Princípios visuais / UX (a refinar com benchmarks)

- **Theme-first, zero ruído.** O card comunica o tema + a provocação. Nada que gere ruído: sem métrica falsa, sem tag de credencial em ghost, sem "em breve" que pareça vaporware (enquadrar como **fronteira de pesquisa aberta**, não "produto futuro").
- **Hub-and-spoke ganha sentido com 7 raios.** Com a malha completa, o hub "Núcleo + IA / a costura" finalmente lê como rede de silos costurados (resolve o ux-M1 do PR #810).
- **Diferenciação real↔ghost sutil mas clara** (ativa convida a fundar; ghost convida a propor) — sem rebaixar visualmente o ghost.
- **Linguagem atrativa, identidade preservada** (brief §6): paleta atual, no máximo o acento laranja já existente; iconografia por tema; motion sutil.
- **Acessível:** contraste AA, foco gerenciado, `role`/`aria` nos elementos decorativos com texto (já aplicado no card real).

---

## 5. Intake de benchmarks (PM preenche)

| Benchmark | Para | O que coletar |
|-----------|------|---------------|
| **pmairevolution.com/ambassadors/** | B3 mapa (próxima sessão) | Mapa com pin 📌 por pessoa (pesquisador/líder/GP/Co-GP) por localização — referência de UX do mapa de cobertura |
| _(PM adiciona)_ | Seção de verticais | Referências de hub-and-spoke / cards temáticos / seções de "research frontiers" |
| _(PM adiciona)_ | Posicionamento | Referências de copy de impacto/protagonismo |

---

## 6. Perguntas abertas (resolver com benchmarks, antes do build)

1. **CTA do ghost**: captura interesse de pesquisa (`capture_visitor_lead` com um `target_theme`) ou é puramente informativo ("fique sabendo quando abrir")?
2. **Quantidade visível**: mostrar os 6 ghosts de uma vez ou um subconjunto rotativo, para não poluir?
3. **Iconografia/ilustração**: set de ícones por tema vs ilustração autoral — qual escala melhor e cabe no sistema visual?
4. **Raios literais no hub-and-spoke**: desenhar linhas SVG hub→card ou manter a leitura por proximidade + espinha do ladder?
5. **Ordem dos cards**: ativação (pitch kit) vs editorial.
6. **Bloco de posicionamento**: band dedicada acima dos cards, ou integrado ao header da seção?

---

## 6b. Requisitos emergentes da landing (PM 2026-06-19) — capturar, escopar depois

> Surgiram alinhando a seção de verticais. NÃO são da seção de verticais em si — são itens de landing/agenda mais amplos. Registrados aqui para não perder contexto; escopo/priorização com o PM.

- **R-NEWS** (issue **#811**) **— feed de projeção/showcase do Núcleo.** Projetar na landing as **notícias de conferências, webinars, podcasts e artigos publicados**. Justificativa de volume: só a conversa do PM com o Ivan (Pres. PMI-GO) de **hoje** tocou webinar/podcast/conferência/artigo/LIM/Detroit + capítulos/parcerias/pesquisa/CPMAI — o Núcleo gera MUITA ação e hoje isso não transparece na home. Substrato de dados já existe: `get_public_impact_data` retorna `recent_publications`, `webinars`, `recognitions`, `timeline`; há MCP `register_showcase`. → Possível **requisito** (escopar fonte canônica + curadoria).
- **R-AGENDA-HOME** (issue **#812**) **— agenda de protagonismo mais visível + melhor UX.** A "agenda de protagonismo" da reunião geral (blocos reserváveis — ver screenshot `IMG20260619WA0047`: "Reservar bloco", Quinta 02/Jul 19:00, 70min livres, bloco 20min "Ecossistema Claude aplicado ao GP") deve **aparecer na página inicial ao rolar**, com UX melhor: mostrar **semana anterior** ou **o dia pós-evento iniciado** (estado temporal mais rico, não só "próximos"). **Benchmark de UX:** UFF "Agendamento de Defesas" (screenshots `IMG20260616WA0017`) — colunas por dia/data, chips de status (Confirmada / Aguard. Banca / Agendada), card por item (título, pessoas, local, papéis). Boa referência de layout semanal com estado.
- **BUG-AGENDA-EDIT** (issue **#813**) **— editar título de evento após inserido na agenda.** Hoje, depois de inserir um evento na agenda, **não dá para editar o título** (os membros não conseguiram nesta rodada). Bug concreto/acionável — escopar o caminho de edição do bloco/evento.

## 7. Próximos passos

1. **PM reage a este doc** (copy das provocações, princípios, perguntas abertas) + traz benchmarks de UX.
2. Alinhar direção visual com os benchmarks → fechar as perguntas abertas.
3. **Só então construir** (provável fatiamento): (B2.1) config estática dos temas + render real+ghost no `VerticalsSection` + bloco de posicionamento; (B3) mapa Brasil/LatAm.
