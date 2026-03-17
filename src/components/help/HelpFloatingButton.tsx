import { useState, useEffect, useRef } from 'react';
import { hasPermission, type MemberForPermission } from '../../lib/permissions';

// ── FAQ Data (trilingual per item) ──

interface FaqItem {
  id: string;
  section: 'getting_started' | 'workspace' | 'leaders' | 'admin' | 'troubleshooting';
  question: Record<string, string>;
  answer: Record<string, string>;
}

const FAQ_ITEMS: FaqItem[] = [
  // ══════════════════════════════════════════
  // COMEÇANDO
  // ══════════════════════════════════════════
  {
    id: 'overview', section: 'getting_started',
    question: { 'pt-BR': 'O que é o Hub?', 'en-US': 'What is the Hub?', 'es-LATAM': '¿Qué es el Hub?' },
    answer: {
      'pt-BR': 'O AI & PM Research Hub é a plataforma digital do Núcleo de Estudos e Pesquisa em IA e GP. Centraliza boards de entregáveis, gamificação, eventos, presença, publicações e metas do ciclo em um único lugar. Após login, acesse seu Workspace para ver tudo relevante ao seu papel.',
      'en-US': 'The AI & PM Research Hub is the digital platform for the AI & PM Study and Research Group. It centralizes deliverable boards, gamification, events, attendance, publications, and cycle goals in one place. After logging in, visit your Workspace to see everything relevant to your role.',
      'es-LATAM': 'El AI & PM Research Hub es la plataforma digital del Núcleo de Estudios e Investigación en IA y GP. Centraliza tableros de entregables, gamificación, eventos, asistencia, publicaciones y metas del ciclo en un solo lugar. Después de iniciar sesión, acceda a su Workspace.',
    },
  },
  {
    id: 'login', section: 'getting_started',
    question: { 'pt-BR': 'Como fazer login?', 'en-US': 'How do I log in?', 'es-LATAM': '¿Cómo inicio sesión?' },
    answer: {
      'pt-BR': 'Clique em "Entrar" no topo do site. Você pode usar Google (recomendado), LinkedIn, ou Magic Link (link enviado por email). Use o mesmo email cadastrado no Núcleo.',
      'en-US': 'Click "Sign In" at the top of the site. You can use Google (recommended), LinkedIn, or Magic Link (sent via email). Use the same email registered with the Group.',
      'es-LATAM': 'Haga clic en "Iniciar sesión" en la parte superior del sitio. Puede usar Google (recomendado), LinkedIn o Magic Link (enviado por correo). Use el mismo correo registrado en el Núcleo.',
    },
  },
  {
    id: 'profile', section: 'getting_started',
    question: { 'pt-BR': 'Como completar meu perfil?', 'en-US': 'How do I complete my profile?', 'es-LATAM': '¿Cómo completo mi perfil?' },
    answer: {
      'pt-BR': 'Após login, clique no seu avatar no canto superior direito → "Configurações". Adicione foto, username do Credly (para sync automático de badges), e confirme seus dados.',
      'en-US': 'After logging in, click your avatar in the top right → "Settings". Add a photo, your Credly username (for automatic badge sync), and confirm your details.',
      'es-LATAM': 'Después de iniciar sesión, haga clic en su avatar en la esquina superior derecha → "Configuraciones". Agregue foto, nombre de usuario de Credly (para sincronización automática de insignias) y confirme sus datos.',
    },
  },
  {
    id: 'gamification', section: 'getting_started',
    question: { 'pt-BR': 'Como funciona a gamificação?', 'en-US': 'How does gamification work?', 'es-LATAM': '¿Cómo funciona la gamificación?' },
    answer: {
      'pt-BR': 'Você ganha XP por: presença em reuniões (10 XP), certificações PMI (25-50 XP dependendo do nível), badges Credly da Trilha PMI (20 XP cada), e entregas concluídas. O ranking é visível para todos na página "Gamificação" no menu superior.',
      'en-US': 'You earn XP for: meeting attendance (10 XP), PMI certifications (25-50 XP depending on level), PMI Trail Credly badges (20 XP each), and completed deliverables. The ranking is visible to everyone on the "Gamification" page in the top menu.',
      'es-LATAM': 'Gana XP por: asistencia a reuniones (10 XP), certificaciones PMI (25-50 XP según nivel), insignias Credly de la Ruta PMI (20 XP cada una) y entregables completados. El ranking es visible para todos en la página "Gamificación" del menú superior.',
    },
  },
  {
    id: 'trail', section: 'getting_started',
    question: { 'pt-BR': 'Como completar a Trilha PMI?', 'en-US': 'How do I complete the PMI Trail?', 'es-LATAM': '¿Cómo completo la Ruta PMI?' },
    answer: {
      'pt-BR': 'A Trilha PMI tem 6 cursos obrigatórios gratuitos no PMI.org. Acesse "Trilha IA" no menu superior para ver quais cursos faltam. Complete-os no site do PMI e seus badges do Credly serão sincronizados automaticamente a cada 5 dias.',
      'en-US': 'The PMI Trail has 6 free mandatory courses on PMI.org. Go to "AI Trail" in the top menu to see which courses are pending. Complete them on the PMI website and your Credly badges will sync automatically every 5 days.',
      'es-LATAM': 'La Ruta PMI tiene 6 cursos obligatorios gratuitos en PMI.org. Acceda a "Ruta IA" en el menú superior para ver cuáles faltan. Complételos en el sitio de PMI y sus insignias de Credly se sincronizarán automáticamente cada 5 días.',
    },
  },

  // ══════════════════════════════════════════
  // SEU WORKSPACE
  // ══════════════════════════════════════════
  {
    id: 'workspace', section: 'workspace',
    question: { 'pt-BR': 'O que é o Workspace?', 'en-US': 'What is the Workspace?', 'es-LATAM': '¿Qué es el Workspace?' },
    answer: {
      'pt-BR': 'O Workspace é sua página principal após login. Mostra: sua tribo e board de entregáveis, alertas operacionais, membros em risco de dropout, KPIs do ciclo, formulário de presença, e cards de acesso rápido (publicações, gamificação, biblioteca).',
      'en-US': 'The Workspace is your main page after login. It shows: your tribe and deliverable board, operational alerts, dropout risk members, cycle KPIs, attendance form, and quick access cards (publications, gamification, library).',
      'es-LATAM': 'El Workspace es su página principal después de iniciar sesión. Muestra: su tribu y tablero de entregables, alertas operativas, miembros en riesgo de abandono, KPIs del ciclo, formulario de asistencia y tarjetas de acceso rápido.',
    },
  },
  {
    id: 'deliverables', section: 'workspace',
    question: { 'pt-BR': 'Como ver minhas entregas?', 'en-US': 'How do I see my deliverables?', 'es-LATAM': '¿Cómo veo mis entregables?' },
    answer: {
      'pt-BR': 'No Workspace, a seção "Minha Tribo" mostra o board da sua tribo com todos os entregáveis. Você pode alternar entre 5 visualizações: Kanban, Tabela, Lista, Calendário e Timeline.',
      'en-US': 'In the Workspace, the "My Tribe" section shows your tribe\'s board with all deliverables. You can switch between 5 views: Kanban, Table, List, Calendar, and Timeline.',
      'es-LATAM': 'En el Workspace, la sección "Mi Tribu" muestra el tablero de su tribu con todos los entregables. Puede alternar entre 5 vistas: Kanban, Tabla, Lista, Calendario y Línea de Tiempo.',
    },
  },
  {
    id: 'attendance', section: 'workspace',
    question: { 'pt-BR': 'Como registrar presença?', 'en-US': 'How do I register attendance?', 'es-LATAM': '¿Cómo registro asistencia?' },
    answer: {
      'pt-BR': 'No Workspace, role até "Registrar Presença", selecione o evento e confirme. Cada presença vale 10 XP na gamificação. Você pode ver seu histórico de presença no mesmo painel.',
      'en-US': 'In the Workspace, scroll to "Register Attendance", select the event, and confirm. Each attendance is worth 10 XP in gamification. You can view your attendance history in the same panel.',
      'es-LATAM': 'En el Workspace, desplácese hasta "Registrar Asistencia", seleccione el evento y confirme. Cada asistencia vale 10 XP en gamificación. Puede ver su historial de asistencia en el mismo panel.',
    },
  },
  {
    id: 'ranking', section: 'workspace',
    question: { 'pt-BR': 'Como ver meu ranking e XP?', 'en-US': 'How do I see my ranking and XP?', 'es-LATAM': '¿Cómo veo mi ranking y XP?' },
    answer: {
      'pt-BR': 'Acesse "Gamificação" no menu superior. Seu ranking, XP total, e detalhamento por categoria (presença, certificações, trilha, entregas) estão lá. O ícone ℹ️ mostra a tabela completa de pontuação por tipo de certificação.',
      'en-US': 'Go to "Gamification" in the top menu. Your ranking, total XP, and breakdown by category (attendance, certifications, trail, deliverables) are there. The ℹ️ icon shows the full scoring table by certification type.',
      'es-LATAM': 'Acceda a "Gamificación" en el menú superior. Su ranking, XP total y desglose por categoría (asistencia, certificaciones, ruta, entregables) están allí. El ícono ℹ️ muestra la tabla completa de puntuación.',
    },
  },
  {
    id: 'publications', section: 'workspace',
    question: { 'pt-BR': 'Como submeter publicações?', 'en-US': 'How do I submit publications?', 'es-LATAM': '¿Cómo envío publicaciones?' },
    answer: {
      'pt-BR': 'Acesse "Publicações" no menu ou Workspace → "Minhas Publicações". Clique "Nova Submissão", preencha título, resumo, tipo de alvo (conferência PMI, periódico, blog), e envie. O pipeline acompanha o status desde rascunho até publicação.',
      'en-US': 'Go to "Publications" in the menu or Workspace → "My Publications". Click "New Submission", fill in title, abstract, target type (PMI conference, journal, blog), and submit. The pipeline tracks status from draft to published.',
      'es-LATAM': 'Acceda a "Publicaciones" en el menú o Workspace → "Mis Publicaciones". Haga clic en "Nueva Submisión", complete título, resumen, tipo de destino (conferencia PMI, periódico, blog) y envíe. El pipeline acompaña el estado desde borrador hasta publicado.',
    },
  },
  {
    id: 'library', section: 'workspace',
    question: { 'pt-BR': 'O que é a Biblioteca?', 'en-US': 'What is the Library?', 'es-LATAM': '¿Qué es la Biblioteca?' },
    answer: {
      'pt-BR': 'A Biblioteca reúne materiais de referência do Núcleo: templates, guias, artigos publicados, e recursos compartilhados. Acesse pelo menu superior → "Biblioteca".',
      'en-US': 'The Library gathers reference materials from the Group: templates, guides, published articles, and shared resources. Access via the top menu → "Library".',
      'es-LATAM': 'La Biblioteca reúne materiales de referencia del Núcleo: plantillas, guías, artículos publicados y recursos compartidos. Acceda por el menú superior → "Biblioteca".',
    },
  },

  // ══════════════════════════════════════════
  // PARA LÍDERES DE TRIBO
  // ══════════════════════════════════════════
  {
    id: 'create_cards', section: 'leaders',
    question: { 'pt-BR': 'Como criar cards no board?', 'en-US': 'How do I create cards on the board?', 'es-LATAM': '¿Cómo creo tarjetas en el tablero?' },
    answer: {
      'pt-BR': 'No board da tribo, clique em "+ Novo Card". Preencha título, descrição, responsável, datas PMBOK (baseline, forecast, actual), e tags. O card aparece na coluna Backlog.',
      'en-US': 'On the tribe board, click "+ New Card". Fill in title, description, assignee, PMBOK dates (baseline, forecast, actual), and tags. The card appears in the Backlog column.',
      'es-LATAM': 'En el tablero de la tribu, haga clic en "+ Nueva Tarjeta". Complete título, descripción, responsable, fechas PMBOK (baseline, forecast, actual) y etiquetas. La tarjeta aparece en la columna Backlog.',
    },
  },
  {
    id: 'drag_drop', section: 'leaders',
    question: { 'pt-BR': 'Como mover cards entre colunas?', 'en-US': 'How do I move cards between columns?', 'es-LATAM': '¿Cómo muevo tarjetas entre columnas?' },
    answer: {
      'pt-BR': 'Na view Kanban, clique e segure o card, arraste para a coluna desejada (Backlog → A Fazer → Em Andamento → Revisão → Concluído). O status atualiza automaticamente.',
      'en-US': 'In the Kanban view, click and hold the card, drag it to the desired column (Backlog → To Do → In Progress → Review → Done). The status updates automatically.',
      'es-LATAM': 'En la vista Kanban, haga clic y mantenga la tarjeta, arrástrela a la columna deseada (Backlog → Por Hacer → En Progreso → Revisión → Hecho). El estado se actualiza automáticamente.',
    },
  },
  {
    id: 'board_views', section: 'leaders',
    question: { 'pt-BR': 'Quais visualizações o board suporta?', 'en-US': 'What views does the board support?', 'es-LATAM': '¿Qué vistas soporta el tablero?' },
    answer: {
      'pt-BR': '5 visualizações: Kanban (colunas por status), Tabela (spreadsheet com todas as colunas), Lista (compacta agrupada por status), Calendário (cards por data), e Timeline (Gantt com baseline vs actual).',
      'en-US': '5 views: Kanban (columns by status), Table (spreadsheet with all columns), List (compact grouped by status), Calendar (cards by date), and Timeline (Gantt with baseline vs actual).',
      'es-LATAM': '5 vistas: Kanban (columnas por estado), Tabla (hoja de cálculo con todas las columnas), Lista (compacta agrupada por estado), Calendario (tarjetas por fecha) y Línea de Tiempo (Gantt con baseline vs actual).',
    },
  },
  {
    id: 'checklists', section: 'leaders',
    question: { 'pt-BR': 'Como gerenciar checklists nos cards?', 'en-US': 'How do I manage checklists on cards?', 'es-LATAM': '¿Cómo gestiono checklists en las tarjetas?' },
    answer: {
      'pt-BR': 'Clique em um card para abrir o detalhe. Na seção "Checklist", adicione itens. Marque como concluído conforme a equipe avança. O progresso aparece como barra no card na view Kanban.',
      'en-US': 'Click a card to open its detail. In the "Checklist" section, add items. Mark them as done as the team progresses. Progress shows as a bar on the card in Kanban view.',
      'es-LATAM': 'Haga clic en una tarjeta para abrir el detalle. En la sección "Checklist", agregue ítems. Márquelos como completados conforme el equipo avanza. El progreso se muestra como barra en la tarjeta en la vista Kanban.',
    },
  },
  {
    id: 'batch_attendance', section: 'leaders',
    question: { 'pt-BR': 'Como registrar presença em lote?', 'en-US': 'How do I register batch attendance?', 'es-LATAM': '¿Cómo registro asistencia en lote?' },
    answer: {
      'pt-BR': 'Na página de Eventos da sua tribo, encontre a reunião e clique em "Presença em Lote". Marque os membros presentes e confirme. Todos recebem 10 XP automaticamente.',
      'en-US': 'On your tribe\'s Events page, find the meeting and click "Batch Attendance". Check the members who were present and confirm. Everyone gets 10 XP automatically.',
      'es-LATAM': 'En la página de Eventos de su tribu, encuentre la reunión y haga clic en "Asistencia en Lote". Marque los miembros presentes y confirme. Todos reciben 10 XP automáticamente.',
    },
  },
  {
    id: 'tribe_events', section: 'leaders',
    question: { 'pt-BR': 'Como criar eventos da tribo?', 'en-US': 'How do I create tribe events?', 'es-LATAM': '¿Cómo creo eventos de la tribu?' },
    answer: {
      'pt-BR': 'Acesse a página da sua tribo → aba "Eventos" → "Novo Evento". Defina título, data, horário, tipo (reunião, workshop, apresentação) e link de videoconferência.',
      'en-US': 'Go to your tribe page → "Events" tab → "New Event". Set the title, date, time, type (meeting, workshop, presentation), and video conference link.',
      'es-LATAM': 'Acceda a la página de su tribu → pestaña "Eventos" → "Nuevo Evento". Defina título, fecha, horario, tipo (reunión, taller, presentación) y enlace de videoconferencia.',
    },
  },

  // ══════════════════════════════════════════
  // PARA ADMINISTRADORES
  // ══════════════════════════════════════════
  {
    id: 'tier_viewer', section: 'admin',
    question: { 'pt-BR': 'Como usar o Simulador de Tier?', 'en-US': 'How do I use the Tier Viewer?', 'es-LATAM': '¿Cómo uso el Simulador de Tier?' },
    answer: {
      'pt-BR': 'O botão "Simular Tier" aparece no canto superior direito (só para superadmins). Selecione um papel, designações opcionais e tribo. A plataforma mostra exatamente o que aquele papel veria. Clique "Sair simulação" para voltar.',
      'en-US': 'The "Simulate Tier" button appears in the top right (superadmins only). Select a role, optional designations, and tribe. The platform shows exactly what that role would see. Click "Exit simulation" to return.',
      'es-LATAM': 'El botón "Simular Tier" aparece en la esquina superior derecha (solo superadmins). Seleccione un rol, designaciones opcionales y tribu. La plataforma muestra exactamente lo que ese rol vería. Haga clic en "Salir de simulación" para volver.',
    },
  },
  {
    id: 'export_pdf', section: 'admin',
    question: { 'pt-BR': 'Como exportar o relatório do ciclo?', 'en-US': 'How do I export the cycle report?', 'es-LATAM': '¿Cómo exporto el informe del ciclo?' },
    answer: {
      'pt-BR': 'Admin → "Relatório Executivo". A página mostra o relatório completo com KPIs, tribos, gamificação, pilotos. Clique "Exportar PDF" para gerar o documento.',
      'en-US': 'Admin → "Executive Report". The page shows the full report with KPIs, tribes, gamification, pilots. Click "Export PDF" to generate the document.',
      'es-LATAM': 'Admin → "Informe Ejecutivo". La página muestra el informe completo con KPIs, tribus, gamificación, pilotos. Haga clic en "Exportar PDF" para generar el documento.',
    },
  },
  {
    id: 'manage_members', section: 'admin',
    question: { 'pt-BR': 'Como gerenciar membros?', 'en-US': 'How do I manage members?', 'es-LATAM': '¿Cómo gestiono miembros?' },
    answer: {
      'pt-BR': 'Admin → "Painel Admin" mostra todos os membros com filtros por tier, tribo, status. Clique em um membro para editar papel, designações, tribo, status ativo.',
      'en-US': 'Admin → "Admin Panel" shows all members with filters by tier, tribe, status. Click a member to edit their role, designations, tribe, active status.',
      'es-LATAM': 'Admin → "Panel Admin" muestra todos los miembros con filtros por tier, tribu, estado. Haga clic en un miembro para editar rol, designaciones, tribu, estado activo.',
    },
  },
  {
    id: 'campaigns', section: 'admin',
    question: { 'pt-BR': 'Como enviar campanhas de email?', 'en-US': 'How do I send email campaigns?', 'es-LATAM': '¿Cómo envío campañas de correo?' },
    answer: {
      'pt-BR': 'Admin → "Campanhas" lista os templates por tier. Clique "Enviar" no template desejado, confirme a audiência, e envie. O botão "Stats" mostra o funil de conversão (entregues → abriram → clicaram).',
      'en-US': 'Admin → "Campaigns" lists templates by tier. Click "Send" on the desired template, confirm the audience, and send. The "Stats" button shows the conversion funnel (delivered → opened → clicked).',
      'es-LATAM': 'Admin → "Campañas" lista las plantillas por tier. Haga clic en "Enviar" en la plantilla deseada, confirme la audiencia y envíe. El botón "Stats" muestra el embudo de conversión (entregados → abiertos → clic).',
    },
  },
  {
    id: 'adoption', section: 'admin',
    question: { 'pt-BR': 'Como ver analytics de adoção?', 'en-US': 'How do I view adoption analytics?', 'es-LATAM': '¿Cómo veo analíticas de adopción?' },
    answer: {
      'pt-BR': 'Admin → "Adoção" mostra quem acessou a plataforma, quando e com que frequência. Indicadores por tribo e tier ajudam a identificar quem precisa de suporte no onboarding.',
      'en-US': 'Admin → "Adoption" shows who accessed the platform, when, and how often. Indicators by tribe and tier help identify who needs onboarding support.',
      'es-LATAM': 'Admin → "Adopción" muestra quién accedió a la plataforma, cuándo y con qué frecuencia. Indicadores por tribu y tier ayudan a identificar quién necesita apoyo en el onboarding.',
    },
  },
  {
    id: 'sustainability', section: 'admin',
    question: { 'pt-BR': 'Como gerenciar sustentabilidade financeira?', 'en-US': 'How do I manage financial sustainability?', 'es-LATAM': '¿Cómo gestiono la sostenibilidad financiera?' },
    answer: {
      'pt-BR': 'Admin → "Sustentabilidade" mostra categorias de custo e receita com entradas por ciclo. Adicione custos (infraestrutura, ferramentas) e receitas (patrocínio, eventos). A meta é custo zero — os indicadores mostram o progresso.',
      'en-US': 'Admin → "Sustainability" shows cost and revenue categories with entries per cycle. Add costs (infrastructure, tools) and revenues (sponsorship, events). The goal is zero cost — indicators show progress.',
      'es-LATAM': 'Admin → "Sostenibilidad" muestra categorías de costo e ingreso con entradas por ciclo. Agregue costos (infraestructura, herramientas) e ingresos (patrocinio, eventos). La meta es costo cero — los indicadores muestran el progreso.',
    },
  },

  // ══════════════════════════════════════════
  // SOLUÇÃO DE PROBLEMAS
  // ══════════════════════════════════════════
  {
    id: 'cant_login', section: 'troubleshooting',
    question: { 'pt-BR': 'Não consigo fazer login', 'en-US': 'I can\'t log in', 'es-LATAM': 'No puedo iniciar sesión' },
    answer: {
      'pt-BR': 'Verifique se está usando o mesmo email cadastrado no Núcleo. Tente outro método de login (Google, LinkedIn, Magic Link). Se o problema persistir, entre em contato com o GP pelo email ou WhatsApp.',
      'en-US': 'Make sure you\'re using the same email registered with the Group. Try a different login method (Google, LinkedIn, Magic Link). If the problem persists, contact the GP via email or WhatsApp.',
      'es-LATAM': 'Verifique que está usando el mismo correo registrado en el Núcleo. Intente otro método de inicio de sesión (Google, LinkedIn, Magic Link). Si el problema persiste, contacte al GP por correo o WhatsApp.',
    },
  },
  {
    id: 'wrong_tribe', section: 'troubleshooting',
    question: { 'pt-BR': 'Estou na tribo errada ou sem tribo', 'en-US': 'I\'m in the wrong tribe or have no tribe', 'es-LATAM': 'Estoy en la tribu equivocada o sin tribu' },
    answer: {
      'pt-BR': 'A alocação de tribo é feita pelo GP. Se o Workspace mostra "Você ainda não está vinculado a uma tribo", entre em contato com o GP para ser alocado.',
      'en-US': 'Tribe allocation is done by the GP. If the Workspace shows "You are not yet assigned to a tribe", contact the GP to be assigned.',
      'es-LATAM': 'La asignación de tribu la realiza el GP. Si el Workspace muestra "Aún no está vinculado a una tribu", contacte al GP para ser asignado.',
    },
  },
  {
    id: 'credly_not_syncing', section: 'troubleshooting',
    question: { 'pt-BR': 'Meus badges do Credly não aparecem', 'en-US': 'My Credly badges aren\'t showing', 'es-LATAM': 'Mis insignias de Credly no aparecen' },
    answer: {
      'pt-BR': 'Os badges são sincronizados automaticamente a cada 5 dias. Verifique se seu username do Credly está correto em Configurações → perfil. Se digitou recentemente, aguarde o próximo ciclo de sync ou peça ao GP para forçar a sincronização.',
      'en-US': 'Badges sync automatically every 5 days. Check that your Credly username is correct in Settings → profile. If recently entered, wait for the next sync cycle or ask the GP to force a sync.',
      'es-LATAM': 'Las insignias se sincronizan automáticamente cada 5 días. Verifique que su nombre de usuario de Credly es correcto en Configuraciones → perfil. Si lo ingresó recientemente, espere el próximo ciclo de sincronización o pida al GP que fuerce la sincronización.',
    },
  },
  {
    id: 'report_bug', section: 'troubleshooting',
    question: { 'pt-BR': 'Como reportar um bug?', 'en-US': 'How do I report a bug?', 'es-LATAM': '¿Cómo reporto un error?' },
    answer: {
      'pt-BR': 'Envie uma descrição do problema (o que fez, o que esperava, o que aconteceu) para nucleoiagp@gmail.com ou pelo WhatsApp do GP. Se possível, inclua um screenshot. Todo feedback é valioso — a plataforma está em Beta.',
      'en-US': 'Send a description of the problem (what you did, what you expected, what happened) to nucleoiagp@gmail.com or via the GP\'s WhatsApp. If possible, include a screenshot. All feedback is valuable — the platform is in Beta.',
      'es-LATAM': 'Envíe una descripción del problema (qué hizo, qué esperaba, qué pasó) a nucleoiagp@gmail.com o por WhatsApp del GP. Si es posible, incluya un screenshot. Todo feedback es valioso — la plataforma está en Beta.',
    },
  },
];

