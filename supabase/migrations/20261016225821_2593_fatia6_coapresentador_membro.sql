-- #2593, fatia 6 — coapresentador membro separado do convidado externo, com o mesmo crédito de protagonismo.
--
-- Medido em 16/10/2026: event_agenda_blocks tem 41 blocos; 15 com guest_name, 3 com external_guest. O campo guest_name
-- servia a duas coisas: o convidado de fora e o membro que apresenta junto (ou no lugar) do dono. Dos 12 blocos com nome
-- e sem a marca de externo, todos de reuniões passadas e confirmados: 5 repetiam o nome do próprio dono, 1 dizia
-- "Geral" e 6 nomeavam outro membro ativo (cada nome casa com exatamente um membro). O XP de protagonismo da
-- confirmação ia só para o dono (_grant_agenda_block_xp), então quem apresentou nesses 6 não recebeu nada.
--
-- Decisões do GP em 16/10/2026: o coapresentador membro recebe o mesmo cálculo de protagonismo do dono, e o dono mantém
-- o dele; os 6 blocos antigos migram para coapresentador com XP retroativo; quem não consta presente não recebe (mesma
-- régua do dono), e a reconfirmação do bloco credita se a presença for corrigida.
--
-- (1) event_agenda_block_copresenters (bloco, membro): deny-all (RLS sem policy, sem privilégio para anon e
--     authenticated); lê e escreve só pelas RPCs SECURITY DEFINER.
-- (2) _agenda_copresenter_ids_problem: até 3, membro ativo, nunca o dono.
--     _agenda_block_copresenters_json: lista para as telas (primeiro nome, ou id e nome).
-- (3) _grant_agenda_block_member_xp / _grant_agenda_block_copresenters_xp: o cálculo do dono (formato, faixa de duração,
--     bônus), só para quem está presente na reunião, um crédito por (bloco, membro). Primeira vez = nenhum outro bloco
--     confirmado como dono e nenhum outro crédito de protagonismo.
-- (4) _reverse_agenda_block_member_xp: estorno (pontos negativos) de quem sai de um bloco já confirmado (ADR-0081).
-- (5)(6) reserve_agenda_block / update_agenda_block: p_copresenter_ids; guest_name só com convidado externo
--     (guest_name_requires_external). Assinatura nova: DROP + CREATE.
-- (7) confirm_agenda_block / confirm_event_blocks: creditam os coapresentadores presentes, independente do dono.
-- (8) revoke_agenda_block_xp: o não realizado estorna dono e coapresentadores.
-- (9) get_geral_agenda_viva / get_meeting_preparation: copresenter_first_names pela regra do primeiro nome do dono
--     (PD-5); o dono e manage_event recebem copresenters com o id.
-- (10) Os 12 blocos antigos: 6 pares (bloco, membro) viram coapresentador; guest_name sai de todo bloco sem convidado
--     externo; CHECK eab_guest_name_only_external; XP retroativo em ordem de data.
--
-- Rollback: recriar as 7 funções pelas capturas anteriores (reserve/update/get_geral da C1 20261011112204,
--   confirm da C2 20261011143731, confirm_event_blocks e _grant da 20260805000179, revoke da 20260805000333,
--   get_meeting_preparation da 20260805000499), DROP das funções novas e da tabela, DROP CONSTRAINT
--   eab_guest_name_only_external. O XP gravado aqui sai por estorno, nunca por DELETE.

-- ── (1) quem apresenta junto, como membro ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.event_agenda_block_copresenters (
  block_id   uuid NOT NULL REFERENCES public.event_agenda_blocks(id) ON DELETE CASCADE,
  member_id  uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  added_by   uuid REFERENCES public.members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (block_id, member_id)
);
CREATE INDEX IF NOT EXISTS eabc_member_idx ON public.event_agenda_block_copresenters (member_id);
ALTER TABLE public.event_agenda_block_copresenters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.event_agenda_block_copresenters FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.event_agenda_block_copresenters IS
  '#2593 fatia 6: membros que apresentam um bloco da Agenda Viva junto com o dono (ou no lugar dele). Convidado de fora continua em event_agenda_blocks.guest_name. Deny-all: só pelas RPCs SECURITY DEFINER.';

