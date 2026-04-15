import { useState } from 'react';

interface Props {
  docs: any[];
  t: (key: string, fallback?: string) => string;
}

const TYPE_STYLE: Record<string, { bg: string; label: string }> = {
  manual: { bg: 'bg-purple-100 text-purple-700', label: 'Manual' },
  cooperation_agreement: { bg: 'bg-blue-100 text-blue-700', label: 'Acordo de Cooperação' },
  framework_reference: { bg: 'bg-gray-100 text-gray-700', label: 'Framework' },
  addendum: { bg: 'bg-amber-100 text-amber-700', label: 'Adendo' },
  policy: { bg: 'bg-teal-100 text-teal-700', label: 'Política' },
  volunteer_term_template: { bg: 'bg-indigo-100 text-indigo-700', label: 'Termo de Voluntariado' },
};

const STATUS_STYLE: Record<string, { bg: string; label: string }> = {
  active: { bg: 'bg-green-100 text-green-700', label: 'Ativo' },
  draft: { bg: 'bg-yellow-100 text-yellow-700', label: 'Draft' },
  superseded: { bg: 'bg-gray-100 text-gray-500', label: 'Substituído' },
};

function ContentPreview({ content }: { content: any }) {
  if (!content) return null;
  const parsed = typeof content === 'string' ? (() => { try { return JSON.parse(content); } catch { return null; } })() : content;
  if (!parsed || typeof parsed !== 'object') return null;

  return (
    <div className="mt-3 pt-3 border-t border-[var(--border-subtle)] space-y-2">
      {Object.entries(parsed).map(([key, value]) => {
        if (typeof value === 'string' && value.length < 500) {
          return (
            <div key={key} className="text-[11px]">
              <span className="font-semibold text-[var(--text-muted)]">{key}:</span>{' '}
              <span className="text-[var(--text-secondary)]">{value}</span>
            </div>
          );
        }
        if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
          const obj = value as Record<string, any>;
          return (
            <div key={key} className="text-[11px]">
              <span className="font-semibold text-[var(--text-muted)]">{obj.titulo || obj.nome || key}</span>
              {obj.texto && <p className="text-[var(--text-secondary)] mt-0.5 ml-3">{obj.texto}</p>}
            </div>
          );
        }
        return null;
      })}
    </div>
  );
}

export default function DocumentsList({ docs, t }: Props) {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const manualCount = docs.filter(d => d.doc_type === 'manual').length;
  const agreementCount = docs.filter(d => d.doc_type === 'cooperation_agreement').length;
  const addendumCount = docs.filter(d => d.doc_type === 'addendum').length;

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] px-5 py-3">
        <p className="text-sm text-[var(--text-secondary)]">
          <span className="font-bold text-navy">{docs.length}</span> {t('governance.documents_count', 'documentos oficiais')}
          {' · '}
          <span className="font-semibold">{agreementCount}</span> {t('governance.agreements_active', 'acordos ativos')}
          {addendumCount > 0 && (<>{' · '}<span className="font-semibold">{addendumCount}</span> {t('governance.addendums_count', 'adendos')}</>)}
          {' · '}
          <span className="font-semibold">{manualCount}</span> {t('governance.manual_current', 'manual vigente')}
        </p>
      </div>

      {/* Document cards */}
      <div className="space-y-3">
        {docs.map((doc: any) => {
          const style = TYPE_STYLE[doc.doc_type] || TYPE_STYLE.policy;
          const statusStyle = STATUS_STYLE[doc.status] || STATUS_STYLE.active;
          const signedDate = doc.signed_at ? new Date(doc.signed_at).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';
          const parties: string[] = doc.parties || [];
          const signatories: any[] = doc.signatories || [];
          const hasContent = doc.content && (typeof doc.content === 'string' ? doc.content.length > 2 : Object.keys(doc.content).length > 0);
          const isExpanded = expandedId === doc.id;

          return (
            <div key={doc.id} className="bg-[var(--surface-card)] rounded-2xl border border-[var(--border-default)] p-5 hover:shadow-sm transition-shadow">
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap mb-1">
                    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${style.bg}`}>
                      {t(`governance.doc_type_${doc.doc_type}`, style.label)}
                    </span>
                    <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${statusStyle.bg}`}>
                      {t(`governance.status_${doc.status}`, statusStyle.label)}
                    </span>
                    {doc.version && (
                      <span className="text-[10px] font-mono text-[var(--text-muted)]">{doc.version}</span>
                    )}
                  </div>
                  <h3 className="text-sm font-bold text-[var(--text-primary)]">{doc.title}</h3>
                  {doc.description && (
                    <p className="text-xs text-[var(--text-secondary)] mt-1">{doc.description}</p>
                  )}
                </div>
                {hasContent && (
                  <button
                    onClick={() => setExpandedId(isExpanded ? null : doc.id)}
                    className="shrink-0 px-2 py-1 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[10px] font-semibold text-[var(--text-muted)] cursor-pointer hover:bg-[var(--surface-hover)]"
                  >
                    {isExpanded ? t('governance.collapse', 'Recolher') : t('governance.expand', 'Expandir')}
                  </button>
                )}
              </div>

              <div className="flex flex-wrap gap-x-4 gap-y-1 mt-3 text-xs text-[var(--text-muted)]">
                <span>{t('governance.signed_at', 'Assinado em')}: <strong className="text-[var(--text-secondary)]">{signedDate}</strong></span>
                {doc.exit_notice_days && (
                  <span>{doc.exit_notice_days} {t('governance.exit_notice_days', 'dias para saída')}</span>
                )}
                {doc.docusign_envelope_id && (
                  <span className="font-mono text-[10px]">DocuSign: {doc.docusign_envelope_id.substring(0, 8)}...</span>
                )}
              </div>

              {/* Parties */}
              {parties.length > 0 && (
                <div className="flex flex-wrap gap-1.5 mt-2">
                  {parties.map((p: string) => (
                    <span key={p} className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-navy/10 text-navy">{p}</span>
                  ))}
                </div>
              )}

              {/* Expanded content */}
              {isExpanded && <ContentPreview content={doc.content} />}

              {/* Signatories (tier-gated) */}
              {signatories.length > 0 ? (
                <div className="mt-3 pt-2 border-t border-[var(--border-subtle)]">
                  <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-1">
                    {t('governance.signatories', 'Signatários')}
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {signatories.map((s: any, i: number) => (
                      <span key={i} className="text-xs text-[var(--text-secondary)]">
                        {s.name} <span className="text-[var(--text-muted)]">({s.role})</span>
                      </span>
                    ))}
                  </div>
                </div>
              ) : (
                <p className="mt-2 text-[10px] text-[var(--text-muted)] italic">
                  {t('governance.signatories_restricted', 'Detalhes restritos — contacte o GP')}
                </p>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
