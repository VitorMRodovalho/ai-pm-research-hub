/**
 * Build per-member trail progress from course_progress rows.
 * Source of truth: course_progress table (status by member/course).
 */
export function buildTrailProgressByMember(rows, totalCourses = 8) {
  const byMemberCourse = new Map();

  for (const row of rows || []) {
    const memberId = row?.member_id;
    const courseId = row?.course_id;
    const status = row?.status;
    if (!memberId || !courseId) continue;
    if (status !== 'completed' && status !== 'in_progress') continue;

    const key = `${memberId}::${courseId}`;
    const prev = byMemberCourse.get(key);
    // completed supersedes in_progress when duplicate rows exist.
    if (prev === 'completed') continue;
    if (status === 'completed' || !prev) byMemberCourse.set(key, status);
  }

  const byMember = new Map();
  for (const [key, status] of byMemberCourse.entries()) {
    const memberId = key.split('::')[0];
    if (!byMember.has(memberId)) byMember.set(memberId, { completed: 0, inProgress: 0, pct: 0 });
    const acc = byMember.get(memberId);
    if (status === 'completed') acc.completed += 1;
    if (status === 'in_progress') acc.inProgress += 1;
  }

  for (const value of byMember.values()) {
    const safeTotal = Math.max(totalCourses, 1);
    value.pct = Math.round((value.completed / safeTotal) * 100);
  }

  return byMember;
}
