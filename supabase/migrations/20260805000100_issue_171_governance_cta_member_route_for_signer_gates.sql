-- #171: governance ratification CTA routing — non-admin signer gates land on the member
-- review-chain route (/governance/documents/<chain>), not the /admin/ shell.
--
-- Root cause: _ip_ratify_cta_link routed only {volunteers_in_role_active, member_ratification,
-- external_signer} to a member route and dumped every OTHER gate — including leader_awareness
-- (tribe leaders), curator, chapter_witness, president_go/president_others — into an
-- /admin/governance/documents/ ELSE branch. Non-admin signers landing on the admin shell read
-- it as "I can't access this" (reported by Ana Carla Cavalcante, a tribe_leader, for her
-- leader_awareness gate). The /admin route is functionally accessible (same ReviewChainIsland),
-- but the persona-correct surface is /governance/documents/<chain> (BaseLayout, no admin sidebar;
-- ReviewChainIsland renders sign buttons for any eligible gate regardless of externalReviewMode).
--
-- Rollback: re-CREATE the prior 2-branch body (member route only for the 3 ratification gates,
-- ELSE /admin/governance/documents/).
CREATE OR REPLACE FUNCTION public._ip_ratify_cta_link(p_chain_id uuid, p_gate_kind text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    -- Volunteer/member ratification gates keep the dedicated IP-agreement signing page.
    WHEN p_gate_kind IN ('volunteers_in_role_active','member_ratification','external_signer')
      THEN '/governance/ip-agreement?chain_id=' || p_chain_id::text
    -- Other non-admin signer gates → member review-chain page (#171). Same ReviewChainIsland
    -- as the admin route, BaseLayout (no admin shell). Curators, tribe leaders, chapter
    -- witnesses and chapter presidents sign here instead of being bounced into /admin/.
    WHEN p_gate_kind IN ('curator','leader_awareness','chapter_witness','president_go','president_others')
      THEN '/governance/documents/' || p_chain_id::text
    -- submitter_acceptance (the GP) and anything unrecognised stay on the admin operations surface.
    ELSE '/admin/governance/documents/' || p_chain_id::text
  END;
$function$;

-- Keep the function comment in sync with the 3-branch logic (the prior ip3d comment said
-- "Admin gates -> /admin/", which now contradicts the member-route branches — #171).
COMMENT ON FUNCTION public._ip_ratify_cta_link(uuid, text) IS
  'Resolve CTA URL por gate_kind. Ratification gates (volunteers_in_role_active/member_ratification/external_signer) -> /governance/ip-agreement; outros gates de signatário não-admin (curator/leader_awareness/chapter_witness/president_go/president_others) -> /governance/documents; submitter_acceptance + desconhecido -> /admin/governance/documents. #171 (2026-06-03).';
