# Sub-issue drafts — Initiative Collaboration Hub (#212)

Ready-to-create issue bodies for the four sub-issues that spawn from #212 after PM signoff on ADR-0094.

Usage: PM signs off the architecture → PM (or agent on PM's behalf) runs `gh issue create` for each of the four below using the body verbatim. Issues then enter the normal worktree-per-issue implementation flow.

All four reference #212 as parent and link to ADR-0094 + `INITIATIVE_COLLABORATION_HUB.md`.

---

## Sub-issue G1 — External member onboarding to an initiative

**Suggested title:** `feat: external member onboarding to initiative (partner_contact + scoped capabilities + LGPD consent)`

**Suggested labels:** `governance`, `ux`, `type:task`, `priority:high`

**Body:**

````markdown
### Lane

Foundation (DB, RPC, RLS, migrations, invariants) + UX (modal in `/initiative/[id]`)

### Prioridade

P1 — destrava colaboração externa em iniciativas + multi-hub readiness

### Objetivo

Implementar o fluxo "Adicionar colaborador externo" em iniciativas: external persons (PMI-RJ chapter board, university coordinators, students, event speakers) modelados como `persons` rows com `auth_id=NULL` + `auth_engagements` de kinds externos (`partner_contact` / `external_reviewer` / `external_signer` / `speaker` / `guest`), com capability tier escopada e consent LGPD capturado via PM-attested checkbox.

Decisão arquitetural: ver ADR-0094 (Initiative Collaboration Hub Architecture) §G1.1 — `partner_contact.liaison` ganha `view_initiative_dashboard` + `write_board_assigned` (nova action escopada).

### Em escopo

- **Migration nova** em `supabase/migrations/`:
  - Seed `engagement_kind_permissions` para `partner_contact.liaison`, `guest.participant`, `speaker.speaker`, `external_signer.signer` (mínimo viável)
  - Nova action `write_board_assigned` (string, sem table change — apenas referenciada em policies)
  - Nova coluna `board_items.assignee_engagement_id uuid REFERENCES auth_engagements(engagement_id) ON DELETE SET NULL`
  - Nova coluna `engagement_kinds.retain_access_after_member_offboard boolean NOT NULL DEFAULT false` (compartilhada com G2)
  - Update `engagement_kinds` rows para `partner_contact` / `guest` / `speaker` com `default_duration_days=90`, `auto_expire_behavior='offboard'`, `notify_before_expiry_days=14`
  - RLS extension on `board_items` permitindo write quando `write_board_assigned` passa e `board_items.assignee_engagement_id = <caller's engagement>`
  - `can()` matcher para `write_board_assigned`
- **Nova RPC** `add_external_collaborator(p_initiative_id uuid, p_email text, p_name text, p_kind text, p_role text, p_partner_entity_id uuid, p_consent_attested boolean, p_engagement_end_date date, p_metadata jsonb) RETURNS jsonb`:
  - Gate: caller tem `can('manage_initiative', initiative_id)`
  - Validate: `p_consent_attested=true` mandatório; kind no whitelist; email shape válido
  - Resolve ou cria `persons` row (reaproveita se email já existe em `persons.email` OU `persons.secondary_emails`)
  - INSERT `auth_engagements` com `end_date` computado via `engagement_kinds.default_duration_days`
  - Write `admin_audit_log` com `kind='external_collaborator_consent_attested'`
  - Trigger G2 enqueue (Drive permission grant — se initiative tem `initiative_drive_links`)
- **MCP tool** `add_external_collaborator` mirrorando a RPC
- **UI**: nova seção "Colaboradores externos" no `/initiative/[id]` settings panel (tab "Configurações" — coordenar com G3)
  - Botão "Adicionar colaborador externo" → modal com fields: email, nome, kind (dropdown), role (dropdown depende de kind), partner_entity (opcional), expiry date (default 90d), consent checkbox
  - Lista de externos atuais: nome, kind/role, expires_at, Drive status (granted/pending/none), actions [Estender prazo] [Revogar]
- **Tests** em `tests/contracts/add_external_collaborator.test.mjs`:
  - happy path: cria persons + engagement + audit
  - consent mandatório (false → error)
  - kind whitelist (volunteer → rejected — não é external)
  - email dedup (já existe persons → reuse)
  - manage_initiative gate (não-manager → error)
  - `write_board_assigned` RLS (external pode write em assigned card, NÃO em outros)

### Fora de escopo

- Email-link consent flow (v2 enhancement, deferred)
- `person_emails` table generalization (#205's `member_emails` cobre members; persons usa `secondary_emails` array por enquanto)
- Drive permission grant — covered pela G2 (esta issue apenas dispara enqueue)
- Composite flow UI completo — coordenado com G3 (esta issue cobre apenas a modal + listing)
- Bulk add (CSV import etc) — deferred
- Revoke flow detalhado — engagement update com status='inactive' já existe via `manage_initiative_engagement`; coordenar UI

### Critérios de aceitação

- [ ] Migration aplicada em produção via `apply_migration` (NÃO `execute_sql`)
- [ ] Migration file commitado em `supabase/migrations/` + `supabase migration repair --status applied <ts>`
- [ ] `check_schema_invariants()` retorna 0 violations
- [ ] `NOTIFY pgrst, 'reload schema'` executado
- [ ] RPC `add_external_collaborator` exposta no PostgREST (`tools/list` MCP confirma)
- [ ] MCP tool count incrementa em 1 (293→294)
- [ ] 6 contract tests passam (`npm test` 0 fail)
- [ ] Smoke manual: criar 1 external collaborator pra Vassouras initiative (`6e9af7a8-1696-4169-a1a1-c0e160600002`) e validar:
  - `persons` row com `auth_id=NULL`, `consent_status='accepted'`
  - `auth_engagements` row com `kind='partner_contact'`, `role='liaison'`, `end_date` ≈ 90 dias
  - `admin_audit_log` row com kind=`external_collaborator_consent_attested`
  - External consegue ver initiative dashboard (login via auth_id quando posterior — ou skip se sem auth_id)
- [ ] UI modal funciona em `/initiative/<id>` (testado em dev server real)
- [ ] Permission gate UI: não-manager NÃO vê o botão "Adicionar colaborador externo"

### Definition of Done

- [ ] Critérios de aceitação acima todos marcados
- [ ] Lane gate (§5): SQL → invariants 0 + rollback documentado; MCP → `tools/list` + smoke
- [ ] `npm test` 0 fail (baseline 1449/0/46 offline, 1501/0/5 com DB env)
- [ ] Handoff block preenchido no PR description
- [ ] Backlog log atualizado em `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` se novos GAP/OPP/WATCH
- [ ] Docs canonical pins verificados sem drift
- [ ] LGPD: `pii_access_log` NÃO leakado pra external (read-perm gate funciona)
- [ ] Council Tier 1 close (platform-guardian + code-reviewer paralelo) executado

### Handoff

(vazio — preencher ao concluir)

### Contexto adicional

- **Parent**: #212 (Initiative Collaboration Hub spec)
- **ADR**: ADR-0094 §G1.1 (capability tier locked PM 2026-05-20)
- **Hard dep**: nenhum
- **Soft dep**: nenhum
- **Blocks**: G2 sub-issue (G2 enqueue espera engagement criada via G1 RPC)
- **Vassouras tactical (T-11d 02-Jun)**: se essa issue não shippar antes do evento, runbook manual em `INITIATIVE_COLLABORATION_HUB_RESEARCH.md` §7 cobre. Não bloqueia evento.
- **PM-locked decision G1.1**: `partner_contact.liaison` = view + comment em assigned cards (não view-only, não full write_board)
- **PM-locked decision G2.4**: cascade default na offboarding — coluna `engagement_kinds.retain_access_after_member_offboard` adicionada NESTA migration (compartilhada com G2 sub-issue)
````

---

## Sub-issue G2 — Engagement-level Drive permission sync

**Suggested title:** `feat: engagement-level Drive permission sync (extends #209 to initiative engagements)`

**Suggested labels:** `governance`, `audit-trail`, `type:task`, `priority:high`

**Body:**

````markdown
### Lane

Foundation (DB, RPC, RLS, migrations) + Integration (Edge Function + cron) + Audit

### Prioridade

P1 — completes LGPD Art. 16 cascade for engagement-level Drive access

### Objetivo

Estender o cascade de revogação Drive do #209 (member-level) para incluir engagements em iniciativas. Quando alguém entra em uma engagement ativa, permissão Drive é concedida automaticamente (via cron drain). Quando engagement vira inativa OU member offboarded, permissão entra em pending_revoke e flui pelo mesmo approval gate do #209.

Decisão arquitetural: ver ADR-0094 §G2 — table `engagement_drive_permissions` + triggers + extensão de `drive_offboarding_audit` com `engagement_id` nullable.

### Em escopo

- **Migration nova** em `supabase/migrations/`:
  - Tabela `engagement_drive_permissions` (id, engagement_id FK CASCADE, drive_folder_id, drive_permission_id, permission_type CHECK in (user, anyone_with_link), permission_role CHECK in (viewer, commenter, editor), granted_at, granted_by_member_id, revoked_at, revoked_audit_id, status CHECK in (pending, granted, pending_revoke, revoked, failed), organization_id, timestamps)
  - UNIQUE partial index (engagement_id, drive_folder_id, status) WHERE status IN ('pending', 'granted')
  - Extensão de `drive_offboarding_audit` (do #209) com:
    - `ALTER TABLE drive_offboarding_audit ADD COLUMN engagement_id uuid REFERENCES auth_engagements(engagement_id)`
    - `ALTER TABLE drive_offboarding_audit ADD COLUMN engagement_drive_permission_id uuid REFERENCES engagement_drive_permissions(id)`
    - `ALTER TABLE drive_offboarding_audit ADD CONSTRAINT chk_audit_scope CHECK (member_id IS NOT NULL OR engagement_id IS NOT NULL)`
  - Trigger `_trg_engagement_drive_sync_grant` AFTER INSERT ON `auth_engagements`: para cada `initiative_drive_links` ativo da initiative, INSERT em `engagement_drive_permissions` + INSERT em `google_api_jobs` (queue da G4)
  - Trigger mirror `_trg_engagement_drive_sync_revoke` AFTER UPDATE OF status ON `auth_engagements`: quando status muda pra 'inactive'/'revoked', INSERT em `drive_offboarding_audit` pending_approval + INSERT em queue
  - Extensão da cron query #209 pra incluir `engagement_kinds.retain_access_after_member_offboard = false` filter
- **Extensão da EF #209** `revoke-drive-permission` pra processar audit rows com `engagement_id NOT NULL` (não só `member_id`):
  - Detect scope (member-level vs engagement-level)
  - Call Drive API permissions.delete
  - Update `engagement_drive_permissions.status = 'revoked'`, `revoked_audit_id`
  - Log em `google_api_call_log` (da G4)
- **EF nova** `process-google-api-jobs` jobs do tipo `drive_permission_grant`:
  - Claim pending row (FOR UPDATE SKIP LOCKED)
  - Read `engagement_drive_permissions` payload
  - Call Drive API permissions.create (com role mapeado de `permission_role`)
  - Update `engagement_drive_permissions.status = 'granted'`, `drive_permission_id`, `granted_at`
  - Log em `google_api_call_log`
- **EF nova** processar `drive_folder_create` jobs (G2.3 auto-provision)
- **MCP tools**:
  - `list_engagement_drive_permissions(p_initiative_id, p_status_filter)`
  - `grant_engagement_drive_permission(p_engagement_id, p_drive_folder_id)` (manual override pra casos edge)
  - `revoke_engagement_drive_permission(p_engagement_drive_permission_id, p_reason)` (manual override, gated por can('manage_initiative'))
- **Tests** em `tests/contracts/engagement_drive_sync.test.mjs`:
  - INSERT engagement → rows criadas em `engagement_drive_permissions` + queue
  - UPDATE engagement status='inactive' → audit row pending_approval
  - Member offboarded → cron query inclui engagement_drive_permissions
  - Override `retain_access_after_member_offboard=true` → engagement NÃO entra em pending_revoke
  - Cardinality: 1 engagement, 2 initiative_drive_links → 2 rows criadas
  - Failure path: API call falha → status='failed', retry exponencial via job queue
  - Non-Google email → permission_type='anyone_with_link' (G2.2 fallback)

### Fora de escopo

- Provisionamento do service account / Workspace setup (covered pela G4 sub-issue + PM ops task)
- Calendar / Meet integration (separate issues — Calendar é #210)
- Per-card permission granularity (board scope é per-folder)
- Re-conceder acesso quando alumni re-ativa (carry from #209)
- Public-link Drive folders (different security model — deferred)
- Real-time UI de Drive permission status (UI listing OK; live status pode ser background poll)

### Critérios de aceitação

- [ ] Migration aplicada via `apply_migration`
- [ ] Local migration file commitado + `supabase migration repair --status applied <ts>`
- [ ] `check_schema_invariants()` retorna 0 violations (nova invariante: cada engagement ativa tem N rows pendientes em engagement_drive_permissions correspondente às initiative_drive_links)
- [ ] EFs deployadas (`supabase functions deploy <name> --no-verify-jwt`)
- [ ] Cron `process-google-api-jobs` rodando (1min interval)
- [ ] Smoke: criar engagement Vassouras, ver row em `engagement_drive_permissions` pending, ver job em `google_api_jobs` pending, cron drain → status='granted' + `drive_permission_id` populated
- [ ] Smoke offboard: marcar member como inactive, cron audit insere `drive_offboarding_audit` pending_approval pra cada engagement Drive row, GP aprova, EF revoga → Drive UI confirma permission removida
- [ ] 7 contract tests passam
- [ ] Idempotência: INSERT mesma engagement 2x não duplica rows
- [ ] MCP tools registrados (tool count incrementa em 3)

### Definition of Done

- [ ] Critérios de aceitação acima todos marcados
- [ ] Lane gate (§5): SQL → invariants + rollback; MCP → tools/list; EF → smoke
- [ ] `npm test` 0 fail
- [ ] Handoff block preenchido
- [ ] LGPD: `pii_access_log` registra leitura de permission data; `google_api_call_log` cobre todos API calls
- [ ] Backlog log atualizado
- [ ] Docs canonical pins verificados
- [ ] Council Tier 1 close

### Handoff

(vazio — preencher ao concluir)

### Contexto adicional

- **Parent**: #212
- **ADR**: ADR-0094 §G2 (extensão de #209 ratificada PM 2026-05-20)
- **Hard dep**: #209 (drive_offboarding_audit table + revoke EF + service account Vault)
- **Hard dep**: G4 (google_api_jobs queue + cron EF + google_api_call_log) — pode ser bundleado nesta issue ou tracked separately
- **Hard dep**: G1 (engagement criada via add_external_collaborator dispara grant — ou via manage_initiative_engagement existente)
- **Soft dep**: G3 (UI de status de Drive permission)
- **PM-locked G2.4**: cascade default sim, opt-out via `engagement_kinds.retain_access_after_member_offboard` (column criada na G1 migration, mas comportamento testado aqui)
- **PM ratified G2.1**: 1 engagement → N folder permissions
- **PM ratified G2.2**: share-link fallback pra emails não-Google
- **PM ratified G2.3**: auto-create folder na initiative INSERT (per-kind opt-out)
- **API quota**: Drive free tier 1B/dia — não é blocker
````

---

## Sub-issue G3 — Initiative Configurações UI (composite flow on top of #211)

**Suggested title:** `feat: initiative Configurações tab + external collaborator UI + Drive provision button (composite of G1+G2)`

**Suggested labels:** `ux`, `type:task`, `priority:high`

**Body:**

````markdown
### Lane

UX (frontend) + composite flow orchestration

### Prioridade

P1 — destrava self-service initiative management + multi-hub readiness

### Objetivo

Implementar a tab "⚙️ Configurações" em `/initiative/[id].astro` que orquestra os fluxos de:
- Edit metadata (depende de #211 metadata-fields work)
- "Adicionar colaborador externo" modal (consome G1 sub-issue's `add_external_collaborator` RPC)
- "Criar pasta Drive" botão (consome G2 sub-issue's `drive_folder_create` job)
- Listagem de colaboradores externos com actions (extend / revoke)

Decisão arquitetural: ver ADR-0094 §G3 + §G3.1 (permission gate via novo action `manage_initiative`).

### Em escopo

- **Migration nova** (pequena):
  - Seed `engagement_kind_permissions` para nova action `manage_initiative`:
    - `volunteer.co_gp`, `volunteer.deputy_manager`, `volunteer.manager` scope='organization'
    - `volunteer.leader`, `committee_coordinator.coordinator`, `study_group_owner.owner`, `study_group_owner.leader`, `workgroup_coordinator.coordinator` scope='initiative'
- **Frontend** em `/src/pages/initiative/[id].astro` (ou equivalente):
  - Nova tab "Configurações" (visível apenas se `can('manage_initiative', initiative_id)`)
  - Section "Metadata" (orquestra #211 fields via `update_initiative` RPC)
  - Section "Pasta Drive":
    - Se vinculada: mostra link + botão "Desvincular" (`unlink_initiative_from_drive`)
    - Se NÃO vinculada: botão "Criar pasta Drive" (calls EF direto) OU "Vincular pasta existente" (input Drive folder URL → `link_initiative_to_drive`)
  - Section "Colaboradores externos":
    - Botão "Adicionar colaborador externo" → modal G1
    - Listagem dos externos atuais com: nome, kind/role, expires_at, Drive permission status (badge), actions
  - i18n keys em pt-BR, en-US, es-LATAM (todas 3)
- **Tests** (puppeteer ou playwright para UI):
  - Manager vê a tab Configurações
  - Não-manager NÃO vê
  - Add external collaborator modal happy path
  - Provisionar pasta Drive abre EF call + UI updates
  - Lista externals com status badges corretos

### Fora de escopo

- Bulk operations (bulk-revoke externos)
- Templated initiative creation com metadata defaults (separate issue)
- Multi-hub configuration sync (separate issue)
- Drive folder browser inside UI (apenas link out + create new)
- Real-time presence indicator (deferred)

### Critérios de aceitação

- [ ] #211 (metadata fields portion) ships first OR coordinated wave with this issue
- [ ] Migration aplicada (manage_initiative seed)
- [ ] Tab Configurações renderiza em `/initiative/[id]`
- [ ] Permission gate funciona: não-manager NÃO vê tab; tentativa de force route → 403
- [ ] Add external collaborator modal funciona end-to-end (smoke manual em dev server)
- [ ] Drive provision button funciona (cria folder real via EF, captura folder_id, link aparece após reload)
- [ ] Listagem de externos popula corretamente
- [ ] i18n: 0 raw keys em produção (grep `t('...')` cross-check)
- [ ] PT-BR + EN + ES pages exist (`/en/initiative/[id]`, `/es/initiative/[id]` redirects)
- [ ] `npx astro build` passa 0 erros
- [ ] UI tested manually em dev server real (golden path + edge cases)

### Definition of Done

- [ ] Critérios de aceitação todos marcados
- [ ] `npm test` 0 fail
- [ ] Handoff block preenchido
- [ ] Backlog log atualizado
- [ ] Docs pins verificados
- [ ] Council Tier 1 close

### Handoff

(vazio — preencher ao concluir)

### Contexto adicional

- **Parent**: #212
- **ADR**: ADR-0094 §G3 + §G3.1
- **Hard dep**: G1 sub-issue (`add_external_collaborator` RPC + permissions seed pra externals)
- **Hard dep**: G2 sub-issue (Drive provision EF + grant flow)
- **Hard dep**: #211 (metadata fields UI portion — ou pode ser shipped em este issue se PM preferir bundle)
- **Soft dep**: nenhum
- **PM ratified G3.1**: `manage_initiative` action seeded for managers + initiative-scoped owners
- **PM ratified M2**: #211 stays open as metadata-fields sub-issue; este issue extends with composite flows
````

---

## Sub-issue G4 — Google API governance + org service account ratification

**Suggested title:** `infra: Google API governance — org-owned service account + queue + audit log`

**Suggested labels:** `governance`, `infrastructure`, `type:task`, `priority:high`

**Body:**

````markdown
### Lane

Infrastructure (Edge Functions + queue + secrets) + Governance (ADR ratification)

### Prioridade

P1 — desbloqueia G2 + #208 + #210; ratifica padrão pra todas integrações Google

### Objetivo

Estabelecer governança canônica pra integrações Google (Drive, Calendar, Meet, Workspace admin) com:
- Service account org-owned (não PM pessoal) — decisão PM-locked 2026-05-20 (G4.1)
- Queue table `google_api_jobs` + cron EF `process-google-api-jobs` (envelope assíncrono pra triggers)
- Direct EF endpoints (envelope síncrono pra ações user-driven)
- Audit log `google_api_call_log` (LGPD Art. 37)
- Rate limiting + exponential backoff + dead-letter
- Threat model extension (update ADR-0018)

Decisão arquitetural: ADR-0094 §G4.

### Em escopo

- **Operational task (PM blocker)**:
  - PM provisiona Google Workspace tenant (ou usa existente) com domínio org-owned
  - PM cria service account dedicada (não conta pessoal)
  - PM gera service account key JSON
  - PM stora key em Supabase Vault como `google_service_account_key` (ou `google_service_account_key_<organization_id>` pra multi-hub futuro)
  - PM transfere ownership / grant editor das pastas Drive existentes (Pasta-mãe Núcleo IA `1PFLzCa8dwjFNhc_y3TPOnkN9O7jfbqnA` etc.) pro service account
- **Migration nova**:
  - Tabela `google_api_jobs` (id, job_type CHECK in (drive_permission_grant, drive_permission_revoke, drive_folder_create, drive_folder_archive, calendar_attendee_update, meet_transcript_fetch), payload jsonb, status CHECK in (pending, in_progress, success, failed, dead_letter), attempts, max_attempts, next_attempt_at, last_error, organization_id, timestamps)
  - Index `(next_attempt_at) WHERE status='pending'`
  - Tabela `google_api_call_log` (id, api_surface CHECK in (drive, calendar, meet, admin), endpoint, caller_kind CHECK in (job, user_direct), caller_member_id, caller_job_id, payload_summary jsonb, response_status, response_body_summary jsonb, duration_ms, organization_id, created_at)
  - Constraints: `google_api_call_log` é append-only (revoke UPDATE/DELETE)
- **EF nova** `supabase/functions/process-google-api-jobs/` (cron every 1 min):
  - Claim pending row via `FOR UPDATE SKIP LOCKED`
  - Read service account key from Vault
  - Initialize Google API client (Drive/Calendar/Meet per job_type)
  - Call API, capture response
  - Update job status (success / failed) + retry logic (exponential backoff via `next_attempt_at`)
  - INSERT `google_api_call_log` row
  - Dead-letter após `max_attempts` (default 5) + notification GP
- **EF library** `_shared/google-api-client.ts`:
  - Auth helper (Vault read + JWT mint)
  - Retry wrapper
  - Audit logger
  - PII redactor (remove emails dos payload_summary antes de log)
- **EF direct** endpoints exemplo (skeleton, real implementations seguem em G2/G3):
  - `drive-folder-create` (POST endpoint pra "Criar pasta Drive" button)
  - `drive-permission-grant-immediate` (manual override, gated por admin)
- **MCP tools**:
  - `get_google_api_jobs_health()` (count by status, oldest pending, dead_letter count)
  - `retry_failed_google_api_job(p_job_id)` (manual retry)
  - `bulk_retry_dead_letter_jobs(p_job_type, p_age_hours)` (housekeeping)
- **ADR update**:
  - ADR-0094 Status: Proposed → Accepted (after PM signoff em todas 4 sub-issues)
  - ADR-0018 (MCP threat model) extension §7.5 do arch doc — Google API attack surface
- **Tests** em `tests/contracts/google_api_governance.test.mjs`:
  - Job queue: INSERT pending row → cron claim → status='in_progress' → success
  - Retry: 1st fail → next_attempt_at em 1s, 2nd → 2s, etc
  - Dead-letter: 5 fails → status='dead_letter' + notification
  - Audit log: cada job claim grava 1 row em `google_api_call_log`
  - PII redactor: payload com email → log com `<redacted>`
  - Vault access: service account key NÃO exposta em env vars

### Fora de escopo

- Antigravity 2.0 / Gemini 3.5 Flash integration (separate issue #206 — escopo AI workload, não estrutural)
- Calendar audit completo (#210 escopo)
- Meet transcripts pipeline completo (#208 escopo)
- Per-organization key rotation automation (manual annual rotation v1)
- Workspace admin operations (out of scope; service account scopes minimal)

### Critérios de aceitação

- [ ] **PM operational task COMPLETED** (service account provisioned + Vault key stored)
- [ ] Migration aplicada
- [ ] EF deployada (`supabase functions deploy process-google-api-jobs --no-verify-jwt`)
- [ ] Cron `process-google-api-jobs` rodando (pg_cron job criada)
- [ ] EF library `_shared/google-api-client.ts` exists + importável por outras EFs
- [ ] Smoke: INSERT manual de 1 job_type='drive_folder_create' → cron drain → folder real criada em Drive → linked
- [ ] Smoke: simulate failure (revoke service account scope temporariamente) → job entra em retry → eventual dead-letter
- [ ] 6 contract tests passam
- [ ] MCP tools `get_google_api_jobs_health` + `retry_failed_google_api_job` + `bulk_retry_dead_letter_jobs` exposed
- [ ] `google_api_call_log` é append-only (test: tentar UPDATE → falha; tentar DELETE → falha)
- [ ] PII redactor unit test
- [ ] Vault key access funciona em EF runtime (sem leak em logs)
- [ ] ADR-0094 atualizada pra Accepted (after PM signoff)
- [ ] ADR-0018 §7.5 extension committed

### Definition of Done

- [ ] Critérios de aceitação todos marcados
- [ ] Lane gate (§5): infra → secrets verified in Vault; SQL → invariants; MCP → tools/list
- [ ] `npm test` 0 fail
- [ ] Handoff block preenchido
- [ ] LGPD: `google_api_call_log` registra cada call, PII redactor testado
- [ ] Backlog log atualizado
- [ ] Docs canonical pins verificados (CLAUDE.md, `.claude/rules/mcp.md`, `.claude/rules/deploy.md`)
- [ ] Council Tier 1 close

### Handoff

(vazio — preencher ao concluir)

### Contexto adicional

- **Parent**: #212
- **ADR**: ADR-0094 §G4 (PM-locked decision G4.1: org-owned dedicated identity)
- **Hard dep**: PM operational task (provisioning Workspace + service account) — blocks Phase B-D start
- **Hard dep**: #209 (compartilha service account; #209 introduz Vault entry; this issue can co-ship with #209)
- **Blocks**: G2 sub-issue (G2 precisa do queue + EF p/ permission grants)
- **Soft dep**: ADR-0018 update pra threat model
- **Cross-references**: #204 (parent umbrella), #208 (Meet transcripts — usa mesmo service account), #210 (Calendar — usa mesmo)
- **PM ratified G4.2**: hybrid envelope (queue + direct EF)
- **PM ratified M1**: design multi-hub from day one (every table carries `organization_id`); per-org Vault key naming convention `google_service_account_key_<organization_id>`
- **Vault key rotation**: annual; manual v1
````

---

## Spawn order recommendation

When PM signs off and is ready to spawn:

1. **G4 first** (or coordinated with #209) — its infrastructure blocks G2.
2. **G1 second** (independent, can spawn in parallel with G4).
3. **G2 third** (depends on G4 + G1).
4. **G3 fourth** (depends on G1 + G2 + #211).

Or coordinated as one larger wave if PM prefers single sub-issue scope inflation.

## After spawn

- All four sub-issues reference #212 as parent.
- #212 stays open as the spec tracking issue until all four ship.
- Sub-issues use the standard worktree-per-issue convention (`agent/issue-NNN`).
- ADR-0094 moves from Proposed → Accepted at the point PM gives signoff on the entire architecture, before sub-issues are claimed by an agent.
