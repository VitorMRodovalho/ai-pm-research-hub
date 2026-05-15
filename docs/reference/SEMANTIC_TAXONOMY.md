# Taxonomia semântica — eventos, reuniões, atas, artefatos, atividades, action-items, XP

**Status:** Draft p161 — pendente alinhamento PM/curadores antes de tocar código
**Created:** 2026-05-14 (sessão p161 — TIER A gamification + semantic clarity)
**Audience:** PM, curadores, líderes de tribo, agentes IA que tocam eventos / atas / gamificação
**Cross-refs:** [ADR-0050](../adr/ADR-0050-gamification-leaderboard-v2-and-opt-out.md) (leaderboard v2 + opt-out), [ADR-0051](../adr/ADR-0051-gamification-leaderboard-scope-filter.md) (scope filter), [ADR-0062](../adr/ADR-0062-gamification-streak-and-cycle-points.md) (streak + cycle points), [V4 Authority Model](./V4_AUTHORITY_MODEL.md) (auth equivalente para autoridade)

---

## Por que este doc existe

O vocabulário da plataforma cresceu organicamente em duas frentes:
1. **Modelo de dados** — tabelas/colunas/RPCs nomeadas conforme o engenheiro que codou cada feature (`events.type`, `meeting_action_items.kind`, `tribe_deliverables`, `meeting_artifacts`).
2. **Voz do membro** — strings de UI/i18n usam termos institucionais herdados (`reunião`, `ata`, `artefato`, `entregável`, `champion`).

Há **drift entre as duas camadas**. Mesma palavra significa coisas distintas em contextos distintos; conceitos distintos compartilham coluna. Antes de redesenhar a UX de transparência de XP (TIER A item 2 do handoff p161), precisamos pinar o que cada termo significa. Sem isso:
- Tooltips de XP referenciam coisas que membros não reconhecem
- Admin não sabe se "completar uma ata" deve gerar pontos
- ADRs futuros sobre XP-rules-config ficariam desalinhados com a linguagem dos membros

Este doc é a **fonte canônica** para termos. Não decide o modelo XP (isso vai virar ADR-XXXX após este doc ser aceito). Decide **vocabulário e fronteiras conceituais**.

---

## Os 6 termos canônicos

### 1. Evento

**Definição:** unidade temporal agendada da plataforma, com `data + duração + participantes`. Tudo que tem horário marcado e pode ter presença é um evento.

**Tabela canônica:** `events` (~289 rows hoje)

**Subtipos (`events.type`):**
| valor | volume | uso | termo de membro |
|---|---|---|---|
| `tribo` | 151 | reunião recorrente de tribo | **Reunião de tribo** |
| `geral` | 72 | reunião geral semanal Núcleo | **Reunião geral** |
| `entrevista` | 35 | entrevista de seleção | **Entrevista** |
| `1on1` | 13 | mentoria/1:1 | **Mentoria** ou **1:1** |
| `lideranca` | 9 | reunião de líderes | **Reunião de liderança** |
| `webinar` | 4 | webinar (espelho em `webinars`) | **Webinar** |
| `parceria` | 2 | encontro de parceria externa | **Reunião com parceiro** |
| `evento_externo` | 2 | participação em evento externo | **Evento externo** |
| `kickoff` | 1 | abertura de ciclo | **Kickoff** |

**Eixo paralelo (`events.nature`):**
- `recorrente` (136) — agendamento periódico via `recurring_event_groups`
- `avulsa` (113) — pontual
- ~~`entrevista_selecao` (35)~~ — **DEPRECATED 2026-05-14 (migration 20260644000000)**: era redundante com `type='entrevista'`, colapsado em `NULL`
- `kickoff` (5) — special-occasion marker; aparece em `type=tribo` (4 — kickoff-de-tribo) + `type=kickoff` (1 — kickoff geral). NÃO é redundante com type.

**Status Q1 (decidido PM 2026-05-14):** os dois eixos são **ortogonais** (`type`=propósito, `nature`=padrão de agendamento + special-occasion). Mantidos ambos. Apenas `nature='entrevista_selecao'` deprecado por ser 1:1 com `type=entrevista`.

