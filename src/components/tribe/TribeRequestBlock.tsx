import { useState, useEffect, useCallback } from 'react';

// Tribe Selection Híbrida — PR2 (researcher-facing). See docs/specs/SPEC_TRIBE_SELECTION_HYBRID.md §5.
//
// Continuous post-promotion tribe entry: a promoted researcher who signed the volunteer term but
// has no tribe yet picks a tribe + writes a motivation (>= 50 chars) and submits a request. The
// tribe leader (or GP) approves it (PR3 / review_tribe_request) -> the bridge trigger sets
// members.tribe_id. The legacy batch select_tribe is frozen (deadline closed); this is the new path.
//
// ONE read powers the island: get_my_tribe_request_context() returns { eligible, pending, tribes }.
//   - pending present  -> "awaiting leader" state (the request was already sent).
//   - eligible + tribes -> the picker.
//   - otherwise         -> render nothing (member has a tribe, isn't termed, is a guest, etc.).
// Eligibility is server-truthed (mirrors request_tribe_assignment's gates) so the picker never
// shows for someone the write RPC would reject. Slot capacity is deferred (PM, SPEC §4.5) — the
// picker does not show counts or block on "full".
//
// Live cohort today = 0 (every active researcher already has a tribe); this island lights up for
// the future promoted-guest cohort. No localStorage dismiss: needing a tribe is not optional noise.

const MIN_MESSAGE = 50;

function formatDate(iso: string, lang: string): string {
  try {
    return new Date(iso).toLocaleDateString(lang, { day: '2-digit', month: 'short', year: 'numeric' });
  } catch {
    return iso;
  }
}

interface TribeOption {
  tribe_id: number;
  title: string;
}
interface PendingRequest {
  invitation_id: string; // #1255: needed to cancel this exact pending request
  tribe_id: number;
  title: string;
  message: string;
  created_at: string;
  expires_at: string;
}
interface Context {
  eligible: boolean;
  // #1139: when eligible=false, the server names WHY so we render an explicit empty-state (never blank).
  ineligible_reason?: 'no_member' | 'inactive' | 'has_tribe' | 'pending_term' | 'ineligible' | null;
  current_tribe_title?: string | null;
  pending: PendingRequest | null;
  tribes: TribeOption[];
}

interface Copy {
  ariaLabel: string;
  pickTitle: string;
  pickBody: string;
  tribeLegend: string;
  messageLabel: string;
  messagePlaceholder: string;
  charsLeft: (n: number) => string;
  submitHint: string;
  submit: string;
  submitting: string;
  pendingTitle: string;
  pendingBody: (title: string) => string;
  pendingExpires: (date: string) => string;
  pendingExpiryNote: string;
  pendingYourMessage: string;
  // #1255: self-service cancel of a pending request (invitee re-picks a tribe)
  cancelRequest: string;
  cancelConfirmPrompt: string;
  cancelConfirm: string;
  cancelBack: string;
  cancelling: string;
  toastCancelled: string;
  emptyTitle: string;
  emptyBody: string;
  // #1139 ineligibility empty-states
  termTitle: string;
  termBody: string;
  termCta: string;
  hasTribeTitle: string;
  hasTribeBody: (title: string | null) => string;
  toastSent: string;
  toastError: string;
}

