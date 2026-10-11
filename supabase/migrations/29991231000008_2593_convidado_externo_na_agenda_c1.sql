-- #2593, fatia C1 — convidado externo da Agenda Viva com identidade, prazo de guarda e remoção. Sem envio:
-- o convite com ICS (C2) e o "Atualizado" com lembrete (C3) vêm depois, com o texto aprovado pelo GP.
--
-- Decisões do GP (09/10 e 11/10/2026): convite só na confirmação; o dono do bloco vê o e-mail do convidado;
-- o nome do convidado externo é público; guarda de evento + 1 ano (o vínculo vence e a varredura da fatia A,
-- external-contact-retention-daily, apaga a pessoa criada por este caminho e anonimiza o nome no bloco).
--
-- Medido em 11/10/2026 (leitura): 37 blocos; 2 com external_guest (1 reserved, 1 no_show), nenhum com e-mail.
-- Corpos vivos conferidos contra as capturas: reserve 21c17bbd, update 8e0dcfb5, cancel 1fde7f88 (20260805000178),
-- get_geral_agenda_viva f0b5e86a (20260825193745), _external_person_upsert 31811976 (20261010153307).
--
-- (1) event_agenda_blocks.guest_person_id → persons, ON DELETE SET NULL: a varredura apaga a pessoa e o bloco só
--     perde o ponteiro; nenhuma mudança na varredura.
-- (2) _agenda_guest_attach / _agenda_guest_detach: pessoa por _external_person_upsert (purpose agenda_guest,
--     source = bloco, retention_until = data do evento + 365); detach apaga o vínculo do bloco.
-- (3) reserve_agenda_block(+ p_guest_email): convidado externo exige nome e e-mail válido.
-- (4) update_agenda_block(+ p_guest_email, p_clear_guest, p_clear_material): troca de e-mail troca a pessoa;
--     deixar de ser externo, ou remover o convidado (também o caminho da oposição, Art. 18 §2º), apaga o vínculo.
-- (5) cancel_agenda_block: apaga o vínculo e o ponteiro.
-- (6) get_geral_agenda_viva: guest_public_name (só convidado externo de bloco confirmado) para todos; o dono vê
--     guest_name e guest_email do próprio bloco; manage_event ganha guest_email. guest_name cru nunca vai ao anônimo.
--
-- ⚠️ A ferramenta MCP agenda_blocks não passa e-mail: reserva com convidado externo por ela passa a receber
--    guest_email_required até a ferramenta ser atualizada (depois da lane B, pelo briefing).
--
-- Rollback: DROP das funções novas e das assinaturas novas de reserve/update; recriar reserve/update/cancel pela
--   captura 20260805000178 e get_geral_agenda_viva pela 20260825193745 (com os grants delas); DROP da coluna.

