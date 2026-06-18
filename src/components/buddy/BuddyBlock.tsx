import { useState, useEffect, useCallback, useRef } from 'react';

// #766 H5 buddy/padrinho — PR2 (light social pointer). CANONICAL component: the future
// post-promotion journey (H1) IMPORTS this block, it does NOT recreate it (SPEC §6 / Q5).
//
// Reads get_my_buddy() (the canonical FE read from PR1) and renders, for the signed-in member:
//   - afilhado side (SPEC §6 a/b): silent | pending offer card [Accept]/[Not now] | accepted pointer
//   - padrino side (SPEC §3 step 4): "you are X's buddy" confirmation + pending offers with withdraw
//
// Deliberately NOT routed through the global MilestoneCelebration island: an offer is a DECISION
// (not a celebration) and the pointer PERSISTS (not ephemeral) — mixing them causes card fatigue
// (ux-leader, SPEC §6). Mounted inline on /workspace, below the onboarding block.
//
// WhatsApp is exposed by get_my_buddy ONLY under the double gate (share_whatsapp AND accepted);
// when null we fall back to the tribe group link surface (the member's own /tribe page).

interface BuddyCopy {
  offerTitle: string;       // {name}
  offerBody: string;
  offerAccept: string;
  offerDecline: string;
  pointerTitle: string;
  pointerBody: string;      // {name}
  pointerWhatsapp: string;
  pointerFallback: string;
  padrinoConfirmed: string; // {name}
  padrinoPending: string;   // {name}
  padrinoRevoke: string;
  toastAccepted: string;
  toastDeclined: string;
  toastRevoked: string;
  toastError: string;
}

interface AsAfilhado {
  pairing_id: string;
  status: 'offered' | 'accepted';
  message: string | null;
  padrino_id: string;
  padrino_name: string;
  padrino_whatsapp: string | null;
}
interface AsPadrino {
  pairing_id: string;
  status: 'offered' | 'accepted';
  afilhado_id: string;
  afilhado_name: string;
  afilhado_whatsapp: string | null;
}
interface BuddyData {
  as_afilhado: AsAfilhado | null;
  as_padrino: AsPadrino[];
}

interface Props {
  lang?: string;
  copy: BuddyCopy;
}

// wa.me link from a raw phone — mirrors resolve_whatsapp_link's digits-only clean.
function waLink(phone: string): string {
  return 'https://wa.me/' + phone.replace(/\D/g, '');
}

function fill(template: string, name: string): string {
  return template.replace('{name}', name);
}

