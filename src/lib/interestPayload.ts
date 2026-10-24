/**
 * #2738: the capture_visitor_lead payload of the interest form (InterestForm.tsx), kept pure and free of
 * JSX so the contract test exercises it without a DOM or a database.
 */
// #2553 PR 2: as três portas da home passam a usar o mesmo formulário: pesquisador, capítulo PMI e organização.
export type InterestRole = 'researcher' | 'leader' | 'chapter' | 'partner';
export type InterestSource = 'apply-vertical' | 'apply-resources' | 'home-join';

export function buildInterestPayload(
  input: { name: string; email: string; message: string },
  opts: { roleInterest: InterestRole; source: InterestSource; targetVertical?: string | null },
  search: string,
): Record<string, unknown> {
  const params = new URLSearchParams(search);
  const utm: Record<string, string> = {};
  for (const k of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content']) {
    const v = params.get(k); if (v) utm[k] = v;
  }
  const refMember = params.get('ref') || params.get('referrer');
  const payload: Record<string, unknown> = {
    name: input.name,
    email: input.email,
    message: input.message || null,
    role_interest: opts.roleInterest,
    lgpd_consent: true,
    source: opts.source,
  };
  if (opts.targetVertical) payload.target_vertical = opts.targetVertical;
  if (Object.keys(utm).length > 0) payload.utm_data = utm;
  if (refMember) payload.referrer_member_id = refMember;
  return payload;
}
