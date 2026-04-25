-- Track Q-A Batch J — orphan recovery: triggers + legacy compute (9 fns)
--
-- Captures live bodies as-of 2026-04-25 for trigger functions + legacy
-- role/tier compute helpers. Bodies preserved verbatim from
-- `pg_get_functiondef` — no behavior change.
--
-- Phase B drift signals:
-- 1. auto_comms_card_on_publish calls create_notification with positional
--    arg order (member_id, type, ref_type, ref_id, title, by, body) which
--    differs from issue_certificate's call shape (member_id, type, title,
--    body, link, ref_type, ref_id). Two overloads coexist; pin one as
--    canonical in Phase B.
-- 2. handle_new_user writes to user_profiles (full_name, avatar_url) which
--    is a separate identity surface from members (name, photo_url). No
--    automatic ghost→member resolution; that lives elsewhere.
-- 3. compute_legacy_role / compute_legacy_roles project V4 operational_role
--    + designations into legacy single-string roles. Used by
--    admin_get_tribe_allocations + 5 other call sites; eventual deprecation
--    target post-CBGPL when consumers migrate to V4 directly.

CREATE OR REPLACE FUNCTION public.auto_comms_card_on_publish()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_comms_board_id uuid;
  v_actor_id uuid;
BEGIN
  IF NEW.curation_status = 'published' AND (OLD.curation_status IS NULL OR OLD.curation_status != 'published') THEN
    -- Find main communication board
    SELECT id INTO v_comms_board_id FROM project_boards WHERE domain_key = 'communication' AND board_name = 'Hub de Comunicação' LIMIT 1;
    IF v_comms_board_id IS NULL THEN RETURN NEW; END IF;

    SELECT id INTO v_actor_id FROM members WHERE auth_id = auth.uid();

    -- Create suggested post card
    INSERT INTO board_items (board_id, title, description, status, tags, created_by)
    VALUES (
      v_comms_board_id,
      '📢 Divulgar: ' || NEW.title,
      'Artigo/entrega publicado pela curadoria. Criar post para redes sociais.' || chr(10) || chr(10) || 'Origem: ' || NEW.title,
      'backlog',
      ARRAY['publicacao', 'sugestao-auto'],
      v_actor_id
    );

    -- Notify comms team leader
    PERFORM create_notification(
      (SELECT m.id FROM members m WHERE m.designations && ARRAY['comms_leader'] LIMIT 1),
      'comms_suggested', 'board_item', NEW.id, NEW.title, v_actor_id,
      'Novo conteudo publicado — sugestao de post criada no Hub de Comunicacao'
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_complete_first_meeting()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Only if it's the first attendance for this member
  IF NOT EXISTS (
    SELECT 1 FROM attendance a WHERE a.member_id = NEW.member_id AND a.id != NEW.id
  ) THEN
    UPDATE onboarding_progress SET status = 'completed', completed_at = now()
    WHERE member_id = NEW.member_id AND step_key = 'first_meeting' AND status != 'completed';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_detect_onboarding_completions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT m.id, 'complete_profile', 'completed', now()
  FROM members m WHERE m.is_active AND (
    (m.name IS NOT NULL AND m.name != '')::int + (m.photo_url IS NOT NULL AND m.photo_url != '')::int +
    (m.state IS NOT NULL AND m.state != '')::int + (m.country IS NOT NULL AND m.country != '')::int +
    (m.linkedin_url IS NOT NULL AND m.linkedin_url != '')::int + (m.pmi_id IS NOT NULL)::int
  ) >= 4
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT gp.member_id, 'start_trail', 'completed', now()
  FROM gamification_points gp WHERE gp.category = 'trail'
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';

  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at)
  SELECT DISTINCT a.member_id, 'first_meeting', 'completed', now()
  FROM attendance a
  ON CONFLICT (member_id, step_key) DO UPDATE SET status = 'completed', completed_at = now() WHERE onboarding_progress.status != 'completed';
END; $function$;

CREATE OR REPLACE FUNCTION public.calc_trail_completion_pct()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ROUND(COALESCE(AVG(member_pct) * 100, 0))
  FROM (
    SELECT COALESCE(COUNT(cp.id) FILTER (WHERE cp.status = 'completed'), 0)::numeric
           / 6.0 AS member_pct
    FROM public.members m
    LEFT JOIN public.course_progress cp ON cp.member_id = m.id
      AND cp.course_id IN (SELECT id FROM courses WHERE is_trail = true)
    WHERE m.current_cycle_active = true AND m.is_active = true
      AND m.operational_role NOT IN ('sponsor', 'chapter_liaison', 'observer', 'candidate', 'visitor')
    GROUP BY m.id
  ) sub;
$function$;

CREATE OR REPLACE FUNCTION public.complete_onboarding_step(p_step_id text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
  IF NOT EXISTS (SELECT 1 FROM onboarding_steps WHERE id = p_step_id) THEN
    RETURN jsonb_build_object('error', 'Invalid step'); END IF;
  INSERT INTO onboarding_progress (member_id, step_key, status, completed_at, metadata, updated_at)
  VALUES (v_member_id, p_step_id, 'completed', now(), p_metadata, now())
  ON CONFLICT (member_id, step_key) DO UPDATE SET
    status = 'completed', completed_at = now(),
    metadata = COALESCE(p_metadata, onboarding_progress.metadata), updated_at = now();
  RETURN jsonb_build_object('success', true, 'step_id', p_step_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.compute_legacy_role(p_op_role text, p_desigs text[])
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  hierarchy TEXT[] := ARRAY[
    'manager', 'deputy_manager', 'tribe_leader', 'sponsor', 'curator',
    'ambassador', 'founder', 'researcher', 'facilitator',
    'communicator'
  ];
  all_roles TEXT[];
  r TEXT;
BEGIN
  all_roles := CASE WHEN p_op_role IS NOT NULL AND p_op_role NOT IN ('none', 'guest')
    THEN ARRAY[p_op_role] ELSE '{}'::TEXT[] END;
  all_roles := all_roles || COALESCE(p_desigs, '{}'::TEXT[]);
  FOREACH r IN ARRAY hierarchy LOOP
    IF r = ANY(all_roles) THEN RETURN r; END IF;
  END LOOP;
  RETURN COALESCE(all_roles[1], 'guest');
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_legacy_roles(p_op_role text, p_desigs text[])
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  result TEXT[];
BEGIN
  result := CASE WHEN p_op_role IS NOT NULL AND p_op_role NOT IN ('none', 'guest')
    THEN ARRAY[p_op_role] ELSE '{}'::TEXT[] END;
  result := result || COALESCE(p_desigs, '{}'::TEXT[]);
  IF array_length(result, 1) IS NULL THEN
    result := ARRAY['guest'];
  END IF;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.current_member_tier_rank()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  declare
    m record;
  begin
    select is_superadmin, operational_role, coalesce(designations, '{}') as
  designations
    into m
    from public.members
    where auth_id = auth.uid()
    limit 1;

    if m is null then return 0; end if;
    if m.is_superadmin is true then return 5; end if;

    if m.operational_role in ('manager', 'deputy_manager')
       or 'co_gp' = any(m.designations) then
      return 4;
    end if;

    if m.operational_role = 'tribe_leader' then
      return 3;
    end if;

    if 'sponsor' = any(m.designations) then
      return 2;
    end if;

    if m.operational_role in ('researcher', 'facilitator', 'communicator') then
      return 1;
    end if;

    return 0;
  end;
  $function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    INSERT INTO public.user_profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture', '')
    );
    RETURN NEW;
END;
$function$;
