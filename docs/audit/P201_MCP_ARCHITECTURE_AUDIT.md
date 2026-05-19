# p201 MCP + Data Architecture Audit

**Data:** 2026-05-19  
**Status:** Em andamento — Onda A iniciada  
**Escopo:** MCP contracts, schema drift, semantic layer, docs/governança e QA local.

---

## 1. Runtime Baseline

Evidência coletada na sessão p201:

- MCP runtime `tools/list`: **293 tools**.
- `nucleo-mcp /health`: **293 tools**, version `2.76.1`, SDK `1.29.0`.
- `check_schema_invariants()`: **16/16 invariantes com 0 violações**.
- `mcp_usage_log`: sem falhas recentes de tool execution; falhas históricas confirmam classe de risco pós-migration (`tribe_id`, `member_status_transitions`, `cpmai_sessions`).
- Cloudflare Worker Observability: requests que passam pela borda chegam ao Worker `platform`; bloqueios `Error 1010` não chegam ao Worker.

---

## 2. Onda A — Inventário MCP Preliminar

Parser estático inicial sobre `supabase/functions/nucleo-mcp/index.ts`:

| Métrica | Contagem |
|---|---:|
| Tools detectadas por parser simples | 292 |
| Tools runtime/health | 293 |
| Tools com `.rpc(...)` | 277 |
| Tools com `.from(...)` direto | 25 |
| Tools com `canV4(...)` detectado | 83 |
| Tools com fetch externo / service role | 4 |

**Nota:** diferença `292` vs `293` indica limitação do parser textual inicial. A fonte de verdade para contagem segue sendo `tools/list` runtime.

### 2.1 Direct Table Access Hotspots

Tabelas mais acessadas diretamente no MCP:

| Tabela | Ocorrências em handlers |
|---|---:|
| `members` | 5 |
| `board_items` | 4 |
| `project_boards` | 3 |
| `events` | 3 |
| `initiatives` | 2 |
| `engagements` | 2 |
| `initiative_invitations` | 2 |
| `public_members` | 1 |
| `attendance` | 1 |
| `announcements` | 1 |
| `governance_documents` | 1 |
| `manual_sections` | 1 |
| `persons` | 1 |
| `selection_interviews` | 1 |
| `cycles` | 1 |
| `board_item_checklists` | 1 |
| `pending_manual_version_approvals` | 1 |
| `document_versions` | 1 |
| `ai_processing_log` | 1 |
| `selection_applications` | 1 |

### 2.2 Tools With Direct Table Reads/Writes

| Tool | Direct tables | RPCs | Gate detectado |
|---|---|---|---|
| `get_my_profile` | `members` | — | RLS/member self |
| `get_my_board_status` | `board_items`, `project_boards` | — | RLS/implicit |
| `get_my_tribe_members` | `public_members` | — | Public-safe view/RLS |
| `get_upcoming_events` | `events` | — | Public/member filtered by RLS |
| `get_meeting_notes` | `attendance`, `events`, `members` | — | RLS/implicit |
| `get_hub_announcements` | `announcements` | — | Public active filter |
| `create_board_card` | `project_boards` | `create_board_item` | `write_board` |
| `send_notification_to_tribe` | `members` | `create_notification` | `write` |
| `list_boards` | `project_boards` | — | RLS/implicit |
| `get_governance_docs` | `governance_documents` | — | RLS/implicit |
| `get_manual_section` | `manual_sections` | — | Current-section filter |
| `drop_event_instance` | `events` | `drop_event_instance` | `manage_event` |
| `manage_initiative_engagement` | `initiatives`, `persons` | `manage_initiative_engagement` | `manage_member` |
| `offboard_member` | `board_items`, `engagements`, `members` | `admin_offboard_member` | `manage_member` |
| `submit_interview_scores` | `selection_interviews` | `get_evaluation_form`, `submit_interview_scores` | RPC gate |
| `list_my_initiative_invitations` | `initiative_invitations` | — | RLS/implicit |
| `list_invitations_sent_by_me` | `initiative_invitations` | — | RLS/implicit |
| `withdraw_from_initiative` | `engagements`, `initiatives`, `members` | `withdraw_from_initiative` | RPC gate |
| `list_cycles` | `cycles` | — | Public/ref data |
| `list_card_checklist` | `board_item_checklists` | — | RLS/implicit |
| `delete_card` | `board_items` | `delete_board_item` | `write_board` |
| `archive_card` | `board_items` | `admin_archive_board_item` | `write_board` |
| `confirm_manual_version` | `pending_manual_version_approvals` | `confirm_manual_version` | `manage_platform` |
| `edit_document_version_draft` | `document_versions` | `upsert_document_version` | `manage_member` |
| `generate_interview_briefing` | `ai_processing_log`, `selection_applications` | — | `view_pii` + service role after gate |