-- ── (2) regra da lista e leitura para as telas ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._agenda_copresenter_ids_problem(p_ids uuid[], p_owner uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN p_ids IS NULL THEN NULL
    WHEN (SELECT count(DISTINCT x) FROM unnest(p_ids) AS x) > 3 THEN 'too_many_copresenters'
    WHEN EXISTS (SELECT 1 FROM unnest(p_ids) AS x WHERE x IS NULL OR x = p_owner) THEN 'invalid_copresenter'
    WHEN EXISTS (SELECT 1 FROM unnest(p_ids) AS x
                 WHERE NOT EXISTS (SELECT 1 FROM public.members m WHERE m.id = x AND m.is_active)) THEN 'invalid_copresenter'
    ELSE NULL
  END;
$function$;
REVOKE ALL ON FUNCTION public._agenda_copresenter_ids_problem(uuid[], uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._agenda_block_copresenters_json(p_block_id uuid, p_detail boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(jsonb_agg(
           CASE WHEN p_detail THEN jsonb_build_object('member_id', m.id, 'name', m.name)
                ELSE to_jsonb(split_part(m.name, ' ', 1)) END
           ORDER BY m.name), '[]'::jsonb)
  FROM public.event_agenda_block_copresenters c
  JOIN public.members m ON m.id = c.member_id
  WHERE c.block_id = p_block_id;
$function$;
REVOKE ALL ON FUNCTION public._agenda_block_copresenters_json(uuid, boolean) FROM PUBLIC, anon, authenticated;

-- ── (3) crédito do coapresentador: o cálculo do dono, para quem estava presente ─────────────────────────────
CREATE OR REPLACE FUNCTION public._grant_agenda_block_member_xp(p_block_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_block    record;
  v_org      uuid;
  v_base     int;
  v_weight   numeric;
  v_bonus    int := 0;
  v_total    int;
  v_reason   text;
BEGIN
  SELECT b.id, b.event_id, b.owner_member_id, b.format_slug, b.duration_min, b.status,
         b.external_guest, b.material_url, b.title, b.organization_id, e.date AS event_date
    INTO v_block
    FROM public.event_agenda_blocks b JOIN public.events e ON e.id = b.event_id
    WHERE b.id = p_block_id;
  IF v_block.id IS NULL OR p_member_id IS NULL OR v_block.status <> 'confirmed' THEN
    RETURN;
  END IF;
  -- só quem está no bloco como coapresentador; o dono segue em _grant_agenda_block_xp
  IF NOT EXISTS (
    SELECT 1 FROM public.event_agenda_block_copresenters c
    WHERE c.block_id = p_block_id AND c.member_id = p_member_id
  ) THEN
    RETURN;
  END IF;
  -- mesma régua do dono: só recebe quem consta presente na reunião
  IF NOT EXISTS (
    SELECT 1 FROM public.attendance a
    WHERE a.event_id = v_block.event_id AND a.member_id = p_member_id AND a.present = true
  ) THEN
    RETURN;
  END IF;
  v_org := v_block.organization_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.gamification_rules
    WHERE slug = 'agenda_block_protagonismo' AND organization_id = v_org
      AND active = true AND effective_from <= now()
  ) THEN
    RETURN;
  END IF;

  -- um crédito por (bloco, membro), como o do dono
  IF EXISTS (
    SELECT 1 FROM public.gamification_points
    WHERE ref_id = p_block_id AND category = 'agenda_block_protagonismo'
      AND member_id = p_member_id
  ) THEN
    RETURN;
  END IF;

  SELECT base_points INTO v_base FROM public.agenda_block_formats WHERE slug = v_block.format_slug;
  IF v_base IS NULL THEN
    RETURN;
  END IF;

  v_weight := CASE
    WHEN v_block.duration_min <= 10 THEN 1.0
    WHEN v_block.duration_min <= 20 THEN 1.15
    ELSE 1.3
  END;

  IF v_block.external_guest IS TRUE THEN
    v_bonus := v_bonus + COALESCE((SELECT base_points FROM public.gamification_rules
      WHERE slug = 'agenda_block_bonus_external_guest' AND organization_id = v_org AND active = true), 0);
  END IF;
  IF v_block.material_url IS NOT NULL AND btrim(v_block.material_url) <> '' THEN
    v_bonus := v_bonus + COALESCE((SELECT base_points FROM public.gamification_rules
      WHERE slug = 'agenda_block_bonus_shared_material' AND organization_id = v_org AND active = true), 0);
  END IF;
  -- primeira vez: nenhum outro bloco confirmado como dono e nenhum outro crédito de protagonismo
  IF NOT EXISTS (
    SELECT 1 FROM public.event_agenda_blocks
    WHERE owner_member_id = p_member_id AND status = 'confirmed' AND id <> p_block_id
  ) AND NOT EXISTS (
    SELECT 1 FROM public.gamification_points
    WHERE member_id = p_member_id AND category = 'agenda_block_protagonismo'
      AND ref_id <> p_block_id AND points > 0
  ) THEN
    v_bonus := v_bonus + COALESCE((SELECT base_points FROM public.gamification_rules
      WHERE slug = 'agenda_block_bonus_first_time' AND organization_id = v_org AND active = true), 0);
  END IF;

  v_total := round(v_base * v_weight)::int + v_bonus;
  v_reason := 'Coapresentação na Reunião Geral: ' || v_block.title || ' (' || v_block.format_slug || ', ' || v_block.duration_min || 'min)';

  -- data do FATO (a reunião), como a presença (#1464): o crédito retroativo cai no dia em que a pessoa apresentou
  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id, organization_id, occurred_at)
  VALUES (p_member_id, v_total, v_reason, 'agenda_block_protagonismo', p_block_id, v_org,
          (v_block.event_date + time '12:00') AT TIME ZONE 'America/Sao_Paulo');
END;
$function$;
REVOKE ALL ON FUNCTION public._grant_agenda_block_member_xp(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._grant_agenda_block_copresenters_xp(p_block_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member uuid;
BEGIN
  FOR v_member IN
    SELECT c.member_id FROM public.event_agenda_block_copresenters c
    WHERE c.block_id = p_block_id ORDER BY c.created_at, c.member_id
  LOOP
    PERFORM public._grant_agenda_block_member_xp(p_block_id, v_member);
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public._grant_agenda_block_copresenters_xp(uuid) FROM PUBLIC, anon, authenticated;

-- ── (4) quem sai de um bloco confirmado devolve o crédito, por estorno ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public._reverse_agenda_block_member_xp(p_block_id uuid, p_member_id uuid, p_actor uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO public.gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
  SELECT gp.member_id, gp.organization_id, -SUM(gp.points), gp.category,
         'Estorno (coapresentação removida): ' || COALESCE(p_reason, 'removido do bloco'), p_block_id, p_actor
  FROM public.gamification_points gp
  WHERE gp.ref_id = p_block_id
    AND gp.category = 'agenda_block_protagonismo'
    AND gp.member_id = p_member_id
  GROUP BY gp.member_id, gp.organization_id, gp.category
  HAVING SUM(gp.points) <> 0;
END;
$function$;
REVOKE ALL ON FUNCTION public._reverse_agenda_block_member_xp(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;

-- ── (5) reserve_agenda_block: coapresentadores, e guest_name só com convidado externo ───────────────────
DROP FUNCTION IF EXISTS public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text, text);
CREATE OR REPLACE FUNCTION public.reserve_agenda_block(p_event_id uuid, p_format_slug text, p_title text, p_duration_min integer, p_guest_name text DEFAULT NULL::text, p_material_url text DEFAULT NULL::text, p_external_guest boolean DEFAULT false, p_guest_email text DEFAULT NULL::text, p_guest_language text DEFAULT NULL::text, p_copresenter_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
  v_lang     text := public.normalize_platform_language(p_guest_language);
  v_problem  text;
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
  -- #2593 fatia 6: guest_name é só do convidado externo; membro que apresenta junto entra como coapresentador
  IF NOT v_external AND NULLIF(btrim(COALESCE(p_guest_name, '')), '') IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'guest_name_requires_external');
  END IF;
  v_problem := public._agenda_copresenter_ids_problem(p_copresenter_ids, v_caller);
  IF v_problem IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_problem);
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
           guest_name = CASE WHEN v_external THEN p_guest_name END, material_url = p_material_url, external_guest = v_external,
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
      CASE WHEN v_external THEN p_guest_name END, p_material_url, v_external, v_sort, 'reserved', v_caller
    ) RETURNING id INTO v_block_id;
  END IF;

  -- #2593: a pessoa do convidado vem do caminho único de pessoa externa, com vínculo até evento + 1 ano.
  -- Linha reativada pode ter vínculo antigo: sai antes, e só o convidado de agora fica ligado ao bloco.
  PERFORM public._agenda_guest_detach(v_block_id);
  IF v_external THEN
    v_person := public._agenda_guest_attach(v_block_id, p_guest_name, v_email);
  END IF;
  UPDATE public.event_agenda_blocks SET guest_person_id = v_person, guest_notified_at = NULL, guest_language = v_lang
   WHERE id = v_block_id;

  -- #2593 fatia 6: a linha reativada traz os coapresentadores de antes; ficam só os de agora
  DELETE FROM public.event_agenda_block_copresenters WHERE block_id = v_block_id;
  INSERT INTO public.event_agenda_block_copresenters (block_id, member_id, added_by)
  SELECT DISTINCT v_block_id, x, v_caller FROM unnest(COALESCE(p_copresenter_ids, '{}'::uuid[])) AS x;

  RETURN jsonb_build_object(
    'success', true, 'block_id', v_block_id, 'event_id', p_event_id,
    'status', 'reserved', 'duration_min', p_duration_min,
    'capacity_used_min', v_used + p_duration_min, 'capacity_remaining_min', 90 - (v_used + p_duration_min)
  );
END
$function$;
REVOKE ALL ON FUNCTION public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, uuid[]) TO authenticated, service_role;

-- ── (6) update_agenda_block: coapresentadores, e guest_name só com convidado externo ────────────────────
DROP FUNCTION IF EXISTS public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, boolean, boolean);
CREATE OR REPLACE FUNCTION public.update_agenda_block(p_block_id uuid, p_title text DEFAULT NULL::text, p_format_slug text DEFAULT NULL::text, p_duration_min integer DEFAULT NULL::integer, p_guest_name text DEFAULT NULL::text, p_material_url text DEFAULT NULL::text, p_external_guest boolean DEFAULT NULL::boolean, p_guest_email text DEFAULT NULL::text, p_guest_language text DEFAULT NULL::text, p_clear_guest boolean DEFAULT false, p_clear_material boolean DEFAULT false, p_copresenter_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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
  v_problem  text;
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
  -- #2593 fatia 6: guest_name é só do convidado externo; bloco que deixa de ter externo perde o nome junto
  IF NOT v_external AND NULLIF(btrim(COALESCE(p_guest_name, '')), '') IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'guest_name_requires_external');
  END IF;
  IF NOT v_external THEN
    v_name := NULL;
  END IF;
  v_problem := public._agenda_copresenter_ids_problem(p_copresenter_ids, v_block.owner_member_id);
  IF v_problem IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_problem);
  END IF;
  -- o e-mail atual é o que foi digitado (no vínculo do bloco), nunca o principal da pessoa
  SELECT l.contact_email INTO v_cur_email FROM public.person_external_links l
  WHERE l.purpose = 'agenda_guest' AND l.source_id = p_block_id
  ORDER BY l.updated_at DESC LIMIT 1;
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
         external_guest = v_external,
         guest_language = CASE WHEN p_guest_language IS NULL THEN guest_language
                               ELSE public.normalize_platform_language(p_guest_language) END,
         -- convidado diferente (nome, e-mail, ou deixou de ser externo) ainda não foi avisado
         guest_notified_at = CASE WHEN v_external AND v_name IS NOT DISTINCT FROM v_block.guest_name
                                       AND v_email IS NOT DISTINCT FROM v_cur_email
                                  THEN guest_notified_at ELSE NULL END
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

  -- #2593 fatia 6: lista de coapresentadores informada substitui a atual (vazia remove todos; nula mantém).
  -- No bloco já confirmado, quem sai recebe o estorno do crédito e quem entra é creditado se estava presente.
  IF p_copresenter_ids IS NOT NULL THEN
    PERFORM public._reverse_agenda_block_member_xp(p_block_id, c.member_id, v_caller, 'removido do bloco')
       FROM public.event_agenda_block_copresenters c
      WHERE c.block_id = p_block_id AND NOT (c.member_id = ANY (p_copresenter_ids))
        AND v_block.status = 'confirmed';
    DELETE FROM public.event_agenda_block_copresenters c
     WHERE c.block_id = p_block_id AND NOT (c.member_id = ANY (p_copresenter_ids));
    INSERT INTO public.event_agenda_block_copresenters (block_id, member_id, added_by)
    SELECT DISTINCT p_block_id, x, v_caller FROM unnest(p_copresenter_ids) AS x
    ON CONFLICT (block_id, member_id) DO NOTHING;
    IF v_block.status = 'confirmed' THEN
      PERFORM public._grant_agenda_block_copresenters_xp(p_block_id);
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id);
END
$function$;
REVOKE ALL ON FUNCTION public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, boolean, boolean, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, boolean, boolean, uuid[]) TO authenticated, service_role;

