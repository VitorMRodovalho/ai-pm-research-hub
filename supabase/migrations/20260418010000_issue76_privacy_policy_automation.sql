-- ============================================================================
-- Issue #76: Automate privacy policy change notifications + validation
-- Two features:
--   1. privacy_policy_versions table + RPC to create draft campaign on new version
--   2. Audit trigger on engagement_kinds for LGPD-relevant field changes
-- Rollback: DROP TABLE IF EXISTS privacy_policy_versions CASCADE;
--           DROP FUNCTION IF EXISTS notify_privacy_policy_change CASCADE;
--           DROP FUNCTION IF EXISTS _audit_engagement_kinds_changes CASCADE;
--           DROP TRIGGER IF EXISTS trg_audit_engagement_kinds ON engagement_kinds;
-- ============================================================================

-- ══════════════════════════════════════════════
-- 1. Privacy policy version tracking
-- ══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.privacy_policy_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version text NOT NULL UNIQUE,
  effective_at timestamptz NOT NULL DEFAULT now(),
  summary_pt text,          -- human-readable diff summary (PT-BR)
  summary_en text,          -- human-readable diff summary (EN)
  summary_es text,          -- human-readable diff summary (ES)
  change_request_id uuid REFERENCES public.change_requests(id),
  notification_campaign_id uuid,  -- campaign_sends.id once created
  notification_created_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.privacy_policy_versions ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read versions (transparency)
CREATE POLICY "Authenticated can view privacy versions"
  ON public.privacy_policy_versions FOR SELECT TO authenticated
  USING (true);

-- Only superadmin can insert/update
CREATE POLICY "Superadmin can manage privacy versions"
  ON public.privacy_policy_versions FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = auth.uid() AND is_superadmin = true
  ));

-- Seed current version
INSERT INTO public.privacy_policy_versions (version, effective_at, summary_pt, summary_en, summary_es)
VALUES (
  'v2.2',
  '2026-04-12T00:00:00Z',
  'Adicionadas linhas de retenção por tipo de engajamento. Base legal alinhada com LGPD Art. 7.',
  'Added retention rows per engagement type. Legal basis aligned with LGPD Art. 7.',
  'Añadidas filas de retención por tipo de compromiso. Base legal alineada con LGPD Art. 7.'
)
ON CONFLICT (version) DO NOTHING;

COMMENT ON TABLE public.privacy_policy_versions IS 'Tracks privacy policy versions for LGPD Section 12 notification compliance.';

-- ══════════════════════════════════════════════
-- 2. RPC: create draft campaign for new privacy policy version
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_privacy_policy_change(
  p_version_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_version record;
  v_template_id uuid;
  v_send_id uuid;
BEGIN
  -- Auth: superadmin only
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = v_caller AND is_superadmin = true
  ) THEN
    RAISE EXCEPTION 'Superadmin only';
  END IF;

  -- Get version details
  SELECT * INTO v_version FROM privacy_policy_versions WHERE id = p_version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Version not found';
  END IF;

  -- Already notified?
  IF v_version.notification_campaign_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'already_notified',
      'campaign_id', v_version.notification_campaign_id
    );
  END IF;

  -- Create campaign template for this version
  INSERT INTO campaign_templates (name, subject, body_html, category, created_by)
  VALUES (
    'Atualização da Política de Privacidade ' || v_version.version,
    'Atualização da Política de Privacidade — ' || v_version.version,
    '<p>Prezado(a) membro,</p>'
    || '<p>Informamos que a Política de Privacidade do Núcleo IA &amp; GP foi atualizada para a versão <strong>' || v_version.version || '</strong>, '
    || 'com vigência a partir de ' || to_char(v_version.effective_at, 'DD/MM/YYYY') || '.</p>'
    || '<p><strong>Resumo das alterações:</strong></p>'
    || '<p>' || COALESCE(v_version.summary_pt, 'Consulte a política atualizada no site.') || '</p>'
    || '<p>A política completa pode ser consultada em: '
    || '<a href="https://nucleoia.vitormr.dev/privacy">nucleoia.vitormr.dev/privacy</a></p>'
    || '<p>Em caso de dúvidas, entre em contato com o DPO: <a href="mailto:vitor.rodovalho@outlook.com">vitor.rodovalho@outlook.com</a></p>'
    || '<p>Atenciosamente,<br/>Núcleo IA &amp; GP</p>',
    'lgpd',
    v_caller
  )
  RETURNING id INTO v_template_id;

  -- Create campaign send in DRAFT status (requires PM approval before sending)
  INSERT INTO campaign_sends (template_id, status, created_by)
  VALUES (v_template_id, 'draft', v_caller)
  RETURNING id INTO v_send_id;

  -- Link back to version
  UPDATE privacy_policy_versions SET
    notification_campaign_id = v_send_id,
    notification_created_at = now()
  WHERE id = p_version_id;

  RETURN jsonb_build_object(
    'status', 'draft_created',
    'campaign_send_id', v_send_id,
    'template_id', v_template_id,
    'note', 'Campaign created in DRAFT status. Review and send via admin_send_campaign.'
  );
END;
$$;

COMMENT ON FUNCTION public.notify_privacy_policy_change IS
  'Creates a draft campaign for LGPD Section 12 notification when privacy policy changes. Requires PM review before send.';

-- ══════════════════════════════════════════════
-- 3. Audit trigger on engagement_kinds for LGPD-relevant changes
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._audit_engagement_kinds_changes()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_changes jsonb := '[]'::jsonb;
  v_actor_id uuid;
