/**
 * PartnersSection — Cycle 4 landing, Fatia C (public partner-connection door).
 *
 * The verticals section is the door for individuals; this is the door for ORGANIZATIONS.
 * It is an INBOUND door ("seja parceiro"), NOT a partner showcase — no logos, no partner
 * names, no signed agreements ever surface here (PM decision 2026-06-19). It states the
 * value-exchange thesis (canvas §A: hubs produce strategy/talent; PMI/Núcleo produces
 * execution + governance + credential — "não competimos, fechamos o ciclo"), the ANSI
 * standard authority hook (PMI writes the standard, incl. the world's first AI standard),
 * and the IA wedge. Inbound → capture_visitor_lead({role_interest:'partner'}) → the
 * existing admin partner pipeline. LGPD consent gates the submit (same as FounderForm).
 *
 * Brand/legal invariant (cycle4 plan, Fatia C): Núcleo = porta de entrada; PMI-GO =
 * capítulo-sede e dono da relação. The copy states this explicitly. No rebrand: reuses
 * existing palette tokens (teal = institutional, orange = protagonista CTA).
 */
import { useEffect, useRef, useState, useCallback } from 'react';

type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

const LABELS: Record<Lang, Record<string, string>> = {
  'pt-BR': {
    label: 'PARCERIAS',
    title: 'Sua organização traz estratégia e talento. O Núcleo traz execução, governança e credencial.',
    subtitle:
      'Hubs de inovação e educação produzem conhecimento e gente boa. Gerir projeto é executar estratégia — e a maioria dos projetos de IA falha por gestão, não por tecnologia. Não competimos com o parceiro: fechamos o ciclo.',
    giveTitle: 'O que o Núcleo + PMI entrega',
    give1: 'Camada de execução (gestão de projeto + método CPMAI para iniciativas de IA)',
    give2: 'Motor de certificação global do PMI — credencial internacional e portável',
    give3: 'Autoridade de padrão: o PMI escreve o padrão americano (ANSI), incluindo o primeiro standard de IA aprovado pela ANSI para a profissão de projetos',
    give4: 'Máquina de pesquisa distribuída (tribos), exposição (SGPL, webinars) e política de PI conjunta',
    getTitle: 'O que procuramos no parceiro',
    get1: 'Alcance e audiência (alunos, empresas, rede)',
    get2: 'Casos reais, palestrantes e conteúdo',
    get3: 'Posicionamento em P&D, negócio ou inovação',
    get4: 'Funil de gente boa para a comunidade e as certificações',
    ownership:
      'O Núcleo é a porta única de primeiro contato. A relação é firmada via PMI-GO, capítulo-sede e dono do acordo.',
    cta: 'Seja parceiro',
    ctaSub: 'Fale com o programa de parcerias — o time vai te chamar para conversar.',
    formName: 'Seu nome',
    formEmail: 'E-mail',
    formOrg: 'Organização (opcional)',
    formMessage: 'O que você imagina construir com o Núcleo? (opcional)',
    formConsent: 'Autorizo o Núcleo IA & GP a usar meus dados (nome, e-mail e informações fornecidas) para entrar em contato sobre esta oportunidade de parceria, conforme a',
    formConsentLink: 'Política de Privacidade',
    formConsentRequired: 'O consentimento é obrigatório.',
    formSubmit: 'Quero conversar',
    formSubmitting: 'Enviando…',
    formSuccess: 'Recebemos seu interesse. O programa de parcerias vai te chamar.',
    formError: 'Erro ao enviar. Tente novamente.',
    cancel: 'Cancelar',
  },
  'en-US': {
    label: 'PARTNERSHIPS',
    title: 'Your organization brings strategy and talent. Núcleo brings execution, governance and credential.',
    subtitle:
      'Innovation and education hubs produce knowledge and good people. Managing a project is executing strategy — and most AI projects fail on management, not technology. We do not compete with the partner: we close the loop.',
    giveTitle: 'What Núcleo + PMI delivers',
    give1: 'Execution layer (project management + the CPMAI method for AI initiatives)',
    give2: "PMI's global certification engine — an international, portable credential",
    give3: 'Standard authority: PMI writes the American standard (ANSI), including the first AI standard approved by ANSI for the project profession',
    give4: 'A distributed research engine (tribes), exposure (SGPL, webinars) and a joint IP policy',
    getTitle: 'What we look for in a partner',
    get1: 'Reach and audience (students, companies, network)',
    get2: 'Real cases, speakers and content',
    get3: 'Positioning in R&D, business or innovation',
    get4: 'A pipeline of good people for the community and the certifications',
    ownership:
      'Núcleo is the single first-contact door. The relationship is signed via PMI-GO, the host chapter and owner of the agreement.',
    cta: 'Become a partner',
    ctaSub: 'Talk to the partnerships program — the team will reach out.',
    formName: 'Your name',
    formEmail: 'Email',
    formOrg: 'Organization (optional)',
    formMessage: 'What do you imagine building with Núcleo? (optional)',
    formConsent: 'I authorize Núcleo IA & GP to use my data (name, email and the information provided) to contact me about this partnership opportunity, per the',
    formConsentLink: 'Privacy Policy',
    formConsentRequired: 'Consent is required.',
    formSubmit: 'I want to talk',
    formSubmitting: 'Sending…',
    formSuccess: 'We got your interest. The partnerships program will reach out.',
    formError: 'Failed to send. Please try again.',
    cancel: 'Cancel',
  },
  'es-LATAM': {
    label: 'ALIANZAS',
    title: 'Tu organización aporta estrategia y talento. Núcleo aporta ejecución, gobernanza y credencial.',
    subtitle:
      'Los hubs de innovación y educación producen conocimiento y buena gente. Gestionar un proyecto es ejecutar estrategia — y la mayoría de los proyectos de IA fracasan por gestión, no por tecnología. No competimos con el socio: cerramos el ciclo.',
    giveTitle: 'Lo que Núcleo + PMI entrega',
    give1: 'Capa de ejecución (gestión de proyectos + el método CPMAI para iniciativas de IA)',
    give2: 'Motor de certificación global del PMI — una credencial internacional y portable',
    give3: 'Autoridad de estándar: el PMI escribe el estándar americano (ANSI), incluido el primer estándar de IA aprobado por ANSI para la profesión de proyectos',
    give4: 'Una máquina de investigación distribuida (tribus), exposición (SGPL, webinars) y una política de PI conjunta',
    getTitle: 'Lo que buscamos en un socio',
    get1: 'Alcance y audiencia (estudiantes, empresas, red)',
    get2: 'Casos reales, ponentes y contenido',
    get3: 'Posicionamiento en I+D, negocio o innovación',
    get4: 'Un flujo de buena gente para la comunidad y las certificaciones',
    ownership:
      'Núcleo es la puerta única de primer contacto. La relación se firma vía PMI-GO, capítulo-sede y dueño del acuerdo.',
    cta: 'Sé socio',
    ctaSub: 'Habla con el programa de alianzas — el equipo te contactará.',
    formName: 'Tu nombre',
    formEmail: 'Correo',
    formOrg: 'Organización (opcional)',
    formMessage: '¿Qué imaginas construir con Núcleo? (opcional)',
    formConsent: 'Autorizo a Núcleo IA & GP a usar mis datos (nombre, correo y la información proporcionada) para contactarme sobre esta oportunidad de alianza, según la',
    formConsentLink: 'Política de Privacidad',
    formConsentRequired: 'El consentimiento es obligatorio.',
    formSubmit: 'Quiero conversar',
    formSubmitting: 'Enviando…',
    formSuccess: 'Recibimos tu interés. El programa de alianzas te contactará.',
    formError: 'Error al enviar. Inténtalo de nuevo.',
    cancel: 'Cancelar',
  },
};