-- ── (7) confirmar credita os coapresentadores presentes ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_agenda_block(p_block_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_block   record;
  v_present boolean;
  v_invite  uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  SELECT * INTO v_block FROM public.event_agenda_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  IF v_block.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'cannot_confirm_cancelled', 'block_id', p_block_id);
  END IF;
  -- Re-confirming an already-confirmed block is intentionally a no-op on XP (the credit is
  -- idempotent by ref_id) but DOES re-attempt the credit — this is the heal path for
  -- "confirmed before attendance was marked, then corrected to present, then re-confirmed".

  v_present := EXISTS (
    SELECT 1 FROM public.attendance
    WHERE event_id = v_block.event_id AND member_id = v_block.owner_member_id AND present = true
  );

  UPDATE public.event_agenda_blocks
     SET status = 'confirmed', confirmed_at = now()
   WHERE id = p_block_id;

  IF v_present THEN
    PERFORM public._grant_agenda_block_xp(p_block_id);
  END IF;
  -- #2593 fatia 6: cada coapresentador presente recebe o mesmo cálculo, independente da presença do dono
  PERFORM public._grant_agenda_block_copresenters_xp(p_block_id);

  -- #2593 (C2): convidado externo ainda não avisado recebe o convite com ICS; o carimbo guest_notified_at só vem
  -- quando o provedor aceita o envio (send-campaign), e é ele que libera o nome na agenda pública
  IF v_block.external_guest AND v_block.guest_notified_at IS NULL THEN
    v_invite := public._agenda_guest_send(p_block_id, 'invite', v_caller, true);
  END IF;

  -- #2593 (C2): o dono sabe pelo sino quando OUTRA pessoa confirma o bloco dele (só na transição, não no reparo)
  IF v_block.status IS DISTINCT FROM 'confirmed' AND v_block.owner_member_id <> v_caller THEN
    PERFORM public._agenda_block_owner_notice(p_block_id, 'agenda_block_confirmed');
  END IF;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'confirmed',
                            'xp_credited', v_present, 'guest_invite_send_id', v_invite);
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_event_blocks(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller    uuid;
  v_block     record;
  v_present   boolean;
  v_confirmed int := 0;
  v_credited  int := 0;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  FOR v_block IN
    SELECT id, event_id, owner_member_id
      FROM public.event_agenda_blocks
      WHERE event_id = p_event_id AND status = 'reserved'
      ORDER BY sort_order, duration_min DESC
      FOR UPDATE
  LOOP
    v_present := EXISTS (
      SELECT 1 FROM public.attendance
      WHERE event_id = v_block.event_id AND member_id = v_block.owner_member_id AND present = true
    );
    UPDATE public.event_agenda_blocks SET status = 'confirmed', confirmed_at = now() WHERE id = v_block.id;
    v_confirmed := v_confirmed + 1;
    IF v_present THEN
      PERFORM public._grant_agenda_block_xp(v_block.id);
      v_credited := v_credited + 1;
    END IF;
    -- #2593 fatia 6: coapresentadores presentes, independente da presença do dono
    PERFORM public._grant_agenda_block_copresenters_xp(v_block.id);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id,
                            'confirmed', v_confirmed, 'credited', v_credited);
