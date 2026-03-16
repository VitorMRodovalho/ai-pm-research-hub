export function buildTrailProgressByMember(rows = [], trailTotal = 6) {
  const byMember = new Map();

  for (const row of rows || []) {
    const memberId = row?.member_id ? String(row.member_id) : '';
    const courseId = row?.course_id ? String(row.course_id) : '';
    const status = String(row?.status || '').toLowerCase();
    if (!memberId || !courseId) continue;

    if (!byMember.has(memberId)) {
      byMember.set(memberId, { completedSet: new Set(), inProgressSet: new Set() });
    }

    const bucket = byMember.get(memberId);
    if (status === 'completed') {
      bucket.completedSet.add(courseId);
      bucket.inProgressSet.delete(courseId);
      continue;
    }
    if (status === 'in_progress' && !bucket.completedSet.has(courseId)) {
      bucket.inProgressSet.add(courseId);
    }
  }

  const result = new Map();
  for (const [memberId, bucket] of byMember.entries()) {
    const completed = bucket.completedSet.size;
    const inProgress = bucket.inProgressSet.size;
    const pct = trailTotal > 0 ? Math.round((completed / trailTotal) * 100) : 0;
    result.set(memberId, { completed, inProgress, pct });
  }

  return result;
}
