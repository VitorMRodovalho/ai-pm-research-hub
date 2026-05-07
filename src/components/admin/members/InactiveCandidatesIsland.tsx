import { useEffect, useState } from 'react';
import { Loader2, AlertTriangle, ChevronRight, Users } from 'lucide-react';
import { usePageI18n } from '../../../i18n/usePageI18n';

interface Candidate {
  member_id: string;
  name: string;
  chapter: string | null;
  tribe_id: number | null;
  last_attendance_at: string | null;
  days_since_last_attendance: number;
}

interface DetectResponse {
  success?: boolean;
  threshold_days?: number;
  candidates_count?: number;
  candidates?: Candidate[];
  error?: string;
}

function langFromUrl(): string {
  if (typeof window === 'undefined') return 'pt-BR';
  const search = new URLSearchParams(window.location.search);
  return search.get('lang') || 'pt-BR';
}

export default function InactiveCandidatesIsland() {
  const t = usePageI18n();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [threshold, setThreshold] = useState<number>(180);
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const lang = langFromUrl();

  const getSb = () => (window as any).navGetSb?.();

  useEffect(() => {
    const boot = async () => {
      const sb = getSb();
      if (!sb) { setTimeout(boot, 300); return; }
      setLoading(true);
      setError(null);
      const { data, error: rpcErr } = await sb.rpc('detect_inactive_members', { p_dry_run: true });
      if (rpcErr) {
        setError(rpcErr.message);
        setLoading(false);
        return;
      }
      const resp = data as DetectResponse;
      if (resp?.error) {
        setError(resp.error);
      } else {
        setThreshold(resp?.threshold_days ?? 180);
        setCandidates(resp?.candidates ?? []);
      }
      setLoading(false);
    };
    boot();
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-16 text-sm text-[var(--text-muted)]">
        <Loader2 className="w-4 h-4 mr-2 animate-spin" />
        {t('common.loading', 'Carregando...')}
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-2xl p-6 flex items-start gap-3">
        <AlertTriangle className="w-5 h-5 text-red-600 mt-0.5 shrink-0" />
        <div>
          <p className="font-semibold text-red-800 text-sm">{t('inactiveCandidates.error', 'Erro ao carregar candidatos')}</p>
          <p className="text-xs text-red-700 mt-1">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <h1 className="text-2xl font-extrabold text-navy">
          {t('inactiveCandidates.title', 'Candidatos a Inativo')}
        </h1>
        <p className="text-sm text-[var(--text-secondary)]">
          {t('inactiveCandidates.subtitle', 'Membros ativos sem participação registrada nos últimos {threshold} dias.').replace('{threshold}', String(threshold))}
        </p>
      </header>

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
          <p className="text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">
            {t('inactiveCandidates.statThreshold', 'Limite atual')}
          </p>
          <p className="text-2xl font-bold text-navy mt-1">{threshold}<span className="text-sm font-normal text-[var(--text-muted)] ml-1">{t('inactiveCandidates.statDaysSuffix', 'dias')}</span></p>
        </div>
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
          <p className="text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">
            {t('inactiveCandidates.statCount', 'Candidatos')}
          </p>
          <p className="text-2xl font-bold text-orange mt-1">{candidates.length}</p>
        </div>
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-4">
          <p className="text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">
            {t('inactiveCandidates.statSource', 'Fonte')}
          </p>
          <p className="text-sm font-semibold text-[var(--text-primary)] mt-1">
            {t('inactiveCandidates.statSourceValue', 'Cron semanal')}
          </p>
        </div>
      </div>

      {candidates.length === 0 ? (
        <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-8 text-center">
          <Users className="w-8 h-8 mx-auto text-emerald-600 mb-2" />
          <p className="font-semibold text-emerald-900">
            {t('inactiveCandidates.empty', 'Nenhum candidato no momento')}
          </p>
          <p className="text-sm text-emerald-800 mt-1">
            {t('inactiveCandidates.emptyDesc', 'Todos os membros ativos têm participação recente.')}
          </p>
        </div>
      ) : (
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-[var(--surface-base)] border-b border-[var(--border-default)]">
              <tr>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('inactiveCandidates.colName', 'Nome')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('inactiveCandidates.colChapter', 'Capítulo')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('inactiveCandidates.colLastSeen', 'Última presença')}</th>
                <th className="text-left px-4 py-2.5 text-xs font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t('inactiveCandidates.colDays', 'Dias inativo')}</th>
                <th className="px-4 py-2.5 w-10"></th>
              </tr>
            </thead>
            <tbody>
              {candidates.map((c) => {
                const lastSeen = c.last_attendance_at ? new Date(c.last_attendance_at).toLocaleDateString() : t('inactiveCandidates.never', 'Nunca');
                const detailHref = `/admin/members/${c.member_id}?lang=${lang}`;
                return (
                  <tr key={c.member_id} className="border-b border-[var(--border-subtle)] last:border-0 hover:bg-[var(--surface-hover)]">
                    <td className="px-4 py-3 font-medium text-[var(--text-primary)]">{c.name}</td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{c.chapter || '—'}</td>
                    <td className="px-4 py-3 text-[var(--text-secondary)]">{lastSeen}</td>
                    <td className="px-4 py-3">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-semibold ${c.days_since_last_attendance >= 365 ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
                        {c.days_since_last_attendance}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <a href={detailHref} className="inline-flex items-center text-xs font-semibold text-orange hover:underline no-underline">
                        {t('inactiveCandidates.openMember', 'Abrir')}
                        <ChevronRight className="w-3.5 h-3.5 ml-0.5" />
                      </a>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <footer className="pt-2">
        <p className="text-xs text-[var(--text-muted)]">
          {t('inactiveCandidates.footer', 'Para transicionar um membro para Inativo, abra o detalhe → menu de offboarding. O cron semanal re-avalia esta lista toda segunda às 12:00 UTC.')}
        </p>
      </footer>
    </div>
  );
}
