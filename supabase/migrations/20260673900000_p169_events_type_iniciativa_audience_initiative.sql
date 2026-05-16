-- p169 — Add 'iniciativa' event type + 'initiative' audience_level + backfill CPMAI Kickoff
-- PM ask 2026-05-16: events modal só tinha 'Tribo' como audience type. Iniciativas (study_group,
-- workgroup, committee, congress) precisam visibilidade própria. CPMAI Kickoff estava como 'geral'
-- mas event.initiative_id já apontava pra "Preparatório CPMAI — Ciclo 3" — só faltava type semântico.
-- Rollback: revert constraints + UPDATE events SET type='geral' WHERE id='a4b1bbe5-8224-40c8-8da9-662b43a1d7c6';

-- Step 1: expand events_type_check pra incluir 'iniciativa'
ALTER TABLE public.events DROP CONSTRAINT events_type_check;
ALTER TABLE public.events
  ADD CONSTRAINT events_type_check
  CHECK (type IN ('geral','tribo','iniciativa','lideranca','kickoff','comms','parceria','entrevista','1on1','evento_externo','webinar'));

-- Step 2: expand events_audience_level_check pra incluir 'initiative'
ALTER TABLE public.events DROP CONSTRAINT events_audience_level_check;
ALTER TABLE public.events
  ADD CONSTRAINT events_audience_level_check
  CHECK (audience_level IN ('all','leadership','tribe','initiative','curators'));

-- Step 3: backfill CPMAI Kickoff event
UPDATE public.events
SET type = 'iniciativa'
WHERE id = 'a4b1bbe5-8224-40c8-8da9-662b43a1d7c6'
  AND type = 'geral'
  AND initiative_id IS NOT NULL;
