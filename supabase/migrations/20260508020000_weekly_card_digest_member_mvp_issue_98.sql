-- Migration: Weekly Card Digest — MVP V1 from issue #98
-- 2026-05-08 p39
-- Context: Leaders cobram via WhatsApp individual; member sem sinal automatizado de
-- cards pendentes / próximos. Fabrício + outros leaders pediram digest automatizado.
-- Escopo MVP V1: card digest individual member (sábado 09h BRT = 12h UTC).
-- V2 leader digest + V3 timezone config ficam backlog.
--
-- Out of scope (ADR-0022 expansion 7-sections): não implementa comunicação unificada.
-- PM pediu explicitamente "card-only MVP". ADR-0022 em disco aguarda sessão paralela.
--
-- Two-phase email delivery:
--   1. pg_cron 'weekly-card-digest-saturday' (sábado 12 UTC) chama
--      generate_weekly_card_digest_cron() que INSERTS rows em public.notifications
--      com type='weekly_card_digest_member' e email_sent_at=NULL.
--   2. cron existente 'send-notification-emails' (a cada 5min) detecta rows
--      pendentes e envia via EF send-notification-email + Resend API.
--   Padrão idêntico ao de IP ratification e governance notifications.
--
-- Rollback:
--   SELECT cron.unschedule('weekly-card-digest-saturday');
--   DROP FUNCTION IF EXISTS public.generate_weekly_card_digest_cron() CASCADE;
--   DROP FUNCTION IF EXISTS public.get_weekly_card_digest(uuid) CASCADE;
--   ALTER TABLE public.members DROP COLUMN IF EXISTS notify_weekly_digest;
--   -- Also remove 'weekly_card_digest_member' from STORAGE_ONLY_ALLOWLIST in
--   -- tests/contracts/schema-cache-columns.test.mjs and from CRITICAL_TYPES in
--   -- supabase/functions/send-notification-email/index.ts (requires redeploy).

BEGIN;

-- =========================================================================
-- 1. Opt-out column em members (default true)
-- =========================================================================
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS notify_weekly_digest boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.members.notify_weekly_digest IS
  'Issue #98: opt-in/out do weekly card digest (sábado 09:00 BRT). Default true — member escolhe opt-out via /settings.';

