import { useEffect, useState, useRef, useCallback } from 'react';

interface ImpactData {
  chapters: number;
  active_members: number;
  tribes: number;
  articles_published: number;
  impact_hours: number;
  webinars: number;
  partner_count: number;
  recent_publications: Array<{ title: string; platform: string; publication_date: string; external_url: string; authors: string[] }>;
  tribes_summary: Array<{ id: number; name: string; quadrant_name: string; member_count: number; leader_name: string }>;
  chapters_summary: Array<{ chapter: string; member_count: number; sponsor: string | null }>;
  partners: Array<{ name: string; type: string }>;
  recognitions: Array<{ title: string; organization: string; recipient: string; date: string; category: string; description: string }>;
  timeline: Array<{ year: string; title: string; description: string }>;
}

interface ImpactPageProps {
  lang?: string;
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
    heroSub: 'Uma iniciativa colaborativa entre capítulos do PMI® no Brasil',
    chapters: 'Capítulos PMI',
    members: 'Colaboradores Ativos',
    tribesLabel: 'Tribos de Pesquisa',
    articles: 'Artigos Publicados',
    hours: 'Horas de Impacto',
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
    chaptersSection: 'Capítulos Patrocinadores',
    partnersSection: 'Parceiros',
    recognitionsSection: 'Reconhecimentos',
    finalist: 'Finalista',
    cta: 'Interessado em participar?',
    ctaSelection: 'Processo Seletivo',
    ctaArticles: 'Nossos Artigos',
    ctaContact: 'Contato',
    sponsor: 'Sponsor',
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
    heroSub: 'A collaborative initiative among PMI® chapters in Brazil',
    chapters: 'PMI Chapters',
    members: 'Active Contributors',
    tribesLabel: 'Research Tribes',
    articles: 'Published Articles',
    hours: 'Impact Hours',
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
    chaptersSection: 'Sponsoring Chapters',
    partnersSection: 'Partners',
    recognitionsSection: 'Recognitions',
    finalist: 'Finalist',
    cta: 'Interested in participating?',
    ctaSelection: 'Selection Process',
    ctaArticles: 'Our Articles',
    ctaContact: 'Contact',
    sponsor: 'Sponsor',
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
    heroSub: 'Una iniciativa colaborativa entre capítulos del PMI® en Brasil',
    chapters: 'Capítulos PMI',
    members: 'Colaboradores Activos',
    tribesLabel: 'Tribus de Investigación',
    articles: 'Artículos Publicados',
    hours: 'Horas de Impacto',
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
    chaptersSection: 'Capítulos Patrocinadores',
    partnersSection: 'Socios',
    recognitionsSection: 'Reconocimientos',
    finalist: 'Finalista',
    cta: '¿Interesado en participar?',
    ctaSelection: 'Proceso de Selección',
    ctaArticles: 'Nuestros Artículos',
    ctaContact: 'Contacto',
    sponsor: 'Sponsor',
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

const CHAPTERS = ['PMI-GO', 'PMI-CE', 'PMI-DF', 'PMI-MG', 'PMI-RS'];

function LeadCaptureForm({ l, lang }: { l: Record<string, string>; lang: string }) {
  const [form, setForm] = useState({ name: '', email: '', phone: '', chapter_interest: '', role_interest: '', message: '', lgpd_consent: false });
  const [status, setStatus] = useState<'idle' | 'submitting' | 'success' | 'error'>('idle');
  const [consentError, setConsentError] = useState(false);

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.lgpd_consent) { setConsentError(true); return; }
    setConsentError(false);
    setStatus('submitting');
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('No client');
      const { error } = await sb.from('visitor_leads').insert([{
        name: form.name,
        email: form.email,
        phone: form.phone || null,
        chapter_interest: form.chapter_interest || null,
        role_interest: form.role_interest || null,
        message: form.message || null,
        lgpd_consent: true,
        source: 'website',
      }]);
      if (error) throw error;
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
              {CHAPTERS.map(ch => <option key={ch} value={ch}>{ch}</option>)}
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
              {l.leadConsent} <a href="/privacy" target="_blank" className="text-teal underline">Privacy</a>
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

export default function ImpactPageIsland({ lang = 'pt-BR' }: ImpactPageProps) {
  const [data, setData] = useState<ImpactData | null>(null);
  const [loading, setLoading] = useState(true);
  const l = LABELS[lang] || LABELS['pt-BR'];

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
        <p className="text-lg text-[var(--text-secondary)] mt-4 max-w-2xl mx-auto">{l.heroSub}</p>
      </section>

      {/* Impact Counters */}
      <section className="grid grid-cols-2 md:grid-cols-5 gap-6 text-center">
        <div><AnimatedCounter target={data.chapters} /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.chapters}</div></div>
        <div><AnimatedCounter target={data.active_members} suffix="+" /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.members}</div></div>
        <div><AnimatedCounter target={data.tribes} /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.tribesLabel}</div></div>
        <div><AnimatedCounter target={data.articles_published} suffix="+" /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.articles}</div></div>
        <div><AnimatedCounter target={Math.round(data.impact_hours)} suffix="+" /><div className="text-sm font-semibold text-[var(--text-secondary)] mt-1">{l.hours}</div></div>
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
            <a key={tribe.id} href={`/tribe/${tribe.id}`} className="block no-underline group">
              <div className="bg-[var(--surface-card)] border-2 rounded-xl p-4 transition-all hover:shadow-lg group-hover:scale-[1.02]"
                   style={{ borderColor: TRIBE_COLORS[i % 8] }}>
                <div className="text-xs font-bold uppercase tracking-wide mb-1" style={{ color: TRIBE_COLORS[i % 8] }}>
                  T{String(tribe.id).padStart(2, '0')}
                </div>
                <div className="font-bold text-sm text-[var(--text-primary)] mb-2">{tribe.name_i18n?.[typeof window !== 'undefined' ? (window.location.pathname.startsWith('/en') ? 'en' : window.location.pathname.startsWith('/es') ? 'es' : 'pt') : 'pt'] || tribe.name}</div>
                <div className="text-xs text-[var(--text-secondary)]">{tribe.quadrant_name_i18n?.[typeof window !== 'undefined' ? (window.location.pathname.startsWith('/en') ? 'en' : window.location.pathname.startsWith('/es') ? 'es' : 'pt') : 'pt'] || tribe.quadrant_name}</div>
                <div className="flex items-center justify-between mt-3">
                  <span className="text-xs font-semibold px-2 py-0.5 rounded-full text-white" style={{ background: TRIBE_COLORS[i % 8] }}>
                    {tribe.member_count} {l.membersCount}
                  </span>
                </div>
                {tribe.leader_name && <div className="text-[11px] text-[var(--text-muted)] mt-2 truncate">{tribe.leader_name}</div>}
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
            {data.recent_publications.map((pub, i) => (
              <a key={i} href={pub.external_url || '#'} target="_blank" rel="noopener noreferrer"
                 className="block bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4 hover:shadow-md transition-all no-underline">
                <div className="font-semibold text-sm text-[var(--text-primary)]">{pub.title}</div>
                <div className="flex items-center gap-2 mt-2 text-xs text-[var(--text-secondary)]">
                  {pub.platform && <span className="px-2 py-0.5 bg-[var(--surface-hover)] rounded">{pub.platform}</span>}
                  {pub.publication_date && <span>{pub.publication_date}</span>}
                </div>
                {pub.authors?.length > 0 && <div className="text-xs text-[var(--text-muted)] mt-1">{pub.authors.join(', ')}</div>}
              </a>
            ))}
          </div>
          <div className="text-center mt-4">
            <a href="/publications" className="text-sm font-semibold text-teal hover:underline">{l.viewAll} &rarr;</a>
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
                <div className="text-2xl font-black text-teal mt-2">{ch.member_count}</div>
                <div className="text-xs text-[var(--text-secondary)]">{l.membersCount}</div>
                {ch.sponsor && <div className="text-[11px] text-[var(--text-muted)] mt-2">{l.sponsor}: {ch.sponsor}</div>}
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Partners */}
      {data.partners?.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold text-[var(--text-primary)] text-center mb-6">{l.partnersSection}</h2>
          <div className="flex flex-wrap justify-center gap-4">
            {data.partners.map((p, i) => (
              <div key={i} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl px-5 py-3">
                <div className="font-semibold text-sm text-[var(--text-primary)]">{p.name}</div>
                <div className="text-xs text-[var(--text-muted)] capitalize">{p.type}</div>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Recognitions */}
      {data.recognitions?.length > 0 && (
        <section>
          <h2 className="text-2xl font-bold text-[var(--text-primary)] text-center mb-6">{l.recognitionsSection}</h2>
          <div className="max-w-2xl mx-auto space-y-3">
            {data.recognitions.map((rec, i) => (
              <div key={i} className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-5 flex items-start gap-4">
                <div className="flex-shrink-0 w-10 h-10 rounded-full bg-amber-100 flex items-center justify-center text-lg">🏅</div>
                <div className="flex-1 min-w-0">
                  <div className="font-bold text-sm text-[var(--text-primary)]">{rec.title}</div>
                  <div className="text-xs text-[var(--text-secondary)] mt-1">{rec.organization}</div>
                  <div className="flex flex-wrap items-center gap-2 mt-2">
                    <span className="text-[10px] px-2 py-0.5 rounded-full bg-amber-100 text-amber-700 font-semibold">{l.finalist}</span>
                    <span className="text-[10px] text-[var(--text-muted)]">{rec.category}</span>
                    <span className="text-[10px] text-[var(--text-muted)]">{rec.date}</span>
                  </div>
                  <div className="text-xs text-[var(--text-muted)] mt-2">{rec.recipient} — {rec.description}</div>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Lead Capture Form */}
      <LeadCaptureForm l={l} lang={lang} />

      {/* CTA */}
      <section className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl p-8 text-center">
        <h2 className="text-2xl font-bold text-[var(--text-primary)] mb-6">{l.cta}</h2>
        <div className="flex flex-wrap justify-center gap-4">
          <a href="/admin/selection" className="px-6 py-3 bg-teal text-white rounded-xl font-semibold text-sm hover:opacity-90 transition-all no-underline">{l.ctaSelection}</a>
          <a href="/publications" className="px-6 py-3 bg-navy text-white rounded-xl font-semibold text-sm hover:opacity-90 transition-all no-underline">{l.ctaArticles}</a>
          <a href="mailto:nucleoia@pmigo.org.br" className="px-6 py-3 border-2 border-navy text-navy rounded-xl font-semibold text-sm hover:bg-navy hover:text-white transition-all no-underline">{l.ctaContact}</a>
        </div>
      </section>
    </div>
  );
}
