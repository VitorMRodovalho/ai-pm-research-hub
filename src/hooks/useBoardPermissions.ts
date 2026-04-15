/**
 * useBoardPermissions.ts — Access control based on member role + board scope
 * W144: Respects simulation state from permissions.ts
 */
import { useState, useEffect } from 'react';
import type { Board } from '../types/board';
import { waitForSb } from './useBoard';
import { getSimulation, type OperationalTier } from '../lib/permissions';

interface MemberContext {
  id: string;
  operational_role: string;
  designations: string[];
  is_superadmin: boolean;
  tribe_id: number | null;
  initiative_id: string | null;
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
  canManageBoard: boolean;
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
      initiative_id: raw.initiative_id || null,
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
      canManageBoard: false, isLoading, member: null,
    };
  }

  // W144: Apply simulation overlay if active
  const sim = getSimulation();
  const effectiveRole = sim.active && sim.tier ? sim.tier : member.operational_role;
  const effectiveDesig = sim.active ? sim.designations : member.designations;
  const effectiveInitiativeId = sim.active && sim.initiative_id ? sim.initiative_id : member.initiative_id;
  const effectiveTribeId = sim.active && sim.tribe_id !== null ? sim.tribe_id : member.tribe_id;
  const effectiveSuperadmin = sim.active ? false : member.is_superadmin;

  const tier = ROLE_TIER[effectiveRole] ?? 5;
  const isSuperadmin = effectiveSuperadmin;
  const isManager = tier <= 2.5;
  const isLeader = tier <= 3;
  const isOwnTribe = board.board_scope === 'tribe' && (
    (board.initiative_id && effectiveInitiativeId ? board.initiative_id === effectiveInitiativeId : false)
    || board.tribe_id === effectiveTribeId
  );
  const isGlobal = board.board_scope === 'global';
  const isComms = effectiveDesig.some((d: string) => ['comms_leader', 'comms_member'].includes(d));
  const isCurator = effectiveDesig.includes('curator') || effectiveDesig.includes('co_gp');

  const canManageBoard = isSuperadmin || isManager || (isLeader && isOwnTribe);
  // Comms team has full editorial control over global boards (communication hub)
  const isCommsOnGlobal = isComms && isGlobal;

  return {
    canView: isSuperadmin || isManager || isGlobal || isOwnTribe,
    canCreate: canManageBoard || isCommsOnGlobal || (isOwnTribe && tier <= 4),
    canEditOwn: tier <= 4,
    canEditAny: canManageBoard || isCommsOnGlobal,
    canMove: canManageBoard || isCommsOnGlobal || (isOwnTribe && tier <= 4),
    canAssign: canManageBoard || isCommsOnGlobal,
    canCurate: canManageBoard || isCurator,
    canDelete: canManageBoard,
    canManageBoard,
    isLoading,
    member,
  };
}