const SECTION_HEADERS: Record<string, Record<string, string>> = {
  getting_started: { 'pt-BR': '🚀 Começando', 'en-US': '🚀 Getting Started', 'es-LATAM': '🚀 Comenzando' },
  workspace: { 'pt-BR': '💼 Seu Workspace', 'en-US': '💼 Your Workspace', 'es-LATAM': '💼 Su Workspace' },
  leaders: { 'pt-BR': '👑 Para Líderes de Tribo', 'en-US': '👑 For Tribe Leaders', 'es-LATAM': '👑 Para Líderes de Tribu' },
  admin: { 'pt-BR': '⚙️ Para Administradores', 'en-US': '⚙️ For Administrators', 'es-LATAM': '⚙️ Para Administradores' },
  troubleshooting: { 'pt-BR': '🔧 Solução de Problemas', 'en-US': '🔧 Troubleshooting', 'es-LATAM': '🔧 Solución de Problemas' },
};

const LABELS: Record<string, Record<string, string>> = {
  title: { 'pt-BR': 'Central de Ajuda', 'en-US': 'Help Center', 'es-LATAM': 'Centro de Ayuda' },
  intro: {
    'pt-BR': 'Bem-vindo à Central de Ajuda do Hub. Selecione um tópico abaixo para ver a resposta.',
    'en-US': 'Welcome to the Hub Help Center. Select a topic below to see the answer.',
    'es-LATAM': 'Bienvenido al Centro de Ayuda del Hub. Seleccione un tema para ver la respuesta.',
  },
  privacy: { 'pt-BR': 'Política de Privacidade', 'en-US': 'Privacy Policy', 'es-LATAM': 'Política de Privacidad' },
  version: { 'pt-BR': 'Versão', 'en-US': 'Version', 'es-LATAM': 'Versión' },
};