END;
$function$;

-- ── (8) não realizado estorna dono e coapresentadores ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_agenda_block_xp(p_block_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_block   record;
  v_reversal_rows int := 0;
  v_reversal_points int := 0;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  SELECT * INTO v_block FROM public.event_agenda_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  -- A cancelled block has its own terminal outcome; do not overwrite it with no_show.
  IF v_block.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'cannot_revoke_cancelled', 'block_id', p_block_id);
  END IF;

  -- #1087 Onda 3: ledger append-only — estorno (pontos negativos) em vez de DELETE.
  WITH net AS (
    SELECT gp.member_id, gp.organization_id, gp.category, SUM(gp.points) AS pts
    FROM public.gamification_points gp
    WHERE gp.ref_id = p_block_id
      AND gp.category = 'agenda_block_protagonismo'
      -- #2593 fatia 6: dono e coapresentadores; todo crédito de protagonismo deste bloco volta
    GROUP BY gp.member_id, gp.organization_id, gp.category
    HAVING SUM(gp.points) <> 0
  ), reversal AS (
    INSERT INTO public.gamification_points (member_id, organization_id, points, category, reason, ref_id, granted_by)
    SELECT n.member_id, n.organization_id, -n.pts, n.category,
           'Estorno (protagonismo revogado): ' || COALESCE(p_reason, 'no_show'), p_block_id, v_caller
    FROM net n
    RETURNING points
  )
  SELECT count(*), COALESCE(SUM(points), 0)::int
    INTO v_reversal_rows, v_reversal_points
  FROM reversal;

  UPDATE public.event_agenda_blocks
     SET status = 'no_show', confirmed_at = NULL,
         cancelled_by = v_caller, cancelled_reason = COALESCE(p_reason, cancelled_reason)
   WHERE id = p_block_id;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'no_show',
                            'xp_revoked', v_reversal_rows,
                            'reversal_points', v_reversal_points);
