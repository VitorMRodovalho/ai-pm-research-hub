# ADR-0110 — Sponsor read-only de fato: split read/write (`view_finance`/`view_partner`) e revogação dos write seeds

**Status:** Accepted (2026-06-28, Onda 2 FU-1, #952)
**Supersede (parcial):** ADR-0025 §Q1 (sponsors com `manage_finance`) · seed `sponsor×sponsor → manage_partner` da migration `20260413400000_v4_phase4_engagement_permissions.sql` (reusada por ADR-0033 Phase 1).
**Retém:** o trigger `notify_sponsor_finance_entry()` da ADR-0043 permanece como **registro histórico** (deixa de disparar — sponsor não passa mais no gate de escrita `manage_finance`).
**Relacionado:** ADR-0007 (V4 `can()` autoridade), ADR-0011 (cutover V4), ADR-0033/0034 (partner subsystem V4), ADR-0023 (ladder), Onda 2 (handoff pt5/pt6; Ivan/sponsor audit), plano `~/.claude/plans/onda-2-auditoria-keen-kahn.md` (achado **F1** + **F9**), `docs/reference/V4_AUTHORITY_MODEL.md`.

## Contexto

A designação institucional `sponsor` (presidentes de capítulo parceiro + o presidente da sede PMI-GO, Ivan, que apresenta o LIM ao PMI LATAM) tinha o seed `sponsor×sponsor` concedendo **5 actions** em scope `organization`:

```
manage_finance               ← WRITE (ADR-0025 Q1)
manage_partner               ← WRITE (seed 20260413400000, reusado por ADR-0033)
participate_in_governance_review
view_chapter_dashboards
view_internal_analytics
```

A decisão de produto (Onda 2, achado **F1**) é: **sponsor é read-only de fato.** Mas um `DELETE` ingênuo dos dois write seeds **também** removeria leituras de sponsor, porque as **mesmas duas actions** gateiam tanto ESCRITA quanto LEITURA em ~25 funções SECDEF + 6 gates do MCP:

- `manage_finance` gateia 6 writes (`create/delete_cost_entry`, `create/delete_revenue_entry`, `update_kpi_target`, `update_sustainability_kpi`) **e** 4 reads (`get_cost_entries`, `get_revenue_entries`, `get_sustainability_dashboard`, `get_sustainability_projections`).
- `manage_partner` gateia 7 writes (partner CRUD, attachments, `link/unlink_partner_to_card`, `create_external_speaker_engagement`, `submit_chapter_need`) **e** leituras de partner/portfolio/attendance grids (`get_partner_pipeline`, `get_partner_entity_attachments`, `get_partner_interaction_attachments`, `get_portfolio_timeline`, `get_attendance_grid`, `get_initiative_attendance_grid`, `get_tribe_attendance_grid`, `list_initiative_events`).

Como os painéis admin que o sponsor LÊ (`admin.partners`/`admin.sustainability`/`admin.portfolio`/`admin.analytics`, concedidos em `permissions.ts`) puxam dados dessas RPCs, um `DELETE` puro deixaria os painéis **visíveis porém sem dados** (`permission_denied`) — contradizendo a matriz-alvo (sponsor SEDE = read completo; sponsor PARCEIRO = read escopado por capítulo no FU-2). Esta é a divergência **F9** (camada client read-only vs seed backend write) somada ao acoplamento read/write na mesma action.

Decisão do PM (2026-06-28, `AskUserQuestion`): **"Split read/write (preserve reads)"** — a opção arquiteturalmente correta, mesmo sendo a maior.

## Decisão

**Separar leitura de escrita no V4 introduzindo duas READ actions dedicadas e repontando os gates de leitura para elas; só então revogar os write seeds do sponsor.**

1. **Novas actions `view_finance` + `view_partner`** (scope `organization`), seedadas a **exatamente o conjunto atual de detentores de `manage_*`** — de modo que **nenhum leitor atual perde acesso**:
   - `view_finance` → `volunteer×{manager,deputy_manager,co_gp}` + `sponsor×sponsor`
   - `view_partner` → `volunteer×{manager,deputy_manager,co_gp}` + `sponsor×sponsor` + `chapter_board×liaison`
2. **Repontar 12 RPCs de LEITURA** `can_by_member(_, 'manage_X') → can_by_member(_, 'view_X')` (mudança cirúrgica: só o literal da action no gate, provado `len_after = len_before − 2` por função, sem tocar comentários/mensagens) + **6 gates de leitura do MCP** (`index.ts`: prompt `isSponsor`, `get_chapter_kpis`, `get_annual_kpis`, `get_partner_pipeline`, `get_portfolio_health`, `get_role_transitions`).
3. **Manter `manage_finance`/`manage_partner` como gate de ESCRITA** em todas as funções/tools de write (13 RPCs + 5 MCP tools).
4. **Revogar** `sponsor×sponsor → {manage_finance, manage_partner}`.

Resultado líquido — a audiência de leitura é **idêntica** à de antes (view_X = mesmo conjunto que tinha manage_X); a **única** mudança é que `sponsor×sponsor` perde as duas WRITE actions. Sponsor fica com **5 actions, todas read/participation**: `view_finance`, `view_partner`, `participate_in_governance_review`, `view_chapter_dashboards`, `view_internal_analytics`.

`get_in_dashboard` é deixado intacto (já admite sponsor pela ramificação `view_internal_analytics OR manage_partner`; nenhuma regressão).

## Verificação (ao vivo, 2026-06-28)

Antes (todos `true`) → depois, via `can_by_member`:

| Persona | manage_finance (W) | manage_partner (W) | view_finance (R) | view_partner (R) |
|---|---|---|---|---|
| 5 sponsors (Ivan/PMI-GO, Felipe/MG, Francisca/CE, Márcio/RS, Matheus/DF) | ❌ revogado | ❌ revogado | ✅ preservado | ✅ preservado |
| GP/manager (Vitor, Fabricio) | ✅ | ✅ | ✅ | ✅ |
| `chapter_board×liaison` (7) | — | ✅ (mantido) | — | ✅ (mantido) |

Bloco `DO` in-tx fail-closed na migration (sponsor com 0 write seeds, 2 view seeds, 0 RPCs alvo ainda gateando em `manage_X`).

## Trade-offs aceitos

1. **`submit_chapter_need` (write) sai do alcance do sponsor.** Reportar necessidade de capítulo é uma escrita; consistente com "read-only". Se o PM quiser devolver essa capacidade pontual, ela merece um grant próprio e estreito (follow-up), não a reabertura do write de partner.
2. **Mensagens de erro de negação** das RPCs de finance ainda citam o nome legado da action (ex.: `'permission_denied: manage_finance required'`) embora o gate agora seja `view_finance`. Mantido para deixar o repoint cirúrgico (só o gate). Cosmético — só aparece a quem é negado.
3. **Audiência de leitura inalterada inclui leituras org-wide** (partner pipeline, attendance grids) para sponsors PARCEIROS. Isto é uma exposição cross-capítulo herdada — **escopo do FU-2** (chapter-scope), não do FU-1. FU-1 preserva o comportamento de leitura atual; FU-2 o restringe por capítulo.
4. **`participate_in_governance_review`** permanece no sponsor (não é leitura pura). Não foi sinalizado no achado F1 e fica fora do escopo travado do FU-1; registrado aqui para revisão futura do PM.

## Mecânica de entrega

- Migration literal `20260805000291_onda2_fu1_sponsor_read_only_split.sql` (SSOT replayable: Part 1 seeds idempotentes + Part 2 revoke + Part 3 os 12 `CREATE OR REPLACE` literais + Part 4 verify DO). Bodies gerados deterministicamente de `pg_get_functiondef` + `regexp_replace` do gate (zero transcrição manual).
- Aplicado ao remoto via MCP `apply_migration` (o `db push` da CLI está bloqueado pelo drift histórico de migration — ADR-0097), `migration repair --status applied 20260805000291`, `NOTIFY pgrst`.
- EF `nucleo-mcp` redeployada com os 6 gates de leitura repontados.
- `permissions.ts`: `ADMIN_TIER_ACTIONS += view_finance, view_partner`; comentários de sponsor/seed atualizados (F9 fechado: client read-only agora bate com o catálogo backend).
- Teste de contrato forward-defense (sponsor sem write seed; nenhuma RPC de leitura alvo gateando em `manage_X`).

## Invariantes respeitados

function-anchored · read ≠ write (agora **enforçado** no catálogo, não só no client) · member-lifecycle = GP-only intacto · confidenciais #785 inalterados · **NÃO** seed-expandir actions destrutivas (ao contrário: revoga) · DDL via `apply_migration` + sync de migration local + repair (database.md).
