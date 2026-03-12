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

  useEffect(() => {
    (async () => {
      const sb = await waitForSb();
      if (!sb) { setIsLoading(false); return; }

      const { data: { user } } = await sb.auth.getUser();
      if (!user) { setIsLoading(false); return; }

      const cached = (window as any).navGetMember?.();
      if (cached) {
        setMember({
          id: cached.id,
          operational_role: cached.operational_role || 'guest',
          designations: cached.designations || [],
          is_superadmin: cached.is_superadmin || false,
          tribe_id: cached.tribe_id || null,
        });
        setIsLoading(false);
        return;
      }

      const { data } = await sb.rpc('get_member_by_auth');
      if (data) {
        setMember({
          id: data.id,
          operational_role: data.operational_role || 'guest',
          designations: data.designations || [],
          is_superadmin: data.is_superadmin || false,
          tribe_id: data.tribe_id || null,
        });
      }
      setIsLoading(false);
    })();
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
