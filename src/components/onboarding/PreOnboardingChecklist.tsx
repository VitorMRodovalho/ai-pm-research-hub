import { useState, useEffect, useCallback } from 'react';

interface Step {
  step_key: string;
  status: string;
  completed_at: string | null;
  sla_deadline: string | null;
  xp: number;
  phase: string;
}

interface LeaderboardEntry {
  name: string;
  photo_url: string | null;
  completed: number;
  total: number;
  xp_earned: number;
  xp_total: number;
  pct: number;
}

interface PreOnboardingData {
  member_id: string;
  steps: Step[];
  pre_onboarding: {
    total: number;
    completed: number;
    xp_earned: number;
    xp_total: number;
  };
  error?: string;
}

interface Props {
  lang?: string;
}

const STEP_META: Record<string, { icon: string; pt: string; en: string; es: string; hint_pt: string; hint_en: string; hint_es: string }> = {
  create_account:   { icon: '🔑', pt: 'Crie sua conta',          en: 'Create your account',     es: 'Cree su cuenta',           hint_pt: 'Login na plataforma com Google/LinkedIn/Microsoft', hint_en: 'Login with Google/LinkedIn/Microsoft', hint_es: 'Inicie sesión con Google/LinkedIn/Microsoft' },
  complete_profile: { icon: '👤', pt: 'Complete seu perfil',      en: 'Complete your profile',   es: 'Complete su perfil',       hint_pt: 'Foto, bio, LinkedIn, telefone, endereço, cidade e aniversário (necessário para o Termo de Voluntariado)', hint_en: 'Photo, bio, LinkedIn, phone, address, city, birthday (required for Volunteer Agreement)', hint_es: 'Foto, bio, LinkedIn, teléfono, dirección, ciudad, cumpleaños (requerido para el Acuerdo)' },
  setup_credly:     { icon: '🏅', pt: 'Configure o Credly',       en: 'Set up Credly',           es: 'Configure Credly',         hint_pt: 'Adicione a URL do Credly ao seu perfil', hint_en: 'Add your Credly URL to your profile', hint_es: 'Agregue su URL de Credly al perfil' },
  explore_platform: { icon: '🔍', pt: 'Explore a plataforma',     en: 'Explore the platform',    es: 'Explore la plataforma',    hint_pt: 'Visite 3+ páginas (blog, tribos, gamificação)', hint_en: 'Visit 3+ pages (blog, streams, gamification)', hint_es: 'Visite 3+ páginas (blog, líneas, gamificación)' },
  read_blog:        { icon: '📖', pt: 'Leia o blog do Núcleo',    en: 'Read the Hub blog',       es: 'Lea el blog del Núcleo',   hint_pt: 'Leia ao menos 1 post sobre o Núcleo IA', hint_en: 'Read at least 1 post about the Hub', hint_es: 'Lea al menos 1 post sobre el Núcleo' },
  start_pmi_certs:  { icon: '🎓', pt: 'Inicie a trilha PMI',      en: 'Start the PMI trail',     es: 'Inicie la ruta PMI',       hint_pt: 'Complete ao menos 1 mini-certificação PMI gratuita', hint_en: 'Complete at least 1 free PMI mini-cert', hint_es: 'Complete al menos 1 mini-certificación PMI gratuita' },
};

// F1/J3 #740 — collective pre-onboarding WhatsApp help group (candidates + Núcleo +
// diretorias de filiação/voluntariado). Single source of truth for the invite link.
const PRE_ONBOARDING_WHATSAPP_URL = 'https://chat.whatsapp.com/Gl6eUqK45DJGQxZ8VFE2bs';