**Status (p160 soft-cancel):** `events.status ∈ {scheduled, cancelled, completed}` com `cancelled_at/cancelled_by/cancellation_reason`. Evento cancelado **preserva auditoria + não penaliza presença** (ISO-week sibling rule no grid).

**RPCs principais:** `create_event`, `update_event`, `cancel_event_occurrence`, `uncancel_event_occurrence`, `drop_event_instance`, `get_event_detail`, `get_events_with_attendance`, `get_initiative_events_timeline`, `get_tribe_events_timeline`.

---

### 2. Reunião (subtipo de evento)

**Definição:** subconjunto de eventos cujo **propósito principal é deliberar + registrar**. Ou seja: tem agenda + ata + action items. Não é uma tabela separada — é um **role semântico** que alguns tipos de evento assumem.

**Tipos que tipicamente viram "reunião":**
- `tribo`, `geral`, `lideranca`, `1on1`, `parceria`, `kickoff`

**Tipos que tipicamente NÃO viram "reunião":**
- `webinar` (é entrega pública, não deliberação interna)
- `evento_externo` (não-controlado)
- `entrevista` (é avaliação 1:1, não deliberação coletiva)

**Marcadores DB que sinalizam "este evento é uma reunião":**
- `events.agenda_text` ou `events.agenda_url` preenchido
- `events.minutes_text` ou `events.minutes_url` preenchido
- Linha correspondente em `meeting_artifacts` (event_id FK)
- Linhas em `meeting_action_items` (event_id FK)
- RPC `meeting_close` rodado para o event_id

⚠ **Implicação:** "reunião" é um **rótulo de UX** sobre o conceito mais geral de evento. Não criar tabela `meetings` separada — vai duplicar `events`.

**RPCs com "meeting" no nome:** `get_meeting_detail`, `get_meeting_notes_compliance`, `get_meeting_preparation`, `meeting_close`, `list_meetings_with_notes`, `auto_complete_first_meeting`, `create_next_geral_meeting`. Todos operam sobre o mesmo `events.id`.

---

### 3. Ata

**Definição:** registro estruturado **publicado** do que aconteceu numa reunião. Não é o brouillon das anotações; é o documento curado que vira fonte institucional.

⚠ **Confusão atual:** "ata" hoje vive em **dois lugares**:

| Camada | Onde mora | Forma | Status |
|---|---|---|---|
| **Light** | `events.minutes_text` + `events.minutes_url` + `events.minutes_posted_at` | string + link | inline, sempre present quando reunião teve registro mínimo |
| **Rica** | `meeting_artifacts` (event_id FK, `is_published` flag) | tabela com `agenda_items[]` + `deliberations[]` + `recording_url` + `page_data_snapshot` jsonb | linha por ata "completa" |

**Drift detectado:** uma reunião pode ter:
- Só `events.minutes_text` (registro mínimo) — sem linha em `meeting_artifacts`
- `meeting_artifacts` publicado mas `events.minutes_text` vazio (curador subiu só na tabela rica)
- Ambos preenchidos com conteúdos divergentes

**Recomendação canônica:** **"Ata" = linha em `meeting_artifacts` com `is_published=true`.** O campo `events.minutes_text` deve ser tratado como **rascunho/legado**. Treat as **questão aberta Q2** se quisermos forçar migration consolidando.

**RPCs principais:** `list_meeting_artifacts`, `list_initiative_meeting_artifacts`, `get_meeting_notes_compliance`, `upsert_event_minutes`.

**Compliance:** `get_meeting_notes_compliance` audita quais reuniões estão sem ata publicada — métrica de saúde por tribo/cycle.

---

### 4. Artefato

⚠ **Termo sobrecarregado** — dois usos legítimos coexistem hoje:

#### 4a. Artefato-ata (uso técnico do DB)

**Definição:** linha em `meeting_artifacts`. É a forma rica de uma ata (ver termo 3). Tabela usa "artifact" porque cobre **mais que minutes** (agenda + deliberations + snapshot + recording).

#### 4b. Artefato-pesquisa (uso institucional / KPI)

**Definição:** produto final de pesquisa de uma tribo num ciclo — artigo, whitepaper, protótipo, blog post, vídeo, webinar gravado. É o output que a tribo entrega ao ciclo.

