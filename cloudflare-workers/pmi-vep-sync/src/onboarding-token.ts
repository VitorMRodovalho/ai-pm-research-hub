/**
 * Helper para emitir onboarding_tokens.
 * Token é gerado no worker via Web Crypto API (256 bits, base64url).
 */

import type { SupabaseClient } from '@supabase/supabase-js';

export interface IssueTokenOpts {
  source_type: 'pmi_application' | 'initiative_invitation' | 'direct_assignment';
  source_id: string;
  scopes: string[];
  ttl_days: number;
  issued_by_worker?: string;
  issued_by?: string;
}

export async function issueOnboardingToken(
  db: SupabaseClient,
  opts: IssueTokenOpts
): Promise<string> {
  const token = generateSecureToken(32);
  const expiresAt = new Date(Date.now() + opts.ttl_days * 86_400_000).toISOString();

  const { error } = await db
    .from('onboarding_tokens')
    .insert({
      token,
      source_type: opts.source_type,
      source_id: opts.source_id,
      scopes: opts.scopes,
      expires_at: expiresAt,
      issued_by: opts.issued_by ?? null,
      issued_by_worker: opts.issued_by_worker ?? null
    });

  if (error) throw new Error(`issueOnboardingToken: ${error.message}`);
  return token;
}

/**
 * Generate cryptographically secure random token.
 */
export function generateSecureToken(byteLength: number = 32): string {
  const buf = new Uint8Array(byteLength);
  crypto.getRandomValues(buf);
  return base64UrlEncode(buf);
}

function base64UrlEncode(buf: Uint8Array): string {
  let str = '';
  for (let i = 0; i < buf.length; i++) {
    str += String.fromCharCode(buf[i]!);
  }
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/**
 * SHA-256 hash a token for safe metadata storage (no plaintext credential leak
 * via campaign_sends.metadata or audit logs).
 *
 * Per migration 20260516200000 R2: campaign metadata stores token_hash, not token.
 */
export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(buf))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}
