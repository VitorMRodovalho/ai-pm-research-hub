/**
 * ChainDocxExportIsland — IP-4 Chunk 3 (p128 D2 · p156 lib swap)
 *
 * Gera DOCX do conteúdo da versão lacrada da cadeia, para envio offline a
 * curadores externos sem conta na plataforma (e.g., advogados externos).
 * Usa @turbodocx/html-to-docx (OOXML real, sem altChunk MHT trick — a lib
 * anterior html-docx-js-typescript embeda HTML via <w:altChunk/> + afchunk.mht,
 * que LibreOffice nunca suportou e Word recente rejeita por security policy).
 * Reusa get_chain_for_pdf RPC que já retorna version.content_html.
 *
 * NOTA: este export inclui apenas o CONTEÚDO da versão (sem assinaturas /
 * audit trail). Para envio formal pós-ratificação, use o PDF Oficial.
 *
 * Sucessor planejado: T-15 — external_reviewer role permitindo acesso direto
 * sem export offline (boa prática a futuro).
 */
import { useCallback, useEffect, useState } from 'react';
// @turbodocx/html-to-docx ships 3 builds (UMD main / ESM module / browser IIFE)
// and NONE work via direct `import`:
//   - main (UMD): imports node built-ins (fs, http, …) — fails Rollup resolve
//   - module (ESM): same node imports — fails Rollup resolve
//   - browser: IIFE assigning `var HTMLToDOCX = …()` to global, never calls
//     module.exports — Vite's CJS interop returns `{}` and `d5(m5)` → undefined
//     (the "g5 is not a function" runtime crash shipped in 55265f7).
// Fix: load the browser bundle as a `<script>` tag via Vite's `?url` asset
// import. That's what the IIFE was designed for — sets `window.HTMLToDOCX`
// on load. We bypass bundler interop entirely.
import htmlToDocxScriptUrl from '@turbodocx/html-to-docx/dist/html-to-docx.browser.js?url';

type HTMLtoDOCXFn = (
  html: string,
  headerHtml: string | null,
  options: Record<string, unknown>,
  footerHtml?: string | null,
) => Promise<Blob | ArrayBuffer>;

let htmlToDocxPromise: Promise<HTMLtoDOCXFn> | null = null;
function loadHTMLtoDOCX(): Promise<HTMLtoDOCXFn> {
  if (typeof window === 'undefined') return Promise.reject(new Error('Sem window'));
  const existing = (window as any).HTMLToDOCX as HTMLtoDOCXFn | undefined;
  if (existing) return Promise.resolve(existing);
  if (htmlToDocxPromise) return htmlToDocxPromise;
  htmlToDocxPromise = new Promise<HTMLtoDOCXFn>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = htmlToDocxScriptUrl;
    script.async = true;
    script.onload = () => {
      const fn = (window as any).HTMLToDOCX as HTMLtoDOCXFn | undefined;
      if (typeof fn === 'function') resolve(fn);
      else reject(new Error('HTMLToDOCX global indisponível após load do script'));
    };
    script.onerror = () => reject(new Error('Falha ao carregar html-to-docx browser bundle'));
    document.head.appendChild(script);
  });
  return htmlToDocxPromise;
}

type ChainData = {
  chain_id: string;
  chain_status: string;
  document: { title: string; doc_type: string };
  version: {
    id: string;
    label: string;
    content_html: string;
    locked_at: string;
    notes?: string | null;
  };
  submitter?: { name?: string };
  opened_at: string;
};

