-- ARM Onda 2.2: consent_records table — LGPD Art. 7 I + Art. 8 §5 audit trail
--
-- Estado pré: política /privacy existe (v2026-04-13) mas SEM tabela registrando
-- quem aceitou qual versão quando. Ônus da prova invertido para o controlador.
--
-- Mudanças:
--   1) Nova tabela consent_records com subject polimórfico (member|application|email_hash)
--   2) policy_type + policy_version + opcional FK para governance_documents
--   3) Minimização: IP e UA armazenados como hash (não raw). Channel para
--      contexto de captura. Revogação via revoked_at.
--   4) RLS rpc-only pattern (mesmo de selection_applications): rpc_only_deny_all
--      PERMISSIVE qual=false + v4_org_scope RESTRICTIVE
--   5) FK opcional selection_applications.consent_record_id para vincular ao
--      registro de aceite no momento da submissão
--
-- Rollback:
--   ALTER TABLE selection_applications DROP COLUMN consent_record_id;
--   DROP TABLE public.consent_records;

CREATE TABLE IF NOT EXISTS public.consent_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Subject polimórfico (one of these set)
  member_id uuid REFERENCES public.members(id) ON DELETE SET NULL,
  application_id uuid REFERENCES public.selection_applications(id) ON DELETE SET NULL,
  email_hash text,

  -- What was consented
  policy_type text NOT NULL,
  policy_version text NOT NULL,
  policy_document_id uuid REFERENCES public.governance_documents(id) ON DELETE SET NULL,

  -- When and how
  accepted_at timestamptz NOT NULL DEFAULT now(),
  channel text NOT NULL,

  -- Minimization (no raw IP/UA)
  ip_hash text,
  user_agent_hash text,

  -- Revocation
  revoked_at timestamptz,
  revocation_reason text,

  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT consent_records_subject_check CHECK (
    member_id IS NOT NULL OR application_id IS NOT NULL OR email_hash IS NOT NULL
  ),
  CONSTRAINT consent_records_policy_type_check CHECK (
    policy_type IN ('privacy_policy', 'volunteer_term', 'ai_analysis', 'communication_preferences', 'cookies', 'other')
  ),
  CONSTRAINT consent_records_channel_check CHECK (
    channel IN ('vep_form', 'platform_signup', 'platform_action', 'email_link', 'admin_attestation', 'api', 'other')
  )
);

CREATE INDEX IF NOT EXISTS ix_consent_records_member ON public.consent_records (member_id) WHERE member_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_consent_records_application ON public.consent_records (application_id) WHERE application_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_consent_records_policy ON public.consent_records (policy_type, policy_version);
CREATE INDEX IF NOT EXISTS ix_consent_records_email_hash ON public.consent_records (email_hash) WHERE email_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_consent_records_accepted_at ON public.consent_records (accepted_at DESC);

ALTER TABLE public.consent_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpc_only_deny_all ON public.consent_records;
CREATE POLICY rpc_only_deny_all
  ON public.consent_records
  AS PERMISSIVE FOR ALL TO public
  USING (false);

DROP POLICY IF EXISTS consent_records_v4_org_scope ON public.consent_records;
CREATE POLICY consent_records_v4_org_scope
  ON public.consent_records
  AS RESTRICTIVE FOR ALL TO public
  USING ((organization_id = auth_org()) OR (organization_id IS NULL))
  WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

-- REVOKE over-permissive grants (defesa em profundidade — pattern Onda 1 #134)
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.consent_records FROM anon;
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.consent_records FROM authenticated;
-- REVOKE SELECT de anon (RLS qual=false já bloqueia, mas defesa em profundidade)
REVOKE SELECT ON public.consent_records FROM anon;
-- Manter SELECT TO authenticated — consistente com selection_* (RLS gateia)

-- FK opcional em selection_applications
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS consent_record_id uuid REFERENCES public.consent_records(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_selection_applications_consent_record
  ON public.selection_applications (consent_record_id) WHERE consent_record_id IS NOT NULL;

COMMENT ON TABLE public.consent_records IS
  'LGPD Art. 7 I + Art. 8 §5: registro auditável de aceite de políticas. Subject polimórfico (member, application ou email_hash anônimo). Política identificada por type+version (ou governance_documents.id quando aplicável). Minimização: IP/UA armazenados como hash via SHA256 antes de chegar aqui (não aceitar raw). RLS rpc-only via pattern selection_applications. ARM Onda 2.2 (security audit p107). Acesso via SECDEF RPCs (record_consent, list_my_consents — futuras).';

COMMENT ON COLUMN public.selection_applications.consent_record_id IS
  'FK opcional para consent_records do aceite no momento da submissão. NULL para legacy applications pré-Onda 2.2.';

NOTIFY pgrst, 'reload schema';
