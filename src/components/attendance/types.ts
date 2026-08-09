// #1657: 'unrecorded' = elegível, evento passado e NÃO SELADO, sem linha de presença. Antes isto
// era renderizado como 'absent', então quem não clicou era indistinguível de quem faltou. Selar o
// evento (`seal_event_attendance`) materializa a linha de no-show e é o ato que transforma omissão
// em ausência; enquanto ninguém sela, a célula diz "sem registro" e não acusa.
export type CellStatus = 'present' | 'absent' | 'na' | 'excused' | 'scheduled' | 'unrecorded';

export interface AttendanceEvent {
  id: string;
  date: string;
  title: string;
  type: string;
  tribe_id: number | null;
  initiative_id: string | null;
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
