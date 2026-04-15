import { useState, useEffect, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { marked } from 'marked';

interface Meeting {
  id: string;
  title: string;
  date: string;
  type: string;
  tribe_id: number | null;
  tribe_name: string | null;
  youtube_url: string | null;
  recording_url: string | null;
  has_minutes: boolean;
  minutes_length: number;
  has_agenda: boolean;
  attendee_count: number;
}

interface Props {
  lang?: string;
}

const L: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Atas de Reunião',
    subtitle: 'Arquivo pesquisável de todas as atas do Núcleo',
    search: 'Buscar em títulos, atas e agendas...',
    allTribes: 'Todas as tribos',
    allTypes: 'Todos os tipos',
    typeGeral: 'Geral',
    typeTribo: 'Tribo',
    typeKickoff: 'Kick-off',
    typeLideranca: 'Liderança',
    includeEmpty: 'Incluir eventos sem ata',
    noResults: 'Nenhuma ata encontrada.',
    hasYoutube: '📺 YouTube',
    hasMinutes: '📝 Ata',
    noMinutes: '⚠️ Sem ata',
    attendees: 'presentes',
    general: 'Geral (sem tribo)',
    openDetail: 'Ver ata completa',
    loading: 'Carregando...',
    compliance: 'Compliance de atas',
    byTribe: 'Por tribo',
    recorded: 'Gravados',
    withMinutes: 'Com ata',
  },
  'en-US': {
    title: 'Meeting Minutes',
    subtitle: 'Searchable archive of all Hub meeting minutes',
    search: 'Search titles, minutes, and agendas...',
    allTribes: 'All tribes',
    allTypes: 'All types',
    typeGeral: 'General',
    typeTribo: 'Tribe',
    typeKickoff: 'Kick-off',
    typeLideranca: 'Leadership',
    includeEmpty: 'Include events without minutes',
    noResults: 'No minutes found.',
    hasYoutube: '📺 YouTube',
    hasMinutes: '📝 Minutes',
    noMinutes: '⚠️ No minutes',
    attendees: 'attendees',
    general: 'General (no tribe)',
    openDetail: 'View full minutes',
    loading: 'Loading...',
    compliance: 'Minutes compliance',
    byTribe: 'By tribe',
    recorded: 'Recorded',
    withMinutes: 'With minutes',
  },
  'es-LATAM': {
    title: 'Actas de Reunión',
    subtitle: 'Archivo buscable de todas las actas del Núcleo',
    search: 'Buscar en títulos, actas y agendas...',
    allTribes: 'Todas las tribus',
    allTypes: 'Todos los tipos',
    typeGeral: 'General',
    typeTribo: 'Tribu',
    typeKickoff: 'Kick-off',
    typeLideranca: 'Liderazgo',
    includeEmpty: 'Incluir eventos sin acta',
    noResults: 'No se encontraron actas.',
    hasYoutube: '📺 YouTube',
    hasMinutes: '📝 Acta',
    noMinutes: '⚠️ Sin acta',
    attendees: 'presentes',
    general: 'General (sin tribu)',
    openDetail: 'Ver acta completa',
    loading: 'Cargando...',
    compliance: 'Cumplimiento de actas',
    byTribe: 'Por tribu',
    recorded: 'Grabados',
    withMinutes: 'Con acta',
  },
};

interface Tribe { id: number; name: string; }
interface ComplianceData {
  by_tribe: Array<{ tribe_id: number | null; tribe_name: string; recorded: number; with_minutes: number; pct: number }>;
  total_recorded: number;
  total_with_minutes: number;
  overall_pct: number;
}

