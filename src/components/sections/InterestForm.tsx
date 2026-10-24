/**
 * InterestForm — the visitor interest form (capture_visitor_lead), opened by the "Apply" buttons of the home.
 *
 * #2738: this is the former FounderForm of VerticalsSection, moved here so the vertical cards and the
 * resources section open the SAME form. Until 19/10/2026 those buttons linked to two VEP opportunities whose
 * application deadlines had passed (31/07 and 13/09/2026). role_interest says which button was used
 * ('researcher' | 'leader'); source says where ('apply-vertical' | 'apply-resources'); target_vertical is the
 * card's initiative id (the RPC drops it unless it is a community_vertical).
 *
 * Labels come from the dictionaries (comp.interestForm.*) via buildPageI18n in the Astro caller.
 */
import { useEffect, useRef, useState, useCallback } from 'react';
import { buildInterestPayload, type InterestRole, type InterestSource } from '../../lib/interestPayload';

export type { InterestRole, InterestSource };

const K = 'comp.interestForm.';

export function InterestForm({ roleInterest, source, targetVertical = null, labels, messageKey = 'message', lp, onClose }: {
  roleInterest: InterestRole;
  source: InterestSource;
  targetVertical?: string | null;
  labels: Record<string, string>;
  messageKey?: 'message' | 'messageVertical' | 'messageChapter' | 'messagePartner';
  lp: string;
  onClose: () => void;
}) {
  const l = (k: string) => labels[K + k] || k;
  const [form, setForm] = useState({ name: '', email: '', message: '', lgpd_consent: false });
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [consentError, setConsentError] = useState(false);
  const nameRef = useRef<HTMLInputElement>(null);

  // a11y: move focus into the form when it expands (keyboard users skip the whole card).
  useEffect(() => { nameRef.current?.focus(); }, []);

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.lgpd_consent) { setConsentError(true); return; }
    setConsentError(false);
    setStatus('submitting');
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('No client');
      const payload = buildInterestPayload(form, { roleInterest, source, targetVertical }, window.location.search);
      const { data, error } = await sb.rpc('capture_visitor_lead', { p_payload: payload });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      setStatus('success');
      try { (window as any).__nucleoTrack?.('apply_interest', { role: roleInterest, source }); } catch { /* noop */ }
    } catch {
      setStatus('error');
    }
  }, [form, roleInterest, source, targetVertical]);

  if (status === 'success') {
    return (
      <div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-4 text-center" role="status">
        <div className="text-2xl mb-1">✅</div>
        <p className="text-sm font-semibold text-emerald-700">{l('success')}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} data-role-interest={roleInterest}
      className="mt-4 space-y-3 rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <input ref={nameRef} type="text" required placeholder={l('name')} aria-label={l('name')} value={form.name}
          onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
          className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
        <input type="email" required placeholder={l('email')} aria-label={l('email')} value={form.email}
          onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
          className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
      </div>
      <textarea rows={2} placeholder={l(messageKey)} aria-label={l(messageKey)} value={form.message}
        onChange={e => setForm(f => ({ ...f, message: e.target.value }))}
        className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)] resize-y" />
      <label className={`flex items-start gap-2 cursor-pointer ${consentError ? 'text-red-600' : ''}`}>
        <input type="checkbox" checked={form.lgpd_consent}
          onChange={e => { setForm(f => ({ ...f, lgpd_consent: e.target.checked })); setConsentError(false); }}
          className="mt-0.5 flex-shrink-0" />
        <span className="text-xs text-[var(--text-secondary)]">
          {l('consent')}{' '}
          <a href={`${lp}/privacy`} target="_blank" rel="noopener" className="text-teal underline">{l('consentLink')}</a>.
        </span>
      </label>
      {consentError && <p className="text-xs text-red-600">{l('consentRequired')}</p>}
      <div className="flex items-center gap-2">
        <button type="submit" disabled={status === 'submitting'}
          className="px-5 py-2 rounded-xl font-semibold text-sm text-white border-0 cursor-pointer disabled:opacity-50 bg-[var(--color-orange-deep)]">
          {status === 'submitting' ? l('submitting') : l('submit')}
        </button>
        <button type="button" onClick={onClose}
          className="px-3 py-2 rounded-xl text-sm text-[var(--text-secondary)] bg-transparent border border-[var(--border-default)] cursor-pointer">
          {l('cancel')}
        </button>
      </div>
      {status === 'error' && <p className="text-xs text-red-600">{l('error')}</p>}
    </form>
  );
}

/** A single "Apply" button that opens the form below it (resources section, and the three doors of the home). */
export default function ApplyInterest({ roleInterest, source, linkText, labels, lp, messageKey = 'message', buttonClassName }: {
  roleInterest: InterestRole;
  source: InterestSource;
  linkText: string;
  labels: Record<string, string>;
  lp: string;
  messageKey?: 'message' | 'messageVertical' | 'messageChapter' | 'messagePartner';
  buttonClassName?: string;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div>
      <button type="button" onClick={() => setOpen(true)} aria-expanded={open} data-apply-role={roleInterest}
        className={buttonClassName ?? 'text-teal text-[.78rem] font-semibold bg-transparent border-0 p-0 cursor-pointer hover:underline'}>
        {linkText}
      </button>
      {open && <InterestForm roleInterest={roleInterest} source={source} labels={labels} lp={lp} messageKey={messageKey} onClose={() => setOpen(false)} />}
    </div>
  );
}
