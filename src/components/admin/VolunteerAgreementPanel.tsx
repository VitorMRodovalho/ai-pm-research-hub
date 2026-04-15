import { useState, useEffect, useCallback } from 'react';

interface Props { lang?: string; }

interface MemberRow {
  id: string;
  name: string;
  email: string;
  chapter: string;
  tribe_id: number | null;
  role: string;
  signed: boolean;
  signed_at: string | null;
  verification_code: string | null;
  cycle_code: string | null;
  cycle_start: string | null;
  cycle_end: string | null;
  // 2-wave signature journey
  counter_signed: boolean;
  counter_signed_at: string | null;
  // Contract period (from signed cert, source of truth)
  contract_start: string | null;
  contract_end: string | null;
}

interface TemplateData {
  id: string;
  title: string;
  version: string;
  content: any;
}

interface ChapterRow {
  chapter: string;
  total: number;
  signed: number;
  unsigned: number;
}

interface Summary {
  total_eligible: number;
  signed: number;
  unsigned: number;
  pct: number;
}

interface FocalPoint {
  id: string;
  name: string;
  chapter: string;
  role: string;
}

const L: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Termo de Voluntariado',
    eligible: 'Elegíveis',
    signed: 'Assinaram',
    pending: 'Pendentes',
    compliance: 'Compliance',
    byChapter: 'Por Capítulo',
    memberList: 'Lista de Membros',
    all: 'Todos',
    signedOnly: 'Assinados',
    pendingOnly: 'Pendentes',
    name: 'Nome',
    chapter: 'Capítulo',
    role: 'Papel',
    status: 'Status',
    signedAt: 'Assinado em',
    code: 'Código',
    exportCsv: 'Exportar CSV',
    notifyPending: 'Notificar Pendentes',
    notifyConfirm: 'Enviar notificação para todos os membros que ainda não assinaram o termo?',
    notifySent: 'Notificações enviadas!',
    notifyError: 'Erro ao enviar notificações',
    noData: 'Sem dados',
    search: 'Buscar membro...',
    focalPoints: 'Pontos Focais (Contra-assinatura)',
    scopedView: 'Visualização do seu capítulo',
    viewTemplate: 'Ver Template',
    closeTemplate: 'Fechar',
    templateTitle: 'Template do Termo de Voluntariado',
    since: 'Desde',
    expires: 'Vence',
    cycle: 'Ciclo',
  },
  'en-US': {
    title: 'Volunteer Agreement',
    eligible: 'Eligible',
    signed: 'Signed',
    pending: 'Pending',
    compliance: 'Compliance',
    byChapter: 'By Chapter',
    memberList: 'Member List',
    all: 'All',
    signedOnly: 'Signed',
    pendingOnly: 'Pending',
    name: 'Name',
    chapter: 'Chapter',
    role: 'Role',
    status: 'Status',
    signedAt: 'Signed at',
    code: 'Code',
    exportCsv: 'Export CSV',
    notifyPending: 'Notify Pending',
    notifyConfirm: 'Send notification to all members who haven\'t signed yet?',
    notifySent: 'Notifications sent!',
    notifyError: 'Error sending notifications',
    noData: 'No data',
    search: 'Search member...',
    focalPoints: 'Focal Points (Counter-signature)',
    scopedView: 'Viewing your chapter only',
    viewTemplate: 'View Template',
    closeTemplate: 'Close',
    templateTitle: 'Volunteer Agreement Template',
    since: 'Since',
    expires: 'Expires',
    cycle: 'Cycle',
  },
  'es-LATAM': {
    title: 'Acuerdo de Voluntariado',
    eligible: 'Elegibles',
    signed: 'Firmados',
    pending: 'Pendientes',
    compliance: 'Cumplimiento',
    byChapter: 'Por Capítulo',
    memberList: 'Lista de Miembros',
    all: 'Todos',
    signedOnly: 'Firmados',
    pendingOnly: 'Pendientes',
    name: 'Nombre',
    chapter: 'Capítulo',
    role: 'Rol',
    status: 'Estado',
    signedAt: 'Firmado en',
    code: 'Código',
    exportCsv: 'Exportar CSV',
    notifyPending: 'Notificar Pendientes',
    notifyConfirm: '¿Enviar notificación a todos los miembros que aún no firmaron?',
    notifySent: '¡Notificaciones enviadas!',
    notifyError: 'Error al enviar notificaciones',
    noData: 'Sin datos',
    search: 'Buscar miembro...',
    focalPoints: 'Puntos Focales (Contra-firma)',
    scopedView: 'Viendo solo su capítulo',
    viewTemplate: 'Ver Plantilla',
    closeTemplate: 'Cerrar',
    templateTitle: 'Plantilla del Acuerdo de Voluntariado',
    since: 'Desde',
    expires: 'Vence',
    cycle: 'Ciclo',
  },
};

