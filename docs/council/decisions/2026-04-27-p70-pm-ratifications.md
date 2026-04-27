# PM Decision Log — 2026-04-27 p70 — Ratifications + Backlog Resolution

**Decisor**: Vitor (PM)
**Data**: 2026-04-27
**Sessão**: p70 (clean exit)
**Contexto**: PM aceita análise comprehensive de 16+ pendências apresentada em
final de sessão p70. Decisões abaixo desbloqueam autonomous work para sessões
futuras (p71+).

---

## A. ADRs ratificadas (4)

| ADR | Status | Justificativa concisa |
|---|---|---|
| **ADR-0037** chapter_needs subsystem 100% V4 | ✅ Accepted | Path Y formalizado; precedent já reusado em ADR-0039. Drift = 1 (João, precedented padrão 8x) |
| **ADR-0038** p68 cleanup batch | ✅ Accepted | 1 zero-drift convert + 2 security drift fixes (parameter-gate + no-gate). LGPD-relevant |
| **ADR-0039** countersign subsystem 100% V4 + register_attendance_batch fix | ✅ Accepted | 3 gains (engagement-without-designation drift correction); zero losses; subsystem 100% V4 |
| **ADR-0040** p70 cleanup batch | ✅ Accepted | DROP dead helper + 3 REVOKE-from-anon. Defense-in-depth pure |

---

## B. Phase B'' deferred — PM ratificações com safeguards

### B.1 — `create_cost_entry` / `create_revenue_entry` → V4 `manage_finance` (+5 sponsors)
**PM decisão**: ✅ ACEITO com safeguard
**Implementação requerida (próxima sessão)**:
- Conversion para `can_by_member('manage_finance')` (mirrors ADR-0038 pattern)
- **Safeguard**: trigger no INSERT em `cost_entries`/`revenue_entries` que dispara notification para holders de `manage_platform` quando o created_by é `sponsor × sponsor` engagement (não-volunteer)
- Audit log entry mais robusto: incluir engagement context + chapter_board affiliation
- ADR-0041-ext ou nova ADR-0042

**Justificativa PM signoff**: V4 catalog explicitly grants sponsor manage_finance; os 5 sponsors são chapter_board × board_member ativos (não passive sponsors). Notification trigger garante governance visibility sem bloquear.

### B.2 — `generate_manual_version` → V4 `manage_platform` com 2-of-N approval
**PM decisão**: ✅ ACEITO com safeguard
**Implementação requerida (próxima sessão)**:
- Conversion para `can_by_member('manage_platform')`
- **Safeguard**: 2-of-N approval pattern similar ao ADR-0016 IP ratification
  - Nova table `pending_manual_version_approvals(id, version_label, proposed_by, proposed_at, signoff_member_id, signoff_at)`
  - Modificar `generate_manual_version` para 2 fases: `propose_manual_version` (cria pending) + `confirm_manual_version` (require 2nd signoff)
  - 24h window; expira se não confirmado
- ADR-0042 ou ADR-0041-ext

**Justificativa PM signoff**: alta-impacto operação (substitui Manual ativo + marca CRs implemented). 2-of-N evita unilateral action mesmo com manage_platform tier.

### B.3 — Sponsor visibility restore (drift signals #3 + #4) — `view_chapter_dashboards` action
**PM decisão**: ✅ ACEITO Opção C (action específica)
**Implementação requerida (próxima sessão)**:
```sql
-- Catalog seed
INSERT INTO engagement_kind_permissions (kind, role, action, scope) VALUES
  ('chapter_board', 'board_member', 'view_chapter_dashboards', 'organization'),
  ('chapter_board', 'liaison', 'view_chapter_dashboards', 'organization'),
  ('sponsor', 'sponsor', 'view_chapter_dashboards', 'organization');

-- Para cada admin dashboard reader RPC convertido em ADR-0011 Amendment B:
-- Adicionar OR can_by_member('view_chapter_dashboards') gate
-- Limitado a leitura (NÃO write). manage_platform continua sole para writes.
```
- Restaura visibility para 7 users (5 sponsors + 2 chapter_liaisons)
- Mantém tightening de write/manage_platform per ADR-0011 Amendment B
- ADR-0043 candidate

