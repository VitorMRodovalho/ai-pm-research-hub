/**
 * VerticalsSection — Cycle 4 landing, the "para quem" axis of the fused "O Modelo" section (R3).
 *
 * Renders the §5a radial hub-and-spoke as THE pitch: center = Núcleo + IA (the seam),
 * spokes = the verticals (each spoke a community/credential), the Champion → CPMAI ladder is
 * the common spine. Reads community_vertical initiatives LIVE via get_public_verticals() (B1,
 * anon-safe) — nothing is hardcoded; the diagram renders whatever verticals exist. Forming
 * verticals surface a founder CTA → capture_visitor_lead(target_vertical) (brief §4).
 *
 * R3 change: this component no longer owns a <section>/header (the parent ModelSection.astro
 * does, fusing it with the quadrants axis). It exposes only the radial + ladder + cards block.
 * No rebrand: reuses existing palette tokens; the orange accent marks the protagonista CTA.
 */
import { useEffect, useRef, useState, useCallback } from 'react';

// Inscrição oficial de voluntário = via VEP (plataforma de voluntários do PMI). Dois cadastros
// DISTINTOS: pesquisador (Pesquisador Nível 4) e líder (Líder de Iniciativa). Mesmas vagas do
// rodapé (ResourcesSection.astro) — manter sincronizado se a vaga mudar.
const VEP = {
  researcher: 'https://volunteer.pmi.org/opportunities/64967',
  leader: 'https://volunteer.pmi.org/opportunities/64966',
};

type Vertical = {
  id: string;
  title: string;
  vertical_status: 'forming' | 'open' | 'paused' | null;
  // PD-CERT scrub (mig 229): get_public_verticals() no longer returns description /
  // anchor_credential / credential_body / partner_org — the public API stays credential-free
  // and partnership-claim-free. The card describes the vertical by CONTEXT (i18n VERTICAL_DESC).
};

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

