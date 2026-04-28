# multiple_permissive_policies — full audit & batch plan (p74)

**Sessão**: p74
**Data**: 2026-04-27
**Trigger**: post-ADR-0057 (auth_rls_initplan 100% closed). MPP é o próximo P2 perf class (133 WARN inicial).
**Resultado batch 1 já shipped**: ADR-0058 batch 1 (publication_series_v4_org_scope flip) → 133 → **115 WARN** (-18).

---

## 1. Como o lint conta

`multiple_permissive_policies` emite 1 WARN por tupla `(schema, table, role∈resolved_roles, cmd)` onde **2+ policies PERMISSIVE** se aplicam. Importante:

* RESTRICTIVE policies não contam (são AND-combined separadamente)
* `polroles = {}` significa PUBLIC = aplica a TODOS os roles físicos (anon, authenticated, authenticator, dashboard_user, service_role, supabase_admin) → multiplica WARNs por ~6
* `cmd = ALL` em pg_policy se expande para SELECT+INSERT+UPDATE+DELETE → multiplica WARNs por 4

Exemplo: 2 policies PERMISSIVE com `cmd=ALL` e `polroles={}` em uma tabela = 2 × 4 cmds × 6 roles = **24 WARN** (mesmo que sejam logicamente apenas "2 policies overlapping").

## 2. Snapshot pós-batch 1 (115 WARN restantes)

### Top 15 tabelas por WARN count

| Count | Tabela |
|---|---|
| 6 | `cycles` |
| 6 | `publication_series` (residual após batch 1; era 24) |
| 6 | `tribe_deliverables` |
| 4 | `board_items` |
| 4 | `member_cycle_history` |
| 4 | `notification_preferences` |
| 4 | `project_boards` |
| 2 | `courses` |
| 2 | `members` |
| 2 | `tribe_selections` |
| 2 | `tribes` |
| 1 | `announcements` (e ~80 outras tabelas com 1 WARN cada) |

## 3. Categorias e batches propostos

### Class A — Anomaly fixes (PERMISSIVE → RESTRICTIVE)

**Status**: ✅ DONE batch 1 (ADR-0058)

* `publication_series_v4_org_scope` PERMISSIVE → RESTRICTIVE — único `*_v4_org_scope` que estava PERMISSIVE; canonical pattern é RESTRICTIVE em 40 outras tabelas.

**Estimativa de impacto**: ~24 WARN closed (entregue 18). Diferença: 6 WARN remanescentes em publication_series são overlap genuíno SELECT entre `superadmin_all` (ALL) e `read_members` (SELECT) — Class B candidate.

### Class B — Genuine duplicate (drop um)

Duplicates onde 2 policies fazem o mesmo USING. Drop o mais antigo, manter o mais recente / canonical.

**Candidates**:

| Tabela | Policies | Análise |
|---|---|---|
| `courses` | "Public courses" (role={}) + `anon_read_courses` ({authenticated,anon}) ambos com USING `true` | Drop "Public courses" (legacy, role={} é mais broad mas equivalente para SELECT × authenticated/anon). Effect: -2 WARN |
| `tribe_selections` | "Public tribe counts" (role={}) + `anon_read_tribe_selections` ({authenticated,anon}) ambos USING true | Mesmo padrão. Drop legacy. Effect: -2 WARN |

**Total Class B potencial**: ~4 WARN. Risk: low (idênticas). Action: ship together as ADR-0058 batch 2.

### Class C — Mergeable via OR (rewrite into single PERMISSIVE)

Sets de policies onde podemos compor em uma policy permissive única usando OR.

**Candidates**:

