/**
 * VerticalsSection — Cycle 4 landing bloco 3 (hub-and-spoke) + bloco 6 (CTA "Seja protagonista").
 *
 * Reads community_vertical initiatives LIVE via get_public_verticals() (B1, anon-safe). The
 * hub-and-spoke diagram IS the pitch (brief §5a): center = Núcleo + IA (the seam), spokes =
 * the verticals, the Champion → CPMAI ladder is the common spine. Nothing is hardcoded — the
 * diagram renders whatever verticals exist (1 today: Construção, em formação). Forming verticals
 * surface a founder CTA → capture_visitor_lead(target_vertical) (brief §4). No rebrand: reuses
 * existing palette tokens; the orange accent (already in the system) marks the protagonista CTA.
 */
import { useEffect, useRef, useState, useCallback } from 'react';

type Vertical = {
  id: string;
  title: string;
  description: string | null;
  vertical_status: 'forming' | 'open' | 'paused' | null;
  anchor_credential: string | null;
  credential_body: string | null;
  partner_org: string | null;
};

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

const LABELS: Record<Lang, Record<string, string>> = {
  'pt-BR': {
    label: 'O MODELO',
    title: 'Verticais de comunidade, costuradas pela IA',
    subtitle:
      'Cada vertical reúne gente boa em torno de uma credencial PMI. A IA é o fio que atravessa os silos — pesquisa, desenvolvimento e networking sobre uma espinha comum.',
    hubLine1: 'Núcleo',
    hubLine2: '+ IA',
    hubCaption: 'a costura',
    ladder: 'Espinha comum: PMIxAI Champion → Grupo de Estudos CPMAI → PMI-CPMAI',
    statusForming: 'Em formação',
    statusOpen: 'Aberta',
    statusPaused: 'Pausada',
    anchorPrefix: 'Âncora',
    partnerPrefix: 'Parceria',
    ctaProtagonist: 'Seja protagonista',
    ctaSub: 'Entre na coorte fundadora — a liderança vai te chamar para confirmar.',
    hubAria: 'Núcleo + IA, a costura entre as verticais',
    empty: 'As verticais do Ciclo 4 estão sendo formadas. Em breve aqui.',
    formName: 'Nome',
    formEmail: 'E-mail',
    formMessage: 'O que te move nesta vertical? (opcional)',
    formConsent:
      'Autorizo o contato do Núcleo IA & GP sobre esta vertical, conforme a',
    formConsentLink: 'Política de Privacidade',
    formConsentRequired: 'O consentimento é obrigatório.',
    formSubmit: 'Quero fundar',
    formSubmitting: 'Enviando…',
    formSuccess: 'Recebemos seu interesse. A liderança da vertical vai te chamar.',
    formError: 'Erro ao enviar. Tente novamente.',
    cancel: 'Cancelar',
  },
  'en-US': {
    label: 'THE MODEL',
    title: 'Community verticals, stitched together by AI',
    subtitle:
      'Each vertical gathers good people around a PMI credential. AI is the thread that crosses the silos — research, development and networking over one common spine.',
    hubLine1: 'Núcleo',
    hubLine2: '+ AI',
    hubCaption: 'the seam',
    ladder: 'Common spine: PMIxAI Champion → CPMAI Study Group → PMI-CPMAI',
    statusForming: 'Forming',
    statusOpen: 'Open',
    statusPaused: 'Paused',
    anchorPrefix: 'Anchor',
    partnerPrefix: 'Partner',
    ctaProtagonist: 'Be a protagonist',
    ctaSub: 'Join the founding cohort — the leadership will reach out to confirm.',
    hubAria: 'Núcleo + AI, the seam across the verticals',
    empty: 'The Cycle 4 verticals are being formed. Coming soon.',
    formName: 'Name',
    formEmail: 'Email',
    formMessage: 'What draws you to this vertical? (optional)',
    formConsent: 'I authorize Núcleo IA & GP to contact me about this vertical, per the',
    formConsentLink: 'Privacy Policy',
    formConsentRequired: 'Consent is required.',
    formSubmit: 'I want to found it',
    formSubmitting: 'Sending…',
    formSuccess: 'We got your interest. The vertical leadership will reach out.',
    formError: 'Failed to send. Please try again.',
    cancel: 'Cancel',
  },
  'es-LATAM': {
    label: 'EL MODELO',
    title: 'Verticales de comunidad, cosidas por la IA',
    subtitle:
      'Cada vertical reúne buena gente en torno a una credencial PMI. La IA es el hilo que atraviesa los silos — investigación, desarrollo y networking sobre una espina común.',
    hubLine1: 'Núcleo',
    hubLine2: '+ IA',
    hubCaption: 'la costura',
    ladder: 'Espina común: PMIxAI Champion → Grupo de Estudio CPMAI → PMI-CPMAI',
    statusForming: 'En formación',
    statusOpen: 'Abierta',
    statusPaused: 'Pausada',
    anchorPrefix: 'Ancla',
    partnerPrefix: 'Alianza',
    ctaProtagonist: 'Sé protagonista',
    ctaSub: 'Únete a la cohorte fundadora — el liderazgo te contactará para confirmar.',
    hubAria: 'Núcleo + IA, la costura entre las verticales',
    empty: 'Las verticales del Ciclo 4 se están formando. Pronto aquí.',
    formName: 'Nombre',
    formEmail: 'Correo',
    formMessage: '¿Qué te mueve en esta vertical? (opcional)',
    formConsent: 'Autorizo el contacto de Núcleo IA & GP sobre esta vertical, según la',
    formConsentLink: 'Política de Privacidad',
    formConsentRequired: 'El consentimiento es obligatorio.',
    formSubmit: 'Quiero fundarla',
    formSubmitting: 'Enviando…',
    formSuccess: 'Recibimos tu interés. El liderazgo de la vertical te contactará.',
    formError: 'Error al enviar. Inténtalo de nuevo.',
    cancel: 'Cancelar',
  },
};