function resolveLocale(locale: string): string {
  if (locale.startsWith('en')) return 'en-US';
  if (locale.startsWith('es')) return 'es-LATAM';
  return 'pt-BR';
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

  const lang = resolveLocale(locale);

  useEffect(() => {
    const handler = (e: Event) => {
      const m = (e as CustomEvent).detail;
      if (m) setMember(m);
    };
    window.addEventListener('nav:member', handler);
    const existing = (window as any).navGetMember?.();
    if (existing) setMember(existing);

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
    { key: 'troubleshooting', visible: true },
  ];

  const visibleFaq = FAQ_ITEMS.filter(item => {
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
              {/* Intro (always visible) */}
              <div className="text-[.8rem] text-[var(--text-secondary)] leading-relaxed px-1">
                {LABELS.intro[lang]}
              </div>

              {sections.filter(s => s.visible).map(sec => {
                const sectionItems = visibleFaq.filter(f => f.section === sec.key);
                if (!sectionItems.length) return null;
                return (
                  <div key={sec.key}>
                    <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2 px-1">
                      {SECTION_HEADERS[sec.key]?.[lang] || sec.key}
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
                            {item.question[lang] || item.question['pt-BR']}
                          </button>
                          {expandedId === item.id && (
                            <div className="px-3 pb-3 pl-7 text-[.75rem] text-[var(--text-secondary)] leading-relaxed">
                              {item.answer[lang] || item.answer['pt-BR']}
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}

              {/* Links */}
              <div className="border-t border-[var(--border-default)] pt-3 mt-3 space-y-1 text-[.8rem]">
                <a href="/privacy" className="flex items-center gap-2 px-3 py-2 text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-lg no-underline transition-colors">
                  📜 {LABELS.privacy[lang]}
                </a>
                <a href="https://github.com/VitorMRodovalho/ai-pm-research-hub" target="_blank" rel="noopener noreferrer" className="flex items-center gap-2 px-3 py-2 text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-lg no-underline transition-colors">
                  💻 GitHub
                </a>
                <a href="mailto:nucleoiagp@gmail.com" className="flex items-center gap-2 px-3 py-2 text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-lg no-underline transition-colors">
                  📧 nucleoiagp@gmail.com
                </a>
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
