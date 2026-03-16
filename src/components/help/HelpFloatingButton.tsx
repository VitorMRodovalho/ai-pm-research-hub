import { useState, useEffect, useRef } from 'react';
import { hasPermission, type MemberForPermission } from '../../lib/permissions';

// ── FAQ Data ──

interface FaqItem {
  id: string;
  section: 'getting_started' | 'workspace' | 'leaders' | 'admin';
  question: string;
  answer: string;
}

const FAQ_PT: FaqItem[] = [
  { id: 'overview', section: 'getting_started', question: 'Como funciona o Hub?', answer: 'O AI & PM Research Hub é a plataforma digital do Núcleo de Estudos e Pesquisa em IA e GP. Ele centraliza boards de entregáveis, gamificação, eventos, presença, publicações e metas do ciclo em um único lugar. Acesse seu Workspace após login para ver tudo relevante ao seu papel.' },
  { id: 'login', section: 'getting_started', question: 'Como fazer login?', answer: 'Use o botão "Entrar" no topo do site. Você pode usar Google (recomendado), LinkedIn, ou Magic Link (link enviado por email). Use o mesmo email cadastrado no Núcleo.' },
  { id: 'profile', section: 'getting_started', question: 'Como completar meu perfil?', answer: 'Após login, clique na sua foto/avatar no canto superior direito → Configurações. Adicione foto, username do Credly (para sync automático de badges), e confirme seus dados.' },
  { id: 'gamification', section: 'getting_started', question: 'Como funciona a gamificação?', answer: 'Você ganha XP por: presença em reuniões (10 XP), certificações PMI (25-50 XP dependendo do nível), badges Credly da trilha (20 XP cada), e entregas concluídas. O ranking é visível para todos na página Gamificação.' },
  { id: 'trail', section: 'getting_started', question: 'Como completar a Trilha PMI?', answer: 'A Trilha PMI tem 6 cursos obrigatórios gratuitos no PMI.org. Acesse "Trilha IA" no menu, veja quais cursos faltam, e complete-os no site do PMI. Seus badges do Credly são sincronizados automaticamente a cada 5 dias.' },
  { id: 'deliverables', section: 'workspace', question: 'Como ver minhas entregas?', answer: 'No Workspace, a seção "Minha Tribo" mostra o board da sua tribo com todos os entregáveis. Use as views Kanban, Tabela, Lista, Calendário ou Timeline para visualizar de formas diferentes.' },
  { id: 'attendance', section: 'workspace', question: 'Como registrar presença?', answer: 'No Workspace, seção "Registrar Presença", selecione o evento e confirme. A presença vale 10 XP na gamificação. Líderes podem registrar presença em lote para toda a tribo.' },
  { id: 'ranking', section: 'workspace', question: 'Como ver meu ranking?', answer: 'Acesse "Gamificação" no menu superior. Seu ranking, XP total, e detalhamento por categoria (presença, certificações, trilha, entregas) estão lá. O ícone ao lado mostra a tabela completa de pontuação.' },
  { id: 'publications', section: 'workspace', question: 'Como submeter publicações?', answer: 'Acesse "Publicações" no menu ou via Workspace → "Minhas Publicações". Clique em "Nova Submissão", preencha título, resumo, tipo de alvo (conferência PMI, periódico, blog), e envie. O pipeline de status acompanha desde rascunho até publicação.' },
  { id: 'create_cards', section: 'leaders', question: 'Como criar cards no board?', answer: 'No board da tribo, clique em "+ Novo Card" no canto superior direito. Preencha título, descrição, assignee, datas (baseline, forecast, actual), e tags. O card aparece na coluna Backlog.' },
  { id: 'drag_drop', section: 'leaders', question: 'Como arrastar cards entre colunas?', answer: 'Na view Kanban, clique e segure o card, arraste para a coluna desejada (Backlog → A Fazer → Em Andamento → Revisão → Concluído). Solte quando a área de destino ficar destacada. Isso atualiza o status automaticamente.' },
  { id: 'checklists', section: 'leaders', question: 'Como gerenciar checklists?', answer: 'Clique em um card para abrir o detalhe. Na seção "Checklist", adicione itens. Marque como concluído conforme a equipe avança. O progresso aparece como barra no card.' },
  { id: 'batch_attendance', section: 'leaders', question: 'Como registrar presença em lote?', answer: 'Na página de Eventos, encontre a reunião da tribo e clique em "Presença em Lote". Marque os membros presentes e confirme. Todos recebem XP automaticamente.' },
  { id: 'tier_viewer', section: 'admin', question: 'Como usar o Tier Viewer?', answer: 'O botão "Simular Tier" aparece no canto superior direito (só para superadmins). Selecione um papel (Pesquisador, Sponsor, Líder), designações opcionais, e tribo. A plataforma mostra exatamente o que aquele papel veria. Clique "Sair" para voltar ao normal.' },
  { id: 'export_pdf', section: 'admin', question: 'Como exportar o relatório do ciclo?', answer: 'Acesse Admin → Relatório Executivo. A página mostra o relatório completo do ciclo com KPIs, tribos, gamificação, pilotos. Clique "Exportar PDF" para gerar o documento para apresentação ao PMI.' },
  { id: 'manage_members', section: 'admin', question: 'Como gerenciar membros?', answer: 'Admin → Painel Admin mostra todos os membros com filtros por tier, tribo, status. Clique em um membro para editar papel, designações, tribo, status ativo. Alterações são registradas na governança.' },
  { id: 'send_campaigns', section: 'admin', question: 'Como enviar campanhas?', answer: 'Admin → Campanhas lista os templates disponíveis. Clique "Enviar" no template desejado, confirme a audiência, e envie. O histórico de envios fica na aba "Histórico".' },
  { id: 'adoption', section: 'admin', question: 'Como ver analytics de adoção?', answer: 'Admin → Adoção mostra quem acessou a plataforma, quando, e com que frequência. Indicadores por tribo e por tier ajudam a identificar quem precisa de suporte no onboarding.' },
];

