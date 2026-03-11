import { hasMinimumTier, resolveTierFromMember } from '../admin/constants';

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
  const designations = Array.isArray(member.designations) ? member.designations : [];
  return member.is_superadmin === true
    || member.operational_role === 'manager'
    || member.operational_role === 'deputy_manager'
    || designations.includes('co_gp');
}

export function canSeeInactiveTribes(member: any): boolean {
  return member?.is_superadmin === true;
}