### 2.3 External Fetch / Service Role Tools

- `upload_text_to_drive_folder`
- `create_drive_subfolder`
- `analyze_application`
- `generate_interview_briefing`

Esses handlers exigem auditoria separada de secrets, LGPD, logging e rollback, pois atravessam fronteiras fora do PostgREST/RLS normal.

---

## 3. Achados Confirmados Nesta Sessão

### 3.1 Docs Drift MCP

Corrigido:

- `README.md`: 284 -> 293 tools.
- `README.pt-BR.md` e `README.es.md`: 266/64 -> 293 tools; Edge Functions 32 -> 37; RPCs 189+ -> 795; pg_cron 4 -> 34; governance 135+ -> 141+.
- `AGENTS.md`: MCP 64 -> 293; Edge Functions ~19/20 -> ~37; pg_cron 4 -> ~34; RPC/SECDEF 189+ -> ~795.
- `docs/MCP_SETUP_GUIDE.md`: 68/29 -> 293 + lista representativa.
- `supabase/functions/nucleo-mcp/index.ts`: comentário stale `Register 94 tools` -> 293.
- `.claude/agents/platform-guardian.md`: 15 -> 16 invariantes, 289 -> 293 tools, ADRs até 0087.
- `docs/GOVERNANCE_CHANGELOG.md`: backfill mínimo GC-142 a GC-146 para autoridade V4, curadoria, presença, MCP runtime e Cloudflare/BIC.
- `docs/RELEASE_LOG.md`: backfill resumido p40-p201 em 10 milestones estruturais.

### 3.2 Attendance RPC Hotfix

Corrigido em produção:

- Bug: `get_attendance_grid` retornava HTTP 400.
- Root cause: `column reference "status" is ambiguous`.
- Migration: `20260722010000_p201_fix_attendance_grid_status_ambiguity.sql`.
- Validação: função live contém `cs2.status`/`cs3.status`; chamada autenticada simulada retorna JSON com `summary`, `events`, `tribes`; invariantes 16/16 zeradas.
- Registro: `docs/RELEASE_LOG.md` + `docs/audit/P162_GAP_OPPORTUNITY_LOG.md`.

Também corrigido:

- Bug: `get_tribe_attendance_grid` mostrava `na` para reunião da Tribo 7 de 2026-05-19 sem linhas de presença.
- Root cause: branch `WHEN COALESCE(erc.row_count, 0) = 0 THEN 'na'` marcava evento elegível vazio como não aplicável.
- Migration: `20260722020000_p201_fix_tribe_attendance_empty_event_absent.sql`.
- Validação: simulando Marcos Klemz, o evento `4b31e97d-2b63-4548-91af-65adbec6fb46` retorna `today_status='absent'`; invariantes 16/16 zeradas.

### 3.3 Cloudflare MCP Bootstrap

Confirmado:

- `Error 1010 browser_signature_banned` ocorre antes do Worker para algumas assinaturas.
- Assinaturas browser-like e `Claude-User/1.0` passam.
- Bloqueios 1010 não aparecem em Worker Observability nem `mcp_usage_log`.

---

## 4. Gaps Abertos

1. **MCP parser canônico:** criar script robusto para gerar matriz 293/293 a partir do runtime `tools/list` + código — GitHub #162.
2. **Tool contract matrix:** cada tool precisa mapear `tool -> dependency -> gate -> output shape -> drift risk` — GitHub #162.
3. **Semantic layer:** direct table reads devem ser classificados como aceitáveis, temporários ou candidatos a RPC/view semantic — GitHub #166.
4. **Cloudflare Security Events:** coletar Ray ID real do Claude connector e aplicar skip/allow correto — GitHub #163.
5. **Local QA:** `supabase start` falha por migration order; isso bloqueia debug local de Edge Functions — GitHub #164.
6. **Release backfill:** `docs/RELEASE_LOG.md` precisa de backfill p40-p201 — GitHub #165.
7. **Parallel agent governance:** padronizar worktrees, lanes, handoff e gates — GitHub #159.
8. **Herlon authority state:** decidir acordo/certificado vs requirement vs UX pendente — GitHub #160.
9. **Sensitive UI gates:** auditar `hasPermission(...)` e migrar superfícies sensíveis para `canFor(...)` — GitHub #161.

---

## 5. Tiers, RLS e Personas

