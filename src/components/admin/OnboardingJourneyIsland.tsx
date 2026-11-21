// src/components/admin/OnboardingJourneyIsland.tsx
// Jornadas de onboarding, fatia B (parte 2): a gestão vê, audita e corrige a jornada pela tela.
//
// Lê get_onboarding_journey_admin (manage_member: diretorias e gestão). A fonte de cada fechamento vem do servidor,
// derivada da evidência: gp, fato, clique ou sem_evidencia. As duas portas de correção são do GP (manage_platform):
// admin_complete_onboarding_step marca uma etapa de fato pendente e admin_reopen_onboarding_step reabre uma etapa
// fechada, as duas com justificativa escrita. O servidor recusa quem não pode; o botão só aparece para quem pode.
import { useState, useEffect, useCallback, useMemo, Fragment } from 'react';
import { Loader2, Route, ChevronDown, ChevronRight, Search, RefreshCw } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { canForUnscoped } from '../../lib/permissions';
import { useResolvedMember } from '../../hooks/useResolvedMember';

type Source = 'gp' | 'fato' | 'clique' | 'sem_evidencia' | null;
interface Evidence { kind: string; at?: string | null; title?: string | null; restricted?: boolean; courses?: number | null; vep_status?: string | null; verification_code?: string | null }
interface GpMark { member_id: string | null; name: string | null; note: string | null; at: string | null }
interface ReopenEntry { reopened_by: string; reopen_note: string; reopened_at: string; previous_status: string; previous_closed_by: string | null }
interface StepRow {
  step_key: string;
  status: string;
  completed_at: string | null;
  sla_deadline: string | null;
  source: Source;
  evidence: Evidence | null;
  gp: GpMark | null;
  reopen_history: ReopenEntry[] | null;
}
interface MemberRow {
  member_id: string;
  name: string;
  chapter: string | null;
  tribe_id: number | null;
  operational_role: string | null;
  member_status: string;
  steps: StepRow[] | null;
}
interface CatalogStep { id: string; step_order: number; closed_by: 'member' | 'fact'; is_required: boolean; label_pt: string; label_en: string | null; label_es: string | null }
interface Scope { global: boolean; chapter: string | null; lines: number[] | null }
type Filter = 'all' | 'fact_pending' | 'gp' | 'no_evidence' | 'fact_unclosed';
type Action = { memberId: string; stepKey: string; kind: 'complete' | 'reopen' } | null;

const uiLang = (): string => (typeof document === 'undefined' ? 'pt-BR' : document.documentElement.lang || 'pt-BR');
const fmtDate = (s: string | null | undefined) => {
  if (!s) return '';
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? s : d.toLocaleDateString(uiLang());
};
const isClosed = (s: StepRow) => s.status === 'completed' || s.status === 'skipped';

