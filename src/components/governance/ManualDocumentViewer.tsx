import { useState, useEffect, useRef, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface Section {
  id: string;
  section_number: string;
  title_pt: string;
  title_en: string | null;
  content_pt: string | null;
  content_en: string | null;
  manual_version: string;
  parent_section_id: string | null;
  sort_order: number;
}

// A merged section: R2 base with optional R3 overlay
interface MergedSection {
  r2: Section | null;
  r3: Section | null;
  section_number: string;
  changeType: 'unchanged' | 'updated' | 'new' | 'pending';
  children: MergedSection[];
}

interface Props { lang?: string; }

function detectLang(): string {
  if (typeof window === 'undefined') return 'pt-BR';
  const p = new URLSearchParams(window.location.search);
  return p.get('lang') || (window.location.pathname.startsWith('/en') ? 'en-US' : window.location.pathname.startsWith('/es') ? 'es-LATAM' : 'pt-BR');
}

function getTitle(s: Section | null, lang: string): string {
  if (!s) return '';
  if (lang === 'en-US' && s.title_en) return s.title_en;
  return s.title_pt;
}

function getContent(s: Section | null, lang: string): string {
  if (!s) return '';
  if (lang === 'en-US' && s.content_en) return s.content_en;
  return s.content_pt || '';
}

function anchor(sn: string): string {
  return `sec-${sn.replace(/\./g, '-')}`;
}

// Pending proposals for §3
const PENDING_SECTION_3 = {
  count: 7,
  crRange: 'CR-036 a CR-042',
  label: 'propostas pendentes de aprovação',
};

export default function ManualDocumentViewer({ lang: langProp }: Props) {
  const t = usePageI18n();
  const lang = langProp || detectLang();
  const [r2Sections, setR2] = useState<Section[]>([]);
  const [r3Sections, setR3] = useState<Section[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeSection, setActiveSection] = useState('');
  const [tocOpen, setTocOpen] = useState(false);
  const [viewMode, setViewMode] = useState<'r2' | 'preview'>('preview'); // default: show preview if R3 exists
  const observerRef = useRef<IntersectionObserver | null>(null);
  const sectionRefs = useRef<Map<string, HTMLElement>>(new Map());

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  // Admin badge is now in the parent GovernancePage header

  useEffect(() => {
    let cancelled = false;
    let retries = 0;
    async function load() {
      const sb = getSb();
      if (!sb && retries < 20) { retries++; setTimeout(load, 300); return; }
      if (!sb) { setLoading(false); return; }
      try {
        const [res2, res3] = await Promise.all([
          sb.rpc('get_manual_sections', { p_version: 'R2' }),
          sb.rpc('get_manual_sections', { p_version: 'R3' }),
        ]);
        if (!cancelled) {
          setR2(Array.isArray(res2.data) ? res2.data : []);
          setR3(Array.isArray(res3.data) ? res3.data : []);
        }
      } catch (e) { console.warn('Manual load failed:', e); }
      finally { if (!cancelled) setLoading(false); }
    }
    load();
    return () => { cancelled = true; };
  }, [getSb]);

  // Merge R2 + R3 into unified list
  const merged = mergeSections(r2Sections, r3Sections);

  // Translate badge labels
  CHANGE_STYLES.new.badge = t('manual.badgeNew', 'NEW');
  CHANGE_STYLES.updated.badge = t('manual.badgeUpdated', 'UPDATED');
  CHANGE_STYLES.pending.badge = t('manual.badgePending', 'PENDING');

  // R2-only view helpers
  const r2TopLevel = r2Sections.filter(s => !s.parent_section_id);
  const r2Children = (parentId: string) => r2Sections.filter(s => s.parent_section_id === parentId);

  // Scroll-spy
  useEffect(() => {
    if (!merged.length) return;
    observerRef.current?.disconnect();
    const observer = new IntersectionObserver(
      (entries) => {
        const vis = entries.filter(e => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (vis.length) setActiveSection(vis[0].target.id);
      },
      { rootMargin: '-80px 0px -60% 0px', threshold: 0 }
    );
    observerRef.current = observer;
    sectionRefs.current.forEach(el => observer.observe(el));
    return () => observer.disconnect();
  }, [merged]);

  const regRef = useCallback((id: string, el: HTMLElement | null) => {
    if (el) sectionRefs.current.set(id, el);
    else sectionRefs.current.delete(id);
  }, []);

  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    setTocOpen(false);
  };

  if (loading) return <div className="flex items-center justify-center py-20"><div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" /></div>;
  if (!merged.length) return <p className="text-center py-12 text-[var(--text-muted)]">{t('manual.noSections', 'No sections found.')}</p>;

  const hasR3 = r3Sections.length > 0;
  const newCount = merged.filter(m => m.changeType === 'new' || m.children.some(c => c.changeType === 'new')).length;
  const updCount = merged.filter(m => m.changeType === 'updated').length;

  return (
    <div className="flex gap-6 relative">
      {/* TOC Desktop */}
      <nav className="hidden lg:block w-56 shrink-0 sticky top-20 self-start max-h-[calc(100vh-6rem)] overflow-y-auto pr-2 print:hidden">
        <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2">Índice</div>
        <TOCList merged={merged} activeSection={activeSection} lang={lang} onClick={scrollTo} />
      </nav>

      {/* TOC Mobile */}
      <button onClick={() => setTocOpen(!tocOpen)} className="lg:hidden fixed bottom-4 right-4 z-50 w-12 h-12 rounded-full bg-navy text-white shadow-lg flex items-center justify-center border-0 cursor-pointer print:hidden" aria-label="Índice">☰</button>
      {tocOpen && (
        <div className="lg:hidden fixed inset-0 z-[400] bg-black/50 print:hidden" onClick={() => setTocOpen(false)}>
          <nav className="absolute right-0 top-0 bottom-0 w-72 bg-[var(--surface-card)] p-4 overflow-y-auto shadow-xl" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-bold uppercase tracking-wider text-[var(--text-muted)]">Índice</span>
              <button onClick={() => setTocOpen(false)} className="text-[var(--text-muted)] text-lg cursor-pointer border-0 bg-transparent">✕</button>
            </div>
            <TOCList merged={merged} activeSection={activeSection} lang={lang} onClick={scrollTo} />
          </nav>
        </div>
      )}

      {/* Document */}
      <article className="flex-1 min-w-0">
        {/* Header */}
        <div className="text-center mb-6 pb-5 border-b border-[var(--border-default)]">
          <div className="text-[10px] font-bold uppercase tracking-[.2em] text-[var(--text-muted)] mb-1">{t('manual.institution', 'AI & PM Study and Research Hub')}</div>
          <h1 className="text-2xl font-extrabold text-[var(--text-primary)]">{t('manual.title', 'Governance and Operations Manual')}</h1>

          {/* Version toggle */}
          {hasR3 && (
            <div className="flex justify-center gap-2 mt-3 print:hidden">
              <button onClick={() => setViewMode('r2')}
                className={`px-4 py-1.5 rounded-full text-[12px] font-semibold cursor-pointer border-2 transition-all ${
                  viewMode === 'r2' ? 'border-navy bg-navy text-white' : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
                }`}>
                {t('manual.r2Label', 'R2 (Approved)')}
              </button>
              <button onClick={() => setViewMode('preview')}
                className={`px-4 py-1.5 rounded-full text-[12px] font-semibold cursor-pointer border-2 transition-all ${
                  viewMode === 'preview' ? 'border-amber-500 bg-amber-500 text-white' : 'border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)]'
                }`}>
                {t('manual.r3Label', 'R3 Simulation')}
              </button>
            </div>
          )}

          {/* Version info */}
          <div className="text-sm text-[var(--text-secondary)] mt-2">
            {viewMode === 'r2' ? (
              <span>Versão R2 · DocuSign B2AFB185 · <strong className="text-emerald-600 dark:text-emerald-400">Aprovado 22/Set/2025</strong></span>
            ) : hasR3 ? (
              <span className="text-amber-700 dark:text-amber-400 font-semibold">{t('manual.r3Warning', '⚠ SIMULATION — Preview of the next revision. This document is NOT approved.')}</span>
            ) : (
              <span>Versão R2 · DocuSign B2AFB185</span>
            )}
          </div>

          {/* Preview stats + legend */}
          {viewMode === 'preview' && hasR3 && (
            <div className="flex flex-wrap justify-center gap-2 mt-3 text-[11px]">
              <span className="px-2 py-0.5 rounded-full bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400 font-semibold">{newCount} {t('manual.newSections', 'new sections')}</span>
              <span className="px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400 font-semibold">{updCount} {t('manual.updatedSections', 'updated')}</span>
              <span className="px-2 py-0.5 rounded-full bg-gray-100 text-gray-600 dark:bg-gray-800/50 dark:text-gray-400 font-semibold">{merged.length - newCount - updCount} {t('manual.unchangedSections', 'unchanged')}</span>
            </div>
          )}

          {/* Actions: PDF export + R2 download */}
          <div className="flex justify-center gap-2 mt-3 print:hidden">
            <button onClick={() => window.print()}
              className="px-3 py-1.5 rounded-lg bg-[var(--surface-card)] border border-[var(--border-default)] text-[11px] font-semibold text-[var(--text-secondary)] cursor-pointer hover:bg-[var(--surface-hover)]">
              📄 {viewMode === 'r2' ? t('manual.exportR2', 'Export R2 PDF') : t('manual.exportSim', 'Export Simulation PDF')}
            </button>
          </div>
        </div>

        {/* Sections — render based on viewMode */}
        <div className="space-y-8">
          {viewMode === 'r2' ? (
            /* R2 ONLY — pure original document, no diff markers */
            r2TopLevel.map(section => (
              <R2SectionBlock key={section.id} section={section} children={r2Children(section.id)} lang={lang} regRef={regRef} />
            ))
          ) : (
            /* PREVIEW — merged R2+R3 with diff markers */
            merged.map(m => (
              <MergedSectionBlock key={m.section_number} merged={m} lang={lang} regRef={regRef} />
            ))
          )}
        </div>
      </article>
    </div>
  );
}

// ── Merge logic ──

function mergeSections(r2: Section[], r3: Section[]): MergedSection[] {
  const r3Map = new Map(r3.map(s => [s.section_number, s]));
  const r2Map = new Map(r2.map(s => [s.section_number, s]));
  const allNumbers = new Set([...r2.map(s => s.section_number), ...r3.map(s => s.section_number)]);

  // Separate top-level from children
  const topR2 = r2.filter(s => !s.parent_section_id);
  const topR3 = r3.filter(s => !s.parent_section_id);
  const topNumbers = new Set([...topR2.map(s => s.section_number), ...topR3.map(s => s.section_number)]);

  const childrenOf = (parentNum: string): MergedSection[] => {
    const childNums = [...allNumbers].filter(n => n.startsWith(parentNum + '.') && n.split('.').length === parentNum.split('.').length + 1);
    return childNums.sort().map(cn => {
      const cr2 = r2.find(s => s.section_number === cn);
      const cr3 = r3Map.get(cn);
      const ct: MergedSection['changeType'] = cr3 && !cr2 ? 'new' : cr3 && cr2 ? 'updated' : 'unchanged';
      return { r2: cr2 || null, r3: cr3 || null, section_number: cn, changeType: ct, children: [] };
    });
  };

  const sorted = [...topNumbers].sort((a, b) => {
    const aSort = topR2.find(s => s.section_number === a)?.sort_order ?? topR3.find(s => s.section_number === a)?.sort_order ?? 99;
    const bSort = topR2.find(s => s.section_number === b)?.sort_order ?? topR3.find(s => s.section_number === b)?.sort_order ?? 99;
    return aSort - bSort;
  });

  return sorted.map(sn => {
    const sr2 = r2Map.get(sn) ?? null;
    const sr3 = r3Map.get(sn) ?? null;
    let ct: MergedSection['changeType'] = 'unchanged';
    if (sr3 && !sr2) ct = 'new';
    else if (sr3 && sr2) ct = 'updated';
    else if (sn === '3' && !sr3) ct = 'pending'; // §3 has no R3 → pending proposals
    return { r2: sr2, r3: sr3, section_number: sn, changeType: ct, children: childrenOf(sn) };
  });
}

// ── TOC ──

function TOCList({ merged, activeSection, lang, onClick }: { merged: MergedSection[]; activeSection: string; lang: string; onClick: (id: string) => void }) {
  const badgeFor = (ct: MergedSection['changeType']) => {
    if (ct === 'new') return <span className="ml-1 w-1.5 h-1.5 rounded-full bg-blue-500 inline-block" />;
    if (ct === 'updated') return <span className="ml-1 w-1.5 h-1.5 rounded-full bg-amber-500 inline-block" />;
    if (ct === 'pending') return <span className="ml-1 w-1.5 h-1.5 rounded-full bg-yellow-500 inline-block" />;
    return null;
  };

  return (
    <ul className="space-y-0.5 text-[12px]">
      {merged.map(m => {
        const a = anchor(m.section_number);
        const s = m.r3 || m.r2;
        const active = activeSection === a;
        return (
          <li key={m.section_number}>
            <button onClick={() => onClick(a)} className={`w-full text-left px-2 py-1 rounded cursor-pointer border-0 bg-transparent transition-colors leading-snug flex items-center ${active ? 'text-navy font-bold bg-blue-50 dark:bg-blue-900/20' : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)]'}`}>
              <span>§{m.section_number} {s ? getTitle(s, lang) : ''}</span>{badgeFor(m.changeType)}
            </button>
            {m.children.length > 0 && (
              <ul className="pl-3 space-y-0.5 mt-0.5">
                {m.children.map(c => {
                  const ca = anchor(c.section_number);
                  const cs = c.r3 || c.r2;
                  return (
                    <li key={c.section_number}>
                      <button onClick={() => onClick(ca)} className={`w-full text-left px-2 py-0.5 rounded cursor-pointer border-0 bg-transparent transition-colors leading-snug text-[11px] flex items-center ${activeSection === ca ? 'text-navy font-semibold bg-blue-50 dark:bg-blue-900/20' : 'text-[var(--text-muted)] hover:text-[var(--text-secondary)]'}`}>
                        <span>§{c.section_number}</span>{badgeFor(c.changeType)}
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </li>
        );
      })}
    </ul>
  );
}

// ── Section rendering ──

const CHANGE_STYLES: Record<string, { border: string; bg: string; badge: string; badgeCls: string }> = {
  new: { border: 'border-l-4 border-blue-400', bg: 'bg-blue-50/50 dark:bg-blue-900/10', badge: '', badgeCls: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400' },
  updated: { border: 'border-l-4 border-amber-400', bg: 'bg-amber-50/50 dark:bg-amber-900/10', badge: '', badgeCls: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400' },
  pending: { border: 'border-l-4 border-yellow-400', bg: 'bg-yellow-50/50 dark:bg-yellow-900/10', badge: '', badgeCls: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400' },
  unchanged: { border: '', bg: '', badge: '', badgeCls: '' },
};

function MergedSectionBlock({ merged: m, lang, regRef }: { merged: MergedSection; lang: string; regRef: (id: string, el: HTMLElement | null) => void }) {
  const a = anchor(m.section_number);
  const style = CHANGE_STYLES[m.changeType] || CHANGE_STYLES.unchanged;
  // Use R3 content when available, otherwise R2
  const displaySection = m.r3 || m.r2;
  const title = displaySection ? getTitle(displaySection, lang) : '';
  const content = displaySection ? getContent(displaySection, lang) : '';

  return (
    <section id={a} ref={el => regRef(a, el)} className={`scroll-mt-20 rounded-lg p-4 ${style.border} ${style.bg}`}>
      <h2 className="text-lg font-bold text-[var(--text-primary)] mb-3 flex items-center gap-2 flex-wrap">
        <span className="text-[var(--text-muted)] text-sm font-mono">§{m.section_number}</span>
        {title}
        {style.badge && <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${style.badgeCls}`}>{style.badge}</span>}
      </h2>

      {/* §3 pending banner */}
      {m.changeType === 'pending' && (
        <div className="mb-4 p-3 rounded-lg bg-yellow-100 dark:bg-yellow-900/20 border border-yellow-300 dark:border-yellow-800">
          <div className="text-sm font-semibold text-yellow-800 dark:text-yellow-300">
            ⏳ {PENDING_SECTION_3.count} {PENDING_SECTION_3.label}
          </div>
          <div className="text-xs text-yellow-700 dark:text-yellow-400 mt-1">{PENDING_SECTION_3.crRange}</div>
        </div>
      )}

      {content && (
        <div className="prose prose-sm prose-slate dark:prose-invert max-w-none text-[var(--text-secondary)] overflow-x-auto">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
        </div>
      )}

      {/* Children */}
      {m.children.length > 0 && (
        <div className="mt-4 space-y-5 pl-4">
          {m.children.map(child => {
            const ca = anchor(child.section_number);
            const cs = CHANGE_STYLES[child.changeType] || CHANGE_STYLES.unchanged;
            const cSec = child.r3 || child.r2;
            const cTitle = cSec ? getTitle(cSec, lang) : '';
            const cContent = cSec ? getContent(cSec, lang) : '';
            return (
              <div key={child.section_number} id={ca} ref={el => regRef(ca, el)} className={`scroll-mt-20 rounded-lg p-3 ${cs.border} ${cs.bg}`}>
                <h3 className="text-base font-semibold text-[var(--text-primary)] mb-2 flex items-center gap-2 flex-wrap">
                  <span className="text-[var(--text-muted)] text-xs font-mono">§{child.section_number}</span>
                  {cTitle}
                  {cs.badge && <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${cs.badgeCls}`}>{cs.badge}</span>}
                </h3>
                {cContent && (
                  <div className="prose prose-sm prose-slate dark:prose-invert max-w-none text-[var(--text-secondary)] overflow-x-auto">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{cContent}</ReactMarkdown>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}

// ── R2-only section (no diff markers, clean document) ──

function R2SectionBlock({ section, children, lang, regRef }: {
  section: Section; children: Section[]; lang: string;
  regRef: (id: string, el: HTMLElement | null) => void;
}) {
  const a = anchor(section.section_number);
  const content = getContent(section, lang);
  const title = getTitle(section, lang);

  return (
    <section id={a} ref={el => regRef(a, el)} className="scroll-mt-20">
      <h2 className="text-lg font-bold text-[var(--text-primary)] mb-3 flex items-center gap-2">
        <span className="text-[var(--text-muted)] text-sm font-mono">§{section.section_number}</span>
        {title}
      </h2>
      {content && (
        <div className="prose prose-sm prose-slate dark:prose-invert max-w-none text-[var(--text-secondary)] overflow-x-auto">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
        </div>
      )}
      {children.length > 0 && (
        <div className="mt-4 space-y-5 pl-4 border-l-2 border-[var(--border-subtle)]">
          {children.map(child => {
            const ca = anchor(child.section_number);
            return (
              <div key={child.id} id={ca} ref={el => regRef(ca, el)} className="scroll-mt-20">
                <h3 className="text-base font-semibold text-[var(--text-primary)] mb-2 flex items-center gap-2">
                  <span className="text-[var(--text-muted)] text-xs font-mono">§{child.section_number}</span>
                  {getTitle(child, lang)}
                </h3>
                {getContent(child, lang) && (
                  <div className="prose prose-sm prose-slate dark:prose-invert max-w-none text-[var(--text-secondary)] overflow-x-auto">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{getContent(child, lang)}</ReactMarkdown>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
