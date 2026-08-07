-- #1666 — o consentimento de IA era gravado como carimbo, sem dizer COM O QUE a pessoa concordou.
--
-- O FATO, MEDIDO EM 07/08/2026
-- `give_consent_via_token` trata dois consentimentos de forma desigual:
--
--   consentimento          o que a função exige                        titulares  com evidência
--   voice_biometric        p_evidence (version+lang+label_text_hash),      32          32
--                          sob RAISE se faltar
--   ai_analysis            nada além do token; grava só o timestamp        56           0
--
-- O ramo de voz até comenta o porquê: "MUST be supplied so we can later prove the candidate saw
-- the destacado label". O ramo de IA faz `UPDATE ... SET consent_ai_analysis_at = COALESCE(...)`
-- e mais nada.
--
-- Ficou concreto agora porque o #1642 REESCREVEU o texto do consentimento nos 3 idiomas: os 56
-- que já consentiram concordaram com uma redação que não existe mais, e não há registro de qual
-- era. O art. 8º, §2º põe no controlador o ônus de provar que o consentimento foi obtido em
-- conformidade, e provar isso exige poder dizer com o que o titular concordou.
--
-- A ARQUITETURA JÁ EXISTIA E NUNCA FOI LIGADA
-- `consent_records` (p107) foi desenhada exatamente para isto e está **vazia** (0 linhas, para
-- todos os tipos):
--   - `policy_type` CHECK já inclui `'ai_analysis'`
--   - `application_id` referencia `selection_applications`
--   - `selection_applications.consent_record_id` já aponta de volta
--   - RLS é RPC-only (anon/authenticated sem INSERT/UPDATE/DELETE), então SECDEF escreve
--
-- Faltava uma coluna para a prova e faltava a escrita. É o que esta migration faz.
--
-- ⚠️ SEM JANELA CONTRA O CÓDIGO DEPLOYADO
-- `p_evidence` JÁ existe na assinatura (default NULL). Então o front pode passar a enviá-la sem
-- nenhuma mudança de contrato, e esta função a REGISTRA quando vier, sem exigi-la ainda. Exigir
-- agora recusaria o consentimento de quem estivesse com o bundle antigo em cache — negar a
-- alguém o ato de consentir é pior, sob a mesma lei, do que registrar um consentimento sem hash.
-- O aperto (RAISE quando faltar, como no ramo de voz) é o passo seguinte, depois de confirmado
-- que o front novo está no ar.
--
-- Para que a lacuna não vire invisível nesse meio-tempo, a ausência de evidência é REGISTRADA
-- (`policy_version = 'unversioned'`), e não silenciada.
--
-- BACKFILL DOS 56 — SEM INVENTAR PROVA
-- Os consentimentos anteriores entram no ledger com `policy_version = 'v1-pre-1642'` e
-- `evidence = NULL`. Não existe hash do texto que aquelas pessoas viram, e fabricar um seria
-- exatamente a falsificação de auditoria que o registro deveria impedir. `channel='email_link'`
-- porque foi por token; `accepted_at` preserva o carimbo original.
--
-- FORA DE ESCOPO, DECLARADO: o consentimento de voz continua guardando a evidência na coluna
-- `consent_voice_biometric_evidence` e NÃO entra no ledger aqui — o `policy_type` CHECK não o
-- prevê, e ele não está quebrado (32 de 32 têm prova). Consolidar os dois no ledger é trabalho
-- próprio, não carona nesta correção.
--
-- Refs #1666, #1642, #1632

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. A coluna que faltava: a prova do que foi exibido.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.consent_records
  ADD COLUMN IF NOT EXISTS evidence jsonb;

COMMENT ON COLUMN public.consent_records.evidence IS
  '#1666 — prova do que foi EXIBIDO ao titular no momento do aceite: {version, lang, label_text_hash}. '
  'NULL significa que a evidência não foi capturada (aceites anteriores ao #1666), e essa ausência é '
  'informação legítima: NUNCA preencher com hash reconstruído a posteriori, porque o texto pode ter '
  'mudado desde então (foi o que o #1642 fez).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Conceder passa a escrever no ledger.
