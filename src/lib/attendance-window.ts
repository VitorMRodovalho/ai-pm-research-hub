// Self check-in window (hours after the event) — frontend SSOT mirror.
//
// The authoritative value lives in DB `platform_settings` under
// 'attendance.self_checkin_window_hours' and is enforced server-side by the
// register_own_presence RPC. This constant is the single frontend source that
// every check-in mirror (MyMeetingsIsland, AttendanceGrid, TribeAttendanceTab,
// attendance.astro) reads, so the button show/hide window matches the server.
//
// Locked to the DB value by tests/contracts/checkin-window-ssot.test.mjs (#1319)
// — if you change the window, update platform_settings AND this constant together.
export const SELF_CHECKIN_WINDOW_HOURS = 72;

// Interpolate the {hours} placeholder used by the check-in i18n strings
// (attendance.checkin.windowExpired, comp.myMeetings.expiredHint).
export function withCheckinHours(msg: string): string {
  return msg.replace('{hours}', String(SELF_CHECKIN_WINDOW_HOURS));
}