export default function ChainDocxExportIsland({ chainId }: { chainId: string }) {
  const [data, setData] = useState<ChainData | null>(null);
  const [error, setError] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      let sb = getSb();
      if (!sb) {
        const deadline = Date.now() + 4000;
        while (!sb && Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, 250));
          sb = getSb();
        }
      }
      if (!sb) {
        setError('Cliente Supabase indisponível. Recarregue a página.');
        setLoading(false);
        return;
      }
      const res = await sb.rpc('get_chain_for_pdf', { p_chain_id: chainId });
      if (cancelled) return;
      if (res.error || res.data?.error) {
        setError(res.error?.message || res.data?.error || 'Erro ao carregar dados da cadeia.');
        setLoading(false);
        return;
      }
      setData(res.data as ChainData);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [chainId, getSb]);

  const downloadDocx = useCallback(async () => {
    if (!data) return;
    setExporting(true);
    setError('');
    try {
      const safeTitle = data.document.title.replace(/[^\w]/g, '_').slice(0, 80);
      const safeVersion = data.version.label.replace(/[^\w]/g, '_').slice(0, 60);
      const fileName = `${safeTitle}_${safeVersion}.docx`;

      const wrappedHtml = `<!DOCTYPE html>
<html lang='pt-BR'>
<head>
  <meta charset='utf-8'>
  <title>${escapeHtml(data.document.title)} — ${escapeHtml(data.version.label)}</title>
</head>
<body>
  <p style="color: #64748b; font-size: 10pt; margin-bottom: 8pt;">
    <strong>${escapeHtml(data.document.title)}</strong><br/>
    Versão: ${escapeHtml(data.version.label)} · Status da cadeia: ${escapeHtml(data.chain_status)}<br/>
    Submetido por: ${escapeHtml(data.submitter?.name || '—')}<br/>
    Lacrado em: ${data.version.locked_at ? escapeHtml(new Date(data.version.locked_at).toLocaleString('pt-BR')) : '—'}<br/>
    Cadeia aberta em: ${data.opened_at ? escapeHtml(new Date(data.opened_at).toLocaleString('pt-BR')) : '—'}<br/>
    <em>Documento exportado para revisão offline. Use o PDF Oficial para envio formal pós-ratificação.</em>
  </p>
  <hr/>
  ${data.version.content_html}
</body>
</html>`;

      const HTMLtoDOCX = await loadHTMLtoDOCX();
      const result = await HTMLtoDOCX(wrappedHtml, null, {
        title: `${data.document.title} — ${data.version.label}`,
        creator: 'Núcleo IA & GP — Plataforma de Governança',
        orientation: 'portrait',
        margins: { top: 1440, right: 1440, bottom: 1440, left: 1440, header: 720, footer: 720, gutter: 0 },
        font: 'Calibri',
        fontSize: 22,
        pageNumber: true,
        lang: 'pt-BR',
        table: { row: { cantSplit: true } },
      });
      const blob = result instanceof Blob
        ? result
        : new Blob([result as ArrayBuffer], { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' });

      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 4000);
    } catch (e: any) {
      setError(`Erro ao gerar DOCX: ${e?.message || String(e)}`);
    } finally {
      setExporting(false);
    }
  }, [data]);

  if (loading) {
    return (
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-6 text-center">
        <p className="text-sm text-[var(--text-muted)]">Carregando dados da cadeia para gerar DOCX…</p>
      </div>
    );
  }
  if (error) {
    return <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>;
  }
  if (!data) return null;

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5">
        <h2 className="text-lg font-bold text-[var(--text-primary)] mb-3">Exportação DOCX (Word) — conteúdo da versão</h2>
        <dl className="grid grid-cols-1 md:grid-cols-2 gap-2 text-[13px] mb-4">
          <div>
            <dt className="text-[11px] font-semibold text-[var(--text-muted)]">Documento</dt>
            <dd className="text-[var(--text-primary)]">{data.document.title}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-[var(--text-muted)]">Versão</dt>
            <dd className="text-[var(--text-primary)]">{data.version.label}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-[var(--text-muted)]">Submetido por</dt>
            <dd className="text-[var(--text-primary)]">{data.submitter?.name || '—'}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-[var(--text-muted)]">Status da cadeia</dt>
            <dd className="text-[var(--text-primary)]">{data.chain_status}</dd>
          </div>
        </dl>
        <div className="rounded-lg bg-amber-50 border border-amber-200 px-3 py-2 text-[12px] text-amber-900 mb-4">
          <strong>Atenção:</strong> este export inclui apenas o <strong>conteúdo</strong> da versão (sem assinaturas /
          audit trail). Para envio formal pós-ratificação, use o PDF Oficial. Indicado para envio a curadores externos
          que não têm acesso direto à plataforma (e.g., advogados em revisão paralela).
        </div>
        <button
          type="button"
          onClick={downloadDocx}
          disabled={exporting}
          className="rounded-lg bg-navy text-white text-[13px] font-bold px-4 py-2 border-0 cursor-pointer hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {exporting ? 'Gerando…' : '⬇ Baixar DOCX'}
        </button>
      </div>
      <div className="rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] p-4 text-[12px] text-[var(--text-muted)]">
        <strong className="text-[var(--text-primary)]">Boa prática futura (T-15):</strong> em vez de export offline, dar
        a curadores externos uma role <code>external_reviewer</code> com acesso temporário à plataforma para visualizar e
        comentar diretamente. Mantém auditoria completa e elimina passos manuais de envio.
      </div>
    </div>
  );
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
