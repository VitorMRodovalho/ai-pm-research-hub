import { useState, useRef, useEffect } from 'react';
import { Command } from 'cmdk';
import type { BoardMember } from '../../types/board';

interface Props {
  members: BoardMember[];
  value: string;
  onChange: (id: string) => void;
  placeholder?: string;
  disabled?: boolean;
}

export default function MemberPicker({ members, value, onChange, placeholder = 'Selecionar...', disabled = false }: Props) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);

  const selected = members.find((m) => m.id === value);

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

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        disabled={disabled}
        onClick={() => !disabled && setOpen((prev) => !prev)}
        className="w-full text-left rounded-lg border border-[var(--border-default)] px-2 py-1.5 text-[12px] bg-[var(--surface-card)]
          outline-none focus:border-blue-400 cursor-pointer disabled:opacity-50 disabled:cursor-default
          flex items-center justify-between gap-1"
      >
        <span className={selected ? 'text-[var(--text-primary)]' : 'text-[var(--text-muted)]'}>
          {selected ? selected.name : placeholder}
        </span>
        <span className="text-[var(--text-muted)] text-[10px]">▾</span>
      </button>

      {open && (
        <div className="absolute z-50 top-full mt-1 left-0 w-full min-w-[220px] rounded-lg border border-[var(--border-default)] bg-[var(--surface-elevated)] shadow-xl overflow-hidden">
          <Command shouldFilter={false}>
            <div className="px-2 pt-2 pb-1">
              <Command.Input
                value={search}
                onValueChange={setSearch}
                placeholder={i18n.searchMember || "Search member..."}
                className="w-full rounded-md border border-[var(--border-default)] bg-[var(--surface-input)] px-2 py-1.5 text-[12px] text-[var(--text-primary)]
                  outline-none focus:border-blue-400 placeholder:text-[var(--text-muted)]"
                autoFocus
              />
            </div>
            <Command.List className="max-h-[200px] overflow-y-auto px-1 pb-1">
              <Command.Item
                value="__clear__"
                onSelect={() => { onChange(''); setOpen(false); }}
                className="flex items-center gap-2 px-2 py-1.5 text-[12px] text-[var(--text-muted)] rounded-md cursor-pointer
                  data-[selected=true]:bg-[var(--surface-hover)]"
              >
                {placeholder}
              </Command.Item>
              {members
                .filter((m) => !search || m.name.toLowerCase().includes(search.toLowerCase()))
                .map((m) => (
                <Command.Item
                  key={m.id}
                  value={m.id}
                  onSelect={() => { onChange(m.id); setOpen(false); }}
                  className="flex items-center gap-2 px-2 py-1.5 text-[12px] rounded-md cursor-pointer
                    data-[selected=true]:bg-[var(--surface-hover)]"
                >
                  {m.avatar_url ? (
                    <img src={m.avatar_url} alt="" className="w-5 h-5 rounded-full object-cover flex-shrink-0" />
                  ) : (
                    <span className="w-5 h-5 rounded-full bg-navy/10 flex items-center justify-center text-[9px] font-bold text-navy flex-shrink-0">
                      {(m.name ?? '?').charAt(0).toUpperCase()}
                    </span>
                  )}
                  <span className="text-[var(--text-primary)] truncate">{m.name}</span>
                  {m.id === value && <span className="ml-auto text-teal text-[10px]">✓</span>}
                </Command.Item>
              ))}
              {members.filter((m) => !search || m.name.toLowerCase().includes(search.toLowerCase())).length === 0 && (
                <div className="px-2 py-3 text-center text-[11px] text-[var(--text-muted)]">{i18n.noMemberFound || 'No member found'}</div>
              )}
            </Command.List>
          </Command>
        </div>
      )}
    </div>
  );
}
