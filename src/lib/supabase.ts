import { createClient } from '@supabase/supabase-js';

const SB_URL  = import.meta.env.PUBLIC_SUPABASE_URL;
const SB_KEY  = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

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
  created_at?: string;
  updated_at?: string;
}

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
  if (!_client) {
    _client = createClient(SB_URL, SB_KEY, {
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
