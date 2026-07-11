-- #1052 — stop anon PII leak via public_members.signature_url.
-- public_members is an anon-readable SECURITY DEFINER view over members. It carried
-- signature_url, whose value is a member-signatures storage path that EMBEDS the member's
-- email in the filename (e.g. .../signatures/<email>.png). members.email is PII that anon
-- must never see (GC-162), so anon could harvest emails by listing this view. 6 members had
-- signatures (2 GP cert-signers + 4 researchers who self-signed their term; the 4 have no
-- reason to appear at all). The signature is only legitimately needed for the cert ISSUER /
-- counter-signer, so it moves to a gated RPC scoped to actual signers.
--
-- Column removal = view signature change -> DROP + CREATE (no dependents; verified via pg_depend).
-- Grants tightened: the old view had GRANT ALL to anon/authenticated (INSERT/UPDATE/DELETE on
-- an auto-updatable definer view = latent write vector). The recreated view is SELECT-only.

DROP VIEW IF EXISTS public.public_members;

CREATE VIEW public.public_members AS
  SELECT id,
    name,
    photo_url,
    chapter,
    operational_role,
    designations,
    tribe_id,
    initiative_id,
    current_cycle_active,
    is_active,
    linkedin_url,
    credly_badges,
    credly_url,
    credly_verified_at,
    cpmai_certified,
    cpmai_certified_at,
    country,
    state,
    cycles,
    created_at,
    share_whatsapp,
    member_status,
    is_founder
   FROM public.members;

REVOKE ALL ON public.public_members FROM anon, authenticated;
GRANT SELECT ON public.public_members TO anon, authenticated, service_role;

-- Gated signature resolver for cert rendering (issuer / counter-signer only). Returns the
-- storage path only for members who ARE a cert signer; NULL otherwise. Callers (client cert
-- print + server puppeteer render + anon verify page) then createSignedUrl against the private
-- member-signatures bucket. Not enumerable: requires knowing a specific signer's member id.
CREATE OR REPLACE FUNCTION public.get_signer_signature_url(p_signer_id uuid)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.signature_url
  FROM public.members m
  WHERE m.id = p_signer_id
    AND m.signature_url IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.certificates c
      WHERE c.issued_by = m.id OR c.counter_signed_by = m.id
    );
$function$;

REVOKE ALL ON FUNCTION public.get_signer_signature_url(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_signer_signature_url(uuid) TO anon, authenticated, service_role;
