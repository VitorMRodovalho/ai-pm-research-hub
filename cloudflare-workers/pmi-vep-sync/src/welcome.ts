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

  const variables = {
    first_name: extractFirstName(opts.applicant_name),
    role_label: openingLabel(opts.opportunity_title, opts.role_applied),
    chapter: opts.chapter ?? 'Núcleo IA & GP',
    onboarding_url: onboardingUrl,
    expires_in_days: ttlDays
  };

  const tokenHash = await sha256Hex(opts.token);

  const { error } = await db.rpc('campaign_send_one_off', {
    p_template_slug: 'pmi_welcome_with_token',
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

function extractFirstName(fullName: string): string {
  return (fullName ?? '').trim().split(/\s+/)[0] ?? '';
}
