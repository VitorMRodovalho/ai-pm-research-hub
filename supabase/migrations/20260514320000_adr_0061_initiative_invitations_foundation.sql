-- ADR-0061 — #88 Foundation: invitation flow + scope-bound permissions
-- Council Tier 3: accountability-advisor BLOCKING items + ux R2/R5/R7

CREATE TABLE IF NOT EXISTS public.initiative_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  initiative_id uuid NOT NULL REFERENCES public.initiatives(id) ON DELETE CASCADE,
  invitee_member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  inviter_member_id uuid NOT NULL REFERENCES public.members(id),
  kind_scope text NOT NULL,
  message text NOT NULL CHECK (length(message) >= 50),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'accepted', 'declined', 'expired', 'revoked'
  )),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '72 hours'),
  reviewed_by uuid REFERENCES public.members(id),
  reviewed_at timestamptz,
  reviewed_note text,
  responded_at timestamptz,
  responded_note text,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES public.members(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ii_invitee_pending_idx ON public.initiative_invitations(invitee_member_id, status)
  WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS ii_initiative_idx ON public.initiative_invitations(initiative_id);
CREATE INDEX IF NOT EXISTS ii_expires_idx ON public.initiative_invitations(expires_at)
  WHERE status = 'pending';

ALTER TABLE public.initiative_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY initiative_invitations_read_self ON public.initiative_invitations
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    invitee_member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid()))
  );

CREATE POLICY initiative_invitations_read_inviter ON public.initiative_invitations
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    inviter_member_id IN (SELECT m.id FROM public.members m WHERE m.auth_id = (SELECT auth.uid()))
  );

CREATE POLICY initiative_invitations_read_admin ON public.initiative_invitations
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    rls_is_superadmin() OR rls_can('manage_member'::text)
  );

COMMENT ON TABLE public.initiative_invitations IS
  'ADR-0061 #88 Foundation: invitation flow with scope-bound permissions. Owner do recurso convida (Notion/Linear/GitHub pattern). Message obrigatorio min 50 chars (ux R5). Expires 72h default (ux R2). Reviewed_by para second-level approval em iniciativas com cobranca. Mutations via SECDEF RPCs only.';

ALTER TABLE public.initiatives
  ADD COLUMN IF NOT EXISTS join_policy text NOT NULL DEFAULT 'invite_only'
  CHECK (join_policy IN ('invite_only', 'request_to_join', 'open'));

UPDATE public.initiatives SET join_policy = 'request_to_join' WHERE kind = 'study_group';

COMMENT ON COLUMN public.initiatives.join_policy IS
  'ADR-0061 #88: invitation model differentiation per initiative kind. invite_only (default), request_to_join (Notion-style), open (no auth). Study_group default request_to_join (high volume), workgroup/committee default invite_only.';

UPDATE public.engagement_kinds
SET created_by_role = COALESCE(created_by_role, ARRAY[]::text[]) || ARRAY['coordinator']::text[]
WHERE slug = 'workgroup_member'
  AND NOT ('coordinator' = ANY(COALESCE(created_by_role, ARRAY[]::text[])));

UPDATE public.engagement_kinds
SET created_by_role = COALESCE(created_by_role, ARRAY[]::text[]) || ARRAY['coordinator']::text[]
WHERE slug = 'committee_member'
  AND NOT ('coordinator' = ANY(COALESCE(created_by_role, ARRAY[]::text[])));

CREATE OR REPLACE FUNCTION public._trg_initiative_invitations_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_initiative_invitations_updated_at ON public.initiative_invitations;
CREATE TRIGGER trg_initiative_invitations_updated_at
  BEFORE UPDATE ON public.initiative_invitations
  FOR EACH ROW EXECUTE FUNCTION public._trg_initiative_invitations_updated_at();

CREATE OR REPLACE FUNCTION public.expire_stale_initiative_invitations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_count int;
BEGIN
  UPDATE public.initiative_invitations
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('expired_count', v_count, 'run_at', now());
END $$;

COMMENT ON FUNCTION public.expire_stale_initiative_invitations() IS
  'Marca invitations pending past expires_at como expired. Chamavel via cron (recomendado: cada hora). Service-role-callable.';

REVOKE EXECUTE ON FUNCTION public.expire_stale_initiative_invitations() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_stale_initiative_invitations() FROM anon;
REVOKE EXECUTE ON FUNCTION public.expire_stale_initiative_invitations() FROM authenticated;

NOTIFY pgrst, 'reload schema';
