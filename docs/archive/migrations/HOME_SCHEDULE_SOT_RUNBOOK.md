# HOME_SCHEDULE_SOT_RUNBOOK.md

Runbook de fechamento da trilha **S-HOME-SCHEDULE-SOT** (Issue #3), consolidando origem de verdade da agenda/prazos da home em `public.home_schedule`.

## Objetivo

Garantir que as superfícies públicas da home (hero, agenda, tribos e recursos) leiam agenda e prazo operacional de uma fonte única em banco, sem hardcodes de data operacional.

## Artefatos técnicos envolvidos

- Migrations base:
  - `supabase/migrations/20260309010000_select_tribe_deadline_check.sql`
  - `supabase/migrations/20260309060000_fix_deadline_and_remove_kpi_override.sql`
  - `supabase/migrations/20260309070000_admin_global_access_and_timelock_bypass.sql`
- Runtime:
  - `src/lib/schedule.ts`
  - `src/pages/index.astro`
  - `src/pages/en/index.astro`
  - `src/pages/es/index.astro`
  - `src/components/sections/HeroSection.astro`
  - `src/components/sections/AgendaSection.astro`
  - `src/components/sections/TribesSection.astro`

## Auditoria operacional (checklist)

1. Confirmar linha única em `public.home_schedule` para o ciclo ativo.
2. Confirmar que `selection_deadline_at` está preenchido com ISO válido.
3. Confirmar que a home carrega sem fallback hardcoded de data (PT/EN/ES).
4. Rodar validação:
   - `npm run smoke:routes`
   - `npm run test:browser:guards`
   - `npm run build`

## SQL de verificação

```sql
select
  kickoff_at,
  platform_label,
  recurring_start_brt,
  recurring_end_brt,
  recurring_weekday,
  selection_deadline_at
from public.home_schedule
limit 1;
```

## SQL de atualização (quando necessário)

```sql
update public.home_schedule
set
  kickoff_at = '2026-03-05T22:30:00Z',
  platform_label = 'Google Meet',
  recurring_start_brt = '19:30',
  recurring_end_brt = '20:30',
  recurring_weekday = 4,
  selection_deadline_at = '2026-03-16T15:00:00Z'
where true;
```

## Rollback operacional

Se houver regressão de comunicação de agenda na home:

1. Restaurar `selection_deadline_at` para o último valor válido conhecido.
2. Reexecutar `npm run smoke:routes` e `npm run test:browser:guards`.
3. Abrir hotfix com referência à issue incidente.

> Não usar hardcode no frontend como rollback rápido. O rollback oficial é de dado/configuração em `home_schedule`.