const STATUS_STYLE: Record<string, string> = {
  forming: 'bg-orange/10 text-orange border-orange/30',
  open: 'bg-emerald-500/10 text-emerald-600 border-emerald-500/30',
  paused: 'bg-gray-400/10 text-gray-500 border-gray-400/30',
};

function statusLabel(l: Record<string, string>, s: string | null): string {
  if (s === 'open') return l.statusOpen;
  if (s === 'paused') return l.statusPaused;
  return l.statusForming;
}

function FounderForm({ vertical, l, lp, onClose }: { vertical: Vertical; l: Record<string, string>; lp: string; onClose: () => void }) {
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
      const params = new URLSearchParams(window.location.search);
      const utm: Record<string, string> = {};
      for (const k of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content']) {
        const v = params.get(k); if (v) utm[k] = v;
      }
      const refMember = params.get('ref') || params.get('referrer');
      const payload: Record<string, unknown> = {
        name: form.name,
        email: form.email,
        message: form.message || null,
        role_interest: 'founder',
        target_vertical: vertical.id,
        lgpd_consent: true,
        source: utm.utm_source ? `vertical:${utm.utm_source}` : 'vertical-cta',
      };
      if (Object.keys(utm).length > 0) payload.utm_data = utm;
      if (refMember) payload.referrer_member_id = refMember;
      const { data, error } = await sb.rpc('capture_visitor_lead', { p_payload: payload });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      setStatus('success');
      try { (window as any).__nucleoTrack?.('vertical_founder_interest', { vertical: vertical.title }); } catch { /* noop */ }
    } catch {
      setStatus('error');
    }
  }, [form, vertical]);

  if (status === 'success') {
    return (
      <div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-4 text-center">
        <div className="text-2xl mb-1">✅</div>
        <p className="text-sm font-semibold text-emerald-700">{l.formSuccess}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 space-y-3 rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <input ref={nameRef} type="text" required placeholder={l.formName} value={form.name}
          onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
          className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
        <input type="email" required placeholder={l.formEmail} value={form.email}
          onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
          className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
      </div>
      <textarea rows={2} placeholder={l.formMessage} value={form.message}
        onChange={e => setForm(f => ({ ...f, message: e.target.value }))}
        className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)] resize-y" />
      <label className={`flex items-start gap-2 cursor-pointer ${consentError ? 'text-red-600' : ''}`}>
        <input type="checkbox" checked={form.lgpd_consent}
          onChange={e => { setForm(f => ({ ...f, lgpd_consent: e.target.checked })); setConsentError(false); }}
          className="mt-0.5 flex-shrink-0" />
        <span className="text-xs text-[var(--text-secondary)]">
          {l.formConsent}{' '}
          <a href={`${lp}/privacy`} target="_blank" rel="noopener" className="text-teal underline">{l.formConsentLink}</a>.
        </span>
      </label>
      {consentError && <p className="text-xs text-red-600">{l.formConsentRequired}</p>}
      <div className="flex items-center gap-2">
        <button type="submit" disabled={status === 'submitting'}
          className="px-5 py-2 rounded-xl font-semibold text-sm text-white border-0 cursor-pointer disabled:opacity-50 bg-orange">
          {status === 'submitting' ? l.formSubmitting : l.formSubmit}
        </button>
        <button type="button" onClick={onClose}
          className="px-3 py-2 rounded-xl text-sm text-[var(--text-secondary)] bg-transparent border border-[var(--border-default)] cursor-pointer">
          {l.cancel}
        </button>
      </div>
      {status === 'error' && <p className="text-xs text-red-600">{l.formError}</p>}
    </form>
  );
}