export default function OnboardingJourneyIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const { memberId } = useResolvedMember();
  const [catalog, setCatalog] = useState<CatalogStep[]>([]);
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('all');
  const [stepFilter, setStepFilter] = useState<string>('');
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const [action, setAction] = useState<Action>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [canCorrect, setCanCorrect] = useState(false);
  const [scope, setScope] = useState<Scope | null>(null);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    setError(null);
    const { data, error: err } = await sb.rpc('get_onboarding_journey_admin');
    if (err) {
      setError(err.message || 'error');
    } else {
      setCatalog(Array.isArray(data?.steps) ? data.steps : []);
      setMembers(Array.isArray(data?.members) ? data.members : []);
      setScope(data?.scope ?? null);
    }
    setCanCorrect(canForUnscoped('manage_platform'));
    setLoading(false);
  }, [getSb]);

  // a primeira chamada espera o membro resolvido (useResolvedMember), sem laço próprio.
  useEffect(() => { if (memberId) load(); }, [load, memberId]);

  const stepById = useMemo(() => new Map(catalog.map((s) => [s.id, s])), [catalog]);
  const label = useCallback((id: string) => {
    const s = stepById.get(id);
    if (!s) return id;
    const l = uiLang();
    return (l.startsWith('en') ? s.label_en : l.startsWith('es') ? s.label_es : s.label_pt) || s.label_pt || id;
  }, [stepById]);
  const isFact = useCallback((id: string) => stepById.get(id)?.closed_by === 'fact', [stepById]);

  const matches = useCallback((s: StepRow): boolean => {
    if (stepFilter && s.step_key !== stepFilter) return false;
    switch (filter) {
      case 'fact_pending': return isFact(s.step_key) && !isClosed(s);
      case 'gp': return s.source === 'gp';
      case 'no_evidence': return s.source === 'sem_evidencia';
      case 'fact_unclosed': return isFact(s.step_key) && !isClosed(s) && !!s.evidence;
      default: return true;
    }
  }, [filter, stepFilter, isFact]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return members.filter((m) => (!q || m.name.toLowerCase().includes(q))
      && (filter === 'all' && !stepFilter ? true : (m.steps || []).some(matches)));
  }, [members, query, filter, stepFilter, matches]);

  // contagem por etapa de fato: o que a gestão leva ao GP
  const counts = useMemo(() => {
    const out = new Map<string, { pending: number; noEvidence: number; gp: number; unclosed: number }>();
    for (const c of catalog.filter((s) => s.closed_by === 'fact')) out.set(c.id, { pending: 0, noEvidence: 0, gp: 0, unclosed: 0 });
    for (const m of members) for (const s of m.steps || []) {
      const c = out.get(s.step_key);
      if (!c) continue;
      if (!isClosed(s)) { c.pending++; if (s.evidence) c.unclosed++; }
      if (s.source === 'sem_evidencia') c.noEvidence++;
      if (s.source === 'gp') c.gp++;
    }
    return out;
  }, [catalog, members]);

  const sourceBadge = (s: StepRow) => {
    if (!isClosed(s)) {
      return s.evidence && isFact(s.step_key)
        ? <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-sky-100 text-sky-800">{t('comp.onboardingJourney.sourceUnclosed', 'fato sem fechar')}</span>
        : null;
    }
    const map: Record<string, [string, string]> = {
      gp: ['bg-purple-100 text-purple-800', t('comp.onboardingJourney.sourceGp', 'GP')],
      fato: ['bg-emerald-100 text-emerald-800', t('comp.onboardingJourney.sourceFact', 'fato')],
      clique: ['bg-slate-100 text-slate-700', t('comp.onboardingJourney.sourceClick', 'clique')],
      sem_evidencia: ['bg-amber-100 text-amber-800', t('comp.onboardingJourney.sourceNoEvidence', 'sem evidência')],
    };
    const v = s.source ? map[s.source] : null;
    return v ? <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${v[0]}`}>{v[1]}</span> : null;
  };

  const evidenceText = (e: Evidence | null) => {
    if (!e) return '';
    const when = fmtDate(e.at);
    switch (e.kind) {
      case 'certificate': return `${t('comp.onboardingJourney.evCertificate', 'Termo assinado')} ${e.verification_code || ''} ${when}`.trim();
      case 'vep': return `${t('comp.onboardingJourney.evVep', 'VEP')}: ${e.vep_status || ''} ${when}`.trim();
      case 'trail': return `${t('comp.onboardingJourney.evTrail', 'Trilha')}: ${e.courses ?? 0} ${t('comp.onboardingJourney.evTrailCourses', 'curso(s)')} ${when}`.trim();
      case 'attendance':
      case 'tribe_attendance': return `${t('comp.onboardingJourney.evAttendance', 'Presença')}: ${e.restricted ? t('comp.onboardingJourney.evRestricted', 'evento restrito') : (e.title || '')} ${when}`.trim();
      default: return e.kind;
    }
  };

  const submit = async () => {
    if (!action) return;
    const sb = getSb();
    if (!sb) return;
    if (note.trim().length < 3) { setActionError(t('comp.onboardingJourney.noteRequired', 'Escreva a justificativa (mínimo de 3 caracteres).')); return; }
    setBusy(true);
    setActionError(null);
    const fn = action.kind === 'complete' ? 'admin_complete_onboarding_step' : 'admin_reopen_onboarding_step';
    const { error: err } = await sb.rpc(fn, { p_member_id: action.memberId, p_step_key: action.stepKey, p_note: note.trim() });
    if (err) { setActionError(err.message); setBusy(false); return; }
    const { data } = await sb.rpc('get_onboarding_journey_admin', { p_member_id: action.memberId });
    const fresh: MemberRow | undefined = Array.isArray(data?.members) ? data.members[0] : undefined;
    if (fresh) setMembers((prev) => prev.map((m) => (m.member_id === fresh.member_id ? fresh : m)));
    setAction(null);
    setNote('');
    setBusy(false);
  };

  if (loading) {
    return <div className="flex items-center gap-2 py-16 justify-center text-[var(--text-muted)]"><Loader2 className="w-4 h-4 animate-spin" />{t('comp.onboardingJourney.loading', 'Carregando jornada…')}</div>;
  }
  if (error) return <div className="py-16 text-center text-red-600">{t('comp.onboardingJourney.loadError', 'Erro ao carregar a jornada')}: {error}</div>;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Route className="w-5 h-5 text-teal" />
        <h1 className="text-lg font-bold">{t('comp.onboardingJourney.title', 'Jornada de onboarding')}</h1>
        <button type="button" onClick={load} className="ml-auto text-xs inline-flex items-center gap-1 px-2 py-1 rounded border border-[var(--border-default)]">
          <RefreshCw className="w-3 h-3" />{t('comp.onboardingJourney.reload', 'Atualizar')}
        </button>
      </div>
      {scope && (
        <p className="text-xs text-[var(--text-muted)]">
          {scope.global
            ? t('comp.onboardingJourney.scopeGlobal', 'Você vê todos os membros.')
            : [scope.chapter ? `${t('comp.onboardingJourney.scopeChapter', 'Você vê o seu capítulo')}: ${scope.chapter}` : '',
               scope.lines && scope.lines.length ? `${t('comp.onboardingJourney.scopeLines', 'Você vê a sua linha')}: ${scope.lines.join(', ')}` : '']
                .filter(Boolean).join(' · ')}
        </p>
      )}
      <p className="text-sm text-[var(--text-secondary)]">{t('comp.onboardingJourney.intro', 'Cada etapa mostra como fechou: pelo fato, por clique da pessoa ou pelo GP. "Sem evidência" é uma etapa de fato fechada sem o fato registrado; é o que auditar.')}</p>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
        {catalog.filter((s) => s.closed_by === 'fact').map((s) => {
          const c = counts.get(s.id);
          return (
            <div key={s.id} className="rounded-lg border border-[var(--border-default)] p-2 text-xs">
              <div className="font-semibold mb-1">{label(s.id)}</div>
              <div>{t('comp.onboardingJourney.countPending', 'Pendentes')}: <b>{c?.pending ?? 0}</b></div>
              <div>{t('comp.onboardingJourney.countNoEvidence', 'Sem evidência')}: <b>{c?.noEvidence ?? 0}</b></div>
              <div>{t('comp.onboardingJourney.countUnclosed', 'Fato sem fechar')}: <b>{c?.unclosed ?? 0}</b></div>
              <div>{t('comp.onboardingJourney.countGp', 'Pelo GP')}: <b>{c?.gp ?? 0}</b></div>
            </div>
          );
        })}
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <label className="inline-flex items-center gap-1 border border-[var(--border-default)] rounded px-2 py-1">
          <Search className="w-3.5 h-3.5" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={t('comp.onboardingJourney.search', 'Buscar por nome')} className="bg-transparent outline-none" />
        </label>
        <select value={filter} onChange={(e) => setFilter(e.target.value as Filter)} className="border border-[var(--border-default)] rounded px-2 py-1 bg-transparent">
          <option value="all">{t('comp.onboardingJourney.filterAll', 'Todas')}</option>
          <option value="fact_pending">{t('comp.onboardingJourney.filterFactPending', 'Etapa de fato pendente')}</option>
          <option value="no_evidence">{t('comp.onboardingJourney.filterNoEvidence', 'Fechada sem evidência')}</option>
          <option value="fact_unclosed">{t('comp.onboardingJourney.filterUnclosed', 'Fato registrado, etapa aberta')}</option>
          <option value="gp">{t('comp.onboardingJourney.filterGp', 'Fechada pelo GP')}</option>
        </select>
        <select value={stepFilter} onChange={(e) => setStepFilter(e.target.value)} className="border border-[var(--border-default)] rounded px-2 py-1 bg-transparent">
          <option value="">{t('comp.onboardingJourney.allSteps', 'Todas as etapas')}</option>
          {catalog.map((s) => <option key={s.id} value={s.id}>{label(s.id)}</option>)}
        </select>
        <span className="text-xs text-[var(--text-muted)]">{visible.length} / {members.length}</span>
      </div>

      {visible.length === 0 ? (
        <div className="py-10 text-center text-[var(--text-muted)]">{t('comp.onboardingJourney.empty', 'Ninguém neste filtro.')}</div>
      ) : (
        <div className="rounded-lg border border-[var(--border-default)] divide-y divide-[var(--border-default)]">
          {visible.map((m) => {
            const steps = m.steps || [];
            const done = steps.filter(isClosed).length;
            const expanded = !!open[m.member_id];
            const shown = filter === 'all' && !stepFilter ? steps : steps.filter(matches);
            return (
              <Fragment key={m.member_id}>
                <button type="button" onClick={() => setOpen((o) => ({ ...o, [m.member_id]: !expanded }))}
                  className="w-full flex items-center gap-2 px-3 py-2 text-left text-sm hover:bg-[var(--surface-hover)]">
                  {expanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                  <span className="font-semibold">{m.name}</span>
                  <span className="text-xs text-[var(--text-muted)]">{m.chapter || ''}</span>
                  <span className="ml-auto text-xs">{done}/{steps.length}</span>
                </button>
                {expanded && (
                  <div className="px-3 pb-3 overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead>
                        <tr className="text-left text-[var(--text-muted)]">
                          <th className="py-1 pr-2">{t('comp.onboardingJourney.colStep', 'Etapa')}</th>
                          <th className="py-1 pr-2">{t('comp.onboardingJourney.colStatus', 'Status')}</th>
                          <th className="py-1 pr-2">{t('comp.onboardingJourney.colSource', 'Fonte')}</th>
                          <th className="py-1 pr-2">{t('comp.onboardingJourney.colEvidence', 'Evidência e registro')}</th>
                          <th className="py-1" />
                        </tr>
                      </thead>
                      <tbody>
                        {shown.map((s) => {
                          const isThis = action?.memberId === m.member_id && action?.stepKey === s.step_key;
                          const canMark = canCorrect && isFact(s.step_key) && !isClosed(s);
                          const canReopen = canCorrect && isClosed(s);
                          return (
                            <Fragment key={s.step_key}>
                              <tr className="align-top border-t border-[var(--border-default)]">
                                <td className="py-1 pr-2">{label(s.step_key)}</td>
                                <td className="py-1 pr-2 whitespace-nowrap">{s.status}{s.completed_at ? ` · ${fmtDate(s.completed_at)}` : ''}</td>
                                <td className="py-1 pr-2">{sourceBadge(s)}</td>
                                <td className="py-1 pr-2">
                                  {s.evidence && <div>{evidenceText(s.evidence)}</div>}
                                  {s.gp && <div>{t('comp.onboardingJourney.gpMarked', 'Marcada pelo GP')} {s.gp.name || ''} {fmtDate(s.gp.at)}: "{s.gp.note}"</div>}
                                  {(s.reopen_history || []).map((r, i) => (
                                    <div key={i} className="text-[var(--text-muted)]">{t('comp.onboardingJourney.reopened', 'Reaberta')} {fmtDate(r.reopened_at)}: "{r.reopen_note}"</div>
                                  ))}
                                </td>
                                <td className="py-1 whitespace-nowrap text-right">
                                  {canMark && (
                                    <button type="button" onClick={() => { setAction({ memberId: m.member_id, stepKey: s.step_key, kind: 'complete' }); setNote(''); setActionError(null); }}
                                      className="px-2 py-0.5 rounded bg-purple-600 text-white">{t('comp.onboardingJourney.markAsGp', 'Marcar como GP')}</button>
                                  )}
                                  {canReopen && (
                                    <button type="button" onClick={() => { setAction({ memberId: m.member_id, stepKey: s.step_key, kind: 'reopen' }); setNote(''); setActionError(null); }}
                                      className="px-2 py-0.5 rounded border border-[var(--border-default)]">{t('comp.onboardingJourney.reopen', 'Reabrir')}</button>
                                  )}
                                </td>
                              </tr>
                              {isThis && (
                                <tr>
                                  <td colSpan={5} className="pb-2">
                                    <div className="rounded border border-[var(--border-default)] p-2 space-y-2">
                                      <div className="font-semibold">{action?.kind === 'complete'
                                        ? t('comp.onboardingJourney.completeTitle', 'Marcar esta etapa pelo GP')
                                        : t('comp.onboardingJourney.reopenTitle', 'Reabrir esta etapa')}</div>
                                      <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2}
                                        placeholder={t('comp.onboardingJourney.notePlaceholder', 'Justificativa (fica registrada e visível)')}
                                        className="w-full border border-[var(--border-default)] rounded p-1 bg-transparent" />
                                      {actionError && <div className="text-red-600">{actionError}</div>}
                                      <div className="flex gap-2">
                                        <button type="button" disabled={busy} onClick={submit} className="px-2 py-1 rounded bg-teal text-white disabled:opacity-50">
                                          {busy ? <Loader2 className="w-3 h-3 animate-spin" /> : t('comp.onboardingJourney.confirm', 'Confirmar')}
                                        </button>
                                        <button type="button" disabled={busy} onClick={() => setAction(null)} className="px-2 py-1 rounded border border-[var(--border-default)]">
                                          {t('comp.onboardingJourney.cancel', 'Cancelar')}
                                        </button>
                                      </div>
                                    </div>
                                  </td>
                                </tr>
                              )}
                            </Fragment>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </Fragment>
            );
          })}
        </div>
      )}
    </div>
  );
}