**Justificativa PM signoff**: chapter governance precisa visibility operacional; tightening era over-correction. Action específica `view_*` vs `manage_*` cria precedent pattern claro.

---

## C. Charter / sweep decisions

### C.1 — `auth_leaked_password_protection` toggle
**PM decisão**: ✅ ATIVAR
**Owner**: PM (action manual no Supabase Dashboard, ~2 min)
**Path**: Supabase Dashboard → Project Settings → Authentication → Enable "Leaked password protection"
**Impacto**: 1 advisor WARN closure permanente. LGPD Art. 46 alignment.

### C.2 — Q-E charter formal (770 SECDEF-WARN)
**PM decisão**: ✅ DEFER ATÉ Phase B'' ≥50%
**Re-evaluation trigger**: quando audit doc mostrar Phase B'' ≥123/246
**Continuar progress incremental**: cada Phase B'' conversion fecha 1-2 advisor entries via REVOKE-from-anon pattern (implícito Q-E progress)
**Justificativa**: ROI marginal já capturado por Phase B'' work; charter formal seria overhead

### C.3 — ADR-0028 deferred layers (adapter pattern)
**PM decisão**: ⏭️ MANTER DEFER
**Re-evaluation trigger**: quando service-role-bypass surface ≥10 fns (atualmente ~5-7)

---

## D. #82 closure plan
**PM decisão**: ✅ FECHAR #82 + CRIAR 2 SPINOFFS

**Implementação requerida (próxima sessão)**:
1. Criar issue `#82-pdf-smoke`: smoke test do PDF flow de `public_members` (10 min de trabalho manual; fecha residual Onda 2)
2. Criar issue `#82-gam-leaderboard-rpc-v2`: feature enhancement (pagination + cycle filter + opt-out withholding) — não security
3. Fechar #82 main com comment: "Closed per ADR-0024 (public_members accepted-risk). Residual operational items spun off to #82-pdf-smoke + #82-gam-leaderboard-rpc-v2."

**Justificativa**: ADR-0024 já é o reference doc para accepted-risk. #82 main não tem mais blockers. Operational items separados não precisam ficar no security issue.

---

## E. Design sessions PM-blocked

### E.1 — #91 G5 Whisper
**PM decisão**: 📅 AGENDAR DESIGN SESSION 1h (PM owner)
**Pre-agenda**: Decision A (visibilidade), B (persistência), C (LGPD), D (audit trail). Claude pode draft proposals pre-session.

### E.2 — #88 Convocação iniciativas
**PM decisão**: 📅 AGENDAR DESIGN SESSION 1h (PM owner)
**Pre-agenda**: Push vs pull, sub-categorias por chapter, cycle alignment.

### E.3 — `preview_gate_eligibles` ladder choice
**PM decisão**: ✅ Opção C (hybrid cache + invalidation)
**Implementação requerida (próxima sessão)**: 2-3h work.
- Materialized view `preview_gate_eligibles_cache(member_id, doc_type, eligible_gates jsonb, last_refreshed)`
- Refresh trigger on `auth_engagements` mutation
- Adapt `preview_gate_eligibles` RPC para read cache + fallback para `_can_sign_gate` se cache stale
- ADR-0016 Amendment 3

---

## F. ADR-0015 Phase 5 timing
**PM decisão**: ⏭️ DEFER QUARTER TARGET = Q3 2026 (post-CBGPL audit)
**Re-evaluation trigger**: post-CBGPL audit closure
**Justificativa**: tribe_id drop affects MANY downstream queries; risk de regression durante CBGPL window é HIGH

---

