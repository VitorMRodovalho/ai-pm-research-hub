-- #1682 — o ledger de consentimento é escrito por `application_id` e lido por `member_id`.
--
-- `consent_records` tem 56 linhas (medido 08/08/2026), todas com `application_id` e NENHUMA com
-- `member_id`. O bloco `consent_records` do `export_my_data` filtra por `member_id`, então a
-- exportação do art. 18 II devolve `[]` para 100% dos titulares, com o ledger cheio. Não é
-- latente: 34 dessas linhas (33 pessoas distintas) são de quem já é membro hoje.
--
-- A ponte que resolve isso já existia 20 linhas acima, no MESMO corpo: o bloco
-- `selection_applications` resolve a candidatura por e-mail, com o UNION de `member_emails` que
-- existe justamente porque o e-mail da candidatura pode não ser o do cadastro. O bloco do ledger
-- não a usava.
--
-- Aqui essa ponte deixa de ser um trecho colado num lugar só e vira `v_emails`, resolvida UMA vez
-- e usada nos dois blocos — a mesma pergunta passa a ter uma resposta só dentro da função.
--
-- ⚠️ Recorte medido, e menor do que a issue supunha. A issue afirmava que
-- `privacy_consent_accepted_at` (88), `consent_voice_biometric_at` (32) e
-- `persons.consent_status` (9) também ficavam de fora. Os três JÁ SAEM: `profile`, `person` e
-- `selection_applications` são montados com `row_to_json()`, que carrega a coluna sem que o
-- corpo da função a mencione. A issue grepou o TEXTO da função; a medição observou o
-- COMPORTAMENTO (export impersonado, 08/08/2026: `privacy_consent_version` = "v1.0",
-- `consent_voice_biometric_evidence` = `{lang, version, label_text_hash}`, `consent_status` =
-- "accepted", e `consent_records` = 0). Só o ledger estava quebrado, e é só ele que muda aqui.
--
-- Refs #1682, #1666, #1643

CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_emails text[];
  v_result jsonb;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_person_id FROM public.persons WHERE legacy_member_id = v_member_id;

  -- #1682: os e-mails do titular, resolvidos UMA vez. O cadastro e a candidatura podem ter
  -- chegado por endereços diferentes, e o ledger de consentimento é endereçado pela candidatura.
  -- COALESCE porque um titular sem e-mail algum deve alcançar ZERO candidaturas, não todas.
  SELECT COALESCE(array_agg(DISTINCT s.e), ARRAY[]::text[]) INTO v_emails
  FROM (
    SELECT lower(trim(m.email::text))  AS e FROM public.members m        WHERE m.id = v_member_id         AND m.email IS NOT NULL
    UNION
    SELECT lower(trim(me.email::text))      FROM public.member_emails me WHERE me.member_id = v_member_id AND me.email IS NOT NULL
  ) s;

  SELECT jsonb_build_object(
    'profile', (SELECT row_to_json(m)::jsonb FROM public.members m WHERE m.id = v_member_id),
    'person', CASE WHEN v_person_id IS NOT NULL THEN
      (SELECT row_to_json(p)::jsonb FROM public.persons p WHERE p.id = v_person_id)
    ELSE NULL END,
    'engagements', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'role', e.role, 'status', e.status,
        'initiative_name', i.title, 'start_date', e.start_date, 'end_date', e.end_date,
        'legal_basis', e.legal_basis, 'has_agreement', (e.agreement_certificate_id IS NOT NULL),
        'granted_at', e.granted_at, 'revoked_at', e.revoked_at, 'revoke_reason', e.revoke_reason
      ) ORDER BY e.start_date DESC)
      FROM public.engagements e LEFT JOIN public.initiatives i ON i.id = e.initiative_id
      WHERE e.person_id = v_person_id
    ), '[]'::jsonb),
    'attendance', COALESCE((SELECT jsonb_agg(row_to_json(a)::jsonb) FROM public.attendance a WHERE a.member_id = v_member_id), '[]'::jsonb),
    'gamification', COALESCE((SELECT jsonb_agg(row_to_json(g)::jsonb) FROM public.gamification_points g WHERE g.member_id = v_member_id), '[]'::jsonb),
    'notifications', COALESCE((SELECT jsonb_agg(row_to_json(n)::jsonb) FROM public.notifications n WHERE n.recipient_id = v_member_id), '[]'::jsonb),
    'board_assignments', COALESCE((SELECT jsonb_agg(row_to_json(ba)::jsonb) FROM public.board_item_assignments ba WHERE ba.member_id = v_member_id), '[]'::jsonb),
    'cycle_history', COALESCE((SELECT jsonb_agg(row_to_json(mch)::jsonb) FROM public.member_cycle_history mch WHERE mch.member_id = v_member_id), '[]'::jsonb),
    'certificates', COALESCE((SELECT jsonb_agg(row_to_json(c)::jsonb) FROM public.certificates c WHERE c.member_id = v_member_id), '[]'::jsonb),
    'selection_applications', COALESCE((
      SELECT jsonb_agg(row_to_json(sa)::jsonb)
      FROM public.selection_applications sa
      WHERE lower(trim(sa.email)) = ANY (v_emails)
    ), '[]'::jsonb),
    'onboarding', COALESCE((SELECT jsonb_agg(row_to_json(op)::jsonb) FROM public.onboarding_progress op WHERE op.member_id = v_member_id), '[]'::jsonb),
    -- #1682: o ledger alcança o titular por member_id OU pela candidatura que é dele. Enquanto
    -- `give_consent_via_token` não carimbar o member_id no ato do aceite, a segunda perna é o
    -- único caminho; depois dela, vira o fallback de quem consentiu antes do carimbo existir.
    'consent_records', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id,
        'policy_type', cr.policy_type,
        'policy_version', cr.policy_version,
        'policy_document_id', cr.policy_document_id,
        'accepted_at', cr.accepted_at,
        'channel', cr.channel,
        'email_hash', cr.email_hash,
        'ip_hash', cr.ip_hash,
        'user_agent_hash', cr.user_agent_hash,
        'revoked_at', cr.revoked_at,
        'revocation_reason', cr.revocation_reason,
        'is_active', (cr.revoked_at IS NULL),
        'created_at', cr.created_at,
        -- #1682: a origem do vínculo e a prova. `evidence` NULL não é omissão — é o registro de
        -- que o aceite chegou sem prova do texto exibido (ver `unversioned` em #1666).
        'application_id', cr.application_id,
        'linked_by', CASE WHEN cr.member_id = v_member_id THEN 'member_id' ELSE 'application_email' END,
        'evidence', cr.evidence
      ) ORDER BY cr.accepted_at DESC)
      FROM public.consent_records cr
      WHERE cr.member_id = v_member_id
         OR cr.application_id IN (
              SELECT sa.id FROM public.selection_applications sa
              WHERE lower(trim(sa.email)) = ANY (v_emails)
            )
    ), '[]'::jsonb),
    -- #569 S4c (ADR-0101 deferred L57): the declarant's PI-exclusion registry — LGPD Art. 18 II
    -- portability. Digest/status/anchor METADATA only; the .ots bytea is not inlined (binary
    -- proof artifact — export it via export_anexo_i por declaration_id), its PRESENCE is
    -- flagged per asset. eficacia_plena (doc7 Cl.4.1) = ALL assets confirmed — surfaced per
    -- declaration so the titular never mis-reads 'pending' as already-efficacious (legal fold).
    'pi_exclusion', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'declaration_id', d.id,
        'title', d.title,
        'status', d.status,
        'created_at', d.created_at,
        'updated_at', d.updated_at,
        'revoked_at', d.revoked_at,
        'total_assets', (SELECT count(*) FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id),
        'confirmed_assets', (SELECT count(*) FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id AND a.ots_status = 'confirmed'),
        'eficacia_plena', COALESCE((
          SELECT bool_and(a.ots_status = 'confirmed') AND count(*) > 0
          FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
        ), false),
        'assets', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'seq', a.seq,
            'titulo', a.title,
            'natureza', a.nature,
            'autor_capitulo', a.author_label,
            'data_criacao', a.work_created_on,
            'caminho_url', a.source_ref,
            'sha256', a.sha256,
            'status', a.ots_status,
            'prova_ots', (a.ots_proof IS NOT NULL),
            'ancoragem', CASE WHEN a.ots_status = 'confirmed'
              THEN jsonb_build_object('bloco', a.bitcoin_block, 'utc', a.attested_at) ELSE NULL END
          ) ORDER BY a.seq)
          FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
        ), '[]'::jsonb)
      ) ORDER BY d.created_at DESC)
      FROM public.pi_exclusion_declarations d WHERE d.declarant_member_id = v_member_id
    ), '[]'::jsonb),
    -- #625 F1: verificações de filiação do titular (Art. 18 II; inclui verification_obs = dado de terceiro sobre o titular)
    'affiliation_verifications', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', mav.id,
        'chapter_verified', mav.chapter_verified,
        'membership_active', mav.membership_active,
        'membership_expires_on', mav.membership_expires_on,
        'method', mav.method,
        'verification_obs', mav.verification_obs,
        'verified_by_name', COALESCE(vb.name, 'Verificador não disponível'),  -- #625: contexto p/ Art. 18 III
        'created_at', mav.created_at
      ) ORDER BY mav.created_at DESC)
      FROM public.member_affiliation_verifications mav
      LEFT JOIN public.members vb ON vb.id = mav.verified_by_member_id
      WHERE mav.member_id = v_member_id
    ), '[]'::jsonb),
    'exported_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$function$;