function useLang(p?: string): string {
  if (p) return p;
  if (typeof window !== 'undefined') {
    if (location.pathname.startsWith('/en')) return 'en-US';
    if (location.pathname.startsWith('/es')) return 'es-LATAM';
  }
  return 'pt-BR';
}

function fmtDate(d: string | null): string {
  if (!d) return '—';
  // Fix timezone shift: date-only strings (YYYY-MM-DD) parse as UTC midnight
  // → BRT (-03) shifts to previous day. Force noon local time instead.
  const clean = String(d).slice(0, 10);
  const dt = clean.length === 10 ? new Date(clean + 'T12:00:00') : new Date(d);
  if (isNaN(dt.getTime())) return String(d);
  return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
}

export default function VolunteerAgreementPanel({ lang: propLang }: Props) {
  const lang = useLang(propLang);
  const t = L[lang] || L['pt-BR'];

  const [summary, setSummary] = useState<Summary | null>(null);
  const [chapters, setChapters] = useState<ChapterRow[]>([]);
  const [members, setMembers] = useState<MemberRow[]>([]);
  const [focalPoints, setFocalPoints] = useState<FocalPoint[]>([]);
  const [template, setTemplate] = useState<TemplateData | null>(null);
  const [showTemplate, setShowTemplate] = useState(false);
  const [isManager, setIsManager] = useState(false);
  const [callerChapter, setCallerChapter] = useState<string>('');
  const [authorized, setAuthorized] = useState(false);
  const [filter, setFilter] = useState<'all' | 'signed' | 'pending'>('all');
  const [chapterFilter, setChapterFilter] = useState<string>('');
  const [search, setSearch] = useState('');
  const [notifying, setNotifying] = useState(false);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    const m = (window as any).navGetMember?.();
    if (!m) { setTimeout(load, 500); return; }
    if (!(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role) || (m.designations || []).includes('chapter_board'))) return;
    setAuthorized(true);
    const { data: d } = await sb.rpc('get_volunteer_agreement_status');
    if (d && !d.error) {
      setSummary(d.summary);
      setChapters(d.by_chapter || []);
      setMembers(d.members || []);
      setFocalPoints(d.focal_points || []);
      setTemplate(d.template || null);
      setIsManager(d.is_manager || false);
      setCallerChapter(d.caller_chapter || '');
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!authorized || !summary) return null;

  const filtered = members.filter(m => {
    if (filter === 'signed' && !m.signed) return false;
    if (filter === 'pending' && m.signed) return false;
    if (chapterFilter && m.chapter !== chapterFilter) return false;
    if (search && !m.name.toLowerCase().includes(search.toLowerCase()) && !m.email.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const uniqueChapters = [...new Set(members.map(m => m.chapter).filter(Boolean))].sort();

  const exportCsv = () => {
    const header = 'Nome,Email,Capítulo,Papel,Status,Assinado em,Código\n';
    const rows = filtered.map(m =>
      `"${m.name}","${m.email}","${m.chapter || ''}","${m.role}","${m.signed ? 'Assinado' : 'Pendente'}","${m.signed_at || ''}","${m.verification_code || ''}"`
    ).join('\n');
    const blob = new Blob([header + rows], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `volunteer_agreement_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const notifyPending = async () => {
    if (!confirm(t.notifyConfirm)) return;
    setNotifying(true);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) return;
      const unsigned = members.filter(m => !m.signed);
      for (const m of unsigned) {
        await sb.rpc('create_notification', {
          p_recipient_id: m.id,
          p_type: 'system',
          p_title: lang === 'en-US' ? 'Volunteer Agreement Pending' : lang === 'es-LATAM' ? 'Acuerdo de Voluntariado Pendiente' : 'Termo de Voluntariado Pendente',
          p_body: lang === 'en-US' ? 'Please sign your volunteer agreement to stay compliant.' : lang === 'es-LATAM' ? 'Por favor firma tu acuerdo de voluntariado.' : 'Por favor assine seu termo de voluntariado para manter a conformidade.',
          p_link: '/volunteer-agreement',
        });
      }
      (window as any).toast?.(t.notifySent, 'success');
    } catch {
      (window as any).toast?.(t.notifyError, 'error');
    } finally {
      setNotifying(false);
    }
  };

  const pctColor = (summary.pct ?? 0) >= 80 ? 'text-emerald-600' : (summary.pct ?? 0) >= 50 ? 'text-amber-600' : 'text-red-600';

  return (
    <div className="space-y-5">
      {/* Context: who is counted */}
      <div className="text-[10px] text-[var(--text-muted)] bg-[var(--surface-section-cool)] rounded-lg px-3 py-1.5">
        {summary.total_eligible} voluntários operacionais de 52 membros ativos (sponsors, liaisons e observers isentos)
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 text-center">
          <div className="text-2xl font-extrabold text-navy">{summary.total_eligible}</div>
          <div className="text-[10px] font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t.eligible}</div>
        </div>
        <div className="rounded-xl border border-emerald-200 bg-emerald-50/50 dark:bg-emerald-900/10 p-4 text-center">
          <div className="text-2xl font-extrabold text-emerald-600">{summary.signed}</div>
          <div className="text-[10px] font-semibold text-emerald-600 uppercase tracking-wide">{t.signed}</div>
        </div>
        <div className="rounded-xl border border-amber-200 bg-amber-50/50 dark:bg-amber-900/10 p-4 text-center">
          <div className="text-2xl font-extrabold text-amber-600">{summary.unsigned}</div>
          <div className="text-[10px] font-semibold text-amber-600 uppercase tracking-wide">{t.pending}</div>
        </div>
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4 text-center">
          <div className={`text-2xl font-extrabold ${pctColor}`}>{summary.pct ?? 0}%</div>
          <div className="text-[10px] font-semibold text-[var(--text-muted)] uppercase tracking-wide">{t.compliance}</div>
        </div>
      </div>

      {/* Template preview button */}
      {template && (
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowTemplate(true)}
            className="px-3 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-secondary)] text-[11px] font-semibold cursor-pointer hover:bg-[var(--surface-hover)]"
          >
            📄 {t.viewTemplate} ({template.version})
          </button>
        </div>
      )}

      {/* Template modal — formal document */}
      {showTemplate && template && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4" onClick={() => setShowTemplate(false)}>
          <div className="bg-white dark:bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] max-w-3xl w-full max-h-[85vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            {/* Close button */}
            <div className="sticky top-0 bg-white/95 dark:bg-[var(--surface-card)]/95 backdrop-blur px-6 py-3 border-b border-[var(--border-subtle)] flex items-center justify-between z-10">
              <span className="text-[10px] font-semibold text-[var(--text-muted)]">{template.title} — {template.version}</span>
              <button onClick={() => setShowTemplate(false)} className="text-[var(--text-muted)] hover:text-[var(--text-primary)] bg-transparent border-0 cursor-pointer text-lg">✕</button>
            </div>

            <div className="px-8 py-6 text-[13px] leading-relaxed text-[var(--text-secondary)]">
              {(() => {
                try {
                  const c = typeof template.content === 'string' ? JSON.parse(template.content) : template.content;
                  const SUB_KEYS: Record<string, string[]> = {
                    clause1: ['clause1a', 'clause1b', 'clause1c'],
                    clause2: ['clause2_1', 'clause2_2', 'clause2_3', 'clause2_4', 'clause2_5'],
                    clause7: ['clause7a'],
                    clause9: ['clause9a', 'clause9b', 'clause9c', 'clause9d', 'clause9e', 'clause9f'],
                  };
                  const MAIN = ['clause1','clause2','clause3','clause4','clause5','clause6','clause7','clause8','clause9','clause10','clause11','clause12'];

                  return (
                    <>
                      {/* Header */}
                      <div className="text-center mb-6">
                        <h2 className="text-lg font-bold text-navy uppercase tracking-wide">Termo de Compromisso de Voluntário com o PMI Goiás</h2>
                      </div>

                      {/* Preamble */}
                      <p className="mb-4 text-[12px]">
                        <strong>Termo de Compromisso de Voluntário com o PMI Goiás</strong> que fazem entre si a <strong>Seção Goiânia, Goiás — Brasil do Project Management Institute (PMI Goiás)</strong>, inscrito no CNPJ/MF sob o nº 06.065.645/0001-99 e:
                      </p>

                      {/* Member data placeholder */}
                      <div className="bg-gray-50 dark:bg-[var(--surface-section-cool)] rounded-lg p-4 mb-4 text-[11px] space-y-1 border border-dashed border-gray-300 dark:border-[var(--border-subtle)]">
                        <div className="text-[var(--text-muted)] italic">[ Dados do membro preenchidos automaticamente na assinatura ]</div>
                        <div>PMI ID: ______ &nbsp;|&nbsp; Nome: ______ &nbsp;|&nbsp; E-mail: ______</div>
                        <div>Cidade/Estado: ______ &nbsp;|&nbsp; Contato: ______</div>
                      </div>

                      <p className="mb-4 text-[12px]">
                        Doravante denominado <strong>VOLUNTÁRIO</strong>, com o objetivo de colaborar como voluntário ao PMI Goiás, nos projetos e processos do Capítulo.
                      </p>

                      <h3 className="font-bold text-navy text-[13px] mt-6 mb-3">Termos da Adesão do Programa de Voluntariado:</h3>

                      {/* Clauses */}
                      <ol className="space-y-3 list-none">
                        {MAIN.map((key, i) => {
                          const text = c[key] || '';
                          const subs = SUB_KEYS[key];
                          return (
                            <li key={key}>
                              <div className="flex gap-2">
                                <span className="font-bold text-[var(--text-muted)] shrink-0">{i + 1}.</span>
                                <span>{text}</span>
                              </div>
                              {subs && (
                                <ol className="mt-2 ml-6 space-y-2">
                                  {subs.map(subKey => {
                                    const subText = c[subKey] || '';
                                    const letter = subKey.slice(-1);
                                    const isNote = subKey.endsWith('note');
                                    const isNumbered = /_\d+$/.test(subKey);
                                    return (
                                      <li key={subKey} className={`text-[12px] ${isNote ? 'italic border-l-2 border-gray-300 pl-3 mt-3' : ''}`}>
                                        <div className="flex gap-2">
                                          {!isNote && !isNumbered && <span className="font-semibold text-[var(--text-muted)] shrink-0">{letter}.</span>}
                                          <span>{subText}</span>
                                        </div>
                                      </li>
                                    );
                                  })}
                                </ol>
                              )}
                            </li>
                          );
                        })}
                      </ol>

                      {/* Signature block */}
                      <div className="mt-8 pt-4 border-t border-[var(--border-subtle)]">
                        <p className="text-[11px] text-[var(--text-muted)] italic mb-6">Goiânia/GO, [ data da assinatura ]</p>
                        <div className="grid grid-cols-2 gap-8 text-center text-[11px]">
                          <div className="pt-8 border-t border-gray-400">Assinatura do Voluntário</div>
                          <div className="pt-8 border-t border-gray-400">Assinatura do Diretor do PMI Goiás</div>
                        </div>
                      </div>

                      {/* Annex */}
                      <div className="mt-8 pt-4 border-t-2 border-navy">
                        <h3 className="font-bold text-navy text-[13px] mb-3">ANEXO — LEI DO SERVIÇO VOLUNTÁRIO</h3>
                        <p className="text-[11px] text-[var(--text-muted)] mb-2">Lei nº 9.608, de 18 de fevereiro de 1998</p>
                        <p className="text-[11px] text-[var(--text-muted)] mb-3 italic">Dispõe sobre o serviço voluntário e dá outras providências.</p>
                        <div className="space-y-2 text-[11px]">
                          <p><strong>Art. 1º</strong> Considera-se serviço voluntário, para fins desta Lei, a atividade não remunerada, prestada por pessoa física a entidade pública de qualquer natureza, ou a Instituição privada de fins não lucrativos, que tenha objetivos cívicos, culturais, educacionais, científicos, recreativos ou de assistência social, inclusive mutualidade.</p>
                          <p className="italic ml-4">Parágrafo único. O serviço voluntário não gera vínculo empregatício, nem obrigação de natureza trabalhista, previdenciária ou afim.</p>
                          <p><strong>Art. 2º</strong> O serviço voluntário será exercido mediante a celebração de Termo de Adesão entre a entidade, pública ou privada, e o prestador do serviço voluntário, dele devendo constar o objeto e as condições de seu exercício.</p>
                          <p><strong>Art. 3º</strong> O prestador de serviço voluntário poderá ser ressarcido pelas despesas que comprovadamente realizar no desempenho das atividades voluntárias.</p>
                          <p className="italic ml-4">Parágrafo único. As despesas a serem ressarcidas deverão estar expressamente autorizadas pela entidade a que for prestado o serviço voluntário.</p>
                          <p><strong>Art. 4º</strong> Esta Lei entra em vigor na data de sua publicação.</p>
                          <p><strong>Art. 5º</strong> Revogam-se as disposições em contrário.</p>
                        </div>
                      </div>
                    </>
                  );
                } catch { return <p>Erro ao carregar template</p>; }
              })()}
            </div>

            {/* Footer */}
            <div className="sticky bottom-0 bg-white/95 dark:bg-[var(--surface-card)]/95 backdrop-blur px-6 py-3 border-t border-[var(--border-subtle)] text-center">
              <button onClick={() => setShowTemplate(false)} className="px-5 py-2 rounded-lg bg-navy text-white text-xs font-semibold border-0 cursor-pointer hover:opacity-90">{t.closeTemplate}</button>
            </div>
          </div>
        </div>
      )}

      {/* Scoped view indicator for chapter_board */}
      {!isManager && callerChapter && (
        <div className="rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 px-4 py-2.5 flex items-center gap-2">
          <span className="text-sm">🏢</span>
          <span className="text-[11px] font-semibold text-blue-700 dark:text-blue-300">{t.scopedView}: {callerChapter}</span>
        </div>
      )}

      {/* Focal points */}
      {focalPoints.length > 0 && isManager && (
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
          <h3 className="text-xs font-bold text-navy mb-3">{t.focalPoints}</h3>
          <div className="flex flex-wrap gap-2">
            {focalPoints.map(fp => (
              <div key={fp.id} className="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--surface-section-cool)] border border-[var(--border-subtle)]">
                <span className="text-[11px] font-semibold text-[var(--text-primary)]">{fp.name}</span>
                <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-navy/10 text-navy font-bold">{fp.chapter}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* By chapter */}
      {chapters.length > 0 && (
        <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
          <h3 className="text-xs font-bold text-navy mb-3">{t.byChapter}</h3>
          <div className="space-y-2">
            {chapters.map(ch => {
              const pct = ch.total > 0 ? Math.round((ch.signed / ch.total) * 100) : 0;
              return (
                <div key={ch.chapter} className="flex items-center gap-3">
                  <span className="text-[11px] font-semibold text-[var(--text-primary)] w-20 truncate">{ch.chapter}</span>
                  <div className="flex-1 bg-[var(--surface-section-cool)] rounded-full h-2.5 overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all ${pct >= 80 ? 'bg-emerald-500' : pct >= 50 ? 'bg-amber-400' : 'bg-red-400'}`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                  <span className="text-[10px] font-mono text-[var(--text-muted)] w-16 text-right">{ch.signed}/{ch.total} ({pct}%)</span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Member list */}
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] overflow-hidden">
        {/* Toolbar */}
        <div className="px-4 py-3 border-b border-[var(--border-subtle)] flex flex-wrap items-center gap-2">
          <h3 className="text-xs font-bold text-navy mr-auto">{t.memberList} ({filtered.length})</h3>

          <input
            type="text"
            placeholder={t.search}
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="text-[11px] px-2.5 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] w-40"
          />

          <select
            value={chapterFilter}
            onChange={e => setChapterFilter(e.target.value)}
            className="text-[11px] px-2 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)]"
          >
            <option value="">{t.all} ({t.chapter})</option>
            {uniqueChapters.map(ch => <option key={ch} value={ch}>{ch}</option>)}
          </select>

          <div className="flex rounded-lg border border-[var(--border-default)] overflow-hidden">
            {(['all', 'signed', 'pending'] as const).map(f => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={`px-2.5 py-1 text-[10px] font-semibold border-0 cursor-pointer transition-colors ${
                  filter === f ? 'bg-navy text-white' : 'bg-[var(--surface-base)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
                }`}
              >
                {f === 'all' ? t.all : f === 'signed' ? t.signedOnly : t.pendingOnly}
              </button>
            ))}
          </div>

          <button
            onClick={exportCsv}
            className="px-2.5 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-secondary)] text-[10px] font-semibold cursor-pointer hover:bg-[var(--surface-hover)]"
          >
            📥 {t.exportCsv}
          </button>

          {summary.unsigned > 0 && (
            <button
              onClick={notifyPending}
              disabled={notifying}
              className="px-2.5 py-1.5 rounded-lg bg-amber-500 text-white text-[10px] font-semibold cursor-pointer border-0 hover:bg-amber-600 disabled:opacity-50"
            >
              🔔 {t.notifyPending} ({summary.unsigned})
            </button>
          )}
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-[11px]">
            <thead>
              <tr className="text-[var(--text-muted)] border-b border-[var(--border-subtle)] bg-[var(--surface-section-cool)]">
                <th className="text-left px-4 py-2 font-semibold">{t.name}</th>
                <th className="text-left px-3 py-2 font-semibold">{t.chapter}</th>
                <th className="text-left px-3 py-2 font-semibold">{t.role}</th>
                <th className="text-left px-3 py-2 font-semibold">{t.cycle}</th>
                <th className="text-left px-3 py-2 font-semibold">Período do Contrato</th>
                <th className="text-center px-3 py-2 font-semibold" title="Voluntário assinou / Diretor contra-assinou">✍️ Voluntário / 👔 Diretor</th>
                <th className="text-left px-3 py-2 font-semibold">{t.signedAt}</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(m => (
                <tr key={m.id} className="border-b border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]">
                  <td className="px-4 py-2 font-medium text-[var(--text-primary)]">
                    <a href={`/admin/members/${m.id}`} className="text-navy hover:underline no-underline">{m.name}</a>
                  </td>
                  <td className="px-3 py-2 text-[var(--text-secondary)]">{m.chapter || '—'}</td>
                  <td className="px-3 py-2 text-[var(--text-secondary)]">{m.role}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)] font-mono text-[9px]">{m.cycle_code?.replace('_', ' ') || '—'}</td>
                  <td className="px-3 py-2 text-[var(--text-muted)] text-[10px]">
                    {/* Use contract period from the signed cert (source of truth). Fallback to cycle_history. */}
                    {m.contract_start ? (
                      <>
                        {fmtDate(m.contract_start)}
                        {m.contract_end && <span className="text-[var(--text-muted)]"> → {fmtDate(m.contract_end)}</span>}
                      </>
                    ) : m.cycle_start ? (
                      <>
                        {fmtDate(m.cycle_start)}
                        {m.cycle_end && <span className="text-[var(--text-muted)]"> → {fmtDate(m.cycle_end)}</span>}
                      </>
                    ) : '—'}
                  </td>
                  <td className="px-3 py-2 text-center whitespace-nowrap">
                    {/* 2-wave signature badges */}
                    {!m.signed && (
                      <span className="inline-block px-2 py-0.5 rounded-full text-[9px] font-bold bg-red-100 text-red-700" title="Voluntário não assinou">❌ Não assinado</span>
                    )}
                    {m.signed && !m.counter_signed && (
                      <span className="inline-block px-2 py-0.5 rounded-full text-[9px] font-bold bg-amber-100 text-amber-700" title="Voluntário assinou. Aguardando diretor.">
                        ✍️ Aguarda diretor
                      </span>
                    )}
                    {m.signed && m.counter_signed && (
                      <span className="inline-block px-2 py-0.5 rounded-full text-[9px] font-bold bg-emerald-100 text-emerald-700" title="Voluntário + Diretor assinaram">
                        ✓✓ Completo
                      </span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-muted)] text-[10px]">
                    {m.signed_at && <div>✍️ {fmtDate(m.signed_at)}</div>}
                    {m.counter_signed_at && <div className="text-emerald-600">👔 {fmtDate(m.counter_signed_at)}</div>}
                    {!m.signed_at && '—'}
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-[var(--text-muted)]">{t.noData}</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