**Tabela canônica:** `tribe_deliverables` (campos `title`, `description_i18n`, `status`, `artifact_id` opcional, `cycle_code`)

**i18n vigente:**
- `kpis.subtitle` = "1-2 **artefatos** de qualidade por tribo"
- `tribes.deliverables` = "**Entregáveis** do Ciclo"
- `admin.analytics.funnelDesc` = "Inscritos → onboarding → tribo → **artefato publicado**"

→ String institucional usa "artefato" para o produto-final. String de tribo usa "entregável" como sinônimo. **Os dois apontam para o mesmo conceito (4b)**, mas diferem da semântica de 4a.

**Recomendação canônica:** 
- **Internamente (DB/RPC):** manter `meeting_artifacts` para 4a (já é o nome) e `tribe_deliverables` para 4b (já é o nome).
- **Externamente (UX/i18n):** usar **"Artefato de pesquisa"** ou **"Entrega da tribo"** consistentemente para 4b. Reservar **"Ata"** para 4a (porque "artefato" abstrato confunde membro).
- Tratar como **questão aberta Q3** — alinhar com líderes de tribo + curadores antes de mudar copy.

**RPCs principais (4b):** `list_initiative_deliverables`, `list_tribe_deliverables`, `upsert_tribe_deliverable`, `get_tribe_deliverables`.

---

### 5. Atividade-de-artefato / Action item

**Definição:** unidade acionável **derivada de uma reunião** — uma tarefa que sai como compromisso (responsável + prazo) e precisa ser fechada.

**Tabela canônica:** `meeting_action_items` (event_id FK obrigatório)

**Campos relevantes:**
- `description` (o quê)
- `assignee_id` ou `assignee_name` (quem)
- `due_date` (quando)
- `status` (`open` único valor observado; falta `resolved`/`closed` no enum efetivo)
- `kind` (`action` 5 | `followup` 1 — pouco usado)
- `carried_to_event_id` (rollover para próxima reunião)
- `board_item_id` (vínculo opcional com Kanban)
- `checklist_item_id` (vínculo opcional com checklist de board card)
- `resolved_at` / `resolved_by` / `resolution_note`

⚠ **Drift detectado:**
- Volume baixíssimo (6 rows totais) — feature pode estar sub-utilizada vs. expectativa
- `status` enum não explícito; só `open` em uso. Provável que `resolved_at NOT NULL` seja o sinal real de fechamento
- Vínculo triplo (event + board + checklist) torna análise de produtividade confusa
- "Atividade-de-artefato" é termo do PM no handoff; **DB não usa** essa string em lugar nenhum

**Termo canônico (decidido PM 2026-05-14):** **"Ação"** (singular) / **"Ações"** (plural). Sub-string contextual quando ambíguo: **"Ação da reunião"**.

**Justificativa:** a codebase já convergiu para "Ação" — UI usa `meetings.actions.title='Ações'`, `meetings.actions.add='Adicionar Ação'`. PT-BR contagem: ação (21) > atividades (12) > atividade (10) > tarefas (3) > compromisso (1). Zero refactor necessário. Termo do handoff PM ("atividades-de-artefatos") foi descritivo — produção já tinha escolhido "Ação".

**Aplicação:**
- **Internamente:** manter `meeting_action_items` (nome técnico inalterado)
- **Externamente (UX/i18n):** "Ação" / "Ações" — qualquer string que use "atividade" para `meeting_action_items` deve migrar para "ação" (não há atualmente, validado por grep)

**RPCs principais:** `create_action_item`, `resolve_action_item`, `manage_action_items`, `list_meeting_action_items`.

---

### 6. Champion / XP / Gamificação

**Definição (XP):** ponto computado e armazenado em `gamification_points`. Unidade quantitativa do membro.

**Tabela canônica:** `gamification_points` (~1331 rows)

**Categorias atuais (`gamification_points.category`):**
| category | volume | descrição |
|---|---|---|
| `attendance` | 1049 (79%) | Presença em evento |
| `trail` | 95 | Avanço em trilha de onboarding |
| `knowledge_ai_pm` | 61 | Conclusão de módulo do knowledge module |
| `specialization` | 46 | Conclusão de track de especialização |
| `badge` | 35 | Badge externa (Credly) linkada |
| `cert_pmi_senior` | 18 | Certificação PMI Senior |
| `showcase` | 12 | Apresentação em evento (showcase) |
| `course` | 5 | Curso externo registrado |
| `cert_pmi_entry/mid/practitioner/cpmai` | 10 total | Outras certificações |

