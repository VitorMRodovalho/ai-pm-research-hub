# ADR-0065: Drive Phase 4 — auto-discovery atas via cron + filename heuristic

**Status:** Accepted (2026-04-28)
**Decision date:** p78 marathon
**Related:** Issue #111 (Phase 4 placeholder), ADR-0064 (Phase 3 OAuth refresh), Pattern 43 (silent-cron-detection)

---

## Context

Drive Phase 3 (ADR-0064) entregou write capability via OAuth refresh flow.
Cards e iniciativas podem agora subir atas via MCP `upload_text_to_drive_folder`.

Mas há uma rota paralela que não passa pela plataforma: usuários (incluindo
PM, líderes de tribo) editam atas direto no Drive nativo (Google Docs / .md /
PDF) sem usar a plataforma para upload. Sem auto-discovery, esses arquivos
ficam invisíveis no contexto operacional do Núcleo:
- Eventos com `minutes_url IS NULL` permanecem assim mesmo quando há ata
  publicada em pasta linkada
- Quem busca "ata da T8 da reunião de 28/05" não acha via plataforma
- Phase A do close-meeting workflow (`meeting_close` RPC) não detecta atas
  externas → counters de drift signal artificialmente altos

## Decision

**Cron diário discovery + filename date heuristic + auto-promote em event vazio.**

### Schema

`drive_file_discoveries` — idempotency cache + audit:
- `drive_file_id text UNIQUE` — prevents reprocessing
- `initiative_drive_link_id` — folder source
- `matched_event_id`, `match_strategy ('unmatched'|'filename_date'|'manual')`,
  `match_confidence ('none'|'low'|'medium'|'high')`
- `promoted_to_minutes_url`, `promoted_at`, `promoted_by` (NULL when auto)
- RLS: `rls_is_member()` read-only para authenticated

### Heuristic: filename date extraction

`_extract_date_from_filename(filename)` regex em 3 patterns:
1. `YYYY-MM-DD` / `YYYY_MM_DD` / `YYYY/MM/DD` (ISO ordering)
2. `DD-MM-YYYY` / `DD/MM/YYYY` (Brazilian convention)
3. `YYYYMMDD` compact (anchored to `20\d{2}` to avoid matching arbitrary numbers)

Returns NULL se nenhum pattern bate. SECDEF + IMMUTABLE.

### Match window

Filename date → buscar `events.date BETWEEN filename_date - 7d AND filename_date + 7d`
da mesma `initiative_id`. Pega o evento mais próximo (`ORDER BY ABS(date - filename_date)`).

### Confidence levels

- `high`: filename_date == event.date (exact)
- `medium`: |filename_date - event.date| <= 1 day
- `low`: 2-7 days off (still within window)

### Auto-promote rule

Apenas se `event.minutes_url IS NULL`. Se já tinha valor, marca discovery
como `matched` mas `promoted_to_minutes_url=false` para review manual
(evita sobrescrever ata já curated).

### Cron schedule

`drive-discover-atas-daily` — `0 3 * * *` (03:00 UTC = 00:00 BRT). Quiet
slot entre LGPD crons (03:30/03:45/04:00) e início business hours.

### Authority

- `record_drive_discovery`: `service_role` (cron) OR `view_internal_analytics`
  (manual replay/test)
- `get_drive_discovery_health`: `view_internal_analytics`
- `list_drive_discoveries`: `view_internal_analytics`

### Pattern 43 4th reuse

`get_drive_discovery_health` segue mesma estrutura de `get_invitation_health`
(W7) + `get_lgpd_cron_health` (W8) + `get_digest_health` (W9):
- Counters: total / last_24h / unmatched / unpromoted
- Cron snapshot: jobid + last_run_at + last_status + last_5_status + failed_runs_30d
- Health signal: green (<=36h success), yellow (idle/no folders), red (>36h or failed)

## Implementation refs

- Migration: `20260514660000_drive_phase_4_discoveries_table_and_record_rpc.sql`
  + `_health_and_list_rpcs.sql` + `_cron_schedule.sql`
- EF: `supabase/functions/drive-discover-atas/index.ts`
- MCP tools: `get_drive_discovery_health` + `list_drive_discoveries`
  (v2.52.0 → v2.53.0, 234 → 236 tools)

## Consequences

### Positive

- Atas externas ficam automaticamente surfaceadas em events.minutes_url
- 0 friction: time não precisa rodar nada manualmente
- Idempotente: re-runs do cron não duplicam (UNIQUE drive_file_id)
- Confidence levels permitem review manual de matches duvidosos via
  `list_drive_discoveries(status_filter='unpromoted')`
- Health observability via Pattern 43 (4th reuse — pattern saturation reached)

### Negative / risks

- **Heuristic miss**: filename sem data legível (e.g. "ata-final.md") fica
  unmatched. Mitigação: convenção de nomenclatura recomendada nas docs
  (`ata-YYYY-MM-DD-titulo.md`)
- **False positive**: filename com data próxima de evento de outra
  iniciativa não pega (filtra por `initiative_id`). Risco maior: 2 events
  da mesma iniciativa em ±7d do mesmo arquivo → pega o mais próximo,
  pode errar se reuniões frequentes
- **Quota**: `drive-discover-atas` faz 1 list call por minute folder. Com
  12 iniciativas + crescimento, ~15-20 list calls/dia. Sob limite Drive
  API (10k req/100s/project)
- **PM action precondition**: até PM criar `/Atas` subfolders + linkar com
  `link_purpose='minutes'`, cron escaneia 0 folders → health=yellow

### Reopening criteria

- Heuristic fails > 30% dos atas reais → adicionar pattern 4 (e.g. "Reunião X dd/mm" Brasileiro free-text)
- False positive rate > 5% → tighten window from ±7d para ±3d
- Cron timing conflicts com outros crons (load) → mover de 03:00 UTC

## Validation evidence (smoke 2026-04-28)

End-to-end test via service_role:
- Discovery insert: `is_new: true` (UUID returned)
- Date extraction: `ata-2026-05-28-reuniao-T8.md` → `2026-05-28` ✅
- Match: T8 event `01d496f8-c255-4560-850e-ead5104ee536` (date=2026-05-28) ✅
- Confidence: `high` (exact date) ✅
- Auto-promote: event.minutes_url filled ✅
- Idempotency: 2nd call → `is_new: false`, same discovery_id ✅
- Rollback successful (event reverted, discovery deleted)

EF smoke test (no minutes folders yet): `folders_scanned: 0, files_seen: 0,
errors: []` HTTP 200 — clean idle state.

Cron registered: `drive-discover-atas-daily` schedule `0 3 * * *` active=true.

## Provenance

- Phase 4 design: p78 autonomous marathon
- PM authorization sequence: A (Phase 4) → B (autonomous backlog) → C (Mayanna UI #113)
- Pattern 43 saturation: 4th reuse — observability template estabilizado
