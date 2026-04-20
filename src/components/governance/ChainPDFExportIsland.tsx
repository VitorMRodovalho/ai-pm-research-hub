/**
 * ChainPDFExportIsland — IP-4 Chunk 2
 * Client-side: carrega dados via get_chain_for_pdf + oferece botão de download PDF.
 */
import { useCallback, useEffect, useState } from 'react';
import { PDFDownloadLink } from '@react-pdf/renderer';
import ChainPDFDocument, { type ChainData } from './ChainPDFDocument';

export default function ChainPDFExportIsland({ chainId }: { chainId: string }) {
  const [data, setData] = useState<ChainData | null>(null);
  const [error, setError] = useState<string>('');
  const [loading, setLoading] = useState(true);

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
      if (!sb) { setError('Cliente Supabase indisponível. Recarregue a página.'); setLoading(false); return; }
      const res = await sb.rpc('get_chain_for_pdf', { p_chain_id: chainId });
      if (cancelled) return;
      if (res.error || res.data?.error) {
        setError(res.error?.message || res.data?.error || 'Erro ao carregar dados da cadeia');
        setLoading(false);
        return;
      }
      setData(res.data as ChainData);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [chainId, getSb]);

  if (loading) {
    return (
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-6 text-center">
        <p className="text-sm text-[var(--text-muted)]">Carregando dados da cadeia para gerar PDF…</p>
      </div>
    );
  }
  if (error) {
    return (
      <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>
    );
  }
  if (!data) return null;

  const fileName = `${data.document.title.replace(/[^\w]/g, '_')}_${data.version.label.replace(/[^\w]/g, '_')}_${data.chain_id.substring(0, 8)}.pdf`;

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5">
        <h2 className="text-lg font-bold text-[var(--text-primary)] mb-3">Exportação PDF — cadeia de ratificação</h2>
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
            <dt className="text-[11px] font-semibold text-[var(--text-muted)]">Status</dt>
            <dd className="text-[var(--text-primary)]">{data.chain_status}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-[var(--text-muted)]">Gates</dt>
            <dd className="text-[var(--text-primary)]">
              {data.gates.length} · {data.gates.reduce((sum, g) => sum + g.signers.length, 0)} assinaturas registradas
            </dd>
          </div>
        </dl>

        <div className="border-l-4 border-amber-400 bg-amber-50 px-3 py-2 text-[12px] text-amber-900 mb-4">
          <strong>Escopo do PDF:</strong> representação digital da cadeia. Assinaturas incluem hash SHA-256 + evidência de recebimento/leitura da notificação (ato concludente CC Art. 111) + versão da Política referenciada. A versão autoritativa permanece na base de dados.
        </div>

        <PDFDownloadLink
          document={<ChainPDFDocument data={data} />}
          fileName={fileName}
          className="inline-block rounded-lg bg-navy text-white text-[13px] font-bold px-4 py-2 border-0 cursor-pointer hover:opacity-90"
        >
          {({ loading: genLoading }) => (genLoading ? 'Gerando PDF…' : `Baixar PDF — ${fileName}`)}
        </PDFDownloadLink>
      </div>
    </div>
  );
}
