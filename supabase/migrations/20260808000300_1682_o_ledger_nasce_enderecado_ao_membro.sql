-- #1682 — o ledger de consentimento passa a nascer endereçado ao membro.
--
-- O #1666 criou o ledger escrevendo só `application_id`. As duas superfícies de leitura do
-- titular filtravam por `member_id`, e as migrations 20260808000100 / 20260808000200 as
-- ensinaram a alcançar o ledger pela candidatura. Isso conserta a LEITURA de quem já consentiu.
--
-- Esta migration conserta a ESCRITA, para que a ponte por e-mail seja o fallback de um período
-- histórico e não a arquitetura permanente: quando a candidatura já corresponde a um membro, o
-- vínculo é carimbado no ato do aceite. Um índice por `member_id` volta a significar alguma
-- coisa, e uma troca futura de e-mail deixa de poder desligar o titular do próprio consentimento.
--
-- ⚠️ NÃO faz backfill das 56 linhas existentes. O ledger é imutável por desenho (#1666: um
-- re-aceite depois de revogar é linha NOVA, nunca UPDATE), e reescrever registros de
-- consentimento já emitidos para melhorar a ergonomia de leitura é exatamente o movimento que
-- o próprio #1666 recusou ao gravar `unversioned` em vez de inventar uma versão. A leitura já
-- alcança as 34 linhas pela ponte; o carimbo vale da próxima em diante.
--
-- Refs #1682, #1666

CREATE OR REPLACE FUNCTION public.give_consent_via_token(p_token text, p_consent_type text DEFAULT 'ai_analysis'::text, p_evidence jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
  v_consent_at timestamptz;
  v_evidence_text text;
  v_consent_record_id uuid;   -- #1666
  v_policy_version text;      -- #1666
  v_member_id uuid;           -- #1682
BEGIN
  SELECT * INTO v_token_row
  FROM onboarding_tokens
  WHERE token = p_token
    AND expires_at > now()
    AND 'consent_giving' = ANY(scopes);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid token or missing consent_giving scope'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_token_row.source_type <> 'pmi_application' THEN
    RAISE EXCEPTION 'Token source_type % does not support consent giving', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_consent_type NOT IN ('ai_analysis', 'voice_biometric') THEN
    RAISE EXCEPTION 'Unsupported consent type: % (supported: ai_analysis, voice_biometric)', p_consent_type;
  END IF;

  IF p_consent_type = 'voice_biometric' THEN
    -- LGPD Art. 11 §I sensitive: evidence (version+lang+label_text_hash) MUST
    -- be supplied so we can later prove the candidate saw the destacado label.
    IF p_evidence IS NULL
       OR (p_evidence ->> 'version') IS NULL
       OR (p_evidence ->> 'lang') IS NULL
       OR (p_evidence ->> 'label_text_hash') IS NULL THEN
      RAISE EXCEPTION 'voice_biometric consent requires p_evidence jsonb with version + lang + label_text_hash'
        USING HINT = 'Compute SHA-256 of the displayed destacado label and submit it as label_text_hash.';
    END IF;
    v_evidence_text := p_evidence::text;

    UPDATE selection_applications
       SET consent_voice_biometric_at = COALESCE(consent_voice_biometric_at, now()),
           consent_voice_biometric_revoked_at = NULL,
           consent_voice_biometric_evidence = COALESCE(consent_voice_biometric_evidence, v_evidence_text),
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_consent_at := v_app.consent_voice_biometric_at;
  ELSE
    UPDATE selection_applications
       SET consent_ai_analysis_at = COALESCE(consent_ai_analysis_at, now()),
           consent_ai_analysis_revoked_at = NULL,
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_consent_at := v_app.consent_ai_analysis_at;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  -- ── #1666: o ledger auditável ──────────────────────────────────────────────
  -- Só para `ai_analysis`: o CHECK de `policy_type` não prevê voz, e a voz já guarda a prova na
  -- própria coluna. Ver o cabeçalho.
  IF p_consent_type = 'ai_analysis' THEN
    -- `unversioned` NÃO é enfeite: é o registro de que o aceite chegou sem prova do texto
    -- exibido. Um default silencioso ('v2', por exemplo) transformaria ausência de evidência em
    -- afirmação falsa sobre qual redação a pessoa viu.
    v_policy_version := COALESCE(NULLIF(p_evidence ->> 'version', ''), 'unversioned');

    -- #1682: o ledger nasce endereçado ao membro quando a candidatura JÁ é de um membro, para
    -- que a ponte por e-mail do `export_my_data`/`list_my_consents` volte a ser o fallback
    -- histórico que ela deveria ter sido, e não o único caminho até o titular.
    --
    -- Só carimba quando a resolução é INEQUÍVOCA (exatamente um membro). Dois membros com o
    -- mesmo endereço é um defeito de identidade, e escolher um deles aqui registraria o
    -- consentimento de uma pessoa na conta de outra — nenhum vínculo é melhor do que o vínculo
    -- errado, porque a ponte por e-mail continua alcançando ambos na leitura.
    WITH cand AS (
      SELECT m.id AS member_id
        FROM public.members m
       WHERE m.email IS NOT NULL
         AND lower(trim(m.email::text)) = lower(trim(v_app.email))
      UNION
      SELECT me.member_id
        FROM public.member_emails me
       WHERE me.email IS NOT NULL
         AND lower(trim(me.email::text)) = lower(trim(v_app.email))
    )
    SELECT c.member_id INTO v_member_id
      FROM cand c
     WHERE (SELECT count(*) FROM cand) = 1;

    -- Idempotente: um aceite ATIVO já registrado é reaproveitado, nunca duplicado. Um re-aceite
    -- depois de revogar é linha NOVA (o ledger é imutável), espelhando `grant_image_voice_consent`.
    SELECT cr.id INTO v_consent_record_id
    FROM public.consent_records cr
    WHERE cr.application_id = v_application_id
      AND cr.policy_type = 'ai_analysis'
      AND cr.revoked_at IS NULL
    ORDER BY cr.accepted_at DESC
    LIMIT 1;

    IF v_consent_record_id IS NULL THEN
      INSERT INTO public.consent_records (
        member_id, application_id, policy_type, policy_version, accepted_at, channel,
        evidence, organization_id
      ) VALUES (
        v_member_id,
        v_application_id,
        'ai_analysis',
        v_policy_version,
        -- o carimbo da candidatura, não `now()`: um re-clique não pode reescrever a data do
        -- aceite original (o UPDATE acima usa COALESCE exatamente por isso).
        v_consent_at,
        'email_link',
        p_evidence,
        v_app.organization_id
      )
      RETURNING id INTO v_consent_record_id;
    END IF;

    -- A ponte de volta, que já existia no schema e nunca era preenchida.
    UPDATE selection_applications
       SET consent_record_id = v_consent_record_id
     WHERE id = v_application_id
       AND consent_record_id IS DISTINCT FROM v_consent_record_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'consent_at', v_consent_at,
    'has_consent', true,
    'has_revoked', false,
    'consent_record_id', v_consent_record_id,        -- #1666
    'policy_version', v_policy_version,              -- #1666
    'evidence_captured', (p_evidence IS NOT NULL),   -- #1666: a lacuna vira observável
    'member_linked', (v_member_id IS NOT NULL)       -- #1682: idem, para o vínculo
  );
END;
$function$;
