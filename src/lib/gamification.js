/**
 * Resolve Credly tier by awarded points.
 * W143 reclassification: cert_pmi_senior=50, cert_cpmai=45,
 * cert_pmi_mid=40, cert_pmi_practitioner=35, cert_pmi_entry=30,
 * specialization=25, trail/knowledge_ai_pm=20, course=15, badge=10
 */
export function credlyTierFromPoints(points) {
  if (points >= 45) return 1;  // cert_pmi_senior (50), cert_cpmai (45)
  if (points >= 25) return 2;  // cert_pmi_mid (40), practitioner (35), entry (30), specialization (25)
  if (points >= 15) return 3;  // trail (20), knowledge_ai_pm (20), course (15)
  if (points >= 10) return 4;  // badge (10)
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