const L: Record<string, Record<string, string>> = {
  'pt-BR':   { title: 'Preparação Pré-Onboarding', subtitle: 'Complete sua preparação para começar com tudo!', xp: 'XP', of: 'de', steps: 'etapas', completed: 'concluídas', profile: 'Ir ao Perfil', blog: 'Ir ao Blog', pmi: 'PMI Learning', noData: 'Nenhuma etapa de pré-onboarding encontrada.', autoDetect: 'Auto-detectado', ranking: 'Ranking Pré-Onboarding', step: 'Passo', helpTitle: 'Dúvidas? Você não está sozinho', helpBody: 'Entre no grupo de WhatsApp do pré-onboarding — candidatos, o Núcleo e as diretorias de filiação e voluntariado tiram dúvidas por lá.', helpCta: 'Entrar no grupo de WhatsApp' },
  'en-US':   { title: 'Pre-Onboarding Prep', subtitle: 'Complete your prep to hit the ground running!', xp: 'XP', of: 'of', steps: 'steps', completed: 'completed', profile: 'Go to Profile', blog: 'Go to Blog', pmi: 'PMI Learning', noData: 'No pre-onboarding steps found.', autoDetect: 'Auto-detected', ranking: 'Pre-Onboarding Ranking', step: 'Step', helpTitle: 'Questions? You\'re not alone', helpBody: 'Join the pre-onboarding WhatsApp group — candidates, the Hub team, and the membership & volunteering boards answer questions there.', helpCta: 'Join the WhatsApp group' },
  'es-LATAM': { title: 'Preparación Pre-Integración', subtitle: '¡Complete su preparación para empezar con todo!', xp: 'XP', of: 'de', steps: 'pasos', completed: 'completados', profile: 'Ir al Perfil', blog: 'Ir al Blog', pmi: 'PMI Learning', noData: 'No se encontraron pasos de pre-integración.', autoDetect: 'Auto-detectado', ranking: 'Ranking Pre-Integración', step: 'Paso', helpTitle: '¿Dudas? No estás solo', helpBody: 'Únase al grupo de WhatsApp de pre-integración — candidatos, el equipo del Núcleo y las direcciones de afiliación y voluntariado responden dudas allí.', helpCta: 'Entrar al grupo de WhatsApp' },
};

// F2/F3/F4 #740 — community & purpose copy (Credly mini-guide, 2026 purpose card,
// first-mission empty state). Inline trilingual to match this component's idiom (L/STEP_META).
interface FBlock {
  purpose: { title: string; body: string; goalsToggle: string; goal1: string; goal2: string; goal3: string };
  credly: { toggle: string; step1: string; step2: string; step3: string };
  mission: { title: string; body: string; nextLabel: string; howToEarn: string };
}
const FBLOCK: Record<string, FBlock> = {
  'pt-BR': {
    purpose: {
      title: '🌟 Por que você está aqui',
      body: 'Você entrou para um time de voluntários que leva IA aplicada à gestão de projetos para toda a comunidade PMI no Brasil. Cada passo abaixo te aproxima de construir isso com a gente.',
      goalsToggle: 'O que vamos construir juntos em 2026',
      goal1: '🎓 Conhecimento aberto — trilhas, webinars e certificações que democratizam IA aplicada a projetos.',
      goal2: '🤝 Comunidade que acolhe — onde cada voluntário encontra propósito, mentoria e pertencimento.',
      goal3: '🚀 Impacto que se vê — publicações e iniciativas que colocam o Brasil no mapa de IA + gestão de projetos.',
    },
    credly: {
      toggle: 'Como pegar meu link do Credly?',
      step1: '1. Entre em credly.com e deixe seu perfil Público (Settings → Privacy).',
      step2: '2. Abra seu perfil e copie a URL credly.com/users/seu-usuario.',
      step3: '3. Cole no campo Credly do seu perfil aqui na plataforma.',
    },
    mission: {
      title: '🎯 Sua primeira missão',
      body: 'Você está com 0 XP — todo voluntário começa assim. Sua primeira missão:',
      nextLabel: 'Comece por aqui',
      howToEarn: 'Cada etapa concluída soma XP e te coloca no ranking de pré-onboarding.',
    },
  },
  'en-US': {
    purpose: {
      title: '🌟 Why you\'re here',
      body: 'You joined a team of volunteers bringing AI applied to project management to the whole PMI community in Brazil. Each step below brings you closer to building it with us.',
      goalsToggle: 'What we\'ll build together in 2026',
      goal1: '🎓 Open knowledge — trails, webinars and certifications that democratize AI applied to projects.',
      goal2: '🤝 A welcoming community — where every volunteer finds purpose, mentorship and belonging.',
      goal3: '🚀 Visible impact — publications and initiatives that put Brazil on the AI + project management map.',
    },
    credly: {
      toggle: 'How do I get my Credly link?',
      step1: '1. Go to credly.com and set your profile to Public (Settings → Privacy).',
      step2: '2. Open your profile and copy the URL credly.com/users/your-username.',
      step3: '3. Paste it into the Credly field of your profile here on the platform.',
    },
    mission: {
      title: '🎯 Your first mission',
      body: 'You\'re at 0 XP — every volunteer starts here. Your first mission:',
      nextLabel: 'Start here',
      howToEarn: 'Each completed step adds XP and puts you on the pre-onboarding ranking.',
    },
  },
  'es-LATAM': {
    purpose: {
      title: '🌟 Por qué estás aquí',
      body: 'Te uniste a un equipo de voluntarios que lleva la IA aplicada a la gestión de proyectos a toda la comunidad PMI en Brasil. Cada paso abajo te acerca a construirlo con nosotros.',
      goalsToggle: 'Lo que construiremos juntos en 2026',
      goal1: '🎓 Conocimiento abierto — rutas, webinars y certificaciones que democratizan la IA aplicada a proyectos.',
      goal2: '🤝 Una comunidad que acoge — donde cada voluntario encuentra propósito, mentoría y pertenencia.',
      goal3: '🚀 Impacto que se ve — publicaciones e iniciativas que ponen a Brasil en el mapa de IA + gestión de proyectos.',
    },
    credly: {
      toggle: '¿Cómo obtengo mi enlace de Credly?',
      step1: '1. Ingrese a credly.com y deje su perfil como Público (Settings → Privacy).',
      step2: '2. Abra su perfil y copie la URL credly.com/users/su-usuario.',
      step3: '3. Péguela en el campo Credly de su perfil aquí en la plataforma.',
    },
    mission: {
      title: '🎯 Tu primera misión',
      body: 'Estás en 0 XP — todo voluntario empieza así. Tu primera misión:',
      nextLabel: 'Empieza por aquí',
      howToEarn: 'Cada paso completado suma XP y te coloca en el ranking de pre-integración.',
    },
  },
};
function fblock(lang: string): FBlock {
  if (lang.startsWith('en')) return FBLOCK['en-US'];
  if (lang.startsWith('es')) return FBLOCK['es-LATAM'];
  return FBLOCK['pt-BR'];
}

