import { useEffect, useState, useRef, useCallback } from 'react';
import { loadChapters, type Chapter } from '../../lib/chapters';

interface ImpactData {
  chapters: number;
  active_members: number;
  tribes: number;
  articles_published: number;
  impact_hours: number;
  /** #2365: ano do primeiro registro contado em impact_hours (acumulado). */
  impact_hours_since: number | null;
  webinars: number;
  partner_count: number;
  // #2553 D7 (GP 24/10/2026): o /about mostra pessoas só em número; autores, liderança, presidência de capítulo,
  // a lista de parceiros e o prêmio individual saíram da RPC (DB-4) e da página.
  recent_publications: Array<{ title: string; platform: string; publication_date: string; external_url: string }>;
  tribes_summary: Array<{ id: number; name: string; quadrant_name: string; member_count: number }>;
  // PR3 A1 (GP 25/10/2026): os capítulos engajados, sem status; member_count é null abaixo de 3 pessoas (o k do mapa).
  chapters_summary: Array<{ chapter: string; member_count: number | null }>;
  timeline: Array<{ year: string; title: string; description: string }>;
}

/** #2783: nome e quadrante de cada linha na língua da página, da mesma fonte da home (get_public_research_lines). */
export type LineNames = Record<number, { name: string; quadrantName: string }>;
/** #2783: textos dos dicionários, resolvidos no servidor pelo about.astro. */
export interface ImpactPageText { relation: string; privacy: string; memberOne: string }

interface ImpactPageProps {
  lang?: string;
  lineNames?: LineNames;
  text?: ImpactPageText;
}

// ── Animated Counter ──
function AnimatedCounter({ target, suffix = '', prefix = '' }: { target: number; suffix?: string; prefix?: string }) {
  const [count, setCount] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const animated = useRef(false);

  useEffect(() => {
    if (!ref.current || animated.current) return;
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && !animated.current) {
        animated.current = true;
        const duration = 1500;
        const start = performance.now();
        const step = (now: number) => {
          const elapsed = now - start;
          const progress = Math.min(elapsed / duration, 1);
          const eased = 1 - Math.pow(1 - progress, 3);
          setCount(Math.round(eased * target));
          if (progress < 1) requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
      }
    }, { threshold: 0.3 });
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [target]);

  return <div ref={ref} className="text-4xl md:text-5xl font-black text-teal">{prefix}{count}{suffix}</div>;
}

