/**
 * Independent oracle for the canonical roster count (#1249).
 *
 * get_initiative_roster_count is COUNT(DISTINCT person_id) over v_initiative_roster (a person with two
 * engagements on the same initiative — e.g. volunteer + speaker — is ONE roster member). Single-source
 * contract tests derive the expected count from the view with the SAME distinct-person definition, so
 * they compare the RPC against the view without hardcoding a cohort fixture that dies at every cohort
 * change (kickoff reorg, #1247 phantom-membership regularization).
 *
 * Cross-ref: issue #1249; SPEC p277/#419 (participants-only roster).
 */
export async function rosterViewCount(sb, initiativeId) {
  const { data, error } = await sb
    .from('v_initiative_roster')
    .select('person_id')
    .eq('initiative_id', initiativeId);
  if (error) throw error;
  return new Set((data || []).map((r) => r.person_id)).size;
}
