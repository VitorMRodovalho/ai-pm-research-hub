-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 11: Site config table (S-RM5 Multi-tenant Config)
-- Key-value store for group_term, cycle_default, webhooks. Superadmin only.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.site_config (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL DEFAULT '{}'::JSONB,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES public.members(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.site_config IS
  'Site-wide configuration (group_term, cycle_default, webhooks). Superadmin write, admin read.';

ALTER TABLE public.site_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "site_config_admin_read" ON public.site_config
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (m.is_superadmin = TRUE OR m.operational_role IN ('manager','deputy_manager','co_gp'))
    )
  );

CREATE POLICY "site_config_superadmin_write" ON public.site_config
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_superadmin = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND m.is_superadmin = TRUE
    )
  );

-- RPC: get all config as JSON
CREATE OR REPLACE FUNCTION public.get_site_config()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (SELECT is_superadmin OR operational_role IN ('manager','deputy_manager','co_gp')
          FROM members WHERE auth_id = auth.uid()) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;
  RETURN (SELECT COALESCE(json_object_agg(key, value), '{}'::JSON) FROM site_config);
END;
$$;

-- RPC: set a config key (superadmin only)
CREATE OR REPLACE FUNCTION public.set_site_config(p_key TEXT, p_value JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (SELECT is_superadmin FROM members WHERE auth_id = auth.uid()) THEN
    RAISE EXCEPTION 'Superadmin only';
  END IF;
  INSERT INTO site_config (key, value, updated_at, updated_by)
  VALUES (p_key, p_value, now(), (SELECT id FROM members WHERE auth_id = auth.uid()))
  ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    updated_at = now(),
    updated_by = EXCLUDED.updated_by;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_site_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_site_config(TEXT, JSONB) TO authenticated;

-- Seed default keys
INSERT INTO public.site_config (key, value)
VALUES
  ('group_term', '"Núcleo"'::JSONB),
  ('cycle_default', 'null'::JSONB),
  ('webhook_url', 'null'::JSONB)
ON CONFLICT (key) DO NOTHING;

COMMIT;
