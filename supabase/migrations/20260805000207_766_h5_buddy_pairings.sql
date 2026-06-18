-- Migration: 766 H5 buddy/padrinho — bilateral pairing loop (volunteer-driven)
-- SPEC: docs/specs/SPEC_766_H5_BUDDY.md  (#766 item 4/4, severity green)
--
-- Model: padrinho (senior, non-guest, same tribe) VOLUNTEERS (inviter) -> afilhado (invitee) accepts.
-- Own minimal table buddy_pairings (NOT initiative_invitations — that primitive is coupled to
-- initiative_id/kind_scope and creates an engagement on accept; none of that fits buddy). ADR-0013 Cat B.
-- LGPD: contact (phone/WhatsApp) lives in members and is exposed ONLY via get_my_buddy() under a DOUBLE
-- gate (members.share_whatsapp = true AND pairing.status = 'accepted'); the accept IS the bilateral consent.
-- No invariant in check_schema_invariants(): pairing status is mutable and bidirectional (accepted ->
-- revoked -> new offered is the normal path); CHECK + partial unique index cover the only static invariant.
-- GC-097 Phase-C: all rationale lives in THIS header / above each CREATE; never inline inside $fn$ bodies.
-- Rollback: DROP TABLE public.buddy_pairings CASCADE; DROP FUNCTION public.buddy_pairings_set_updated_at();
--   DROP FUNCTION public.offer_buddy(uuid,text); DROP FUNCTION public.respond_to_buddy_offer(uuid,text);
--   DROP FUNCTION public.revoke_buddy_offer(uuid); DROP FUNCTION public.get_my_buddy();

-- ============================ Table ============================
CREATE TABLE public.buddy_pairings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  padrino_member_id   uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  afilhado_member_id  uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  status              text NOT NULL DEFAULT 'offered',
  message             text,
  offered_at          timestamptz NOT NULL DEFAULT now(),
  responded_at        timestamptz,
  revoked_at          timestamptz,
  revoked_by          uuid REFERENCES public.members(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT buddy_pairings_status_chk CHECK (status IN ('offered','accepted','declined','revoked')),
  CONSTRAINT buddy_pairings_distinct_chk CHECK (padrino_member_id <> afilhado_member_id)
);

-- At most ONE active (offered/accepted) pairing per afilhado; declined/revoked free re-pairing.
CREATE UNIQUE INDEX buddy_pairings_one_active_afilhado
  ON public.buddy_pairings (afilhado_member_id)
  WHERE status IN ('offered','accepted');

-- Lookup by padrino (get_my_buddy as_padrino + revoke); afilhado is covered by the partial unique above.
CREATE INDEX buddy_pairings_padrino_idx ON public.buddy_pairings (padrino_member_id);

COMMENT ON TABLE public.buddy_pairings IS
  '766 H5 buddy/padrinho: bilateral pairing, volunteer-driven. padrino=inviter, afilhado=invitee. ADR-0013 Cat B.';

-- ====================== updated_at trigger ======================
-- Dedicated per-table fn (project has no generic set_updated_at helper).
CREATE FUNCTION public.buddy_pairings_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $fn$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER _trg_buddy_pairings_updated_at
  BEFORE UPDATE ON public.buddy_pairings
  FOR EACH ROW EXECUTE FUNCTION public.buddy_pairings_set_updated_at();

REVOKE EXECUTE ON FUNCTION public.buddy_pairings_set_updated_at() FROM PUBLIC;

-- ============================ RLS ============================
-- Mutations only via SECDEF RPCs (no write policy -> default deny). SELECT for the two parties + the
-- tribe_leader of the padrino's tribe (coverage visibility). tribe_id derived via members (no cache column).
ALTER TABLE public.buddy_pairings ENABLE ROW LEVEL SECURITY;

CREATE POLICY buddy_pairings_select ON public.buddy_pairings
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members me
      WHERE me.auth_id = auth.uid()
        AND me.id IN (buddy_pairings.padrino_member_id, buddy_pairings.afilhado_member_id)
    )
    -- tribe_leader sees pairings whose PADRINO is in their tribe (the afilhado may have since moved tribes).
    OR EXISTS (
      SELECT 1 FROM public.members tl
      JOIN public.members p ON p.id = buddy_pairings.padrino_member_id
      WHERE tl.auth_id = auth.uid()
        AND tl.operational_role = 'tribe_leader'
        AND tl.tribe_id IS NOT NULL
        AND tl.tribe_id = p.tribe_id
    )
  );

-- ============================ RPCs ============================