-- ── (1) identidade do convidado ──────────────────────────────────────────────
ALTER TABLE public.event_agenda_blocks
  ADD COLUMN IF NOT EXISTS guest_person_id uuid REFERENCES public.persons(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_event_agenda_blocks_guest_person ON public.event_agenda_blocks (guest_person_id)
  WHERE guest_person_id IS NOT NULL;
COMMENT ON COLUMN public.event_agenda_blocks.guest_person_id IS
  '#2593: pessoa do convidado externo (persons), criada por _external_person_upsert com vínculo agenda_guest até evento + 1 ano. Nulo sem convidado externo.';

-- ── (2) auxiliares ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_guest_attach(p_block_id uuid, p_name text, p_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_date date;
BEGIN
  SELECT e.date INTO v_date
  FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
  WHERE b.id = p_block_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agenda block not found' USING ERRCODE = 'no_data_found';
  END IF;
  RETURN public._external_person_upsert(p_email, p_name, 'agenda_guest', p_block_id, v_date + 365);
END;
$function$;

CREATE OR REPLACE FUNCTION public._agenda_guest_detach(p_block_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_n integer;
BEGIN
  DELETE FROM public.person_external_links l
  WHERE l.purpose = 'agenda_guest' AND l.source_id = p_block_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION public._agenda_guest_attach(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._agenda_guest_detach(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._agenda_guest_attach(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public._agenda_guest_detach(uuid) TO service_role;

-- ── (3) reserva ──────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean);
CREATE OR REPLACE FUNCTION public.reserve_agenda_block(
  p_event_id       uuid,
  p_format_slug    text,
  p_title          text,
  p_duration_min   integer,
  p_guest_name     text DEFAULT NULL,
  p_material_url   text DEFAULT NULL,
  p_external_guest boolean DEFAULT false,
  p_guest_email    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_event    record;
  v_rn       int;
  v_used     int;
  v_existing record;
  v_block_id uuid;
  v_sort     int;
  v_external boolean := COALESCE(p_external_guest, false);
  v_email    text := NULLIF(lower(btrim(COALESCE(p_guest_email, ''))), '');
  v_person   uuid;
BEGIN
  -- Caller resolves from the session; reservations are always self-scoped.
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT public.can_by_member(v_caller, 'reserve_agenda_block') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'reserve_agenda_block');
  END IF;

  IF p_title IS NULL OR btrim(p_title) = '' THEN
    RETURN jsonb_build_object('error', 'title_required');
  END IF;
  IF p_duration_min IS NULL OR p_duration_min <= 0 OR p_duration_min % 5 <> 0 THEN
    RETURN jsonb_build_object('error', 'invalid_duration', 'detail', 'must be a positive multiple of 5');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.agenda_block_formats WHERE slug = p_format_slug AND active) THEN
    RETURN jsonb_build_object('error', 'invalid_format', 'received', p_format_slug);
  END IF;
  -- #2593: convidado externo precisa de nome e e-mail, senão a plataforma não consegue avisá-lo nem convidá-lo
  IF v_external THEN
    IF p_guest_name IS NULL OR btrim(p_guest_name) = '' THEN
      RETURN jsonb_build_object('error', 'guest_name_required');
    END IF;
    IF v_email IS NULL THEN
      RETURN jsonb_build_object('error', 'guest_email_required');
    END IF;
    IF length(v_email) > 254 OR v_email !~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$' THEN
      RETURN jsonb_build_object('error', 'invalid_guest_email');
    END IF;
  END IF;

  -- Lock the event row: serializes concurrent reservations for the capacity check.
  SELECT e.id, e.type, e.status, e.time_start,
         (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_event
    FROM public.events e
    WHERE e.id = p_event_id
    FOR UPDATE;
  IF v_event.id IS NULL OR v_event.type <> 'geral' OR v_event.status IS NOT DISTINCT FROM 'cancelled' THEN
    RETURN jsonb_build_object('error', 'event_not_reservable');
  END IF;
  -- Fail-close on unconfigured start time (the COALESCE-to-midnight fallback would silently
  -- close the window at 00:00 local on the event day); a geral event must have time_start set.
  IF v_event.time_start IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_reservable', 'detail', 'event time_start not configured');
  END IF;

  -- Must be one of the next 2 upcoming `geral` meetings (this also enforces now < start).
  SELECT rn INTO v_rn FROM (
    SELECT e.id,
           row_number() OVER (
             ORDER BY (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo')
           ) AS rn
    FROM public.events e
    WHERE e.type = 'geral'
      AND e.status IS DISTINCT FROM 'cancelled'
      AND (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') > now()
  ) up WHERE up.id = p_event_id;
  IF v_rn IS NULL OR v_rn > 2 THEN
    RETURN jsonb_build_object('error', 'reservation_window_closed', 'detail', 'event is not among the next 2 open Reuniões Gerais');
  END IF;

  -- Capacity: reserved+confirmed must stay ≤ 90 min (the event is 90 min).
  SELECT COALESCE(SUM(duration_min), 0) INTO v_used
    FROM public.event_agenda_blocks
    WHERE event_id = p_event_id AND status IN ('reserved','confirmed');
  IF v_used + p_duration_min > 90 THEN
    RETURN jsonb_build_object('error', 'capacity_exceeded', 'used_min', v_used, 'requested_min', p_duration_min, 'cap_min', 90);
  END IF;

  -- One block per person per event. A prior cancelled row is reused (UNIQUE is unconditional).
  SELECT id, status INTO v_existing
    FROM public.event_agenda_blocks
    WHERE event_id = p_event_id AND owner_member_id = v_caller;
  -- Only a 'cancelled' row is reactivatable; reserved/confirmed/no_show all block a re-reserve.
  IF v_existing.id IS NOT NULL AND v_existing.status IN ('reserved','confirmed','no_show') THEN
    RETURN jsonb_build_object('error', 'already_reserved', 'block_id', v_existing.id, 'status', v_existing.status);
  END IF;

  SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_sort
    FROM public.event_agenda_blocks WHERE event_id = p_event_id;

  IF v_existing.id IS NOT NULL THEN
    -- Reactivate the cancelled row.
    UPDATE public.event_agenda_blocks
       SET format_slug = p_format_slug, title = p_title, duration_min = p_duration_min,
           guest_name = p_guest_name, material_url = p_material_url, external_guest = COALESCE(p_external_guest,false),
           status = 'reserved', reserved_at = now(), confirmed_at = NULL,
           cancelled_by = NULL, cancelled_reason = NULL, sort_order = v_sort, created_by = v_caller
     WHERE id = v_existing.id
     RETURNING id INTO v_block_id;
  ELSE
    INSERT INTO public.event_agenda_blocks (
      event_id, owner_member_id, format_slug, title, duration_min,
      guest_name, material_url, external_guest, sort_order, status, created_by
    ) VALUES (
      p_event_id, v_caller, p_format_slug, p_title, p_duration_min,
      p_guest_name, p_material_url, COALESCE(p_external_guest,false), v_sort, 'reserved', v_caller
    ) RETURNING id INTO v_block_id;
  END IF;

  -- #2593: a pessoa do convidado vem do caminho único de pessoa externa, com vínculo até evento + 1 ano.
  -- Linha reativada pode ter vínculo antigo: sai antes, e só o convidado de agora fica ligado ao bloco.
  PERFORM public._agenda_guest_detach(v_block_id);
  IF v_external THEN
    v_person := public._agenda_guest_attach(v_block_id, p_guest_name, v_email);
  END IF;
  UPDATE public.event_agenda_blocks SET guest_person_id = v_person WHERE id = v_block_id;

  RETURN jsonb_build_object(
    'success', true, 'block_id', v_block_id, 'event_id', p_event_id,
    'status', 'reserved', 'duration_min', p_duration_min,
    'capacity_used_min', v_used + p_duration_min, 'capacity_remaining_min', 90 - (v_used + p_duration_min)
  );
END
$function$;

REVOKE ALL ON FUNCTION public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text) TO authenticated;

-- ── (4) edição ───────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.update_agenda_block(uuid, text, text, integer, text, text, boolean);
CREATE OR REPLACE FUNCTION public.update_agenda_block(
  p_block_id       uuid,
  p_title          text DEFAULT NULL,
  p_format_slug    text DEFAULT NULL,
  p_duration_min   integer DEFAULT NULL,
  p_guest_name     text DEFAULT NULL,
  p_material_url   text DEFAULT NULL,
  p_external_guest boolean DEFAULT NULL,
  p_guest_email    text DEFAULT NULL,
  p_clear_guest    boolean DEFAULT false,
  p_clear_material boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean;
  v_block    record;
  v_start    timestamptz;
  v_used     int;
  v_new_dur  int;
  v_external boolean;
  v_name     text;
  v_cur_email text;
  v_email    text;
  v_person   uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  v_is_admin := public.can_by_member(v_caller, 'manage_event');

  SELECT b.*, (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_block
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.id = p_block_id
    FOR UPDATE OF b;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;

  IF NOT v_is_admin THEN
    IF v_block.owner_member_id <> v_caller THEN RETURN jsonb_build_object('error', 'access_denied'); END IF;
    IF now() >= v_block.start_at THEN RETURN jsonb_build_object('error', 'edit_window_closed'); END IF;
  END IF;
  IF v_block.status NOT IN ('reserved','confirmed') THEN
    RETURN jsonb_build_object('error', 'block_not_editable', 'status', v_block.status);
  END IF;

  v_new_dur := COALESCE(p_duration_min, v_block.duration_min);
  IF v_new_dur <= 0 OR v_new_dur % 5 <> 0 THEN
    RETURN jsonb_build_object('error', 'invalid_duration', 'detail', 'must be a positive multiple of 5');
  END IF;
  IF p_format_slug IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.agenda_block_formats WHERE slug = p_format_slug AND active) THEN
    RETURN jsonb_build_object('error', 'invalid_format', 'received', p_format_slug);
  END IF;

  -- Re-check capacity when duration grows (exclude this block's current contribution).
  IF v_new_dur <> v_block.duration_min THEN
    -- Acquire the event-row lock first, the same lock reserve_agenda_block holds, so the
    -- capacity SUM cannot race a concurrent reservation on the same event.
    PERFORM 1 FROM public.events WHERE id = v_block.event_id FOR UPDATE;
    SELECT COALESCE(SUM(duration_min), 0) INTO v_used
      FROM public.event_agenda_blocks
      WHERE event_id = v_block.event_id AND status IN ('reserved','confirmed') AND id <> p_block_id;
    IF v_used + v_new_dur > 90 THEN
      RETURN jsonb_build_object('error', 'capacity_exceeded', 'used_min', v_used, 'requested_min', v_new_dur, 'cap_min', 90);
    END IF;
  END IF;

  -- #2593: remover convidado ou material é explícito (p_clear_*); sem a marca, campo nulo mantém o atual
  v_external := CASE WHEN COALESCE(p_clear_guest, false) THEN false
                     ELSE COALESCE(p_external_guest, v_block.external_guest) END;
  v_name := CASE WHEN COALESCE(p_clear_guest, false) THEN NULL
                 ELSE COALESCE(NULLIF(btrim(p_guest_name), ''), v_block.guest_name) END;
  SELECT lower(p.email) INTO v_cur_email FROM public.persons p WHERE p.id = v_block.guest_person_id;
  v_email := COALESCE(NULLIF(lower(btrim(COALESCE(p_guest_email, ''))), ''), v_cur_email);
  IF v_external THEN
    IF v_name IS NULL OR btrim(v_name) = '' THEN
      RETURN jsonb_build_object('error', 'guest_name_required');
    END IF;
    IF v_email IS NULL THEN
      RETURN jsonb_build_object('error', 'guest_email_required');
    END IF;
    IF length(v_email) > 254 OR v_email !~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$' THEN
      RETURN jsonb_build_object('error', 'invalid_guest_email');
    END IF;
  END IF;

  UPDATE public.event_agenda_blocks
     SET title          = COALESCE(p_title, title),
         format_slug    = COALESCE(p_format_slug, format_slug),
         duration_min   = v_new_dur,
         guest_name     = v_name,
         material_url   = CASE WHEN COALESCE(p_clear_material, false) THEN NULL
                               ELSE COALESCE(p_material_url, material_url) END,
         external_guest = v_external
   WHERE id = p_block_id;

  -- a pessoa só troca quando o convidado troca (e-mail novo, ou passou a ser externo); deixar de ser externo
  -- ou remover o convidado apaga o vínculo do bloco, e a varredura leva a pessoa se não houver outro laço
  IF v_external THEN
    IF v_block.guest_person_id IS NULL OR v_email IS DISTINCT FROM v_cur_email THEN
      PERFORM public._agenda_guest_detach(p_block_id);
      v_person := public._agenda_guest_attach(p_block_id, v_name, v_email);
      UPDATE public.event_agenda_blocks SET guest_person_id = v_person WHERE id = p_block_id;
    END IF;
  ELSIF v_block.guest_person_id IS NOT NULL THEN
    PERFORM public._agenda_guest_detach(p_block_id);
    UPDATE public.event_agenda_blocks SET guest_person_id = NULL WHERE id = p_block_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id);
END
$function$;

REVOKE ALL ON FUNCTION public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, boolean, boolean) TO authenticated;

-- ── (5) cancelamento ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_agenda_block(
  p_block_id uuid,
  p_reason   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller   uuid;
  v_is_admin boolean;
  v_block    record;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  v_is_admin := public.can_by_member(v_caller, 'manage_event');

  SELECT b.*, (e.date + COALESCE(e.time_start,'00:00'::time)) AT TIME ZONE COALESCE(e.timezone,'America/Sao_Paulo') AS start_at
    INTO v_block
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.id = p_block_id
    FOR UPDATE OF b;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  IF v_block.status = 'cancelled' THEN RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'already', true); END IF;

  IF NOT v_is_admin THEN
    IF v_block.owner_member_id <> v_caller THEN RETURN jsonb_build_object('error', 'access_denied'); END IF;
    IF now() >= v_block.start_at THEN RETURN jsonb_build_object('error', 'cancel_window_closed'); END IF;
  END IF;

  -- #2593: bloco cancelado não precisa mais do contato do convidado; o vínculo sai e a varredura decide a pessoa
  PERFORM public._agenda_guest_detach(p_block_id);
  UPDATE public.event_agenda_blocks
     SET status = 'cancelled', cancelled_by = v_caller, cancelled_reason = p_reason, guest_person_id = NULL
   WHERE id = p_block_id;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'cancelled');
END
$function$;

REVOKE ALL ON FUNCTION public.cancel_agenda_block(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_agenda_block(uuid, text) TO authenticated;

-- ── (6) leitura ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_geral_agenda_viva(p_limit_events integer DEFAULT 2, p_member_id uuid DEFAULT NULL::uuid, p_window text DEFAULT 'upcoming'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
    v_is_admin := public._can_anywhere_by_member(v_caller, 'manage_event');
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
           m.name AS owner_full_name,
           gp.email AS guest_email
    FROM selected s
    JOIN public.event_agenda_blocks b ON b.event_id = s.id
    JOIN public.members m ON m.id = b.owner_member_id
    LEFT JOIN public.persons gp ON gp.id = b.guest_person_id
    -- upcoming: reserved+confirmed (futuro reservável); past: confirmed+no_show (realizado/falta).
    -- #1071: past 'reserved' also visible to admins (manage_event) so they can confirm/
    -- no-show a block whose meeting already ended (protagonism never confirmed live).
    WHERE (NOT s.is_past AND b.status IN ('reserved','confirmed'))
       OR (s.is_past     AND b.status IN ('confirmed','no_show'))
       OR (s.is_past AND v_is_admin AND b.status = 'reserved')
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
                -- LGPD PD-5 (#1548): a regra vive em _agenda_block_owner_visible, nao aqui.
                'owner_first_name', CASE
                  WHEN public._agenda_block_owner_visible(
                         bk.status,
                         (v_caller IS NOT NULL AND bk.owner_member_id = v_caller),
                         v_is_admin)
                    THEN bk.owner_first_name
                  ELSE NULL
                END,
                'is_mine', (v_caller IS NOT NULL AND bk.owner_member_id = v_caller)
              )
              -- #2593 (decisão do GP): o nome do convidado EXTERNO é público, mas só no bloco confirmado, que é
              -- quando ele recebe o convite com o aviso de privacidade. guest_name cru segue protegido abaixo.
              || CASE WHEN bk.external_guest AND bk.status = 'confirmed' AND bk.guest_name IS NOT NULL
                      THEN jsonb_build_object('guest_public_name', bk.guest_name)
                      ELSE '{}'::jsonb END
              -- #2593: o dono vê o convidado que cadastrou (a edição abria vazia), inclusive o e-mail
              || CASE WHEN v_caller IS NOT NULL AND bk.owner_member_id = v_caller
                      THEN jsonb_build_object('guest_name', bk.guest_name, 'guest_email', bk.guest_email)
                      ELSE '{}'::jsonb END
              -- authenticated (non-admin) additionally see the material link
              || CASE WHEN v_caller IS NOT NULL
                      THEN jsonb_build_object('material_url', bk.material_url)
                      ELSE '{}'::jsonb END
              -- manage_event sees full detail (owner id + full name + guest PII + raw fields)
              || CASE WHEN v_is_admin
                      THEN jsonb_build_object(
                             'owner_member_id', bk.owner_member_id,
                             'owner_full_name', bk.owner_full_name,
                             'guest_name', bk.guest_name,
                             'guest_email', bk.guest_email)
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

-- ── pós-condição ──────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_n integer;
  v_anon jsonb;
BEGIN
  -- as assinaturas antigas sumiram (não há sobrecarga que o PostgREST possa escolher)
  SELECT count(*) INTO v_n FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace AND proname IN ('reserve_agenda_block', 'update_agenda_block');
  IF v_n <> 2 THEN RAISE EXCEPTION '#2593: esperava 1 versão de reserve e 1 de update, achei %', v_n; END IF;

  -- quem chama a RPC não alcança os auxiliares
  IF has_function_privilege('authenticated', 'public._agenda_guest_attach(uuid, text, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._agenda_guest_detach(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, boolean, boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2593: auxiliar alcançável por authenticated, ou escrita alcançável por anon';
  END IF;

  -- a leitura sem sessão (o caminho do anônimo) não carrega nome cru nem e-mail de ninguém
  v_anon := public.get_geral_agenda_viva(6, NULL, 'both');
  IF v_anon::text ~ '"(guest_name|guest_email|owner_full_name|owner_member_id)"' THEN
    RAISE EXCEPTION '#2593: a leitura sem sessão vazou campo protegido';
  END IF;

  -- nenhum bloco ficou com ponteiro para pessoa sem ser convidado externo
  SELECT count(*) INTO v_n FROM public.event_agenda_blocks WHERE guest_person_id IS NOT NULL AND NOT external_guest;
  IF v_n <> 0 THEN RAISE EXCEPTION '#2593: % bloco(s) com pessoa sem convidado externo', v_n; END IF;
END
$postcondition$;

NOTIFY pgrst, 'reload schema';