END;
$function$;

-- ── (9) a agenda mostra os coapresentadores ─────────────────────────────────────────────────────────────
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
           b.guest_notified_at,
           b.guest_language,
           gl.contact_email AS guest_email
    FROM selected s
    JOIN public.event_agenda_blocks b ON b.event_id = s.id
    JOIN public.members m ON m.id = b.owner_member_id
    -- #2593: o e-mail mostrado é o digitado para este bloco (vínculo), nunca o principal da pessoa
    LEFT JOIN LATERAL (
      SELECT l.contact_email FROM public.person_external_links l
      WHERE l.purpose = 'agenda_guest' AND l.source_id = b.id
      ORDER BY l.updated_at DESC LIMIT 1
    ) gl ON true
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
                'is_mine', (v_caller IS NOT NULL AND bk.owner_member_id = v_caller),
                -- #2593 fatia 6: coapresentador membro segue a mesma regra do primeiro nome do dono (PD-5)
                'copresenter_first_names', CASE
                  WHEN public._agenda_block_owner_visible(
                         bk.status,
                         (v_caller IS NOT NULL AND bk.owner_member_id = v_caller),
                         v_is_admin)
                    THEN public._agenda_block_copresenters_json(bk.id, false)
                  ELSE '[]'::jsonb
                END
              )
              -- #2593 (decisão do GP): o nome do convidado EXTERNO é público, mas só no bloco confirmado e depois
              -- que ele recebeu o convite com o aviso de privacidade. guest_name cru segue protegido abaixo.
              || CASE WHEN bk.external_guest AND bk.status = 'confirmed' AND bk.guest_notified_at IS NOT NULL
                       AND bk.guest_name IS NOT NULL
                      THEN jsonb_build_object('guest_public_name', bk.guest_name)
                      ELSE '{}'::jsonb END
              -- #2593: o dono vê o convidado que cadastrou (a edição abria vazia), inclusive o e-mail
              || CASE WHEN v_caller IS NOT NULL AND bk.owner_member_id = v_caller
                      THEN jsonb_build_object('guest_name', bk.guest_name, 'guest_email', bk.guest_email,
                                              'guest_language', bk.guest_language)
                      ELSE '{}'::jsonb END
              -- #2593 fatia 6: o dono e manage_event veem quem coapresenta, com o id, para editar
              || CASE WHEN (v_caller IS NOT NULL AND bk.owner_member_id = v_caller) OR v_is_admin
                      THEN jsonb_build_object('copresenters', public._agenda_block_copresenters_json(bk.id, true))
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
                             'guest_email', bk.guest_email,
                             'guest_language', bk.guest_language)
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

