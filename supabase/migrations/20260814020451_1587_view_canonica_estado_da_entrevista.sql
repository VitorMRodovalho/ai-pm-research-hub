-- =============================================================================
-- #1587 -- selection_interviews tem multiplas linhas por candidatura:
--          ler "a mais recente por data" devolve o estado errado.
--
-- Medicoes desta migration (todas re-consultadas em 14/08/2026, nenhuma recitada):
--
--   * 14 candidaturas tem mais de uma linha em selection_interviews (34 linhas).
--   * 5 delas dao resposta ERRADA quando lidas como
--     DISTINCT ON (application_id) ... ORDER BY scheduled_at DESC:
--       4 cuja ultima linha por data e 'cancelled' (supersede) e 1 'scheduled',
--       todas com a entrevista efetivamente realizada em OUTRA linha.
--   * Varredura das 29 funcoes vivas que tocam selection_interviews: apenas
--     selection_rescue_stuck_interview ordena por data pura, e ela ja filtra
--     status='scheduled' AND conducted_at IS NULL, portanto NAO cai no vies.
--     Medido: 0 candidaturas exploraveis hoje. A contencao vem do dado
--     (app.status), nao da estrutura -- por isso a view abaixo existe.
--   * O cache selection_applications.interview_status NUNCA assume 'completed':
--     dominio vivo = none(131) / scheduled(37) / needs_reschedule(1) / rescheduled(1).
--     106 das 170 candidaturas exibem estado divergente do derivado.
--
-- `needs_reschedule` NAO e derivavel das linhas de entrevista: e um estado de
-- INTENCAO, escrito por request_interview_reschedule / process_pending_reschedule_nudges,
-- e a fila de convite do admin depende dele. A view por isso o preserva a partir
-- do cache, em vez de sobrescreve-lo pelo estado das linhas.
-- =============================================================================

DROP VIEW IF EXISTS public.v_application_interview_state;

