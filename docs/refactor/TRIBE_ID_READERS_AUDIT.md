# tribe_id Readers Audit (ADR-0015 Fase 0)

**Status:** Fase 0 complete — ready for Fase 1 planning
**Data:** 2026-04-17
**Autor:** Vitor (PM) + Claude
**Escopo:** Inventário de readers de `tribe_id` por surface (src/, RPCs, EFs, MCP tools) para preparar execução das Fases 1-4 do ADR-0015.

## Sweep summary

| Surface | Count | Notas |
|---|---|---|
| `src/` files | 75 | Frontend + Astro pages + components + hooks |
| `supabase/functions/` | 6 EFs | nucleo-mcp, send-campaign, send-global-onboarding, send-allocation-notify, send-tribe-broadcast, import-calendar-legacy |
| `public` RPCs (ILIKE tribe_id) | ~180 | Qualquer menção (scope amplo) |
| RPCs tocando tabelas C3 diretamente | ~60 | Subset acionável |

**Observação**: ~180 RPCs mencionam `tribe_id` é um number grande porque muitos leem `members.tribe_id` (C4 deferred) para derivar afiliação histórica V3. Após C3 cutover, o número permanece alto — o volume real dos readers C4 só cai quando members.tribe_id sair (Fase 5).

## Per-table reader inventory (C3 droppable)

Os 11 readers abaixo são *específicos por tabela* — escrevendo/lendo `<tabela>.tribe_id` direto, não apenas mencionando tribe_id no contexto de outras tabelas.

### webinars (6 rows) — primeiro candidato Fase 1

| Reader | Tipo | Uso | Impacto |
|---|---|---|---|
| `upsert_webinar` | RPC | Writer — p_tribe_id parameter + INSERT/UPDATE tribe_id | Signature muda |
| `list_webinars_v2` | RPC | Reader — returns w.tribe_id | Output shape muda |
| `webinars_pending_comms` | RPC | Reader — returns w.tribe_id | Output shape muda |
| `link_webinar_event` | RPC | Reader — v_webinar.tribe_id → escreve em events.tribe_id | Dual-coupling |
| `/admin/webinars.astro` | Frontend | Form field + reads w.tribe_id + passes p_tribe_id | UI coupling real |
| `list_tribe_webinars` (MCP tool 17) | MCP | Filter/display por tribo | User-visible output |

**Frontend coupling**: `src/pages/admin/webinars.astro:561,633,651` — form tem "tribe" dropdown, salva via `p_tribe_id`. **Cutover requires UI changes + dev server testing**.

**Recomendação**: Fase 1 webinars = 1 sessão dedicada com browser testing, não quick-win de migration-only.

### events (270 rows, 150 with both, 2 init-only) — último candidato Fase 1

Exposição máxima:
- Readers em todas as pages /attendance, /meetings, /workspace
- `get_events_with_attendance`, `get_attendance_grid`, `get_tribe_attendance_grid`, `get_event_detail`, `get_meeting_detail`, `get_near_events`, `get_recent_events`, `drop_event_instance`, `update_event*`, `create_event`, `audit_events_changes` + muitos mais
- Frontend: `src/pages/attendance.astro`, `src/components/attendance/*`, `src/components/meetings/MeetingsPage.tsx`, etc.
- `auto_tag_event_by_type` trigger
- `drop_event_instance` reads `events.tribe_id` (agora via filtro WHERE)

**Recomendação**: events por ÚLTIMO no ciclo Fase 1. Pattern consolidado nas tabelas menores primeiro.

### publication_submissions (8 rows)

Readers:
- `create_publication_submission` — writer
- `get_publication_submissions` — reader
- `get_publication_submission_detail` — reader
- `admin_manage_publication` — writer
- `get_publication_pipeline_summary` — reader/agg
- `auto_publish_approved_article` — trigger
- `enqueue_artifact_publication_card` — trigger
- `/publications/submissions.astro` + `src/pages/publications/submissions/[id].astro` — frontend

### meeting_artifacts (12 rows)

Readers:
- `list_meeting_artifacts`
- `list_initiative_meeting_artifacts`
- `get_meeting_detail`, `get_meeting_notes_compliance`
- Trigger: `enqueue_artifact_publication_card`

### project_boards (14 rows, 3 init-only already)

Readers:
- `list_project_boards`, `list_initiative_boards`, `list_active_boards`
- `admin_archive_project_board`, `admin_restore_project_board`, `admin_update_board_columns`
- `admin_link_board_to_legacy_tribe`, `admin_link_communication_boards`, `admin_detect_board_taxonomy_drift`
- `admin_ensure_communication_tribe` (creates boards for new comms tribe)
- `enforce_project_board_taxonomy` trigger
- Frontend: `src/components/boards/TribeKanbanIsland.tsx`, `src/pages/tribe/[id].astro`, `src/components/islands/BoardEngine.tsx`

**Nota**: 3 boards já são init-only — pattern de initiative-native board está provado funcional.

### broadcast_log (25 rows)

Readers:
- `broadcast_count_today`, `broadcast_count_today_v4`, `broadcast_history`
- EFs: `send-campaign`, `send-tribe-broadcast`
- Frontend: nenhum direto (lê via RPC)

### announcements

