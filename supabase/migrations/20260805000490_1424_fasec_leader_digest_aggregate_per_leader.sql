-- #1424 Fase C (item 1) — digest de lider: 1 payload agregado por LIDER
--
-- Contexto medido (2026-07-25, consultas ao vivo):
--   - sabado 18/07 (ultimo sem as Fases A+B): 108 envios no dia = 71 member digest
--     (1,00/pessoa) + 37 linhas de leader digest para 20 lideres (1,85/lider).
--   - hoje: 20 lideres, 40 pares (lider x iniciativa), 9 lideres multi-iniciativa,
--     maximo 8 iniciativas para um mesmo lider.
--
-- Problema que esta migration corrige (NAO e cota, e perda de conteudo):
--   A Fase A (send-notification-email, viva desde 21/07) dedupa digests ricos
--   mantendo apenas a linha MAIS RECENTE por (tipo, destinatario) e marcando as
--   demais como enviadas. Como o cron inseria 1 linha por (iniciativa, lider), o
--   lider de 8 iniciativas passou a receber 1 resumo e a PERDER os outros 7 em
--   silencio. O corte 40 -> 20 e-mails ja acontecia; acontecia por descarte.
--
-- Correcao: agregar no PRODUTOR. O cron passa a inserir 1 notificacao por lider,
-- com o payload de TODAS as iniciativas dele. Mesmo numero de e-mails (1/lider),
-- zero resumo perdido.
--
-- Forma do payload (v2, lido por buildWeeklyTribeDigestLeaderHtml):
--   { version: 2, leader_id, initiative_count, generated_at,
--     initiatives: [ <payload de get_weekly_initiative_digest>, ... ] }
--   O renderer mantem o caminho v1 (payload de uma iniciativa no topo) para as
--   linhas enfileiradas antes desta migration.
--
-- Assinatura de retorno INALTERADA de proposito: permite CREATE OR REPLACE (que
-- preserva a ACL) em vez de DROP + CREATE, que resetaria os grants e faria a
-- funcao voltar a ser PUBLIC-reachable, quebrando o gate #965. O retorno segue
-- granular por (iniciativa, lider) para observabilidade; so o INSERT agregou.

CREATE OR REPLACE FUNCTION public.generate_weekly_leader_digest_cron()
 RETURNS TABLE(initiative_id uuid, initiative_name text, leader_id uuid, notified boolean, reason text, batch_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_batch_id uuid := gen_random_uuid();
BEGIN
  RETURN QUERY
  WITH inits AS MATERIALIZED (
    SELECT i.initiative_id, i.name
    FROM public._v4_active_initiatives_with_leaders() i
  ),
  -- MATERIALIZED e obrigatorio: sem ele o planner pode reavaliar
  -- get_weekly_initiative_digest uma vez por PAR (40x) em vez de uma vez por
  -- iniciativa (~26x). O digest e caro (varias agregacoes por iniciativa).
  digests AS MATERIALIZED (
    SELECT i.initiative_id, i.name,
           public.get_weekly_initiative_digest(i.initiative_id) AS digest
    FROM inits i
  ),
  scored AS (
    SELECT d.initiative_id, d.name, d.digest,
           ( (d.digest->'aggregates'->>'cards_overdue_total')::int > 0
          OR (d.digest->'aggregates'->>'cards_due_next_7d')::int > 0
          OR (d.digest->'aggregates'->>'cards_without_assignee')::int > 0
          OR (d.digest->'aggregates'->>'cards_without_due_date')::int > 0
          OR (d.digest->'aggregates'->>'cards_completed_window')::int > 0
          OR (d.digest->'aggregates'->'ata_pending'->>'count_events')::int > 0
          OR (d.digest->'aggregates'->'attendance_pending'->>'count')::int > 0
          OR (d.digest->'aggregates'->'champion_pending'->>'count')::int > 0
           ) AS has_signal
    FROM digests d
  ),
  -- LEFT JOIN LATERAL preserva o caso "iniciativa ativa sem engagement de lider
  -- ativo": leader_id NULL vira uma linha de relatorio, como antes.
  pairs AS (
    SELECT s.initiative_id, s.name, s.digest, s.has_signal,
           l.lid AS leader_id,
           m.notify_delivery_mode_pref AS leader_pref
    FROM scored s
    LEFT JOIN LATERAL public._v4_leader_member_ids_by_initiative(s.initiative_id) l(lid) ON true
    LEFT JOIN public.members m ON m.id = l.lid
  ),
  classified AS (
    SELECT p.*,
           CASE
             WHEN p.leader_id IS NULL            THEN 'no_active_v4_leader_engagement'
             WHEN p.leader_pref = 'suppress_all' THEN 'leader_suppressed_all'
             WHEN NOT p.has_signal               THEN 'no_signal_skip'
             ELSE 'sent'
           END AS reason
    FROM pairs p
  ),
  to_send AS (
    SELECT c.leader_id,
           jsonb_agg(c.digest ORDER BY c.name) AS initiatives,
           count(*)::int AS n,
           min(c.name) AS first_name
    FROM classified c
    WHERE c.reason = 'sent'
    GROUP BY c.leader_id
  ),
  -- Data-modifying CTE: executa exatamente uma vez e por completo, sendo ou nao
  -- referenciada pela query principal (doc do Postgres, WITH).
  ins AS (
    INSERT INTO public.notifications (
      recipient_id, type, title, body, link, source_type, source_id,
      is_read, delivery_mode, digest_batch_id
    )
    SELECT
      t.leader_id,
      'weekly_tribe_digest_leader', -- type unchanged for email handler back-compat
      CASE WHEN t.n = 1
           THEN 'Resumo semanal: ' || t.first_name
           ELSE 'Resumo semanal: ' || t.n || ' iniciativas'
      END,
      jsonb_build_object(
        'version', 2,
        'leader_id', t.leader_id,
        'initiative_count', t.n,
        'generated_at', now(),
        'initiatives', t.initiatives
      )::text,
      '/admin/portfolio',
      'leader_digest',
      v_batch_id,
      false,
      'transactional_immediate',
      v_batch_id
    FROM to_send t
    RETURNING recipient_id
  )
  SELECT c.initiative_id,
         c.name,
         c.leader_id,
         (c.reason = 'sent'),
         c.reason,
         CASE WHEN c.reason = 'sent' THEN v_batch_id ELSE NULL END
  FROM classified c
  ORDER BY c.name, c.leader_id;
END;
$function$;

COMMENT ON FUNCTION public.generate_weekly_leader_digest_cron() IS
  '#1424 Fase C: insere 1 notificacao weekly_tribe_digest_leader por LIDER, com payload v2 agregando todas as iniciativas dele (initiatives: []). Antes inseria 1 linha por (iniciativa, lider), e a dedup da Fase A no send-notification-email descartava as demais — o lider multi-iniciativa perdia resumos. Retorno segue granular por par para observabilidade. Chamada por pg_cron jobid 27 (sab 12:30 UTC).';