function label(key: string, lang: string): string {
  const m = STEP_META[key];
  if (!m) return key;
  if (lang.startsWith('en')) return m.en;
  if (lang.startsWith('es')) return m.es;
  return m.pt;
}

function hint(key: string, lang: string): string {
  const m = STEP_META[key];
  if (!m) return '';
  if (lang.startsWith('en')) return m.hint_en;
  if (lang.startsWith('es')) return m.hint_es;
  return m.hint_pt;
}

function icon(key: string): string {
  return STEP_META[key]?.icon || '📋';
}

export default function PreOnboardingChecklist({ lang = 'pt-BR' }: Props) {
  const l = L[lang] || L['pt-BR'];
  const fb = fblock(lang);
  // p123 i18n nav: prefix preserves /en /es when navigating between sections
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
  const [data, setData] = useState<PreOnboardingData | null>(null);
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([]);
  const [loading, setLoading] = useState(true);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    try {
      const [progRes, lbRes] = await Promise.all([
        sb.rpc('get_candidate_onboarding_progress'),
        sb.rpc('get_pre_onboarding_leaderboard'),
      ]);
      if (progRes.data && !progRes.data.error) {
        setData(progRes.data);
      }
      if (lbRes.data?.leaderboard) {
        setLeaderboard(lbRes.data.leaderboard);
      }
    } catch { /* not a candidate */ }
    setLoading(false);
  }, [getSb]);

  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  if (loading) return null;
  if (!data) return null;

  const preSteps = (data.steps || []).filter(s => s.phase === 'pre_onboarding');
  if (preSteps.length === 0) return null;

  const { total, completed, xp_earned, xp_total } = data.pre_onboarding;
  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  const allDone = completed === total && total > 0;
  // A3 #740 — linear stepper: communicate the sequence position.
  const firstIncomplete = preSteps.findIndex((s) => s.status !== 'completed');
  const currentStep = firstIncomplete === -1 ? preSteps.length : firstIncomplete + 1;

  return (
    <div className={`rounded-2xl border-2 ${allDone ? 'border-emerald-300 bg-emerald-50/30' : 'border-teal/30 bg-[var(--surface-card)]'} p-5 mb-6 shadow-sm`}>
      {/* F3 #740 — purpose / 2026 goals card so a newcomer knows "why am I here" (pre-onboarding only) */}
      {!allDone && (
      <div className="mb-4 rounded-xl border border-indigo-200 dark:border-indigo-800 bg-indigo-50/50 dark:bg-indigo-900/15 p-3.5">
        <h3 className="text-[12px] font-bold text-indigo-800 dark:text-indigo-300">{fb.purpose.title}</h3>
        <p className="text-[11px] text-indigo-700 dark:text-indigo-400 mt-1 leading-relaxed">{fb.purpose.body}</p>
        <details className="mt-2">
          <summary className="text-[11px] font-semibold text-indigo-700 dark:text-indigo-300 cursor-pointer list-none">{fb.purpose.goalsToggle} ↓</summary>
          <ul className="mt-2 space-y-1.5 text-[11px] text-indigo-700 dark:text-indigo-400 leading-relaxed list-none pl-0">
            <li>{fb.purpose.goal1}</li>
            <li>{fb.purpose.goal2}</li>
            <li>{fb.purpose.goal3}</li>
          </ul>
        </details>
      </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between mb-1">
        <h2 className="text-base font-extrabold text-navy">{l.title}</h2>
        <span className="text-xs font-bold text-teal">{xp_earned}/{xp_total} {l.xp}</span>
      </div>
      <p className="text-[11px] text-[var(--text-muted)] mb-1">{l.subtitle}</p>
      <p className="text-[11px] font-semibold text-teal mb-3">{l.step} {currentStep} {l.of} {preSteps.length}</p>

      {/* Progress bar */}
      <div className="flex items-center gap-3 mb-4">
        <div className="flex-1 bg-[var(--surface-base)] rounded-full h-2.5 overflow-hidden">
          <div className={`h-full rounded-full transition-all duration-700 ${allDone ? 'bg-emerald-500' : 'bg-gradient-to-r from-teal to-blue-500'}`} style={{ width: `${pct}%` }} />
        </div>
        <span className="text-[11px] font-bold text-[var(--text-secondary)] whitespace-nowrap">
          {completed}/{total} {l.completed}
        </span>
      </div>

      {/* F4 #740 — first-mission empty state for 0-XP newcomers (how to earn XP) */}
      {xp_earned === 0 && firstIncomplete !== -1 && (
        <div className="mb-4 rounded-xl border border-amber-200 dark:border-amber-800 bg-amber-50/60 dark:bg-amber-900/15 p-3.5">
          <h3 className="text-[12px] font-bold text-amber-800 dark:text-amber-300">{fb.mission.title}</h3>
          <p className="text-[11px] text-amber-700 dark:text-amber-400 mt-1 leading-relaxed">{fb.mission.body}</p>
          <div className="mt-2 flex items-center gap-2 px-2.5 py-2 rounded-lg bg-white/70 dark:bg-black/20 border border-amber-200 dark:border-amber-800">
            <span className="text-base flex-shrink-0">{icon(preSteps[firstIncomplete].step_key)}</span>
            <span className="text-[11px] font-semibold text-amber-900 dark:text-amber-200 flex-1">{label(preSteps[firstIncomplete].step_key, lang)}</span>
            <span className="text-[10px] font-bold text-amber-600 whitespace-nowrap">+{preSteps[firstIncomplete].xp} {l.xp}</span>
          </div>
          <p className="text-[10px] text-amber-600 dark:text-amber-400 mt-2 italic">{fb.mission.howToEarn}</p>
        </div>
      )}

      {/* Steps */}
      <div className="space-y-2">
        {preSteps.map((s, i) => {
          const done = s.status === 'completed';
          const overdue = !done && s.sla_deadline && new Date(s.sla_deadline) < new Date();
          return (
            <div key={s.step_key} className={`flex items-center gap-3 px-3 py-2.5 rounded-xl border transition-all ${done ? 'border-emerald-200 bg-emerald-50/60' : overdue ? 'border-amber-300 bg-amber-50/40' : 'border-[var(--border-subtle)] bg-[var(--surface-base)]'}`}>
              <span className={`flex-shrink-0 w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold ${done ? 'bg-emerald-500 text-white' : 'bg-teal/15 text-teal'}`}>
                {done ? '✓' : i + 1}
              </span>
              <span className="text-lg flex-shrink-0">{icon(s.step_key)}</span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className={`text-[12px] font-semibold ${done ? 'text-emerald-700 line-through' : 'text-[var(--text-primary)]'}`}>
                    {label(s.step_key, lang)}
                  </span>
                  {done && <span className="text-[10px] text-emerald-600">✓</span>}
                  {overdue && <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">SLA</span>}
                </div>
                <p className="text-[10px] text-[var(--text-muted)] mt-0.5">{hint(s.step_key, lang)}</p>
                {!done && (
                  <div className="mt-1.5 flex gap-2 flex-wrap">
                    {s.step_key === 'complete_profile' && (
                      <a href={`${lp}/profile`} className="px-2.5 py-1 rounded-lg bg-blue-100 text-blue-700 text-[10px] font-semibold no-underline hover:bg-blue-200">{l.profile}</a>
                    )}
                    {s.step_key === 'setup_credly' && (
                      <a href={`${lp}/profile`} className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-700 text-[10px] font-semibold no-underline hover:bg-amber-200">{l.profile}</a>
                    )}
                    {s.step_key === 'read_blog' && (
                      <a href={`${lp}/blog`} className="px-2.5 py-1 rounded-lg bg-purple-100 text-purple-700 text-[10px] font-semibold no-underline hover:bg-purple-200">{l.blog}</a>
                    )}
                    {s.step_key === 'start_pmi_certs' && (
                      <a href="https://www.pmi.org/learning" target="_blank" rel="noopener" className="px-2.5 py-1 rounded-lg bg-teal/10 text-teal text-[10px] font-semibold no-underline hover:bg-teal/20">{l.pmi}</a>
                    )}
                  </div>
                )}
                {/* F2 #740 — inline "how to get my Credly link" mini-guide */}
                {!done && s.step_key === 'setup_credly' && (
                  <details className="mt-1.5">
                    <summary className="text-[10px] font-semibold text-amber-700 dark:text-amber-400 cursor-pointer list-none">{fb.credly.toggle}</summary>
                    <ol className="mt-1.5 space-y-1 text-[10px] text-[var(--text-secondary)] leading-relaxed list-none pl-0">
                      <li>{fb.credly.step1}</li>
                      <li>{fb.credly.step2}</li>
                      <li>{fb.credly.step3}</li>
                    </ol>
                  </details>
                )}
              </div>
              <span className={`text-[10px] font-bold whitespace-nowrap ${done ? 'text-emerald-600' : 'text-[var(--text-muted)]'}`}>+{s.xp} {l.xp}</span>
            </div>
          );
        })}
      </div>

      {/* Leaderboard */}
      {leaderboard.length > 1 && (
        <div className="mt-4 border border-[var(--border-subtle)] rounded-xl p-3.5 bg-[var(--surface-base)]">
          <h3 className="text-[12px] font-bold text-navy mb-2 flex items-center gap-1.5">
            <span>🏆</span> {l.ranking}
          </h3>
          <div className="space-y-1.5">
            {leaderboard.slice(0, 5).map((entry, i) => (
              <div key={entry.name} className="flex items-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-[var(--surface-hover)]">
                <span className={`text-[11px] font-extrabold w-5 text-center ${i === 0 ? 'text-amber-500' : i === 1 ? 'text-gray-400' : i === 2 ? 'text-amber-700' : 'text-[var(--text-muted)]'}`}>
                  {i + 1}
                </span>
                {entry.photo_url ? (
                  <img src={entry.photo_url} alt="" className="w-5 h-5 rounded-full object-cover" />
                ) : (
                  <div className="w-5 h-5 rounded-full bg-navy/10 flex items-center justify-center text-[9px] font-bold text-navy">
                    {entry.name.charAt(0)}
                  </div>
                )}
                <span className="text-[11px] font-semibold text-[var(--text-primary)] flex-1 truncate">{entry.name}</span>
                <span className="text-[10px] font-bold text-teal">{entry.xp_earned} {l.xp}</span>
                <span className="text-[9px] text-[var(--text-muted)]">{entry.pct}%</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {allDone && (
        <div className="mt-4 text-center text-sm font-bold text-emerald-700">
          {lang.startsWith('en') ? 'All done! You\'re ready for onboarding.' : lang.startsWith('es') ? '¡Todo listo! Estás preparado para la integración.' : 'Tudo pronto! Você está preparado para o onboarding.'}
        </div>
      )}

      {/* F1/J3 #740 — collective WhatsApp help group so a newcomer is never isolated */}
      <div className="mt-4 border border-emerald-200 dark:border-emerald-800 rounded-xl p-3.5 bg-emerald-50/50 dark:bg-emerald-900/15">
        <h3 className="text-[12px] font-bold text-emerald-800 dark:text-emerald-300 flex items-center gap-1.5">
          <span>💬</span> {l.helpTitle}
        </h3>
        <p className="text-[11px] text-emerald-700 dark:text-emerald-400 mt-1 leading-relaxed">{l.helpBody}</p>
        <a
          href={PRE_ONBOARDING_WHATSAPP_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-block mt-2.5 px-3 py-1.5 rounded-lg bg-emerald-600 text-white text-[11px] font-bold no-underline hover:bg-emerald-700 transition-colors"
        >
          {l.helpCta} →
        </a>
      </div>
    </div>
  );
}