function VerticalCard({ v, l, lp, lang }: { v: Vertical; l: Record<string, string>; lp: string; lang: Lang }) {
  const [open, setOpen] = useState(false);
  const isForming = v.vertical_status === 'forming';
  const sStyle = STATUS_STYLE[v.vertical_status || 'forming'] || STATUS_STYLE.forming;

  return (
    <div className={`relative p-6 rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] w-full ${open ? 'sm:w-[460px]' : 'sm:w-[340px]'}`}
      style={{ borderTop: '4px solid #FF610F' }}>
      <div className="flex items-center gap-2 mb-2 flex-wrap">
        <span className={`text-[.62rem] font-bold tracking-wide uppercase px-2 py-0.5 rounded-full border ${sStyle}`}>
          {statusLabel(l, v.vertical_status)}
        </span>
        {v.anchor_credential && (
          <span className="text-[.62rem] font-semibold text-[var(--text-secondary)] px-2 py-0.5 rounded-full border border-[var(--border-subtle)]">
            {l.anchorPrefix}: {v.anchor_credential}
          </span>
        )}
      </div>
      <h3 className="font-bold text-lg text-[var(--text-primary)] mb-1">{v.title}</h3>
      {/* description is authored in pt-BR only; suppress on /en/ /es/ rather than show wrong-language
          prose (ux M2). Localized descriptions tracked as GAP-B2.C. */}
      {v.description && lang === 'pt-BR' && <p className="text-sm text-[var(--text-secondary)] mb-2">{v.description}</p>}
      {v.partner_org && (
        <p className="text-xs text-[var(--text-secondary)] mb-1">{l.partnerPrefix}: <span className="font-medium">{v.partner_org}</span></p>
      )}
      {isForming && !open && (
        <button type="button" onClick={() => setOpen(true)}
          className="mt-3 inline-flex items-center gap-1 px-4 py-2 rounded-xl font-semibold text-sm text-white border-0 cursor-pointer bg-orange">
          {l.ctaProtagonist} →
        </button>
      )}
      {isForming && !open && <p className="text-xs text-[var(--text-secondary)] mt-1.5">{l.ctaSub}</p>}
      {isForming && open && <FounderForm vertical={v} l={l} lp={lp} onClose={() => setOpen(false)} />}
    </div>
  );
}

export default function VerticalsSection({ lang = 'pt-BR' }: { lang?: Lang }) {
  const l = LABELS[lang] || LABELS['pt-BR'];
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [verticals, setVerticals] = useState<Vertical[] | null>(null);

  useEffect(() => {
    let tries = 0;
    let cancelled = false;
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) {
        if (tries++ < 25 && !cancelled) setTimeout(load, 200);
        return;
      }
      try {
        const { data, error } = await sb.rpc('get_public_verticals');
        if (!cancelled && !error && Array.isArray(data)) setVerticals(data);
        else if (!cancelled) setVerticals([]);
      } catch {
        if (!cancelled) setVerticals([]);
      }
    };
    load();
    return () => { cancelled = true; };
  }, []);

  return (
    <section className="py-16 px-6 bg-[var(--surface-base)]" id="verticals">
      <div className="max-w-[1100px] mx-auto">
        <div className="text-[.73rem] font-bold tracking-[.15em] uppercase text-orange mb-2">{l.label}</div>
        <h2 className="text-[clamp(1.7rem,4vw,2.5rem)] font-extrabold leading-tight mb-3">{l.title}</h2>
        <p className="text-base text-[var(--text-secondary)] max-w-[760px] mb-10">{l.subtitle}</p>

        {/* Hub — the seam. The spokes (vertical cards) sit below; the ladder is the common spine. */}
        <div className="flex flex-col items-center mb-8">
          <div role="img" aria-label={l.hubAria}
            className="relative w-36 h-36 rounded-full flex flex-col items-center justify-center text-center shadow-md"
            style={{ background: 'radial-gradient(circle at 50% 35%, #00799E, #074a63)' }}>
            <span className="text-white font-extrabold text-lg leading-none">{l.hubLine1}</span>
            <span className="text-white font-extrabold text-xl leading-none">{l.hubLine2}</span>
            <span className="text-white/80 text-[.6rem] uppercase tracking-widest mt-1">{l.hubCaption}</span>
          </div>
          <div className="w-px h-8 bg-[var(--border-default)]" aria-hidden="true" />
          <p className="text-xs text-[var(--text-secondary)] text-center max-w-[560px]">{l.ladder}</p>
        </div>

        {verticals === null && (
          <div className="flex flex-wrap justify-center gap-5" aria-busy="true">
            <div className="w-full sm:w-[340px] h-40 rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] animate-pulse" />
          </div>
        )}
        {verticals !== null && verticals.length === 0 && (
          <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] p-6 text-sm text-[var(--text-secondary)] text-center">
            {l.empty}
          </div>
        )}
        {verticals !== null && verticals.length > 0 && (
          <div className="flex flex-wrap justify-center gap-5">
            {verticals.map(v => <VerticalCard key={v.id} v={v} l={l} lp={lp} lang={lang} />)}
          </div>
        )}
      </div>
    </section>
  );
}
