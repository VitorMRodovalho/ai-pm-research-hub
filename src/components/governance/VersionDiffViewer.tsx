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

export default function VersionDiffViewer({ previous, current }: Props) {
  const prevHashes = useMemo(() => buildHashSet(previous.content_html), [previous.content_html]);
  const currHashes = useMemo(() => buildHashSet(current.content_html), [current.content_html]);
  const prevMarked = useMemo(() => markBlocks(previous.content_html, currHashes), [previous.content_html, currHashes]);
  const currMarked = useMemo(() => markBlocks(current.content_html, prevHashes), [current.content_html, prevHashes]);

  const prevRef = useRef<HTMLDivElement>(null);
  const currRef = useRef<HTMLDivElement>(null);
  const syncingRef = useRef(false);
  const [mobileView, setMobileView] = useState<'prev' | 'curr'>('curr');
  const [isMobile, setIsMobile] = useState(false);

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
            Paragrafos alterados ficam destacados
          </span>
        </div>
        <DiffStyles />
        <div
          className={paneStyle}
          dangerouslySetInnerHTML={{ __html: mobileView === 'prev' ? prevMarked : currMarked }}
          aria-label={mobileView === 'prev' ? `Versao ${previous.version_label}` : `Versao ${current.version_label}`}
        />
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="text-[11px] text-[var(--text-muted)] italic">
        Paragrafos em destaque ambar nao tem correspondencia hash na outra versao (adicionados, removidos ou alterados).
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
            aria-label={`Versao anterior ${previous.version_label}`}
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
            aria-label={`Versao atual ${current.version_label}`}
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
    `}</style>
  );
}
