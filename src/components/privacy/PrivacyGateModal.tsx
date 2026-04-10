import { useState, useEffect } from 'react';

/**
 * PrivacyGateModal — runs on every authenticated page load.
 * Checks check_my_privacy_status() and shows 2 possible modals:
 *   1. NEEDS_CONSENT → user must accept the privacy policy (blocks dismissal)
 *   2. NEEDS_REVALIDATION → user should confirm their data is still correct (dismissable)
 *
 * Priorities: consent first, then revalidation.
 * Only shows once per session (stored in sessionStorage).
 */

interface PrivacyStatus {
  current_version: string;
  accepted_version: string | null;
  accepted_at: string | null;
  last_reviewed_at: string | null;
  needs_consent: boolean;
  needs_revalidation: boolean;
}

const SESSION_KEY_CONSENT_SHOWN = 'nia_consent_shown_v1';
const SESSION_KEY_REVAL_SHOWN = 'nia_revalidation_shown_v1';

export default function PrivacyGateModal({ lang = 'pt-BR' }: { lang?: string }) {
  const [status, setStatus] = useState<PrivacyStatus | null>(null);
  const [show, setShow] = useState<'consent' | 'revalidation' | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const boot = async () => {
      // Wait for nav to be ready
      const sb = (window as any).navGetSb?.();
      const member = (window as any).navGetMember?.();
      if (!sb || !member) {
        setTimeout(boot, 600);
        return;
      }
      try {
        const { data } = await sb.rpc('check_my_privacy_status');
        if (!data || data.error) return;
        setStatus(data);

        // Decide which modal to show (consent > revalidation)
        if (data.needs_consent && !sessionStorage.getItem(SESSION_KEY_CONSENT_SHOWN)) {
          setShow('consent');
        } else if (data.needs_revalidation && !sessionStorage.getItem(SESSION_KEY_REVAL_SHOWN)) {
          setShow('revalidation');
        }
      } catch (_) { /* silent */ }
    };
    boot();
  }, []);

  const acceptConsent = async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb || !status) return;
    setSubmitting(true);
    try {
      const { data, error } = await sb.rpc('accept_privacy_consent', { p_version: status.current_version });
      if (error || data?.error) {
        (window as any).toast?.('Erro ao registrar consentimento', 'error');
        return;
      }
      sessionStorage.setItem(SESSION_KEY_CONSENT_SHOWN, '1');
      sessionStorage.setItem(SESSION_KEY_REVAL_SHOWN, '1'); // consent also marks review
      (window as any).toast?.('Consentimento registrado ✓', 'success');
      setShow(null);
    } finally {
      setSubmitting(false);
    }
  };

  const confirmRevalidation = async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    setSubmitting(true);
    try {
      await sb.rpc('mark_my_data_reviewed');
      sessionStorage.setItem(SESSION_KEY_REVAL_SHOWN, '1');
      (window as any).toast?.('Dados confirmados ✓', 'success');
      setShow(null);
    } finally {
      setSubmitting(false);
    }
  };

  const dismissRevalidation = () => {
    sessionStorage.setItem(SESSION_KEY_REVAL_SHOWN, '1');
    setShow(null);
  };

  if (!show || !status) return null;

  if (show === 'consent') {
    return (
      <div className="fixed inset-0 bg-black/70 z-[9999] flex items-center justify-center p-4">
        <div className="bg-[var(--surface-card)] rounded-2xl max-w-lg w-full p-6 shadow-2xl">
          <div className="flex items-start gap-3 mb-4">
            <span className="text-3xl">🔒</span>
            <div>
              <h2 className="text-lg font-extrabold text-navy">Política de Privacidade</h2>
              <p className="text-xs text-[var(--text-muted)] mt-0.5">Versão {status.current_version} · LGPD Lei 13.709/2018</p>
            </div>
          </div>

          <div className="text-sm text-[var(--text-secondary)] space-y-3 mb-5 leading-relaxed">
            <p>
              Para continuar usando o Núcleo, você precisa aceitar nossa <strong>Política de Privacidade</strong>, que explica:
            </p>
            <ul className="list-disc list-inside space-y-1 text-[13px]">
              <li>Quais dados pessoais coletamos (nome, email, telefone, endereço, etc.) e <strong>por quê</strong></li>
              <li>Como usamos seus dados (apenas para Termo de Voluntariado, comunicação e reconhecimento)</li>
              <li>Seus direitos LGPD (acesso, correção, exclusão, portabilidade)</li>
              <li>O que <strong>não fazemos</strong> (não vendemos, não compartilhamos, não usamos para marketing)</li>
            </ul>
            <p className="text-[13px] bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg p-3">
              ⚠️ Coletamos apenas o mínimo necessário. Nunca pedimos CPF, RG, renda, religião ou dados sensíveis.
            </p>
          </div>

          <div className="flex flex-col sm:flex-row gap-2 items-center">
            <a
              href="/privacy"
              target="_blank"
              rel="noopener"
              className="flex-1 text-center px-4 py-2.5 rounded-lg border border-navy text-navy text-sm font-semibold no-underline hover:bg-navy/5 transition-colors"
            >
              📄 Ler Política Completa
            </a>
            <button
              onClick={acceptConsent}
              disabled={submitting}
              className="flex-1 px-4 py-2.5 rounded-lg bg-navy text-white text-sm font-bold cursor-pointer border-0 hover:opacity-90 disabled:opacity-50"
            >
              {submitting ? 'Registrando...' : '✓ Li e aceito'}
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (show === 'revalidation') {
    return (
      <div className="fixed inset-0 bg-black/50 z-[9999] flex items-center justify-center p-4">
        <div className="bg-[var(--surface-card)] rounded-2xl max-w-md w-full p-6 shadow-2xl">
          <div className="flex items-start gap-3 mb-3">
            <span className="text-2xl">📋</span>
            <div>
              <h2 className="text-base font-extrabold text-navy">Revisão Anual de Dados</h2>
              <p className="text-xs text-[var(--text-muted)] mt-0.5">LGPD — transparência e confirmação</p>
            </div>
          </div>

          <p className="text-sm text-[var(--text-secondary)] mb-2 leading-relaxed">
            Já se passaram 12+ meses desde sua última revisão de dados pessoais. Por favor:
          </p>
          <ol className="text-sm text-[var(--text-primary)] space-y-1 list-decimal list-inside mb-4">
            <li>Visite <strong>Meu Perfil</strong> e confira se endereço, telefone e outros dados estão corretos</li>
            <li>Atualize o que estiver desatualizado</li>
            <li>Confirme no botão abaixo</li>
          </ol>

          <div className="flex gap-2">
            <button
              onClick={dismissRevalidation}
              className="px-4 py-2 rounded-lg border border-[var(--border-default)] text-[var(--text-secondary)] text-xs font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)]"
            >
              Mais tarde
            </button>
            <a
              href="/profile"
              className="flex-1 text-center px-4 py-2 rounded-lg border border-navy text-navy text-xs font-semibold no-underline hover:bg-navy/5"
            >
              Revisar perfil
            </a>
            <button
              onClick={confirmRevalidation}
              disabled={submitting}
              className="flex-1 px-4 py-2 rounded-lg bg-navy text-white text-xs font-bold cursor-pointer border-0 hover:opacity-90 disabled:opacity-50"
            >
              {submitting ? '...' : '✓ Meus dados estão corretos'}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return null;
}
