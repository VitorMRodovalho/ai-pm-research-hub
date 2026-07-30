-- #1536 — colapsar duas duplicatas CROSS-SÉRIE que a varredura por (título, data) do #1528 não podia ver.
--
-- Classe: dois eventos com TÍTULOS DIFERENTES, mesmo dia, mesmo horário, mesma iniciativa, com as MESMAS
-- pessoas marcadas presentes. Presença sobreposta no mesmo slot é contradição física (ninguém está em duas
-- reuniões às 19:00), então cada pessoa pontuou duas vezes por uma noite só.
--
-- Grupo A — 2026-03-18 19:00, iniciativa ROI & Portfólio, TRÊS títulos, todos do MESMO recurrence_group
--   bb5a48fe-…, criados em 7 minutos (03:58 / 04:02 / 04:05 de 19/03) por Fabricio Costa e pelo import.
--   Keeper = 63a2991f (o mais antigo, com 7 presentes E a única ata do grupo).
--   Removidos: b63bcc1d ("[Tribo 6] Reuniao Semana 1 - Ciclo 3", 6 presentes) e
--              b0011160 ("ROI & Portfólio — Reunião Semanal", 6 presentes).
--
-- Grupo B — 2026-07-20 19:00, iniciativa Radar Tecnológico, DOIS títulos, séries diferentes
--   (ca527888 e a1772307 — as duas séries nascidas do duplo-submit de 6 segundos corrigido no #1535).
--   Keeper = 797d3e94 ("Acompanhamento Semanal - Radar Tecnológico", título correto da tribo).
--   Removido: 89a0f881 ("Reunião Geral — Núcleo IA & GP | Semana 3" — o título institucional errado
--             que o #1535 corrigiu na origem), 7 presentes, conjunto IDÊNTICO ao do keeper.
--
-- MÉRITO PRESERVADO POR CONSTRUÇÃO, verificado antes de escrever esta migration: os presentes de cada
-- removido são SUBCONJUNTO do keeper (`only_on_dup = 0` nos dois grupos), logo apagar o lado duplicado não
-- pode tirar presença de ninguém. Por isso não há passo de migração de presença aqui — ele seria no-op.
--
-- NÃO colapsa o par de 2026-03-19 ("Reunião de Liderança (pré-Geral)" × "Reunião Geral — Semana 2"): ali a
-- sobreposição de 8 pessoas é LEGÍTIMA. Tipos diferentes (lideranca/geral), audiências diferentes
-- (leadership/all), durações diferentes (30/60 min) e o próprio título diz "pré-Geral" — eram dois
-- encontros reais na mesma noite. O defeito lá é só o time_start do registro retroativo. Decisão do PM.

-- ── Registro de recuperação, no próprio banco ────────────────────────────────────────────────────────
-- Preferido a um arquivo JSON solto: fica versionado, sobrevive à sessão e não sai do banco (as linhas
-- carregam member_id). Genérica de propósito, para o próximo colapso reusar em vez de criar outra tabela.
CREATE TABLE IF NOT EXISTS public.audit_event_collapse_backup (
  id                bigserial PRIMARY KEY,
  issue_ref         text        NOT NULL,
  collapsed_at      timestamptz NOT NULL DEFAULT now(),
  keeper_event_id   uuid        NOT NULL,
  removed_event_id  uuid        NOT NULL,
  reason            text        NOT NULL,
  payload           jsonb       NOT NULL
);

COMMENT ON TABLE public.audit_event_collapse_backup IS
  'Linhas removidas por colapso de evento duplicado (evento + presenças + pontos, em jsonb), para permitir '
  'reversão. Contém member_id: service-role apenas, sem policy para anon/authenticated (LGPD GC-162).';

-- LGPD GC-162: RLS ligada e nenhuma policy = fail-closed para anon e authenticated; só service_role
-- (que bypassa RLS) alcança. A tabela guarda member_id, então não pode vazar por PostgREST.
ALTER TABLE public.audit_event_collapse_backup ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.audit_event_collapse_backup FROM anon, authenticated;
GRANT ALL ON TABLE public.audit_event_collapse_backup TO service_role;
REVOKE ALL ON SEQUENCE public.audit_event_collapse_backup_id_seq FROM anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.audit_event_collapse_backup_id_seq TO service_role;

-- ── Backup antes de apagar ──────────────────────────────────────────────────────────────────────────
WITH pares(keeper, removido, motivo) AS (
  VALUES
    ('63a2991f-6d1a-457a-9729-2ea0410bdee9'::uuid, 'b63bcc1d-38dc-43d4-8ba4-05eced9a73a8'::uuid,
     'A 2026-03-18: mesma reuniao sob 3 titulos, mesmo recurrence_group bb5a48fe, presentes subconjunto do keeper'),
    ('63a2991f-6d1a-457a-9729-2ea0410bdee9'::uuid, 'b0011160-571a-4174-9ec3-39c63d1c757e'::uuid,
     'A 2026-03-18: mesma reuniao sob 3 titulos, mesmo recurrence_group bb5a48fe, presentes subconjunto do keeper'),
    ('797d3e94-8245-4e15-829d-6cae777c41f4'::uuid, '89a0f881-63a8-4071-97fe-ea0be6199f43'::uuid,
     'B 2026-07-20: duplo-submit gerou 2 series (ca527888/a1772307); conjuntos de presentes IDENTICOS')
)
INSERT INTO public.audit_event_collapse_backup (issue_ref, keeper_event_id, removed_event_id, reason, payload)
SELECT '#1536', p.keeper, p.removido, p.motivo,
       jsonb_build_object(
         'event',      (SELECT to_jsonb(e) FROM public.events e WHERE e.id = p.removido),
         'attendance', coalesce((SELECT jsonb_agg(to_jsonb(a)) FROM public.attendance a WHERE a.event_id = p.removido), '[]'::jsonb),
         'points',     coalesce((SELECT jsonb_agg(to_jsonb(gp)) FROM public.gamification_points gp
                                  WHERE gp.ref_id = p.removido
                                     OR gp.ref_id IN (SELECT a.id FROM public.attendance a WHERE a.event_id = p.removido)), '[]'::jsonb)
       )
FROM pares p
WHERE EXISTS (SELECT 1 FROM public.events e WHERE e.id = p.removido);

-- ── Colapso: pontos → presenças → evento (ordem que respeita as FKs) ────────────────────────────────
-- ref_id de ponto de presença é POLIMÓRFICO (aponta ora para attendance.id, ora para events.id — #1537
-- item 3), por isso os dois lados são cobertos. Cobrir um só devolve zero e parece "nada a fazer".
WITH removidos(id) AS (VALUES
  ('b63bcc1d-38dc-43d4-8ba4-05eced9a73a8'::uuid),
  ('b0011160-571a-4174-9ec3-39c63d1c757e'::uuid),
  ('89a0f881-63a8-4071-97fe-ea0be6199f43'::uuid))
DELETE FROM public.gamification_points gp
WHERE gp.ref_id IN (SELECT id FROM removidos)
   OR gp.ref_id IN (SELECT a.id FROM public.attendance a WHERE a.event_id IN (SELECT id FROM removidos));

DELETE FROM public.attendance a
WHERE a.event_id IN (
  'b63bcc1d-38dc-43d4-8ba4-05eced9a73a8'::uuid,
  'b0011160-571a-4174-9ec3-39c63d1c757e'::uuid,
  '89a0f881-63a8-4071-97fe-ea0be6199f43'::uuid);

DELETE FROM public.events e
WHERE e.id IN (
  'b63bcc1d-38dc-43d4-8ba4-05eced9a73a8'::uuid,
  'b0011160-571a-4174-9ec3-39c63d1c757e'::uuid,
  '89a0f881-63a8-4071-97fe-ea0be6199f43'::uuid);
