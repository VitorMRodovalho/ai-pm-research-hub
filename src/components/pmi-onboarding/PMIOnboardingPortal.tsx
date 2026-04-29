import { useState, useMemo } from 'react';
import { createClient } from '@supabase/supabase-js';
import type { Lang } from '../../i18n/utils';

interface OnboardingProgressEntry {
  step_key: string;
  status: 'pending' | 'in_progress' | 'completed' | 'skipped';
  completed_at: string | null;
  evidence_url: string | null;
  notes: string | null;
  sla_deadline: string | null;
}

interface OnboardingStepDef {
  key: string;
  label?: string;
  description?: string;
  is_required?: boolean;
  type?: string;
}

interface ConsumePayload {
  source_type: 'pmi_application';
  scopes: string[];
  application: {
    id: string;
    applicant_name: string;
    email: string;
    phone: string | null;
    linkedin_url: string | null;
    role_applied: string;
    cycle_id: string;
    has_consent: boolean;
    has_revoked: boolean;
    status: string;
  };
  cycle: {
    id: string;
    cycle_code: string;
    title: string;
    phase: string;
    onboarding_steps: OnboardingStepDef[];
  };
  onboarding_progress: OnboardingProgressEntry[];
  token_metadata: {
    access_count: number;
    expires_at: string;
    first_access: boolean;
  };
}

type I18nBundle = Record<string, string>;

interface Props {
  token: string;
  initialPayload: ConsumePayload | null;
  i18n: I18nBundle;
  lang: Lang;
  supabaseUrl: string;
  supabaseAnonKey: string;
}