CREATE OR REPLACE FUNCTION public.get_meeting_preparation(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_admin boolean := false;
  v_is_past boolean := false;
  v_event record;
  v_initiative record;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Caller has no member record'; END IF;

  SELECT e.id, e.title, e.date, e.type, e.duration_minutes, e.meeting_link,
         e.initiative_id, e.agenda_text, e.agenda_url, e.time_start, e.timezone
  INTO v_event FROM public.events e WHERE e.id = p_event_id;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  IF NOT public.rls_can_see_initiative(v_event.initiative_id) THEN
    RETURN jsonb_build_object('error', 'event_not_found');
  END IF;

  -- #1548: mesmo calculo de "ja aconteceu" de get_geral_agenda_viva, para os dois nao divergirem.
  v_is_admin := public.can_by_member(v_caller_id, 'manage_event');
  v_is_past := (
    (v_event.date + COALESCE(v_event.time_start,'00:00'::time))
      AT TIME ZONE COALESCE(v_event.timezone,'America/Sao_Paulo')
  ) <= now();

  -- #1383 W3: this SELECT INTO must run UNCONDITIONALLY. It used to be guarded by
  -- `IF v_event.initiative_id IS NOT NULL`, which left v_initiative UNASSIGNED for org-wide
  -- events, and the read of v_initiative.id below then raised instead of yielding NULL.
  -- With no matching row the record is assigned all-NULLs, which is what that read expects.
  SELECT i.id, i.title, i.kind, i.legacy_tribe_id
  INTO v_initiative FROM public.initiatives i WHERE i.id = v_event.initiative_id;

  v_result := jsonb_build_object(
    'event', jsonb_build_object(
      'id', v_event.id,
      'title', v_event.title,
      'date', v_event.date,
      'type', v_event.type,
      'duration_minutes', v_event.duration_minutes,
      'meeting_link', v_event.meeting_link,
      'agenda_text', v_event.agenda_text,
      'agenda_url', v_event.agenda_url,
      'is_past', v_is_past
    ),
    'initiative', CASE WHEN v_initiative.id IS NOT NULL THEN
      jsonb_build_object('id', v_initiative.id, 'title', v_initiative.title,
        'kind', v_initiative.kind, 'legacy_tribe_id', v_initiative.legacy_tribe_id)
    ELSE NULL END,
    -- #1548: a pauta de uma Reuniao Geral SAO os blocos. Recorte por status identico ao
    -- get_geral_agenda_viva (#1071): futuro = reserved+confirmed; passado = confirmed+no_show,
    -- mais reserved quando quem le tem manage_event (e quem pode confirmar).
    'agenda_blocks', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'sort_order', b.sort_order,
          'format_slug', b.format_slug,
          'title', b.title,
          'duration_min', b.duration_min,
          'status', b.status,
          'external_guest', b.external_guest,
          'material_url', b.material_url,
          'owner_first_name', CASE
            WHEN public._agenda_block_owner_visible(
                   b.status, (b.owner_member_id = v_caller_id), v_is_admin)
              THEN split_part(bm.name, ' ', 1)
            ELSE NULL
          END,
          'is_mine', (b.owner_member_id = v_caller_id),
          -- #2593 fatia 6: mesma regra do primeiro nome do dono (PD-5)
          'copresenter_first_names', CASE
            WHEN public._agenda_block_owner_visible(
                   b.status, (b.owner_member_id = v_caller_id), v_is_admin)
              THEN public._agenda_block_copresenters_json(b.id, false)
            ELSE '[]'::jsonb
          END
        )
        || CASE WHEN v_is_admin
                THEN jsonb_build_object(
                       'owner_member_id', b.owner_member_id,
                       'owner_full_name', bm.name,
                       'guest_name', b.guest_name)
                ELSE '{}'::jsonb END
        || CASE WHEN v_is_admin
                THEN jsonb_build_object('copresenters', public._agenda_block_copresenters_json(b.id, true))
                ELSE '{}'::jsonb END
        ORDER BY b.sort_order, b.duration_min DESC)
      FROM public.event_agenda_blocks b
      JOIN public.members bm ON bm.id = b.owner_member_id
      WHERE b.event_id = p_event_id
        AND (
             (NOT v_is_past AND b.status IN ('reserved','confirmed'))
          OR (v_is_past     AND b.status IN ('confirmed','no_show'))
          OR (v_is_past AND v_is_admin AND b.status = 'reserved')
        )
    ), '[]'::jsonb),
    -- `total` e o tamanho da pauta — informacao publica na propria pagina, sem nome de ninguem.
    'agenda_blocks_total', (
      SELECT count(*) FROM public.event_agenda_blocks b WHERE b.event_id = p_event_id
    ),
    -- `pending` NAO: um bloco 'reserved' de reuniao passada e exatamente a linha que o #1071
    -- esconde do membro comum. A contagem nao tem nome, mas denuncia o que a regra de status
    -- oculta, e so quem tem manage_event pode agir sobre ela. NULL = "nao divulgado a voce";
    -- 0 seria mentira. A chave fica sempre presente (envelope estavel).
    'agenda_blocks_pending', CASE WHEN v_is_admin THEN (
      SELECT count(*) FROM public.event_agenda_blocks b
      WHERE b.event_id = p_event_id AND b.status = 'reserved' AND v_is_past
    ) ELSE NULL END,
    'expected_attendees', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id,
        'name', m.name,
        'operational_role', m.operational_role,
        'engagement_kind', ae.kind,
        'engagement_role', ae.role,
        'photo_url', m.photo_url
      ) ORDER BY m.name)
      FROM public.members m
      JOIN public.persons p ON p.legacy_member_id = m.id
      JOIN public.auth_engagements ae ON ae.person_id = p.id
      WHERE m.is_active = true
        AND ae.is_authoritative = true
        AND ae.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
    ), '[]'::jsonb),
    'pending_action_items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mai.id,
        'event_id', mai.event_id,
        'event_title', e2.title,
        'event_date', e2.date,
        'description', mai.description,
        'kind', mai.kind,
        'assignee_name', mai.assignee_name,
        'assignee_id', mai.assignee_id,
        'due_date', mai.due_date,
        'days_open', GREATEST(0, EXTRACT(DAY FROM (now() - mai.created_at))::int)
      ) ORDER BY mai.due_date NULLS LAST, mai.created_at DESC)
      FROM public.meeting_action_items mai
      JOIN public.events e2 ON e2.id = mai.event_id
      WHERE mai.resolved_at IS NULL
        AND e2.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND e2.id <> p_event_id
        AND e2.date < v_event.date
        AND mai.created_at >= (now() - interval '90 days')
    ), '[]'::jsonb),
    'open_cards', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', bi.id,
        'title', bi.title,
        'status', bi.status,
        'curation_status', bi.curation_status,
        'assignee_id', bi.assignee_id,
        'assignee_name', am.name,
        'due_date', bi.due_date,
        'forecast_date', bi.forecast_date,
        'baseline_date', bi.baseline_date,
        'days_since_update', GREATEST(0, EXTRACT(DAY FROM (now() - bi.updated_at))::int),
        'tags', bi.tags,
        'is_at_risk', (
          (bi.forecast_date IS NOT NULL AND bi.baseline_date IS NOT NULL
            AND bi.forecast_date > bi.baseline_date + INTERVAL '7 days')
          OR (bi.updated_at < now() - interval '14 days' AND bi.status NOT IN ('done', 'archived'))
        )
      ) ORDER BY
        CASE WHEN bi.status NOT IN ('done', 'archived') THEN 0 ELSE 1 END,
        bi.due_date NULLS LAST, bi.updated_at DESC)
      FROM public.board_items bi
      JOIN public.project_boards pb ON pb.id = bi.board_id
      LEFT JOIN public.members am ON am.id = bi.assignee_id
      WHERE pb.initiative_id = v_event.initiative_id
        AND v_event.initiative_id IS NOT NULL
        AND pb.is_active = true
        AND bi.status NOT IN ('archived')
      LIMIT 50
    ), '[]'::jsonb),
    -- #1548: para evento org-wide (toda Reuniao Geral) o escopo por iniciativa devolvia vazio.
    -- Sem iniciativa, "reunioes recentes" sao as do mesmo TIPO — que e o que quem prepara quer ver.
    'recent_meetings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e3.id,
        'title', e3.title,
        'date', e3.date,
        'type', e3.type,
        'has_minutes', e3.minutes_text IS NOT NULL,
        'attendance_count', (SELECT COUNT(*) FROM public.attendance a WHERE a.event_id = e3.id),
        'agenda_blocks_pending', CASE WHEN v_is_admin THEN (
          SELECT COUNT(*) FROM public.event_agenda_blocks b2
          WHERE b2.event_id = e3.id AND b2.status = 'reserved'
        ) ELSE NULL END,
        'open_actions_count', (
          SELECT COUNT(*) FROM public.meeting_action_items
          WHERE event_id = e3.id AND resolved_at IS NULL
        )
      ) ORDER BY e3.date DESC)
      FROM public.events e3
      WHERE e3.id <> p_event_id
        AND e3.date < v_event.date
        AND e3.date >= (v_event.date - interval '60 days')
        AND e3.status IS DISTINCT FROM 'cancelled'
        AND CASE
              WHEN v_event.initiative_id IS NOT NULL THEN e3.initiative_id = v_event.initiative_id
              ELSE e3.initiative_id IS NULL AND e3.type = v_event.type
            END
      LIMIT 5
    ), '[]'::jsonb),
    'generated_at', now()
  );

  RETURN v_result;