const FAQ_EN: FaqItem[] = [
  { id: 'overview', section: 'getting_started', question: 'How does the Hub work?', answer: 'The AI & PM Research Hub is the digital platform of the AI & PM Study and Research Group. It centralizes deliverable boards, gamification, events, attendance, publications, and cycle goals in one place. Access your Workspace after login to see everything relevant to your role.' },
  { id: 'login', section: 'getting_started', question: 'How to log in?', answer: 'Use the "Sign In" button at the top. You can use Google (recommended), LinkedIn, or Magic Link (link sent by email). Use the same email registered with the Group.' },
  { id: 'profile', section: 'getting_started', question: 'How to complete my profile?', answer: 'After login, click your avatar in the top right → Settings. Add a photo, Credly username (for automatic badge sync), and confirm your data.' },
  { id: 'gamification', section: 'getting_started', question: 'How does gamification work?', answer: 'You earn XP for: meeting attendance (10 XP), PMI certifications (25-50 XP depending on level), Credly trail badges (20 XP each), and completed deliverables. Rankings are visible to everyone on the Gamification page.' },
  { id: 'trail', section: 'getting_started', question: 'How to complete the PMI Trail?', answer: 'The PMI Trail has 6 mandatory free courses on PMI.org. Go to "AI Trail" in the menu, see which courses are missing, and complete them on PMI\'s site. Your Credly badges sync automatically every 5 days.' },
  { id: 'deliverables', section: 'workspace', question: 'How to see my deliverables?', answer: 'In Workspace, the "My Tribe" section shows your tribe\'s board with all deliverables. Use Kanban, Table, List, Calendar, or Timeline views.' },
  { id: 'attendance', section: 'workspace', question: 'How to register attendance?', answer: 'In Workspace, "Register Attendance" section, select the event and confirm. Attendance is worth 10 XP. Leaders can batch-register for the whole tribe.' },
  { id: 'ranking', section: 'workspace', question: 'How to see my ranking?', answer: 'Go to "Gamification" in the top menu. Your ranking, total XP, and breakdown by category are there.' },
  { id: 'publications', section: 'workspace', question: 'How to submit publications?', answer: 'Go to "Publications" in the menu or Workspace → "My Publications". Click "New Submission", fill in title, abstract, target type, and submit.' },
  { id: 'create_cards', section: 'leaders', question: 'How to create board cards?', answer: 'On the tribe board, click "+ New Card" in the top right. Fill in title, description, assignee, dates, and tags.' },
  { id: 'drag_drop', section: 'leaders', question: 'How to drag cards between columns?', answer: 'In Kanban view, click and hold a card, drag to the desired column. Release when the drop area is highlighted.' },
  { id: 'checklists', section: 'leaders', question: 'How to manage checklists?', answer: 'Click a card to open details. In "Checklist", add items and mark as done. Progress shows as a bar on the card.' },
  { id: 'batch_attendance', section: 'leaders', question: 'How to batch register attendance?', answer: 'On the Events page, find the tribe meeting and click "Batch Attendance". Check present members and confirm.' },
  { id: 'tier_viewer', section: 'admin', question: 'How to use the Tier Viewer?', answer: 'The "Simulate Tier" button appears in the top right (superadmins only). Select a role, optional designations, and tribe to see what that role would see.' },
  { id: 'export_pdf', section: 'admin', question: 'How to export the cycle report?', answer: 'Go to Admin → Executive Report. Click "Export PDF" to generate the document.' },
  { id: 'manage_members', section: 'admin', question: 'How to manage members?', answer: 'Admin → Admin Panel shows all members with filters by tier, tribe, status. Click a member to edit.' },
  { id: 'send_campaigns', section: 'admin', question: 'How to send campaigns?', answer: 'Admin → Campaigns lists available templates. Click "Send", confirm audience, and send.' },
  { id: 'adoption', section: 'admin', question: 'How to view adoption analytics?', answer: 'Admin → Adoption shows who accessed the platform, when, and how often.' },
];