-- offer_buddy: a member volunteers to be padrinho of an afilhado in the same tribe.
-- ADR-0011: buddy is a CONSENSUAL peer action, not a privileged-authority gate — the real gate is
-- tribe co-membership + bilateral accept, NOT a role capability. So this RPC deliberately carries no
-- operational_role authority branch (which V4 would require to route through can()). Guest exclusion
-- (buddy is post-promotion) is a DATA filter on the volunteer pool in get_my_buddy.can_volunteer_for
-- + the FE, not a hard RPC gate; a guest offering directly is harmless (the afilhado must still accept).
CREATE FUNCTION public.offer_buddy(p_afilhado_member_id uuid, p_message text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller   record;
  v_afilhado record;
  v_pairing_id uuid;
BEGIN
  SELECT id, tribe_id, name INTO v_caller
  FROM public.members WHERE auth_id = auth.uid() AND is_active = true;
  IF v_caller.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_caller.tribe_id IS NULL THEN
    RAISE EXCEPTION 'Caller has no tribe' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_afilhado_member_id = v_caller.id THEN
    RAISE EXCEPTION 'Cannot be your own buddy' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT id, tribe_id INTO v_afilhado
  FROM public.members WHERE id = p_afilhado_member_id AND is_active = true;
  IF v_afilhado.id IS NULL THEN
    RAISE EXCEPTION 'Afilhado not found or inactive' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_afilhado.tribe_id IS DISTINCT FROM v_caller.tribe_id THEN
    RAISE EXCEPTION 'Afilhado is not in your tribe' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.buddy_pairings
    WHERE afilhado_member_id = p_afilhado_member_id AND status IN ('offered','accepted')
  ) THEN
    RAISE EXCEPTION 'Afilhado already has an active buddy offer or pairing'
      USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO public.buddy_pairings (padrino_member_id, afilhado_member_id, message)
  VALUES (v_caller.id, p_afilhado_member_id, p_message)
  RETURNING id INTO v_pairing_id;

  INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
  VALUES (
    p_afilhado_member_id,
    'buddy_offer',
    v_caller.name || ' quer ser seu padrinho',
    'Alguém da sua tribo se voluntariou para te apoiar nos primeiros passos. Você decide.',
    '/workspace',
    'buddy_pairing',
    v_pairing_id,
    v_caller.id,
    'transactional_immediate'
  );

  RETURN jsonb_build_object('ok', true, 'pairing_id', v_pairing_id, 'status', 'offered');
END;
$fn$;

COMMENT ON FUNCTION public.offer_buddy(uuid, text) IS
  '766 H5: caller volunteers as padrinho for an afilhado in the same tribe. Guards: caller has tribe; afilhado active + same tribe; not self; afilhado has no active pairing. Notifies afilhado. Guest exclusion is a pool/FE data filter (ADR-0011: no role authority in body).';