export default function PMIOnboardingPortal({
  token, initialPayload, i18n, lang, supabaseUrl, supabaseAnonKey
}: Props) {
  const [payload, setPayload] = useState<ConsumePayload | null>(initialPayload);
  const [busyConsent, setBusyConsent] = useState(false);
  const [busyStep, setBusyStep] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const sb = useMemo(() => createClient(supabaseUrl, supabaseAnonKey), [supabaseUrl, supabaseAnonKey]);
  const T = (k: string) => i18n[k] ?? k;

  if (!payload) {
    return (
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
        <p>{T('pmi.onboarding.loading')}</p>
      </div>
    );
  }

  const { application: app, cycle, onboarding_progress: progress, token_metadata } = payload;

  const expiresAtDate = new Date(token_metadata.expires_at);
  const daysLeft = Math.max(0, Math.floor((expiresAtDate.getTime() - Date.now()) / 86400000));

  const roleLabel = (() => {
    const map: Record<string, string> = {
      researcher: lang === 'en-US' ? 'Researcher' : lang === 'es-LATAM' ? 'Investigador' : 'Pesquisador',
      leader: lang === 'en-US' ? 'Tribe Leader' : lang === 'es-LATAM' ? 'Líder de Tribu' : 'Líder de Tribo',
      manager: lang === 'en-US' ? 'Project Manager' : lang === 'es-LATAM' ? 'Gerente de Proyecto' : 'Gerente de Projeto',
      both: lang === 'en-US' ? 'Researcher / Leader' : lang === 'es-LATAM' ? 'Investigador / Líder' : 'Pesquisador / Líder',
    };
    return map[app.role_applied] ?? app.role_applied;
  })();

  const handleConsentToggle = async (grant: boolean) => {
    setBusyConsent(true);
    setErrorMsg(null);
    try {
      const fnName = grant ? 'give_consent_via_token' : 'revoke_consent_via_token';
      const { error } = await sb.rpc(fnName, { p_token: token, p_consent_type: 'ai_analysis' });
      if (error) throw new Error(error.message);
      setPayload({
        ...payload,
        application: { ...app, has_consent: grant, has_revoked: !grant }
      });
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setBusyConsent(false);
    }
  };

  const handleStepUpdate = async (stepKey: string, newStatus: 'completed' | 'in_progress') => {
    setBusyStep(stepKey);
    setErrorMsg(null);
    try {
      const { error } = await sb.rpc('update_pmi_onboarding_step', {
        p_token: token,
        p_step_key: stepKey,
        p_status: newStatus,
        p_evidence_url: null,
      });
      if (error) throw new Error(error.message);
      // Optimistic update
      setPayload({
        ...payload,
        onboarding_progress: progress.map(p =>
          p.step_key === stepKey
            ? { ...p, status: newStatus, completed_at: newStatus === 'completed' ? new Date().toISOString() : null }
            : p
        )
      });
    } catch (e: any) {
      setErrorMsg(e?.message ?? String(e));
    } finally {
      setBusyStep(null);
    }
  };

  const completedCount = progress.filter(p => p.status === 'completed' || p.status === 'skipped').length;
  const totalCount = progress.length;
  const completionPct = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

  const isInPreOnboarding = ['submitted', 'screening', 'objective_eval', 'objective_cutoff', 'interview_pending', 'interview_scheduled', 'interview_done', 'final_eval'].includes(app.status);
  const isApproved = app.status === 'approved';

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="bg-gradient-to-br from-blue-50 to-indigo-50 border border-blue-200 rounded-xl p-6">
        <h1 className="text-2xl md:text-3xl font-bold text-gray-900 mb-2">
          {T('pmi.onboarding.greeting').replace('{name}', app.applicant_name.split(/\s+/)[0] ?? '')}
        </h1>
        <p className="text-gray-700">
          {T('pmi.onboarding.intro')
            .replace('{role}', roleLabel)
            .replace('{cycle}', cycle.title)}
        </p>
        <div className="mt-4 flex flex-wrap gap-2 text-sm">
          <span className="bg-white border border-blue-200 text-blue-800 px-3 py-1 rounded-full">
            {T('pmi.onboarding.cycleCode')}: <strong>{cycle.cycle_code}</strong>
          </span>
          <span className="bg-white border border-blue-200 text-blue-800 px-3 py-1 rounded-full">
            {T('pmi.onboarding.role')}: <strong>{roleLabel}</strong>
          </span>
          <span className="bg-white border border-blue-200 text-blue-800 px-3 py-1 rounded-full">
            {T('pmi.onboarding.status')}: <strong>{app.status}</strong>
          </span>
        </div>
      </div>

      {/* Token expiry notice */}
      <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 text-sm text-amber-900">
        ⏰ {T('pmi.onboarding.expires').replace('{days}', String(daysLeft))}
      </div>

      {/* Consent toggle (LGPD AI analysis) */}
      <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
        <h2 className="text-lg font-semibold text-gray-900 mb-2">
          {T('pmi.onboarding.consentTitle')}
        </h2>
        <p className="text-gray-600 text-sm mb-4">
          {T('pmi.onboarding.consentBody')}
        </p>
        <div className="flex items-center gap-3 flex-wrap">
          {app.has_consent && !app.has_revoked ? (
            <>
              <span className="bg-green-100 text-green-800 px-3 py-1 rounded-full text-sm font-medium">
                ✓ {T('pmi.onboarding.consentGranted')}
              </span>
              <button
                disabled={busyConsent}
                onClick={() => handleConsentToggle(false)}
                className="text-sm text-gray-600 underline hover:text-red-700 disabled:opacity-50"
              >
                {T('pmi.onboarding.revokeConsent')}
              </button>
            </>
          ) : (
            <>
              <span className="bg-gray-100 text-gray-800 px-3 py-1 rounded-full text-sm">
                {T('pmi.onboarding.consentNotGranted')}
              </span>
              <button
                disabled={busyConsent}
                onClick={() => handleConsentToggle(true)}
                className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white px-4 py-2 rounded-lg font-medium text-sm"
              >
                {busyConsent ? '...' : T('pmi.onboarding.grantConsent')}
              </button>
            </>
          )}
        </div>
      </section>

      {/* Progress overview */}
      {totalCount > 0 && (
        <section className="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
          <div className="flex justify-between items-center mb-3">
            <h2 className="text-lg font-semibold text-gray-900">
              {T('pmi.onboarding.progressTitle')}
            </h2>
            <span className="text-sm text-gray-600">
              {completedCount} / {totalCount} ({completionPct}%)
            </span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2 mb-4">
            <div
              className="bg-blue-600 h-2 rounded-full transition-all"
              style={{ width: `${completionPct}%` }}
            />
          </div>
          <ul className="divide-y divide-gray-100">
            {progress.map(step => {
              const def = cycle.onboarding_steps.find(s => s.key === step.step_key) ?? null;
              const label = def?.label ?? step.step_key;
              const desc = def?.description;
              const done = step.status === 'completed' || step.status === 'skipped';
              return (
                <li key={step.step_key} className="py-3 flex items-start gap-3">
                  <div className={`mt-1 w-5 h-5 rounded-full flex-shrink-0 flex items-center justify-center text-xs ${done ? 'bg-green-500 text-white' : 'bg-gray-200 text-gray-500'}`}>
                    {done ? '✓' : ''}
                  </div>
                  <div className="flex-1">
                    <div className="font-medium text-gray-900">{label}</div>
                    {desc && <div className="text-sm text-gray-600 mt-0.5">{desc}</div>}
                    {step.completed_at && (
                      <div className="text-xs text-gray-500 mt-1">
                        {T('pmi.onboarding.completedOn')}: {new Date(step.completed_at).toLocaleDateString(lang === 'en-US' ? 'en-US' : 'pt-BR')}
                      </div>
                    )}
                  </div>
                  {!done && (
                    <button
                      disabled={busyStep === step.step_key}
                      onClick={() => handleStepUpdate(step.step_key, 'completed')}
                      className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white px-3 py-1 rounded text-sm flex-shrink-0"
                    >
                      {busyStep === step.step_key ? '...' : T('pmi.onboarding.markDone')}
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {/* Pre-onboarding (avaliação) info */}
      {isInPreOnboarding && (
        <section className="bg-blue-50 border border-blue-200 rounded-xl p-6">
          <h2 className="text-lg font-semibold text-blue-900 mb-2">
            📋 {T('pmi.onboarding.evaluationPhase')}
          </h2>
          <p className="text-blue-800 text-sm">
            {T('pmi.onboarding.evaluationBody')}
          </p>
        </section>
      )}

      {/* Approved (next step → onboarding journey as member) */}
      {isApproved && (
        <section className="bg-green-50 border border-green-200 rounded-xl p-6">
          <h2 className="text-lg font-semibold text-green-900 mb-2">
            🎉 {T('pmi.onboarding.approvedTitle')}
          </h2>
          <p className="text-green-800 text-sm mb-4">
            {T('pmi.onboarding.approvedBody')}
          </p>
          <a
            href={lang === 'en-US' ? '/en/onboarding' : lang === 'es-LATAM' ? '/es/onboarding' : '/onboarding'}
            className="inline-block bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg font-medium"
          >
            {T('pmi.onboarding.goToFullOnboarding')} →
          </a>
        </section>
      )}

      {/* Video screening placeholder (requires drive integration — coming soon) */}
      <section className="bg-gray-50 border border-gray-200 rounded-xl p-6">
        <h2 className="text-lg font-semibold text-gray-700 mb-2">
          🎥 {T('pmi.onboarding.videoScreeningTitle')}
        </h2>
        <p className="text-gray-600 text-sm">
          {T('pmi.onboarding.videoScreeningSoon')}
        </p>
      </section>

      {/* Footer / contact */}
      <footer className="text-center text-sm text-gray-600 pt-6 border-t border-gray-200">
        {T('pmi.onboarding.contactFooter')}{' '}
        <a href="mailto:nucleoia@pmigo.org.br" className="underline">nucleoia@pmigo.org.br</a>
      </footer>

      {errorMsg && (
        <div className="fixed bottom-4 right-4 bg-red-100 border border-red-300 text-red-800 rounded-lg p-3 shadow-lg max-w-sm">
          <div className="font-bold text-sm">⚠️ {T('pmi.onboarding.errorTitle')}</div>
          <div className="text-xs mt-1 break-words">{errorMsg}</div>
          <button onClick={() => setErrorMsg(null)} className="text-xs underline mt-1">×</button>
        </div>
      )}
    </div>
  );
}