const FAQ_ES: FaqItem[] = [
  { id: 'overview', section: 'getting_started', question: '¿Cómo funciona el Hub?', answer: 'El AI & PM Research Hub es la plataforma digital del Núcleo de Estudios e Investigación en IA y GP. Centraliza boards, gamificación, eventos, asistencia, publicaciones y metas del ciclo en un solo lugar.' },
  { id: 'login', section: 'getting_started', question: '¿Cómo iniciar sesión?', answer: 'Use el botón "Entrar" arriba. Puede usar Google (recomendado), LinkedIn o Magic Link. Use el mismo correo registrado.' },
  { id: 'profile', section: 'getting_started', question: '¿Cómo completar mi perfil?', answer: 'Después de iniciar sesión, haga clic en su avatar → Configuraciones. Agregue foto, nombre de Credly y confirme sus datos.' },
  { id: 'gamification', section: 'getting_started', question: '¿Cómo funciona la gamificación?', answer: 'Gana XP por: asistencia (10 XP), certificaciones PMI (25-50 XP), badges Credly (20 XP), y entregas completadas.' },
  { id: 'trail', section: 'getting_started', question: '¿Cómo completar la Ruta PMI?', answer: 'La Ruta PMI tiene 6 cursos obligatorios gratuitos en PMI.org. Sus badges de Credly se sincronizan automáticamente.' },
  { id: 'deliverables', section: 'workspace', question: '¿Cómo ver mis entregas?', answer: 'En Workspace, la sección "Mi Tribu" muestra el board con todos los entregables.' },
  { id: 'attendance', section: 'workspace', question: '¿Cómo registrar asistencia?', answer: 'En Workspace, seleccione el evento y confirme. La asistencia vale 10 XP.' },
  { id: 'ranking', section: 'workspace', question: '¿Cómo ver mi ranking?', answer: 'Acceda a "Gamificación" en el menú. Su ranking y XP total están allí.' },
  { id: 'publications', section: 'workspace', question: '¿Cómo enviar publicaciones?', answer: 'Vaya a "Publicaciones" y haga clic en "Nueva Submisión".' },
  { id: 'create_cards', section: 'leaders', question: '¿Cómo crear cards?', answer: 'En el board, haga clic en "+ Nuevo Card" y complete los campos.' },
  { id: 'drag_drop', section: 'leaders', question: '¿Cómo arrastrar cards?', answer: 'En vista Kanban, haga clic y arrastre el card a la columna deseada.' },
  { id: 'checklists', section: 'leaders', question: '¿Cómo gestionar checklists?', answer: 'Haga clic en un card y en "Checklist" agregue ítems.' },
  { id: 'batch_attendance', section: 'leaders', question: '¿Cómo registrar asistencia en lote?', answer: 'En Eventos, busque la reunión y haga clic en "Asistencia en Lote".' },
  { id: 'tier_viewer', section: 'admin', question: '¿Cómo usar el Tier Viewer?', answer: 'El botón "Simular Tier" aparece para superadmins. Seleccione un rol y tribu para simular.' },
  { id: 'export_pdf', section: 'admin', question: '¿Cómo exportar el informe?', answer: 'Admin → Informe Ejecutivo → "Exportar PDF".' },
  { id: 'manage_members', section: 'admin', question: '¿Cómo gestionar miembros?', answer: 'Admin → Panel Admin muestra todos los miembros con filtros.' },
  { id: 'send_campaigns', section: 'admin', question: '¿Cómo enviar campañas?', answer: 'Admin → Campañas lista los templates disponibles.' },
  { id: 'adoption', section: 'admin', question: '¿Cómo ver adopción?', answer: 'Admin → Adopción muestra quién accedió a la plataforma.' },
];