CREATE VIEW public.v_application_interview_state
WITH (security_invoker = true) AS
WITH per_app AS (
  SELECT
    si.application_id,
    count(*)                                                              AS interview_rows,
    bool_or(si.status = 'completed' OR si.conducted_at IS NOT NULL)       AS ja_realizada,
    max(si.conducted_at)                                                  AS last_conducted_at,
    count(*) FILTER (WHERE si.status = 'completed'
                        OR si.conducted_at IS NOT NULL)                   AS conducted_rows,
    count(DISTINCT si.conducted_at)
      FILTER (WHERE si.conducted_at IS NOT NULL)                          AS distinct_conducted_instants,
    count(*) FILTER (WHERE si.status = 'cancelled')                       AS cancelled_rows,
    count(*) FILTER (WHERE si.status = 'noshow')                          AS noshow_rows,
    count(*) FILTER (WHERE si.status IN ('scheduled', 'rescheduled')
                       AND si.conducted_at IS NULL)                       AS open_rows,
    min(si.scheduled_at) FILTER (WHERE si.status IN ('scheduled', 'rescheduled')
                                   AND si.conducted_at IS NULL
                                   AND si.scheduled_at >= now())          AS next_scheduled_at,
    bool_or(si.status IN ('scheduled', 'rescheduled')
              AND si.conducted_at IS NULL
              AND si.scheduled_at IS NOT NULL
              AND si.scheduled_at < now())                                AS has_stuck_row
  FROM public.selection_interviews si
  GROUP BY si.application_id
),
canonical AS (
  -- A linha que REPRESENTA o estado da candidatura. A precedencia e por SIGNIFICADO,
  -- nunca por acidente de data: uma entrevista realizada vence uma supersedida que
  -- por acaso tem scheduled_at maior. Dentro do bucket "aberta e futura" queremos a
  -- MAIS PROXIMA (ASC); nos demais, a mais recente (DESC) -- dai o sinal invertido no
  -- epoch, que deixa as duas direcoes num unico ORDER BY.
  SELECT DISTINCT ON (si.application_id)
    si.application_id,
    si.id              AS canonical_interview_id,
    si.status          AS canonical_row_status,
    si.scheduled_at    AS canonical_scheduled_at,
    si.conducted_at    AS canonical_conducted_at,
    si.interviewer_ids AS canonical_interviewer_ids
  FROM public.selection_interviews si
  ORDER BY
    si.application_id,
    CASE
      WHEN si.status = 'completed' OR si.conducted_at IS NOT NULL              THEN 1
      WHEN si.status IN ('scheduled', 'rescheduled')
             AND si.conducted_at IS NULL AND si.scheduled_at >= now()          THEN 2
      WHEN si.status IN ('scheduled', 'rescheduled')
             AND si.conducted_at IS NULL                                       THEN 3
      WHEN si.status = 'noshow'                                                THEN 4
      ELSE 5
    END,
    si.conducted_at DESC NULLS LAST,
    CASE
      WHEN si.status IN ('scheduled', 'rescheduled')
             AND si.conducted_at IS NULL AND si.scheduled_at >= now()
        THEN  extract(epoch FROM si.scheduled_at)
      ELSE   -extract(epoch FROM si.scheduled_at)
    END ASC
)
SELECT
  a.id                                        AS application_id,
  a.cycle_id,
  COALESCE(p.interview_rows, 0)               AS interview_rows,
  COALESCE(p.ja_realizada, false)             AS ja_realizada,
  p.last_conducted_at,
  p.next_scheduled_at,
  COALESCE(p.has_stuck_row, false)            AS has_stuck_row,
  c.canonical_interview_id,
  c.canonical_row_status,
  c.canonical_scheduled_at,
  c.canonical_conducted_at,
  c.canonical_interviewer_ids,

  -- O estado canonico. `needs_reschedule` vem do cache de proposito (ver cabecalho).
  CASE
    WHEN a.interview_status = 'needs_reschedule'  THEN 'needs_reschedule'
    WHEN p.application_id IS NULL                 THEN 'none'
    WHEN p.ja_realizada                           THEN 'completed'
    WHEN p.next_scheduled_at IS NOT NULL          THEN 'scheduled'
    WHEN p.has_stuck_row                          THEN 'stuck'
    WHEN p.noshow_rows > 0                        THEN 'noshow'
    WHEN p.cancelled_rows > 0                     THEN 'cancelled'
    ELSE 'none'
  END                                         AS interview_state,

  -- Por que a candidatura tem mais de uma linha. Distinguir supersede de dual_track
  -- de duplicata era requisito explicito da issue: em 03/08 uma candidatura dual_track
  -- (duas trilhas, mesmo conducted_at, mesma nota) foi confundida com duplicata.
  CASE
    WHEN COALESCE(p.interview_rows, 0) = 0                          THEN 'none'
    WHEN p.interview_rows = 1                                       THEN 'single'
    WHEN p.conducted_rows >= 2 AND p.distinct_conducted_instants = 1 THEN 'dual_track'
    WHEN p.conducted_rows >= 2                                      THEN 'duplicate_suspect'
    WHEN p.conducted_rows = 1 AND p.cancelled_rows >= 1             THEN 'supersede'
    ELSE 'multi_open'
  END                                         AS multiplicity_class,

  a.interview_status                          AS cache_interview_status,
  (a.interview_status IS DISTINCT FROM (
     CASE
       WHEN a.interview_status = 'needs_reschedule' THEN 'needs_reschedule'
       WHEN p.application_id IS NULL                THEN 'none'
       WHEN p.ja_realizada                          THEN 'completed'
       WHEN p.next_scheduled_at IS NOT NULL         THEN 'scheduled'
       WHEN p.has_stuck_row                         THEN 'stuck'
       WHEN p.noshow_rows > 0                       THEN 'noshow'
       WHEN p.cancelled_rows > 0                    THEN 'cancelled'
       ELSE 'none'
     END))                                    AS cache_is_stale
FROM public.selection_applications a
LEFT JOIN per_app   p ON p.application_id = a.id
LEFT JOIN canonical c ON c.application_id = a.id;

COMMENT ON VIEW public.v_application_interview_state IS
  '#1587 -- estado canonico da entrevista por candidatura. Fonte unica para "ja realizada": '
  'bool_or(status=completed OR conducted_at IS NOT NULL), nunca a ultima linha por data, que '
  'pode ser uma supersedida pelo trigger trg_supersede_prior_open_interviews. '
  'security_invoker=true: a RLS de selection_interviews e selection_applications continua '
  'valendo para quem consulta (a view NAO e uma porta de contorno). '
  'cache_is_stale existe para o ratchet medir a divergencia do cache encolher.';

-- A view herda a RLS das tabelas-base via security_invoker, mas o alcance de leitura
-- ainda e concedido explicitamente: PII de candidatura nunca para anon (LGPD/GC-162).
REVOKE ALL ON public.v_application_interview_state FROM PUBLIC, anon;
GRANT SELECT ON public.v_application_interview_state TO authenticated, service_role;
