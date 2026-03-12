/**
 * useBoardPermissions.ts — Access control based on member role + board scope
 */
import { useState, useEffect } from 'react';
import type { Board } from '../types/board';
import { waitForSb } from './useBoard';

interface MemberContext {
  id: string;
  operational_role: string;
  designations: string[];
  is_superadmin: boolean;
  tribe_id: number | null;
}

interface Permissions {
  canView: boolean;
  canCreate: boolean;
  canEditOwn: boolean;
  canEditAny: boolean;
  canMove: boolean;
  canAssign: boolean;
  canCurate: boolean;
  canDelete: boolean;
  isLoading: boolean;
  member: MemberContext | null;
}

const ROLE_TIER: Record<string, number> = {
  sponsor: 1, chapter_liaison: 1.5, manager: 2, deputy_manager: 2.5,
  tribe_leader: 3, researcher: 4, facilitator: 4, communicator: 4, guest: 5,
};

/**
 * Resolve authenticated member context. Useful for components that
 * need member info without a specific Board (e.g. CuratorshipBoardIsland).
 */
export function useMemberContext() {
  const [member, setMember] = useState<MemberContext | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  function applyMember(raw: any) {
    if (!raw) return;
    setMember({
      id: raw.id,
      operational_role: raw.operational_role || 'guest',
      designations: raw.designations || [],
      is_superadmin: raw.is_superadmin || false,
      tribe_id: raw.tribe_id || null,
    });
    setIsLoading(false);
  }

  useEffect(() => {
    let resolved = false;

    (async () => {
      // Try cached member first (fastest path)
      const cached = (window as any).navGetMember?.();
      if (cached) { resolved = true; applyMember(cached); return; }

      const sb = await waitForSb();
      if (!sb) { setIsLoading(false); return; }

      try {
        const userRes = await sb.auth.getUser?.();
        if (!userRes?.data?.user) { setIsLoading(false); return; }
      } catch {
        setIsLoading(false);
        return;
      }

      // Re-check cache after awaiting sb (nav may have booted in parallel)
      const cached2 = (window as any).navGetMember?.();
      if (cached2) { resolved = true; applyMember(cached2); return; }

      const { data } = await sb.rpc('get_member_by_auth');
      if (data) { resolved = true; applyMember(data); return; }
      setIsLoading(false);
    })();

    // Fallback: listen for nav:member event (fires when nav boots after island)
    function onNavMember(e: Event) {
      const detail = (e as CustomEvent).detail;
      if (detail && !resolved) {
        resolved = true;
        applyMember(detail);
      }
    }
    window.addEventListener('nav:member', onNavMember);
    return () => window.removeEventListener('nav:member', onNavMember);
  }, []);

  return { member, isLoading };
}

export function useBoardPermissions(board: Board | null): Permissions {
  const { member, isLoading } = useMemberContext();

  if (!member || !board) {
    return {
      canView: false, canCreate: false, canEditOwn: false, canEditAny: false,
      canMove: false, canAssign: false, canCurate: false, canDelete: false,
      isLoading, member: null,
    };
  }

  const tier = ROLE_TIER[member.operational_role] ?? 5;
  const isSuperadmin = member.is_superadmin;
  const isManager = tier <= 2.5;
  const isLeader = tier <= 3;
  const isOwnTribe = board.board_scope === 'tribe' && board.tribe_id === member.tribe_id;
  const isGlobal = board.board_scope === 'global';
  const isComms = member.designations.some((d) => ['comms_leader', 'comms_member'].includes(d));
  const isCurator = member.designations.includes('curator') || member.designations.includes('co_gp');

  return {
    canView: isSuperadmin || isManager || isGlobal || isOwnTribe,
    canCreate: isSuperadmin || isManager || (isLeader && isOwnTribe) || (isComms && isGlobal) || tier <= 4,
    canEditOwn: tier <= 4,
    canEditAny: isSuperadmin || isManager || (isLeader && isOwnTribe),
    canMove: isSuperadmin || isManager || (isLeader && isOwnTribe) || (isComms && isGlobal) || tier <= 4,
    canAssign: isSuperadmin || isManager || (isLeader && isOwnTribe) || (isComms && isGlobal),
    canCurate: isSuperadmin || isManager || (isLeader && isOwnTribe) || isCurator,
    canDelete: isSuperadmin || isManager || (isLeader && isOwnTribe),
    isLoading,
    member,
  };
}
