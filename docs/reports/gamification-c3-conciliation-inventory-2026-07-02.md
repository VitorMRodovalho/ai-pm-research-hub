# Handoff — Champions & Gamificação do Ciclo 3 (2026/1) a partir do YouTube

**Gerado:** 2026-07-02 · **Fonte:** canal YouTube "Núcleo de Estudos e Pesquisa em IA e GP" (48 vídeos) + `nucleo-ia` MCP (ciclo/regras) + hub `ai-pm-research-hub` (`gamification_rules`, eventos, artefatos).
**Recorte:** `cycle_3` = **2026-03-01 → hoje** (fim NULL/aberto), confirmado ao vivo via `get_current_cycle`.
**Governança:** este MD é **leitura + relatório** produzido no nó Pai. **Nenhum `award_champion` foi executado.** As outorgas propostas na seção 4 só devem ser gravadas **de dentro do hub**, com tua validação e resolução dos `member_id`.

---

## 1. Modelo de pontuação (grounded na `gamification_rules`, não no manual)

Dois pilares **paralelos**. O exercício "protagonista de vídeo" toca dois deles:

### Pilar CHAMPION (outorga manual, contra um contexto)
| slug | base | +critério | cap | superfície | contexto elegível |
|---|---|---|---|---|---|
| `champion_general` | 30 | +5 | 50 | general | `events` tipo `geral`/`lideranca` (initiative NULL) |
| `champion_tribe` | 20 | +5 | 40 | tribe | `events` tipo `tribo`/`1on1` (initiative NOT NULL) |
| `champion_deliverable` | 40 | +5 | 60 | deliverable | `tribe_deliverables` (assigned) ou `meeting_artifacts` (published, creator) |

- **Fórmula:** `pontos = base + 5 × nº_critérios` (1–4 critérios), limitado ao cap. Bônus é **flat +5**, sem peso.
- **Caps que BLOQUEIAM:** por contexto **3/2/1** (general/tribe/deliverable) · por outorgante **3** por contexto.
- **Cap por ciclo (SOFT, só avisa):** general **5** · tribe **8** · deliverable **3** → passa com `soft_cap_warning:true`.
- **Critérios objetivos** (`criteria_met`, cada um vale +5):
  - **general:** `conduziu_pauta` · `apresentou_resultados` · `destravou_bloqueio` · `mediou_decisao`
  - **tribe:** `conduziu_reuniao` · `entregou_demo` · `mentorou_novo` · `apoio_externo`
  - **deliverable:** `qualidade_acima_baseline` · `prazo_antecipado` · `impacto_pmi` · `inovacao_tecnica`

### Pilar PRODUÇÃO/SHOWCASE (trigger automático, não é champion)
`showcase_case_study` 25 · `showcase`/`tool_review`/`prompt_week` 20 · `awareness`/`quick_insight` 15 · `deliverable_completed` 30 (+10 no prazo) · `artifact_published` 15 · `action_resolved` 5 · `curation_*` 5–30.

