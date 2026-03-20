export type CellStatus = 'present' | 'absent' | 'na' | 'excused';

export interface AttendanceEvent {
  id: string;
  date: string;
  title: string;
  type: string;
  tribe_id: number | null;
  tribe_name: string | null;
  duration_minutes: number;
  week_number: number;
  is_tribe_event?: boolean;
  is_leadership?: boolean;
}

export interface AttendanceMember {
  id: string;
  name: string;
  rate: number;
  present_count: number;
  eligible_count: number;
  attendance: Record<string, CellStatus>;
}

export interface AttendanceGridData {
  summary: {
    overall_rate: number;
    perfect_attendance: number;
    below_50: number;
  };
  events: AttendanceEvent[];
  members: AttendanceMember[];
}

export interface CheckInResult {
  success: boolean;
  error?: 'checkin_window_expired' | 'checkin_too_early' | 'not_authenticated' | 'event_not_found';
  message?: string;
}

export interface ToggleResult {
  success: boolean;
  error?: 'permission_denied' | 'not_your_tribe';
  message?: string;
  marked?: number;
}