**Gap detectado (TIER A item 2 PM):** **NÃO existem hoje categorias para:**
- ❌ Champions — apenas string em i18n (`rules.dashboard.text` = "Horas, champions e gamificação"), zero implementação DB
- ❌ Ata publicada — `meeting_artifacts.is_published=true` não gera ponto
- ❌ Action item resolvido — `meeting_action_items.resolved_at IS NOT NULL` não gera ponto
- ❌ Deliverable concluído — `tribe_deliverables.status='completed'` não gera ponto

**Definição (Champion) — atualizada 2026-05-14 PM:**

Champion = **reconhecimento atribuído manualmente por liderança** a membros que se destacaram em momentos específicos. Hoje vive **apenas** como prática informal em reuniões gerais ("protagonistas do dia"). PM quer expandir para 3 superfícies, **mantendo a atribuição manual mas suportada por critérios objetivos auditáveis**:

1. **Champion em reunião geral** — atribuído na reunião pelo líder do Núcleo (já existe como prática, falta sistema)
2. **Champion em reunião de tribo/iniciativa** — atribuído pelo líder de tribo durante/após a reunião usando critérios pré-definidos
3. **Champion por entregável** — atribuído quando artefato/pacto combinado é concluído com qualidade acima do baseline

**Constraints (PM 2026-05-14):**
- Atribuição **manual**, não automática (preserva julgamento qualitativo da liderança)
- Critérios **objetivos** — não "achei que ele foi bem", e sim checklist preenchido pelo líder (ex: "X conduziu agenda · Y trouxe insight novo · Z destravou bloqueio")
- **Auditoria obrigatória** — quem deu, quando, em qual evento/entregável, com que critério, com timestamp e justificativa textual
- **Ranking visível em 3 níveis** (tribo / iniciativa / pessoa) para transparência + engajamento
- Champion conta como categoria XP separada (não vira "presença +5" — vira `champion` com lógica própria)

**Implicação técnica:**
- Nova tabela `champions_awarded` (member_id, awarded_by, event_id OR deliverable_id, criteria_jsonb, justification_text, awarded_at, value_points)
- RPC `award_champion(p_member_id, p_context_id, p_context_kind, p_criteria, p_justification)` com gate V4 — `manage_event` para reunião, líder de tribo do contexto, etc
- RPC `get_champions_ranking(p_scope_kind, p_scope_id, p_cycle_code)` retornando ranking por scope
- Categoria nova em `gamification_points` (`champion_general | champion_tribe | champion_deliverable`)
- UI: card em /admin/attendance + /admin/tribe/[id]/meetings + /admin/deliverables para "Dar Champion"
- UI: leaderboard em /tribe/[id] + /initiative/[id] + /profile/me mostrando champions recebidos + critério

⚠ **Drift atual:** zero implementação. Concept-only. Roteiro de implementação é **ADR-XXXX (a criar)** + 1-2 migrations + RPCs + UI.

**RPCs principais:** `get_my_xp_and_ranking`, `get_member_cycle_xp`, `get_initiative_gamification`, `get_tribe_gamification`, `get_gamification_leaderboard`, `get_my_gamification_stats`, `get_member_gamification_stats`, `set_my_gamification_visibility`, `sync_attendance_points`.

**Streak / cycle points (ADR-0062):** já entregue. Membro vê `current_streak_count` + `points_this_cycle`. Algoritmo: `sort_order + row_number()` sobre cycles com pontos, grace de 1 ciclo.

**Opt-out LGPD (ADR-0050):** `members.gamification_opt_out` permite remover-se do leaderboard público sem perder histórico.

---

## Mapa consolidado: termo ↔ DB ↔ UX

