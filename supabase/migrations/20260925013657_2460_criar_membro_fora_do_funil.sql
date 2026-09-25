-- #2460: caminho oficial para o GP criar membro fora do funil de selecao.
--
-- Antes: a tela /admin/member/new fazia INSERT direto em members, sem persons e sem filiacao de
-- capitulo (2 membros de 27/08 ficaram sem person_id, e sem person ninguem pode ser vinculado a
-- iniciativa). Os convidados do Hackathon (24/09) entraram por DML manual, e a falta da filiacao
-- primaria derrubou a invariante U no check-invariants da #2462.
--
-- Agora, numa transacao so: persons + members (+ legacy_member_id) + filiacao primaria do capitulo
-- (via upsert_chapter_affiliation, o mesmo helper do funil) + vinculo opcional a uma iniciativa
-- (via manage_initiative_engagement, que valida autoridade e initiative_kinds_allowed) + auditoria.
-- Se o vinculo for recusado, NADA fica gravado.
CREATE OR REPLACE FUNCTION public.admin_create_member(
  p_name text,
  p_email text,
  p_chapter_code text DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL,
  p_kind text DEFAULT NULL,
  p_role text DEFAULT 'participant',
  p_reason text DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid;
  v_name text := NULLIF(btrim(p_name), '');
  v_email text := lower(NULLIF(btrim(p_email), ''));
  v_code text := NULLIF(regexp_replace(upper(btrim(coalesce(p_chapter_code, ''))), '^PMI-', ''), '');
  v_existing uuid;
  v_person_id uuid;
  v_member_id uuid;
  v_eng jsonb;
BEGIN
  SELECT m.id INTO v_caller
    FROM public.members m
   WHERE m.auth_id = auth.uid() AND m.is_active = true
   LIMIT 1;
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_caller, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_name IS NULL OR v_email IS NULL THEN
    RETURN jsonb_build_object('success', false, 'state', 'missing_fields');
  END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RETURN jsonb_build_object('success', false, 'state', 'invalid_email');
  END IF;

  -- O e-mail nao pode existir em NENHUMA das identidades: membro (principal ou secundario),
  -- pessoa (principal ou secundario) ou member_emails. Duplicar identidade e o defeito que o
  -- funil evita casando por pmi_id/e-mail (#1163); aqui o GP e avisado e decide.
  SELECT m.id INTO v_existing FROM public.members m
   WHERE lower(m.email) = v_email OR v_email = ANY (SELECT lower(x) FROM unnest(m.secondary_emails) x)
   LIMIT 1;
  IF v_existing IS NULL THEN
    SELECT me.member_id INTO v_existing FROM public.member_emails me WHERE lower(me.email) = v_email LIMIT 1;
  END IF;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'state', 'email_exists', 'member_id', v_existing);
  END IF;
  IF EXISTS (SELECT 1 FROM public.persons p
              WHERE lower(p.email) = v_email OR v_email = ANY (SELECT lower(x) FROM unnest(p.secondary_emails) x)) THEN
    RETURN jsonb_build_object('success', false, 'state', 'email_exists');
  END IF;

  IF v_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.chapter_registry cr WHERE cr.chapter_code = v_code) THEN
    RETURN jsonb_build_object('success', false, 'state', 'invalid_chapter');
  END IF;
  IF p_initiative_id IS NOT NULL AND NULLIF(btrim(coalesce(p_kind, '')), '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'state', 'missing_kind');
  END IF;

  INSERT INTO public.persons (name, email)
  VALUES (v_name, v_email)
  RETURNING id INTO v_person_id;

  INSERT INTO public.members (name, email, person_id, chapter, entry_chapter_code,
                              member_status, is_active, current_cycle_active)
  VALUES (v_name, v_email, v_person_id, COALESCE('PMI-' || v_code, 'Outro'), v_code,
          'active', true, true)
  RETURNING id INTO v_member_id;

  UPDATE public.persons SET legacy_member_id = v_member_id WHERE id = v_person_id;

  -- Filiacao primaria: sem ela a invariante U (ADR-0104) reprova todo membro de capitulo do
  -- registro. Capitulo fora do registro (Outro) fica sem filiacao, como a invariante preve.
  IF v_code IS NOT NULL THEN
    PERFORM public.upsert_chapter_affiliation(v_person_id, v_code, 'admin_import', true);
  END IF;

  IF p_initiative_id IS NOT NULL THEN
    v_eng := public.manage_initiative_engagement(p_initiative_id, v_person_id, btrim(p_kind),
                                                 COALESCE(NULLIF(btrim(p_role), ''), 'participant'), 'add');
    IF (v_eng ->> 'ok') IS DISTINCT FROM 'true' THEN
      -- Desfaz a pessoa e o membro criados acima: cadastro sem o vinculo pedido e o estado
      -- travado que esta funcao existe para evitar.
      RAISE EXCEPTION 'Vinculo recusado: %', COALESCE(v_eng ->> 'error', 'erro desconhecido')
        USING ERRCODE = 'check_violation', HINT = COALESCE(v_eng ->> 'hint', '');
    END IF;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller,
    'member.created_by_admin',
    'member',
    v_member_id,
    jsonb_build_object('person_id', v_person_id, 'chapter_code', v_code,
                       'initiative_id', p_initiative_id, 'kind', p_kind, 'role', p_role,
                       'engagement_id', v_eng ->> 'engagement_id'),
    jsonb_build_object('source', 'admin_create_member', 'issue', 2460, 'reason', p_reason)
  );

  RETURN jsonb_build_object(
    'success', true,
    'state', 'created',
    'member_id', v_member_id,
    'person_id', v_person_id,
    'engagement_id', v_eng ->> 'engagement_id'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_create_member(text, text, text, uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_member(text, text, text, uuid, text, text, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_create_member(text, text, text, uuid, text, text, text) IS
  '#2460: GP cria membro fora do funil. persons + members + filiacao primaria + vinculo opcional + auditoria, atomico. Gate manage_member.';
