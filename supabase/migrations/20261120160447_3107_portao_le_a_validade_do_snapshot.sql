-- #3107: o caminho A do portao de filiacao respeita a validade do snapshot VEP.
--
-- Fatia 2 da consolidacao dos fluxos de filiacao. Decisoes do GP (20/11/2026): o portao le a validade no snapshot VEP,
-- sem apagar a linha pmi_vep; e o caminho A le SO o snapshot (opcao b): a linha pmi_vep deixa de ser condicao.
--
-- Antes: o caminho A abria com qualquer linha member_chapter_affiliations (source = 'pmi_vep') em capitulo
-- participante. O worker pmi-vep-sync grava a linha quando o capitulo aparece em pmi_memberships e nunca a remove; a
-- tabela nao tem validade. Medido em 20/11/2026: 2 voluntarios com o portao aberto pelo caminho A cujo snapshot VEP mais
-- recente nao mostra filiacao ativa (bucket not_affiliated). E o inverso: 2 com o portao fechado ('unknown') cujo
-- snapshot mostra filiacao ativa em capitulo participante, porque a linha deles era 'legacy', nao 'pmi_vep'.
--
-- Agora: o caminho A le os capitulos participantes (chapter_registry ativo) que estao em active_br_codes do snapshot
-- VEP mais recente da pessoa. classify_entry_chapter ja descarta filiacao vencida e e a mesma funcao que o diagnostico
-- da pessoa (get_my_entry_chapter_diagnosis) e a aprovacao leem. A linha member_chapter_affiliations nao e lida pelo
-- portao: quem decide e o dado da VEP. Snapshot = a candidatura mais recente com
-- pmi_data_fetched_at, pelo e-mail principal e pelos e-mails secundarios da pessoa. Sem snapshot, o caminho A nao
-- valida (em 20/11/2026, 0 dos 76 caminhos A abertos estavam sem snapshot). O motivo do portao fechado passa a sair do
-- mesmo snapshot.
--
-- A linha pmi_vep nao e apagada: ela alimenta members.chapter e a invariante U (ADR-0104, 3b-ii). Ao assinar pelo
-- caminho A, o termo segue gravando a afiliacao primaria com source pmi_vep (sign_volunteer_agreement nao muda), o que
-- corrige a linha 'legacy' de quem entra assim. O caminho B (verificacao manual vigente) nao muda. Renovacao continua fora do portao (affiliation_gate_first_term).
--
-- 1) affiliation_vep_snapshot(member_id): a selecao do snapshot num lugar so. O portao, o radar de vencimento (#3108)
--    e o aviso de "nao filiado" (#3109) leem esta funcao, em vez de copiar a selecao.
-- 2) affiliation_gate: corpo = captura 20261008032910 (md5 do corpo normalizado conferido contra o vivo em
--    20/11/2026), com o snapshot lido uma vez no inicio e usado no caminho A e no motivo.
--
-- Rollback: recriar affiliation_gate pela captura 20261008032910 e DROP FUNCTION public.affiliation_vep_snapshot(uuid).

-- 1) o snapshot VEP mais recente da pessoa, num lugar so
CREATE OR REPLACE FUNCTION public.affiliation_vep_snapshot(p_member_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- A candidatura mais recente COM dado da VEP (pmi_data_fetched_at), pelo e-mail principal e pelos secundarios,
  -- classificada pela mesma funcao do diagnostico da pessoa. NULL quando nao ha snapshot.
  SELECT jsonb_build_object('pmi_memberships', sa.pmi_memberships, 'fetched_at', sa.pmi_data_fetched_at)
         || public.classify_entry_chapter(sa.pmi_memberships, sa.community_profile_private, sa.pmi_data_fetched_at)
  FROM public.members m
  JOIN public.selection_applications sa
    ON sa.pmi_data_fetched_at IS NOT NULL
   AND (lower(sa.email) = lower(m.email)
        OR lower(sa.email) IN (SELECT lower(me.email) FROM public.member_emails me WHERE me.member_id = m.id))
  WHERE m.id = p_member_id
  ORDER BY sa.pmi_data_fetched_at DESC
  LIMIT 1;
$function$;

-- Interna: le dado de filiacao de qualquer pessoa. So as funcoes SECURITY DEFINER a chamam.
REVOKE ALL ON FUNCTION public.affiliation_vep_snapshot(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_vep_snapshot(uuid) TO service_role;

-- 2) o portao
CREATE OR REPLACE FUNCTION public.affiliation_gate(p_member_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_person_id uuid;
  v_email text;
  v_entry text;
  v_vep text[];
  v_manual text;
  v_snapshot jsonb;
BEGIN
  SELECT m.person_id, m.email, m.entry_chapter_code INTO v_person_id, v_email, v_entry
  FROM public.members m WHERE m.id = p_member_id;
  IF v_person_id IS NULL THEN
    RETURN jsonb_build_object('open', false, 'reason', 'unknown');
  END IF;

  -- #3107: o snapshot VEP mais recente da pessoa. Vale para o caminho A e para o motivo.
  v_snapshot := public.affiliation_vep_snapshot(p_member_id);

  -- caminho A: capitulos participantes que o snapshot VEP mais recente mostra com filiacao ativa
  SELECT array_agg(cr.chapter_code ORDER BY cr.chapter_code) INTO v_vep
  FROM public.chapter_registry cr
  WHERE cr.is_active
    AND COALESCE(v_snapshot -> 'active_br_codes', '[]'::jsonb) ? cr.chapter_code;

  IF v_vep IS NOT NULL THEN
    IF array_length(v_vep, 1) > 1 AND (v_entry IS NULL OR NOT v_entry = ANY(v_vep)) THEN
      RETURN jsonb_build_object('open', false, 'reason', 'entry_chapter_required', 'chapters', to_jsonb(v_vep));
    END IF;
    RETURN jsonb_build_object('open', true, 'path', 'vep',
      'chapter', CASE WHEN v_entry = ANY(v_vep) THEN v_entry ELSE v_vep[1] END);
  END IF;

  -- caminho B, o ultimo ELSE: verificacao manual vigente em capitulo participante
  SELECT regexp_replace(v.chapter_verified, '^PMI-', '') INTO v_manual
  FROM public.member_affiliation_verifications v
  JOIN public.chapter_registry cr ON cr.chapter_code = regexp_replace(v.chapter_verified, '^PMI-', '') AND cr.is_active
  WHERE v.member_id = p_member_id
    AND v.membership_active
    AND (v.membership_expires_on IS NULL OR v.membership_expires_on > CURRENT_DATE)
    AND v.method IN ('vep_sync', 'sede_manual')
  ORDER BY v.created_at DESC
  LIMIT 1;

  IF v_manual IS NOT NULL THEN
    RETURN jsonb_build_object('open', true, 'path', 'manual', 'chapter', v_manual);
  END IF;

  -- fechado: so explica o motivo, com o mesmo snapshot (nunca abre o portao)
  RETURN jsonb_build_object('open', false,
    'reason', CASE WHEN v_snapshot ->> 'bucket' = 'not_affiliated' THEN 'not_affiliated' ELSE 'unknown' END);
END;
$function$;

-- pos-condicao: as duas funcoes continuam internas
DO $postcondition$
BEGIN
  IF has_function_privilege('authenticated', 'public.affiliation_gate(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.affiliation_gate(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_vep_snapshot(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.affiliation_vep_snapshot(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3107: funcao de filiacao ficou executavel por anon ou authenticated';
  END IF;
END
$postcondition$;