-- =========================================================================
-- 2. get_weekly_card_digest — read RPC retornando payload jsonb
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_weekly_card_digest(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
  v_is_self boolean;
BEGIN
  -- ADR-0011 gate: member vê próprio digest SEMPRE; admin pode ver outros via manage_member
  SELECT id INTO v_caller_id FROM members WHERE auth_id = auth.uid();
  v_is_self := (v_caller_id = p_member_id);

  -- Anon + non-admin cross-member read denied
  IF NOT v_is_self AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized: can only read own digest or requires manage_member permission';
  END IF;

  SELECT jsonb_build_object(
    'member_id', p_member_id,
    'generated_at', now(),
    'this_week_pending', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'board_name', pb.board_name,
        'initiative_title', i.title,
        'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date)
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
    ), '[]'::jsonb),
    'next_week_due', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'board_name', pb.board_name,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date > CURRENT_DATE
        AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
    ), '[]'::jsonb),
    'overdue_7plus', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'board_name', pb.board_name,
        'initiative_title', i.title,
        'days_overdue', CURRENT_DATE - bi.due_date
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = p_member_id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_weekly_card_digest(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_weekly_card_digest(uuid) IS
  'Issue #98: individual member card digest (this_week_pending + next_week_due + overdue_7plus). V1 MVP.';

-- =========================================================================
-- 3. generate_weekly_card_digest_cron — orchestrator do pg_cron
--
-- Nota: inlina a query ao invés de chamar get_weekly_card_digest() porque a
-- RPC usa auth.uid() e pg_cron executa como superuser sem JWT — auth.uid()
-- retorna NULL. A RPC get_weekly_card_digest() é para consumo user-authenticated
-- (workspace UI, MCP tool). O orchestrator inline garante que o cron é independente
-- de contexto de autenticação (sempre generates for the given p_member_id).
--
-- Two-phase email delivery: este orchestrator cria rows em notifications;
-- o cron 'send-notification-emails' (a cada 5min) detecta email_sent_at IS NULL
-- e envia via Resend — padrão idêntico ao de IP ratification e governance.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.generate_weekly_card_digest_cron()
RETURNS TABLE(member_id uuid, notified boolean, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_m record;
  v_overdue jsonb;
  v_pending jsonb;
  v_next jsonb;
  v_has_content boolean;
  v_body text;
  v_title text;
  v_pending_count int;
  v_overdue_count int;
  v_next_count int;
BEGIN
  FOR v_m IN
    SELECT id, name, email
    FROM public.members
    WHERE is_active = true
      AND notify_weekly_digest = true  -- NOT NULL DEFAULT true, COALESCE redundante
  LOOP
    -- Inline queries (sem depender de get_weekly_card_digest → auth.uid())
    v_overdue := COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'days_overdue', CURRENT_DATE - bi.due_date,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = v_m.id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date < CURRENT_DATE - INTERVAL '7 days'
    ), '[]'::jsonb);

    v_pending := COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'days_overdue', GREATEST(0, CURRENT_DATE - bi.due_date),
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = v_m.id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date BETWEEN CURRENT_DATE - INTERVAL '7 days' AND CURRENT_DATE
    ), '[]'::jsonb);

    v_next := COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'due_date', bi.due_date,
        'initiative_title', i.title
      ) ORDER BY bi.due_date ASC)
      FROM public.board_items bi
      LEFT JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.initiatives i ON i.id = pb.initiative_id
      WHERE bi.assignee_id = v_m.id
        AND bi.status NOT IN ('done', 'archived')
        AND bi.due_date > CURRENT_DATE
        AND bi.due_date <= CURRENT_DATE + INTERVAL '7 days'
    ), '[]'::jsonb);

    v_overdue_count := jsonb_array_length(v_overdue);
    v_pending_count := jsonb_array_length(v_pending);
    v_next_count := jsonb_array_length(v_next);
    v_has_content := v_overdue_count > 0 OR v_pending_count > 0 OR v_next_count > 0;

    IF v_has_content THEN
      -- Title dinâmico com contagens
      v_title := 'Resumo semanal: ' ||
        CASE WHEN v_overdue_count > 0 THEN v_overdue_count::text || ' atrasada' ||
             CASE WHEN v_overdue_count > 1 THEN 's' ELSE '' END || ' + ' ELSE '' END ||
        v_pending_count::text || ' recente' ||
        CASE WHEN v_pending_count <> 1 THEN 's' ELSE '' END || ' + ' ||
        v_next_count::text || ' próxima semana';

      v_body := 'Olá, ' || COALESCE(v_m.name, 'voluntário(a)') || '!' || E'\n\n' ||
        'Aqui vai seu resumo semanal de atividades no Núcleo IA & GP.' || E'\n\n';

      IF v_overdue_count > 0 THEN
        v_body := v_body || 'ATRASADAS MAIS DE 7 DIAS (' || v_overdue_count || '):' || E'\n';
        v_body := v_body || (
          SELECT string_agg(
            '- ' || (item->>'title') ||
            ' — ' || (item->>'days_overdue') || ' dias atrasado' ||
            COALESCE(' (' || (item->>'initiative_title') || ')', ''),
            E'\n'
          )
          FROM jsonb_array_elements(v_overdue) AS item
        ) || E'\n\n';
      END IF;

      IF v_pending_count > 0 THEN
        v_body := v_body || 'PENDENTES DOS ÚLTIMOS 7 DIAS (' || v_pending_count || '):' || E'\n';
        v_body := v_body || (
          SELECT string_agg(
            '- ' || (item->>'title') ||
            ' — vence ' || (item->>'due_date') ||
            CASE WHEN (item->>'days_overdue')::int > 0
                 THEN ' (' || (item->>'days_overdue') || ' dias atraso)'
                 ELSE '' END ||
            COALESCE(' (' || (item->>'initiative_title') || ')', ''),
            E'\n'
          )
          FROM jsonb_array_elements(v_pending) AS item
        ) || E'\n\n';
      END IF;

      IF v_next_count > 0 THEN
        v_body := v_body || 'PRÓXIMOS 7 DIAS (' || v_next_count || '):' || E'\n';
        v_body := v_body || (
          SELECT string_agg(
            '- ' || (item->>'title') ||
            ' — vence ' || (item->>'due_date') ||
            COALESCE(' (' || (item->>'initiative_title') || ')', ''),
            E'\n'
          )
          FROM jsonb_array_elements(v_next) AS item
        ) || E'\n\n';
      END IF;

      v_body := v_body || 'Acesse a plataforma para atualizar cards, negociar prazos ou marcar tarefas concluídas.';

      INSERT INTO public.notifications (
        recipient_id, type, title, body, link, is_read
      )
      VALUES (
        v_m.id,
        'weekly_card_digest_member',
        v_title,
        v_body,
        '/workspace',
        false
      );
      member_id := v_m.id; notified := true; reason := 'sent';
    ELSE
      member_id := v_m.id; notified := false; reason := 'no_pending_cards_skip';
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_weekly_card_digest_cron() TO service_role;

COMMENT ON FUNCTION public.generate_weekly_card_digest_cron() IS
  'Issue #98: orchestrator do cron weekly-card-digest-saturday. Itera members opt-in, gera digest via get_weekly_card_digest, INSERT notifications.';

-- =========================================================================
-- 4. pg_cron entry — sábado 12:00 UTC (09:00 BRT)
-- =========================================================================
SELECT cron.schedule(
  'weekly-card-digest-saturday',
  '0 12 * * 6',
  $cron$SELECT public.generate_weekly_card_digest_cron()$cron$
);

-- =========================================================================
-- Reload PostgREST schema cache
-- =========================================================================
NOTIFY pgrst, 'reload schema';

COMMIT;