| Tabela | Set | Merge proposal |
|---|---|---|
| `cycles` | `cycles_admin_write` (ALL, USING superadmin) + `cycles_read_all` (SELECT, USING true) | Tricky: admin_write covers all 4 cmds, read_all covers SELECT only. SELECT has 2 policies = 6 WARN. Merge: split admin_write into separate INSERT/UPDATE/DELETE policies + leave read_all. Net: same number of policies, more lines, BUT zero overlap on SELECT → 0 WARN. Effect: -6 WARN. Cost: 4 policies in place of 1 + 1. Trade-off marginal |
| `tribe_deliverables` | `tribe_deliverables_write_v4` (ALL) + `tribe_deliverables_read` (SELECT, USING auth.role()='authenticated') | Same shape as cycles. Same merge pattern viable. Effect: -6 WARN |
| `board_items` | `board_items_superadmin_all` (ALL) + `board_items_write_v4` (ALL) + `board_items_read_members` (SELECT) | 3 policies, all overlap on SELECT (3) + INSERT/UPDATE/DELETE (2 each). Mergeable: combine first two into single PERMISSIVE with OR predicate (`is_superadmin OR rls_can_for_initiative('write_board')`), keep read_members separate. Reduces SELECT overlap from 3 to 2; INSERT/UPDATE/DELETE from 2 to 1. Effect: -8 to -10 WARN. Cost: 1 fewer policy, more complex predicate |
| `project_boards` | Same structure as board_items | Same pattern. Effect: -8 to -10 WARN |

**Total Class C potencial**: ~28-32 WARN. Risk: medium (predicate composition). Action: defer for ADR-0058 batches 3+ pending PM review.

### Class D — Intentional separation (DON'T merge, document)

Sets de policies onde split é semanticamente intencional — merging perderia readability.

**Examples**:

| Tabela | Why split is intentional |
|---|---|
| `members` (5 SELECT policies) | `members_select_own` + `_admin` + `_stakeholder` + `_tribe_leader` + `_read_by_members` cobrem 5 paths distintos com 5 predicados radicalmente diferentes (auth_id match, V4 admin gate, partner gate, tribe scope, generic member). Merging em 1 policy with 5-way OR perde reviewability. Tracking: documentar como "intentional" e suprimir lint via comment se possível |
| `notification_preferences` | `notifpref_own` (USING member_id=self) + `rpc_only_deny_all` (USING false). Permissive false = belt-and-suspenders pattern (no-op + ownership filter). Intentional |
| `member_cycle_history` | Same belt-and-suspenders pattern: `mch_superadmin_write` (USING has_min_tier(5)) + `rpc_only_deny_all` (USING false). Intentional |

**Total Class D**: ~30-40 WARN. Action: leave as-is, document the pattern in this doc + ADR-0058. **No code change.**

### Class E — Per-table judgment (everything else)

Restante (~50 WARN distribuídas em ~80 tabelas com 1 WARN cada). Cada caso requer review:
* É anomaly tipo A?
* É duplicate tipo B?
* É mergeable tipo C?
* É intentional tipo D?

**Action**: ship in micro-batches (1-3 tables per ADR) as PM signals or as found in unrelated work.

## 4. Decision matrix per batch

| Batch | Target | Class | Estimated closure | Risk |
|---|---|---|---|---|
| ADR-0058 batch 1 ✅ | publication_series_v4_org_scope flip | A | 18 WARN (133→115) | Low |
| ADR-0058 batch 2 | courses + tribe_selections drop legacy | B | 4 WARN | Low |
| ADR-0058 batch 3 | cycles + tribe_deliverables split admin_write | C | 12 WARN | Medium (verify SELECT path) |
| ADR-0058 batch 4 | board_items + project_boards merge superadmin+write_v4 | C | 16-20 WARN | Medium (predicate complexity) |
| (none) | members + notification_prefs + member_cycle_history | D | 0 (document only) | — |
| ADR-0058 batch 5+ | Class E micro-batches | E | ~50 WARN total | Variable |

**Total potencial closure**: ~80-100 WARN (133 → 30-50 residuals from Class D + intentional E).

**Floor (intentional)**: ~30-40 WARN remain by design.

## 5. Recommendation

**Autonomous**: ship batch 1 (DONE) + batch 2 (Class B drop legacy duplicates — clean win).

**PM signal needed**:
- Batch 3-4 (Class C merges) — predicate rewriting has medium risk; PM should sign off on the OR composition pattern before scaling
- Batch 5+ (Class E micro-batches) — per-table judgment

**No-op (document)**:
- Class D — leave as-is, document in ADR-0058 + this audit

## 6. References

* ADR-0011 (V4 authority, RLS pattern)
* ADR-0053..0057 (auth_rls_initplan — sibling RLS perf series)
* ADR-0058 (this batch)
* Supabase docs: <https://supabase.com/docs/guides/database/postgres/row-level-security#permissive-vs-restrictive>

---

Assisted-By: Claude (Anthropic)