export default function MeetingsPage({ lang = 'pt-BR' }: Props) {
  const l = L[lang] || L['pt-BR'];
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [tribes, setTribes] = useState<Tribe[]>([]);
  const [compliance, setCompliance] = useState<ComplianceData | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [tribeFilter, setTribeFilter] = useState<number | null>(null);
  const [typeFilter, setTypeFilter] = useState<string | null>(null);
  const [includeEmpty, setIncludeEmpty] = useState(false);
  const [selectedMeeting, setSelectedMeeting] = useState<any | null>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const loadMeetings = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    try {
      const { data } = await sb.rpc('list_meetings_with_notes', {
        p_tribe_id: tribeFilter,
        p_type: typeFilter,
        p_search: search || null,
        p_include_empty: includeEmpty,
        p_limit: 200,
        p_offset: 0,
      });
      if (data?.meetings) setMeetings(data.meetings);
    } catch (e) { console.error('Failed to load meetings:', e); }
    setLoading(false);
  }, [getSb, search, tribeFilter, typeFilter, includeEmpty]);

  const loadTribes = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { data } = await sb.from('tribes').select('id, name').eq('is_active', true).order('name');
      if (data) setTribes(data);
    } catch {}
  }, [getSb]);

  const loadCompliance = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { data } = await sb.rpc('get_meeting_notes_compliance');
      if (data) setCompliance(data);
    } catch {}
  }, [getSb]);

  useEffect(() => {
    const boot = () => {
      if ((window as any).navGetSb?.()) {
        loadTribes();
        loadCompliance();
        loadMeetings();
      } else setTimeout(boot, 500);
    };
    boot();
  }, [loadTribes, loadCompliance, loadMeetings]);

  useEffect(() => {
    const delay = setTimeout(loadMeetings, 300); // debounce
    return () => clearTimeout(delay);
  }, [search, tribeFilter, typeFilter, includeEmpty, loadMeetings]);

  const openDetail = async (meetingId: string) => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_meeting_detail', { p_event_id: meetingId });
    if (data && !data.error) setSelectedMeeting(data);
  };

  // Group meetings by tribe
  const grouped: Record<string, Meeting[]> = {};
  for (const m of meetings) {
    const key = m.tribe_name || l.general;
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(m);
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-6">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-3xl font-extrabold text-navy mb-1">{l.title}</h1>
        <p className="text-[var(--text-secondary)]">{l.subtitle}</p>
      </div>

      {/* Compliance card */}
      {compliance && (
        <div className="mb-6 p-4 rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)]">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-base font-bold text-navy">{l.compliance}</h2>
            <div className="text-2xl font-extrabold text-navy">
              {compliance.overall_pct}%
              <span className="text-xs font-semibold text-[var(--text-muted)] ml-2">
                {compliance.total_with_minutes}/{compliance.total_recorded}
              </span>
            </div>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
            {compliance.by_tribe.map((t) => (
              <div key={`${t.tribe_id}-${t.tribe_name}`}
                className={`rounded-xl p-2.5 border ${t.pct === 100 ? 'border-emerald-300 bg-emerald-50/40' : t.pct >= 50 ? 'border-amber-300 bg-amber-50/40' : 'border-red-300 bg-red-50/40'}`}>
                <div className="text-[10px] font-semibold text-[var(--text-secondary)] truncate">{t.tribe_name}</div>
                <div className="text-lg font-extrabold text-navy">{t.pct}%</div>
                <div className="text-[9px] text-[var(--text-muted)]">{t.with_minutes}/{t.recorded}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="mb-4 flex flex-wrap gap-2 items-center">
        <input type="text" value={search} onChange={(e) => setSearch(e.target.value)}
          placeholder={l.search}
          className="flex-1 min-w-[200px] px-3 py-2 rounded-lg border-[1.5px] border-[var(--border-default)] text-sm focus:outline-none focus:border-navy" />
        <select value={tribeFilter || ''} onChange={(e) => setTribeFilter(e.target.value ? parseInt(e.target.value) : null)}
          className="px-3 py-2 rounded-lg border-[1.5px] border-[var(--border-default)] text-sm bg-[var(--surface-card)]">
          <option value="">{l.allTribes}</option>
          {tribes.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
        <select value={typeFilter || ''} onChange={(e) => setTypeFilter(e.target.value || null)}
          className="px-3 py-2 rounded-lg border-[1.5px] border-[var(--border-default)] text-sm bg-[var(--surface-card)]">
          <option value="">{l.allTypes}</option>
          <option value="geral">{l.typeGeral}</option>
          <option value="tribo">{l.typeTribo}</option>
          <option value="kickoff">{l.typeKickoff}</option>
          <option value="lideranca">{l.typeLideranca}</option>
        </select>
        <label className="flex items-center gap-1.5 text-xs text-[var(--text-secondary)] cursor-pointer">
          <input type="checkbox" checked={includeEmpty} onChange={(e) => setIncludeEmpty(e.target.checked)} />
          {l.includeEmpty}
        </label>
      </div>

      {/* Results */}
      {loading ? (
        <div className="text-center py-8 text-[var(--text-muted)]">{l.loading}</div>
      ) : meetings.length === 0 ? (
        <div className="text-center py-8 text-[var(--text-muted)]">{l.noResults}</div>
      ) : (
        <div className="space-y-6">
          {Object.entries(grouped).map(([tribeName, list]) => (
            <div key={tribeName}>
              <h3 className="text-sm font-bold text-[var(--text-secondary)] uppercase tracking-wide mb-2">
                {tribeName} <span className="text-[var(--text-muted)] font-normal">({list.length})</span>
              </h3>
              <div className="space-y-2">
                {list.map((m) => (
                  <button key={m.id} onClick={() => openDetail(m.id)}
                    className="w-full text-left bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-3 hover:border-navy hover:shadow-sm transition-all cursor-pointer">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex-1 min-w-0">
                        <div className="font-semibold text-navy text-sm truncate">{m.title}</div>
                        <div className="text-xs text-[var(--text-muted)]">
                          {new Date(m.date).toLocaleDateString(lang === 'pt-BR' ? 'pt-BR' : lang === 'en-US' ? 'en-US' : 'es')}
                          {m.attendee_count > 0 && ` · ${m.attendee_count} ${l.attendees}`}
                        </div>
                      </div>
                      <div className="flex gap-1.5 flex-shrink-0">
                        {m.youtube_url && <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-red-100 text-red-700">YT</span>}
                        {m.has_minutes ? (
                          <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-700">📝</span>
                        ) : (
                          <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">⚠️</span>
                        )}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Detail modal */}
      {selectedMeeting && (
        <div className="fixed inset-0 bg-black/60 z-[100] flex items-start justify-center p-4 overflow-y-auto"
             onClick={(e) => { if (e.target === e.currentTarget) setSelectedMeeting(null); }}>
          <div className="bg-[var(--surface-card)] rounded-2xl max-w-3xl w-full mt-12 shadow-xl">
            <div className="px-5 py-4 border-b border-[var(--border-default)] flex items-start justify-between gap-3">
              <div>
                <h2 className="text-xl font-extrabold text-navy">{selectedMeeting.event.title}</h2>
                <div className="text-xs text-[var(--text-muted)] mt-1">
                  {new Date(selectedMeeting.event.date).toLocaleDateString()}
                  {selectedMeeting.event.tribe_name && ` · ${selectedMeeting.event.tribe_name}`}
                  {` · ${selectedMeeting.attendee_count} ${l.attendees}`}
                </div>
              </div>
              <button onClick={() => setSelectedMeeting(null)} className="text-2xl text-[var(--text-muted)] hover:text-navy">×</button>
            </div>
            <div className="p-5 max-h-[70vh] overflow-y-auto space-y-4">
              {selectedMeeting.event.youtube_url && (
                <a href={selectedMeeting.event.youtube_url} target="_blank" rel="noopener"
                   className="inline-block px-3 py-1.5 rounded-lg bg-red-100 text-red-700 text-xs font-semibold no-underline hover:bg-red-200">
                  📺 Ver no YouTube
                </a>
              )}
              {selectedMeeting.event.agenda_text && (
                <div>
                  <h3 className="text-sm font-bold text-navy mb-1">Agenda</h3>
                  <div className="prose prose-sm max-w-none text-[var(--text-primary)] bg-[var(--surface-base)] p-4 rounded-lg
                    prose-headings:text-navy prose-headings:font-bold prose-headings:mt-3 prose-headings:mb-1
                    prose-p:my-1 prose-li:my-0.5 prose-ul:my-1 prose-ol:my-1
                    prose-strong:text-[var(--text-primary)]">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{selectedMeeting.event.agenda_text}</ReactMarkdown>
                  </div>
                </div>
              )}
              {selectedMeeting.event.minutes_text ? (
                <div>
                  <h3 className="text-sm font-bold text-navy mb-1">Ata</h3>
                  <div className="prose prose-sm max-w-none text-[var(--text-primary)] bg-[var(--surface-base)] p-4 rounded-lg
                    prose-headings:text-navy prose-headings:font-bold prose-headings:mt-3 prose-headings:mb-1
                    prose-p:my-1 prose-li:my-0.5 prose-ul:my-1 prose-ol:my-1
                    prose-strong:text-[var(--text-primary)]">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{selectedMeeting.event.minutes_text}</ReactMarkdown>
                  </div>
                </div>
              ) : (
                <div className="text-xs text-amber-700 bg-amber-50 p-3 rounded-lg">{l.noMinutes}</div>
              )}
            </div>
            {/* Print button */}
            {selectedMeeting.event.minutes_text && (
              <div className="px-5 py-3 border-t border-[var(--border-default)] flex justify-end">
                <button
                  onClick={() => {
                    const m = selectedMeeting;
                    const date = new Date(m.event.date).toLocaleDateString('pt-BR', { dateStyle: 'long' });
                    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Ata — ${m.event.title}</title>
                      <style>body{font-family:Georgia,serif;max-width:800px;margin:40px auto;padding:0 20px;color:#333;line-height:1.6}
                      h1{font-size:18px;color:#1a365d;border-bottom:2px solid #1a365d;padding-bottom:8px}
                      h2{font-size:15px;color:#1a365d;margin-top:20px}h3{font-size:13px;color:#444;margin-top:16px}
                      ul,ol{padding-left:20px}li{margin:4px 0}
                      .meta{font-size:12px;color:#666;margin-bottom:20px}
                      .footer{margin-top:40px;padding-top:12px;border-top:1px solid #ccc;font-size:10px;color:#888}
                      @media print{body{margin:20px}}</style></head><body>
                      <h1>${m.event.title}</h1>
                      <div class="meta">${date}${m.event.tribe_name ? ` · ${m.event.tribe_name}` : ''} · ${m.attendee_count || 0} presentes</div>
                      ${m.event.agenda_text ? `<h2>Agenda</h2>${marked.parse(m.event.agenda_text)}` : ''}
                      <h2>Ata</h2>${marked.parse(m.event.minutes_text)}
                      <div class="footer">Núcleo de IA & GP — nucleoia.vitormr.dev · Documento gerado em ${new Date().toLocaleString('pt-BR')}</div>
                      </body></html>`;
                    const w = window.open('', '_blank');
                    if (w) { w.document.write(html); w.document.close(); setTimeout(() => w.print(), 300); }
                  }}
                  className="px-4 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-secondary)] text-xs font-semibold cursor-pointer hover:bg-[var(--surface-hover)] transition-colors"
                >
                  🖨️ Imprimir ata
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
