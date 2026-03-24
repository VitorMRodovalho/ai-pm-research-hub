import { useState, useRef, useEffect } from 'react';
import { Command } from 'cmdk';
import type { BoardMember, AssignmentRole, ItemAssignment, BoardI18n } from '../../types/board';

interface Props {
  members: BoardMember[];
  assignments: ItemAssignment[];
  onAdd: (memberId: string, role: AssignmentRole) => void;
  onRemove: (memberId: string, role: AssignmentRole) => void;
  i18n: BoardI18n;
  disabled?: boolean;
}

const ROLE_LABELS: Record<AssignmentRole, { color: string; bgColor: string }> = {
  author: { color: 'text-blue-700', bgColor: 'bg-blue-50' },
  reviewer: { color: 'text-purple-700', bgColor: 'bg-purple-50' },
  contributor: { color: 'text-emerald-700', bgColor: 'bg-emerald-50' },
  curation_reviewer: { color: 'text-amber-700', bgColor: 'bg-amber-50' },
};

function getRoleLabel(role: AssignmentRole, i18n: BoardI18n): string {
  const map: Record<AssignmentRole, string | undefined> = {
    author: i18n.roleAuthor,
    reviewer: i18n.roleReviewer,
    contributor: i18n.roleContributor,
    curation_reviewer: i18n.roleCurationReviewer,
  };
  return map[role] || role;
}