export default function BuddyBlock({ lang = 'pt-BR', copy }: Props) {
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [data, setData] = useState<BuddyData | null>(null);
  const [busy, setBusy] = useState(false);
  const acceptRef = useRef<HTMLButtonElement>(null);
  const offerCardRef = useRef<HTMLDivElement>(null);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data: res } = await sb.rpc('get_my_buddy');
    if (res && typeof res === 'object') setData(res as BuddyData);
  }, [getSb]);

  // Boot like MilestoneCelebration/OnboardingChecklist: wait for the nav member, then load.
  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  const toast = (msg: string, kind: 'success' | 'error' | 'info' = 'success') =>
    (window as any).toast?.(msg, kind);

  const respond = useCallback(async (pairingId: string, response: 'accept' | 'decline') => {
    const sb = getSb();
    if (!sb || busy) return;
    setBusy(true);
    try {
      const { data: res, error } = await sb.rpc('respond_to_buddy_offer', {
        p_pairing_id: pairingId, p_response: response,
      });
      if (error || res?.ok === false) throw new Error(error?.message || 'failed');
      // Declining is not a "success" — use the neutral info kind so it does not flash green.
      toast(response === 'accept' ? copy.toastAccepted : copy.toastDeclined,
        response === 'accept' ? 'success' : 'info');
      await load();
    } catch {
      toast(copy.toastError, 'error');
    } finally {
      setBusy(false);
    }
  }, [getSb, busy, copy, load]);

  const revoke = useCallback(async (pairingId: string) => {
    const sb = getSb();
    if (!sb || busy) return;
    setBusy(true);
    try {
      const { data: res, error } = await sb.rpc('revoke_buddy_offer', { p_pairing_id: pairingId });
      if (error || res?.ok === false) throw new Error(error?.message || 'failed');
      toast(copy.toastRevoked, 'success');
      await load();
    } catch {
      toast(copy.toastError, 'error');
    } finally {
      setBusy(false);
    }
  }, [getSb, busy, copy, load]);

  // a11y: when a pending offer appears, focus its primary action (Accept).
  const hasOffer = data?.as_afilhado?.status === 'offered';
  useEffect(() => {
    if (hasOffer) acceptRef.current?.focus();
  }, [hasOffer]);

  // a11y: Escape on a pending offer = "Not now" (decline). Guard against bubbling Escape from
  // another open dialog accidentally declining a bilateral invite — only act when focus is inside
  // the offer card, and stop propagation so it does not double-fire other Escape handlers.
  useEffect(() => {
    if (!hasOffer || !data?.as_afilhado) return;
    const pid = data.as_afilhado.pairing_id;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      if (!offerCardRef.current?.contains(document.activeElement)) return;
      e.stopPropagation();
      respond(pid, 'decline');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [hasOffer, data, respond]);

  if (!data) return null;

  const af = data.as_afilhado;
  const padrinoAccepted = (data.as_padrino || []).filter((p) => p.status === 'accepted');
  const padrinoPending = (data.as_padrino || []).filter((p) => p.status === 'offered');

  // Nothing to show → silent (the "no offer" state).
  if (!af && padrinoAccepted.length === 0 && padrinoPending.length === 0) return null;

  // Fallback contact when WhatsApp is gated/unavailable: the member's own tribe page (its
  // group-link surface). tribe_id comes from the nav member (afilhado's tribe = padrino's tribe).
  // No tribe_id (edge: member off-tribe) → no group to point to, so the CTA is suppressed.
  const myTribeId = (window as any).navGetMember?.()?.tribe_id ?? null;
  const fallbackHref = myTribeId ? `${lp}/tribe/${myTribeId}` : null;

  return (
    <section role="region" aria-label={copy.pointerTitle} className="space-y-3">
      {/* (b) Pending offer to me — a decision card. */}
      {af && af.status === 'offered' && (
        <div ref={offerCardRef} aria-busy={busy} className="rounded-2xl border-2 border-amber-300 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 p-5">
          <h2 className="text-base font-extrabold text-amber-800 dark:text-amber-200">
            {fill(copy.offerTitle, af.padrino_name)}
          </h2>
          <p className="text-sm text-amber-800/90 dark:text-amber-200/90 mt-1.5 leading-relaxed">
            {copy.offerBody}
          </p>
          <div className="mt-3 flex items-center gap-2 flex-wrap">
            <button
              ref={acceptRef}
              onClick={() => respond(af.pairing_id, 'accept')}
              disabled={busy}
              className="min-h-[44px] px-4 rounded-lg bg-amber-600 text-white text-sm font-bold cursor-pointer border-0 hover:bg-amber-700 disabled:opacity-50"
            >
              {copy.offerAccept}
            </button>
            <button
              onClick={() => respond(af.pairing_id, 'decline')}
              disabled={busy}
              className="min-h-[44px] px-4 rounded-lg border border-amber-300 dark:border-amber-700 text-amber-700 dark:text-amber-300 text-sm font-semibold cursor-pointer bg-transparent hover:bg-amber-100/50 disabled:opacity-50"
            >
              {copy.offerDecline}
            </button>
          </div>
        </div>
      )}

      {/* (a) Accepted pointer — name + WhatsApp (double-gated) or tribe-group fallback. */}
      {af && af.status === 'accepted' && (
        <div className="rounded-2xl border-2 border-teal/40 bg-teal/5 p-5">
          <h2 className="text-base font-extrabold text-navy dark:text-teal">{copy.pointerTitle}</h2>
          <p className="text-sm text-[var(--text-secondary)] mt-1.5 leading-relaxed">
            {fill(copy.pointerBody, af.padrino_name)}
          </p>
          {(af.padrino_whatsapp || fallbackHref) && (
            <div className="mt-3">
              <a
                href={af.padrino_whatsapp ? waLink(af.padrino_whatsapp) : fallbackHref!}
                target={af.padrino_whatsapp ? '_blank' : undefined}
                rel={af.padrino_whatsapp ? 'noopener noreferrer' : undefined}
                className="min-h-[44px] inline-flex items-center px-4 rounded-lg bg-[#25D366]/10 text-[#1da851] text-sm font-bold no-underline hover:bg-[#25D366]/20"
              >
                {af.padrino_whatsapp ? copy.pointerWhatsapp : copy.pointerFallback}
              </a>
            </div>
          )}
        </div>
      )}

      {/* Padrino side: confirmations + pending offers I sent (SPEC §3 step 4). */}
      {(padrinoAccepted.length > 0 || padrinoPending.length > 0) && (
        <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] p-5 space-y-2.5">
          {padrinoAccepted.map((p) => (
            <div key={p.pairing_id} className="flex items-center justify-between gap-2 flex-wrap text-sm">
              <span className="text-[var(--text-primary)] font-medium">
                {fill(copy.padrinoConfirmed, p.afilhado_name)}
              </span>
              {p.afilhado_whatsapp && (
                <a
                  href={waLink(p.afilhado_whatsapp)}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label={`${copy.pointerWhatsapp} — ${p.afilhado_name}`}
                  className="min-h-[44px] inline-flex items-center px-3 rounded-lg bg-[#25D366]/10 text-[#1da851] text-xs font-bold no-underline hover:bg-[#25D366]/20"
                >
                  {copy.pointerWhatsapp}
                </a>
              )}
            </div>
          ))}
          {padrinoPending.map((p) => (
            <div key={p.pairing_id} className="flex items-center justify-between gap-2 flex-wrap text-sm">
              <span className="text-[var(--text-secondary)]">
                {fill(copy.padrinoPending, p.afilhado_name)}
              </span>
              <button
                onClick={() => revoke(p.pairing_id)}
                disabled={busy}
                className="min-h-[44px] px-3 rounded-lg border border-[var(--border-subtle)] text-[var(--text-secondary)] text-xs font-semibold cursor-pointer bg-transparent hover:bg-[var(--surface-hover)] disabled:opacity-50"
              >
                {copy.padrinoRevoke}
              </button>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
