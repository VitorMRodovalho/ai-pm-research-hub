import { useState, useEffect, useCallback } from 'react';
import { Search, Filter, ChevronLeft, ChevronRight, Loader2 } from 'lucide-react';
import { usePageI18n } from '../../../i18n/usePageI18n';

/* ────── Types ────── */
interface AuditEntry {
  id: string;
  actor_name: string;
  actor_id: string;
  action: string;
  target_name: string | null;
  target_id: string | null;
  changes: any;
  created_at: string;
}

interface AuditData {
  total: number;
  entries: AuditEntry[];
  actors: Array<{ id: string; name: string }>;
}

/* ────── Helpers ────── */
function fmtDateTime(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }) + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

function formatAction(action: string): string {
  return action.replace('member.', '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function formatChanges(changes: any): string {
  if (!changes) return '—';
  if (changes.field) {
    return `${changes.field}: ${changes.old ?? 'null'} → ${changes.new ?? 'null'}`;
  }
  return JSON.stringify(changes);
}

/* ────── Component ────── */
export default function AuditLogIsland() {
  const t = usePageI18n();
  const [data, setData] = useState<AuditData | null>(null);
  const [loading, setLoading] = useState(true);
  const [actorFilter, setActorFilter] = useState('');
  const [targetSearch, setTargetSearch] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [page, setPage] = useState(0);
  const pageSize = 20;

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const fetchData = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    const { data, error } = await sb.rpc('get_audit_log', {
      p_actor_id: actorFilter || null,
      p_target_id: null,
      p_action: actionFilter || null,
      p_date_from: dateFrom ? new Date(dateFrom).toISOString() : null,
      p_date_to: dateTo ? new Date(dateTo + 'T23:59:59').toISOString() : null,
      p_limit: pageSize,
      p_offset: page * pageSize,
    });
    if (!error && data) setData(data);
    setLoading(false);
  }, [actorFilter, actionFilter, dateFrom, dateTo, page]);

  useEffect(() => {
    const boot = () => {
      if (getSb()) fetchData();
      else setTimeout(boot, 300);
    };
    boot();
  }, [fetchData, getSb]);

  const filteredEntries = data?.entries?.filter(e => {
    if (!targetSearch) return true;
    return e.target_name?.toLowerCase().includes(targetSearch.toLowerCase());
  }) ?? [];

  const total = data?.total ?? 0;
  const from = page * pageSize + 1;
  const to = Math.min((page + 1) * pageSize, total);
  const lastPage = Math.max(0, Math.ceil(total / pageSize) - 1);

  const inputClass = 'px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]';

  const clearFilters = () => {
    setActorFilter('');
    setTargetSearch('');
    setActionFilter('');
    setDateFrom('');
    setDateTo('');
    setPage(0);
  };

  const applyFilters = () => {
    setPage(0);
    fetchData();
  };

  /* ────── Render ────── */
  return (
    <div className="max-w-[1100px] mx-auto">
      {/* Title */}
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-[var(--text-primary)]">{t('comp.auditLog.title', 'Registro de Auditoria')}</h1>
        <p className="text-sm text-[var(--text-muted)]">{t('comp.auditLog.subtitle', 'Todas as ações administrativas registradas')}</p>
      </div>

      {/* Filter bar */}
      <div className="flex flex-wrap gap-2 mb-4 items-end">
        <select
          value={actorFilter}
          onChange={e => setActorFilter(e.target.value)}
          className={inputClass}
        >
          <option value="">{t('comp.auditLog.allActors', 'Todos os atores')}</option>
          {data?.actors?.map(a => (
            <option key={a.id} value={a.id}>{a.name}</option>
          ))}
        </select>

        <input
          type="text"
          placeholder={t('comp.auditLog.filterAction', 'Filtrar por ação...')}
          value={actionFilter}
          onChange={e => setActionFilter(e.target.value)}
          className={inputClass}
        />

        <input
          type="date"
          value={dateFrom}
          onChange={e => setDateFrom(e.target.value)}
          className={inputClass}
          title={t('comp.auditLog.dateFrom', 'Data início')}
        />

        <input
          type="date"
          value={dateTo}
          onChange={e => setDateTo(e.target.value)}
          className={inputClass}
          title={t('comp.auditLog.dateTo', 'Data fim')}
        />

        <button
          onClick={applyFilters}
          className="px-4 py-2 rounded-lg bg-teal-600 text-white text-sm font-medium hover:bg-teal-700 transition-colors"
        >
          <Filter className="inline w-4 h-4 mr-1 -mt-0.5" />
          {t('comp.auditLog.filter', 'Filtrar')}
        </button>

        <button
          onClick={clearFilters}
          className="px-4 py-2 rounded-lg border border-[var(--border-default)] text-sm text-[var(--text-muted)] hover:bg-[var(--surface-hover)] transition-colors"
        >
          {t('comp.auditLog.clear', 'Limpar')}
        </button>
      </div>

      {/* Target search (client-side) */}
      <div className="mb-4">
        <div className="relative w-64">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-muted)]" />
          <input
            type="text"
            placeholder={t('comp.auditLog.searchTarget', 'Buscar membro afetado...')}
            value={targetSearch}
            onChange={e => setTargetSearch(e.target.value)}
            className={`${inputClass} pl-9 w-full`}
          />
        </div>
      </div>

      {/* Loading */}
      {loading && (
        <div className="flex items-center justify-center py-16">
          <Loader2 className="w-6 h-6 animate-spin text-teal-600" />
        </div>
      )}

      {/* Empty state */}
      {!loading && filteredEntries.length === 0 && (
        <div className="text-center py-16 text-[var(--text-muted)]">
          {t('comp.auditLog.noActions', 'Nenhuma ação registrada')}
        </div>
      )}

      {/* Table */}
      {!loading && filteredEntries.length > 0 && (
        <>
          <div className="rounded-xl border border-[var(--border-default)] overflow-hidden">
            <table className="w-full text-left">
              <thead>
                <tr className="bg-[var(--surface-section-cool)] text-[var(--text-muted)] text-[.7rem] uppercase tracking-wider">
                  <th className="px-4 py-3">{t('comp.auditLog.colDateTime', 'Data/Hora')}</th>
                  <th className="px-4 py-3">{t('comp.auditLog.colActor', 'Ator')}</th>
                  <th className="px-4 py-3">{t('comp.auditLog.colAction', 'Ação')}</th>
                  <th className="px-4 py-3">{t('comp.auditLog.colTarget', 'Membro Afetado')}</th>
                  <th className="px-4 py-3">{t('comp.auditLog.colDetails', 'Detalhes')}</th>
                </tr>
              </thead>
              <tbody>
                {filteredEntries.map(entry => (
                  <tr key={entry.id} className="border-t border-[var(--border-default)] hover:bg-[var(--surface-hover)]">
                    <td className="px-4 py-3 text-sm text-[var(--text-muted)] whitespace-nowrap">
                      {fmtDateTime(entry.created_at)}
                    </td>
                    <td className="px-4 py-3 text-sm font-medium text-[var(--text-primary)]">
                      {entry.actor_name}
                    </td>
                    <td className="px-4 py-3">
                      <span className="inline-block px-2 py-0.5 rounded-full text-xs font-medium bg-[var(--surface-section-cool)] text-[var(--text-secondary)]">
                        {formatAction(entry.action)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      {entry.target_id ? (
                        <a
                          href={`/admin/members/${entry.target_id}`}
                          className="text-teal-600 hover:underline"
                        >
                          {entry.target_name}
                        </a>
                      ) : (
                        <span className="text-[var(--text-muted)]">{entry.target_name ?? '—'}</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-xs text-[var(--text-muted)] max-w-[260px] truncate">
                      {formatChanges(entry.changes)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          <div className="flex items-center justify-between mt-4">
            <span className="text-sm text-[var(--text-muted)]">
              {t('comp.auditLog.showing', 'Mostrando')} {from}–{to} {t('comp.auditLog.of', 'de')} {total} {t('comp.auditLog.records', 'registros')}
            </span>
            <div className="flex gap-2">
              <button
                disabled={page === 0}
                onClick={() => setPage(p => p - 1)}
                className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-sm text-[var(--text-primary)] hover:bg-[var(--surface-hover)] transition-colors disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
              >
                <ChevronLeft className="w-4 h-4" />
                {t('comp.auditLog.prev', 'Anterior')}
              </button>
              <button
                disabled={page >= lastPage}
                onClick={() => setPage(p => p + 1)}
                className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-sm text-[var(--text-primary)] hover:bg-[var(--surface-hover)] transition-colors disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1"
              >
                {t('comp.auditLog.next', 'Próximo')}
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