| Termo PM (handoff) | Tabela DB | UX i18n vigente | Estado |
|---|---|---|---|
| events | `events` | "Evento" / "Reunião" (inconsistente) | ✅ modelado |
| meetings | `events` (subset) | "Reunião" | ⚠ semântica derivada, sem flag explícita |
| atas | `events.minutes_*` + `meeting_artifacts` | "Ata" | ⚠ dupla camada light/rica |
| artefatos | `meeting_artifacts` (4a) OU `tribe_deliverables` (4b) | "Artefato" (4b) / "Entregável" (4b) | ⚠ termo sobrecarregado |
| atividades-de-artefatos | `meeting_action_items` | (sem string canonical) | ⚠ termo PM não tem aderência DB/UX |
| action-items | `meeting_action_items` | (sem string canonical) | ⚠ idem |
| (champions) | — | "Champions" (i18n string única) | ❌ não modelado |
| XP | `gamification_points` | "XP" / "Pontos" / "Gamificação" | ✅ modelado |

---

## Questões abertas (precisam decisão PM antes de tocar código)

### Q1 — `events.type` × `events.nature` (✅ DECIDIDO 2026-05-14 — Opção A refinada)

**Decisão PM:** manter os dois eixos como **ortogonais** (`type`=propósito, `nature`=padrão de agendamento + special-occasion).

**Cleanup aplicado** (migration `20260644000000_p161_taxonomy_cleanup_events_nature_and_comments.sql`):
- `nature='entrevista_selecao'` (35 rows) → `NULL` (era 1:1 redundante com `type='entrevista'`)
- `COMMENT ON COLUMN events.type` + `events.nature` adicionados documentando dimensões

**Por que não colapsar em 1 eixo:** `nature='kickoff'` aparece em `type=tribo` (4 — kickoff-de-tribo) + `type=kickoff` (1 — kickoff geral). Colapsar perderia info ortogonal.

**Resíduo a observar (não bloqueia Q1):** 5 events `nature=recorrente` SEM `recurrence_group` (órfãos) e 88 events `nature=avulsa` COM `recurrence_group` (occurrence detached). Não tratados nesta migration — são candidatos a audit separado de data sanity.

### Q2 — Consolidar atas light × rica?
- Hoje `events.minutes_text` + `meeting_artifacts` co-existem
- **Opção A:** deprecar `events.minutes_text`, forçar uso de `meeting_artifacts` (migration de backfill + trigger sync legado)
- **Opção B:** manter ambos; declarar `meeting_artifacts` como "publicado" e minutes_text como "rascunho"
- Implicação: hoje qualquer RPC que lê ata olha um OU outro, gerando drift visível

### Q3 — Nomenclatura de artefato (4a vs 4b) na UX (✅ DECIDIDO 2026-05-14 — Opção A)

**Decisão PM:** UX está OK como está; só clarificar a sobreposição técnica.

**Achado decisivo:** página `/meetings` usa "Atas de Reunião" (4a) e página `/artifacts` usa "Artefatos do Núcleo" (4b) — **rotas separadas + i18n consistente**. A confusão é só técnica (nome da tabela `meeting_artifacts` colide com a página `/artifacts`).

**Aplicado** (mesma migration `20260644000000`): `COMMENT ON TABLE meeting_artifacts` documentando que ela NÃO é a fonte de `/artifacts` (é `tribe_deliverables`).

**Renomear `meeting_artifacts` → `meeting_minutes`** descartado: custo alto (15+ RPCs + MCP + frontend) vs zero benefício (membro não vê o nome técnico).

### Q4 — Nome canônico para action items em PT-BR (✅ DECIDIDO 2026-05-14 — Opção B "Ação")

**Decisão PM:** **"Ação"** (singular) / **"Ações"** (plural). Sub-string contextual quando ambíguo: "Ação da reunião".

**Achado decisivo:** codebase já convergiu — UI usa `meetings.actions.title='Ações'`, `meetings.actions.add='Adicionar Ação'`. Word counts PT-BR: ação(21) > atividades(12) > atividade(10) > tarefas(3) > compromisso(1).

**Aplicação:** zero refactor necessário; "ação" já é o termo de produção. Mantida coluna `meeting_action_items.kind` (`action`/`followup`) — anglicismo OK em column name técnico.

⚠ **Bloqueio para futuro:** se alguém propor mudar para "atividade" ou "tarefa" numa string i18n, **bloquear** PR e referenciar Q4 aqui.

### Q5 — Champion: definição operacional (PM 2026-05-14 → Opção B refinada)

