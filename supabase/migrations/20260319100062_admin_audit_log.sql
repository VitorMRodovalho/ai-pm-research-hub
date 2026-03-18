-- ============================================================
-- W-ADMIN Phase 1: Admin Audit Log table
-- Tracks all administrative actions for governance and compliance.
-- Superadmin-only read access. Any authenticated user can insert
-- (actor_id must match their own member record).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid NOT NULL REFERENCES public.members(id),
  action text NOT NULL,
  target_type text NOT NULL DEFAULT 'member',
  target_id uuid,
  changes jsonb DEFAULT '{}',
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Superadmin can read audit log" ON public.admin_audit_log
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members
    WHERE auth_id = auth.uid() AND is_superadmin = true
  ));

CREATE POLICY "Authenticated can insert audit log" ON public.admin_audit_log
  FOR INSERT TO authenticated
  WITH CHECK (
    actor_id = (SELECT id FROM public.members WHERE auth_id = auth.uid())
  );

CREATE INDEX idx_audit_log_target ON public.admin_audit_log(target_type, target_id, created_at DESC);
CREATE INDEX idx_audit_log_actor ON public.admin_audit_log(actor_id, created_at DESC);
CREATE INDEX idx_audit_log_created ON public.admin_audit_log(created_at DESC);

COMMENT ON TABLE public.admin_audit_log IS 'Tracks all administrative actions for governance and compliance. Superadmin-only read access.';
