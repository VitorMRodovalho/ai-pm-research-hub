// Isolated tribe permissions helper — avoids bundler issues when
// permissions.ts is imported from both Astro inline scripts and React islands

export function getTribePermissions(member: any, viewingTribeId: number, viewingInitiativeId?: string | null) {
  const isOwnTribe = viewingInitiativeId
    ? member?.initiative_id === viewingInitiativeId
    : member?.tribe_id === viewingTribeId;
  const isSuperadmin = !!member?.is_superadmin;
  const desigs: string[] = member?.designations || [];
  const role = member?.operational_role || '';
  const isGP = role === 'manager'
    || desigs.includes('deputy_manager')
    || desigs.includes('co_gp');
  const isAdmin = isSuperadmin || isGP;
  const isStakeholder = role === 'sponsor' || role === 'chapter_liaison';
  const isLeader = role === 'tribe_leader';
  const isLeaderOwnTribe = isLeader && isOwnTribe;
  const isResearcher = role === 'researcher';
  const isObserver = role === 'observer';
  const isCurator = desigs.includes('curator');
  const isComms = desigs.some(d => d === 'comms_leader' || d === 'comms_member');

  return {
    canSeeAllTribes: true,
    hasHomeTribe: member?.initiative_id != null || member?.tribe_id != null,
    isViewingOwnTribe: isOwnTribe,
    showCrossTribeBanner: !isOwnTribe && !isAdmin && member?.tribe_id != null,
    showCuratorBanner: isCurator && !isOwnTribe,
    canCreateEvent: isAdmin || isLeaderOwnTribe,
    canEditTribeInfo: isAdmin || isLeaderOwnTribe,
    canToggleAttendance: isAdmin || isLeaderOwnTribe,
    canSelfCheckIn: !isStakeholder && !isObserver && (isOwnTribe || isAdmin),
    selfCheckInHasWindow: isResearcher && !isSuperadmin,
    canSeeExcuseReason: isAdmin,
    showDetailedMetrics: isOwnTribe || isAdmin || isStakeholder,
    canEditBoardItems: isAdmin || isLeaderOwnTribe || (isResearcher && isOwnTribe),
    canReviewCuration: isCurator,
    canSeeFullGamification: true,
    isAdmin,
    isStakeholder,
    isLeaderOwnTribe,
    isCurator,
    isComms,
  };
}
