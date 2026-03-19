-- Event Governance: Add nature column (3rd dimension)
-- type = audience (geral/tribo/lideranca), nature = lifecycle (kickoff/recorrente/avulsa)

ALTER TABLE events ADD COLUMN IF NOT EXISTS nature text DEFAULT 'avulsa';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'events_nature_check') THEN
    ALTER TABLE events ADD CONSTRAINT events_nature_check
      CHECK (nature IN ('kickoff', 'recorrente', 'avulsa', 'encerramento', 'workshop', 'entrevista_selecao'));
  END IF;
END $$;

-- Backfill existing events
UPDATE events SET nature = 'kickoff' WHERE title ILIKE '%kick%off%' OR title ILIKE '%kick-off%';
UPDATE events SET nature = 'recorrente' WHERE (title ILIKE '%semanal%' OR title ILIKE '%recorrente%' OR title ILIKE '%reunião%') AND nature = 'avulsa';
UPDATE events SET nature = 'entrevista_selecao' WHERE type = 'entrevista';

SELECT pg_notify('pgrst', 'reload schema');
