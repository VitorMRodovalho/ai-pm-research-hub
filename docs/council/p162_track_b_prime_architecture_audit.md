# Track B' (digest pivot) — architecture audit (p162)

**Date:** 2026-05-15
**Lenses:** data-architect · platform-guardian · senior-software-engineer
**Result:** 3 changes vs initial G1-G4 proposal + 6 new backlog items

## Top 3 mudanças críticas

### #1 — Schema verdict (data-architect): NÃO usar `meeting_artifacts.champion_decision jsonb`

**Razão técnica:**
- `meeting_artifacts` já tem 2 estruturas pesadas (`page_data_snapshot jsonb` + `deliberations text[]` + `agenda_items text[]`) → 4ª jsonb cria TOAST composto
- Predicate index em jsonb não-seletivo (maioria das rows = NULL = pending)
- Dual-write risk com `champions_awarded`

**Alternativa proposta:** adicionar em `events` (não em meeting_artifacts):
```sql
ALTER TABLE events
  ADD COLUMN event_champion_waived boolean DEFAULT NULL,
  ADD COLUMN event_champion_waived_at timestamptz,
  ADD COLUMN event_champion_waived_by uuid REFERENCES members(id),
  ADD COLUMN event_champion_waived_reason text;

CREATE INDEX idx_events_champion_pending
  ON events(initiative_id, date)
  WHERE event_champion_waived IS NULL AND status = 'scheduled';
```

Mirroring o pattern p160 soft-cancel (`cancelled_at/by/reason`). Tipo boolean explícito sem ambiguidade jsonb. Predicate index seletivo (~95% rows NULL = pending) com baixa cardinalidade já melhora plano.

### #2 — G1 NÃO é load-bearing para G2 (senior-engineer)

**Insight:** o digest "ata pendente" detecta via `meeting_artifacts.is_published=true` ausente. **Não precisa champion_decision/waived para shipar G2.** Heurística pura:
- ata pendente = events.date<now() + sem meeting_artifacts publicado
- presença pendente = events.date<now() + sem rows em attendance
- champion pendente = events.date<now() + sem champions_awarded ativo (heurística pura — aceita falso positivo se líder decidiu verbalmente "nenhum")

G1 (events.event_champion_waived) elimina o falso positivo mas pode ser shipped DEPOIS de G2 funcionar.

### #3 — 2 blockers reais (platform-guardian)

