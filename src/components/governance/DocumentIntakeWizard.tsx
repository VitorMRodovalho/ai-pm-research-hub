import { useCallback, useMemo, useState } from 'react';

/**
 * /admin/governance/documents — "Novo documento" intake wizard.
 *
 * #315 Wave 2 (#310). Tier-1 5-field intake per P1-Q6 + optional
 * proposer_ack_offline (A2) + optional proposer_member_id. Consumes RPC
 * create_governance_document_intake (live since Wave 1a M3).
 *
 * On success redirects to the existing /admin/governance/documents/{docId}/versions/new
 * editor.
 *
 * Auth: page-level admin gate is already AdminLayout; the RPC enforces
 * can_by_member(manage_event) SECDEF.
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

type VisibilityClass =
  | 'public'
  | 'active_members'
  | 'legal_scoped'
  | 'admin_only'
  | 'audit_restricted';

type AcknowledgementMode = 'informational' | 'binding' | 'legal_signature';

const DOC_TYPES: DocType[] = [
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

const VISIBILITY_CLASSES: VisibilityClass[] = [
  'public',
  'active_members',
  'legal_scoped',
  'admin_only',
  'audit_restricted',
];

// Mirror of A1 default-per-doc_type table (intake RPC pre-fills the same way).
// Surfaced read-only to GP so they understand which ack flow ships with the doc.
const ACK_DEFAULTS: Record<DocType, AcknowledgementMode> = {
  manual: 'informational',
  editorial_guide: 'informational',
  governance_guideline: 'informational',
  executive_summary: 'informational',
  framework_reference: 'informational',
  project_charter: 'informational',
  cooperation_agreement: 'legal_signature',
  cooperation_addendum: 'legal_signature',
  volunteer_term_template: 'binding',
  volunteer_addendum: 'binding',
  policy: 'binding',
};

type Strings = {
  ctaOpen: string;
  modalTitle: string;
  modalSubtitle: string;
  fieldTitle: string;
  fieldTitlePlaceholder: string;
  fieldDocType: string;
  fieldDocTypeHint: string;
  fieldAuthor: string;
  fieldAuthorPlaceholder: string;
  fieldAuthorHint: string;
  fieldVisibility: string;
  fieldVisibilityHint: string;
  fieldDescription: string;
  fieldDescriptionPlaceholder: string;
  advancedToggle: string;
  fieldProposerAckOffline: string;
  fieldProposerAckOfflineHint: string;
  fieldProposerMemberId: string;
  fieldProposerMemberIdHint: string;
  ackPreviewLabel: string;
  ackInformational: string;
  ackBinding: string;
  ackLegalSignature: string;
  initialStatusLabel: string;
  initialStatusPendingProposer: string;
  initialStatusDraft: string;
  cancelBtn: string;
  submitBtn: string;
  submittingLabel: string;
  errorLabel: string;
  successRedirect: string;
  docTypes: Record<DocType, string>;
  visibilityClasses: Record<VisibilityClass, { label: string; hint: string }>;
  validationRequired: string;
};

type Props = {
  langPrefix: string;
  strings: Strings;
};

function isUuid(v: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

export default function DocumentIntakeWizard({ langPrefix, strings }: Props) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [docType, setDocType] = useState<DocType>('editorial_guide');
  const [authorLabel, setAuthorLabel] = useState('');
  const [visibilityClass, setVisibilityClass] = useState<VisibilityClass>('active_members');
  const [description, setDescription] = useState('');
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [proposerAckOffline, setProposerAckOffline] = useState(false);
  const [proposerMemberId, setProposerMemberId] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const ackPreview = useMemo(() => ACK_DEFAULTS[docType], [docType]);

  const reset = useCallback(() => {
    setTitle('');
    setDocType('editorial_guide');
    setAuthorLabel('');
    setVisibilityClass('active_members');
    setDescription('');
    setAdvancedOpen(false);
    setProposerAckOffline(false);
    setProposerMemberId('');
    setSubmitting(false);
    setError(null);
  }, []);

  const close = useCallback(() => {
    if (submitting) return;
    setOpen(false);
    reset();
  }, [submitting, reset]);

  const ackLabel = useCallback(
    (mode: AcknowledgementMode) => {
      if (mode === 'informational') return strings.ackInformational;
      if (mode === 'binding') return strings.ackBinding;
      return strings.ackLegalSignature;
    },
    [strings],
  );

  const handleSubmit = useCallback(
    async (ev: React.FormEvent<HTMLFormElement>) => {
      ev.preventDefault();
      setError(null);

      const v_title = title.trim();
      const v_author = authorLabel.trim();
      const v_description = description.trim();
      if (!v_title || !v_author || !v_description) {
        setError(strings.validationRequired);
        return;
      }
      const v_proposer = proposerMemberId.trim();
      if (v_proposer && !isUuid(v_proposer)) {
        setError(strings.fieldProposerMemberIdHint);
        return;
      }

      setSubmitting(true);
      try {
        const sb = getSb();
        if (!sb) {
          setError('Supabase client unavailable.');
          setSubmitting(false);
          return;
        }
        const payload: Record<string, unknown> = {
          title: v_title,
          doc_type: docType,
          author_label: v_author,
          visibility_class: visibilityClass,
          description: v_description,
          proposer_ack_offline: proposerAckOffline,
        };
        if (v_proposer) payload.proposer_member_id = v_proposer;

        const res = await sb.rpc('create_governance_document_intake', { p_payload: payload });
        if (res.error) {
          setError(res.error.message || 'RPC error');
          setSubmitting(false);
          return;
        }
        const docId: string | undefined = res.data?.document_id;
        if (!docId) {
          setError('RPC succeeded but did not return document_id.');
          setSubmitting(false);
          return;
        }
        window.location.href = `${langPrefix}/admin/governance/documents/${docId}/versions/new`;
      } catch (e: any) {
        setError(e?.message || 'Unexpected error');
        setSubmitting(false);
      }
    },
    [
      getSb,
      title,
      docType,
      authorLabel,
      visibilityClass,
      description,
      proposerAckOffline,
      proposerMemberId,
      strings,
      langPrefix,
    ],
  );

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded-lg bg-navy text-white text-[12px] font-bold px-4 py-2 hover:bg-navy/90 transition-colors"
        data-testid="intake-cta"
      >
        {strings.ctaOpen}
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4 py-6"
          role="dialog"
          aria-modal="true"
          aria-labelledby="intake-modal-title"
          data-testid="intake-modal"
        >
          <form
            onSubmit={handleSubmit}
            className="w-full max-w-2xl rounded-2xl bg-white shadow-xl border border-[var(--border-default)] max-h-[90vh] overflow-y-auto"
          >
            <header className="px-6 py-4 border-b border-[var(--border-default)] sticky top-0 bg-white">
              <h2 id="intake-modal-title" className="text-lg font-extrabold text-navy">
                {strings.modalTitle}
              </h2>
              <p className="text-[12px] text-[var(--text-muted)] mt-0.5">{strings.modalSubtitle}</p>
            </header>

            <div className="px-6 py-4 space-y-4">
              {/* Title */}
              <div>
                <label className="block text-[12px] font-bold text-navy mb-1" htmlFor="intake-title">
                  {strings.fieldTitle} <span className="text-red-600">*</span>
                </label>
                <input
                  id="intake-title"
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder={strings.fieldTitlePlaceholder}
                  className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm focus:outline-none focus:border-navy"
                  required
                  maxLength={300}
                />
              </div>

              {/* doc_type */}
              <div>
                <label className="block text-[12px] font-bold text-navy mb-1" htmlFor="intake-doc-type">
                  {strings.fieldDocType} <span className="text-red-600">*</span>
                </label>
                <select
                  id="intake-doc-type"
                  value={docType}
                  onChange={(e) => setDocType(e.target.value as DocType)}
                  className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm focus:outline-none focus:border-navy bg-white"
                  required
                >
                  {DOC_TYPES.map((dt) => (
                    <option key={dt} value={dt}>
                      {strings.docTypes[dt]}
                    </option>
                  ))}
                </select>
                <p className="text-[11px] text-[var(--text-muted)] mt-1">{strings.fieldDocTypeHint}</p>
              </div>

              {/* Acknowledgement preview (read-only — Wave 2 doesn't override) */}
              <div className="rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] px-3 py-2 text-[11px]">
                <span className="font-bold text-[var(--text-muted)]">{strings.ackPreviewLabel}: </span>
                <span className="text-navy font-semibold">{ackLabel(ackPreview)}</span>
              </div>

              {/* author_label */}
              <div>
                <label className="block text-[12px] font-bold text-navy mb-1" htmlFor="intake-author">
                  {strings.fieldAuthor} <span className="text-red-600">*</span>
                </label>
                <input
                  id="intake-author"
                  type="text"
                  value={authorLabel}
                  onChange={(e) => setAuthorLabel(e.target.value)}
                  placeholder={strings.fieldAuthorPlaceholder}
                  className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm focus:outline-none focus:border-navy"
                  required
                  maxLength={200}
                />
                <p className="text-[11px] text-[var(--text-muted)] mt-1">{strings.fieldAuthorHint}</p>
              </div>

              {/* visibility_class */}
              <div>
                <label className="block text-[12px] font-bold text-navy mb-1" htmlFor="intake-visibility">
                  {strings.fieldVisibility} <span className="text-red-600">*</span>
                </label>
                <select
                  id="intake-visibility"
                  value={visibilityClass}
                  onChange={(e) => setVisibilityClass(e.target.value as VisibilityClass)}
                  className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm focus:outline-none focus:border-navy bg-white"
                  required
                >
                  {VISIBILITY_CLASSES.map((vc) => (
                    <option key={vc} value={vc}>
                      {strings.visibilityClasses[vc].label}
                    </option>
                  ))}
                </select>
                <p className="text-[11px] text-[var(--text-muted)] mt-1">
                  {strings.visibilityClasses[visibilityClass].hint}
                </p>
              </div>

              {/* description */}
              <div>
                <label className="block text-[12px] font-bold text-navy mb-1" htmlFor="intake-description">
                  {strings.fieldDescription} <span className="text-red-600">*</span>
                </label>
                <textarea
                  id="intake-description"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder={strings.fieldDescriptionPlaceholder}
                  className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm focus:outline-none focus:border-navy resize-y"
                  rows={3}
                  required
                  maxLength={1000}
                />
              </div>

              {/* Initial status preview */}
              <div className="rounded-lg border border-[var(--border-default)] bg-amber-50 px-3 py-2 text-[11px]">
                <span className="font-bold text-amber-800">{strings.initialStatusLabel}: </span>
                <span className="text-amber-900">
                  {proposerAckOffline ? strings.initialStatusDraft : strings.initialStatusPendingProposer}
                </span>
              </div>

              {/* Advanced collapsible */}
              <div className="rounded-lg border border-[var(--border-default)] bg-white">
                <button
                  type="button"
                  onClick={() => setAdvancedOpen((s) => !s)}
                  className="w-full text-left px-3 py-2 text-[12px] font-bold text-navy hover:bg-[var(--surface-card)]"
                  aria-expanded={advancedOpen}
                >
                  {advancedOpen ? '▼' : '▶'} {strings.advancedToggle}
                </button>
                {advancedOpen && (
                  <div className="px-3 pb-3 space-y-3 border-t border-[var(--border-default)]">
                    <label className="flex items-start gap-2 cursor-pointer pt-3">
                      <input
                        type="checkbox"
                        checked={proposerAckOffline}
                        onChange={(e) => setProposerAckOffline(e.target.checked)}
                        className="mt-0.5"
                      />
                      <span className="text-[12px]">
                        <span className="font-bold text-navy">{strings.fieldProposerAckOffline}</span>
                        <span className="block text-[11px] text-[var(--text-muted)] mt-0.5">
                          {strings.fieldProposerAckOfflineHint}
                        </span>
                      </span>
                    </label>
                    <div>
                      <label className="block text-[12px] font-bold text-navy mb-1" htmlFor="intake-proposer-id">
                        {strings.fieldProposerMemberId}
                      </label>
                      <input
                        id="intake-proposer-id"
                        type="text"
                        value={proposerMemberId}
                        onChange={(e) => setProposerMemberId(e.target.value)}
                        placeholder="00000000-0000-0000-0000-000000000000"
                        className="w-full rounded-lg border border-[var(--border-default)] px-3 py-2 text-sm font-mono focus:outline-none focus:border-navy"
                        maxLength={36}
                      />
                      <p className="text-[11px] text-[var(--text-muted)] mt-1">
                        {strings.fieldProposerMemberIdHint}
                      </p>
                    </div>
                  </div>
                )}
              </div>

              {error && (
                <div
                  className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-[12px] text-red-800"
                  data-testid="intake-error"
                >
                  <span className="font-bold">{strings.errorLabel}: </span>
                  {error}
                </div>
              )}
            </div>

            <footer className="px-6 py-3 border-t border-[var(--border-default)] bg-[var(--surface-card)] sticky bottom-0 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={close}
                disabled={submitting}
                className="rounded-lg bg-white border border-[var(--border-default)] text-[12px] font-bold text-[var(--text-secondary)] px-4 py-2 hover:text-navy hover:border-navy disabled:opacity-50"
              >
                {strings.cancelBtn}
              </button>
              <button
                type="submit"
                disabled={submitting}
                className="rounded-lg bg-navy text-white text-[12px] font-bold px-5 py-2 hover:bg-navy/90 disabled:opacity-50"
                data-testid="intake-submit"
              >
                {submitting ? strings.submittingLabel : strings.submitBtn}
              </button>
            </footer>
          </form>
        </div>
      )}
    </>
  );
}
