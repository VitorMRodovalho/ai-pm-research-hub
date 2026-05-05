/**
 * ChainPDFExportIsland — IP-4 Chunk 2 (revisado p93c)
 *
 * Carrega dados via get_chain_for_pdf + oferece DOIS botões PDF:
 *   1. 📝 Draft offline — sem assinaturas + watermark RASCUNHO. Para revisores
 *      lerem offline antes de assinar a chain. Sempre disponível.
 *   2. ⬇ Oficial — com página de assinaturas + audit trail SHA-256. Indicado
 *      para chains pós-aprovação (active/superseded). Em chains em review,
 *      reflete o status parcial das assinaturas.
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

  const safeTitle = data.document.title.replace(/[^\w]/g, '_');
  const safeVersion = data.version.label.replace(/[^\w]/g, '_');
  const chainShort = data.chain_id.substring(0, 8);
  const draftFileName = `${safeTitle}_${safeVersion}_DRAFT-REVISAO.pdf`;
  const officialFileName = `${safeTitle}_${safeVersion}_OFICIAL_${chainShort}.pdf`;

  const totalSignatures = data.gates.reduce((sum, g) => sum + g.signers.length, 0);
  const isPreRatification = data.chain_status === 'review' || (data.chain_status === 'draft');
  const recommendDraft = isPreRatification && totalSignatures === 0;

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
              {data.gates.length} · {totalSignatures} assinatura{totalSignatures === 1 ? '' : 's'} registrada{totalSignatures === 1 ? '' : 's'}
            </dd>
          </div>
        </dl>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {/* Draft button */}
          <div className={`rounded-xl border-2 ${recommendDraft ? 'border-amber-400 bg-amber-50' : 'border-[var(--border-default)] bg-white'} p-4`}>
            <div className="flex items-start justify-between gap-2 mb-2">
              <div>
                <h3 className="text-[13px] font-bold text-[var(--text-primary)]">📝 Rascunho para revisão</h3>
                <p className="text-[11px] text-[var(--text-muted)] mt-0.5">Leitura offline pré-assinatura</p>
              </div>
              {recommendDraft && (
                <span className="inline-block rounded-full bg-amber-200 text-amber-900 text-[9px] font-bold px-2 py-0.5">
                  Recomendado
                </span>
              )}
            </div>
            <ul className="text-[11px] text-[var(--text-secondary)] space-y-1 mb-3 pl-4 list-disc">
              <li>Conteúdo lacrado da versão {data.version.label}</li>
              <li>Watermark "RASCUNHO" em cada página</li>
              <li>Sem página de assinaturas (audit trail fica na plataforma)</li>
            </ul>
            <PDFDownloadLink
              document={<ChainPDFDocument data={data} mode="draft" />}
              fileName={draftFileName}
              className="inline-block rounded-lg bg-amber-600 text-white text-[12px] font-bold px-3 py-2 border-0 cursor-pointer hover:bg-amber-700 no-underline"
            >
              {({ loading: genLoading }) => (genLoading ? 'Gerando…' : 'Baixar draft')}
            </PDFDownloadLink>
          </div>

          {/* Official button */}
          <div className={`rounded-xl border-2 ${!recommendDraft ? 'border-navy bg-blue-50/30' : 'border-[var(--border-default)] bg-white'} p-4`}>
            <div className="flex items-start justify-between gap-2 mb-2">
              <div>
                <h3 className="text-[13px] font-bold text-[var(--text-primary)]">⬇ PDF oficial</h3>
                <p className="text-[11px] text-[var(--text-muted)] mt-0.5">Documento + assinaturas</p>
              </div>
              {!recommendDraft && (
                <span className="inline-block rounded-full bg-navy text-white text-[9px] font-bold px-2 py-0.5">
                  Recomendado
                </span>
              )}
            </div>
            <ul className="text-[11px] text-[var(--text-secondary)] space-y-1 mb-3 pl-4 list-disc">
              <li>Conteúdo + página de assinaturas com hash SHA-256</li>
              <li>Evidência de notificação (CC Art. 111)</li>
              <li>{totalSignatures > 0 ? `${totalSignatures} assinatura${totalSignatures === 1 ? '' : 's'} já registrada${totalSignatures === 1 ? '' : 's'}` : 'Inclui mesmo sem assinaturas (estado inicial)'}</li>
            </ul>
            <PDFDownloadLink
              document={<ChainPDFDocument data={data} mode="official" />}
              fileName={officialFileName}
              className="inline-block rounded-lg bg-navy text-white text-[12px] font-bold px-3 py-2 border-0 cursor-pointer hover:opacity-90 no-underline"
            >
              {({ loading: genLoading }) => (genLoading ? 'Gerando…' : 'Baixar oficial')}
            </PDFDownloadLink>
          </div>
        </div>

        <div className="mt-4 border-l-4 border-amber-400 bg-amber-50 px-3 py-2 text-[11px] text-amber-900">
          <strong>Sobre o rascunho:</strong> destinado a revisores baixarem o texto e lerem offline antes de assinar.
          A versão autoritativa com assinaturas hash SHA-256 + evidência de leitura permanece na plataforma. Para
          chain {data.chain_status === 'active' ? 'já ratificada' : 'em revisão'}, prefira o PDF oficial.
        </div>
      </div>
    </div>
  );
}