**Blocker A — RLS V3 hardcoded:** `meeting_artifacts_manage` policy usa `operational_role IN (manager, deputy_manager, tribe_leader)` hardcoded (ADR-0011 violation ativo, item #12 do gap log). Qualquer ALTER TABLE em meeting_artifacts herda essa policy errada. **Resolver antes de tocar meeting_artifacts em qualquer track.**

**Blocker B — Digest leader identification V3:** `get_weekly_tribe_digest:47` identifica líder via `tribes.leader_member_id` (V3 cache). Em V4, líder vem de auth_engagements. Digest pode ir para ex-líder ou faltar para líder atual quando mudança passa só pelo V4. **Não bloqueia smoke com 1 líder por tribo, mas é pre-req antes de rollout amplo.**

## Conflitos identificados (com solução)

| # | Conflito | Solução |
|---|---|---|
| C1 | Eventos sem `initiative_id` (gerais) invisíveis em queries V4 | `COALESCE(e.initiative_id = ?) OR (e.type='geral' AND e.initiative_id IS NULL)` |
| C2 | "Presença pendente" semântica errada (present=false ≠ não-registrada) | Definir: `NOT EXISTS attendance row` (zero marcações) vs `present=false` (registrou ausência). Digest só sinaliza o primeiro |
| C3 | Recorrência: série semanal sem ata 4 semanas vira 4 alertas | `GROUP BY events.recurrence_group` na seção de ata pendente: "Reunião de tribo — 4 ocorrências sem ata nos últimos 28 dias" |
| C4 | Cron itera por tribes.id, queries são por initiatives.id | Resolver mapping tribe_id→initiative_id no início do cron, falhar visivelmente se ausente |

## Indexes adicionais necessários (data-arch)

```sql
-- Crítico (G2 query depende):
CREATE INDEX idx_meeting_artifacts_event_id ON meeting_artifacts(event_id);

-- Covering composite (acelera 3 sections):
CREATE INDEX idx_events_type_date_initiative
  ON events(initiative_id, type, date)
  WHERE status = 'scheduled';

-- Opcional (só se G1 shipped):
CREATE INDEX idx_events_champion_pending
  ON events(initiative_id, date)
  WHERE event_champion_waived IS NULL AND status = 'scheduled';
```

## Semantic clarifications (a documentar em SEMANTIC_TAXONOMY.md)

1. **Ata pendente (digest):** `is_published=true` em meeting_artifacts ausente. NÃO usar `minutes_text IS NULL` (definição V3 light depreciando).
2. **Presença pendente (digest):** zero rows em attendance para o event (`NOT EXISTS`). Não é o mesmo que "todos absent" (registro feito).
3. **Champion pendente (digest):** heurística pura sem coluna = `NOT EXISTS champions_awarded WHERE context_kind='event' AND context_id=event_id AND status='active'`. Com coluna `event_champion_waived` (G1 opcional): adicionar `AND event_champion_waived IS NULL`.

## Multi-domain impact (senior-engineer)

| Surface | Impacto | Ação |
|---|---|---|
| `list_meeting_artifacts` RPC | `SELECT *` retorna campo novo | Backward-compat se G1 shipped |
| `list_initiative_meeting_artifacts` | Herda de list_meeting_artifacts | OK |
| `award_champion` RPC | Lê meeting_artifacts via SELECT * | OK (campo extra ignorado) |
| `presentations.astro` frontend | client-side select * em ma | OK (supabase-js ignora) |
| `/admin/gamification` modal | Precisa URLSearchParams reader para deep link | ~20-30 linhas (G3b) |
| `/attendance` page | Precisa URLSearchParams reader | ~20-30 linhas (G3b) |
| MCP tools | 0 breaking — nenhum tool retorna meeting_artifacts row diretamente | Zero ação |
| `database.gen.ts` TypeScript | 3 linhas manuais (não regenerar 1.5MB) | G2 acompanhamento |

## ADR verdict (platform-guardian)

**NÃO criar ADR novo. Estender ADR-0022 como Amendment B (W3 Leader Digest Sections v2).** Razões:
- ADR-0022 já governa digest semanal — Track B' é concretização de W3 pendente
- ADR-0081 é Champion ledger (domínio errado)
- Amendment B cobre: 3 sections (ata/presença/champion) + recurrence grouping + semantic boundaries

## Invariantes propostos (5 novos)

| Nome | Severity | Quando ativar |
|---|---|---|
| I_champion_decision_consistency | HIGH | Após G1 shipped (depende de coluna) |
| I_champion_pending_digest_coverage | WARNING | Após G2 + G1 (threshold 21d para evitar false positive) |
| I_meeting_artifact_event_orphan | WARNING | Pode adicionar imediatamente (defesa anti-drift FK) |
| I_tribe_initiative_bridge_complete | WARNING | Pode adicionar imediatamente (cron drift defense) |
| I_attendance_unregistered_events | WARNING | Após G2 estável (monitoramento) |

## 6 novos backlog items (para P162_GAP_OPPORTUNITY_LOG.md)

16. **RISK** — platform-guardian system prompt diz "8 invariantes" mas DB tem 13 (J/K/L/M/N adicionadas pós-p48). XS.
17. **RISK** — `get_weekly_tribe_digest:47` identifica líder via V3 `tribes.leader_member_id` em vez de V4 engagements. S. **Cross-ref:** parte do Blocker B.
18. **GAP** — `meeting_artifacts` RLS policy V3 hardcoded (ADR-0011 violation, mesmo item #12 do log original — re-flagged como pre-req crítico de Track B'). S.
19. **GAP** — Recurrence grouping ausente no digest. S.
20. **GAP** — `champion_decision` semantic PM decision (staging vs sync). XS (decisão).
21. **OPPORTUNITY** — multiple leaders per initiative (V4 N:N) digest delivery. M.

## Revised phasing (Track B')

| Fase | Escopo | Effort | Blocker pre-req | Status |
|---|---|---|---|---|
| **G0** | Fix RLS V3 de meeting_artifacts (item #12/#18 log) | ~1h | — | NOVO — pre-req crítico |
| **G2a** | Extend `get_weekly_tribe_digest` RPC com 3 sections (top-3 + count, recurrence GROUP BY, hide-if-empty) | ~2.5h | — | Independente de G0/G1 |
| **G2b** | Extend `generate_weekly_leader_digest_cron()` com v_has_signal + tribe_id→initiative_id mapping | ~30min | G2a | NOVO |
| **G3a** | Extend `buildWeeklyTribeDigestLeaderHtml` EF com 3 sections + CTAs (PT-BR inline) | ~2h | G2 | — |
| **G3b** | Deep link URLSearchParams parsers em `/attendance` + `/admin/gamification` | ~1h | G3a | NOVO |
| **G4** | Smoke cron + email render Roberto/Sarah | ~1h | G2/G3 | — |
| **G5** | Contract test `weekly-tribe-digest.test.mjs` (cobertura ata/presença/champion sections) | ~1h | G2 | NOVO |
| **G1** | Migration `events.event_champion_waived` + trio (4 colunas, 1 index partial) — pattern p160 soft-cancel | ~1h | G0 | **DEFERRABLE — não load-bearing para G2** |

**Effort revisto: ~10h** (vs 5.5h original) — cresce por G0 (pre-req) + G2b (cron sync) + G3b (deep links) + G5 (tests). G1 fica opcional, pode shippar depois.

## Cross-references

- ADR-0022 (digest schema W3) — Amendment B target
- ADR-0011 (V4 auth, RLS invariante) — G0 pre-req
- ADR-0081 (Champion ledger) — domain reference, NÃO host
- ADR-0028 (privacy-preserving aggregates) — princípio honrado em G2
- Sediment `feedback_resend_5rps_bulk_throttle.md` (p92) — G3a tech debt note
- Sediment `feedback_supabase_insert_silent_400.md` (p138) — relevante se admin CRUD futuro
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` — 6 novos itens (16-21) a adicionar
