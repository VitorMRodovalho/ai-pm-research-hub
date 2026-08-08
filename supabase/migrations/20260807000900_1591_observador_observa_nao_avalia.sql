-- #1591 (2ª parte) — OBSERVADOR OBSERVA. O eixo de autoridade passa a distinguir papel.
--
-- O QUE A 1ª PARTE ERROU
-- A migration 20260807000700 criou o quarto eixo ("é do comitê de seleção") e o expôs ao menu como
-- um BOOLEANO, `selection_committee_active`. Booleano não tem como dizer *qual* papel, então
-- `evaluator` e `observer` viraram a mesma coisa em toda a superfície.
--
-- Isso passou despercebido porque o servidor já era assim: nem `submit_evaluation` nem
-- `get_my_pending_evaluations` olhavam `sc.role` — bastava estar no `selection_committee`. Medido
-- em 07/08/2026 no ciclo vivo:
--
--   papel        pessoas   avaliações submetidas
--   evaluator       3              455
--   observer        4                0
--
-- Ou seja: o comportamento estava certo por HÁBITO das pessoas, não por trava. Uma capacidade que
-- apenas não é exercida por costume não é uma regra — e o #1591 ia piorar isso, porque acabou de
-- pôr `/minhas-avaliacoes` no menu. Os 4 observadores passariam a ver a fila com botão "Avaliar".
-- Latente virava convite.
--
-- Foi o PM quem apontou a distinção, ao corrigir uma confusão minha entre o comitê de SELEÇÃO
-- (que tem observadores) e o comitê de CURADORIA de artigos, que é outro corpo e outro domínio.
--
-- A DECISÃO (PM, 07/08/2026)
-- Peer review aberto a todo o comitê, EXCETO observadores, que só visualizam.
--
-- O QUE MUDA, EM DUAS CAMADAS
--   1. `submit_evaluation` — a FRONTEIRA. Recusa `observer` com `insufficient_privilege`. O escape
--      de `manage_platform` continua, porque a correção é sobre papel no comitê, não sobre quem
--      administra a plataforma.
--   2. `get_member_by_auth` — o SINAL. `selection_committee_active` (booleano) dá lugar a
--      `selection_committee_role` ('evaluator' | 'observer' | NULL), derivado por
--      `selection_committee_role_for()`. Uma representação só: booleano + papel seriam duas
--      verdades sobre o mesmo fato, e é assim que uma envelhece.
--
-- No nav, o eixo deixa de ser `boolean` e passa a ser `'any' | 'evaluator'`:
--   `/admin/selection`   → 'any'        (acompanhar o processo é a função do observador)
--   `/minhas-avaliacoes` → 'evaluator'  (a fila é de quem pontua)
--
-- ⚠️ RESÍDUO DECLARADO: `get_my_pending_evaluations` continua listando a fila para observador que
-- chegue por URL direta. Isso é coerente com "só visualizam" e a fronteira (submissão) está
-- fechada, mas significa que um observador teimoso vê um botão que vai recusar. Não foi tratado
-- aqui de propósito: mexer no retorno da RPC muda contrato com a tela, e a decisão foi sobre quem
-- AVALIA, não sobre quem VÊ.
--
-- Como este arquivo foi produzido: alteração aplicada por substituição ancorada sobre
-- `pg_get_functiondef` (com RAISE se a âncora não casasse) e corpos extraídos do banco por script.
--
-- Refs #1591, #1590