-- respond_to_buddy_offer: the afilhado accepts or declines a pending offer.
CREATE FUNCTION public.respond_to_buddy_offer(p_pairing_id uuid, p_response text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller_id   uuid;
  v_caller_name text;
  v_pairing     record;
BEGIN
  SELECT id, name INTO v_caller_id, v_caller_name
  FROM public.members WHERE auth_id = auth.uid() AND is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_response NOT IN ('accept','decline') THEN
    RAISE EXCEPTION 'Response must be accept or decline (got: %)', p_response
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_pairing FROM public.buddy_pairings WHERE id = p_pairing_id;
  IF v_pairing.id IS NULL THEN
    RAISE EXCEPTION 'Pairing not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_pairing.afilhado_member_id <> v_caller_id THEN
    RAISE EXCEPTION 'Only the afilhado can respond to this offer' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_pairing.status <> 'offered' THEN
    RAISE EXCEPTION 'Offer is not pending (current status: %)', v_pairing.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  UPDATE public.buddy_pairings
  SET status = CASE WHEN p_response = 'accept' THEN 'accepted' ELSE 'declined' END,
      responded_at = now()
  WHERE id = p_pairing_id;

  IF p_response = 'accept' THEN
    INSERT INTO public.notifications (recipient_id, type, title, body, link, source_type, source_id, actor_id, delivery_mode)
    VALUES (
      v_pairing.padrino_member_id,
      'buddy_accepted',
      v_caller_name || ' aceitou você como padrinho',
      'Vocês agora são padrinho e afilhado. Diga olá!',
      '/workspace',
      'buddy_pairing',
      p_pairing_id,
      v_caller_id,
      'transactional_immediate'
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'pairing_id', p_pairing_id, 'response', p_response);
END;
$fn$;

COMMENT ON FUNCTION public.respond_to_buddy_offer(uuid, text) IS
  '766 H5: afilhado accepts/declines a pending buddy offer. Caller must be the invitee; status must be offered. On accept notifies the padrinho.';

-- revoke_buddy_offer: padrinho withdraws an offer, OR either party ends an accepted pairing.
-- ADR-0011: ownership-only gate (caller is one of the two parties) — no role authority. tribe_leader
-- coverage stays as SELECT visibility via the RLS policy; a tribe_leader FORCE-revoke is deferred (would
-- be a role capability that V4 routes through can(); not needed for the green MVP).
CREATE FUNCTION public.revoke_buddy_offer(p_pairing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller_id uuid;
  v_pairing   record;
BEGIN
  SELECT id INTO v_caller_id
  FROM public.members WHERE auth_id = auth.uid() AND is_active = true;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_pairing FROM public.buddy_pairings WHERE id = p_pairing_id;
  IF v_pairing.id IS NULL THEN
    RAISE EXCEPTION 'Pairing not found' USING ERRCODE = 'no_data_found';
  END IF;
  IF v_pairing.status NOT IN ('offered','accepted') THEN
    RAISE EXCEPTION 'Pairing is not active (current status: %)', v_pairing.status
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_caller_id NOT IN (v_pairing.padrino_member_id, v_pairing.afilhado_member_id) THEN
    RAISE EXCEPTION 'Not authorized to revoke this pairing' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.buddy_pairings
  SET status = 'revoked', revoked_at = now(), revoked_by = v_caller_id
  WHERE id = p_pairing_id;

  RETURN jsonb_build_object('ok', true, 'pairing_id', p_pairing_id, 'status', 'revoked');
END;
$fn$;

COMMENT ON FUNCTION public.revoke_buddy_offer(uuid) IS
  '766 H5: revoke an active (offered/accepted) pairing. Authorized: either party (ownership-only). Sets status=revoked, freeing the partial-unique slot for a new pairing.';

-- get_my_buddy: canonical FE read. WhatsApp under double gate (share_whatsapp + accepted).
CREATE FUNCTION public.get_my_buddy()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id   uuid;
  v_tribe_id    integer;
  v_as_afilhado jsonb;
  v_as_padrino  jsonb;
  v_can_volunteer jsonb;
BEGIN
  SELECT id, tribe_id INTO v_member_id, v_tribe_id
  FROM public.members WHERE auth_id = auth.uid() AND is_active = true;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT to_jsonb(x) INTO v_as_afilhado FROM (
    SELECT bp.id AS pairing_id, bp.status, bp.message,
           p.id AS padrino_id, p.name AS padrino_name,
           CASE WHEN bp.status = 'accepted' AND p.share_whatsapp THEN p.phone ELSE NULL END AS padrino_whatsapp
    FROM public.buddy_pairings bp
    JOIN public.members p ON p.id = bp.padrino_member_id
    WHERE bp.afilhado_member_id = v_member_id AND bp.status IN ('offered','accepted')
    LIMIT 1
  ) x;

  SELECT coalesce(jsonb_agg(to_jsonb(y)), '[]'::jsonb) INTO v_as_padrino FROM (
    SELECT bp.id AS pairing_id, bp.status,
           a.id AS afilhado_id, a.name AS afilhado_name,
           CASE WHEN bp.status = 'accepted' AND a.share_whatsapp THEN a.phone ELSE NULL END AS afilhado_whatsapp
    FROM public.buddy_pairings bp
    JOIN public.members a ON a.id = bp.afilhado_member_id
    WHERE bp.padrino_member_id = v_member_id AND bp.status IN ('offered','accepted')
    ORDER BY bp.offered_at DESC
  ) y;

  IF v_tribe_id IS NULL THEN
    v_can_volunteer := '[]'::jsonb;
  ELSE
    SELECT coalesce(jsonb_agg(to_jsonb(z)), '[]'::jsonb) INTO v_can_volunteer FROM (
      SELECT m.id AS member_id, m.name
      FROM public.members m
      WHERE m.tribe_id = v_tribe_id
        AND m.is_active = true
        AND m.operational_role <> 'guest'
        AND m.id <> v_member_id
        AND NOT EXISTS (
          SELECT 1 FROM public.buddy_pairings bp
          WHERE bp.afilhado_member_id = m.id AND bp.status IN ('offered','accepted')
        )
      ORDER BY m.name
    ) z;
  END IF;

  RETURN jsonb_build_object(
    'as_afilhado', v_as_afilhado,
    'as_padrino', v_as_padrino,
    'can_volunteer_for', v_can_volunteer
  );
END;
$fn$;

COMMENT ON FUNCTION public.get_my_buddy() IS
  '766 H5: canonical FE read. Returns as_afilhado (active offer/pairing), as_padrino[], can_volunteer_for[] (non-guest tribe peers without active pairing). WhatsApp only when share_whatsapp AND accepted. Guards manager/GP (tribe_id NULL) -> can_volunteer_for=[].';

REVOKE EXECUTE ON FUNCTION public.offer_buddy(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.respond_to_buddy_offer(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_buddy_offer(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_buddy() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.offer_buddy(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_to_buddy_offer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_buddy_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_buddy() TO authenticated;

NOTIFY pgrst, 'reload schema';