const COPY: Record<string, Copy> = {
  'pt-BR': {
    ariaLabel: 'Pedir para entrar em uma tribo',
    pickTitle: 'Escolha sua tribo de pesquisa',
    pickBody: 'Você concluiu sua entrada no Núcleo. Escolha uma tribo e conte por que quer participar — o líder da tribo confirma seu ingresso.',
    tribeLegend: 'Tribos disponíveis',
    messageLabel: 'Por que você quer entrar nesta tribo?',
    messagePlaceholder: 'Conte sua motivação, experiência e o que pode contribuir (mín. 50 caracteres).',
    charsLeft: (n) => (n > 0 ? `Faltam ${n} caractere${n === 1 ? '' : 's'}` : 'Pronto para enviar'),
    submitHint: 'Selecione uma tribo e escreva ao menos 50 caracteres para habilitar o envio.',
    submit: 'Enviar pedido',
    submitting: 'Enviando…',
    pendingTitle: 'Pedido enviado',
    pendingBody: (title) => `Seu pedido para entrar na tribo ${title} foi enviado. Aguardando a confirmação do líder.`,
    pendingExpires: (date) => `Este pedido expira em ${date}.`,
    pendingExpiryNote: 'Se ninguém revisar até lá, o pedido expira e você poderá escolher uma tribo de novo.',
    pendingYourMessage: 'Sua mensagem',
    cancelRequest: 'Escolher outra tribo',
    cancelConfirmPrompt: 'Cancelar este pedido e escolher outra tribo?',
    cancelConfirm: 'Sim, cancelar',
    cancelBack: 'Voltar',
    cancelling: 'Cancelando…',
    toastCancelled: 'Pedido cancelado. Escolha uma tribo.',
    emptyTitle: 'Nenhuma tribo disponível',
    emptyBody: 'Não há tribos abertas para ingresso no momento. Fale com a coordenação do Núcleo.',
    termTitle: 'Assine seu termo de voluntário',
    termBody: 'Para escolher uma tribo de pesquisa, você precisa primeiro assinar o Termo de Adesão ao Serviço Voluntário. Assim que ele estiver assinado, a escolha de tribo aparece aqui.',
    termCta: 'Assinar termo de voluntário',
    hasTribeTitle: 'Você já participa de uma tribo',
    hasTribeBody: (title) => title
      ? `Você já faz parte da tribo ${title}. Para trocar de tribo, fale com a coordenação do Núcleo.`
      : 'Você já participa de uma tribo de pesquisa. Para trocar de tribo, fale com a coordenação do Núcleo.',
    toastSent: 'Pedido enviado! O líder da tribo vai revisar.',
    toastError: 'Não foi possível enviar. Tente novamente.',
  },
  'en-US': {
    ariaLabel: 'Request to join a tribe',
    pickTitle: 'Choose your research tribe',
    pickBody: 'You have completed your onboarding. Pick a tribe and tell them why you want to join — the tribe leader confirms your entry.',
    tribeLegend: 'Available tribes',
    messageLabel: 'Why do you want to join this tribe?',
    messagePlaceholder: 'Share your motivation, experience and what you can contribute (min. 50 characters).',
    charsLeft: (n) => (n > 0 ? `${n} character${n === 1 ? '' : 's'} to go` : 'Ready to send'),
    submitHint: 'Select a tribe and write at least 50 characters to enable sending.',
    submit: 'Send request',
    submitting: 'Sending…',
    pendingTitle: 'Request sent',
    pendingBody: (title) => `Your request to join the ${title} tribe was sent. Awaiting the leader's confirmation.`,
    pendingExpires: (date) => `This request expires on ${date}.`,
    pendingExpiryNote: 'If no one reviews it by then, the request expires and you can pick a tribe again.',
    pendingYourMessage: 'Your message',
    cancelRequest: 'Choose another tribe',
    cancelConfirmPrompt: 'Cancel this request and choose another tribe?',
    cancelConfirm: 'Yes, cancel',
    cancelBack: 'Back',
    cancelling: 'Cancelling…',
    toastCancelled: 'Request cancelled. Choose a tribe.',
    emptyTitle: 'No tribes available',
    emptyBody: 'There are no tribes open to join right now. Contact the Núcleo coordination.',
    termTitle: 'Sign your volunteer term',
    termBody: 'To choose a research tribe, you first need to sign the Volunteer Service Agreement. Once it is signed, tribe selection will appear here.',
    termCta: 'Sign volunteer term',
    hasTribeTitle: 'You are already in a tribe',
    hasTribeBody: (title) => title
      ? `You are already part of the ${title} tribe. To switch tribes, contact the Núcleo coordination.`
      : 'You are already part of a research tribe. To switch tribes, contact the Núcleo coordination.',
    toastSent: 'Request sent! The tribe leader will review it.',
    toastError: 'Could not send. Please try again.',
  },
  'es-LATAM': {
    ariaLabel: 'Solicitar ingreso a una tribu',
    pickTitle: 'Elige tu tribu de investigación',
    pickBody: 'Completaste tu ingreso al Núcleo. Elige una tribu y cuenta por qué quieres participar — el líder de la tribu confirma tu ingreso.',
    tribeLegend: 'Tribus disponibles',
    messageLabel: '¿Por qué quieres entrar en esta tribu?',
    messagePlaceholder: 'Cuenta tu motivación, experiencia y lo que puedes aportar (mín. 50 caracteres).',
    charsLeft: (n) => (n > 0 ? `Faltan ${n} carácter${n === 1 ? '' : 'es'}` : 'Listo para enviar'),
    submitHint: 'Selecciona una tribu y escribe al menos 50 caracteres para habilitar el envío.',
    submit: 'Enviar solicitud',
    submitting: 'Enviando…',
    pendingTitle: 'Solicitud enviada',
    pendingBody: (title) => `Tu solicitud para entrar en la tribu ${title} fue enviada. Esperando la confirmación del líder.`,
    pendingExpires: (date) => `Esta solicitud expira el ${date}.`,
    pendingExpiryNote: 'Si nadie la revisa para entonces, la solicitud expira y podrás elegir una tribu de nuevo.',
    pendingYourMessage: 'Tu mensaje',
    cancelRequest: 'Elegir otra tribu',
    cancelConfirmPrompt: '¿Cancelar esta solicitud y elegir otra tribu?',
    cancelConfirm: 'Sí, cancelar',
    cancelBack: 'Volver',
    cancelling: 'Cancelando…',
    toastCancelled: 'Solicitud cancelada. Elige una tribu.',
    emptyTitle: 'No hay tribus disponibles',
    emptyBody: 'No hay tribus abiertas para unirse en este momento. Contacta a la coordinación del Núcleo.',
    termTitle: 'Firma tu término de voluntariado',
    termBody: 'Para elegir una tribu de investigación, primero debes firmar el Término de Adhesión al Servicio Voluntario. Una vez firmado, la elección de tribu aparecerá aquí.',
    termCta: 'Firmar término de voluntariado',
    hasTribeTitle: 'Ya participas en una tribu',
    hasTribeBody: (title) => title
      ? `Ya formas parte de la tribu ${title}. Para cambiar de tribu, contacta a la coordinación del Núcleo.`
      : 'Ya participas en una tribu de investigación. Para cambiar de tribu, contacta a la coordinación del Núcleo.',
    toastSent: '¡Solicitud enviada! El líder de la tribu la revisará.',
    toastError: 'No se pudo enviar. Inténtalo de nuevo.',
  },
};

