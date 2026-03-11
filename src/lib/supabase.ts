import { createClient } from '@supabase/supabase-js';

function readRuntimePublicEnv(key: '__PUBLIC_SUPABASE_URL' | '__PUBLIC_SUPABASE_ANON_KEY'): string {
  if (typeof window === 'undefined') return '';
  const value = (window as any)[key];
  return typeof value === 'string' ? value.trim() : '';
}

const _runtimeSupabaseConfig = {
  url: '',
  anonKey: '',
};

export function setSupabaseRuntimeConfig(url: string, anonKey: string) {
  _runtimeSupabaseConfig.url = typeof url === 'string' ? url.trim() : '';
  _runtimeSupabaseConfig.anonKey = typeof anonKey === 'string' ? anonKey.trim() : '';
}

function resolveSupabasePublicEnv() {
  const url = (
    import.meta.env.PUBLIC_SUPABASE_URL ||
    _runtimeSupabaseConfig.url ||
    readRuntimePublicEnv('__PUBLIC_SUPABASE_URL') ||
    ''
  ).trim();
  const anonKey = (
    import.meta.env.PUBLIC_SUPABASE_ANON_KEY ||
    _runtimeSupabaseConfig.anonKey ||
    readRuntimePublicEnv('__PUBLIC_SUPABASE_ANON_KEY') ||
    ''
  ).trim();
  return { url, anonKey };
}

function getMissingSupabaseEnvVars(url: string, anonKey: string): string[] {
  const missing: string[] = [];
  if (!url) missing.push('PUBLIC_SUPABASE_URL');
  if (!anonKey) missing.push('PUBLIC_SUPABASE_ANON_KEY');
  return missing;
}

function assertSupabaseEnvConfigured() {
  const { url, anonKey } = resolveSupabasePublicEnv();
  const missing = getMissingSupabaseEnvVars(url, anonKey);
  if (missing.length === 0) return { url, anonKey };
  const details = missing.join(', ');
  throw new Error(
    `[Supabase Config Error] Missing required public environment variable(s): ${details}. ` +
    `Configure them in the deployment environment (Production/Preview) and redeploy.`
  );
}

// ── Typed member ─────────────────────────────────────────────
export type MemberRole =
  | 'manager' | 'tribe_leader' | 'researcher'
  | 'ambassador' | 'curator' | 'sponsor' | 'founder'
  | 'facilitator' | 'communicator' | 'guest';

export interface Member {
  id: string;
  name: string;
  email: string;
  secondary_emails?: string[];
  pmi_id?: string;
  phone?: string;
  role: MemberRole;
  roles?: MemberRole[];
  chapter?: string;
  tribe_id?: number;
  current_cycle_active: boolean;
  is_superadmin?: boolean;
  photo_url?: string;
  linkedin_url?: string;
  auth_id?: string;
  inactivated_at?: string;
  inactivation_reason?: string;
  cpmai_certified?: boolean;
  credly_badges?: any[];
  credly_url?: string;
  created_at?: string;
  updated_at?: string;
}

// ── Role labels (PT-BR fallback, used when i18n not available) ──
export const ROLE_LABELS: Record<string, string> = {
  manager:      'Gerente',
  tribe_leader: 'Líder de Tribo',
  researcher:   'Pesquisador',
  ambassador:   'Embaixador',
  curator:      'Curador',
  sponsor:      'Patrocinador',
  founder:      'Fundador',
  facilitator:  'Facilitador',
  communicator: 'Multiplicador',
  guest:        'Visitante',
};

/**
 * Get localized role label. Reads from DOM i18n data if available,
 * falls back to hardcoded PT-BR labels.
 */
export function getLocalizedRoleLabel(role: string): string {
  try {
    const el = document.getElementById('role-labels-data');
    if (el) {
      const labels = JSON.parse(el.textContent || '{}');
      if (labels[role]) return labels[role];
    }
  } catch {}
  return ROLE_LABELS[role] || role;
}

export const ROLE_COLORS: Record<string, string> = {
  manager:      '#FF610F',
  tribe_leader: '#4F17A8',
  researcher:   '#EC4899',
  ambassador:   '#10B981',
  curator:      '#D97706',
  sponsor:      '#BE2027',
  founder:      '#7C3AED',
  facilitator:  '#EC4899',
  communicator: '#EC4899',
};

// ── Client factory (browser-safe singleton) ───────────────────
let _client: ReturnType<typeof createClient> | null = null;

export function getSupabase() {
  const { url, anonKey } = assertSupabaseEnvConfigured();
  if (!_client) {
    _client = createClient(url, anonKey, {
      auth: { persistSession: true, detectSessionInUrl: true },
    });
  }
  return _client;
}

// ── Auth helpers ─────────────────────────────────────────────
export async function getCurrentMember(): Promise<Member | null> {
  const sb = getSupabase();
  const { data } = await sb.rpc('get_member_by_auth');
  return data ?? null;
}

export async function getCurrentSession() {
  const sb = getSupabase();
  const { data: { session } } = await sb.auth.getSession();
  return session;
}