const SECTION_LABELS: Record<string, Record<string, string>> = {
  getting_started: { pt: 'Começando', en: 'Getting Started', es: 'Empezando' },
  workspace: { pt: 'Seu Workspace', en: 'Your Workspace', es: 'Tu Workspace' },
  leaders: { pt: 'Para Líderes de Tribo', en: 'For Tribe Leaders', es: 'Para Líderes de Tribu' },
  admin: { pt: 'Para Administradores', en: 'For Administrators', es: 'Para Administradores' },
};

const LABELS: Record<string, Record<string, string>> = {
  title: { pt: 'Central de Ajuda', en: 'Help Center', es: 'Centro de Ayuda' },
  links: { pt: 'Links Úteis', en: 'Useful Links', es: 'Enlaces Útiles' },
  contact: { pt: 'Contato', en: 'Contact', es: 'Contacto' },
  version: { pt: 'Versão', en: 'Version', es: 'Versión' },
};

function getFaq(locale: string): FaqItem[] {
  if (locale.startsWith('en')) return FAQ_EN;
  if (locale.startsWith('es')) return FAQ_ES;
  return FAQ_PT;
}

function getLang(locale: string): string {
  if (locale.startsWith('en')) return 'en';
  if (locale.startsWith('es')) return 'es';
  return 'pt';
}

// ── Component ──

interface Props {
  locale?: string;
}

