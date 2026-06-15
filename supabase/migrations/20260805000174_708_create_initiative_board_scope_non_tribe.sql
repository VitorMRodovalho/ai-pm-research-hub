-- #708 — create_initiative falhava ao provisionar o board para kinds NÃO-tribo.
--
-- ROOT CAUSE: o INSERT em project_boards dentro de create_initiative NÃO setava
-- board_scope → default 'tribe'. O trigger enforce_project_board_taxonomy() exige
-- que board 'tribe' aponte para uma iniciativa tribe-scoped (legacy_tribe_id NOT
-- NULL). Kinds não-tribo (congress/committee/workgroup/book_club/study_group, todos
-- has_board=true) não têm legacy_tribe_id → o trigger sempre dispara
-- ('Tribe boards require initiative_id pointing to tribe-scoped initiative') e a
-- criação via /admin/portfolio quebra.
--
-- FIX: após inserir a iniciativa, derivar board_scope da tribe-scoping real:
--   tribe-scoped (legacy_tribe_id NOT NULL) → board_scope='tribe' (domain_key não
--     exigido pelo trigger);
--   não-tribo → board_scope='global' + domain_key (exigido p/ board global). O
--     domain_key vem de metadata.domain_key se o caller passar, senão cai num bucket
--     genérico 'cross_functional' (recategorizável depois no admin).
-- Sem mudança de assinatura (o caller frontend `create_initiative` continua igual;
-- domain_key é opcional via metadata).
--
-- ROLLBACK: re-aplicar o corpo anterior (board insert sem board_scope/domain_key —
-- bugado p/ não-tribo).

CREATE OR REPLACE FUNCTION public.create_initiative(
  p_kind text,
  p_title text,
  p_description text DEFAULT NULL::text,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_parent_initiative_id uuid DEFAULT NULL::uuid
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_kind_row record;
  v_count integer;
  v_new_id uuid;
  v_legacy_tribe_id int;
  v_board_scope text;
  v_domain_key text;
BEGIN
  SELECT * INTO v_kind_row FROM public.initiative_kinds WHERE slug = p_kind;
  IF v_kind_row IS NULL THEN
    RAISE EXCEPTION 'Unknown initiative kind: %', p_kind USING ERRCODE = 'P0004';
  END IF;

  -- #708: research_tribe é tribe-scoped — precisa do bridge legacy_tribe_id (via
  -- admin_upsert_legacy_tribe). create_initiative nunca seta legacy_tribe_id, então
  -- criar uma tribo por aqui produziria uma tribo SEM legacy_tribe_id, cujo board
  -- nem 'tribe' (trigger exige legacy_tribe_id) nem 'global' (scope errado p/ tribo)
  -- é válido. Fail-loud em vez de criar uma tribo meia-quebrada.
  IF p_kind = 'research_tribe' THEN
    RAISE EXCEPTION 'research_tribe deve ser criada via o bridge de tribo (admin_upsert_legacy_tribe), não create_initiative'
      USING ERRCODE = 'P0006';
  END IF;

  IF v_kind_row.max_concurrent_per_org IS NOT NULL THEN
    SELECT count(*) INTO v_count
    FROM public.initiatives
    WHERE kind = p_kind
      AND organization_id = public.auth_org()
      AND status IN ('draft', 'active');

    IF v_count >= v_kind_row.max_concurrent_per_org THEN
      RAISE EXCEPTION 'Maximum concurrent initiatives of kind "%" reached (limit: %)',
        p_kind, v_kind_row.max_concurrent_per_org USING ERRCODE = 'P0005';
    END IF;
  END IF;

  INSERT INTO public.initiatives (kind, title, description, metadata, parent_initiative_id, organization_id)
  VALUES (p_kind, p_title, p_description, p_metadata, p_parent_initiative_id, public.auth_org())
  RETURNING id INTO v_new_id;

  IF v_kind_row.has_board THEN
    -- #708: derivar board_scope da tribe-scoping real (um dual-write trigger pode ter
    -- setado legacy_tribe_id para kinds de tribo). Antes ficava no default 'tribe' e o
    -- trigger de taxonomy rejeitava todo board de kind não-tribo.
    SELECT legacy_tribe_id INTO v_legacy_tribe_id FROM public.initiatives WHERE id = v_new_id;
    IF v_legacy_tribe_id IS NOT NULL THEN
      v_board_scope := 'tribe';
      v_domain_key  := nullif(p_metadata->>'domain_key', '');
    ELSE
      v_board_scope := 'global';
      v_domain_key  := coalesce(nullif(p_metadata->>'domain_key', ''), 'cross_functional');
    END IF;

    INSERT INTO public.project_boards (board_name, initiative_id, source, is_active, organization_id, board_scope, domain_key)
    VALUES (p_title, v_new_id, 'manual', true, public.auth_org(), v_board_scope, v_domain_key);
  END IF;

  RETURN v_new_id;
END;
$function$;

-- self-containment (CREATE OR REPLACE preserva grants, mas a migration deve ser completa)
GRANT EXECUTE ON FUNCTION public.create_initiative(text, text, text, jsonb, uuid) TO authenticated;
