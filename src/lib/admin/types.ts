export interface Member {
  id: string;
  name: string;
  full_name: string;
  email: string;
  photo_url: string | null;
  operational_role: string;
  designations: string[];
  is_superadmin: boolean;
  is_active: boolean;
  tribe_id: number | null;
  initiative_id: string | null;
  selected_tribe_id: number | null;
  fixed_tribe_id: number | null;
  chapter: string;
  auth_id: string | null;
  credly_username: string | null;
  last_seen_at: string | null;
  total_sessions: number;
  created_at: string;
  updated_at: string;
}

export interface Tribe {
  id: number;
  name: string;
  shorthand: string;
  emoji: string;
  description: string;
  leader_name: string;
  member_count: number;
  meeting_day: string | null;
  meeting_time: string | null;
  meeting_link: string | null;
  whatsapp_link: string | null;
  drive_link: string | null;
  miro_link: string | null;
  is_active: boolean;
}

export interface AdminStats {
  total: number;
  active: number;
  pending: number;
  inactive: number;
  noAuth: number;
  chapters: number;
  tribes: number;
  verified: number;
}

export interface AuditLogEntry {
  id: string;
  actor_id: string;
  action: string;
  target_type: string;
  target_id: string | null;
  changes: Record<string, unknown>;
  metadata: Record<string, unknown>;
  created_at: string;
}