-- ─────────────────────────────────────────────────────────────────────────────
-- O papel, como predicado derivado do domínio.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.selection_committee_role_for(p_member_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Papel da pessoa no comite de algum ciclo VIVO. `evaluator` vence `observer` quando ha os dois
  -- (alguem pode observar um ciclo e avaliar outro; a capacidade maior e a que vale).
  -- NULL = nao esta em comite nenhum vivo.
  SELECT CASE
           WHEN bool_or(sc.role = 'evaluator') THEN 'evaluator'
           WHEN count(*) > 0 THEN 'observer'
         END
  FROM public.selection_committee sc
  JOIN public.selection_cycles c ON c.id = sc.cycle_id
  WHERE sc.member_id = p_member_id
    AND (c.status = 'open' OR c.phase = 'evaluating');
$function$;

COMMENT ON FUNCTION public.selection_committee_role_for(uuid) IS
  '#1591 — papel no comite de selecao de ciclo vivo: evaluator | observer | NULL. Substitui o '
  'booleano `selection_committee_active`, que tratava observador e avaliador como a mesma coisa e '
  'por isso convidava o observador a avaliar. Observador OBSERVA (decisao do PM, 07/08/2026).';

-- `FROM PUBLIC` sozinho não fecha nada: anon e authenticated têm GRANT próprio.
REVOKE ALL ON FUNCTION public.selection_committee_role_for(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.selection_committee_role_for(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.submit_evaluation(p_application_id uuid, p_evaluation_type text, p_scores jsonb, p_notes text DEFAULT NULL::text, p_criterion_notes jsonb DEFAULT NULL::jsonb, p_ai_suggestion_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller record;
  v_app record;
  v_cycle record;
  v_committee record;
  v_criteria jsonb;
  v_criterion jsonb;
  v_key text;
  v_score numeric;
  v_weight numeric;
  v_max numeric;
  v_weighted_sum numeric := 0;
  v_eval_id uuid;
  v_total_evaluators int;
  v_submitted_count int;
  v_all_subtotals numeric[];
  v_pert_score numeric;
  v_min_sub numeric;
  v_max_sub numeric;
  v_avg_sub numeric;
  v_cutoff numeric;
  v_median numeric;
  v_new_status text;
BEGIN
  SELECT * INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Unauthorized: member not found'; END IF;

  SELECT * INTO v_app FROM public.selection_applications WHERE id = p_application_id;
  IF v_app IS NULL THEN RAISE EXCEPTION 'Application not found'; END IF;

  SELECT * INTO v_cycle FROM public.selection_cycles WHERE id = v_app.cycle_id;

  SELECT * INTO v_committee FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND member_id = v_caller.id;
  IF v_committee IS NULL AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: not a committee member';
  END IF;

  -- #1591 — OBSERVADOR OBSERVA, nao avalia.
  -- Ate aqui estar no comite bastava: nem esta funcao nem `get_my_pending_evaluations` olhavam o
  -- `role`. Na pratica os 4 observadores do ciclo vivo nunca submeteram (455 avaliacoes, TODAS de
  -- `evaluator`), entao o comportamento estava certo por HABITO das pessoas, nao por trava. Uma
  -- capacidade que so nao e exercida por costume nao e uma regra.
  -- Decisao do PM (07/08/2026): peer review aberto a todo o comite, EXCETO observadores.
  -- O escape de `manage_platform` continua, para nao mudar a autoridade de quem administra.
  IF v_committee.role = 'observer'
     AND NOT public.can_by_member(v_caller.id, 'manage_platform'::text) THEN
    RAISE EXCEPTION 'Unauthorized: observer role does not evaluate'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.selection_evaluations
    WHERE application_id = p_application_id
      AND evaluator_id = v_caller.id
      AND evaluation_type = p_evaluation_type
      AND submitted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Evaluation already submitted and locked';
  END IF;

  v_criteria := CASE p_evaluation_type
    WHEN 'objective' THEN v_cycle.objective_criteria
    WHEN 'interview' THEN v_cycle.interview_criteria
    WHEN 'leader_extra' THEN v_cycle.leader_extra_criteria
    ELSE '[]'::jsonb
  END;

  FOR v_criterion IN SELECT * FROM jsonb_array_elements(v_criteria)
  LOOP
    v_key := v_criterion ->> 'key';
    v_weight := COALESCE((v_criterion ->> 'weight')::numeric, 1);
    v_max := COALESCE((v_criterion ->> 'max')::numeric, 10);
    IF NOT (p_scores ? v_key) THEN RAISE EXCEPTION 'Missing score for criterion: %', v_key; END IF;
    v_score := (p_scores ->> v_key)::numeric;
    IF v_score IS NULL THEN RAISE EXCEPTION 'Score for % must be numeric', v_key; END IF;
    IF v_score < 0 OR v_score > v_max THEN
      RAISE EXCEPTION 'Score % for criterion "%" must be between 0 and % (schema max)', v_score, v_key, v_max;
    END IF;
    v_weighted_sum := v_weighted_sum + (v_weight * v_score);
  END LOOP;

  INSERT INTO public.selection_evaluations (
    application_id, evaluator_id, evaluation_type,
    scores, weighted_subtotal, notes, criterion_notes, submitted_at
  ) VALUES (
    p_application_id, v_caller.id, p_evaluation_type,
    p_scores, ROUND(v_weighted_sum, 2), p_notes,
    COALESCE(p_criterion_notes, '{}'::jsonb), now()
  )
  ON CONFLICT (application_id, evaluator_id, evaluation_type)
  DO UPDATE SET
    scores = EXCLUDED.scores,
    weighted_subtotal = EXCLUDED.weighted_subtotal,
    notes = EXCLUDED.notes,
    criterion_notes = EXCLUDED.criterion_notes,
    submitted_at = now()
  RETURNING id INTO v_eval_id;

  SELECT COUNT(*) INTO v_total_evaluators FROM public.selection_committee
  WHERE cycle_id = v_app.cycle_id AND role IN ('evaluator', 'lead');

  SELECT COUNT(*) INTO v_submitted_count FROM public.selection_evaluations
  WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

  IF v_submitted_count >= v_cycle.min_evaluators THEN
    SELECT ARRAY_AGG(weighted_subtotal ORDER BY weighted_subtotal) INTO v_all_subtotals
    FROM public.selection_evaluations
    WHERE application_id = p_application_id AND evaluation_type = p_evaluation_type AND submitted_at IS NOT NULL;

    v_min_sub := v_all_subtotals[1];
    v_max_sub := v_all_subtotals[array_upper(v_all_subtotals, 1)];
    SELECT AVG(unnest) INTO v_avg_sub FROM unnest(v_all_subtotals);
    v_pert_score := ROUND((2 * v_min_sub + 4 * v_avg_sub + 2 * v_max_sub) / 8, 2);

    IF p_evaluation_type = 'objective' THEN
      UPDATE public.selection_applications SET objective_score_avg = v_pert_score, updated_at = now() WHERE id = p_application_id;
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY objective_score_avg) INTO v_median
      FROM public.selection_applications WHERE cycle_id = v_app.cycle_id AND objective_score_avg IS NOT NULL;
      v_cutoff := ROUND(COALESCE(v_median, 0) * 0.75, 2);
      IF v_pert_score < v_cutoff AND v_cutoff > 0 THEN v_new_status := 'objective_cutoff'; ELSE v_new_status := 'interview_pending'; END IF;
      UPDATE public.selection_applications SET status = v_new_status, updated_at = now()
      WHERE id = p_application_id AND status IN ('submitted', 'screening', 'objective_eval');
    ELSIF p_evaluation_type = 'interview' THEN
      UPDATE public.selection_applications
        SET interview_score = v_pert_score,
            status = 'final_eval',
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    ELSIF p_evaluation_type = 'leader_extra' THEN
      UPDATE public.selection_applications
        SET leader_extra_pert_score = v_pert_score,
            updated_at = now()
      WHERE id = p_application_id;
      PERFORM public.compute_application_scores(p_application_id);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'evaluation_id', v_eval_id, 'weighted_subtotal', ROUND(v_weighted_sum, 2),
    'all_submitted', v_submitted_count >= v_cycle.min_evaluators,
    'pert_score', v_pert_score, 'new_status', v_new_status
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_member_by_auth()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_member_id uuid;
  v_existing_auth_id uuid;
  v_result json;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  -- Step 1: direct match on members.auth_id (the common case)
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_uid LIMIT 1;

  -- Step 2: match on secondary_auth_ids (admin-pre-approved alternates -> safe to rotate)
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id
      FROM public.members
     WHERE v_uid = ANY(COALESCE(secondary_auth_ids, '{}'))
     LIMIT 1;

    IF v_member_id IS NOT NULL THEN
      SELECT auth_id INTO v_existing_auth_id FROM public.members WHERE id = v_member_id;

      UPDATE public.members
         SET auth_id            = v_uid,
             secondary_auth_ids = array_append(
                                    array_remove(COALESCE(secondary_auth_ids, '{}'::uuid[]), v_uid),
                                    v_existing_auth_id
                                  ),
             updated_at         = now()
       WHERE id = v_member_id;

      -- p177 D=1 fix: sync persons.auth_id to the new primary (mirror try_auto_link_ghost).
      UPDATE public.persons
         SET auth_id = v_uid
       WHERE legacy_member_id = v_member_id
         AND (auth_id IS NULL OR auth_id <> v_uid);

      INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
      VALUES (
        v_member_id,
        'members.auth_id.rotated_secondary_to_primary',
        'member',
        v_member_id,
        jsonb_build_object(
          'promoted_auth_id', v_uid,
          'demoted_auth_id', v_existing_auth_id
        ),
        jsonb_build_object('via', 'get_member_by_auth.step2_secondary_auth_ids_match')
      );
    END IF;
  END IF;

  -- Step 3: PRIMARY email first-link (only when auth_id IS NULL -- genuine ghost first login).
  -- P168 R3-a: dropped the (a) secondary_emails match branch and (b) replace-existing-auth_id
  -- branch. Both were the mechanism behind Paulo Alves identity hijack.
  IF v_member_id IS NULL THEN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_uid;

    IF v_email IS NOT NULL THEN
      SELECT id INTO v_member_id
        FROM public.members
       WHERE lower(email) = v_email
         AND auth_id IS NULL
       LIMIT 1;

      IF v_member_id IS NOT NULL THEN
        UPDATE public.members
           SET auth_id    = v_uid,
               updated_at = now()
         WHERE id = v_member_id;

        -- p177 D=1 fix: sync persons.auth_id on first-link (mirror try_auto_link_ghost).
        UPDATE public.persons
           SET auth_id = v_uid
         WHERE legacy_member_id = v_member_id
           AND (auth_id IS NULL OR auth_id <> v_uid);

        INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, changes, metadata)
        VALUES (
          v_member_id,
          'members.auth_id.first_link',
          'member',
          v_member_id,
          jsonb_build_object(
            'linked_auth_id', v_uid,
            'matched_via',    'primary_email',
            'matched_email',  v_email
          ),
          jsonb_build_object('via', 'get_member_by_auth.step3_primary_email_when_null')
        );
      END IF;
    END IF;
  END IF;

  IF v_member_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Return JSON shape -- adds allow_precise_location_in_public_map (Cycle4 PD-MAP unified opt-in); rest UNCHANGED.
  SELECT row_to_json(q) INTO v_result FROM (
    SELECT m.id, m.name, m.email, m.secondary_emails,
      m.pmi_id, m.phone, m.operational_role, m.designations,
      compute_legacy_role(m.operational_role, m.designations)  AS role,
      compute_legacy_roles(m.operational_role, m.designations) AS roles,
      m.chapter, m.tribe_id, m.current_cycle_active, m.is_superadmin, m.is_active,
      m.member_status, m.state, m.country, m.share_whatsapp, m.signature_url,
      m.address, m.city, m.birth_date,
      m.share_address, m.share_birth_date, m.allow_state_in_public_map, m.allow_precise_location_in_public_map,
      m.privacy_consent_accepted_at, m.privacy_consent_version, m.data_last_reviewed_at,
      m.inactivated_at, m.inactivation_reason,
      m.photo_url, m.linkedin_url, m.auth_id,
      m.credly_url, m.credly_badges, m.cpmai_certified,
      m.created_at, m.updated_at,
      -- #1591: o quarto eixo de autoridade que o nav nao tinha. E DERIVADO do dominio
      -- (selection_committee x ciclo vivo), nunca uma coluna espelho mantida a mao — espelho
      -- envelhece e passa a conceder o que ja acabou.
      public.selection_committee_role_for(m.id) AS selection_committee_role
    FROM public.members m
    WHERE m.id = v_member_id
  ) q;

  RETURN v_result;
END;
$function$;