export default function HelpFloatingButton({ locale = 'pt-BR' }: Props) {
  const [open, setOpen] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [member, setMember] = useState<MemberForPermission | null>(null);
  const [siteVersion, setSiteVersion] = useState('development');
  const panelRef = useRef<HTMLDivElement>(null);

  const lang = getLang(locale);
  const faq = getFaq(locale);

  useEffect(() => {
    const handler = (e: Event) => {
      const m = (e as CustomEvent).detail;
      if (m) setMember(m);
    };
    window.addEventListener('nav:member', handler);
    const existing = (window as any).navGetMember?.();
    if (existing) setMember(existing);

    // Get version
    const versionEl = document.getElementById('footer-version');
    if (versionEl?.textContent && versionEl.textContent !== 'development') {
      setSiteVersion(versionEl.textContent);
    }

    return () => window.removeEventListener('nav:member', handler);
  }, []);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open]);

  // Close on click outside
  useEffect(() => {
    if (!open) return;
    const onClick = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    setTimeout(() => document.addEventListener('click', onClick), 0);
    return () => document.removeEventListener('click', onClick);
  }, [open]);

  // Don't show if not authenticated
  if (!member) return null;

  const canSeeLeaders = hasPermission(member, 'board.create_item');
  const canSeeAdmin = hasPermission(member, 'admin.access');

  const sections: { key: string; visible: boolean }[] = [
    { key: 'getting_started', visible: true },
    { key: 'workspace', visible: true },
    { key: 'leaders', visible: canSeeLeaders },
    { key: 'admin', visible: canSeeAdmin },
  ];

  const visibleFaq = faq.filter(item => {
    const sec = sections.find(s => s.key === item.section);
    return sec?.visible;
  });

  return (
    <>
      {/* Floating button */}
      {!open && (
        <button
          onClick={() => setOpen(true)}
          className="fixed bottom-4 right-4 z-40 w-12 h-12 rounded-full bg-[var(--surface-elevated)] border border-[var(--border-default)] shadow-lg flex items-center justify-center text-lg font-bold text-teal hover:scale-110 transition-transform cursor-pointer"
          aria-label={LABELS.title[lang]}
        >
          ?
        </button>
      )}

      {/* Panel */}
      {open && (
        <>
          <div className="fixed inset-0 z-40 bg-black/20" onClick={() => setOpen(false)} />
          <div
            ref={panelRef}
            className="fixed top-0 right-0 z-50 h-full w-full sm:w-[400px] bg-[var(--surface-elevated)] border-l border-[var(--border-default)] shadow-2xl flex flex-col animate-slide-in-right"
          >
            {/* Header */}
            <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--border-default)]">
              <h2 className="text-base font-bold text-[var(--text-primary)]">
                {LABELS.title[lang]}
              </h2>
              <button
                onClick={() => setOpen(false)}
                className="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-[var(--surface-hover)] text-[var(--text-muted)] cursor-pointer border-0 bg-transparent text-lg"
              >
                &times;
              </button>
            </div>

            {/* Scrollable content */}
            <div className="flex-1 overflow-y-auto px-4 py-3 space-y-4">
              {sections.filter(s => s.visible).map(sec => {
                const sectionItems = visibleFaq.filter(f => f.section === sec.key);
                if (!sectionItems.length) return null;
                return (
                  <div key={sec.key}>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2 px-1">
                      {SECTION_LABELS[sec.key]?.[lang] || sec.key}
                    </div>
                    <div className="space-y-1">
                      {sectionItems.map(item => (
                        <div key={item.id} className="rounded-lg overflow-hidden">
                          <button
                            onClick={() => setExpandedId(expandedId === item.id ? null : item.id)}
                            className="w-full text-left px-3 py-2 text-[.8rem] font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] transition-colors cursor-pointer border-0 bg-transparent flex items-center gap-2"
                          >
                            <span className={`text-[.6rem] text-[var(--text-muted)] transition-transform ${expandedId === item.id ? 'rotate-90' : ''}`}>
                              &#9654;
                            </span>
                            {item.question}
                          </button>
                          {expandedId === item.id && (
                            <div className="px-3 pb-3 pl-7 text-[.75rem] text-[var(--text-secondary)] leading-relaxed">
                              {item.answer}
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}

              {/* Links */}
              <div>
                <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2 px-1">
                  {LABELS.links[lang]}
                </div>
                <div className="space-y-1 text-[.8rem]">
                  <a href="/privacy" className="flex items-center gap-2 px-3 py-2 text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-lg no-underline transition-colors">
                    <span className="w-4 text-center">&#128220;</span>
                    {lang === 'en' ? 'Privacy Policy' : lang === 'es' ? 'Politica de Privacidad' : 'Politica de Privacidade'}
                  </a>
                  <a href="https://github.com/VitorMRodovalho/ai-pm-research-hub" target="_blank" rel="noopener noreferrer" className="flex items-center gap-2 px-3 py-2 text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-lg no-underline transition-colors">
                    <span className="w-4 text-center">&#128187;</span>
                    GitHub
                  </a>
                  <a href="mailto:nucleoiagp@gmail.com" className="flex items-center gap-2 px-3 py-2 text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-lg no-underline transition-colors">
                    <span className="w-4 text-center">&#128231;</span>
                    nucleoiagp@gmail.com
                  </a>
                </div>
              </div>
            </div>

            {/* Footer */}
            <div className="px-4 py-2 border-t border-[var(--border-default)] text-[.65rem] text-[var(--text-muted)]">
              {LABELS.version[lang]}: {siteVersion}
            </div>
          </div>
        </>
      )}

      <style>{`
        @keyframes slideInRight {
          from { transform: translateX(100%); }
          to { transform: translateX(0); }
        }
        .animate-slide-in-right {
          animation: slideInRight 0.2s ease-out;
        }
      `}</style>
    </>
  );
}