// ── Labels ──
const LABELS: Record<string, Record<string, string>> = {
  'pt-BR': {
    hero: 'Transformando o Gerenciamento de Projetos na Era da Inteligência Artificial',
    chapters: 'Capítulos PMI engajados',
    members: 'Colaboradores Ativos',
    tribesLabel: 'Tribos de Pesquisa',
    articles: 'Publicações',
    hours: 'Horas de Impacto',
    hoursSince: 'desde',
    timeline: 'Nossa História',
    mission: 'Missão',
    missionText: 'Avançar a aplicação de IA no Gerenciamento de Projetos por meio de pesquisas inovadoras e comunidade engajada.',
    vision: 'Visão',
    visionText: 'Mapear e influenciar o futuro do Gerenciamento de Projetos na era da Inteligência Artificial.',
    values: 'Valores',
    valuesText: 'Transparência, Mérito Técnico, Colaboração, Ética (Código PMI), Inovação.',
    tribesSection: 'Tribos de Pesquisa',
    publications: 'Publicações Recentes',
    viewAll: 'Ver todas as publicações',
    chaptersSection: 'Capítulos participantes',
    cta: 'Interessado em participar?',
    ctaSelection: 'Processo Seletivo',
    ctaArticles: 'Nossos Artigos',
    ctaContact: 'Contato',
    membersCount: 'membros',
    loading: 'Carregando dados de impacto...',
    leadTitle: 'Interessado em participar?',
    leadSubtitle: 'Preencha o formulário e entraremos em contato.',
    leadName: 'Nome completo',
    leadEmail: 'E-mail',
    leadPhone: 'Telefone (opcional)',
    leadChapter: 'Capítulo PMI de interesse',
    leadChapterPlaceholder: 'Selecione um capítulo',
    leadRole: 'Interesse como',
    leadRolePlaceholder: 'Selecione um papel',
    leadRoleResearcher: 'Pesquisador',
    leadRoleLeader: 'Líder de Tribo',
    leadRoleOther: 'Outro',
    leadMessage: 'Mensagem (opcional)',
    leadConsent: 'Concordo com a Política de Privacidade e autorizo o contato sobre oportunidades de participação.',
    leadSubmit: 'Enviar interesse',
    leadSubmitting: 'Enviando...',
    leadSuccess: 'Obrigado! Entraremos em contato em breve.',
    leadError: 'Erro ao enviar. Tente novamente.',
    leadConsentRequired: 'O consentimento é obrigatório.',
  },
  'en-US': {
    hero: 'Transforming Project Management in the Age of Artificial Intelligence',
    chapters: 'Engaged PMI Chapters',
    members: 'Active Contributors',
    tribesLabel: 'Research Tribes',
    articles: 'Publications',
    hours: 'Impact Hours',
    hoursSince: 'since',
    timeline: 'Our Story',
    mission: 'Mission',
    missionText: 'Advance the application of AI in Project Management through innovative research and an engaged community.',
    vision: 'Vision',
    visionText: 'Map and influence the future of Project Management in the age of Artificial Intelligence.',
    values: 'Values',
    valuesText: 'Transparency, Technical Merit, Collaboration, Ethics (PMI Code), Innovation.',
    tribesSection: 'Research Tribes',
    publications: 'Recent Publications',
    viewAll: 'View all publications',
    chaptersSection: 'Participating chapters',
    cta: 'Interested in participating?',
    ctaSelection: 'Selection Process',
    ctaArticles: 'Our Articles',
    ctaContact: 'Contact',
    membersCount: 'members',
    loading: 'Loading impact data...',
    leadTitle: 'Interested in joining?',
    leadSubtitle: 'Fill out the form and we will get in touch.',
    leadName: 'Full name',
    leadEmail: 'Email',
    leadPhone: 'Phone (optional)',
    leadChapter: 'PMI Chapter of interest',
    leadChapterPlaceholder: 'Select a chapter',
    leadRole: 'Interest as',
    leadRolePlaceholder: 'Select a role',
    leadRoleResearcher: 'Researcher',
    leadRoleLeader: 'Tribe Leader',
    leadRoleOther: 'Other',
    leadMessage: 'Message (optional)',
    leadConsent: 'I agree to the Privacy Policy and authorize contact about participation opportunities.',
    leadSubmit: 'Submit interest',
    leadSubmitting: 'Submitting...',
    leadSuccess: 'Thank you! We will get in touch soon.',
    leadError: 'Error submitting. Please try again.',
    leadConsentRequired: 'Consent is required.',
  },
  'es-LATAM': {
    hero: 'Transformando la Gestión de Proyectos en la Era de la Inteligencia Artificial',
    chapters: 'Capítulos PMI comprometidos',
    members: 'Colaboradores Activos',
    tribesLabel: 'Tribus de Investigación',
    articles: 'Publicaciones',
    hours: 'Horas de Impacto',
    hoursSince: 'desde',
    timeline: 'Nuestra Historia',
    mission: 'Misión',
    missionText: 'Avanzar la aplicación de IA en la Gestión de Proyectos a través de investigaciones innovadoras y comunidad comprometida.',
    vision: 'Visión',
    visionText: 'Mapear e influenciar el futuro de la Gestión de Proyectos en la era de la Inteligencia Artificial.',
    values: 'Valores',
    valuesText: 'Transparencia, Mérito Técnico, Colaboración, Ética (Código PMI), Innovación.',
    tribesSection: 'Tribus de Investigación',
    publications: 'Publicaciones Recientes',
    viewAll: 'Ver todas las publicaciones',
    chaptersSection: 'Capítulos participantes',
    cta: '¿Interesado en participar?',
    ctaSelection: 'Proceso de Selección',
    ctaArticles: 'Nuestros Artículos',
    ctaContact: 'Contacto',
    membersCount: 'miembros',
    loading: 'Cargando datos de impacto...',
    leadTitle: '¿Interesado en participar?',
    leadSubtitle: 'Completa el formulario y nos pondremos en contacto.',
    leadName: 'Nombre completo',
    leadEmail: 'Correo electrónico',
    leadPhone: 'Teléfono (opcional)',
    leadChapter: 'Capítulo PMI de interés',
    leadChapterPlaceholder: 'Selecciona un capítulo',
    leadRole: 'Interés como',
    leadRolePlaceholder: 'Selecciona un rol',
    leadRoleResearcher: 'Investigador',
    leadRoleLeader: 'Líder de Tribu',
    leadRoleOther: 'Otro',
    leadMessage: 'Mensaje (opcional)',
    leadConsent: 'Acepto la Política de Privacidad y autorizo el contacto sobre oportunidades de participación.',
    leadSubmit: 'Enviar interés',
    leadSubmitting: 'Enviando...',
    leadSuccess: '¡Gracias! Nos pondremos en contacto pronto.',
    leadError: 'Error al enviar. Inténtalo de nuevo.',
    leadConsentRequired: 'El consentimiento es obligatorio.',
  },
};