function PartnerForm({ l, lp, onClose }: { l: Record<string, string>; lp: string; onClose: () => void }) {
  const [form, setForm] = useState({ name: '', email: '', org: '', message: '', lgpd_consent: false });
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [consentError, setConsentError] = useState(false);
  const nameRef = useRef<HTMLInputElement>(null);

  // a11y: move focus into the form when it expands (mirrors FounderForm).
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
      // org folds into the free-text message so the admin pipeline reads it without a schema change.
      const composedMessage = [
        form.org.trim() ? `Organização: ${form.org.trim()}` : '',
        form.message.trim(),
      ].filter(Boolean).join(' — ') || null;
      const payload: Record<string, unknown> = {
        name: form.name,
        email: form.email,
        message: composedMessage,
        role_interest: 'partner',
        lgpd_consent: true,
        source: utm.utm_source ? `partner:${utm.utm_source}` : 'partner-cta',
      };
      if (Object.keys(utm).length > 0) payload.utm_data = utm;
      if (refMember) payload.referrer_member_id = refMember;
      const { data, error } = await sb.rpc('capture_visitor_lead', { p_payload: payload });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      setStatus('success');
      try { (window as any).__nucleoTrack?.('partner_interest', {}); } catch { /* noop */ }
    } catch {
      setStatus('error');
    }
  }, [form]);

  if (status === 'success') {
    return (
      <div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-4 text-center">
        <div className="text-2xl mb-1"><span role="img" aria-label="Confirmação">✅</span></div>
        <p className="text-sm font-semibold text-emerald-700">{l.formSuccess}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="mt-5 space-y-3 rounded-xl border border-[var(--border-default)] bg-[var(--surface-base)] p-4 max-w-[640px]">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div>
          <label htmlFor="partner-name" className="sr-only">{l.formName}</label>
          <input id="partner-name" ref={nameRef} type="text" required placeholder={l.formName} value={form.name}
            onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
            className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
        </div>
        <div>
          <label htmlFor="partner-email" className="sr-only">{l.formEmail}</label>
          <input id="partner-email" type="email" required placeholder={l.formEmail} value={form.email}
            onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
            className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
        </div>
      </div>
      <label htmlFor="partner-org" className="sr-only">{l.formOrg}</label>
      <input id="partner-org" type="text" placeholder={l.formOrg} value={form.org}
        onChange={e => setForm(f => ({ ...f, org: e.target.value }))}
        className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]" />
      <label htmlFor="partner-message" className="sr-only">{l.formMessage}</label>
      <textarea id="partner-message" rows={2} placeholder={l.formMessage} value={form.message}
        onChange={e => setForm(f => ({ ...f, message: e.target.value }))}
        className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)] resize-y" />
      <label className={`flex items-start gap-2 cursor-pointer ${consentError ? 'text-red-600' : ''}`}>
        <input type="checkbox" checked={form.lgpd_consent}
          onChange={e => { setForm(f => ({ ...f, lgpd_consent: e.target.checked })); setConsentError(false); }}
          aria-describedby={consentError ? 'partner-consent-error' : undefined}
          className="mt-0.5 flex-shrink-0" />
        <span className="text-xs text-[var(--text-secondary)]">
          {l.formConsent}{' '}
          <a href={`${lp}/privacy`} target="_blank" rel="noopener" className="text-teal underline">{l.formConsentLink}</a>.
        </span>
      </label>
      {consentError && <p id="partner-consent-error" className="text-xs text-red-600">{l.formConsentRequired}</p>}
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