PM definiu (ver termo 6 acima): atribuição **manual com critérios objetivos** + auditoria + ranking 3 níveis. Direção é **Opção B** (era "indicação manual"), agora refinada com:

- **Opção B' (refinada — recomendada):** atribuição manual via UI por líder de evento/tribo/entregável, com checklist de critérios objetivos por contexto, justificativa textual obrigatória, auditoria completa em tabela própria, e categoria XP separada com pontuação configurável.

**Sub-questões para PM decidir antes de migration:**
- **Q5.1:** Quem pode dar Champion em reunião geral? (Sugestão: GP + co-GP + curadores)
- **Q5.2:** Quem pode dar Champion em reunião de tribo? (Sugestão: líder + co-líder de tribo do contexto)
- **Q5.3:** Quem pode dar Champion por entregável? (Sugestão: líder de tribo que aprova o entregável)
- **Q5.4:** Critérios objetivos por contexto — checklist final por tipo de Champion (lista pré-definida que o líder marca)
- **Q5.5:** Valor em XP de cada Champion — fixo (ex: 50 pts cada) ou variável por critérios marcados?
- **Q5.6:** Limite de Champions por evento/ciclo? (Evitar inflação — ex: máx 3 Champions por reunião)
- **Q5.7:** Champion é revogável? (Cenário: líder se enganou; precisa de fluxo de revogação com auditoria)

### Q6 — Quais categorias adicionar ao XP?
- TIER A item 2 PM: "presenças/champions/entregas"
- **Presenças** ✅ já existe (category=`attendance`, 1049 rows)
- **Champions** → Q5 (3 sub-categorias: `champion_general` / `champion_tribe` / `champion_deliverable`)
- **Entregas** ❌ não existe. Candidatos:
  - `tribe_deliverables.status='completed'` → category novo `deliverable_completed`
  - `meeting_artifacts.is_published=true` → category novo `artifact_published`
  - `meeting_action_items.resolved_at IS NOT NULL` → category novo `action_resolved`
- Cada categoria nova precisa: pontuação (quantos pts), trigger (quando computa), idempotência (evitar duplicar), retroatividade (rodar over histórico ou só forward?)
- Implicação direta para Q7: **deveria virar admin-config-driven (ADR-XXXX) ou hardcoded em RPC?**
- **Cross-ref Q8:** novas categorias de certificações PMI optional entram aqui também (mas em Onda 2)

### Q7 — XP rules: config-driven (admin UI) ou hardcoded?
- Handoff TIER A item 4: "Possível ADR pra modelo XP rules (config-driven via admin)"
- **Opção A — hardcoded:** rules vivem em RPCs (`sync_attendance_points` calcula pts), admin não edita
- **Opção B — config-driven:** nova tabela `gamification_rules` (category, pts, trigger_kind, active), admin UI edita, RPCs leem
- Trade-off: Opção B alinha com ADR-0009 (config not code) mas tem custo inicial maior + risco de admin desconfigurar regras

### Q8 — Calibragem de certificações (escopo Onda 2 confirmado PM)

**Constraint sagrado (PM 2026-05-14):** as **6 obrigatórias** (mapeadas hoje como `cert_pmi_entry|mid|practitioner|senior` + `cert_cpmai`) **não podem ser tocadas**. Critério de elegibilidade do membro é fixo.

**Gap atual:** PMI passou a oferecer **rota de mini-certificações IA** que não estão mapeadas. Suspeitos identificados pelo PM:
| Curso PMI | PDU | Status atual |
|---|---|---|
| Free Introduction to CPMAI™ — PT-BR | 3 | ❌ não mapeado |
| PMI-CPMAI™ Exam Prep Course — PT-BR | 21 | ❌ não mapeado |
| PMI Essentials: Seven AI Project Patterns | 5 | ❌ não mapeado |
| AI in Agile Delivery | 5 | ❌ não mapeado |
| PMI Essentials M.O.R.E. Maximizing Project Success | 5 | ❌ não mapeado |
| Leading AI Transformation | 0 | ❌ não mapeado |

