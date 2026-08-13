// ─── Admin Shared Constants ───
// Used by admin page and potentially other admin components

import { hasPermission } from '../permissions.ts';

// #1590 — a autoridade de rota mora em `route-access.ts` e é REEXPORTADA daqui, para que os
// call sites existentes (`import { canAccessAdminRoute } from '.../admin/constants'`) sigam
// valendo. O motivo da separação está no cabeçalho de lá: este arquivo arrasta i18n e dados de
// tribo, e isso impedia um contrato de exercer o predicado de verdade.
export * from './route-access.ts';

export const OPROLE_LABELS: Record<string, string> = {
  manager: 'Gerente', deputy_manager: 'Deputy PM', tribe_leader: 'Líder de Tribo',
  researcher: 'Pesquisador', facilitator: 'Facilitador', communicator: 'Multiplicador',
  sponsor: 'Patrocinador', institutional_auditor: 'Auditor Institucional',
  none: 'Sem papel', guest: 'Convidado'
};

export const OPROLE_COLORS: Record<string, string> = {
  manager: '#FF610F', deputy_manager: '#FF610F', tribe_leader: '#4F17A8',
  researcher: '#EC4899', facilitator: '#06B6D4', communicator: '#8B5CF6',
  sponsor: '#BE2027', institutional_auditor: '#0D9488', none: '#94A3B8', guest: '#94A3B8'
};

export const DESIG_LABELS: Record<string, string> = {
  sponsor: 'Patrocinador', chapter_liaison: 'Ponto Focal', ambassador: 'Embaixador',
  founder: 'Fundador', curator: 'Curador', comms_team: 'Comunicação',
  co_gp: 'Co-GP', tribe_leader: 'Líder de Tribo',
  comms_leader: 'Líder de Comunicação', comms_member: 'Membro de Comunicação'
};

export const DESIG_COLORS: Record<string, string> = {
  sponsor: '#BE2027', chapter_liaison: '#0284C7', ambassador: '#10B981',
  founder: '#7C3AED', curator: '#D97706', comms_team: '#06B6D4',
  co_gp: '#FF610F', tribe_leader: '#4F17A8',
  comms_leader: '#06B6D4', comms_member: '#06B6D4'
};

export const TRIBE_NAMES: Record<number, string> = {
  1: 'Radar Tecnológico', 2: 'Agentes Autônomos', 3: 'TMO & PMO do Futuro',
  4: 'Cultura & Change', 5: 'Talentos & Upskilling', 6: 'ROI & Portfólio',
  7: 'Governança & Trustworthy AI', 8: 'Inclusão & Colaboração'
};

export const TRIBE_LEADERS: Record<number, string> = {
  1: 'Hayala Curto', 2: 'Débora Moura', 3: 'Marcel Fleming',
  4: 'Fernando Maquiaveli', 5: 'Jefferson Pinto', 6: 'Fabricio Costa',
  7: 'Marcos Klemz', 8: 'Ana Carla Cavalcante'
};

export const TRIBE_COLORS: Record<number, string> = {
  1: '#00799E', 2: '#00799E', 3: '#FF610F', 4: '#FF610F',
  5: '#4F17A8', 6: '#4F17A8', 7: '#10B981', 8: '#10B981'
};

export const TIER_LABELS: Record<string, string> = {
  superadmin: '🔧 Superadmin (CRUD total)',
  admin: '⚙️ Admin (gestão completa)',
  leader: '🏷️ Líder (tribo read-only)',
  observer: '👁️ Observador (KPIs agregados)',
  member: '👤 Membro (perfil + participação)',
  visitor: '🚫 Visitante (apenas página pública)',
};

export { MAX_SLOTS } from '../../data/tribes.ts';
export const ELIGIBLE_ROLES = ['researcher', 'facilitator', 'communicator'];

export const CATEGORY_META: Record<string, { icon: string; color: string; bg: string }> = {
  attendance: { icon: '📅', color: '#2563EB', bg: '#EFF6FF' },
  course:     { icon: '🎓', color: '#7C3AED', bg: '#F5F3FF' },
  artifact:   { icon: '📄', color: '#059669', bg: '#ECFDF5' },
  bonus:      { icon: '⭐', color: '#D97706', bg: '#FFFBEB' },
};

// ─── Helper functions ───

export function initials(name: string): string {
  return name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase();
}

export function avatar(m: any, size = 'w-8 h-8'): string {
  return m.photo_url
    ? `<img src="${m.photo_url}" class="${size} rounded-full object-cover flex-shrink-0" alt="">`
    : `<div class="${size} rounded-full bg-teal flex items-center justify-center text-white font-bold text-[.6rem] flex-shrink-0">${initials(m?.name)}</div>`;
}

export function memberTags(m: any): string {
  const opRole = m.operational_role || 'guest';
  const desigs: string[] = m.designations?.length ? m.designations : [];
  let html = '';

  if (opRole !== 'none' && opRole !== 'guest') {
    const c = OPROLE_COLORS[opRole] || '#94A3B8';
    html += `<span class="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style="background:${c}18;color:${c}">${OPROLE_LABELS[opRole] || opRole}</span>`;
  }

  desigs.forEach(d => {
    const c = DESIG_COLORS[d] || '#94A3B8';
    html += `<span class="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style="background:${c}18;color:${c}">${DESIG_LABELS[d] || d}</span>`;
  });

  if (m.is_superadmin) {
    html += `<span class="text-[.6rem] font-bold px-1.5 py-0.5 rounded bg-orange/10 text-orange">🔧 SA</span>`;
  }

  if (opRole === 'guest' && desigs.length === 0) {
    html += `<span class="text-[.6rem] font-bold px-1.5 py-0.5 rounded bg-[var(--surface-section-cool)] text-[var(--text-muted)]">Convidado</span>`;
  }

  return html;
}

export function memberTribeTag(m: any): string {
  const tid = m.selected_tribe_id || m.fixed_tribe_id || m.tribe_id;
  if (!tid) return '<span class="text-[.6rem] text-[var(--text-muted)]">sem tribo</span>';
  const color = TRIBE_COLORS[tid] || '#94A3B8';
  return `<span class="text-[.6rem] font-bold px-1.5 py-0.5 rounded" style="background:${color}18;color:${color}">T${String(tid).padStart(2,'0')}</span>`;
}

export function canAccessWebinarsWorkspace(member: any): boolean {
  if (!member) return false;
  return hasPermission(member, 'board.view_global');
}

export function canAccessPublicationsWorkspace(member: any): boolean {
  if (!member) return false;
  return hasPermission(member, 'content.view_publications');
}