END;
$function$;


-- ── (10) os 12 blocos antigos ─────────────────────────────────────────────────────────────────────────────
-- Pares (bloco, membro) medidos em 16/10/2026 a partir do nome digitado no bloco; cada nome casa com um único membro
-- ativo. Em ordem de data da reunião, que é a ordem do XP retroativo (a primeira vez vale para o bloco mais antigo).
-- Num banco sem esses blocos (reconstrução do zero), os pares e o XP são pulados; a limpeza do nome vale sempre.
DO $backfill$
DECLARE
  v_par      record;
  v_n        int;
BEGIN
  SELECT count(*) INTO v_n FROM public.event_agenda_blocks
   WHERE id IN ('ce2156f6-d19d-4f6f-aac2-a75d79a4040c', '167eee7a-47b3-48d2-8826-a2301dfe0e70',
                'af1637e1-01f9-486c-8202-a3aea00f1f18', '007c2e53-23d6-48fe-bc7b-7c88bdd59c9a',
                '6f2d93ce-1630-4a20-a063-e9cba82f6015', '17d029a8-69d4-45ad-a5b5-1bc2827d97aa');
  IF v_n <> 6 THEN
    RAISE NOTICE '#2593 fatia 6: os 6 blocos medidos em 16/10 não estão neste banco; pares e XP retroativo pulados';
    UPDATE public.event_agenda_blocks SET guest_name = NULL WHERE NOT external_guest AND guest_name IS NOT NULL;
    RETURN;
  END IF;

  INSERT INTO public.event_agenda_block_copresenters (block_id, member_id, added_by)
  VALUES ('ce2156f6-d19d-4f6f-aac2-a75d79a4040c', '92d26057-5550-4f15-a3bf-b00eed5f32f9', NULL),
         ('167eee7a-47b3-48d2-8826-a2301dfe0e70', '598aedf9-a5a5-46fa-a26b-83fae144a2c9', NULL),
         ('af1637e1-01f9-486c-8202-a3aea00f1f18', '92d26057-5550-4f15-a3bf-b00eed5f32f9', NULL),
         ('007c2e53-23d6-48fe-bc7b-7c88bdd59c9a', 'c1ec0bcb-4ef5-41e5-8767-ab761320736f', NULL),
         ('6f2d93ce-1630-4a20-a063-e9cba82f6015', '59297c6e-f738-47e6-bf71-b4bef302dbf5', NULL),
         ('17d029a8-69d4-45ad-a5b5-1bc2827d97aa', '59297c6e-f738-47e6-bf71-b4bef302dbf5', NULL);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 6 THEN RAISE EXCEPTION '#2593 fatia 6: esperava 6 coapresentadores antigos, gravou %', v_n; END IF;

  -- o nome livre sai de todo bloco sem convidado externo (os 6 acima, 5 que repetiam o dono e 1 "Geral")
  UPDATE public.event_agenda_blocks SET guest_name = NULL
   WHERE NOT external_guest AND guest_name IS NOT NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 12 THEN RAISE EXCEPTION '#2593 fatia 6: esperava limpar 12 nomes, limpou %', v_n; END IF;

  -- XP retroativo, um bloco por vez em ordem de data
  FOR v_par IN
    SELECT c.block_id, c.member_id
      FROM public.event_agenda_block_copresenters c
      JOIN public.event_agenda_blocks b ON b.id = c.block_id
      JOIN public.events e ON e.id = b.event_id
     WHERE c.added_by IS NULL
     ORDER BY e.date, c.block_id
  LOOP
    PERFORM public._grant_agenda_block_member_xp(v_par.block_id, v_par.member_id);
  END LOOP;
