import { useState, useEffect, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import GovernanceStats from './GovernanceStats';
import GovernanceCRTable from './GovernanceCRTable';

export default function GovernanceAdminIsland() {
  const t = usePageI18n();
  const [stats, setStats] = useState<any>(null);
  const [crs, setCrs] = useState<any[]>([]);
  const [sections, setSections] = useState<any[]>([]);
  const [member, setMember] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const loadData = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    try {
      const [statsRes, crsRes, secRes] = await Promise.all([
        sb.rpc('get_governance_stats'),
        sb.rpc('get_change_requests', { p_status: null, p_cr_type: null }),
        sb.rpc('get_manual_sections', { p_version: 'R2' }),
      ]);
      if (statsRes.data && !statsRes.data.error) setStats(statsRes.data);
      if (Array.isArray(crsRes.data)) setCrs(crsRes.data);
      if (Array.isArray(secRes.data)) setSections(secRes.data);
    } catch (e: any) {
      setError(e.message || 'Erro ao carregar dados');
    }
  }, [getSb]);

  useEffect(() => {
    let cancelled = false;
    let retries = 0;

    async function boot() {
      const sb = getSb();
      const m = (window as any).navGetMember?.();
      if ((!sb || !m) && retries < 30) {
        retries++;
        setTimeout(boot, 300);
        return;
      }
      if (m && !cancelled) setMember(m);
      if (!sb) { if (!cancelled) { setLoading(false); setError('Supabase not available'); } return; }

      await loadData();
      if (!cancelled) setLoading(false);
    }

    boot();
    return () => { cancelled = true; };
  }, [getSb, loadData]);

  const handleRefresh = useCallback(async () => {
    await loadData();
  }, [loadData]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-16">
        <div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
        <span className="ml-3 text-sm text-[var(--text-secondary)]">{t('governance.loading', 'Carregando...')}</span>
      </div>
    );
  }

  if (error) {
    return <div className="text-red-600 text-sm py-8 text-center">{error}</div>;
  }

  const pendingCount = crs.filter(cr => ['submitted', 'under_review'].includes(cr.status)).length;

  return (
    <div className="space-y-6">
      {/* Title */}
      <div>
        <h1 className="text-xl font-extrabold text-navy">{t('governance.admin_tab_title', 'Governança')}</h1>
      </div>

      {/* Scope disclaimer */}
      <div className="rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-blue-800 text-sm">
        ℹ️ {t('governance.admin_scope_disclaimer', 'Este fluxo cobre a governança de conteúdo do Manual (produto). A governança estratégica do Núcleo é tratada pelo Steering Committee multi-capítulos.')}
      </div>

      {/* Stats */}
      <GovernanceStats stats={stats} t={t} />

      {/* Pending Review section */}
      <div>
        <h2 className="text-sm font-extrabold text-navy mb-3 flex items-center gap-2">
          {t('governance.pending_review_section', 'Pendentes de Revisão')}
          {pendingCount > 0 && (
            <span className="px-2 py-0.5 rounded-full bg-blue-100 text-blue-700 text-[11px] font-bold">{pendingCount}</span>
          )}
        </h2>
        <GovernanceCRTable crs={crs} sections={sections} member={member} preFilter="pending" t={t} getSb={getSb} onRefresh={handleRefresh} />
      </div>

      {/* All CRs section */}
      <div>
        <h2 className="text-sm font-extrabold text-navy mb-3">
          {t('governance.all_crs_section', 'Todas as CRs')}
        </h2>
        <GovernanceCRTable crs={crs} sections={sections} member={member} preFilter="all" t={t} getSb={getSb} onRefresh={handleRefresh} />
      </div>

      {/* Governance Log — approved/implemented CRs as changelog */}
      {(() => {
        const logEntries = crs
          .filter(cr => ['approved', 'implemented'].includes(cr.status))
          .sort((a, b) => (b.approved_at || b.updated_at || '').localeCompare(a.approved_at || a.updated_at || ''));
        if (logEntries.length === 0) return null;
        const TYPE_BADGE: Record<string, string> = {
          amendment: 'bg-purple-100 text-purple-700',
          correction: 'bg-blue-100 text-blue-700',
          addition: 'bg-emerald-100 text-emerald-700',
          removal: 'bg-red-100 text-red-700',
          critical: 'bg-red-100 text-red-700',
        };
        return (
          <div>
            <h2 className="text-sm font-extrabold text-navy mb-3 flex items-center gap-2">
              {t('governance.changelog_section', 'Governance Log')}
              <span className="px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700 text-[11px] font-bold">{logEntries.length}</span>
            </h2>
            <div className="space-y-2 max-h-[400px] overflow-y-auto">
              {logEntries.map((cr: any) => (
                <div key={cr.id} className="flex items-start gap-3 px-3 py-2 rounded-lg border border-[var(--border-subtle)] bg-[var(--surface-base)]">
                  <span className="text-[11px] font-bold text-navy whitespace-nowrap">{cr.cr_number}</span>
                  <div className="flex-1 min-w-0">
                    <div className="text-[12px] font-medium text-[var(--text-primary)] truncate">{cr.title}</div>
                    {cr.description && <div className="text-[10px] text-[var(--text-muted)] mt-0.5 line-clamp-1">{cr.description}</div>}
                  </div>
                  <div className="flex items-center gap-1.5 flex-shrink-0">
                    {cr.cr_type && (
                      <span className={`text-[9px] px-1.5 py-0.5 rounded-full font-semibold ${TYPE_BADGE[cr.cr_type] || 'bg-gray-100 text-gray-600'}`}>{cr.cr_type}</span>
                    )}
                    <span className={`text-[9px] px-1.5 py-0.5 rounded-full font-semibold ${cr.status === 'implemented' ? 'bg-emerald-100 text-emerald-700' : 'bg-blue-100 text-blue-700'}`}>
                      {cr.status === 'implemented' ? '✅' : '✓'} {cr.status}
                    </span>
                    {(cr.approved_at || cr.updated_at) && (
                      <span className="text-[9px] text-[var(--text-muted)]">
                        {new Date(cr.approved_at || cr.updated_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        );
      })()}

      {/* Footer notes */}
      <div className="space-y-2 pt-2 border-t border-[var(--border-subtle)]">
        <p className="text-xs text-[var(--text-muted)]">
          {t('governance.version_note', 'CRs aprovadas serão consolidadas na versão R3 do Manual. A decisão de publicar nova versão é do CCB/Sponsor.')}
        </p>
        <p className="text-xs text-[var(--text-muted)]">
          {t('governance.communication_note', 'O estado de cada CR é visível em /governance. Para rejeições, registre justificativa clara em review_notes.')}
        </p>
        <p className="text-xs text-[var(--text-muted)]">
          {t('governance.escalation_note', 'Em caso de desacordo entre capítulos, o tema é escalonado ao Steering Committee multi-capítulos para decisão final.')}
        </p>
      </div>
    </div>
  );
}
