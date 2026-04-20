/**
 * ChainAuditReportIsland — IP-4 Chunk 3
 * Carrega dados via get_chain_audit_report + oferece download PDF auditoria.
 */
import { useCallback, useEffect, useState } from 'react';
import { PDFDownloadLink } from '@react-pdf/renderer';
import ChainAuditReportPDF, { type AuditReportData } from './ChainAuditReportPDF';

export default function ChainAuditReportIsland({ chainId }: { chainId: string }) {
  const [data, setData] = useState<AuditReportData | null>(null);
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
      const res = await sb.rpc('get_chain_audit_report', { p_chain_id: chainId });
      if (cancelled) return;
      if (res.error || res.data?.error) {
        setError(res.error?.message || res.data?.error || 'Erro ao carregar relatório de auditoria');
        setLoading(false);
        return;
      }
      setData(res.data as AuditReportData);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [chainId, getSb]);

  if (loading) {
    return (
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-6 text-center">
        <p className="text-sm text-[var(--text-muted)]">Carregando dados para relatório de auditoria…</p>
      </div>
    );
  }
  if (error) {
    return <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">{error}</div>;
  }
  if (!data) return null;

  const fileName = `AUDIT_${data.document.title.replace(/[^\w]/g, '_')}_${data.version.label.replace(/[^\w]/g, '_')}_${data.chain_id.substring(0, 8)}.pdf`;

  return (
    <div className="space-y-4">
      <div className="rounded-xl border border-amber-300 bg-amber-50 p-5">
        <h2 className="text-lg font-bold text-amber-900 mb-3">Relatório de Auditoria — Conselho Fiscal PMI-GO</h2>
        <p className="text-[13px] text-amber-900 mb-4">
          Documento destinado a <strong>auditoria externa</strong> pelo Conselho Fiscal PMI-GO. Complementa o PDF oficial (que contém o conteúdo lacrado), focando em <strong>evidence trail</strong>, <strong>timeline cronológica</strong> e <strong>integridade de assinaturas</strong>.
        </p>

        <dl className="grid grid-cols-1 md:grid-cols-2 gap-2 text-[13px] mb-4">
          <div>
            <dt className="text-[11px] font-semibold text-amber-800">Documento</dt>
            <dd className="text-amber-950">{data.document.title}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-amber-800">Versão</dt>
            <dd className="text-amber-950">{data.version.label}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-amber-800">Status da cadeia</dt>
            <dd className="text-amber-950">{data.chain_status}</dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-amber-800">Eventos registrados</dt>
            <dd className="text-amber-950">
              {data.timeline.length} eventos · {data.signoffs.length} signoffs · {data.audit_log_entries.length} audit log
            </dd>
          </div>
          <div>
            <dt className="text-[11px] font-semibold text-amber-800">Integridade (RF-III/RF-V)</dt>
            <dd className="text-amber-950 text-[11px]">
              {data.integrity_summary.with_hash}/{data.integrity_summary.total_signoffs} c/ hash ·
              {data.integrity_summary.with_policy_version_ref}/{data.integrity_summary.total_signoffs} c/ policy ref ·
              {data.integrity_summary.with_notification_read_evidence}/{data.integrity_summary.total_signoffs} c/ read evidence
            </dd>
          </div>
        </dl>

        <PDFDownloadLink
          document={<ChainAuditReportPDF data={data} />}
          fileName={fileName}
          className="inline-block rounded-lg bg-amber-700 text-white text-[13px] font-bold px-4 py-2 border-0 cursor-pointer hover:opacity-90"
        >
          {({ loading: genLoading }) => (genLoading ? 'Gerando relatório…' : `Baixar relatório de auditoria — ${fileName}`)}
        </PDFDownloadLink>
      </div>
    </div>
  );
}
