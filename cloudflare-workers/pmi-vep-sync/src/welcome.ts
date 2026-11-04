/**
 * Welcome message dispatcher.
 *
 * Per migration 20260516200000 B3: usa wrapper RPC `campaign_send_one_off`
 * (slug-based template lookup → admin_send_campaign external_contacts).
 *
 * PRE-DEPLOY: PM precisa seedar campaign_templates com slug =
 * 'pmi_welcome_with_token' antes do worker entrar em prod. Template deve ter
 * placeholders: {{first_name}}, {{role_label}}, {{chapter}}, {{onboarding_url}},
 * {{expires_in_days}}.
 *
 * Per R2: token PLAINTEXT NÃO vai em metadata — apenas sha256 hash para
 * troubleshooting. Token é a credencial do candidato; armazenar plain seria
 * leak via campaign_sends queryable.
 */

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Env } from './types';
import { sha256Hex } from './onboarding-token';
import { openingLabel } from './opening-label';

export interface DispatchWelcomeOpts {
  application_id: string;
  applicant_name: string;
  email: string;
  role_applied: string;
  opportunity_title?: string | null;  // #2847: the email names the opening
  evaluation_track?: string | null;   // #2393 A3: the line pilot opening has its own email
  video_invite_by?: string | null;    // #2393 A3: the date the pilot email promises (YYYY-MM-DD)
  chapter: string | null;
  token: string;
}

export async function dispatchWelcome(
  db: SupabaseClient,
  env: Env,
  opts: DispatchWelcomeOpts
): Promise<{ success: boolean; reason?: string }> {
  const onboardingUrl = `${env.ONBOARDING_BASE_URL}/${opts.token}`;
  const ttlDays = parseInt(env.ONBOARDING_TOKEN_TTL_DAYS, 10) || 7;

  // #2393 A3 (ADR-0134): the line pilot opening sends its own email, with the steps and the promised date of the
  // video invitation. Without that date there is nothing to promise, so the general email stays.
  const pilot = opts.evaluation_track === 'line_pilot' && Boolean(opts.video_invite_by);
  const templateSlug = pilot ? 'pmi_welcome_line_pilot' : 'pmi_welcome_with_token';

  const variables = {
    first_name: extractFirstName(opts.applicant_name),
    role_label: openingLabel(opts.opportunity_title, opts.role_applied),
    chapter: opts.chapter ?? 'Núcleo IA & GP',
    onboarding_url: onboardingUrl,
    expires_in_days: ttlDays,
    ...(pilot ? { video_invite_by: brDate(opts.video_invite_by as string) } : {})
  };

  const tokenHash = await sha256Hex(opts.token);

  const { error } = await db.rpc('campaign_send_one_off', {
    p_template_slug: templateSlug,
    p_to_email: opts.email,
    p_variables: variables,
    p_metadata: {
      source: 'pmi-vep-sync',
      application_id: opts.application_id,
      onboarding_token_hash: tokenHash
    }
  });

  if (error) {
    console.error('dispatchWelcome failed:', error.message, { application_id: opts.application_id });
    return { success: false, reason: error.message };
  }

  return { success: true };
}

/** #2393 A3: YYYY-MM-DD (the column) becomes DD/MM/YYYY (the email is sent in pt-BR). */
export function brDate(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso.trim());
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
}

function extractFirstName(fullName: string): string {
  return (fullName ?? '').trim().split(/\s+/)[0] ?? '';
}
