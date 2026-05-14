# ADR-0080 — V4 Engagement Canonical (Deprecate `members.initiative_id`)

**Status:** PROPOSED — pending PM sign-off + Phase A/B/C cutover
**Date:** 2026-05-14 (p159 Sessão #3)
**Author:** Claude (drafted)
**Supersedes:** none
**Related:** ADR-0004 (Domain Model V4 Master) · ADR-0005 (Initiative is the Domain Primitive) · ADR-0006 (Person + Engagement Identity Model) · ADR-0008 (Engagement Lifecycle Config) · ADR-0009 (Initiative Kinds Configuration) · `memory/feedback_members_initiative_id_v3_v4_hybrid_design.md` (p155 sediment)

---

## Contexto

### O drift V3+V4 hybrid hoje

Domain Model V4 (concluído 2026-04-13, ADRs 0004-0009) moveu identity + autoridade para `persons` + `engagements`, com `initiatives` como primitivo. Mas a coluna legacy `members.initiative_id` (V3 — primary tribe 1:1) **NÃO foi removida** porque alguns componentes frontend ainda dependem dela como atalho de "qual tribo este membro pertence".

p155 G-NEW (commit `778ad78`, migration `20260621000000`) instalou trigger `trg_sync_member_initiative_from_engagement` que mantém `members.initiative_id` consistente como espelho do engagement primário em V4. **Bridge tático, não estrutural.**

**Sediment p155** (`feedback_members_initiative_id_v3_v4_hybrid_design.md`):
- V3 modela 1:1 (primary tribe single)
- V4 modela N:N (engagements ativos simultâneos: research_tribe + workgroup + committee + ...)
- 13 CONFLICT (V3 primary ≠ algum V4 engagement) **não é bug** — esperado pelo design V3+V4
- 11 NULL_DRIFT pré-G-NEW (member só em V4, sem V3 primary) backfillados via trigger sync

### Audit atual (p159 Sessão #3)

**RPC layer (DB)**: praticamente livre de referência direta a `members.initiative_id`:
- `get_member_tribe(p_member_id)` já lê V4 (`JOIN engagements e ON e.person_id=m.person_id JOIN initiatives i WHERE i.kind='research_tribe'`)
- `join_initiative` escreve V4 (INSERT em `engagements`) — não toca `members.initiative_id`
- Apenas 4 migrations referenciam (todas legítimas — column definition + V4 retrofit + p155 backfill + retrofit P2)
- 0 RPCs públicos têm `members.initiative_id` literal em production

**Frontend (src/)**: 3 arquivos consomem `initiative_id` da `members` row:
- `src/components/boards/TribeKanbanIsland.tsx` — usa `member.initiative_id` para filtrar membros da tribo na kanban view
- `src/hooks/useBoard.ts` — bridge V3 prop em hook do BoardEngine
- `src/lib/admin/types.ts` — type defs incluindo a coluna

**Worker/EFs**: nenhum acesso direto (todos via RPC).

**Data state**: 49 active+current_cycle members, 39 com V3 primary, 10 sem (post-backfill esperado: 0 NULL_DRIFT via trigger).

### Por que finalmente deprecar

1. **Source of truth divergence**: ter a info em 2 lugares (V3 mirror + V4 canonical) garante drift. Trigger ajuda mas não elimina race conditions (e.g. UPDATE em members.initiative_id manual fora do trigger).
2. **Mental load**: dev novo lê o código, vê `members.initiative_id`, assume single-tribe model — perde N:N reality.
3. **Schema invariant gap**: nenhum CHECK constraint garante V3 ↔ V4 alignment hoje. Bugs silenciosos possíveis.
4. **Cutover é pequeno**: scope real é 3 arquivos frontend + drop column + cleanup do trigger. Estimativa ~3-4h sessão dedicada (não os "100 RPCs" sediment p155 sugeria).
5. **Bloqueia simplificação futura**: queries cross-tribe complexas têm que cobrir 2 caminhos (V3 OR V4 join). Pós-cutover: V4-only é canônico.

---

## Decisão

Deprecar `members.initiative_id` em **3 fases progressivas**, mantendo o trigger sync ativo durante shadow period para permitir rollback rápido. Cutover **frontend-first** (não-bloqueante para DB).

### Fase A — Frontend cutover (shadow on)
1. **TribeKanbanIsland.tsx**: replace `member.initiative_id === currentTribe` filters por hook que chama RPC `get_initiative_members(initiative_id)` (V4-only). Hook já existe.
2. **useBoard.ts**: deprecar prop `initiative_id` derivada de members; usar `get_member_tribe(member_id)` RPC (V4-only, já implementada).
3. **admin/types.ts**: marcar `members.initiative_id` como `@deprecated` no JSDoc + manter no type para compat durante shadow.

**Critério de done Fase A:**
- Grep `members\.initiative_id\|m\.initiative_id\|mem\.initiative_id` no `src/` retorna apenas refs em `admin/types.ts` + deprecation comments.
- TribeKanbanIsland + BoardEngine + qualquer dashboard com filtro "members of tribe X" carrega via V4 (`get_initiative_members` ou similar).
- Smoke: para member com 2 engagements (e.g. Fabricio em research_tribe + workgroup), UIs mostram membership correta em ambas.

**Tempo estimado:** ~2-3h.

### Fase B — DB invariant + monitoring (shadow ainda on, 7d quiet window)
1. Adicionar invariante schema (CI test em `tests/contracts/`): `I_MEMBERS_INITIATIVE_ID_HAS_MATCHING_ACTIVE_V4` — para todo member com `initiative_id IS NOT NULL`, deve existir engagement ativo do `kind` apropriado (`research_tribe` ou primary kind do membro).
2. Adicionar query exec scheduled (pg_cron daily): `SELECT count(*) FROM members WHERE initiative_id IS NOT NULL AND NOT EXISTS (engagement v4)` — log em `data_anomaly_log` quando > 0.
3. Adicionar test contract: `tests/contracts/v4-engagement-canonical.test.mjs` — verificar grep frontend não tem regression para V3 reads.

**Critério de done Fase B:**
- Invariante passa 7 dias consecutivos (quiet window).
- Nenhum WARN no `data_anomaly_log` para o cron.
- Nenhum bug reportado pelo PM em UIs de membros/tribos durante shadow.

**Tempo estimado:** ~1h setup invariant + 7 dias observação.

### Fase C — Cutover final (shadow off, drop column)
1. Drop trigger `trg_sync_member_initiative_from_engagement` (G-NEW p155).
2. Drop column `members.initiative_id` (após confirmar 0 references via search_path scan).
3. Update `admin/types.ts`: remover `initiative_id` do shape de `Member`.
4. Atualizar `feedback_members_initiative_id_v3_v4_hybrid_design.md` como **superseded** + linkar ADR-0080.
5. Atualizar `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` adicionando ADR-0080 como cleanup post-V4.

**Critério de done Fase C:**
- Migration aplicada via `apply_migration` + repair.
- `npx astro build` clean + tests 1437/0/1475 baseline.
- Nenhum RPC pg_proc referencia `members.initiative_id` (verify via SQL audit).

**Tempo estimado:** ~1h.

---

## Plano de cutover total

| Fase | Esforço | Quando | Risco |
|---|---|---|---|
| A — Frontend V4 reads | ~2-3h | Próxima sessão dedicada | Baixo — RPCs V4 já existem |
| B — Invariant + monitoring (7d shadow) | ~1h setup + 7d wait | Após A merge | Baixo |
| C — Drop column + trigger | ~1h | Após B verde 7d | Médio — irreversível |

**Total ~4-5h código + 7 dias observação.** Aborto a qualquer momento durante A ou B é trivial (revert frontend ou trigger continua funcionando).

---

## Invariantes (CI tests após Fase A)

### I-V4-1: Frontend não-read direto de `members.initiative_id`
Grep test em `tests/contracts/v4-engagement-canonical.test.mjs`:
```js
assert.equal(
  exec("grep -rE 'member\\.initiative_id|m\\.initiative_id' src/").lines.filter(l => !l.includes('@deprecated')).length,
  0,
  'No direct V3 reads of members.initiative_id should remain (use get_member_tribe or get_initiative_members V4 RPCs)'
);
```

### I-V4-2: V3 mirror consistency (during shadow B)
SQL CHECK em pg_cron:
```sql
SELECT count(*) AS drift
FROM members m
WHERE m.initiative_id IS NOT NULL
  AND m.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM engagements e
    WHERE e.person_id = m.person_id
      AND e.initiative_id = m.initiative_id
      AND e.status = 'active'
  );
-- expect: 0 sustained over 7 days
```

### I-V4-3: Post-Fase C — column dropped
```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='members' AND column_name='initiative_id';
-- expect: 0 rows post-cutover
```

---

## Anti-patterns (continuar evitando, mesmo pós-cutover)

1. **NÃO criar coluna "primary X" 1:1 em members** quando o modelo correto é N:N via engagements. Resistir à tentação de "primary tribe", "primary committee", etc. Se UI precisa de "default", deriva por priority kind (research_tribe > study_group > committee > workgroup) em RPC, não em coluna.

2. **NÃO referenciar `members.initiative_id` em código novo** mesmo durante shadow. CI test I-V4-1 vai pegar.

3. **NÃO usar `member.initiative_id` em RLS policies** novas. Sempre via `engagements.initiative_id WHERE status='active'`.

4. **NÃO escrever em `members.initiative_id` direto** fora do trigger sync. Toda mudança de "primary tribe" deve passar por `engagements` (e.g. revoke + grant via `manage_initiative_engagement`).

---

## Risco + rollback

**Risco principal:** dashboards legacy ou queries cross-tribe assumem `members.initiative_id` populado. Sediment p155 confirmou ~10 NULL_DRIFT existiam → backfilled. Pós-Fase C: nenhum query deveria assumir.

**Rollback paths:**
- Fase A revert: git revert dos 3 arquivos frontend → V3 reads voltam, trigger ainda mantém data atual.
- Fase B revert: drop invariant + cron query, sem impacto data.
- Fase C revert: re-CREATE column `members.initiative_id text` + UPDATE backfill via engagements query (matriz priority kind p155 G-NEW). Trigger re-CREATE. **Bridge ainda gritando data via trigger forward**, mas reads frontend V4 ficaram (sem regressão funcional).

Pós-cutover Fase C, qualquer dependência V3 surgindo = bug → fix com query V4, não recriar coluna.

---

## Open questions para PM (pré-execução)

1. **Timing**: PM tem janela para próxima sessão dedicada (~3h Fase A)? Ou bundle com outra entrega visual (ex: TribeKanbanIsland refresh)?

2. **Test invariant trigger**: adicionar invariante I-V4-2 como pg_cron diário OU em `check_schema_invariants()` (suite existente)? Sediment recomenda check_schema_invariants pra consistência com outros invariants V4.

3. **Frontend deprecation strategy**: PM prefere (a) cutover sharp Fase A (remover refs imediatamente) ou (b) shadow mode (manter refs V3 com fallback V4 condicional, deprecation por 7d antes de remover)? (a) é mais limpo; (b) é mais conservador.

4. **Type definition em admin/types.ts**: manter `initiative_id?: number | null` no shape de `Member` post-Fase C (compat futura) ou remover totalmente? Recomendação: remover (force breaking change clareza).

---

## Status próximas ações

- **PM sign-off pendente** — esta ADR é PROPOSED. Após sign-off, Fase A vira sessão executável.
- **Fase A — quando agendada**: estimativa ~3h (TribeKanbanIsland refactor + useBoard hook + admin/types annotation).
- **Fase B — após A**: ~1h setup invariant + 7d quiet window.
- **Fase C — após B verde**: ~1h cutover final.

Próximo sediment proposto pós-cutover: `feedback_v3_v4_hybrid_cleanup_canonical.md` documentando o pattern de "deprecar coluna legacy mantendo bridge via trigger durante shadow".

---

## References

- ADR-0004: Domain Model V4 Master
- ADR-0005: Initiative is the Domain Primitive
- ADR-0006: Person + Engagement Identity Model
- ADR-0008: Engagement Lifecycle Configuration
- ADR-0009: Initiative Kinds Configuration
- `memory/feedback_members_initiative_id_v3_v4_hybrid_design.md` (p155 sediment — supersedes pós-Fase C)
- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md`
- Migration `20260621000000_p155_gnew_backfill_null_drift_plus_sync_trigger.sql` (G-NEW bridge)
- Migration `20260413320000_v4_phase3_engagements_table.sql` (V4 base)