const LABELS: Record<Lang, Record<string, string>> = {
  'pt-BR': {
    hubLine1: 'Núcleo',
    hubLine2: 'IA & GP',
    hubCaption: 'a comunidade',
    ladder: 'O fio comum: IA aplicada à sua área de atuação.',
    statusForming: 'Em formação',
    statusOpen: 'Aberta',
    statusPaused: 'Pausada',
    anchorPrefix: 'Âncora',
    partnerPrefix: 'Parceria',
    ctaProtagonist: 'Seja protagonista',
    ctaResearcher: 'Candidatar-se como pesquisador',
    ctaLeader: 'Candidatar-se como líder',
    ctaSub: 'A inscrição é feita na plataforma de voluntários do PMI (VEP) — pesquisador e líder são cadastros distintos.',
    hubAria: 'Núcleo + IA, a comunidade no centro das verticais',
    radialAria: 'Diagrama radial: Núcleo + IA no centro, cada raio é uma vertical de comunidade',
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
    hubLine1: 'AI & PM',
    hubLine2: 'Research Hub',
    hubCaption: 'the community',
    ladder: 'The common thread: AI applied to your field of practice.',
    statusForming: 'Forming',
    statusOpen: 'Open',
    statusPaused: 'Paused',
    anchorPrefix: 'Anchor',
    partnerPrefix: 'Partner',
    ctaProtagonist: 'Be a protagonist',
    ctaResearcher: 'Apply as researcher',
    ctaLeader: 'Apply as leader',
    ctaSub: 'Enrollment is on the PMI volunteer platform (VEP) — researcher and leader are distinct registrations.',
    hubAria: 'Núcleo + AI, the community at the center of the verticals',
    radialAria: 'Radial diagram: Núcleo + AI at the center, each spoke is a community vertical',
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
    hubLine1: 'Núcleo',
    hubLine2: 'IA & GP',
    hubCaption: 'la comunidad',
    ladder: 'El hilo común: IA aplicada a tu área de actuación.',
    statusForming: 'En formación',
    statusOpen: 'Abierta',
    statusPaused: 'Pausada',
    anchorPrefix: 'Ancla',
    partnerPrefix: 'Alianza',
    ctaProtagonist: 'Sé protagonista',
    ctaResearcher: 'Postularse como investigador',
    ctaLeader: 'Postularse como líder',
    ctaSub: 'La inscripción se hace en la plataforma de voluntarios del PMI (VEP) — investigador y líder son registros distintos.',
    hubAria: 'Núcleo + IA, la comunidad en el centro de las verticales',
    radialAria: 'Diagrama radial: Núcleo + IA en el centro, cada radio es una vertical de comunidad',
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

/**
 * Vertical descriptions, by CONTEXT of practice — NOT by credential (PD-CERT-4, PM 2026-06-21).
 * The home presents verticals as research themes the practitioner recognizes by context; the PMI
 * credential + knowledge area stay IMPLICIT (never written) to avoid reading as a certification
 * funnel (conflict with PMI certification boards) and because they are research themes, not tracks.
 * Authored here in all 3 langs (credential-free) so the FE NEVER renders the DB `description`
 * (which embeds "ancorada na credencial PMI-X") nor `anchor_credential` — this also localizes the
 * cards in en/es (was GAP-B2.C: DB prose is pt-only). Keyed by the live DB `title`; unknown title
 * → suppressed (never falls back to the credential-bearing DB description). CPMAI stays explicit
 * (the common spine line below). DB/RPC payload scrub: DONE (mig 229) — get_public_verticals()
 * no longer returns anchor_credential/credential_body/description/partner_org.
 */
const VERTICAL_DESC: Record<Lang, Record<string, string>> = {
  'pt-BR': {
    'Ágil': 'IA aplicada à gestão adaptativa e a times ágeis.',
    'Construção': 'IA aplicada a megaprojetos e à gestão na construção.',
    'ESG': 'IA aplicada à sustentabilidade e ao impacto ESG em projetos.',
    'Negócio': 'IA aplicada à análise de negócio e à geração de valor.',
    'PMO': 'IA aplicada a escritórios de projetos e à gestão de portfólio.',
  },
  'en-US': {
    'Ágil': 'AI applied to adaptive management and agile teams.',
    'Construção': 'AI applied to megaprojects and construction management.',
    'ESG': 'AI applied to sustainability and ESG impact in projects.',
    'Negócio': 'AI applied to business analysis and value generation.',
    'PMO': 'AI applied to project offices and portfolio management.',
  },
  'es-LATAM': {
    'Ágil': 'IA aplicada a la gestión adaptativa y a equipos ágiles.',
    'Construção': 'IA aplicada a megaproyectos y a la gestión en construcción.',
    'ESG': 'IA aplicada a la sostenibilidad y al impacto ESG en proyectos.',
    'Negócio': 'IA aplicada al análisis de negocio y a la generación de valor.',
    'PMO': 'IA aplicada a oficinas de proyectos y a la gestión de portafolio.',
  },
};

function verticalDesc(lang: Lang, title: string): string | null {
  return (VERTICAL_DESC[lang] || VERTICAL_DESC['pt-BR'])[title] ?? null;
}

function statusLabel(l: Record<string, string>, s: string | null): string {
  if (s === 'open') return l.statusOpen;
  if (s === 'paused') return l.statusPaused;
  return l.statusForming;
}

/**
 * Radial hub-and-spoke (§5a) — center = Núcleo + IA, spokes radiate to live vertical nodes.
 * Read-only pitch visual; the actionable layer (CTA/founder form) is the cards below. Nodes are
 * placed by trig around a circle (first node at top, -90°); SVG lines draw the spokes behind.
 * Desktop only — on mobile the diagram collapses to the center node + stacked cards (the spokes
 * read poorly on narrow screens). 1 vertical today renders as center + 1 node (honest, grows).
 */
function Radial({ verticals, l }: { verticals: Vertical[]; l: Record<string, string> }) {
  const n = verticals.length;
  const cx = 50;
  const cy = 50;
  const R = 34; // node-ring radius in viewBox units
  const nodes = verticals.map((v, i) => {
    const ang = ((-90 + i * (360 / Math.max(n, 1))) * Math.PI) / 180;
    return { v, x: cx + R * Math.cos(ang), y: cy + R * Math.sin(ang) };
  });

  return (
    <div
      className="relative mx-auto mb-2 hidden sm:block w-full max-w-[460px] aspect-square"
      role="img"
      aria-label={l.radialAria}
    >
      {/* spokes */}
      <svg viewBox="0 0 100 100" className="absolute inset-0 w-full h-full overflow-visible" aria-hidden="true">
        {nodes.map((nd, i) => (
          <line
            key={i}
            x1={cx}
            y1={cy}
            x2={nd.x}
            y2={nd.y}
            stroke="var(--border-default)"
            strokeWidth={0.5}
          />
        ))}
      </svg>

      {/* center — the seam */}
      <div
        className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-32 h-32 rounded-full flex flex-col items-center justify-center text-center shadow-md z-10"
        style={{ background: 'radial-gradient(circle at 50% 35%, #00799E, #074a63)' }}
      >
        <span className="text-white font-extrabold text-[.92rem] leading-tight">{l.hubLine1}</span>
        <span className="text-white font-extrabold text-[.92rem] leading-tight">{l.hubLine2}</span>
        <span className="text-white/80 text-[.55rem] uppercase tracking-widest mt-1">{l.hubCaption}</span>
      </div>

      {/* spoke nodes — each a community/credential */}
      {nodes.map((nd, i) => (
        <div
          key={i}
          className="absolute -translate-x-1/2 -translate-y-1/2 z-20 w-[124px]"
          style={{ left: `${nd.x}%`, top: `${nd.y}%` }}
        >
          <div
            className="rounded-xl border border-[var(--border-subtle)] bg-[var(--surface-card)] px-3 py-2 text-center shadow-sm"
            style={{ borderTop: '3px solid #FF610F' }}
          >
            <div className="font-bold text-[.8rem] leading-tight text-[var(--text-primary)]">{nd.v.title}</div>
            {/* PD-CERT-4: credential (anchor_credential) is implicit — not rendered. */}
            <span
              className={`inline-block mt-1 text-[.55rem] font-bold tracking-wide uppercase px-1.5 py-0.5 rounded-full border ${STATUS_STYLE[nd.v.vertical_status || 'forming'] || STATUS_STYLE.forming}`}
            >
              {statusLabel(l, nd.v.vertical_status)}
            </span>
          </div>
        </div>
      ))}
    </div>
  );
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
          className="px-5 py-2 rounded-xl font-semibold text-sm text-white border-0 cursor-pointer disabled:opacity-50 bg-[var(--color-orange-deep)]">
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

function VerticalCard({ v, l, lang }: { v: Vertical; l: Record<string, string>; lang: Lang }) {
  const isForming = v.vertical_status === 'forming';
  const sStyle = STATUS_STYLE[v.vertical_status || 'forming'] || STATUS_STYLE.forming;

  return (
    <div className="relative p-6 rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] w-full sm:w-[340px]"
      style={{ borderTop: '4px solid #FF610F' }}>
      <div className="flex items-center gap-2 mb-2 flex-wrap">
        <span className={`text-[.62rem] font-bold tracking-wide uppercase px-2 py-0.5 rounded-full border ${sStyle}`}>
          {statusLabel(l, v.vertical_status)}
        </span>
        {/* PD-CERT-4: the PMI credential (anchor_credential) stays IMPLICIT — not rendered as a chip. */}
      </div>
      <h3 className="font-bold text-lg text-[var(--text-primary)] mb-1">{v.title}</h3>
      {/* PD-CERT-4 + GAP-B2.C: description by CONTEXT of practice, authored credential-free in all 3
          langs (VERTICAL_DESC). NEVER renders the DB `description` (it embeds the PMI credential). */}
      {verticalDesc(lang, v.title) && <p className="text-sm text-[var(--text-secondary)] mb-2">{verticalDesc(lang, v.title)}</p>}
      {/* partner_org NOT rendered: claiming "Parceria: Global Construction Ambassadors" without a
          signed agreement is an unsubstantiated partnership claim (same paper-trail rule as
          co-branding). Members may individually be ambassadors, but the org has no formal accord.
          Re-enable per-vertical only when backed by a signed instrument. DB scrub: DONE (mig 229). */}
      {/* CTA → VEP (inscrição oficial). Dois cadastros distintos: pesquisador + líder. Substitui o
          antigo formulário de lead (FounderForm dead-code abaixo — limpeza trivial pendente). */}
      {isForming && (
        <div className="mt-3 flex flex-col gap-2">
          <div className="flex flex-wrap gap-2">
            <a href={VEP.researcher} target="_blank" rel="noopener"
              className="inline-flex items-center gap-1 px-4 py-2 rounded-xl font-semibold text-sm text-white no-underline cursor-pointer bg-[var(--color-orange-deep)]">
              {l.ctaResearcher} →
            </a>
            <a href={VEP.leader} target="_blank" rel="noopener"
              className="inline-flex items-center gap-1 px-4 py-2 rounded-xl font-semibold text-sm text-teal no-underline cursor-pointer border border-teal/40 hover:bg-teal/5 transition-colors">
              {l.ctaLeader} →
            </a>
          </div>
          <p className="text-xs text-[var(--text-secondary)]">{l.ctaSub}</p>
        </div>
      )}
    </div>
  );
}

export default function VerticalsSection({ lang = 'pt-BR' }: { lang?: Lang }) {
  const l = LABELS[lang] || LABELS['pt-BR'];
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
    <div className="mt-4">
      {/* Para quem — the verticals. Radial hub-and-spoke is the pitch; cards carry the CTA. */}
      {verticals === null && (
        <div className="flex flex-wrap justify-center gap-5" aria-busy="true">
          <div className="w-full sm:w-[340px] h-40 rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] animate-pulse" />
        </div>
      )}

      {verticals !== null && verticals.length === 0 && (
        <div className="flex flex-col items-center">
          {/* center node alone — the seam still reads even with no verticals yet */}
          <div role="img" aria-label={l.hubAria}
            className="relative w-32 h-32 rounded-full flex flex-col items-center justify-center text-center shadow-md mb-4"
            style={{ background: 'radial-gradient(circle at 50% 35%, #00799E, #074a63)' }}>
            <span className="text-white font-extrabold text-[.92rem] leading-tight">{l.hubLine1}</span>
            <span className="text-white font-extrabold text-[.92rem] leading-tight">{l.hubLine2}</span>
            <span className="text-white/80 text-[.55rem] uppercase tracking-widest mt-1">{l.hubCaption}</span>
          </div>
          <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-card)] p-6 text-sm text-[var(--text-secondary)] text-center max-w-[560px]">
            {l.empty}
          </div>
        </div>
      )}

      {verticals !== null && verticals.length > 0 && (
        <>
          {/* desktop: radial diagram. mobile: center node only (cards stack below) */}
          <Radial verticals={verticals} l={l} />
          <div className="flex sm:hidden flex-col items-center mb-4">
            <div role="img" aria-label={l.hubAria}
              className="relative w-28 h-28 rounded-full flex flex-col items-center justify-center text-center shadow-md"
              style={{ background: 'radial-gradient(circle at 50% 35%, #00799E, #074a63)' }}>
              <span className="text-white font-extrabold text-[.78rem] leading-tight">{l.hubLine1}</span>
              <span className="text-white font-extrabold text-[.78rem] leading-tight">{l.hubLine2}</span>
              <span className="text-white/80 text-[.5rem] uppercase tracking-widest mt-1">{l.hubCaption}</span>
            </div>
          </div>

          {/* the common spine — the ladder every vertical shares */}
          <p className="text-xs text-[var(--text-secondary)] text-center max-w-[620px] mx-auto mb-8">{l.ladder}</p>

          {/* actionable layer: the cards with the protagonista CTA */}
          <div className="flex flex-wrap justify-center gap-5">
            {verticals.map(v => <VerticalCard key={v.id} v={v} l={l} lang={lang} />)}
          </div>
        </>
      )}
    </div>
  );
}
