import { useState, useEffect, useCallback } from 'react';

// #740: persistent pointer to the Hub's general WhatsApp group on /workspace.
//
// The invite is never in the bundle: whoever joins a group sees its members' phone numbers. It lives
// in site_config and get_community_group_link serves it only to active members with the volunteer
// term signed (the tribe-group rule) or to platform admins, so this island self-gates on the RPC
// answer and renders nothing otherwise. "Already in the group" hides it on this device; there is no
// TTL, because being in the group does not expire the way a pending governance nudge does.

interface Props {
  lang?: string;
}

const DISMISS_KEY = 'nucleo:generalGroupCardDismissed';

interface Copy {
  ariaLabel: string;
  title: string;
  body: string;
  cta: string;
  dismiss: string;
}

// Inline trilingual (sibling-island idiom: no t(), so no 3-dict surface).
const COPY: Record<string, Copy> = {
  'pt-BR': {
    ariaLabel: 'Grupo geral do Núcleo no WhatsApp',
    title: '💬 Grupo geral do Núcleo no WhatsApp',
    body: 'É o grupo de todo o Núcleo: avisos das reuniões gerais, materiais e troca de conhecimento sobre IA e gerenciamento de projetos.',
    cta: 'Entrar no grupo geral',
    dismiss: 'Já estou no grupo',
  },
  'en-US': {
    ariaLabel: 'The Hub general WhatsApp group',
    title: '💬 The Hub general WhatsApp group',
    body: 'The group for the whole Hub: general meeting notices, materials and knowledge sharing on AI and project management.',
    cta: 'Join the general group',
    dismiss: "I'm already in",
  },
  'es-LATAM': {
    ariaLabel: 'Grupo general del Núcleo en WhatsApp',
    title: '💬 Grupo general del Núcleo en WhatsApp',
    body: 'Es el grupo de todo el Núcleo: avisos de las reuniones generales, materiales e intercambio de conocimiento sobre IA y gestión de proyectos.',
    cta: 'Entrar al grupo general',
    dismiss: 'Ya estoy en el grupo',
  },
};
function copyFor(lang: string): Copy {
  if (lang.startsWith('en')) return COPY['en-US'];
  if (lang.startsWith('es')) return COPY['es-LATAM'];
  return COPY['pt-BR'];
}

export default function GeneralGroupCard({ lang = 'pt-BR' }: Props) {
  const c = copyFor(lang);
  const [url, setUrl] = useState<string | null>(null);
  const [hidden, setHidden] = useState(false);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    try {
      if (localStorage.getItem(DISMISS_KEY)) { setHidden(true); return; }
    } catch { /* localStorage blocked: show the card */ }
    const sb = getSb();
    if (!sb) return;
    try {
      const { data } = await sb.rpc('get_community_group_link', { p_group: 'general' });
      if (data?.success && data.whatsapp_url) setUrl(data.whatsapp_url);
    } catch { /* non-blocking */ }
  }, [getSb]);

  // Boot like the sibling islands: wait for the nav member, then load.
  useEffect(() => {
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) load();
      else setTimeout(boot, 500);
    };
    boot();
  }, [load]);

  const dismiss = useCallback(() => {
    try { localStorage.setItem(DISMISS_KEY, '1'); } catch { /* ignore */ }
    setHidden(true);
  }, []);

  if (hidden || !url) return null;

  return (
    <section
      role="region"
      aria-label={c.ariaLabel}
      className="mb-6 rounded-2xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50/50 dark:bg-emerald-900/15 p-4"
    >
      <h2 className="text-[13px] font-bold text-emerald-800 dark:text-emerald-300">{c.title}</h2>
      <p className="text-[11px] text-emerald-700 dark:text-emerald-400 mt-1 leading-relaxed">{c.body}</p>
      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        <a
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          className="min-h-[44px] inline-flex items-center px-3 rounded-lg bg-emerald-600 text-white text-[11px] font-bold no-underline hover:bg-emerald-700 transition-colors"
        >
          {c.cta} →
        </a>
        <button
          type="button"
          onClick={dismiss}
          className="min-h-[44px] px-3 rounded-lg bg-transparent border border-emerald-300 dark:border-emerald-700 text-emerald-700 dark:text-emerald-300 text-[11px] font-semibold cursor-pointer hover:bg-emerald-100/60 dark:hover:bg-emerald-900/30"
        >
          {c.dismiss}
        </button>
      </div>
    </section>
  );
}
