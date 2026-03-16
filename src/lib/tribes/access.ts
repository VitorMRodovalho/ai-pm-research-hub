import { hasMinimumTier, resolveTierFromMember } from '../admin/constants';
import { hasPermission } from '../permissions';

export function isActivePlatformMember(member: any): boolean {
  if (!member) return false;
  if (member.current_cycle_active === false) return false;
  if (member.is_active === false) return false;
  return resolveTierFromMember(member) !== 'visitor';
}

export function canExploreTribes(member: any): boolean {
  if (!isActivePlatformMember(member)) return false;
  return hasMinimumTier(resolveTierFromMember(member), 'member');
}

export function canManageTribeLifecycle(member: any): boolean {
  if (!isActivePlatformMember(member)) return false;
  return hasPermission(member, 'admin.access');
}

export function canSeeInactiveTribes(member: any): boolean {
  if (!member) return false;
  return hasPermission(member, 'system.global_config');
}