export default function MemberPickerMulti({ members, assignments, onAdd, onRemove, i18n, disabled = false }: Props) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [selectedRole, setSelectedRole] = useState<AssignmentRole>('contributor');
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  useEffect(() => {
    if (!open) setSearch('');
  }, [open]);

  const assignedIds = new Set(assignments.map((a) => `${a.member_id}:${a.role}`));
  const grouped: Record<string, ItemAssignment[]> = {};
  for (const a of assignments) {
    (grouped[a.role] ??= []).push(a);
  }

  const roles: AssignmentRole[] = ['author', 'reviewer', 'contributor', 'curation_reviewer'];

  return (
    <div ref={containerRef} className="space-y-2">
      {/* Grouped assignment chips */}
      {roles.map((role) => {
        const group = grouped[role];
        if (!group || group.length === 0) return null;
        const style = ROLE_LABELS[role];
        return (
          <div key={role}>
            <span className={`text-[9px] font-semibold uppercase tracking-wide ${style.color}`}>
              {getRoleLabel(role, i18n)}
            </span>
            <div className="flex flex-wrap gap-1 mt-0.5">
              {group.map((a) => (
                <span
                  key={`${a.member_id}-${a.role}`}
                  className={`inline-flex items-center gap-1 px-1.5 py-0.5 ${style.bgColor} ${style.color} rounded text-[10px] font-medium`}
                >
                  {a.avatar_url ? (
                    <img src={a.avatar_url} alt="" className="w-3.5 h-3.5 rounded-full object-cover" />
                  ) : (
                    <span className="w-3.5 h-3.5 rounded-full bg-navy/10 flex items-center justify-center text-[7px] font-bold text-navy">
                      {a.name.charAt(0).toUpperCase()}
                    </span>
                  )}
                  <span className="truncate max-w-[80px]">{a.name}</span>
                  {!disabled && (
                    <button
                      onClick={() => onRemove(a.member_id, a.role as AssignmentRole)}
                      className="text-current opacity-50 hover:opacity-100 cursor-pointer bg-transparent border-0 text-[8px] ml-0.5"
                    >
                      ✕
                    </button>
                  )}
                </span>
              ))}
            </div>
          </div>
        );
      })}

      {/* Add button */}
      {!disabled && (
        <button
          type="button"
          onClick={() => setOpen((prev) => !prev)}
          className="text-[10px] text-blue-600 hover:text-blue-800 cursor-pointer bg-transparent border-0 font-medium"
        >
          + {i18n.addMember || 'Adicionar membro'}
        </button>
      )}

      {/* Dropdown */}
      {open && (
        <div className="relative z-50">
          <div className="absolute top-0 left-0 w-full min-w-[240px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-elevated)] shadow-xl overflow-hidden">
            <Command shouldFilter={false}>
              <div className="px-2 pt-2 pb-1 space-y-1">
                <Command.Input
                  value={search}
                  onValueChange={setSearch}
                  placeholder="Buscar membro..."
                  className="w-full rounded-md border border-[var(--border-default)] bg-[var(--surface-input)] px-2 py-1.5 text-[12px] text-[var(--text-primary)]
                    outline-none focus:border-blue-400 placeholder:text-[var(--text-muted)]"
                  autoFocus
                />
                {/* Role selector */}
                <div className="flex gap-1">
                  {roles.map((r) => (
                    <button
                      key={r}
                      type="button"
                      onClick={() => setSelectedRole(r)}
                      className={`px-1.5 py-0.5 rounded text-[9px] font-medium border-0 cursor-pointer transition-colors
                        ${selectedRole === r
                          ? `${ROLE_LABELS[r].bgColor} ${ROLE_LABELS[r].color}`
                          : 'bg-transparent text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
                        }`}
                    >
                      {getRoleLabel(r, i18n)}
                    </button>
                  ))}
                </div>
              </div>
              {/* Helper text */}
              <div className="px-2 py-1 text-[10px] text-[var(--text-muted)]">
                Selecione para adicionar como <strong className={ROLE_LABELS[selectedRole].color}>{getRoleLabel(selectedRole, i18n)}</strong>
              </div>
              <Command.List className="max-h-[180px] overflow-y-auto px-1 pb-1">
                {members
                  .filter((m) => !search || m.name.toLowerCase().includes(search.toLowerCase()))
                  .filter((m) => {
                    // FIX 1: Curador tab only shows curators
                    if (selectedRole === 'curation_reviewer') {
                      return m.designations?.includes('curator');
                    }
                    return true;
                  })
                  .map((m) => {
                    const isAssigned = assignedIds.has(`${m.id}:${selectedRole}`);
                    // FIX 3: Check for cross-role assignment
                    const existingOtherRole = assignments.find(
                      (a) => a.member_id === m.id && a.role !== selectedRole
                    );
                    return (
                      <Command.Item
                        key={m.id}
                        value={m.id}
                        onSelect={() => {
                          if (!isAssigned) {
                            onAdd(m.id, selectedRole);
                          }
                        }}
                        className={`flex items-center gap-2 px-2 py-1.5 text-[12px] rounded-md cursor-pointer
                          data-[selected=true]:bg-[var(--surface-hover)]
                          ${isAssigned ? 'opacity-40 pointer-events-none' : ''}`}
                      >
                        {m.avatar_url ? (
                          <img src={m.avatar_url} alt="" className="w-5 h-5 rounded-full object-cover flex-shrink-0" />
                        ) : (
                          <span className="w-5 h-5 rounded-full bg-navy/10 flex items-center justify-center text-[9px] font-bold text-navy flex-shrink-0">
                            {m.name.charAt(0).toUpperCase()}
                          </span>
                        )}
                        <span className="text-[var(--text-primary)] truncate">{m.name}</span>
                        {isAssigned && <span className="ml-auto text-teal text-[10px]">✓</span>}
                        {existingOtherRole && !isAssigned && (
                          <span className={`ml-auto text-[8px] px-1 py-0.5 rounded ${ROLE_LABELS[existingOtherRole.role as AssignmentRole]?.bgColor || 'bg-gray-100'} ${ROLE_LABELS[existingOtherRole.role as AssignmentRole]?.color || 'text-gray-600'}`}>
                            {getRoleLabel(existingOtherRole.role as AssignmentRole, i18n)}
                          </span>
                        )}
                      </Command.Item>
                    );
                  })}
                {members
                  .filter((m) => !search || m.name.toLowerCase().includes(search.toLowerCase()))
                  .filter((m) => selectedRole !== 'curation_reviewer' || m.designations?.includes('curator'))
                  .length === 0 && (
                  <div className="px-2 py-3 text-center text-[11px] text-[var(--text-muted)]">Nenhum membro encontrado</div>
                )}
              </Command.List>
            </Command>
          </div>
        </div>
      )}
    </div>
  );
}
