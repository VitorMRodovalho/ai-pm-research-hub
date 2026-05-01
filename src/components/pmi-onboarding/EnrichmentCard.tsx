import { useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';

interface EnrichmentStatus {
  application_id: string;
  has_consent: boolean;
  has_analysis: boolean;
  should_offer_enrichment: boolean;
  enrichment_count: number;
  remaining_attempts: number;
  cap_reached: boolean;
  last_enrichment_at: string | null;
  cooldown_until: string | null;
  is_in_cooldown: boolean;
  red_flags: any[];
  areas_to_probe: any[];
  fit_score: number | null;
  analyzed_at: string | null;
}

interface Props {
  token: string;
  sb: SupabaseClient;
  status: EnrichmentStatus;
  T: (k: string) => string;
  onEnriched?: () => void;
}

const ENRICHABLE_FIELDS: Array<{ key: string; icon: string; labelKey: string; placeholderKey: string }> = [
  { key: 'academic_background', icon: '📚', labelKey: 'pmi.enrichment.field.academic.label', placeholderKey: 'pmi.enrichment.field.academic.placeholder' },
  { key: 'non_pmi_experience', icon: '💼', labelKey: 'pmi.enrichment.field.experience.label', placeholderKey: 'pmi.enrichment.field.experience.placeholder' },
  { key: 'leadership_experience', icon: '👑', labelKey: 'pmi.enrichment.field.leadership.label', placeholderKey: 'pmi.enrichment.field.leadership.placeholder' },
  { key: 'proposed_theme', icon: '🎯', labelKey: 'pmi.enrichment.field.theme.label', placeholderKey: 'pmi.enrichment.field.theme.placeholder' },
  { key: 'motivation_letter', icon: '✍️', labelKey: 'pmi.enrichment.field.motivation.label', placeholderKey: 'pmi.enrichment.field.motivation.placeholder' },
];

export default function EnrichmentCard({ token, sb, status, T, onEnriched }: Props) {
  const [values, setValues] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const cooldownLabel = (() => {
    if (!status.is_in_cooldown || !status.cooldown_until) return null;
    const remainingMs = new Date(status.cooldown_until).getTime() - Date.now();
    const remainingMin = Math.max(0, Math.ceil(remainingMs / 60000));
    return remainingMin > 0 ? T('pmi.enrichment.gap.cooldownRemaining').replace('{n}', String(remainingMin)) : null;
  })();

  const handleSave = async () => {
    setBusy(true);
    setError(null);
    setSuccess(null);
    const updates: Record<string, string> = {};
    for (const [k, v] of Object.entries(values)) {
      if (v && v.trim().length > 0) updates[k] = v.trim();
    }
    if (Object.keys(updates).length === 0) {
      setError(T('pmi.enrichment.gap.errorEmpty'));
      setBusy(false);
      return;
    }
    try {
      const { data, error: rpcErr } = await sb.rpc('request_application_enrichment', {
        p_token: token,
        p_field_updates: updates,
      });
      if (rpcErr) throw new Error(rpcErr.message);
      if ((data as any)?.success === false) {
        throw new Error((data as any)?.error || T('pmi.enrichment.gap.errorGeneric'));
      }
      setSuccess(T('pmi.enrichment.gap.successSaved'));
      setValues({});
      if (onEnriched) onEnriched();
    } catch (e: any) {
      setError(e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  };

  if (status.cap_reached) {
    return (
      <div className="bg-emerald-50 border border-emerald-200 rounded-lg p-4 my-4">
        <h3 className="text-base font-bold text-emerald-900 mb-2">✓ {T('pmi.enrichment.gap.capReachedTitle')}</h3>
        <p className="text-sm text-emerald-800">{T('pmi.enrichment.gap.capReachedBody')}</p>
      </div>
    );
  }

  return (
    <div className="bg-amber-50 border border-amber-200 rounded-lg p-5 my-4">
      <h3 className="text-base font-bold text-amber-900 mb-1">
        🤖 {T('pmi.enrichment.gap.title')}
      </h3>
      <p className="text-sm text-amber-800 mb-4">{T('pmi.enrichment.gap.subtitle')}</p>

      <div className="space-y-3 mb-4">
        {ENRICHABLE_FIELDS.map(field => (
          <div key={field.key}>
            <label className="block text-sm font-semibold text-amber-900 mb-1">
              {field.icon} {T(field.labelKey)}
            </label>
            <textarea
              value={values[field.key] ?? ''}
              onChange={(e) => setValues({ ...values, [field.key]: e.target.value })}
              placeholder={T(field.placeholderKey)}
              rows={3}
              maxLength={2000}
              disabled={busy || status.is_in_cooldown}
              className="w-full px-3 py-2 text-sm border border-amber-300 rounded-md bg-white focus:outline-none focus:ring-2 focus:ring-amber-400 disabled:bg-amber-100 disabled:cursor-not-allowed"
            />
          </div>
        ))}
      </div>

      {error && <p className="text-sm text-red-700 mb-2">{error}</p>}
      {success && <p className="text-sm text-emerald-700 mb-2">{success}</p>}

      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={handleSave}
          disabled={busy || status.is_in_cooldown}
          className="px-5 py-2.5 bg-amber-600 text-white rounded-lg text-sm font-bold hover:bg-amber-700 disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {busy ? T('pmi.enrichment.gap.saving') : T('pmi.enrichment.gap.cta_save')}
        </button>
        <span className="text-xs text-amber-800">
          {T('pmi.enrichment.gap.attemptsRemaining').replace('{n}', String(status.remaining_attempts))}
        </span>
        {cooldownLabel && (
          <span className="text-xs text-amber-700 italic">⏱ {cooldownLabel}</span>
        )}
      </div>
    </div>
  );
}
