import { useCallback, useEffect, useMemo, useState } from 'react';

/**
 * /governance/documents — Member-facing biblioteca canônica.
 *
 * #315 Wave 3 (#314). Consumes RPC list_governance_library(p_filters jsonb)
 * (Wave 1a M3) — visibility_class é filtrada server-side; admin_only e
 * audit_restricted nunca chegam a um non-admin; file_id/drive_url/content/
 * pdf_url nunca aparecem no payload (P0-Q8 forward-defense).
 *
 * Filtros suportados via query string (?type=…&status=…) para links
 * shareable. Empty state e error state trilíngues. Cada card linka para
 * /governance/document/{id} (reader individual; hardening em leaf futuro).
 */

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

type DocType =
  | 'manual'
  | 'cooperation_agreement'
  | 'framework_reference'
  | 'cooperation_addendum'
  | 'volunteer_addendum'
  | 'policy'
  | 'volunteer_term_template'
  | 'executive_summary'
  | 'project_charter'
  | 'editorial_guide'
  | 'governance_guideline';

type Status = 'draft' | 'pending_proposer_consent' | 'under_review' | 'approved' | 'active' | 'superseded' | 'withdrawn' | 'revoked';

type VisibilityClass = 'public' | 'active_members' | 'legal_scoped' | 'admin_only' | 'audit_restricted';

type AcknowledgementMode = 'informational' | 'binding' | 'legal_signature';

// Wave 1a M3 payload shape (list_governance_library returns this exact set of
// fields per document — adding/removing fields server-side would mean a CI
// regression caught by the contract test).
type LibraryDoc = {
  id: string;
  title: string;
  description: string | null;
  doc_type: DocType;
  status: Status;
  visibility_class: VisibilityClass;
  acknowledgement_mode: AcknowledgementMode;
  effective_from: string | null;
  effective_until: string | null;
  approved_at: string | null;
  current_ratified_version_id: string | null;
  current_version_id: string | null;
};

const DOC_TYPE_FILTER_OPTIONS: DocType[] = [
  'manual',
  'editorial_guide',
  'governance_guideline',
  'policy',
  'volunteer_term_template',
  'volunteer_addendum',
  'cooperation_agreement',
  'cooperation_addendum',
  'project_charter',
  'executive_summary',
  'framework_reference',
];

const STATUS_FILTER_OPTIONS: Status[] = ['active', 'approved', 'under_review', 'superseded'];

type Strings = {
  pageTitle: string;
  pageIntro: string;
  filtersHeading: string;
  filterDocType: string;
  filterStatus: string;
  filterAll: string;
  filterClear: string;
  loading: string;
  errorPrefix: string;
  emptyTitle: string;
  emptyHint: string;
  cardEffective: string;
  cardApproved: string;
  cardOpenReader: string;
  cardNoDescription: string;
  docTypes: Record<DocType, string>;
  statusLabels: Record<Status, string>;
  visibilityLabels: Record<VisibilityClass, string>;
  ackLabels: Record<AcknowledgementMode, string>;
};

type Props = {
  langPrefix: string;
  strings: Strings;
};

const STATUS_TONE: Record<Status, string> = {
  draft: 'bg-gray-100 text-gray-700 border-gray-300',
  pending_proposer_consent: 'bg-amber-50 text-amber-800 border-amber-200',
  under_review: 'bg-amber-100 text-amber-800 border-amber-300',
  approved: 'bg-blue-100 text-blue-800 border-blue-300',
  active: 'bg-emerald-100 text-emerald-800 border-emerald-300',
  superseded: 'bg-gray-200 text-gray-600 border-gray-400',
  withdrawn: 'bg-red-100 text-red-700 border-red-300',
  revoked: 'bg-red-200 text-red-800 border-red-400',
};

const ACK_TONE: Record<AcknowledgementMode, string> = {
  informational: 'bg-sky-50 text-sky-800 border-sky-200',
  binding: 'bg-amber-50 text-amber-900 border-amber-300',
  legal_signature: 'bg-purple-50 text-purple-900 border-purple-300',
};

