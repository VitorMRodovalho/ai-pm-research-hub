// Module-level singleton Supabase client for the PMI onboarding portal.
// Avoids "Multiple GoTrueClient instances" warning when multiple components
// mount and each calls createClient.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let _client: SupabaseClient | null = null;

export function getPMISupabaseClient(url: string, anonKey: string): SupabaseClient {
  if (_client) return _client;
  _client = createClient(url, anonKey, {
    auth: {
      // PMI candidate portal does NOT use Supabase Auth — token is the credential.
      // Disabling persistSession + autoRefreshToken prevents the GoTrueClient from
      // creating a parallel auth state alongside the main BaseLayout/Nav client.
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  return _client;
}