BEGIN
  -- Detect changes to LGPD-relevant fields
  IF OLD.legal_basis IS DISTINCT FROM NEW.legal_basis THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'legal_basis', 'old', OLD.legal_basis, 'new', NEW.legal_basis
    ));
  END IF;

  IF OLD.retention_days_after_end IS DISTINCT FROM NEW.retention_days_after_end THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'retention_days_after_end', 'old', OLD.retention_days_after_end, 'new', NEW.retention_days_after_end
    ));
  END IF;

  IF OLD.anonymization_policy IS DISTINCT FROM NEW.anonymization_policy THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'anonymization_policy', 'old', OLD.anonymization_policy, 'new', NEW.anonymization_policy
    ));
  END IF;

  IF OLD.requires_agreement IS DISTINCT FROM NEW.requires_agreement THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'requires_agreement', 'old', OLD.requires_agreement, 'new', NEW.requires_agreement
    ));
  END IF;

  -- Only log if LGPD-relevant fields changed
  IF jsonb_array_length(v_changes) = 0 THEN
    RETURN NEW;
  END IF;

  -- Get actor
  v_actor_id := auth.uid();

  -- Log to admin_audit_log
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, details)
  VALUES (
    v_actor_id,
    'engagement_kind_lgpd_update',
    'engagement_kinds',
    NEW.slug,
    jsonb_build_object(
      'kind', NEW.slug,
      'display_name', NEW.display_name,
      'changes', v_changes,
      'warning', 'LGPD-relevant fields changed. Verify alignment with published privacy policy.',
      'privacy_policy_fields_to_check', ARRAY[
        'privacy.s6ret (retention table)',
        'privacy.s4legal (legal basis section)'
      ]
    )
  );

  -- Validate legal_basis values against LGPD Art. 7
  IF NEW.legal_basis NOT IN (
    'contract_volunteer', 'contract_course', 'consent',
    'legitimate_interest', 'chapter_delegation'
  ) THEN
    RAISE WARNING 'engagement_kind % has unrecognized legal_basis: %. Verify LGPD Art. 7 compliance.',
      NEW.slug, NEW.legal_basis;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_engagement_kinds ON public.engagement_kinds;
CREATE TRIGGER trg_audit_engagement_kinds
BEFORE UPDATE ON public.engagement_kinds
FOR EACH ROW
EXECUTE FUNCTION public._audit_engagement_kinds_changes();

COMMENT ON FUNCTION public._audit_engagement_kinds_changes IS
  'Audit trigger: logs LGPD-relevant changes to engagement_kinds (legal_basis, retention, anonymization) to admin_audit_log with validation warnings.';

-- ══════════════════════════════════════════════
-- 4. Validation RPC: check engagement_kinds vs privacy policy consistency
-- ══════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.validate_privacy_policy_consistency()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_issues jsonb := '[]'::jsonb;
  v_current_version text;
  v_kind record;
BEGIN
  -- Auth: superadmin only
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = v_caller AND is_superadmin = true
  ) THEN
    RAISE EXCEPTION 'Superadmin only';
  END IF;

  -- Get current policy version
  SELECT version INTO v_current_version
  FROM privacy_policy_versions
  ORDER BY effective_at DESC LIMIT 1;

  -- Check each engagement_kind for potential issues
  FOR v_kind IN
    SELECT slug, display_name, legal_basis, retention_days_after_end,
           anonymization_policy, requires_agreement
    FROM engagement_kinds
    ORDER BY slug
  LOOP
    -- Issue: retention > 5 years (1825 days) without explicit justification
    IF v_kind.retention_days_after_end > 1825 THEN
      v_issues := v_issues || jsonb_build_array(jsonb_build_object(
        'kind', v_kind.slug,
        'severity', 'warning',
        'issue', 'Retention exceeds 5 years (' || v_kind.retention_days_after_end || ' days). Verify legal justification.'
      ));
    END IF;

    -- Issue: consent-based kind without agreement requirement
    IF v_kind.legal_basis = 'consent' AND NOT v_kind.requires_agreement THEN
      v_issues := v_issues || jsonb_build_array(jsonb_build_object(
        'kind', v_kind.slug,
        'severity', 'error',
        'issue', 'Consent-based kind does not require agreement. LGPD Art. 8 requires explicit consent documentation.'
      ));
    END IF;

    -- Issue: no retention configured
    IF v_kind.retention_days_after_end IS NULL OR v_kind.retention_days_after_end = 0 THEN
      v_issues := v_issues || jsonb_build_array(jsonb_build_object(
        'kind', v_kind.slug,
        'severity', 'error',
        'issue', 'No retention period configured. Must be documented per LGPD Art. 15.'
      ));
    END IF;
  END LOOP;

  -- Check for unnotified versions
  RETURN jsonb_build_object(
    'current_policy_version', v_current_version,
    'total_engagement_kinds', (SELECT count(*) FROM engagement_kinds),
    'issues_found', jsonb_array_length(v_issues),
    'issues', v_issues,
    'unnotified_versions', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'version', version, 'effective_at', effective_at
      )), '[]'::jsonb)
      FROM privacy_policy_versions
      WHERE notification_campaign_id IS NULL
    )
  );
END;
$$;

COMMENT ON FUNCTION public.validate_privacy_policy_consistency IS
  'Validates that engagement_kinds configuration is consistent with LGPD requirements and flags unnotified policy versions.';

NOTIFY pgrst, 'reload schema';
