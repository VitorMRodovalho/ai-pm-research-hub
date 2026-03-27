import { useState, useEffect, useRef, useCallback } from 'react';
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
  page_start: number | null;
  page_end: number | null;
}

interface Props {
  lang?: string;
}

function detectLang(): string {
  if (typeof window === 'undefined') return 'pt-BR';
  const params = new URLSearchParams(window.location.search);
  return params.get('lang') || (window.location.pathname.startsWith('/en') ? 'en-US' : window.location.pathname.startsWith('/es') ? 'es-LATAM' : 'pt-BR');
}

function getTitle(s: Section, lang: string): string {
  if (lang === 'en-US' && s.title_en) return s.title_en;
  return s.title_pt;
}

function getContent(s: Section, lang: string): string {
  if (lang === 'en-US' && s.content_en) return s.content_en;
  return s.content_pt || '';
}

function sectionAnchor(s: Section): string {
  return `sec-${s.section_number.replace(/\./g, '-')}`;
}

export default function ManualDocumentViewer({ lang: langProp }: Props) {
  const lang = langProp || detectLang();
  const [sections, setSections] = useState<Section[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeSection, setActiveSection] = useState<string>('');
  const [tocOpen, setTocOpen] = useState(false);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const sectionRefs = useRef<Map<string, HTMLElement>>(new Map());

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  // Load sections
  useEffect(() => {
    let cancelled = false;
    let retries = 0;
    async function load() {
      const sb = getSb();
      if (!sb && retries < 20) { retries++; setTimeout(load, 300); return; }
      if (!sb) { setLoading(false); return; }
      try {
        const { data, error } = await sb.rpc('get_manual_sections', { p_version: 'R2' });
        if (error) throw error;
        if (!cancelled) setSections(Array.isArray(data) ? data : []);
      } catch (e) { console.warn('Manual sections load failed:', e); }
      finally { if (!cancelled) setLoading(false); }
    }
    load();
    return () => { cancelled = true; };
  }, [getSb]);

  // Scroll-spy with IntersectionObserver
  useEffect(() => {
    if (!sections.length) return;
    observerRef.current?.disconnect();

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter(e => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible.length > 0) {
          setActiveSection(visible[0].target.id);
        }
      },
      { rootMargin: '-80px 0px -60% 0px', threshold: 0 }
    );

    observerRef.current = observer;
    sectionRefs.current.forEach((el) => observer.observe(el));

    return () => observer.disconnect();
  }, [sections]);

  const registerRef = useCallback((id: string, el: HTMLElement | null) => {
    if (el) sectionRefs.current.set(id, el);
    else sectionRefs.current.delete(id);
  }, []);

  const scrollTo = (id: string) => {
    const el = document.getElementById(id);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      setTocOpen(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="animate-spin h-6 w-6 border-2 border-[var(--accent)] border-t-transparent rounded-full" />
      </div>
    );
  }

  if (!sections.length) {
    return <p className="text-center py-12 text-[var(--text-muted)]">Nenhuma secção do manual encontrada.</p>;
  }

  // Build hierarchy: top-level sections and their children
  const topLevel = sections.filter(s => !s.parent_section_id);
  const children = (parentId: string) => sections.filter(s => s.parent_section_id === parentId);

  return (
    <div className="flex gap-6 relative">
      {/* TOC Sidebar — desktop */}
      <nav className="hidden lg:block w-56 shrink-0 sticky top-20 self-start max-h-[calc(100vh-6rem)] overflow-y-auto pr-2 print:hidden">
        <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2">Índice</div>
        <TOCList sections={topLevel} childrenFn={children} activeSection={activeSection} lang={lang} onClick={scrollTo} />
      </nav>

      {/* TOC Mobile toggle */}
      <button
        onClick={() => setTocOpen(!tocOpen)}
        className="lg:hidden fixed bottom-4 right-4 z-50 w-12 h-12 rounded-full bg-navy text-white shadow-lg flex items-center justify-center border-0 cursor-pointer print:hidden"
        aria-label="Índice"
      >
        ☰
      </button>

      {/* TOC Mobile drawer */}
      {tocOpen && (
        <div className="lg:hidden fixed inset-0 z-[400] bg-black/50 print:hidden" onClick={() => setTocOpen(false)}>
          <nav className="absolute right-0 top-0 bottom-0 w-72 bg-[var(--surface-card)] p-4 overflow-y-auto shadow-xl" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-bold uppercase tracking-wider text-[var(--text-muted)]">Índice</span>
              <button onClick={() => setTocOpen(false)} className="text-[var(--text-muted)] text-lg cursor-pointer border-0 bg-transparent">✕</button>
            </div>
            <TOCList sections={topLevel} childrenFn={children} activeSection={activeSection} lang={lang} onClick={scrollTo} />
          </nav>
        </div>
      )}

      {/* Manual content */}
      <article className="flex-1 min-w-0">
        {/* Document header */}
        <div className="text-center mb-8 pb-6 border-b border-[var(--border-default)]">
          <div className="text-[10px] font-bold uppercase tracking-[.2em] text-[var(--text-muted)] mb-1">
            Núcleo de Estudos e Pesquisa em IA & Gerenciamento de Projetos
          </div>
          <h1 className="text-2xl font-extrabold text-[var(--text-primary)]">Manual de Governança e Operações</h1>
          <div className="text-sm text-[var(--text-secondary)] mt-1">Versão R2 · DocuSign B2AFB185</div>
        </div>

        {/* Sections */}
        <div className="space-y-8">
          {topLevel.map(section => (
            <SectionBlock
              key={section.id}
              section={section}
              children={children(section.id)}
              lang={lang}
              registerRef={registerRef}
            />
          ))}
        </div>
      </article>
    </div>
  );
}