function readUrlFilters(): { docType: DocType | ''; status: Status | '' } {
  if (typeof window === 'undefined') return { docType: '', status: '' };
  const params = new URLSearchParams(window.location.search);
  const dt = (params.get('type') || '') as DocType | '';
  const st = (params.get('status') || '') as Status | '';
  return {
    docType: (DOC_TYPE_FILTER_OPTIONS as string[]).includes(dt) ? (dt as DocType) : '',
    status: (STATUS_FILTER_OPTIONS as string[]).includes(st) ? (st as Status) : '',
  };
}

function writeUrlFilters(docType: DocType | '', status: Status | '') {
  if (typeof window === 'undefined') return;
  const url = new URL(window.location.href);
  if (docType) url.searchParams.set('type', docType);
  else url.searchParams.delete('type');
  if (status) url.searchParams.set('status', status);
  else url.searchParams.delete('status');
  window.history.replaceState(null, '', url.toString());
}

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleDateString();
  } catch {
    return iso.slice(0, 10);
  }
}

export default function GovernanceLibrary({ langPrefix, strings }: Props) {
  const initial = useMemo(() => readUrlFilters(), []);
  const [docType, setDocType] = useState<DocType | ''>(initial.docType);
  const [status, setStatus] = useState<Status | ''>(initial.status);
  const [docs, setDocs] = useState<LibraryDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    let tries = 0;
    let sb: any = null;
    while (!sb && tries < 30) {
      sb = getSb();
      if (sb) break;
      await new Promise((r) => setTimeout(r, 200));
      tries++;
    }
    if (!sb) {
      setError('Supabase client unavailable.');
      setLoading(false);
      return;
    }
    const filters: Record<string, unknown> = {};
    if (docType) filters.doc_type = docType;
    if (status) filters.status = status;
    const res = await sb.rpc('list_governance_library', { p_filters: filters });
    if (res.error) {
      setError(res.error.message || 'RPC error');
      setLoading(false);
      return;
    }
    const list: LibraryDoc[] = Array.isArray(res.data?.documents) ? res.data.documents : [];
    setDocs(list);
    setLoading(false);
  }, [docType, status, getSb]);

  useEffect(() => {
    writeUrlFilters(docType, status);
    void load();
  }, [docType, status, load]);

  const clearFilters = useCallback(() => {
    setDocType('');
    setStatus('');
  }, []);

  const hasFilters = docType !== '' || status !== '';

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="text-2xl font-extrabold text-navy">{strings.pageTitle}</h1>
        <p className="text-sm text-[var(--text-secondary)] max-w-3xl">{strings.pageIntro}</p>
      </header>

      {/* Filters */}
      <section className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-4">
        <h2 className="text-[12px] font-bold text-navy uppercase tracking-wide mb-3">
          {strings.filtersHeading}
        </h2>
        <div className="flex flex-wrap gap-3 items-end">
          <div className="flex flex-col gap-1">
            <label className="text-[11px] font-semibold text-[var(--text-muted)]" htmlFor="lib-filter-type">
              {strings.filterDocType}
            </label>
            <select
              id="lib-filter-type"
              value={docType}
              onChange={(e) => setDocType((e.target.value || '') as DocType | '')}
              className="rounded-lg border border-[var(--border-default)] bg-white px-3 py-2 text-sm focus:outline-none focus:border-navy min-w-[220px]"
            >
              <option value="">{strings.filterAll}</option>
              {DOC_TYPE_FILTER_OPTIONS.map((dt) => (
                <option key={dt} value={dt}>
                  {strings.docTypes[dt]}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label className="text-[11px] font-semibold text-[var(--text-muted)]" htmlFor="lib-filter-status">
              {strings.filterStatus}
            </label>
            <select
              id="lib-filter-status"
              value={status}
              onChange={(e) => setStatus((e.target.value || '') as Status | '')}
              className="rounded-lg border border-[var(--border-default)] bg-white px-3 py-2 text-sm focus:outline-none focus:border-navy min-w-[180px]"
            >
              <option value="">{strings.filterAll}</option>
              {STATUS_FILTER_OPTIONS.map((st) => (
                <option key={st} value={st}>
                  {strings.statusLabels[st]}
                </option>
              ))}
            </select>
          </div>
          {hasFilters && (
            <button
              type="button"
              onClick={clearFilters}
              className="rounded-lg bg-white border border-[var(--border-default)] text-[11px] font-bold text-[var(--text-secondary)] px-3 py-2 hover:text-navy hover:border-navy"
            >
              {strings.filterClear}
            </button>
          )}
        </div>
      </section>

      {/* Loading / error / empty / list */}
      {loading && (
        <div className="text-center py-12 text-sm text-[var(--text-muted)]" data-testid="lib-loading">
          {strings.loading}
        </div>
      )}

      {!loading && error && (
        <div
          className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800"
          data-testid="lib-error"
        >
          <span className="font-bold">{strings.errorPrefix} </span>
          {error}
        </div>
      )}

      {!loading && !error && docs.length === 0 && (
        <div
          className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-6 py-12 text-center"
          data-testid="lib-empty"
        >
          <p className="text-sm font-bold text-navy">{strings.emptyTitle}</p>
          <p className="text-[12px] text-[var(--text-muted)] mt-1">{strings.emptyHint}</p>
        </div>
      )}

      {!loading && !error && docs.length > 0 && (
        <ul className="grid gap-4 md:grid-cols-2" data-testid="lib-list">
          {docs.map((d) => {
            const statusToneClass = STATUS_TONE[d.status] || STATUS_TONE.draft;
            const ackToneClass = ACK_TONE[d.acknowledgement_mode] || ACK_TONE.informational;
            return (
              <li
                key={d.id}
                className="rounded-xl border border-[var(--border-default)] bg-white p-4 shadow-sm flex flex-col gap-3"
                data-testid="lib-card"
              >
                <div className="flex items-start justify-between gap-2 flex-wrap">
                  <h3 className="text-base font-extrabold text-navy">{d.title}</h3>
                  <span
                    className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full border text-[10px] font-bold ${statusToneClass}`}
                  >
                    {strings.statusLabels[d.status] || d.status}
                  </span>
                </div>

                <div className="flex flex-wrap gap-1.5 text-[10px]">
                  <span className="inline-flex items-center px-2 py-0.5 rounded-full border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-secondary)] font-semibold">
                    {strings.docTypes[d.doc_type] || d.doc_type}
                  </span>
                  <span className={`inline-flex items-center px-2 py-0.5 rounded-full border font-semibold ${ackToneClass}`}>
                    {strings.ackLabels[d.acknowledgement_mode] || d.acknowledgement_mode}
                  </span>
                  <span className="inline-flex items-center px-2 py-0.5 rounded-full border border-[var(--border-default)] bg-[var(--surface-card)] text-[var(--text-muted)] font-semibold">
                    {strings.visibilityLabels[d.visibility_class] || d.visibility_class}
                  </span>
                </div>

                <p className="text-[12px] text-[var(--text-secondary)] line-clamp-3">
                  {d.description || strings.cardNoDescription}
                </p>

                <dl className="text-[11px] text-[var(--text-muted)] grid grid-cols-2 gap-x-3 gap-y-1">
                  <dt className="font-semibold">{strings.cardEffective}</dt>
                  <dd>{formatDate(d.effective_from)}</dd>
                  <dt className="font-semibold">{strings.cardApproved}</dt>
                  <dd>{formatDate(d.approved_at)}</dd>
                </dl>

                <a
                  href={`${langPrefix}/governance/document/${d.id}`}
                  className="self-start inline-flex items-center gap-1 text-[12px] font-bold text-navy no-underline hover:underline"
                >
                  {strings.cardOpenReader} →
                </a>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