const TRIBE_COLORS = ['#0d9488', '#2563eb', '#7c3aed', '#dc2626', '#ea580c', '#0891b2', '#4f46e5', '#059669'];

function LeadCaptureForm({ l, lang, privacyLabel }: { l: Record<string, string>; lang: string; privacyLabel: string }) {
  // Locale prefix for the privacy link. Declared here because `lp` in ImpactPageIsland is out of
  // scope for this component; referencing it threw ReferenceError and blanked /about.
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [form, setForm] = useState({ name: '', email: '', phone: '', chapter_interest: '', role_interest: '', message: '', lgpd_consent: false });
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [consentError, setConsentError] = useState(false);
  const [chapters, setChapters] = useState<Chapter[]>([]);

  useEffect(() => { loadChapters().then(setChapters); }, []);

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.lgpd_consent) { setConsentError(true); return; }
    setConsentError(false);
    setStatus('submitting');
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('No client');

      // ARM-1: capture UTM + referral from URL query params
      const params = new URLSearchParams(typeof window !== 'undefined' ? window.location.search : '');
      const utmKeys = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content'] as const;
      const utm: Record<string, string> = {};
      for (const k of utmKeys) {
        const v = params.get(k);
        if (v) utm[k] = v;
      }
      const refMember = params.get('ref') || params.get('referrer');

      const payload: Record<string, unknown> = {
        name: form.name,
        email: form.email,
        phone: form.phone || null,
        chapter_interest: form.chapter_interest || null,
        role_interest: form.role_interest || null,
        message: form.message || null,
        lgpd_consent: true,
        source: utm.utm_source ? `utm:${utm.utm_source}` : 'website',
      };
      if (Object.keys(utm).length > 0) payload.utm_data = utm;
      if (refMember) payload.referrer_member_id = refMember;

      const { data, error } = await sb.rpc('capture_visitor_lead', { p_payload: payload });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      setStatus('success');
    } catch {
      setStatus('error');
    }
  }, [form]);

  if (status === 'success') {
    return (
      <section className="bg-green-50 border border-green-200 rounded-2xl p-8 text-center">
        <div className="text-3xl mb-3">✅</div>
        <p className="text-green-700 font-semibold">{l.leadSuccess}</p>
      </section>
    );
  }

  return (
    <section className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-6 md:p-8" id="lead-form">
      <h2 className="text-xl font-bold text-[var(--text-primary)] mb-1">{l.leadTitle}</h2>
      <p className="text-sm text-[var(--text-secondary)] mb-6">{l.leadSubtitle}</p>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">{l.leadName} *</label>
            <input type="text" required value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-sm text-[var(--text-primary)]" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">{l.leadEmail} *</label>
            <input type="email" required value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-sm text-[var(--text-primary)]" />
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">{l.leadPhone}</label>
            <input type="tel" value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-sm text-[var(--text-primary)]" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">{l.leadChapter}</label>
            <select value={form.chapter_interest} onChange={e => setForm(f => ({ ...f, chapter_interest: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-sm text-[var(--text-primary)]">
              <option value="">{l.leadChapterPlaceholder}</option>
              {chapters.map(ch => <option key={ch.display_code} value={ch.display_code}>{ch.display_code}</option>)}
              <option value="other">{l.leadRoleOther}</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">{l.leadRole}</label>
            <select value={form.role_interest} onChange={e => setForm(f => ({ ...f, role_interest: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-sm text-[var(--text-primary)]">
              <option value="">{l.leadRolePlaceholder}</option>
              <option value="researcher">{l.leadRoleResearcher}</option>
              <option value="leader">{l.leadRoleLeader}</option>
              <option value="other">{l.leadRoleOther}</option>
            </select>
          </div>
        </div>
        <div>
          <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">{l.leadMessage}</label>
          <textarea rows={3} value={form.message} onChange={e => setForm(f => ({ ...f, message: e.target.value }))}
            className="w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-sm text-[var(--text-primary)] resize-y" />
        </div>
        <div>
          <label className={`flex items-start gap-2 cursor-pointer ${consentError ? 'text-red-600' : ''}`}>
            <input type="checkbox" checked={form.lgpd_consent} onChange={e => { setForm(f => ({ ...f, lgpd_consent: e.target.checked })); setConsentError(false); }}
              className="mt-1 flex-shrink-0" />
            <span className="text-xs text-[var(--text-secondary)]">
              {/* #2783: o rótulo do link vem do dicionário (nav.privacy); era "Privacy" fixo nas 3 línguas */}
              {l.leadConsent} <a href={`${lp}/privacy`} target="_blank" className="text-teal underline">{privacyLabel}</a>
            </span>
          </label>
          {consentError && <p className="text-xs text-red-600 mt-1">{l.leadConsentRequired}</p>}
        </div>
        <button type="submit" disabled={status === 'submitting'}
          className="w-full md:w-auto px-6 py-2.5 bg-teal text-white rounded-xl font-semibold text-sm hover:opacity-90 transition-all border-0 cursor-pointer disabled:opacity-50">
          {status === 'submitting' ? l.leadSubmitting : l.leadSubmit}
        </button>
        {status === 'error' && <p className="text-xs text-red-600">{l.leadError}</p>}
      </form>
    </section>
  );
}

export default function ImpactPageIsland({ lang = 'pt-BR', lineNames, text }: ImpactPageProps) {
  // p123 i18n nav: prefix preserves /en /es when navigating between sections
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [data, setData] = useState<ImpactData | null>(null);
  const [loading, setLoading] = useState(true);
  const l = LABELS[lang] || LABELS['pt-BR'];
  // #2783: "1 membros" / "1 members". O singular vem do dicionário (about.memberCountOne), resolvido no servidor.
  const membersLabel = (n: number) => (n === 1 && text?.memberOne ? text.memberOne : l.membersCount);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) { setTimeout(load, 300); return; }
      try {
        const { data: d, error } = await sb.rpc('get_public_impact_data');
        if (!cancelled && !error) setData(d);
      } catch {}
      if (!cancelled) setLoading(false);
    };
    load();
    return () => { cancelled = true; };
  }, []);

  if (loading) return <div className="text-center py-20 text-[var(--text-muted)]">{l.loading}</div>;
  if (!data) return null;

  return (
    <div className="space-y-16">
      {/* Hero */}
      <section className="text-center py-12">
        <h1 className="text-3xl md:text-4xl font-black text-[var(--text-primary)] max-w-3xl mx-auto leading-tight">{l.hero}</h1>
        {/* #2783: a mesma descrição institucional da home (homeV2.hero.relation), sem texto novo */}
        {text?.relation && <p className="text-lg text-[var(--text-secondary)] mt-4 max-w-2xl mx-auto">{text.relation}</p>}
      </section>

      {/* Impact Counters */}
      <section className="grid grid-cols-2 md:grid-cols-5 gap-6 text-center">
        <div><AnimatedCounter target={data.chapters} /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.chapters}</div></div>
        <div><AnimatedCounter target={data.active_members} suffix="+" /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.members}</div></div>
        <div><AnimatedCounter target={data.tribes} /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.tribesLabel}</div></div>
        <div><AnimatedCounter target={data.articles_published} suffix="+" /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.articles}</div></div>
        <div><AnimatedCounter target={Math.round(data.impact_hours)} suffix="+" /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.hours}</div>{data.impact_hours_since ? <div className="text-xs text-[var(--text-muted)]">{l.hoursSince} {data.impact_hours_since}</div> : null}</div>
      </section>

      {/* Timeline */}
      <section>
        <h2 className="text-2xl font-bold text-[var(--text-primary)] text-center mb-8">{l.timeline}</h2>
        <div className="relative max-w-2xl mx-auto">
          <div className="absolute left-4 md:left-1/2 top-0 bottom-0 w-0.5 bg-[var(--border-default)]" />
          {data.timeline.map((item, i) => (
            <div key={item.year} className={`relative flex items-start mb-8 ${i % 2 === 0 ? 'md:flex-row' : 'md:flex-row-reverse'}`}>
              <div className={`flex-1 ${i % 2 === 0 ? 'md:pr-8 md:text-right' : 'md:pl-8'} pl-10 md:pl-0`}>
                <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4">
                  <div className="text-sm font-black text-teal mb-1">{item.year}</div>
                  <div className="font-bold text-[var(--text-primary)]">{item.title}</div>
                  <div className="text-sm text-[var(--text-secondary)] mt-1">{item.description}</div>
                </div>
              </div>
              <div className="absolute left-2 md:left-1/2 md:-translate-x-1/2 w-4 h-4 rounded-full bg-teal border-2 border-white mt-5" />
              <div className="hidden md:block flex-1" />
            </div>
          ))}
        </div>
      </section>

      {/* Mission / Vision / Values */}
      <section className="grid md:grid-cols-3 gap-6">
        {[
          { icon: '🎯', title: l.mission, text: l.missionText },
          { icon: '🔭', title: l.vision, text: l.visionText },
          { icon: '💎', title: l.values, text: l.valuesText },
        ].map(item => (
          <div key={item.title} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-6 text-center">
            <div className="text-3xl mb-3">{item.icon}</div>
            <h3 className="font-bold text-[var(--text-primary)] mb-2">{item.title}</h3>
            <p className="text-sm text-[var(--text-secondary)]">{item.text}</p>
          </div>
        ))}
      </section>

      {/* Tribes Grid */}
      <section>
        <h2 className="text-2xl font-bold text-[var(--text-primary)] text-center mb-6">{l.tribesSection}</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {(data.tribes_summary || []).map((tribe, i) => (
            // #2553 D7: /tribe/<id> nega o visitante; o card leva à lista de linhas da home, que abre o detalhe ali
            <a key={tribe.id} href={`${lp}/#tribes`} className="block no-underline group">
              <div className="bg-[var(--surface-card)] border-2 rounded-xl p-4 transition-all hover:shadow-lg group-hover:scale-[1.02]"
                   style={{ borderColor: TRIBE_COLORS[i % 8] }}>
                <div className="text-xs font-bold uppercase tracking-wide mb-1" style={{ color: TRIBE_COLORS[i % 8] }}>
                  T{String(tribe.id).padStart(2, '0')}
                </div>
                {/* #2783: a RPC devolve o nome em português e o quadrante em inglês; a língua da página vem de lineNames */}
                <div className="font-bold text-sm text-[var(--text-primary)] mb-2">{lineNames?.[tribe.id]?.name || tribe.name}</div>
                <div className="text-xs text-[var(--text-secondary)]">{lineNames?.[tribe.id]?.quadrantName || tribe.quadrant_name}</div>
                <div className="flex items-center justify-between mt-3">
                  <span className="text-xs font-semibold px-2 py-0.5 rounded-full text-white" style={{ background: TRIBE_COLORS[i % 8] }}>
                    {tribe.member_count} {membersLabel(tribe.member_count)}
                  </span>
                </div>
              </div>
            </a>
          ))}
        </div>
      </section>

      {/* Publications Preview */}
      {data.recent_publications?.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold text-[var(--text-primary)] text-center mb-6">{l.publications}</h2>
          <div className="space-y-3 max-w-2xl mx-auto">
            {data.recent_publications.map((pub, i) => {
              // #2553 D7: sem URL, o item fica sem link (antes virava href="#", que não leva a lugar nenhum)
              const Tag = pub.external_url ? 'a' : 'div';
              const link = pub.external_url ? { href: pub.external_url, target: '_blank', rel: 'noopener noreferrer' } : {};
              return (
              <Tag key={i} {...link}
                 className="block bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4 hover:shadow-md transition-all no-underline">
                <div className="font-semibold text-sm text-[var(--text-primary)]">{pub.title}</div>
                <div className="flex items-center gap-2 mt-2 text-xs text-[var(--text-secondary)]">
                  {pub.platform && <span className="px-2 py-0.5 bg-[var(--surface-hover)] rounded">{pub.platform}</span>}
                  {pub.publication_date && <span>{pub.publication_date}</span>}
                </div>
              </Tag>
              );
            })}
          </div>
          <div className="text-center mt-4">
            <a href={`${lp}/publications`} className="text-sm font-semibold text-teal hover:underline">{l.viewAll} &rarr;</a>
          </div>
        </section>
      )}

      {/* Chapters */}
      {data.chapters_summary?.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold text-[var(--text-primary)] text-center mb-6">{l.chaptersSection}</h2>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            {data.chapters_summary.map((ch) => (
              <div key={ch.chapter} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4 text-center">
                <div className="font-bold text-sm text-[var(--text-primary)]">{ch.chapter}</div>
                {/* PR3 A1: abaixo de 3 pessoas a RPC devolve null e o card mostra só o capítulo */}
                {typeof ch.member_count === 'number' && (
                  <>
                    <div className="text-2xl font-black text-teal mt-2">{ch.member_count}</div>
                    <div className="text-xs text-[var(--text-secondary)]">{membersLabel(ch.member_count)}</div>
                  </>
                )}
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Lead Capture Form */}
      <LeadCaptureForm l={l} lang={lang} privacyLabel={text?.privacy ?? ''} />

      {/* CTA */}
      <section className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-8 text-center">
        <h2 className="text-2xl font-bold text-[var(--text-primary)] mb-6">{l.cta}</h2>
        <div className="flex flex-wrap justify-center gap-4">
          {/* #2553 D7: o visitante ia para uma tela de admin; agora vai às portas de entrada da home */}
          <a href={`${lp}/#join`} className="px-6 py-3 bg-teal text-white rounded-xl font-semibold text-sm hover:opacity-90 transition-all no-underline">{l.ctaSelection}</a>
          <a href={`${lp}/publications`} className="px-6 py-3 bg-navy text-white rounded-xl font-semibold text-sm hover:opacity-90 transition-all no-underline">{l.ctaArticles}</a>
          <a href="mailto:nucleoia@pmigo.org.br" className="px-6 py-3 border-2 border-navy text-navy rounded-xl font-semibold text-sm hover:bg-navy hover:text-white transition-all no-underline">{l.ctaContact}</a>
        </div>
      </section>
    </div>
  );
}