export default function PartnersSection({ lang = 'pt-BR' }: { lang?: Lang }) {
  const l = LABELS[lang] || LABELS['pt-BR'];
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [open, setOpen] = useState(false);

  const gives = [l.give1, l.give2, l.give3, l.give4];
  const gets = [l.get1, l.get2, l.get3, l.get4];

  return (
    <section className="py-16 px-6 bg-[var(--surface-card)]" id="partners">
      <div className="max-w-[1100px] mx-auto">
        <div className="text-[.73rem] font-bold tracking-[.15em] uppercase text-orange mb-2">{l.label}</div>
        <h2 className="text-[clamp(1.6rem,3.6vw,2.3rem)] font-extrabold leading-tight mb-3 max-w-[860px]">{l.title}</h2>
        <p className="text-base text-[var(--text-secondary)] max-w-[820px] mb-10">{l.subtitle}</p>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
          <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-base)] p-6"
            style={{ borderTop: '4px solid #00799E' }}>
            <h3 className="font-bold text-base text-[var(--text-primary)] mb-3">{l.giveTitle}</h3>
            <ul className="space-y-2">
              {gives.map((g, i) => (
                <li key={`give-${i}`} className="flex items-start gap-2 text-sm text-[var(--text-secondary)]">
                  <span className="text-teal mt-0.5 flex-shrink-0" aria-hidden="true">→</span>
                  <span>{g}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="rounded-2xl border border-[var(--border-subtle)] bg-[var(--surface-base)] p-6"
            style={{ borderTop: '4px solid #FF610F' }}>
            <h3 className="font-bold text-base text-[var(--text-primary)] mb-3">{l.getTitle}</h3>
            <ul className="space-y-2">
              {gets.map((g, i) => (
                <li key={`get-${i}`} className="flex items-start gap-2 text-sm text-[var(--text-secondary)]">
                  <span className="text-orange mt-0.5 flex-shrink-0" aria-hidden="true">←</span>
                  <span>{g}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Brand/legal invariant: Núcleo = porta de entrada; PMI-GO = dono da relação. */}
        <p className="text-sm text-[var(--text-secondary)] border-l-2 border-teal pl-3 mb-8 max-w-[820px]">
          {l.ownership}
        </p>

        {!open && (
          <div>
            <button type="button" onClick={() => setOpen(true)}
              className="inline-flex items-center gap-1 px-6 py-3 rounded-xl font-semibold text-sm text-white border-0 cursor-pointer bg-[var(--color-orange-deep)]">
              {l.cta} <span aria-hidden="true">→</span>
            </button>
            <p className="text-xs text-[var(--text-secondary)] mt-2">{l.ctaSub}</p>
          </div>
        )}
        {open && <PartnerForm l={l} lp={lp} onClose={() => setOpen(false)} />}
      </div>
    </section>
  );
}
