import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface BoardMember {
  id: string;
  name: string;
  photo_url: string | null;
  operational_role: string;
  board_role: string;
  designations: string[];
}

interface Board {
  id: string;
  board_name: string;
  board_scope: string;
  tribe_id: number | null;
}

const ROLE_COLORS: Record<string, string> = {
  admin: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300',
  editor: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300',
  viewer: 'bg-gray-100 text-gray-600 dark:bg-gray-800/50 dark:text-gray-300',
};

function getSb() { return (window as any).navGetSb?.(); }

export default function BoardMembersPanel() {
  const t = usePageI18n();
  const [boards, setBoards] = useState<Board[]>([]);
  const [selectedBoard, setSelectedBoard] = useState<string>('');
  const [members, setMembers] = useState<BoardMember[]>([]);
  const [allMembers, setAllMembers] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMembers, setLoadingMembers] = useState(false);
  const [addMemberId, setAddMemberId] = useState('');
  const [addRole, setAddRole] = useState('editor');
  const [saving, setSaving] = useState(false);
  const [member, setMember] = useState<any>(null);

  // Self-boot: wait for nav to be ready
  useEffect(() => {
    let retries = 0;
    const check = () => {
      const m = (window as any).navGetMember?.();
      if (m) { setMember(m); setLoading(false); }
      else if (retries < 30) { retries++; setTimeout(check, 300); }
      else setLoading(false);
    };
    setTimeout(check, 300);
  }, []);

  const isGP = member?.is_superadmin || member?.operational_role === 'manager' || (member?.designations || []).includes('deputy_manager');
  if (!isGP && !loading) return null;

  const loadBoards = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.from('project_boards').select('id, board_name, board_scope, tribe_id').eq('is_active', true).order('board_name');
    if (data) setBoards(data);
    setLoading(false);
  }, [getSb]);

  const loadBoardMembers = useCallback(async (boardId: string) => {
    const sb = getSb();
    if (!sb || !boardId) return;
    setLoadingMembers(true);
    const { data } = await sb.rpc('get_board_members', { p_board_id: boardId });
    setMembers(Array.isArray(data) ? data : []);
    setLoadingMembers(false);
  }, [getSb]);

  const loadAllMembers = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.from('members').select('id, name').eq('is_active', true).order('name');
    if (data) setAllMembers(data);
  }, [getSb]);

  useEffect(() => { loadBoards(); loadAllMembers(); }, [loadBoards, loadAllMembers]);

  useEffect(() => {
    if (selectedBoard) loadBoardMembers(selectedBoard);
    else setMembers([]);
  }, [selectedBoard, loadBoardMembers]);

  const handleAdd = async () => {
    if (!addMemberId || !selectedBoard || saving) return;
    setSaving(true);
    const sb = getSb();
    const { data, error } = await sb.rpc('admin_manage_board_member', {
      p_board_id: selectedBoard, p_member_id: addMemberId, p_board_role: addRole, p_action: 'add',
    });
    if (error || data?.error) {
      (window as any).toast?.(error?.message || data?.error || t('common.errorGeneric', 'Error'), 'error');
    } else {
      (window as any).toast?.(t('boardMembers.added', 'Member added to board'), 'success');
      setAddMemberId('');
      await loadBoardMembers(selectedBoard);
    }
    setSaving(false);
  };

  const handleRemove = async (memberId: string) => {
    if (!selectedBoard || saving) return;
    if (!confirm(t('boardMembers.confirmRemove', 'Remove member from this board?'))) return;
    setSaving(true);
    const sb = getSb();
    const { error } = await sb.rpc('admin_manage_board_member', {
      p_board_id: selectedBoard, p_member_id: memberId, p_action: 'remove',
    });
    if (error) {
      (window as any).toast?.(error.message, 'error');
    } else {
      (window as any).toast?.(t('boardMembers.removed', 'Member removed'), 'success');
      await loadBoardMembers(selectedBoard);
    }
    setSaving(false);
  };

  const handleChangeRole = async (memberId: string, newRole: string) => {
    if (!selectedBoard || saving) return;
    setSaving(true);
    const sb = getSb();
    await sb.rpc('admin_manage_board_member', {
      p_board_id: selectedBoard, p_member_id: memberId, p_board_role: newRole, p_action: 'add',
    });
    await loadBoardMembers(selectedBoard);
    setSaving(false);
  };

  if (loading) return null;

  const selectedBoardData = boards.find(b => b.id === selectedBoard);
  const globalBoards = boards.filter(b => b.board_scope === 'global');
  const tribeBoards = boards.filter(b => b.board_scope === 'tribe');
  const availableToAdd = allMembers.filter(m => !members.some(bm => bm.id === m.id));

  return (
    <section className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <h2 className="text-lg font-extrabold text-navy mb-1">{t('boardMembers.title', 'Board Permissions')}</h2>
      <p className="text-xs text-[var(--text-muted)] mb-4">{t('boardMembers.subtitle', 'Manage member access to specific boards')}</p>

      {/* Board selector */}
      <select value={selectedBoard} onChange={e => setSelectedBoard(e.target.value)}
        className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)] mb-4 focus:outline-none focus:border-navy">
        <option value="">{t('boardMembers.selectBoard', 'Select a board...')}</option>
        {globalBoards.length > 0 && (
          <optgroup label={t('boardMembers.globalBoards', 'Global Boards')}>
            {globalBoards.map(b => <option key={b.id} value={b.id}>{b.board_name}</option>)}
          </optgroup>
        )}
        {tribeBoards.length > 0 && (
          <optgroup label={t('boardMembers.tribeBoards', 'Tribe Boards')}>
            {tribeBoards.map(b => <option key={b.id} value={b.id}>{b.board_name}</option>)}
          </optgroup>
        )}
      </select>

      {selectedBoard && (
        <>
          {/* Board info badge */}
          {selectedBoardData && (
            <div className="flex items-center gap-2 mb-3">
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                selectedBoardData.board_scope === 'global' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
              }`}>{selectedBoardData.board_scope}</span>
              {selectedBoardData.tribe_id && <span className="text-[10px] text-[var(--text-muted)]">Tribo {selectedBoardData.tribe_id}</span>}
            </div>
          )}

          {/* Current members */}
          {loadingMembers ? (
            <div className="text-center py-4"><div className="animate-spin h-4 w-4 border-2 border-[var(--accent)] border-t-transparent rounded-full inline-block" /></div>
          ) : members.length === 0 ? (
            <p className="text-sm text-[var(--text-muted)] py-3">{t('boardMembers.noSpecific', 'No members with specific permissions on this board.')}</p>
          ) : (
            <div className="space-y-2 mb-4">
              {members.map(m => (
                <div key={m.id} className="flex items-center gap-3 py-2 px-3 rounded-lg bg-[var(--surface-hover)]">
                  <div className="flex-1 min-w-0">
                    <span className="text-sm font-medium text-[var(--text-primary)]">{m.name}</span>
                    <span className="text-[11px] text-[var(--text-muted)] ml-2">{m.operational_role}</span>
                  </div>
                  <select value={m.board_role} onChange={e => handleChangeRole(m.id, e.target.value)}
                    className="px-2 py-1 rounded text-[11px] font-bold border-0 cursor-pointer focus:outline-none"
                    style={{ background: 'transparent' }}>
                    <option value="admin">admin</option>
                    <option value="editor">editor</option>
                    <option value="viewer">viewer</option>
                  </select>
                  <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${ROLE_COLORS[m.board_role] || ROLE_COLORS.viewer}`}>
                    {m.board_role}
                  </span>
                  <button onClick={() => handleRemove(m.id)} className="text-red-500 hover:text-red-700 text-xs cursor-pointer border-0 bg-transparent" title={t('common.remove', 'Remove')}>
                    ✕
                  </button>
                </div>
              ))}
            </div>
          )}

          {/* Add member */}
          <div className="flex gap-2 items-end flex-wrap">
            <div className="flex-1 min-w-[180px]">
              <label className="text-[10px] font-bold uppercase tracking-wide text-[var(--text-muted)] mb-1 block">{t('boardMembers.member', 'Member')}</label>
              <select value={addMemberId} onChange={e => setAddMemberId(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)] focus:outline-none focus:border-navy">
                <option value="">{t('boardMembers.select', 'Select...')}</option>
                {availableToAdd.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
              </select>
            </div>
            <div className="w-24">
              <label className="text-[10px] font-bold uppercase tracking-wide text-[var(--text-muted)] mb-1 block">{t('boardMembers.role', 'Role')}</label>
              <select value={addRole} onChange={e => setAddRole(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)] focus:outline-none focus:border-navy">
                <option value="admin">admin</option>
                <option value="editor">editor</option>
                <option value="viewer">viewer</option>
              </select>
            </div>
            <button onClick={handleAdd} disabled={!addMemberId || saving}
              className="px-4 py-1.5 rounded-lg bg-navy text-white text-sm font-semibold border-0 cursor-pointer hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed transition-opacity">
              {saving ? '...' : t('boardMembers.add', '+ Add')}
            </button>
          </div>
        </>
      )}
    </section>
  );
}