-- ─────────────────────────────────────────────────────────────────────────────
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
        application_id, policy_type, policy_version, accepted_at, channel,
        evidence, organization_id
      ) VALUES (
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
    'evidence_captured', (p_evidence IS NOT NULL)    -- #1666: a lacuna vira observável
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Revogar passa a fechar a linha do ledger.
--    Sem isto o ledger afirmaria consentimento ATIVO para quem revogou — pior que não ter ledger.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_consent_via_token(p_token text, p_consent_type text DEFAULT 'ai_analysis'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_token_row onboarding_tokens%ROWTYPE;
  v_application_id uuid;
  v_app selection_applications%ROWTYPE;
  v_revoked_at timestamptz;
  v_ledger_fechadas int := 0;   -- #1666
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
    RAISE EXCEPTION 'Token source_type % does not support consent revocation', v_token_row.source_type;
  END IF;

  v_application_id := v_token_row.source_id;

  IF p_consent_type NOT IN ('ai_analysis', 'voice_biometric') THEN
    RAISE EXCEPTION 'Unsupported consent type: % (supported: ai_analysis, voice_biometric)', p_consent_type;
  END IF;

  IF p_consent_type = 'voice_biometric' THEN
    UPDATE selection_applications
       SET consent_voice_biometric_revoked_at = COALESCE(consent_voice_biometric_revoked_at, now()),
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_revoked_at := v_app.consent_voice_biometric_revoked_at;
  ELSE
    UPDATE selection_applications
       SET consent_ai_analysis_revoked_at = COALESCE(consent_ai_analysis_revoked_at, now()),
           updated_at = now()
     WHERE id = v_application_id
    RETURNING * INTO v_app;

    v_revoked_at := v_app.consent_ai_analysis_revoked_at;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Token references missing application';
  END IF;

  -- ── #1666: fechar a linha do ledger ────────────────────────────────────────
  IF p_consent_type = 'ai_analysis' THEN
    WITH fechadas AS (
      UPDATE public.consent_records cr
         SET revoked_at = v_revoked_at,
             revocation_reason = COALESCE(cr.revocation_reason, 'candidate self-service revocation via token')
       WHERE cr.application_id = v_application_id
         AND cr.policy_type = 'ai_analysis'
         AND cr.revoked_at IS NULL
      RETURNING 1
    )
    SELECT count(*) INTO v_ledger_fechadas FROM fechadas;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'application_id', v_application_id,
    'consent_type', p_consent_type,
    'revoked_at', v_revoked_at,
    'has_consent', false,
    'has_revoked', true,
    'ledger_rows_closed', v_ledger_fechadas   -- #1666
  );
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Backfill: os aceites anteriores entram no ledger COMO SÃO, sem prova inventada.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.consent_records (
  application_id, policy_type, policy_version, accepted_at, channel,
  evidence, revoked_at, revocation_reason, organization_id
)
SELECT a.id,
       'ai_analysis',
       -- A redação que estas pessoas viram é a anterior ao #1642. Não temos o hash dela, e
       -- reconstruí-lo hoje daria o texto NOVO — a versão nomeia o que sabemos e só isso.
       'v1-pre-1642',
       a.consent_ai_analysis_at,
       'email_link',
       NULL,
       a.consent_ai_analysis_revoked_at,
       CASE WHEN a.consent_ai_analysis_revoked_at IS NOT NULL
            THEN 'backfill #1666: revogação anterior ao ledger' END,
       a.organization_id
FROM public.selection_applications a
WHERE a.consent_ai_analysis_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.consent_records cr
    WHERE cr.application_id = a.id AND cr.policy_type = 'ai_analysis'
  );

-- E a ponte de volta, para os que acabaram de entrar.
UPDATE public.selection_applications a
   SET consent_record_id = cr.id
  FROM public.consent_records cr
 WHERE cr.application_id = a.id
   AND cr.policy_type = 'ai_analysis'
   AND cr.revoked_at IS NULL
   AND a.consent_record_id IS NULL;
