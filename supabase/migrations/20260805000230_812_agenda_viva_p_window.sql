-- =====================================================================================
-- #812 Agenda Viva na home com estado temporal — camada .sql (PD-1)
--
-- Adiciona o parâmetro `p_window` a get_geral_agenda_viva para expor, além das próximas
-- Reuniões Gerais, a ÚLTIMA reunião geral concluída (o "pós-evento" pedido pelo PM, PD-2).
-- DROP+CREATE porque a assinatura muda (3º parâmetro). Backward-compatible: o default
-- p_window='upcoming' reproduz exatamente o comportamento anterior (callers atuais passam
-- só {p_limit_events}).
--
--   p_window:
--     'upcoming'    (default) — próximas N reuniões `geral` (start_at > now), blocos
--                                reserved+confirmed. Comportamento legado idêntico.
--     'past_recent'           — só a ÚLTIMA reunião geral concluída (start_at <= now),
--                                blocos confirmed + no_show (read-only no FE).
--     'both'                  — última concluída + próximas N (timeline passado→futuro).
--
-- LGPD (PD-5, parecer legal-counsel 2026-06-22): expor publicamente que uma pessoa
-- IDENTIFICÁVEL (1º nome) FALTOU (no_show) viola finalidade/necessidade/não-discriminação
-- (LGPD Art. 6º III/IX) e cria dano reputacional permanente em superfície indexável. Logo,
-- para blocos no_show o owner_first_name é SUPRIMIDO (NULL) no ramo público (anon) e para o
-- membro logado comum; só o PRÓPRIO titular (is_mine, Art. 18 I — acesso ao próprio dado) e
-- manage_event veem o nome. O FE renderiza chip neutro ("Bloco não realizado"), nunca
-- "não compareceu". Título do bloco permanece (contexto da pauta, não é dado de conduta).
-- Demais camadas de PII inalteradas: guest_name/owner_full_name/owner_member_id só admin.
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.get_geral_agenda_viva(integer, uuid, text);
--   -- e re-aplicar o corpo (integer, uuid) do slice2 (20260805000178).
-- =====================================================================================

-- Assinatura nova (3 params) → DROP da antiga antes do CREATE (evita overload).
DROP FUNCTION IF EXISTS public.get_geral_agenda_viva(integer, uuid);

CREATE FUNCTION public.get_geral_agenda_viva(
  p_limit_events integer DEFAULT 2,
  p_member_id    uuid DEFAULT NULL,
  p_window       text DEFAULT 'upcoming'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean := false;
  v_limit    int := LEAST(GREATEST(COALESCE(p_limit_events, 2), 1), 6);
  v_window   text := lower(COALESCE(p_window, 'upcoming'));
  v_result   jsonb;
BEGIN
  IF v_window NOT IN ('upcoming','past_recent','both') THEN
    v_window := 'upcoming';
  END IF;

  -- p_member_id is part of the spec signature, reserved for a future admin "view as member"
  -- mode (slice 3); the caller is always resolved from auth.uid() here (no impersonation yet).
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NOT NULL THEN
    v_is_admin := public.can_by_member(v_caller, 'manage_event');
  END IF;

  WITH all_geral AS (
    SELECT e.id, e.title, e.date, e.time_start, e.timezone,
           (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    FROM public.events e
    WHERE e.type = 'geral'
      AND e.status IS DISTINCT FROM 'cancelled'
  ),
  upcoming AS (
    SELECT ag.id, ag.title, ag.date, ag.time_start, ag.timezone, ag.start_at, false AS is_past
    FROM all_geral ag
    WHERE v_window IN ('upcoming','both')
      AND ag.start_at > now()
    ORDER BY ag.start_at
    LIMIT v_limit
  ),
  past AS (
    SELECT ag.id, ag.title, ag.date, ag.time_start, ag.timezone, ag.start_at, true AS is_past
    FROM all_geral ag
    WHERE v_window IN ('past_recent','both')
      AND ag.start_at <= now()
    ORDER BY ag.start_at DESC
    LIMIT 1
  ),
  selected AS (
    SELECT * FROM past
    UNION ALL
    SELECT * FROM upcoming
  ),
  blocks AS (
    SELECT s.is_past, b.event_id, b.id, b.format_slug, b.title, b.duration_min, b.status, b.sort_order,
           b.external_guest, b.owner_member_id, b.guest_name, b.material_url,
           split_part(m.name, ' ', 1) AS owner_first_name,
           m.name AS owner_full_name
    FROM selected s
    JOIN public.event_agenda_blocks b ON b.event_id = s.id
    JOIN public.members m ON m.id = b.owner_member_id
    -- upcoming: reserved+confirmed (futuro reservável); past: confirmed+no_show (realizado/falta).
    WHERE (NOT s.is_past AND b.status IN ('reserved','confirmed'))
       OR (s.is_past     AND b.status IN ('confirmed','no_show'))
  )
  SELECT jsonb_build_object(
    'viewer', jsonb_build_object('is_authenticated', v_caller IS NOT NULL, 'is_admin', v_is_admin),
    'window', v_window,
    'events', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id, 'title', s.title, 'date', s.date, 'time_start', s.time_start,
          'timezone', s.timezone, 'start_at', s.start_at,
          'is_past', s.is_past,
          'capacity_total_min', 90,
          'capacity_used_min', COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = s.id), 0),
          'capacity_remaining_min', 90 - COALESCE((SELECT SUM(duration_min) FROM blocks bk WHERE bk.event_id = s.id), 0),
          'blocks', COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'id', bk.id, 'format_slug', bk.format_slug, 'title', bk.title,
                'duration_min', bk.duration_min, 'status', bk.status, 'sort_order', bk.sort_order,
                'external_guest', bk.external_guest,
                -- LGPD PD-5: no_show NÃO revela o nome ao público nem ao membro comum; só o
                -- próprio titular (is_mine) e manage_event. Ver cabeçalho da migration.
                'owner_first_name', CASE
                  WHEN bk.status = 'no_show'
                       AND NOT v_is_admin
                       AND NOT (v_caller IS NOT NULL AND bk.owner_member_id = v_caller)
                    THEN NULL
                  ELSE bk.owner_first_name
                END,
                'is_mine', (v_caller IS NOT NULL AND bk.owner_member_id = v_caller)
              )
              -- authenticated (non-admin) additionally see the material link
              || CASE WHEN v_caller IS NOT NULL
                      THEN jsonb_build_object('material_url', bk.material_url)
                      ELSE '{}'::jsonb END
              -- manage_event sees full detail (owner id + full name + guest PII + raw fields)
              || CASE WHEN v_is_admin
                      THEN jsonb_build_object(
                             'owner_member_id', bk.owner_member_id,
                             'owner_full_name', bk.owner_full_name,
                             'guest_name', bk.guest_name)
                      ELSE '{}'::jsonb END
              ORDER BY bk.sort_order, bk.duration_min DESC
            ) FROM blocks bk WHERE bk.event_id = s.id
          ), '[]'::jsonb)
        ) ORDER BY s.start_at
      ) FROM selected s
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END
$function$;

REVOKE ALL ON FUNCTION public.get_geral_agenda_viva(integer, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_geral_agenda_viva(integer, uuid, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
