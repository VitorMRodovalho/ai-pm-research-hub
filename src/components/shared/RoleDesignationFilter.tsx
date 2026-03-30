import { useState } from 'react';

const ROLES = [
  { value: 'manager', pt: 'Gerente', en: 'Manager', es: 'Gerente' },
  { value: 'deputy_manager', pt: 'Deputy', en: 'Deputy Manager', es: 'Subgerente' },
  { value: 'tribe_leader', pt: 'Líder de Tribo', en: 'Tribe Leader', es: 'Líder de Tribu' },
  { value: 'researcher', pt: 'Pesquisador', en: 'Researcher', es: 'Investigador' },
  { value: 'facilitator', pt: 'Facilitador', en: 'Facilitator', es: 'Facilitador' },
  { value: 'communicator', pt: 'Comunicação', en: 'Communications', es: 'Comunicación' },
  { value: 'sponsor', pt: 'Patrocinador', en: 'Sponsor', es: 'Patrocinador' },
  { value: 'chapter_liaison', pt: 'Ponto Focal', en: 'Chapter Liaison', es: 'Enlace de Capítulo' },
  { value: 'observer', pt: 'Observador', en: 'Observer', es: 'Observador' },
];

const DESIGNATIONS = [
  { value: 'curator', pt: 'Curador', en: 'Curator', es: 'Curador' },
  { value: 'ambassador', pt: 'Embaixador', en: 'Ambassador', es: 'Embajador' },
  { value: 'founder', pt: 'Fundador', en: 'Founder', es: 'Fundador' },
  { value: 'comms_leader', pt: 'Líder Comms', en: 'Comms Leader', es: 'Líder Comms' },
  { value: 'comms_member', pt: 'Membro Comms', en: 'Comms Member', es: 'Miembro Comms' },
  { value: 'co_gp', pt: 'Co-GP', en: 'Co-GP', es: 'Co-GP' },
];

interface Props {
  lang?: string;
  onFilterChange: (filter: { role?: string; designation?: string }) => void;
  className?: string;
}

export function RoleDesignationFilter({ lang, onFilterChange, className }: Props) {
  const [role, setRole] = useState('');
  const [desig, setDesig] = useState('');
  const loc = lang?.startsWith('en') ? 'en' : lang?.startsWith('es') ? 'es' : 'pt';
  const l = { pt: { allR: 'Todos os papéis', allD: 'Todas as designações', r: 'Papel', d: 'Designação' }, en: { allR: 'All roles', allD: 'All designations', r: 'Role', d: 'Designation' }, es: { allR: 'Todos los roles', allD: 'Todas las designaciones', r: 'Rol', d: 'Designación' } }[loc]!;

  return (
    <div className={`flex flex-wrap gap-2 ${className || ''}`}>
      <select value={role} onChange={e => { setRole(e.target.value); onFilterChange({ role: e.target.value || undefined, designation: desig || undefined }); }}
        className="rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] px-2 py-1.5 text-[.75rem] text-[var(--text-primary)]">
        <option value="">{l.allR}</option>
        <optgroup label={l.r}>
          {ROLES.map(r => <option key={r.value} value={r.value}>{r[loc as 'pt']}</option>)}
        </optgroup>
      </select>
      <select value={desig} onChange={e => { setDesig(e.target.value); onFilterChange({ role: role || undefined, designation: e.target.value || undefined }); }}
        className="rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] px-2 py-1.5 text-[.75rem] text-[var(--text-primary)]">
        <option value="">{l.allD}</option>
        <optgroup label={l.d}>
          {DESIGNATIONS.map(d => <option key={d.value} value={d.value}>{d[loc as 'pt']}</option>)}
        </optgroup>
      </select>
    </div>
  );
}

export function applyRoleDesignationFilter<T extends { operational_role?: string; designations?: string[] }>(
  members: T[], filter: { role?: string; designation?: string }
): T[] {
  return members.filter(m => {
    if (filter.role && m.operational_role !== filter.role) return false;
    if (filter.designation && !(m.designations || []).includes(filter.designation)) return false;
    return true;
  });
}