interface Props {
  lang?: string;
}

export default function TribeRequestBlock({ lang = 'pt-BR' }: Props) {
  const copy = COPY[lang] || COPY['pt-BR'];
  const [ctx, setCtx] = useState<Context | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);
  // #1255: inline confirm + in-flight state for cancelling a pending request (no native dialog).
  const [confirmingCancel, setConfirmingCancel] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data, error } = await sb.rpc('get_my_tribe_request_context');
    if (error || !data || typeof data !== 'object') return;
    setCtx(data as Context);
  }, [getSb]);

  // Boot like the sibling islands: wait for the nav member, then load once.
  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  const remaining = Math.max(0, MIN_MESSAGE - message.trim().length);
  const canSubmit = selected != null && remaining === 0 && !submitting;

  const submit = useCallback(async () => {
    const sb = getSb();
    if (!sb || selected == null || message.trim().length < MIN_MESSAGE || submitting) return;
    setSubmitting(true);
    try {
      const { data, error } = await sb.rpc('request_tribe_assignment', {
        p_tribe_id: selected,
        p_message: message.trim(),
      });
      if (error || (data && data.ok === false)) throw new Error(error?.message || 'failed');
      (window as any).toast?.(copy.toastSent, 'success');
      setMessage('');
      setSelected(null);
      await load(); // re-read -> now shows the pending state
    } catch {
      (window as any).toast?.(copy.toastError, 'error');
    } finally {
      setSubmitting(false);
    }
  }, [getSb, selected, message, submitting, copy, load]);

  // #1255: cancel the pending self-request so the picker reopens (re-request is immediate; the
  // wrong-tribe request never produced a contribution, so nothing material is lost).
  const cancel = useCallback(async () => {
    const sb = getSb();
    const invitationId = ctx?.pending?.invitation_id;
    if (!sb || !invitationId || cancelling) return;
    setCancelling(true);
    try {
      const { data, error } = await sb.rpc('cancel_tribe_request', {
        p_invitation_id: invitationId,
      });
      if (error || (data && data.ok === false)) throw new Error(error?.message || 'failed');
      (window as any).toast?.(copy.toastCancelled, 'success');
      setConfirmingCancel(false);
      await load(); // re-read -> pending clears, picker reappears
    } catch {
      (window as any).toast?.(copy.toastError, 'error');
    } finally {
      setCancelling(false);
    }
  }, [getSb, ctx, cancelling, copy, load]);

  if (!ctx) return null; // loading / not hydrated

  // Pending state — the request was already sent, awaiting the leader.
  if (ctx.pending) {
    return (
      <section role="region" aria-label={copy.ariaLabel} className="mb-6">
        <div className="rounded-2xl border border-amber-300/60 bg-amber-50 dark:bg-amber-950/20 p-5">
          <div className="flex items-start gap-3">
            <svg className="w-6 h-6 text-amber-600 flex-shrink-0" fill="none" viewBox="0 0 24 24" strokeWidth="1.8" stroke="currentColor" aria-hidden="true">
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
            </svg>
            <div className="flex-1 min-w-0">
              <h2 className="text-base font-extrabold text-navy dark:text-amber-200">{copy.pendingTitle}</h2>
              <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.pendingBody(ctx.pending.title)}</p>
              {ctx.pending.expires_at && (
                <p className="text-xs text-[var(--text-secondary)] mt-1.5">
                  {copy.pendingExpires(formatDate(ctx.pending.expires_at, lang))} {copy.pendingExpiryNote}
                </p>
              )}
              <div className="mt-3 rounded-lg border border-[var(--border-subtle)] bg-[var(--surface)] p-3">
                <p className="text-xs font-semibold text-[var(--text-secondary)] uppercase tracking-wide">{copy.pendingYourMessage}</p>
                <p className="text-sm text-[var(--text-primary)] mt-1 whitespace-pre-wrap break-words">{ctx.pending.message}</p>
              </div>
              {/* #1255: self-service cancel — picked the wrong tribe? cancel + re-pick, no 72h wait. */}
              <div className="mt-3">
                {!confirmingCancel ? (
                  <button
                    type="button"
                    onClick={() => setConfirmingCancel(true)}
                    className="min-h-[44px] px-4 rounded-lg border border-amber-400/70 text-navy dark:text-amber-200 text-sm font-bold cursor-pointer hover:bg-amber-100/60 dark:hover:bg-amber-900/30"
                  >
                    {copy.cancelRequest}
                  </button>
                ) : (
                  <div className="flex flex-col sm:flex-row sm:items-center gap-2">
                    <p className="text-sm font-semibold text-[var(--text-primary)]">{copy.cancelConfirmPrompt}</p>
                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={cancel}
                        disabled={cancelling}
                        aria-disabled={cancelling}
                        className="min-h-[44px] px-4 rounded-lg bg-amber-600 text-white text-sm font-bold cursor-pointer hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {cancelling ? copy.cancelling : copy.cancelConfirm}
                      </button>
                      <button
                        type="button"
                        onClick={() => setConfirmingCancel(false)}
                        disabled={cancelling}
                        className="min-h-[44px] px-4 rounded-lg border border-[var(--border-subtle)] text-[var(--text-primary)] text-sm font-bold cursor-pointer hover:bg-[var(--surface-hover)] disabled:opacity-50"
                      >
                        {copy.cancelBack}
                      </button>
                    </div>
                    <span role="status" aria-live="assertive" className="sr-only">{cancelling ? copy.cancelling : ''}</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </section>
    );
  }

  // Not eligible — render an explicit empty-state naming the reason + next step, never a blank block.
  // #1139: the dominant case at the C4 kickoff is `pending_term` (37 researchers without a signed term).
  if (!ctx.eligible) {
    if (ctx.ineligible_reason === 'pending_term') {
      const langPrefix = (typeof window !== 'undefined' && (window as any).__LANG_PREFIX) || '';
      return (
        <section role="region" aria-label={copy.ariaLabel} className="mb-6">
          <div className="rounded-2xl border border-amber-300/60 bg-amber-50 dark:bg-amber-950/20 p-5">
            <h2 className="text-base font-extrabold text-navy dark:text-amber-200">{copy.termTitle}</h2>
            <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.termBody}</p>
            <a
              href={`${langPrefix}/volunteer-agreement`}
              className="mt-3 inline-flex items-center min-h-[44px] px-4 rounded-lg bg-navy text-white text-sm font-bold no-underline hover:opacity-90"
            >
              {copy.termCta}
            </a>
          </div>
        </section>
      );
    }
    if (ctx.ineligible_reason === 'has_tribe') {
      return (
        <section role="region" aria-label={copy.ariaLabel} className="mb-6">
          <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface)] p-5">
            <h2 className="text-base font-extrabold text-navy dark:text-teal">{copy.hasTribeTitle}</h2>
            <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.hasTribeBody(ctx.current_tribe_title || null)}</p>
          </div>
        </section>
      );
    }
    // inactive / no_member / unknown — the member is not expecting a picker; stay quiet (no noise).
    return null;
  }

  // Eligible but zero selectable tribes = platform-config gap, not a normal state: don't go blank.
  if (!ctx.tribes || ctx.tribes.length === 0) {
    return (
      <section role="region" aria-label={copy.ariaLabel} className="mb-6">
        <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface)] p-5">
          <h2 className="text-base font-extrabold text-navy dark:text-teal">{copy.emptyTitle}</h2>
          <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.emptyBody}</p>
        </div>
      </section>
    );
  }

  // Picker — eligible researcher without a tribe.

  return (
    <section role="region" aria-label={copy.ariaLabel} className="mb-6">
      <div className="rounded-2xl border border-teal/40 bg-teal/5 p-5">
        <h2 className="text-base font-extrabold text-navy dark:text-teal">{copy.pickTitle}</h2>
        <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">{copy.pickBody}</p>

        <fieldset className="mt-4">
          <legend className="text-xs font-semibold text-[var(--text-secondary)] uppercase tracking-wide mb-2">{copy.tribeLegend}</legend>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {ctx.tribes.map((tr) => (
              <label
                key={tr.tribe_id}
                className={`flex items-center gap-2 min-h-[44px] px-3 rounded-lg border cursor-pointer transition-colors focus-within:ring-2 focus-within:ring-teal/50 ${
                  selected === tr.tribe_id
                    ? 'border-teal bg-teal/10'
                    : 'border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]'
                }`}
              >
                <input
                  type="radio"
                  name="tribe-request"
                  value={tr.tribe_id}
                  checked={selected === tr.tribe_id}
                  onChange={() => setSelected(tr.tribe_id)}
                  className="accent-teal"
                />
                <span className="text-sm font-semibold text-[var(--text-primary)]">{tr.title}</span>
              </label>
            ))}
          </div>
        </fieldset>

        <div className="mt-4">
          <label htmlFor="tribe-request-message" className="block text-sm font-semibold text-[var(--text-primary)]">
            {copy.messageLabel}
          </label>
          <textarea
            id="tribe-request-message"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder={copy.messagePlaceholder}
            rows={4}
            maxLength={2000}
            className="mt-1.5 w-full rounded-lg border border-[var(--border-subtle)] bg-[var(--surface)] p-3 text-sm text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-teal/50"
          />
          <p className="mt-1 text-xs text-[var(--text-secondary)]" aria-live="polite">{copy.charsLeft(remaining)}</p>
        </div>

        <div className="mt-3">
          <button
            type="button"
            onClick={submit}
            disabled={!canSubmit}
            aria-disabled={!canSubmit}
            aria-describedby="tribe-request-hint"
            className="min-h-[44px] px-4 rounded-lg bg-teal text-white text-sm font-bold cursor-pointer hover:bg-teal/90 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {submitting ? copy.submitting : copy.submit}
          </button>
          {/* Names what's still missing so the disabled state never reads as "broken" (no hover on mobile). */}
          {!canSubmit && !submitting && (
            <p id="tribe-request-hint" className="mt-2 text-xs text-[var(--text-secondary)]">{copy.submitHint}</p>
          )}
          {/* In-flight announcement for screen readers (reliable, unlike aria-busy on a button). */}
          <span role="status" aria-live="assertive" className="sr-only">{submitting ? copy.submitting : ''}</span>
        </div>
      </div>
    </section>
  );
}