Readers:
- `get_hub_announcements` — public reader
- Frontend: `src/components/sections/HomepageHero.astro` (?)

### hub_resources

Readers:
- `search_hub_resources`
- `/library.astro`, `src/components/sections/WeeklyScheduleSection.astro`

### ia_pilots + pilots

Readers:
- `get_pilots_summary`, `create_pilot`, `update_pilot`
- `/admin/pilots.astro`, `src/components/admin/ResearchPipelineWidget.tsx`

### public_publications

Readers:
- `get_public_publications` — public reader
- `/publications.astro`

## Artifacts table (special case)

**Volume**: 29 rows
**Dual-write**: NO (sem trigger)
**Has initiative_id**: NO

Schema (vs publication_submissions):
- artifacts: id, member_id, tribe_id, title, type, description, url, status, cycle, submitted_at, reviewed_by, reviewed_at, review_notes, published_at, source, trello_card_id, tags, curation_status
- publication_submissions: (similar columns) + initiative_id

Data sample:
- 2 rows com tribe_id=6 (Tribo 6)
- 3 rows com tribe_id=NULL (artigos gerais — "ai at work 2024", "2026 02 17 nucleo ia gp ciclo3 kickoff lideranca")

**Investigação 17/Abr (post-sweep)**:
- **0 RPCs** referenciam a tabela (não há interface via RPC).
- **0 triggers** referenciam a tabela.
- **MAS 4 frontend pages fazem direct Supabase queries**:
  - `src/pages/artifacts.astro` — CRUD principal (SELECT/INSERT/UPDATE)
  - `src/pages/tribe/[id].astro` — lista published artifacts por tribo
  - `src/pages/profile.astro` — lista artifacts do user
  - `src/pages/gamification.astro` — count por member
- Nav: `/artifacts` linkada em `workspace`, `onboarding`, `navigation.config.ts`.

**Conclusão**: artifacts **NÃO é órfão** — é parte ativa da plataforma mas escapou do pattern V4 (sem initiative_id, sem dual-write, sem RPC interface).

**Opções de tratamento** (decisão pendente PM):

1. **Acknowledge como C2 bridge-locked**: manter artifacts com tribe_id, nunca adicionar initiative_id. Racional: pequeno, estável, user flow funcional.
2. **Alinhar com C3 pattern**: ADD COLUMN initiative_id + dual-write trigger + backfill 29 rows. Custo: 1 migration, futuro pattern.
3. **Consolidar em publication_submissions**: migrar 29 rows + drop tabela. Mais agressivo, requer shape reconciliation. Reduz surface mas frontend precisa cutover.

**Recomendação**: **Opção 2** (alinhar com C3) é a mais conservadora — preserva frontend + introduz initiative_id para readers futuros pós-Fase 1. Consolidação opt3 pode ser avaliada separadamente se for identificado uso redundante.

## Ordem recomendada para Fase 1 (menor → maior risco)

1. **webinars** (6 rows) — isolada, reader surface pequena, mas coupling UI no admin. **Requer sessão dev com browser**.
2. **publication_submissions** (8 rows) — reader surface média, page dedicada.
3. **meeting_artifacts** (12 rows) — leitores RPC-only, trigger envolvido.
4. **project_boards** (14 rows) — 3 init-only já existentes = pattern validado.
5. **broadcast_log** (25 rows) — EFs + RPCs, nenhum frontend direto.
6. **pilots** + **ia_pilots** — small volume, admin page dedicada.
7. **hub_resources**, **announcements**, **public_publications** — volume baixo.
8. **events** (270 rows) — LAST. Máxima exposição UI; cutover final vai validar pattern completo.

Entre cada: rodar `check_schema_invariants()` + smoke dev + commit atômico.

## MCP tools impactados

De 76 tools, os seguintes referenciam tribe_id via RPC:
- `list_tribe_webinars` → `list_webinars_v2`
- `get_meeting_notes` → `list_meetings_with_notes`
- `get_attendance_ranking` → `get_attendance_grid`
- `search_board_cards` → `search_board_items`
- `get_tribe_dashboard`, `get_tribe_stats_ranked`, `get_tribes_comparison`, `get_my_tribe_members` etc. (tribe_*)
- Outros que mencionam tribe_id ao renderizar member listings

**Impact**: tools de output shape vão ter `tribe_id` removido do JSON retornado após Fase 3. Claude.ai connector pode mostrar "tribe_id: null" por um ciclo se campo for deprecated antes de drop completo. Comunicar em changelog do connector.

## Próximas ações

- [ ] **Fase 1 webinars** (sessão dedicada): audit UI, cutover admin form, migrar RPCs, drop column. Smoke browser.
- [ ] **Investigar artifacts**: readers? migrar ou archive?
- [ ] **Schema-cache-columns test extension**: adicionar asserção anti-regress "nova tabela C3-candidate não pode ter ADD COLUMN tribe_id" (ADR-0015).
- [ ] **members.tribe_id (C4)**: audit separado de frontend V3 readers — prerequisite para Fase 5.

## Referências

- ADR-0015 — Tribes Bridge Consolidation
- ADR-0005 — Initiative as Domain Primitive
- ADR-0012 — Schema Consolidation Principles (Princípio 1: single source of truth)
- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` — histórico V4

---
*Last updated: 2026-04-17 (Fase 0 complete)*