### 5.1 Evidência de Personas

Consulta live em `members`, `engagements`, `can_by_member` e `get_caller_capabilities()`:

| Pessoa | Estado atual | Evidência de permissão |
|---|---|---|
| Roberto Macêdo | `operational_role='researcher'`, designations `chapter_liaison`, `ambassador`, `curator`; active Curadoria committee coordinator | `curate_content=true`, `participate_in_governance_review=true`, `view_internal_analytics=true`, `view_chapter_dashboards=true` |
| Sarah Faria | `operational_role='researcher'`, designations `ambassador`, `founder`, `curator`; active Curadoria committee coordinator | `curate_content=true`, `participate_in_governance_review=true`; initiative `Comitê de Curadoria` grants `view_pii`, `write`, `write_board` |
| Marcos Klemz | `operational_role='tribe_leader'`, Tribe 7 leader | `manage_event=true`, `write_board=true`, `award_champion=true` scoped to Tribe 7 / initiative `Governança & Trustworthy AI` |
| Herlon Alves | `operational_role='observer'`, designations `ambassador`; active `study_group_owner` role `leader` in CPMAI | `org_actions=[]`, `initiative_actions={}` because `requires_agreement=true`, `agreement_certificate_id=NULL`, `is_authoritative=false` |

### 5.2 Bugs Confirmados e Corrigidos

1. **Tribo 7 attendance** — `get_tribe_attendance_grid` returned `na` for same-day eligible event with no attendance rows. Fixed by `20260722020000_p201_fix_tribe_attendance_empty_event_absent.sql`.
2. **Curatorship UI gate** — `CuratorshipBoardIsland` and `AdminNav` used legacy `hasPermission('admin.curation')` only. Fixed to also accept `canFor('curate_content')` and `canFor('participate_in_governance_review')`.

### 5.3 Gaps de Arquitetura de Permissão

- `navigation.config.ts` exposes `/admin/curatorship` at `minTier='observer'`, but the React island had stricter legacy permission gating. This class of mismatch can create "link visible, content denied" bugs.
- `AdminNav.astro` previously mapped `curatorship` to `admin.curation` only; p201 hotfix now adds V4 capability fallback for `curate_content` and `participate_in_governance_review`.
- `getAccessTier()` and `hasPermission()` remain cache/designation driven. V4 source of truth is `can()` / `can_by_member()` / capability cache. High-risk pages should prefer `canFor()`.
- Herlon is a live example of pending-authority state: the `study_group_owner/leader` engagement has permissions in `engagement_kind_permissions`, but `auth_engagements` does not expose them because the engagement requires agreement and has no `agreement_certificate_id`. This may be correct compliance behavior, but the UI needs to explain "leadership pending agreement" instead of silently showing only `observer`.

### 5.4 Recommended Permission Audit Matrix

| Surface | Source today | Recommended source |
|---|---|---|
| Main nav visibility | `navigation.config.ts` tier/designations | Keep for discoverability, but annotate V4 capability routes |
| Admin subnav | `hasPermission()` local map | `canFor()` / capability cache for V4 actions |
| React island gates | mixed local maps | `canFor()` first, legacy map fallback |
| RLS/RPC | `can_by_member()` | Keep canonical |
| MCP | `canV4()` / RPC gates | Keep, add defense-in-depth for high-risk writes |

---

## 6. Próximas Ondas

### Onda A — MCP Contract Inventory

Gerar matriz completa 293 tools com:

- Nome da tool.
- Categoria/domínio.
- RPCs chamadas.
- Tabelas acessadas diretamente.
- Gate JS (`canV4`) e/ou gate RPC.
- Output envelope esperado.
- Risco de drift.
- Smoke test recomendado.

### Onda B — Semantic Layer

Propor contratos estáveis por domínio:

- `member`
- `initiative`
- `board`
- `selection`
- `governance`
- `curation`
- `gamification`
- `attendance`

### Onda C — Docs/Governance

Backfill release log em milestones:

- Domain Model V4.
- MCP growth 68 -> 293.
- LGPD cycle.
- Selection AI/video.
- Curation pipeline.
- Attendance/cancelled-event hotfixes.

### Onda D — Local QA

Resolver:

- `supabase start` migration ordering.
- `deno` unavailable.
- `supabase db push` blocked by remote-only migration drift.

### Onda E — Cloudflare Access

Criar regra Cloudflare validada com Security Events:

- `/mcp`
- `/.well-known/oauth-*`
- `/oauth/*`

Com skip específico para Browser Integrity/Bot checks, mantendo rate limit e OAuth gates.
