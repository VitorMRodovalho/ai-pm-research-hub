# RLS Phase 2 — Auditoria das 24 policies `rls_is_member()`

**Data:** 2026-06-24 · **Origem:** follow-up do achado da Phase 1 (#869, vazamento do diretório de membros)
**Método:** prova comportamental ao vivo (impersonação RLS via `SET LOCAL ROLE` + `request.jwt.claims`, transação revertida) + grep de leituras diretas PostgREST no código + verificação adversarial multi-agente (workflow `rls-phase2-audit`, 27 agents). **Read-only — nada aplicado.**
**Projeto:** `ldrfrvwhxsmgaabwmaik` · todos os números abaixo vêm de tool results deste turno.

---

## 1. Tese e achado central

A Phase 1 endureceu **uma** policy (`members_read_by_members`) trocando `rls_is_member()` → `rls_is_authoritative_member()`. Restavam **24** policies SELECT ainda em `rls_is_member()`.

- `rls_is_member()` = `EXISTS(members WHERE auth_id=auth.uid())` → **só existência de linha**. É TRUE para **qualquer** autenticado com linha em `members`, incluindo os **23 guests pré-onboarding ativos com login** (`operational_role='guest'`, termo de voluntário não assinado, engajamento não-autoritativo). (O cohort total de guests é ~30–31; 23 têm `auth_id`+`is_active`, i.e. conseguem autenticar e disparar leituras.)
- `rls_is_authoritative_member()` (helper da Phase 1) = membro ativo com `operational_role <> 'guest'` → 40 callers.

**Prova comportamental (ao vivo):** um guest vê **contagem de linhas IDÊNTICA** à de um membro autoritativo nas **24 tabelas**. O `*_v4_org_scope` (RESTRICTIVE) não diferencia (org do guest = org principal); o gate confidencial (ADR-0105) já está fora de ambas as contagens. Anon vê só **75 eventos públicos** (intencional); resto 0.

Apertar a policy só remove **guests** — membros reais (todos autoritativos) ficam intactos. O único vetor que o aperto afeta é **leitura direta via PostgREST (`.from('<tabela>')`) sob o JWT do usuário**; RPCs SECURITY DEFINER e código server (service_role) **bypassam RLS** e são imunes.

---

## 2. Exposição atual por tabela (guest = membro pleno)

| Tabela | Linhas que o guest vê | Sensibilidade | Conteúdo sensível |
|---|---:|---|---|
| **partner_entities** | 32 | **HIGH** | `contact_email`, `contact_name`, `notes` — **PII de contato de parceiro** |
| gamification_points | 1752 | MEDIUM | pontos/`reason` de **todos** os membros |
| attendance | 1506 | MEDIUM | presença + `excuse_reason` + `notes` de todos os membros |
| publication_submissions | 37 | MEDIUM/HIGH | `abstract`, `estimated_cost_brl`, `actual_cost_brl`, `reviewer_feedback` |
| course_progress | 144 | MEDIUM | progresso de trilha de todos os membros |
| change_requests | 53 | MEDIUM | `justification`, `review_notes` de governança |
| board_items | 615 | MEDIUM | `leader_review_notes`, `peer_review_summary`, descrições |
| event_invited_members / webinar_lifecycle_events | 1 / 11 | MEDIUM | convites / transições de status |
| board_item_assignments / checklists | 703 / 419 | MEDIUM | quem-faz-o-quê / texto de checklist |
| board_item_files / board_drive_links / drive_file_discoveries / initiative_drive_links | 14/0/0/28 | LOW-MED | URLs/nomes de arquivos Drive |
| event_audience_rules / event_tag_assignments / board_item_tag_assignments | 413/1074/374 | LOW | metadados/tags |
| project_boards / publication_series | 24 / 6 | LOW-MED | metadados de board / config editorial |
| publication_submission_authors / _events | 0 / 0 | LOW-MED | autoria / canais (0 linhas) |
| events / webinars | 471 / 8 | LOW | semi-públicos por design |

---

## 3. Resultado por tabela (recomendação + evidência)

### Grupo A — TIGHTEN simples (seguro + efetivo; nenhuma leitura direta guest-acessível) — 16 tabelas
Troca `rls_is_member()` → `rls_is_authoritative_member()`. Verificação adversarial = `CONFIRM_TIGHTEN` em todas; comportamento-neutro para membros reais.

`board_items` · `board_item_assignments` · `board_item_checklists` · `board_item_tag_assignments` · `project_boards` · `event_audience_rules` · `event_invited_members` · `event_tag_assignments` · `webinars` · `webinar_lifecycle_events` · `publication_submission_authors` · `publication_submission_events` · **`partner_entities` (HIGH — prioridade)** · `change_requests` · `drive_file_discoveries` · `initiative_drive_links`

Notas: o único `.from('board_items')` guest-acessível (workspace.astro:426) está atrás de `if(member.tribe_id)` e **0/30 guests têm tribo** → não dispara. board_item_checklists só lido em `CardDetail.tsx` (montado em páginas minTier member/admin). Verificadores rodaram teste JWT de 2 lados (ex.: `board_item_tag_assignments` guest 374→0; membro autoritativo mantém).

### Grupo B — TIGHTEN + REVOKE GRANT anon latente — 2 tabelas
`board_item_files` · `board_drive_links` — além do tighten, têm **GRANT SELECT anon** sem policy anon (0 linhas hoje, mas dívida de superfície). `REVOKE SELECT … FROM anon`.

### Grupo C — Own-row carve-out (NÃO troca cega) — 3 tabelas
`gamification_points` · `attendance` · `publication_submissions`. Têm **leitura self-scoped guest-acessível** em `/profile` e `/gamification` (`.eq('member_id', MEMBER.id)` / `primary_author_id`) e **não têm** own-row policy separada. Org-scope é RESTRICTIVE (confirmado: `is_permissive=false`) → não faz backfill → o tighten É efetivo, mas uma troca cega quebraria o self-read no dia em que um guest tiver linha própria.
**Fix correto:** `USING (rls_is_authoritative_member() OR <coluna_do_dono> IN (SELECT id FROM members WHERE auth_id=auth.uid()))`. Fecha o vazamento de diretório (guest deixa de ler TODOS os membros) e preserva o self-read para sempre. `gamification_points` também tem GRANT anon latente → revogar.

> ⚠️ Correção de auditoria: o agente de `gamification_points` classificou-a como "TIGHTEN_MOOT" alegando que `gamification_points_v4_org_scope` seria PERMISSIVE e faria backfill. **Verificação ao vivo provou o contrário** (`is_permissive=false`, RESTRICTIVE). Logo o tighten é efetivo; a tabela entra no Grupo C, não em "moot".

### Grupo D — course_progress — TIGHTEN simples (own-row já preservada) — 1 tabela
Tem policy own-row **separada** (`Auth update progress`, cmd=ALL) → trocar `course_progress_read_members` → autoritativo preserva o self-read automaticamente e fecha o vazamento. **Consequência cosmética:** a coluna "progresso de trilha dos OUTROS" no leaderboard (`gamification.astro:860`, leitura cross-member) fica vazia para um viewer guest. Aceitável; ou roteie a L860 por RPC SECDEF antes (mudança de código, fora do escopo RLS).

### Grupo E — publication_series — FIX_ROLE_DIVERGENCE — 1 tabela
Read policy tem `roles = PUBLIC` (não `authenticated` como as irmãs). Anon só é barrado pela ausência de GRANT SELECT — frágil. **Fix principal:** mudar role para `authenticated` (e, na mesma migration, trocar o helper p/ autoritativo — sem leitura direta guest, é seguro).

### Grupo F — events — LEAVE (no-op) — 1 tabela
Apertar `events_read_authenticated` é **inócuo**: `events_select_org_scope` é genuinamente **PERMISSIVE** (`is_permissive=true`, role PUBLIC) e readmite os 471. Eventos são semi-públicos por design (gate confidencial já exclui confidenciais). GRANT anon é **load-bearing** (`events_read_anon` da home pública) — **não** revogar. Restringir visibilidade de evento a guest seria mudança no modelo org-scope/confidencial, fora do escopo desta fase.

---

## 4. Remediação proposta (rascunho — NÃO aplicado)

```sql
-- GRUPO A + B (TIGHTEN simples). board_item_files preserva o guard deleted_at.
ALTER POLICY board_items_read_members          ON board_items                 USING (rls_is_authoritative_member());
ALTER POLICY assignments_read_members          ON board_item_assignments      USING (rls_is_authoritative_member());
ALTER POLICY checklists_read_members           ON board_item_checklists       USING (rls_is_authoritative_member());
ALTER POLICY tag_assignments_read_members      ON board_item_tag_assignments  USING (rls_is_authoritative_member());
ALTER POLICY project_boards_read_members       ON project_boards              USING (rls_is_authoritative_member());
ALTER POLICY audience_rules_read_members       ON event_audience_rules        USING (rls_is_authoritative_member());
ALTER POLICY invited_read_members              ON event_invited_members       USING (rls_is_authoritative_member());
ALTER POLICY event_tags_read_members           ON event_tag_assignments       USING (rls_is_authoritative_member());
ALTER POLICY webinars_read_authenticated       ON webinars                    USING (rls_is_authoritative_member() OR status = ANY (ARRAY['confirmed','completed']));
ALTER POLICY wle_read_members                  ON webinar_lifecycle_events    USING (rls_is_authoritative_member());
ALTER POLICY sub_authors_read_members          ON publication_submission_authors USING (rls_is_authoritative_member());
ALTER POLICY sub_events_read_members           ON publication_submission_events  USING (rls_is_authoritative_member());
ALTER POLICY partners_read_members             ON partner_entities            USING (rls_is_authoritative_member());  -- HIGH
ALTER POLICY cr_read_members                   ON change_requests             USING (rls_is_authoritative_member());
ALTER POLICY drive_file_discoveries_read_authenticated ON drive_file_discoveries USING (rls_is_authoritative_member());
ALTER POLICY initiative_drive_links_read_authenticated ON initiative_drive_links USING (rls_is_authoritative_member());
ALTER POLICY board_item_files_read_authenticated ON board_item_files          USING (deleted_at IS NULL AND rls_is_authoritative_member());
ALTER POLICY board_drive_links_read_authenticated ON board_drive_links        USING (rls_is_authoritative_member());

-- GRUPO C (own-row carve-out)
ALTER POLICY gamification_read_members ON gamification_points
  USING (rls_is_authoritative_member() OR member_id IN (SELECT id FROM members WHERE auth_id = auth.uid()));
ALTER POLICY attendance_read_members ON attendance
  USING (rls_is_authoritative_member() OR member_id IN (SELECT id FROM members WHERE auth_id = auth.uid()));
ALTER POLICY submissions_read_members ON publication_submissions
  USING (rls_is_authoritative_member() OR primary_author_id IN (SELECT id FROM members WHERE auth_id = auth.uid()));

-- GRUPO D (own-row já existe em policy separada)
ALTER POLICY course_progress_read_members ON course_progress USING (rls_is_authoritative_member());

-- GRUPO E (role divergence)
ALTER POLICY publication_series_read_members ON publication_series TO authenticated USING (rls_is_authoritative_member());

-- REVOKE de GRANTs anon latentes (não load-bearing)
REVOKE SELECT ON public.board_item_files, public.board_drive_links,
                 public.drive_file_discoveries, public.gamification_points,
                 public.initiative_drive_links FROM anon;

-- events: SEM mudança (LEAVE — tighten é no-op; anon GRANT é load-bearing)
```

**Governança:** DDL de policy via `apply_migration` + arquivo local `supabase/migrations/<ts>` + `repair --status applied` + **deletar a auto-row** de apply-time ([[feedback-apply-migration-creates-tracking-row]]) + `NOTIFY pgrst`. Prova de 2 lados ao vivo (guest bloqueado / autoritativo mantido / own-row preservado) ANTES de mergear, padrão #869 ([[feedback-auth-gate-test-both-sides]]). Repo público → **sem issue pública** detalhando o exploit (no pre-fix disclosure). `main` auto-deploya → **não mergear sem "vai" do PM** ([[feedback-no-merge-to-main-without-pm-approval]]).

---

## 5. Resumo executivo

- **18 tabelas** → TIGHTEN seguro/efetivo (Grupos A+B), incluindo a única **HIGH** (`partner_entities`, e-mails de parceiro).
- **3 tabelas** → own-row carve-out (Grupo C) — fecha vazamento de diretório de dado comportamental/financeiro de membro, preserva self-read.
- **1** → TIGHTEN c/ nota cosmética (course_progress); **1** → fix de role (publication_series); **1** → LEAVE/no-op (events).
- **5 tabelas** → REVOKE de GRANT anon latente (higiene de superfície).
- Behavior-neutral para os 40 membros autoritativos; só remove leitura de diretório dos ~23 guests pré-onboarding.
