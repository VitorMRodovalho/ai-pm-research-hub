/**
 * VerticalsSection — Cycle 4 landing, the "para quem" axis of the fused "O Modelo" section (R3).
 *
 * Renders the §5a radial hub-and-spoke as THE pitch: center = Núcleo + IA (the seam),
 * spokes = the verticals (each spoke a community/credential), the Champion → CPMAI ladder is
 * the common spine. Reads community_vertical initiatives LIVE via get_public_verticals() (B1,
 * anon-safe) — nothing is hardcoded; the diagram renders whatever verticals exist. Forming
 * verticals surface researcher/leader CTAs → InterestForm → capture_visitor_lead(target_vertical) (#2738).
 *
 * R3 change: this component no longer owns a <section>/header (the parent ModelSection.astro
 * does, fusing it with the quadrants axis). It exposes only the radial + ladder + cards block.
 * No rebrand: reuses existing palette tokens; the orange accent marks the protagonista CTA.
 */
import { useEffect, useState } from 'react';
import { InterestForm, type InterestRole } from './InterestForm';

// #2738: os botões de pesquisador e líder abriam duas vagas do VEP com prazo vencido (31/07 e
// 13/09/2026). Agora abrem o formulário de interesse (InterestForm), o mesmo da ResourcesSection.

// #2738: canal de contato para propor uma vertical nova (o mesmo do rodapé e da seção de capítulos).
const CONTACT_EMAIL = 'nucleoia@pmigo.org.br';

type Vertical = {
  id: string;
  // Raw DB title (pt-BR). Stays the lookup key for VERTICAL_DESC and analytics.
  title: string;
  // Localized label for display, resolved from the i18n dictionaries by ModelSection.astro.
  label?: string;
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
    hubAria: 'Núcleo + IA, a comunidade no centro das verticais',
    radialAria: 'Diagrama radial: Núcleo + IA no centro, cada raio é uma vertical de comunidade',
    empty: 'As verticais do Ciclo 4 estão sendo formadas. Em breve aqui.',
    morePre: 'Algumas verticais já têm linha de pesquisa ativa: veja ',
    moreLink: 'Linhas de Pesquisa',
    moreMid: ' abaixo. Sua área não está aqui? Novas verticais abrem quando profissionais as propõem: escreva para ',
    moreEnd: '.',
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
    hubAria: 'Núcleo + AI, the community at the center of the verticals',
    radialAria: 'Radial diagram: Núcleo + AI at the center, each spoke is a community vertical',
    empty: 'The Cycle 4 verticals are being formed. Coming soon.',
    morePre: 'Some verticals already have an active research stream: see ',
    moreLink: 'Research Streams',
    moreMid: " below. Don't see your field? New verticals open when practitioners propose them: write to ",
    moreEnd: '.',
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
    hubAria: 'Núcleo + IA, la comunidad en el centro de las verticales',
    radialAria: 'Diagrama radial: Núcleo + IA en el centro, cada radio es una vertical de comunidad',
    empty: 'Las verticales del Ciclo 4 se están formando. Pronto aquí.',
    morePre: 'Algunas verticales ya tienen una línea de investigación activa: mira ',
    moreLink: 'Líneas de Investigación',
    moreMid: ' abajo. ¿No ves tu área? Se abren nuevas verticales cuando profesionales las proponen: escribe a ',
    moreEnd: '.',
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
 * Read-only pitch visual; the actionable layer (CTA/interest form) is the cards below. Nodes are
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
            <div className="font-bold text-[.8rem] leading-tight text-[var(--text-primary)]">{nd.v.label || nd.v.title}</div>
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

function VerticalCard({ v, l, lang, formLabels }: { v: Vertical; l: Record<string, string>; lang: Lang; formLabels: Record<string, string> }) {
  const isForming = v.vertical_status === 'forming';
  const [applyRole, setApplyRole] = useState<InterestRole | null>(null);
  const lp = lang === 'pt-BR' ? '' : lang === 'en-US' ? '/en' : '/es';
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
      <h3 className="font-bold text-lg text-[var(--text-primary)] mb-1">{v.label || v.title}</h3>
      {/* PD-CERT-4 + GAP-B2.C: description by CONTEXT of practice, authored credential-free in all 3
          langs (VERTICAL_DESC). NEVER renders the DB `description` (it embeds the PMI credential). */}
      {verticalDesc(lang, v.title) && <p className="text-sm text-[var(--text-secondary)] mb-2">{verticalDesc(lang, v.title)}</p>}
      {/* partner_org NOT rendered: claiming "Parceria: Global Construction Ambassadors" without a
          signed agreement is an unsubstantiated partnership claim (same paper-trail rule as
          co-branding). Members may individually be ambassadors, but the org has no formal accord.
          Re-enable per-vertical only when backed by a signed instrument. DB scrub: DONE (mig 229). */}
      {/* #2738: os dois botões abrem o formulário de interesse com o papel do botão e o id do card. */}
      {isForming && (
        <div className="mt-3 flex flex-col gap-2">
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => setApplyRole('researcher')} aria-expanded={applyRole === 'researcher'} data-apply-role="researcher"
              className="inline-flex items-center gap-1 px-4 py-2 rounded-xl font-semibold text-sm text-white border-0 cursor-pointer bg-[var(--color-orange-deep)]">
              {l.ctaResearcher} →
            </button>
            <button type="button" onClick={() => setApplyRole('leader')} aria-expanded={applyRole === 'leader'} data-apply-role="leader"
              className="inline-flex items-center gap-1 px-4 py-2 rounded-xl font-semibold text-sm text-teal bg-transparent cursor-pointer border border-teal/40 hover:bg-teal/5 transition-colors">
              {l.ctaLeader} →
            </button>
          </div>
          {applyRole && (
            <InterestForm key={applyRole} roleInterest={applyRole} source="apply-vertical" targetVertical={v.id}
              labels={formLabels} messageKey="messageVertical" lp={lp} onClose={() => setApplyRole(null)} />
          )}
        </div>
      )}
    </div>
  );
}

export default function VerticalsSection({ lang = 'pt-BR', titles = {}, formLabels = {} }: { lang?: Lang; titles?: Record<string, string>; formLabels?: Record<string, string> }) {
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
        if (!cancelled && !error && Array.isArray(data)) {
          setVerticals(data.map((v: Vertical) => ({ ...v, label: titles[v.title] || v.title })));
        }
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
            {verticals.map(v => <VerticalCard key={v.id} v={v} l={l} lang={lang} formLabels={formLabels} />)}
          </div>

          {/* #2738: quem chega por uma área (construção, PMO, ágil) precisa saber que já existe linha de
              pesquisa ativa e que outras podem abrir. Texto aprovado pelo GP em 19/10/2026. */}
          <p className="text-sm text-[var(--text-secondary)] text-center max-w-[620px] mx-auto mt-8">
            {l.morePre}<a href="#tribes" className="text-teal font-semibold underline">{l.moreLink}</a>{l.moreMid}<a href={`mailto:${CONTACT_EMAIL}`} className="text-teal font-semibold underline">{CONTACT_EMAIL}</a>{l.moreEnd}
          </p>
        </>
      )}
    </div>
  );
}