**Sub-questões para PM decidir (Onda 2):**
- **Q8.1:** Cada mini-cert nova vira categoria `cert_*` ou usa `course` genérico (que já existe, 5 rows)?
- **Q8.2:** Valor em XP de cada mini-cert é proporcional ao PDU (ex: 3 PDU = 30 pts) ou flat (todos = 50 pts)?
- **Q8.3:** Mini-cert de 0 PDU (Leading AI Transformation) vale XP fixo? (Sugestão: vale, como reconhecimento de tempo investido mesmo sem PDU oficial)
- **Q8.4:** Onde se registra a completion? `members.pmi_certifications` jsonb existente? Nova tabela `member_courses_completed`?
- **Q8.5:** PMI Credly emite badge para essas mini-certs? Se sim, integração via `link_my_credly_badge` (RPC existente) é o caminho?
- **Q8.6:** Backfill: aceitar evidência manual de completion (PDF/screenshot do PMI dashboard) ou exigir badge Credly?

**Status sessão p161:** Q8 explícitamente marcado **"Onda 2 — após primeira análise e implementação"** pelo PM. Não incluir em Fase 1-4 de p161. **Mas:** Q6 categoria nova `course_pmi_optional` (ou similar) deve ser definida em Q6 de forma que Onda 2 não pinte canto.

---

## Mapa XP: o que gera pontos hoje + o que NÃO gera

| Ação do membro | Gera XP? | Categoria | Trigger técnico |
|---|---|---|---|
| Presença em reunião | ✅ | `attendance` | `sync_attendance_points` quando `attendance.present=true` |
| Falta em reunião | ❌ | — | (sem penalidade — soft-cancel pattern p160) |
| Apresentar showcase no evento | ✅ | `showcase` | `register_event_showcase` RPC |
| Avançar passo de trilha onboarding | ✅ | `trail` | `complete_onboarding_step` RPC |
| Concluir módulo knowledge AI/PM | ✅ | `knowledge_ai_pm` | módulo trigger |
| Concluir specialization track | ✅ | `specialization` | track trigger |
| Linkar badge Credly | ✅ | `badge` | `link_my_credly_badge` RPC |
| Receber certificado PMI | ✅ | `cert_pmi_*` | `issue_certificate` RPC |
| Publicar ata (`meeting_artifacts.is_published=true`) | ❌ | — | (TIER A gap) |
| Resolver action item | ❌ | — | (TIER A gap) |
| Completar tribe deliverable | ❌ | — | (TIER A gap) |
| Receber título "Champion" | ❌ | — | (Q5 — conceito não modelado) |
| Comentar em document chain (ADR-0041) | ❌ | — | (open question — vale XP?) |
| Curar / aprovar artigo da tribo | ❌ | — | (open question — vale XP?) |

**Concentração:** hoje 79% dos pontos vêm de presença. PM quer **diluir** essa concentração reconhecendo outros tipos de contribuição.

---

## Recomendações para sessão p161

**Fase 1 — alinhar terminologia (este doc + decisão PM)** — ~1h
- PM lê Q1-Q7 acima
- PM decide opção por questão OU posterga (deixa marcado "pendente")
- Atualizar este doc com decisões → seção "Decisões PM 2026-05-14"

**Fase 2 — UX transparency (sem mudar XP rules)** — ~2h
- Tooltip "Como ganho XP?" na página /gamification + /profile/me
- Cada linha de `gamification_points` mostra `category` legível + link para regra (sem editar regra)
- Member leaderboard breakdown formula: "150 pts = 80 presença + 40 trilha + 30 badge"
- **Zero schema change.** Só RPC `get_my_xp_breakdown` (estruturação do que já existe) + UI.

**Fase 3 — categorias XP novas (se PM aprovar Q6)** — ~3-5h
- Migration: ADR-XXXX define `category` novos
- RPC `sync_deliverable_points` / `sync_artifact_points` / `sync_action_resolved_points`
- Triggers AFTER UPDATE em tabelas-fonte para pontuação idempotente
- Backfill opcional (decidir cutoff date)

**Fase 4 — ADR XP rules config-driven (se PM aprovar Q7)** — ~4-6h
- Nova tabela `gamification_rules`
- Admin UI em `/admin/gamification`
- RPCs lêem da tabela em vez de hardcoded
- Feature flag para shadow mode (rodar paralelo + comparar)