function TOCList({
  sections, childrenFn, activeSection, lang, onClick,
}: {
  sections: Section[];
  childrenFn: (id: string) => Section[];
  activeSection: string;
  lang: string;
  onClick: (id: string) => void;
}) {
  return (
    <ul className="space-y-0.5 text-[12px]">
      {sections.map(s => {
        const anchor = sectionAnchor(s);
        const isActive = activeSection === anchor;
        const kids = childrenFn(s.id);
        return (
          <li key={s.id}>
            <button
              onClick={() => onClick(anchor)}
              className={`w-full text-left px-2 py-1 rounded cursor-pointer border-0 bg-transparent transition-colors leading-snug ${
                isActive
                  ? 'text-navy font-bold bg-blue-50 dark:bg-blue-900/20'
                  : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)]'
              }`}
            >
              §{s.section_number} {getTitle(s, lang)}
            </button>
            {kids.length > 0 && (
              <ul className="pl-3 space-y-0.5 mt-0.5">
                {kids.map(k => {
                  const kAnchor = sectionAnchor(k);
                  const kActive = activeSection === kAnchor;
                  return (
                    <li key={k.id}>
                      <button
                        onClick={() => onClick(kAnchor)}
                        className={`w-full text-left px-2 py-0.5 rounded cursor-pointer border-0 bg-transparent transition-colors leading-snug text-[11px] ${
                          kActive
                            ? 'text-navy font-semibold bg-blue-50 dark:bg-blue-900/20'
                            : 'text-[var(--text-muted)] hover:text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
                        }`}
                      >
                        §{k.section_number}
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

function SectionBlock({
  section, children, lang, registerRef,
}: {
  section: Section;
  children: Section[];
  lang: string;
  registerRef: (id: string, el: HTMLElement | null) => void;
}) {
  const anchor = sectionAnchor(section);
  const content = getContent(section, lang);
  const title = getTitle(section, lang);

  return (
    <section
      id={anchor}
      ref={(el) => registerRef(anchor, el)}
      className="scroll-mt-20"
    >
      <h2 className="text-lg font-bold text-[var(--text-primary)] mb-3 flex items-center gap-2">
        <span className="text-[var(--text-muted)] text-sm font-mono">§{section.section_number}</span>
        {title}
      </h2>

      {content && (
        <div className="prose prose-sm prose-slate dark:prose-invert max-w-none text-[var(--text-secondary)]">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
        </div>
      )}

      {/* Sub-sections */}
      {children.length > 0 && (
        <div className="mt-4 space-y-5 pl-4 border-l-2 border-[var(--border-subtle)]">
          {children.map(child => {
            const cAnchor = sectionAnchor(child);
            const cContent = getContent(child, lang);
            const cTitle = getTitle(child, lang);
            return (
              <div
                key={child.id}
                id={cAnchor}
                ref={(el) => registerRef(cAnchor, el)}
                className="scroll-mt-20"
              >
                <h3 className="text-base font-semibold text-[var(--text-primary)] mb-2 flex items-center gap-2">
                  <span className="text-[var(--text-muted)] text-xs font-mono">§{child.section_number}</span>
                  {cTitle}
                </h3>
                {cContent && (
                  <div className="prose prose-sm prose-slate dark:prose-invert max-w-none text-[var(--text-secondary)]">
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
