/**
 * VersionDiffViewer — side-by-side (desktop) ou toggle (mobile) de
 * document_versions v_prev ↔ v_curr. Phase IP-3d.
 *
 * Spec: UX-leader audit p33b (Option B desktop + toggle mobile).
 *  - Desktop (≥768px): split 50/50 horizontal com highlight de paragrafos
 *    alterados via hash matching (nao por posicao sequencial)
 *  - Mobile (<768px): single pane com toggle v_prev/v_curr
 *  - Scroll-sync no desktop via scrollTop / (scrollHeight - clientHeight)
 *
 * Algoritmo de diff:
 *  - Parse content_html em blocos (split por '<p|h|ul|ol|li|blockquote').
 *  - Hash cada bloco (djb2 xor). Paragrafos com hash diferente = alterados
 *    (nao marca adicoes/remocoes separadamente — UI clara com "sem match"
 *    highlighted em ambber na versao current).
 */
import { useEffect, useMemo, useRef, useState } from 'react';

type VersionPayload = {
  version_id: string;
  version_label: string;
  content_html: string;
  locked_at: string | null;
};

interface Props {
  previous: VersionPayload;
  current: VersionPayload;
}

function djb2(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h) ^ s.charCodeAt(i);
  return h >>> 0;
}

function normalizeBlock(html: string): string {
  // Strip tags, collapse whitespace — for hashing equivalence
  return html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

// Split HTML into "rough blocks" — match on top-level closing tags
function splitBlocks(html: string): string[] {
  if (!html) return [];
  // Split on closing tags of block elements; keep closer attached
  const re = /(<\/(?:p|h[1-6]|ul|ol|li|blockquote|pre|hr|table)>)/gi;
  const parts: string[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  // eslint-disable-next-line no-cond-assign
  while ((m = re.exec(html)) !== null) {
    parts.push(html.slice(last, m.index + m[0].length));
    last = m.index + m[0].length;
  }
  if (last < html.length) parts.push(html.slice(last));
  return parts.map(p => p.trim()).filter(Boolean);
}

function buildHashSet(html: string): Set<number> {
  return new Set(splitBlocks(html).map(b => djb2(normalizeBlock(b))));
}

function markBlocks(html: string, otherHashes: Set<number>): string {
  const blocks = splitBlocks(html);
  return blocks.map(b => {
    const h = djb2(normalizeBlock(b));
    if (!otherHashes.has(h) && normalizeBlock(b).length > 0) {
      return `<div class="vdv-changed" data-hash="${h}">${b}</div>`;
    }
    return `<div class="vdv-unchanged" data-hash="${h}">${b}</div>`;
  }).join('');
}

// p130 T-13: extract clause anchors (§ X.Y.Z) próximos a paragraphs changed.
// Heurística: se um bloco changed contém um padrão "X.Y" no início ou tem
// header (h1-h3) com âncora antes/dentro do bloco, captura. Anchors únicos.
const CLAUSE_RE = /(\b\d+\.\d+(?:\.\d+)?(?:[a-z])?\b|§\s*\d+(?:\.\d+)*[a-z]?|Art\.?\s*\d+|Cláusula\s*[\d.]+)/i;

function extractAnchorsFromChanged(html: string): string[] {
  const blocks = splitBlocks(html);
  const anchors = new Set<string>();
  for (const b of blocks) {
    if (b.includes('vdv-changed') || b.match(/<\/(p|h[1-6]|li|blockquote)>/i)) {
      const text = b.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
      const m = text.match(CLAUSE_RE);
      if (m) anchors.add(m[1].replace(/\s+/g, ' '));
    }
  }
  return Array.from(anchors).slice(0, 12);
}

export default function VersionDiffViewer({ previous, current }: Props) {
  const prevHashes = useMemo(() => buildHashSet(previous.content_html), [previous.content_html]);
  const currHashes = useMemo(() => buildHashSet(current.content_html), [current.content_html]);
  const prevMarked = useMemo(() => markBlocks(previous.content_html, currHashes), [previous.content_html, currHashes]);
  const currMarked = useMemo(() => markBlocks(current.content_html, prevHashes), [current.content_html, prevHashes]);

  // p130 T-13: counts + clause anchors do current marked HTML para summary banner.
  const summary = useMemo(() => {
    const prevBlocks = splitBlocks(previous.content_html);
    const currBlocks = splitBlocks(current.content_html);
    const prevSet = new Set(prevBlocks.map(b => djb2(normalizeBlock(b))));
    const currSet = new Set(currBlocks.map(b => djb2(normalizeBlock(b))));
    let added = 0, removed = 0;
    for (const b of currBlocks) {
      const h = djb2(normalizeBlock(b));
      if (!prevSet.has(h) && normalizeBlock(b).length > 0) added++;
    }
    for (const b of prevBlocks) {
      const h = djb2(normalizeBlock(b));
      if (!currSet.has(h) && normalizeBlock(b).length > 0) removed++;
    }
    return {
      added,
      removed,
      total: prevBlocks.length,
      anchors: extractAnchorsFromChanged(currMarked),
    };
  }, [previous.content_html, current.content_html, currMarked]);

  const prevRef = useRef<HTMLDivElement>(null);
  const currRef = useRef<HTMLDivElement>(null);
  const syncingRef = useRef(false);
  const [mobileView, setMobileView] = useState<'prev' | 'curr'>('curr');
  const [isMobile, setIsMobile] = useState(false);
  const [changeIdx, setChangeIdx] = useState(0);

  // p130 T-13: navega para próximo/anterior bloco .vdv-changed na pane atual.
  function jumpToChange(direction: 1 | -1) {
    const target = isMobile
      ? (mobileView === 'curr' ? currRef.current : prevRef.current)
      : currRef.current; // desktop: use current pane (mais relevante)
    if (!target) return;
    const items = target.querySelectorAll('.vdv-changed');
    if (!items.length) return;
    const next = (changeIdx + direction + items.length) % items.length;
    setChangeIdx(next);
    const el = items[next] as HTMLElement;
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.classList.add('vdv-flash');
    setTimeout(() => el.classList.remove('vdv-flash'), 800);
  }

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 767px)');
    const onChange = () => setIsMobile(mq.matches);
    onChange();
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  // Scroll-sync for desktop
  useEffect(() => {
    if (isMobile) return;
    const a = prevRef.current;
    const b = currRef.current;
    if (!a || !b) return;

    function sync(source: HTMLDivElement, target: HTMLDivElement) {
      if (syncingRef.current) return;
      syncingRef.current = true;
      const ratio = source.scrollTop / Math.max(1, source.scrollHeight - source.clientHeight);
      target.scrollTop = ratio * (target.scrollHeight - target.clientHeight);
      requestAnimationFrame(() => { syncingRef.current = false; });
    }

    function onAScroll() { sync(a!, b!); }
    function onBScroll() { sync(b!, a!); }
    a.addEventListener('scroll', onAScroll);
    b.addEventListener('scroll', onBScroll);
    return () => {
      a.removeEventListener('scroll', onAScroll);
      b.removeEventListener('scroll', onBScroll);
    };
  }, [isMobile, prevMarked, currMarked]);

  const paneStyle = 'max-h-[60vh] overflow-y-auto prose prose-sm max-w-none px-4 py-3 text-[var(--text-primary)] bg-[var(--surface-base)] border border-[var(--border-default)] rounded-lg';

  // p130 T-13: summary banner reutilizado em mobile + desktop.
  const summaryBanner = (
    <div className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 flex items-center gap-3 flex-wrap">
      <div className="flex items-center gap-2 text-[12px] text-amber-900 flex-wrap">
        <span><strong>{summary.added}</strong> adicionado(s)</span>
        <span className="text-amber-300">·</span>
        <span><strong>{summary.removed}</strong> removido(s)</span>
        <span className="text-amber-300">·</span>
        <span className="text-amber-700">{summary.total} parágrafo(s) na versão anterior</span>
      </div>
      {summary.anchors.length > 0 && (
        <div className="flex items-center gap-1.5 flex-wrap text-[10px]">
          <span className="text-amber-700">Cláusulas tocadas:</span>
          {summary.anchors.map(a => (
            <span key={a} className="px-1.5 py-0.5 rounded-full border border-amber-300 bg-white font-mono text-amber-900">{a}</span>
          ))}
        </div>
      )}
      {(summary.added + summary.removed) > 0 && (
        <div className="flex items-center gap-1 ml-auto">
          <button type="button" onClick={() => jumpToChange(-1)}
            className="rounded border border-amber-400 bg-white text-[11px] font-semibold px-2 py-0.5 text-amber-900 cursor-pointer hover:bg-amber-100"
            title="Alteração anterior">↑ anterior</button>
          <button type="button" onClick={() => jumpToChange(1)}
            className="rounded border border-amber-400 bg-white text-[11px] font-semibold px-2 py-0.5 text-amber-900 cursor-pointer hover:bg-amber-100"
            title="Próxima alteração">próxima ↓</button>
        </div>
      )}
    </div>
  );

  if (isMobile) {
    return (
      <div className="space-y-2">
        <div className="flex items-center gap-2">
          <div role="tablist" className="inline-flex rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] p-0.5">
            <button
              type="button"
              role="tab"
              aria-selected={mobileView === 'prev'}
              onClick={() => setMobileView('prev')}
              className={`text-[11px] font-bold px-3 py-1 rounded-md border-0 cursor-pointer ${mobileView === 'prev' ? 'bg-navy text-white' : 'bg-transparent text-[var(--text-secondary)]'}`}
            >
              Anterior ({previous.version_label})
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mobileView === 'curr'}
              onClick={() => setMobileView('curr')}
              className={`text-[11px] font-bold px-3 py-1 rounded-md border-0 cursor-pointer ${mobileView === 'curr' ? 'bg-navy text-white' : 'bg-transparent text-[var(--text-secondary)]'}`}
            >
              Atual ({current.version_label})
            </button>
          </div>
          <span className="text-[10px] text-[var(--text-muted)] italic">
            Parágrafos alterados ficam destacados
          </span>
        </div>
        {summaryBanner}
        <DiffStyles />
        <div
          ref={mobileView === 'prev' ? prevRef : currRef}
          className={paneStyle}
          dangerouslySetInnerHTML={{ __html: mobileView === 'prev' ? prevMarked : currMarked }}
          aria-label={mobileView === 'prev' ? `Versão ${previous.version_label}` : `Versão ${current.version_label}`}
        />
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {summaryBanner}
      <div className="text-[11px] text-[var(--text-muted)] italic">
        Parágrafos em destaque âmbar não têm correspondência hash na outra versão (adicionados, removidos ou alterados).
      </div>
      <DiffStyles />
      <div className="grid grid-cols-2 gap-3">
        <div>
          <h4 className="text-[11px] font-bold text-[var(--text-secondary)] mb-1">
            {previous.version_label} <span className="text-[var(--text-muted)] font-normal">(anterior)</span>
          </h4>
          <div
            ref={prevRef}
            className={paneStyle}
            dangerouslySetInnerHTML={{ __html: prevMarked }}
            aria-label={`Versão anterior ${previous.version_label}`}
          />
        </div>
        <div>
          <h4 className="text-[11px] font-bold text-[var(--text-secondary)] mb-1">
            {current.version_label} <span className="text-[var(--text-muted)] font-normal">(atual)</span>
          </h4>
          <div
            ref={currRef}
            className={paneStyle}
            dangerouslySetInnerHTML={{ __html: currMarked }}
            aria-label={`Versão atual ${current.version_label}`}
          />
        </div>
      </div>
    </div>
  );
}

function DiffStyles() {
  return (
    <style>{`
      .vdv-changed { background: #fff8e1; border-left: 3px solid #ffc107; padding-left: 8px; margin-left: -11px; }
      .vdv-unchanged { opacity: 0.92; }
      .vdv-flash { background: #fde68a !important; transition: background 0.5s ease-out; }
    `}</style>
  );
}