END
$backfill$;

ALTER TABLE public.event_agenda_blocks DROP CONSTRAINT IF EXISTS eab_guest_name_only_external;
ALTER TABLE public.event_agenda_blocks
  ADD CONSTRAINT eab_guest_name_only_external CHECK (guest_name IS NULL OR external_guest);

NOTIFY pgrst, 'reload schema';

-- ── pós-condição ─────────────────────────────────────────────────────────────────────────────────────────
DO $postcondition$
DECLARE
  v_n   int;
  v_sum int;
BEGIN
  IF (SELECT count(*) FROM public.event_agenda_blocks WHERE guest_name IS NOT NULL AND NOT external_guest) <> 0 THEN
    RAISE EXCEPTION '#2593 fatia 6: sobrou guest_name em bloco sem convidado externo';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eab_guest_name_only_external'
                 AND conrelid = 'public.event_agenda_blocks'::regclass AND convalidated) THEN
    RAISE EXCEPTION '#2593 fatia 6: a CHECK do guest_name não ficou validada';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.event_agenda_block_copresenters'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.event_agenda_block_copresenters'::regclass)
     OR has_table_privilege('authenticated', 'public.event_agenda_block_copresenters', 'SELECT')
     OR has_table_privilege('anon', 'public.event_agenda_block_copresenters', 'SELECT') THEN
    RAISE EXCEPTION '#2593 fatia 6: a tabela de coapresentadores não ficou deny-all';
  END IF;

  -- XP retroativo: 5 créditos, 89 pontos (prévia de 16/10 com a fórmula do dono); o par sem presença fica sem crédito.
  -- Só onde o backfill rodou (o banco que tem os 6 blocos).
  IF EXISTS (SELECT 1 FROM public.event_agenda_block_copresenters WHERE added_by IS NULL) THEN
  SELECT count(*), COALESCE(SUM(gp.points), 0) INTO v_n, v_sum
    FROM public.gamification_points gp
    JOIN public.event_agenda_block_copresenters c ON c.block_id = gp.ref_id AND c.member_id = gp.member_id
   WHERE gp.category = 'agenda_block_protagonismo' AND c.added_by IS NULL;
  IF v_n <> 5 OR v_sum <> 89 THEN
    RAISE EXCEPTION '#2593 fatia 6: XP retroativo divergiu da prévia: % créditos, % pontos (esperado 5 e 89)', v_n, v_sum;
  END IF;
  -- o dono mantém o que já tinha nos 6 blocos (115 pontos medidos antes)
  SELECT COALESCE(SUM(gp.points), 0) INTO v_sum
    FROM public.gamification_points gp
    JOIN public.event_agenda_blocks b ON b.id = gp.ref_id AND b.owner_member_id = gp.member_id
   WHERE gp.category = 'agenda_block_protagonismo'
     AND b.id IN (SELECT block_id FROM public.event_agenda_block_copresenters WHERE added_by IS NULL);
  IF v_sum <> 115 THEN
    RAISE EXCEPTION '#2593 fatia 6: o crédito dos donos mudou: % (esperado 115)', v_sum;
  END IF;
  END IF;

  IF (SELECT count(*) FROM pg_proc WHERE proname = 'reserve_agenda_block' AND pronamespace = 'public'::regnamespace) <> 1
     OR (SELECT count(*) FROM pg_proc WHERE proname = 'update_agenda_block' AND pronamespace = 'public'::regnamespace) <> 1 THEN
    RAISE EXCEPTION '#2593 fatia 6: sobrou sobrecarga de reserve/update_agenda_block';
  END IF;
  IF has_function_privilege('anon', 'public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, uuid[])', 'EXECUTE')
     OR has_function_privilege('anon', 'public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, boolean, boolean, uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.reserve_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_agenda_block(uuid, text, text, integer, text, text, boolean, text, text, boolean, boolean, uuid[])', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._grant_agenda_block_member_xp(uuid, uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._grant_agenda_block_copresenters_xp(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._reverse_agenda_block_member_xp(uuid, uuid, uuid, text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public._agenda_block_copresenters_json(uuid, boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public._agenda_copresenter_ids_problem(uuid[], uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#2593 fatia 6: privilégio fora do esperado';
  END IF;
  -- a migration não tem sessão: a reserva recusa sem gravar nada
  IF (public.reserve_agenda_block(gen_random_uuid(), 'x', 'x', 5)->>'error') IS DISTINCT FROM 'not_authenticated' THEN
    RAISE EXCEPTION '#2593 fatia 6: a reserva não recusou chamada sem sessão';
  END IF;
END
$postcondition$;