### Regra de roteamento vídeo → pilar
| Tipo de vídeo | Elegível a Champion? | Rota |
|---|---|---|
| Reunião **Geral** (aberta) | ✅ `champion_general` | via `events.youtube_url` |
| Reunião de **Liderança** | ❌ **EXCLUÍDA** (decisão Vitor 2026-07-02 — reconhecimento entre a própria liderança) | — |
| Reunião de **Tribo** | ✅ `champion_tribe` | via `events` (tipo tribo) |
| **Ata autoral publicada** / entregável de tribo | ✅ `champion_deliverable` | `meeting_artifacts`/`tribe_deliverables` |
| **Webinar** / painel / mesa | ✅ pilar PRODUÇÃO — regra `talk` **25 XP** por palestrante (PR #1075, issue #1073), escopo Núcleo-atribuível | XP automático, não usa slot de champion |
| **Curadoria / pílula autoral** (M.O.R.E) | ⏳ mesmo princípio de protagonismo autoral | Produção: `event_showcases` quick_insight (15) / `content_products` |
| **Recorte** de reunião | ❌ (é gravação, não obra) | não pontua sozinho |

> **Autoral × recorte:** o sistema **não tem flag booleano**. Recorte = `events.youtube_url` (gravação). Autoral = obra registrada (`content_products` c/ `instrument`, `event_showcases` quick_insight/case_study, ou `meeting_artifacts` autoral).

---

## 2. Catálogo de vídeos do Ciclo 3 (38 na janela de upload)

⚠️ **Data do evento ≠ data de upload.** Uso a **data no título** (quando o tema foi falado). Isso exclui a playlist "Q2 member H" — 10 vídeos subiram em 07-04 mas o conteúdo é **Ciclo 02** (2025-09 a 2026-02); só 23-03 e 30-03 são C3.

### 2a. Reuniões Gerais (surface `general`)
| Data evento | UUID evento | min | Protagonistas (por capítulo) | Vídeo |
|---|---|---|---|---|
| 03-06 Kick-off | *(sem UUID — tipo `kickoff`, não elegível)* | 116 | Diretorias PMI DF/CE/GO/MG/RS; líderes de tribo | público |
| 03-12 | `f8a7787b-112e-441f-8271-f906c47ab5aa` | 64 | member C (Notion+agentes); visão plataforma | público |
| 03-19 | `b8713f93-4113-4cb2-b862-4b6efff66604` | 73 | **member N** (voz Claude), **member E** (APM/agentic PM, demo) | público |
| 03-26 | `ba2b9bf9-0b08-416e-8739-6e5c3dbe11cf` | 103 | **member B** (framework prompt multi-LLM), **member A** (GitHub/Markdown), **Maia** (podcast NotebookLM), **member D** (agente Manus), **member I** (Lovable/Base44), **member V** (curadoria/mentoria) | público |
| 04-02 | `7eb8f380-2bb6-49de-ba1b-f6bce2f4ab8c` | 66 | **member K** (PMO-CP), **member B** (governança ONU/WR), **member N** (PM Strategic Analyzer, demo), **Evilácio** (segundo cérebro/Obsidian), **member M** (Obsidian/MD) | público |
| 04-09 | `dc823582-6ba7-4aae-942f-1539d174da02` | 84 | **member N** (adoção IA), **member X** (foco de ferramentas), **member G** (caso mineração), **member F** (caso de uso); demo plataforma/MCP | público |
| 04-23 | `deb3de2b-ac37-450b-a48a-40c07842d3db` | 91 | **member O** (showcase "Persua"/acessibilidade), **Prof. member Q** (PI/patentes) | público |
| 05-07 | `5f4b01be-9c12-4647-af22-c5158d86fd5b` | 116 | **member B** (Aula Magna arquiteturas/LLMs), Tribo 4 (change), Tribo 8 (neurodivergência) | público |
| 05-21 | `43135439-4463-4aa5-9d72-0fa80948ca6c` | 99 | **Sávio** (CPMAI deep-dive 6 fases/7 padrões); showcase transcritor | público · ⚠️ `youtube_url` NULL |
| 06-04 | `9ea5fc3c-8f4e-4e16-b7f1-5d3b871bf37f` | 110 | Case Cteec (engajamento univ.); distrito de inovação; táticas de prompt/RAG | público · ⚠️ `youtube_url` NULL |
| 06-18 | `a029ce54-31ae-4d9e-b95d-c0cd92326f0c` | 88 | Tribo 1 (radar tecnológico); **member Q** (métricas de avaliação) | público · ⚠️ `youtube_url` NULL |

### 2b. Reuniões de Liderança — ❌ EXCLUÍDAS do champion (decisão Vitor 2026-07-02)
Não pontuam champion. Registro apenas documental: liderança em 03-19, 04-16, 05-14, 05-28, 06-25. Ignorar no cálculo.

### 2c. Webinars/Painéis → pilar PRODUÇÃO, regra `talk` **25 XP** por palestrante (PR #1075)
| Data | min | Tema | Palestrantes (25 XP cada, se membro do Núcleo) |
|---|---|---|---|
| 07-01 | 91 | IA em Projetos e o Novo Standard do PMI — Painel (ANSI/PMI 26-007) | Palestrantes: **member N** · **member B** · **member F** · *(moderação: **member I** — edge)* |
| 06-03 | 100 | SESTEC / Núcleo — Mesa Redonda: IA e o Futuro das Competências | Palestrantes: **member N** · **member T** · **member S** · *(moderação: **Vitor** — edge)* · *(member D = Coordenador/Líder, não Palestrante → fora do `talk`)* |

- **SESTEC = iniciativa** `6e9af7a8-1696-4169-a1a1-c0e160600002` (papéis já registrados: role `Palestrante` é a fonte atribuível). Live `mJx_KpwDl0I` ≠ upload playlist `jYWuKBh0Bpg` (stream vs versão publicada — reconciliar no vínculo vídeo↔evento).
- **Roster `talk` 25 XP (a executar):** member N (2× — 06-03 e 07-01), member B, member F, member T, member S. *(+ moderadores member I e Vitor se a borda for "sim".)*
- **Decisão de borda:** moderador conta como `talk`? Recomendo **sim** (mesa/painel = protagonismo de condução), mas é tua ratificação.
- Todos os palestrantes são membros do Núcleo → **todos atribuíveis** (nenhum externo no corte).

### 2d. Comitê de Curadoria — série "Sustentabilidade M.O.R.E" → pilar PRODUÇÃO (autoral, NÃO champion)
| Data | min | Protagonista (autor) | Rota sugerida |
|---|---|---|---|
| 04-09 | 2 | Institucional (Comitê de Curadoria) | — |
| 04-09 (série 1) | — | **member S** (PMP, LEED GA — design sustentável) | `event_showcases` quick_insight (15) ou `content_products` |
| 04-14 (série 2) | 6 | **member I** (PMP, eng. civil — mindset M.O.R.E) | idem |
| 04-16 (série 3) | 2 | **member V** (Dir. Inovação ADTIS/CE) | idem |

### 2e. Pílulas de conhecimento (autoral)
**Zero dentro do Ciclo 3** — as 3 da playlist são anteriores a 2026-03-01. Se existirem shorts autorais C3 fora dessa playlist, sinalizar.

---

## 3. Artefatos/entregáveis elegíveis a `champion_deliverable` (grounded no hub)

### Atas publicadas (`meeting_artifacts`, creator = destinatário obrigatório) — 4 no C3
| UUID | data | ata | creator (destinatário) | obs |
|---|---|---|---|---|
| `c1a8e1c5-f58a-484e-9fc3-bab8a5bcdb64` | 04-09 | Geral (Radar/MCP) | **Vitor** | ⚠️ initiative NULL → autoridade pode falhar |
| `dcded397-17aa-4261-a22f-75aa34aaf3bb` | 04-06 | Talentos & Upskilling 4ª | **member F** | ok |
| `df735a51-801d-4217-bd60-460d151756de` | 03-30 | Agentes Autônomos | **member H** | ok |
| `76c39319-a395-4cf6-b621-93ca52dd137b` | 03-23 | Agentes Autônomos | **member H** | ok |

### `tribe_deliverables` — ~60 no C3 (CSV sob demanda)
Distribuídos por iniciativa: Governança & Trustworthy AI (member B), Talentos & Upskilling (member F), Cultura & Change (member N), ROI & Portfólio (member I), Radar Tecnológico (member T), Inclusão/Colaboração (member C), Agentes Autônomos (member H), TMO & PMO. Cada um tem `assigned_member_id`. Puxar CSV completo (id/título/data/dono/iniciativa) se for premiar por entregável.

---

## 4. Propostas de `award_champion` (NÃO executadas — aguardam validação)

**Restrições que valem:** máx **3** general champions por reunião (cap bloqueante) · máx **3** por outorgante/contexto · soft-warn a partir de **5 general por ciclo**. Ou seja, escolher os **≤3 destaques reais** por encontro, não todo apresentador.

### 4a. General (reuniões com UUID)
Sugestões (critérios = slugs; ajustar à tua leitura):
- **03-19** (`b8713f93`): member E — `apresentou_resultados`,`conduziu_pauta` (APM + demo) → 40 · member N — `apresentou_resultados` → 35.
- **03-26** (`ba2b9bf9`): member B — `apresentou_resultados`,`destravou_bloqueio` (framework multi-LLM) → 40 · member A — `apresentou_resultados` → 35 · member V — `mentorou_novo`≈`mediou_decisao` (curadoria/mentoria) → 35.
- **04-02** (`7eb8f380`): member N — `apresentou_resultados` (demo PM Analyzer) → 35 · member K — `apresentou_resultados` (PMO-CP) → 35 · Evilácio — `apresentou_resultados` → 35.
- **04-09** (`dc823582`): member G — `apresentou_resultados` (caso mineração) → 35 · member F — `apresentou_resultados` → 35 · member X — `mediou_decisao` → 35.
- **04-23** (`deb3de2b`): member O — `apresentou_resultados` (showcase Persua) → 35 · Prof. member Q — `apresentou_resultados`,`impacto_pmi`→ (nota: `impacto_pmi` é slug deliverable; em general usar `conduziu_pauta`) → 35.
- **05-07** (`5f4b01be`): member B — `apresentou_resultados`,`conduziu_pauta` (Aula Magna) → 40.
- **03-12** (`f8a7787b`): member C — `apresentou_resultados` → 35.
- **05-21** (`43135439`): Sávio — `apresentou_resultados`,`conduziu_pauta` (CPMAI deep-dive) → 40.
- **06-04** (`9ea5fc3c`): protagonistas do case Cteec / distrito de inovação (resolver nomes na ata) — `apresentou_resultados` → 35.
- **06-18** (`a029ce54`): Tribo 1 (radar) — `apresentou_resultados` → 35 · member Q — `mediou_decisao` (métricas) → 35.
- *(Reuniões de liderança excluídas por decisão do Vitor — não premiar.)*

### 4b. Deliverable (direto, creator conhecido)
- member H ×2 (atas Agentes Autônomos 03-23, 03-30) → `champion_deliverable` base 40 + critérios.
- member F (ata Talentos 04-06) → 40 + critérios.
- Vitor (ata Geral 04-09) → **checar** o initiative NULL antes (autoridade).

> **Para executar:** resolver cada nome → `member_id` (via `search_members`), confirmar presença (`attendance.present`) no evento, e rodar `award_champion` de dentro do hub. `justification` ≥50 chars por outorga (audit-load-bearing).

---

## 5. Flags de integridade (para reconciliar no hub)

1. ✅ **RESOLVIDO — as 3 gerais EXISTEM** (verificado via `list_initiative_events` 2026-07-02; total 11 gerais no C3, lista do hub estava capada). Todas com ata + presença. UUIDs: 05-21 `43135439…`, 06-04 `9ea5fc3c…`, 06-18 `a029ce54…`. Entram no champion `general` → **10 reuniões gerais elegíveis** no total.
2. **Conciliação de gravação — `youtube_url` NULL nas 3.** Não há tool MCP para gravar esse campo (`update_event_instance` não cobre) → sai por `execute_sql` **no hub**. SQL pronto:
   ```sql
   -- Vincular gravação YouTube às 3 Reuniões Gerais C3 (confirmar nomes de coluna antes de rodar)
   UPDATE events SET youtube_url='https://www.youtube.com/watch?v=6dR0C_08X88',
     recording_url='https://www.youtube.com/watch?v=6dR0C_08X88', recording_type='youtube', is_recorded=true
     WHERE id='43135439-4463-4aa5-9d72-0fa80948ca6c';  -- 2026-05-21 CPMAI
   UPDATE events SET youtube_url='https://www.youtube.com/watch?v=NPJ5fHyDKWU',
     recording_url='https://www.youtube.com/watch?v=NPJ5fHyDKWU', recording_type='youtube', is_recorded=true
     WHERE id='9ea5fc3c-8f4e-4e16-b7f1-5d3b871bf37f';  -- 2026-06-04 Governança
   UPDATE events SET youtube_url='https://www.youtube.com/watch?v=Lt2oYV9dlhA',
     recording_url='https://www.youtube.com/watch?v=Lt2oYV9dlhA', recording_type='youtube', is_recorded=true
     WHERE id='a029ce54-31ae-4d9e-b95d-c0cd92326f0c';  -- 2026-06-18 Radar
   ```
   Normalização adjacente (opcional, mesma passada): vários gerais têm `youtube_url` setado mas `recording_url`/`recording_type` NULL — o hub pode uniformizar num só UPDATE.
3. **Ata 04-09 com `initiative` NULL** (`c1a8e1c5`): autoridade de champion deliverable pode falhar — validar.
4. **Frontend `/gamification`:** chip "+30 Artefato" estava errado (backend `artifact_published`=15; o 30 é `deliverable_completed`). **Já corrigido** no PR #1070 (aberto, verde, merge é da sessão main).

---

## 6. Decisões abertas para o Vitor

1. **Premiar liderança?** Reuniões de liderança são `general` elegíveis, mas é reconhecimento entre pares da própria liderança — quer incluir ou só reuniões gerais abertas?
2. **Webinars/curadoria/pílulas** entram como **produção/showcase** (XP automático), não champion. Confirmar se quer que eu registre os autores (member S, member X, member V; painelistas) como `event_showcases`/`content_products` — isso é outro fluxo, também do hub.
3. **Profundidade:** premiar só os destaques (≤3/reunião) ou quer o CSV de `tribe_deliverables` (~60) para uma varredura de champion deliverable por iniciativa?
4. **Onde grava:** eu deixo as propostas prontas aqui e você roda no hub, ou prefere que a próxima sessão do hub leia este MD e execute os `award_champion` com tua aprovação item a item?

---

## 7. Diretório de `member_id` (resolvido via `search_members`, 2026-07-02)

| Nome | member_id | Tribo / papel |
|---|---|---|
| member N | `c8b930c3-62ec-4d38-881e-307cd57a44f7` | T4 Cultura & Change (líder) |
| member B | `c204ac61-4d39-42f2-8d28-814727b62e90` | T7 Governança (líder) |
| member F | `622ab18b-a8b4-46ff-b151-7bbd34394ed3` | T5 Talentos (líder) |
| member T | `f64ee70a-5d37-4670-9306-a5efe4666cd3` | T1 Radar (líder) |
| member S | `19b7ff75-bcb1-4a15-a8e1-006fc6822069` | Coord. Comitê Curadoria |
| Vitor Maia Rodovalho | `880f736c-3e76-4df4-9375-33575c190305` | GP / manager |
| member I | `92d26057-5550-4f15-a3bf-b00eed5f32f9` | T6 ROI (líder), co-GP |
| member H | `a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7` | T2 Agentes (líder) |
| member D | `293fcaf8-7dda-46f7-8e3b-1daf4c54f420` | T8 Inclusão |
| member E | `dc42d4c5-6e87-4284-afa7-ca3b1369a16f` | T2 Agentes |
| member G | `60ffebc2-0fe1-47c9-95db-1547bc4e70cc` | T1 Radar |
| member O | `f5dee40d-c13b-4b48-b454-1f45f105f47e` | T2 Agentes |
| member K | `ae04fc15-19c8-4a42-90d4-f248b09881b9` | T6 ROI |
| member V | `49836a70-a41e-4a0b-85b0-aa05b13d3f25` | T8 Coord. Curadoria |
| member P | `79dd3f46-b0e1-4920-9795-17cb3d42f7a7` | T7 Governança |
| member Q ✅ | `c562af94-4e80-4116-aeff-90bbc362058f` | T2 Agentes (base grava "member R", email `r_frana@…` — confirmado por Vitor = member Q) |
| member M ✅ | `279684f3-a6fa-4b7e-b96e-c665f69b7758` | T4 Cultura & Change (confirmado por Vitor) |
| member C | `63b87315-78ab-43f7-bb05-cc2e89682bbf` | T8 Inclusão (líder) |
| member A | `57fcf33c-25a3-4555-b358-a168a4151794` | T5 Talentos ("member J") |
| member L | `bb499ca6-254d-43bc-b38a-81ee986dbe3d` | T8 Inclusão (comms leader) — a "Maia" do 03-26 |

**Resolvidos por evidência de showcase:**
- **member D** (03-26 Manus) = **member D** `293fcaf8-7dda-46f7-8e3b-1daf4c54f420` — confirmado pelo showcase "Manus AI" atribuído a ele no evento `ba2b9bf9` (member W também presente, mas o showcase é do member Y).
- **Sávio** (05-21 CPMAI) → **convidado EXTERNO** (organizado por member I), não é membro → **não atribuível**. Remover do cálculo.

## 9. ⭐ ACHADO — protagonismo já é `event_showcases` (fonte autoritativa, pilar produção)

O `get_event_detail` mostra que cada reunião geral já registra os protagonistas como **showcases**, com `member_id` + `showcase_type` + XP automático:
`case_study` **25** · `tool_review`/`showcase`/`prompt_week` **20** · `awareness`/`quick_insight` **15**.

**Isso é a régua real do "protagonista de reunião" — não os meus parses de descrição.** A extração dos capítulos do YouTube foi um bom proxy, mas os `event_showcases` são o registro autoritativo (onde existem).

**Cobertura de showcase por reunião geral C3** (`showcase_count`):
| Reunião | showcases | Gap |
|---|---|---|
| 03-12 | 0 | ⚠️ protagonistas na ata, sem showcase registrado |
| 03-19 | 3 | ok |
| 03-26 | 4 | ok (member B/member A/member D/member C) |
| 04-02 | 5 | ok |
| 04-09 | 7 | ok |
| 04-23 | 2 | verificar cobertura (member O/Persua?) |
| 05-07 | 0 | ⚠️ Aula Magna member B sem showcase |
| 05-21 | 2 | ok |
| 06-04 | 2 | ok |
| 06-18 | 0 | ⚠️ Tribo 1 radar sem showcase |

**A conciliação de gamificação real:** as reuniões com `showcase_count` 0 (03-12, 05-07, 06-18) têm protagonistas claros na ata/vídeo mas **sem showcase registrado** → registrar via `register_showcase` fecha o XP de protagonismo desses membros. As demais já estão pontuadas pelo showcase.

**Champion `general` (award_champion) é uma camada A MAIS** de reconhecimento sobre isso, sujeita aos caps 3/reunião — reservar para os destaques excepcionais, não repetir o que o showcase já premiou.

## 10. Showcases — quadro autoritativo (puxado ao vivo de `get_event_detail`, 2026-07-02)

### 10a. Já REGISTRADOS (25 showcases em 7 reuniões — já pontuados, não mexer)
| Reunião | Showcases (membro · tipo · XP) |
|---|---|
| 03-19 | member N `quick_insight`15 · member D `tool_review`20 · member E `case_study`25 |
| 03-26 | member B `case_study`25 · member J `tool_review`20 · member D `tool_review`20 · member C `quick_insight`15 |
| 04-02 | member K `quick_insight`15 · member B `awareness`15 · member N `case_study`25 · member P `tool_review`20 · Vitor `tool_review`20 |
| 04-09 | member N `awareness`15 · member G `awareness`15 · member F `awareness`15 · member C `case_study`25 · member T `case_study`25 · Vitor `case_study`25 · member I `case_study`25 |
| 04-23 | member O `tool_review`20 · member Q `awareness`15 |
| 05-21 | member C `case_study`25 · member N `tool_review`20 *(Sávio externo, não pontua)* |
| 06-04 | member D `case_study`25 · member V `quick_insight`15 |

### 10b. GAPS — ✅ EXECUTADO 2026-07-02 (12 showcases registrados, 240 XP)
Todos os 12 abaixo foram gravados via `register_showcase` (aprovação do Vitor). IDs retornados registrados na plataforma. XP por membro deste passe: member C +45 · member B +40 · member N +35 · member D +25 · member G +25 · member M +20 · member U +20 · member W +15 · member Q +15.

**05-07** (`5f4b01be-9c12-4647-af22-c5158d86fd5b`) — reunião rica, nenhum showcase registrado:
| member_id | membro | showcase_type | XP | título proposto |
|---|---|---|---|---|
| `c204ac61…` | member B | case_study | 25 | Aula Magna: Tipos de IA, Arquiteturas e LLMs |
| `279684f3…` | member M | tool_review | 20 | Tribo 4: IA na Gestão de Mudança + estratégia ágil de conteúdo |
| `c8b930c3…` | member N | tool_review | 20 | Tribo 4: IA na Gestão de Mudança (co-apresentação) |
| `63b87315…` | member C | case_study | 25 | Tribo 8: Neurodivergência + demo Goblin.tools |
| `293fcaf8…` | member D | case_study | 25 | Tribo 8: Neurodivergência + demo Goblin.tools (co) |
| `d29c42fd…` | member W | awareness | 15 | Relato do Congresso PMI (Gramado) |

**06-18** (`a029ce54-31ae-4d9e-b95d-c0cd92326f0c`):
| member_id | membro | showcase_type | XP | título proposto |
|---|---|---|---|---|
| `60ffebc2…` | member G | case_study | 25 | Tribo 1: Radar Tecnológico de IA |
| `8f171d94…` | member U | tool_review | 20 | Tribo 1: Claude como juiz + business case MIT (co) |
| `c562af94…` | member Q | awareness | 15 | Métricas objetivas de avaliação (referência Microsoft, Likert) |
| `c8b930c3…` | member N | awareness | 15 | Playbook de submissão a eventos PMI |
| `c204ac61…` | member B | awareness | 15 | Radar de iniciativas de IA em outros capítulos PMI |

**03-12** (`f8a7787b-112e-441f-8271-f906c47ab5aa`) — reunião de alinhamento/plataforma, protagonismo mais fino:
| member_id | membro | showcase_type | XP | título proposto |
|---|---|---|---|---|
| `63b87315…` | member C | tool_review | 20 | Workspace no Notion (bancos + agente de pesquisas) |

*(03-12: member J propôs podcast e member B relatou webinar de capítulo — discussão/proposta, não showcase-demo; deixei de fora. Incluir se você considerar protagonismo.)*

**Total proposto de gap-fill:** 12 showcases (6 no 05-07, 5 no 06-18, 1 no 03-12). Cada um é um `register_showcase(event_id, member_id, showcase_type, title, ...)`. **Não disparado — aguarda teu OK item a item ou em bloco.**

## 8. Payloads prontos

### 8a. `talk` 25 XP (pilar produção — NÃO é `award_champion`; grounded no papel `speaker` da iniciativa)
| Recipient | member_id | Iniciativa fonte | XP |
|---|---|---|---|
| member N | `c8b930c3…` | SESTEC `6e9af7a8…` + ANSI `56f0cde5…` | **50** (2×) |
| member T | `f64ee70a…` | SESTEC `6e9af7a8…` | 25 |
| member S | `19b7ff75…` | SESTEC `6e9af7a8…` | 25 |
| member B | `c204ac61…` | ANSI `56f0cde5…` | 25 |
| member F | `622ab18b…` | ANSI `56f0cde5…` | 25 |
| member I | `92d26057…` | ANSI `56f0cde5…` (role speaker) | 25 |

*Edge moderador resolvido pela plataforma: no SESTEC, Vitor = observer e member D = coordinator (não speaker) → sem `talk` por padrão. member I no ANSI está como speaker → recebe.*

### 8b. `champion_deliverable` (via `award_champion`, surface `deliverable`)
| Recipient | member_id | context (ata) | context_kind | base+crit |
|---|---|---|---|---|
| member H | `a8c9af17…` | `df735a51…` (Agentes 03-30) | artifact | 40 + crit |
| member H | `a8c9af17…` | `76c39319…` (Agentes 03-23) | artifact | 40 + crit |
| member F | `622ab18b…` | `dcded397…` (Talentos 04-06) | artifact | 40 + crit |
| Vitor Maia Rodovalho | `880f736c…` | `c1a8e1c5…` (Geral 04-09) | artifact | ⚠️ initiative NULL — checar autoridade |

### 8c. `champion_general` — protagonistas resolvidos (Vitor seleciona ≤3/reunião)
member N `c8b930c3…` · member B `c204ac61…` · member F `622ab18b…` · member E `dc42d4c5…` · member G `60ffebc2…` · member O `f5dee40d…` · member K `ae04fc15…` · member P `79dd3f46…` · member I `92d26057…` · (member Q, member M, member C, member A, Maia, member D = confirmar).
