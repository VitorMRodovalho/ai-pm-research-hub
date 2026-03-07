/**
 * Resolve Credly tier by awarded points.
 * verify-credly currently assigns:
 * T1=50, T2=25, T3=15, T4=10
 */
export function credlyTierFromPoints(points) {
  if (points === 50) return 1;
  if (points === 25) return 2;
  if (points === 15) return 3;
  if (points === 10) return 4;
  return 0;
}

/**
 * Aggregate Credly rows grouped by member.
 * Input rows should be filtered to reason like "Credly:%".
 */
export function aggregateCredlyByMember(rows) {
  const map = {};
  for (const row of rows || []) {
    const memberId = row.member_id;
    if (!memberId) continue;
    if (!map[memberId]) {
      map[memberId] = { total: 0, badges: 0, t1: 0, t2: 0, t3: 0, t4: 0 };
    }
    const tier = credlyTierFromPoints(row.points || 0);
    map[memberId].total += row.points || 0;
    map[memberId].badges += 1;
    if (tier === 1) map[memberId].t1 += 1;
    if (tier === 2) map[memberId].t2 += 1;
    if (tier === 3) map[memberId].t3 += 1;
    if (tier === 4) map[memberId].t4 += 1;
  }
  return map;
}