**Fase 5 — Champion (se PM aprovar Q5)** — variável
- Opção A: trivial (~30min, derivado do leaderboard)
- Opção B: feature dedicada (~6-10h, workflow + UI)
- Opção C: requer ADR + ~8h

---

## Anti-pattern: copy hot-fix sem alinhar taxonomia

**Sintoma:** alguém troca "evento" → "reunião" numa string i18n específica porque "ficou melhor", sem alinhar com o resto. Acumula drift entre páginas (`/admin/attendance` diz "evento", `/admin/tribe/X` diz "reunião", `/hero` diz "encontro").

**Risco:**
- Membro vê 3 palavras diferentes para mesma entidade → desconfiança da plataforma
- Curador escreve docs e usa o termo errado → drift sedimenta
- Agente IA (MCP) responde inconsistente para mesma pergunta

**Como evitar:**
- Antes de trocar string referente a um dos 6 termos canônicos, abrir este doc + ver qual é o termo aprovado pelo PM
- Se o termo aprovado ainda é "pendente", levantar com PM antes de mudar
- Mudanças de copy em massa entram como PR único (não scatter)

---

## Quando este doc precisa de update

- **PM resolve uma das Q1-Q7:** mover decisão para seção "Decisões PM" abaixo, atualizar tabela do termo afetado
- **Categoria nova de XP adicionada:** atualizar "Mapa XP" + categoria na tabela do termo 6
- **Tabela DB nova introduzida no domínio (events/meetings/atas/artefatos/XP):** adicionar na seção do termo correspondente
- **ADR de gamificação aceito (ex: rules-config, champion-algoritmo):** cross-ref + atualizar termo afetado
- **Mudança i18n significativa em string que envolve um dos 6 termos:** validar contra este doc; se diverge, atualizar doc OU reverter PR

Mantenedor: PM (Vitor). Co-manutenção: agente `product-leader` quando taxonomy review for executado.

---

## Decisões PM (pendente)

> Esta seção será preenchida após PM revisar Q1-Q7. Cada decisão fica registrada com data, opção escolhida, e justificativa curta. Decisões viram base para ADRs/migrations subsequentes.

| Questão | Data | Decisão | Justificativa |
|---|---|---|---|
| Q1 type×nature | 2026-05-14 | **Opção A refinada** | Eixos ortogonais; manter ambos. Só `nature='entrevista_selecao'` (35 rows) → NULL (1:1 redundante com `type='entrevista'`). Aplicado em migration `20260644000000`. |
| Q2 atas consolidação | 2026-05-14 | **Opção B reformulada (deferido)** | Manter light+rich; declarar `events.minutes_*` mínimo + `meeting_artifacts` enriquecido. Bloqueio real é gap dos 186 sem ata (75%). Trigger + helper RPC dependem de Q6 (pontuação ata exige rich). Decisão executiva confirmada; código de Q2 strict vai para Batch 4 (junto com Q6). |
| Q3 nomenclatura artefato | 2026-05-14 | **Opção A** | UX está OK (`/meetings`=Atas, `/artifacts`=Artefatos via tribe_deliverables). Aplicado COMMENT ON TABLE meeting_artifacts (migration `20260644000000`). Rename de tabela descartado (custo alto vs benefício zero). |
| Q4 nome canônico action item | 2026-05-14 | **Opção B "Ação"** | Codebase já convergiu (`meetings.actions.*`). Zero refactor. Documentado no termo 5. |
| Q5 definição Champion | 2026-05-14 | **Opção B' refinada (manual + critérios objetivos + auditoria)** | PM definiu escopo: 3 superfícies (geral / tribo / entregável) + auditoria + ranking 3 níveis. Sub-Qs 5.1-5.7 pendentes para Batch 3. |
| Q6 categorias XP novas | — | pendente Batch 4 | Cross com Q5 + Q7 + escopo Q8 |
| Q7 XP rules config-driven | — | pendente Batch 4 | Cross com Q6 + Q8 |
| Q5.1-5.7 Champion sub-questões | — | pendente Batch 3 | Aguardando exploração de gates V4 + analog de critérios checklist |
| Q8 Mini-certs PMI (Onda 2) | 2026-05-14 | **deferido para Onda 2** | PM: "segunda onda posterior a primeira análise e implementação". 6 obrigatórias intocáveis; novas entram como opcionais. |