## G. ADR-0041 candidate — document_comments + curation cluster
**PM decisão**: ✅ Opção A — Nova V4 action `participate_in_governance_review`
**Implementação requerida (próxima sessão)**:
1. Migration: catalog seed para nova action
   ```sql
   INSERT INTO engagement_kind_permissions (kind, role, action, scope) VALUES
     ('volunteer', 'manager', 'participate_in_governance_review', 'organization'),
     ('volunteer', 'deputy_manager', 'participate_in_governance_review', 'organization'),
     ('volunteer', 'co_gp', 'participate_in_governance_review', 'organization'),
     ('chapter_board', 'liaison', 'participate_in_governance_review', 'organization');
   ```
2. Future: quando criar `committee_curator` engagement kind, adicionar mapping
3. Convert 9 fns:
   - **Document comments (3)**: `create_document_comment`, `list_document_comments`, `resolve_document_comment`
   - **Curation/board writers (6)**: `assign_curation_reviewer`, `assign_member_to_item`, `submit_curation_review`, `submit_for_curation`, `unassign_member_from_item`, `publish_board_item_from_curation`
4. ADR-0041 doc + 2 migrations (convert + REVOKE-from-anon)

**Justificativa PM signoff**: desbloqueia 9 fns em 1 ADR; cria precedent claro para curator V4 representation; aligned com V4 catalog source-of-truth.

---

## H. Helper body V3→V4 conversion batch
**PM decisão (parcial)**: 
- ✅ Convert `_can_manage_event` → `can_by_member('manage_event')` (autonomous)
- ⏭️ Defer `_can_sign_gate` (precisa ADR-0016 Amendment 3 design)
- ⏭️ Leave-as-is `has_min_tier` (low value)
- ⏭️ Defer `can_manage_comms_metrics` (Path Y comms_member preservation — design call)

**Implementação requerida**: pequena parte da próxima ADR-0041 (single-fn conversion).

---

## I. New issues priority order (PM ratifica)

### Sprint near-term (3 sessions)
1. **ADR-0041** participate_in_governance_review + 9 fns conversion + view_chapter_dashboards action restore
2. **#87** Selection bias-prevention + MCP candidato (just-in-time cycle3-2026)
3. **#97** External speaker engagement lifecycle (LATAM LIM blocker)

### Sprint mid-term (5 sessions)
4. **#84** Meeting↔Board traceability gap
5. **#94** Pipeline unificado publicação
6. **#96** Newsletter Frontiers launch (operational simple)
7. cost/revenue notification trigger + audit log enhancement (B.1 implementation)
8. generate_manual_version 2-of-N approval (B.2 implementation)
9. preview_gate_eligibles hybrid cache (E.3 implementation)

### Defer com triggers
- **#88** Convocação iniciativas → após PM design session
- **#89** portfolio_item gating → aguardar visibility pattern from ADR-0041
- **#95** Echo-chamber/narrative-cluster → POC research only (not product feature)

---

## J. Action items consolidados

### Immediate (PM time, ~15 min total)
- [ ] PM toggle `auth_leaked_password_protection` no Supabase Dashboard
- [ ] PM agenda #91 G5 Whisper design session (1h)
- [ ] PM agenda #88 Convocação iniciativas design session (1h)

### Próxima sessão técnica (Claude autonomous)
- [ ] ADR-0041 implementation (participate_in_governance_review action + 9 fns convert)
- [ ] view_chapter_dashboards action restore (B.3)
- [ ] _can_manage_event V3→V4 conversion (H, autonomous part)
- [ ] #82 closure + 2 spinoffs (D)

### Sprint mid-term (PM picks order)
- B.1 cost/revenue notification trigger
- B.2 generate_manual_version 2-of-N approval
- E.3 preview_gate_eligibles hybrid cache
- #87 Selection bias-prevention
- #97 External speaker
- #84, #94, #96

---

## K. Ratification metadata

- **PM**: Vitor Maia Rodovalho (sole authority via is_superadmin + manager engagement)
- **Date**: 2026-04-27
- **Method**: PM accepted Claude analysis recommendations in chat session p70
- **ADRs status update**: 4 ADRs marked Accepted (Status field updated in same commit)
- **Audit doc update**: this decision log + ADR Status updates referenced
- **Path A/B/C optionality**: all decisions preserve optionality (per Claude analysis)
