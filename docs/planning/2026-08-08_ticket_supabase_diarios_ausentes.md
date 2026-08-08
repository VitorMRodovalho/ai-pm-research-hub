# Rascunho do ticket para o Supabase — diários ausentes (decisão 3, ratificada 08/08/2026)

> Colar no suporte do Supabase. **Não vai para issue pública**: postura de backup é informação útil
> para quem ataca.
> Re-medir os fatos antes de enviar: `GET /v1/projects/<ref>/database/backups`.

---

**Assunto:** Daily physical backups missing on two dates (project `ldrfrvwhxsmgaabwmaik`, sa-east-1)

**Corpo:**

Hi,

Project ref: `ldrfrvwhxsmgaabwmaik` (region `sa-east-1`, Postgres 17.6.1.084).

Querying `GET /v1/projects/ldrfrvwhxsmgaabwmaik/database/backups` on 2026-08-08 at 02:21 UTC
returned five completed physical backups, with two dates missing from the window:

| date (04:20 UTC) | backup |
|---|---|
| 2026-08-01 | present |
| **2026-08-02** | **missing** |
| 2026-08-03 | present |
| 2026-08-04 | present |
| 2026-08-05 | present |
| 2026-08-06 | present |
| **2026-08-07** | **missing** (the scheduled time had already passed) |

All five listed entries report `status: COMPLETED`, `is_physical_backup: true`.
`pitr_enabled` is `false` and `walg_enabled` is `true`.

Two questions:

1. Why did the daily backup not run (or not complete) on 2026-08-02 and 2026-08-07? The gaps sit in
   the middle of the retention window, so this is not retention pruning, which removes the oldest
   entries first.
2. Is there any notification we can subscribe to when a scheduled daily backup fails or is skipped?
   Right now a missed backup is silent from our side: we only noticed by querying the API directly.

Context on impact: the most recent restore point at the time of the query was 2026-08-06 04:20 UTC,
which is roughly 46 hours old, where we would have expected about 22. A full day of production
changes sat outside any vendor-side restore point without us being aware.

Thanks.

---

## Fatos medidos que sustentam o ticket (08/08/2026)

- `pitr_enabled: false`, `walg_enabled: true`, região `sa-east-1`
- 5 backups completos listados: 01, 03, 04, 05, 06 de agosto
- ausentes: 02 e 07 de agosto
- backup mais novo com 1 dia e 22 horas na hora da consulta
- buraco no meio da janela **não** é poda de retenção: a poda remove o mais velho, e o 01/08 estava
  presente enquanto o 02/08 não
