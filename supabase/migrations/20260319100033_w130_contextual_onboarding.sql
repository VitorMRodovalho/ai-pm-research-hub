-- W130: Contextual Onboarding + Help Rewrite
-- ============================================================
-- 1. help_journeys table with 7 persona journeys
-- 2. visitor_leads table with LGPD-compliant lead capture
-- 3. profile_completed_at column on members
-- 4. data_retention_policy entry for visitor_leads (90 days)
-- 5. WhatsApp GP config in site_config
-- ============================================================

-- ============================================================
-- 1. HELP JOURNEYS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.help_journeys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_key text NOT NULL UNIQUE,
  title jsonb NOT NULL,
  subtitle jsonb NOT NULL,
  icon text DEFAULT '📋',
  display_order int DEFAULT 0,
  is_visible_to_visitors boolean DEFAULT true,
  steps jsonb NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.help_journeys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public reads help journeys"
  ON public.help_journeys FOR SELECT USING (true);

CREATE POLICY "Admin manages help journeys"
  ON public.help_journeys FOR ALL USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin OR m.operational_role IN ('manager','deputy_manager')))
  );

-- Seed 7 persona journeys
INSERT INTO public.help_journeys (persona_key, title, subtitle, icon, display_order, is_visible_to_visitors, steps) VALUES

-- 1. RESEARCHER
('researcher',
 '{"pt":"Pesquisador","en":"Researcher","es":"Investigador"}'::jsonb,
 '{"pt":"Sua jornada no Núcleo de IA & GP","en":"Your journey in the AI & PM Hub","es":"Tu camino en el Núcleo de IA & GP"}'::jsonb,
 '📋', 1, true,
 '[
   {"key":"complete_profile","title":{"pt":"Complete seu perfil","en":"Complete your profile","es":"Completa tu perfil"},"description":{"pt":"Adicione foto, bio, LinkedIn e conecte seu Credly para validação automática de certificações.","en":"Add photo, bio, LinkedIn and connect your Credly for automatic certification validation.","es":"Agrega foto, bio, LinkedIn y conecta tu Credly para validación automática de certificaciones."},"why":{"pt":"O Credly é nossa fonte de verdade para certificações PMI. Conectar seu perfil Credly permite que o sistema valide automaticamente certificações como PMP, CAPM, PMI-ACP e compute sua pontuação na trilha de certificação IA. Sem o Credly, suas certificações precisam ser validadas manualmente.","en":"Credly is our source of truth for PMI certifications. Connecting your Credly profile allows the system to automatically validate certifications like PMP, CAPM, PMI-ACP and compute your AI certification trail score. Without Credly, your certifications need manual validation.","es":"Credly es nuestra fuente de verdad para certificaciones PMI. Conectar tu perfil Credly permite que el sistema valide automáticamente certificaciones como PMP, CAPM, PMI-ACP y compute tu puntuación en el sendero de certificación IA. Sin Credly, tus certificaciones necesitan validación manual."},"action_url":"/profile","action_label":{"pt":"Ir para Perfil","en":"Go to Profile","es":"Ir al Perfil"},"icon":"👤","estimated_minutes":5,"is_required":true},
   {"key":"complete_trail","title":{"pt":"Complete a Trilha IA","en":"Complete the AI Trail","es":"Completa el Sendero IA"},"description":{"pt":"8 mini-cursos sobre IA aplicada a Gerenciamento de Projetos.","en":"8 mini-courses on AI applied to Project Management.","es":"8 mini-cursos sobre IA aplicada a Gestión de Proyectos."},"why":{"pt":"A trilha é o nivelamento base do Núcleo. A meta do ciclo é 70% de conclusão entre os pesquisadores.","en":"The trail is the Hub base leveling. The cycle goal is 70% completion among researchers.","es":"El sendero es la nivelación base del Núcleo. La meta del ciclo es 70% de conclusión entre los investigadores."},"action_url":"/gamification","action_label":{"pt":"Ver Trilha","en":"View Trail","es":"Ver Sendero"},"icon":"🎓","estimated_minutes":240,"is_required":true},
   {"key":"know_tribe","title":{"pt":"Conheça sua Tribo","en":"Meet your Tribe","es":"Conoce tu Tribu"},"description":{"pt":"Veja seu board de pesquisa, conheça o líder e seus colegas de tribo.","en":"See your research board, meet the leader and your tribe colleagues.","es":"Ve tu tablero de investigación, conoce al líder y tus colegas de tribu."},"why":{"pt":"Cada tribo foca em um quadrante de pesquisa específico. Conhecer sua tribo é o primeiro passo para contribuir.","en":"Each tribe focuses on a specific research quadrant. Knowing your tribe is the first step to contributing.","es":"Cada tribu se enfoca en un cuadrante de investigación específico. Conocer tu tribu es el primer paso para contribuir."},"action_url":"/workspace","action_label":{"pt":"Ir para Workspace","en":"Go to Workspace","es":"Ir al Workspace"},"icon":"🏠","estimated_minutes":5,"is_required":true},
   {"key":"register_attendance","title":{"pt":"Registre presença em reuniões","en":"Register attendance at meetings","es":"Registra asistencia en reuniones"},"description":{"pt":"Confirme sua presença nas reuniões da tribo com 1 clique.","en":"Confirm your attendance at tribe meetings with 1 click.","es":"Confirma tu asistencia en reuniones de la tribu con 1 clic."},"why":{"pt":"Cada presença gera horas de impacto que alimentam nosso KPI de 1.800 horas anuais. Também mantém seu streak de gamificação.","en":"Each attendance generates impact hours that feed our 1,800 annual hours KPI. It also maintains your gamification streak.","es":"Cada asistencia genera horas de impacto que alimentan nuestro KPI de 1.800 horas anuales. También mantiene tu racha de gamificación."},"action_url":"/attendance","action_label":{"pt":"Ver Eventos","en":"View Events","es":"Ver Eventos"},"icon":"✅","estimated_minutes":1,"is_required":true},
   {"key":"produce_content","title":{"pt":"Produza conteúdo no Board","en":"Produce content on the Board","es":"Produce contenido en el Tablero"},"description":{"pt":"Crie cards, escreva artigos e contribua com pesquisas no board da sua tribo.","en":"Create cards, write articles and contribute research on your tribe board.","es":"Crea tarjetas, escribe artículos y contribuye investigación en el tablero de tu tribu."},"why":{"pt":"Os boards são o motor de produção do Núcleo. Cada artigo publicado conta como contribuição mensurável para o portfólio.","en":"Boards are the Hub production engine. Each published article counts as measurable contribution to the portfolio.","es":"Los tableros son el motor de producción del Núcleo. Cada artículo publicado cuenta como contribución medible para el portafolio."},"action_url":"/workspace","action_label":{"pt":"Abrir Board","en":"Open Board","es":"Abrir Tablero"},"icon":"📝","estimated_minutes":30,"is_required":false},
   {"key":"submit_curation","title":{"pt":"Submeta para Curadoria","en":"Submit for Curation","es":"Envía a Curaduría"},"description":{"pt":"Quando seu artigo estiver pronto, envie para revisão pelos curadores.","en":"When your article is ready, submit it for review by curators.","es":"Cuando tu artículo esté listo, envíalo para revisión por los curadores."},"why":{"pt":"A curadoria garante qualidade acadêmica. Dois revisores avaliam com rubrica de 5 critérios antes da publicação.","en":"Curation ensures academic quality. Two reviewers evaluate with a 5-criteria rubric before publication.","es":"La curaduría garantiza calidad académica. Dos revisores evalúan con rúbrica de 5 criterios antes de la publicación."},"action_url":"/publications","action_label":{"pt":"Ver Publicações","en":"View Publications","es":"Ver Publicaciones"},"icon":"🔍","estimated_minutes":5,"is_required":false},
   {"key":"track_gamification","title":{"pt":"Acompanhe sua Gamificação","en":"Track your Gamification","es":"Sigue tu Gamificación"},"description":{"pt":"Veja seu XP, badges, ranking e conquistas.","en":"See your XP, badges, ranking and achievements.","es":"Ve tu XP, insignias, ranking y logros."},"why":{"pt":"A gamificação incentiva participação contínua. Pesquisadores com mais XP são destacados e ganham reconhecimento.","en":"Gamification encourages continuous participation. Researchers with more XP are highlighted and gain recognition.","es":"La gamificación incentiva la participación continua. Investigadores con más XP son destacados y ganan reconocimiento."},"action_url":"/gamification","action_label":{"pt":"Ver Gamificação","en":"View Gamification","es":"Ver Gamificación"},"icon":"🏆","estimated_minutes":2,"is_required":false},
   {"key":"export_data","title":{"pt":"Exporte seus dados","en":"Export your data","es":"Exporta tus datos"},"description":{"pt":"Exerça seu direito LGPD de portabilidade exportando seus dados pessoais.","en":"Exercise your LGPD right to portability by exporting your personal data.","es":"Ejerce tu derecho LGPD de portabilidad exportando tus datos personales."},"why":{"pt":"A LGPD garante seu direito de acessar e exportar todos os dados que mantemos sobre você. O botão gera um arquivo JSON completo.","en":"LGPD guarantees your right to access and export all data we maintain about you. The button generates a complete JSON file.","es":"La LGPD garantiza tu derecho de acceder y exportar todos los datos que mantenemos sobre ti. El botón genera un archivo JSON completo."},"action_url":"/profile","action_label":{"pt":"Exportar Dados","en":"Export Data","es":"Exportar Datos"},"icon":"📦","estimated_minutes":1,"is_required":false}
 ]'::jsonb),

-- 2. TRIBE LEADER
('tribe_leader',
 '{"pt":"Líder de Tribo","en":"Tribe Leader","es":"Líder de Tribu"}'::jsonb,
 '{"pt":"Gerencie sua tribo e acompanhe resultados","en":"Manage your tribe and track results","es":"Gestiona tu tribu y acompaña resultados"}'::jsonb,
 '🏆', 2, true,
 '[
   {"key":"access_dashboard","title":{"pt":"Acesse o Dashboard da Tribo","en":"Access Tribe Dashboard","es":"Accede al Dashboard de la Tribu"},"description":{"pt":"Veja métricas de membros, produção, engajamento e gamificação da sua tribo.","en":"See member metrics, production, engagement and gamification for your tribe.","es":"Ve métricas de miembros, producción, compromiso y gamificación de tu tribu."},"why":{"pt":"O dashboard centraliza todos os dados da tribo em 4 abas. Use-o para acompanhar o progresso semanal.","en":"The dashboard centralizes all tribe data in 4 tabs. Use it to track weekly progress.","es":"El dashboard centraliza todos los datos de la tribu en 4 pestañas. Úsalo para acompañar el progreso semanal."},"action_url":"/admin","action_label":{"pt":"Ir para Admin","en":"Go to Admin","es":"Ir al Admin"},"icon":"📊","estimated_minutes":5,"is_required":true},
   {"key":"manage_events","title":{"pt":"Gerencie eventos recorrentes","en":"Manage recurring events","es":"Gestiona eventos recurrentes"},"description":{"pt":"Crie e edite reuniões semanais da tribo com horário fixo.","en":"Create and edit weekly tribe meetings with fixed schedules.","es":"Crea y edita reuniones semanales de la tribu con horario fijo."},"why":{"pt":"Eventos recorrentes alimentam o calendário e permitem check-in automatizado.","en":"Recurring events feed the calendar and enable automated check-in.","es":"Eventos recurrentes alimentan el calendario y permiten check-in automatizado."},"action_url":"/attendance","action_label":{"pt":"Ver Eventos","en":"View Events","es":"Ver Eventos"},"icon":"📅","estimated_minutes":10,"is_required":true},
   {"key":"bulk_roster","title":{"pt":"Registre presença em lote","en":"Register bulk attendance","es":"Registra asistencia en lote"},"description":{"pt":"Marque presença de múltiplos membros de uma vez após cada reunião.","en":"Mark attendance for multiple members at once after each meeting.","es":"Marca asistencia de múltiples miembros de una vez después de cada reunión."},"why":{"pt":"O registro em lote é mais eficiente para líderes. Cada presença gera XP e horas de impacto automaticamente.","en":"Bulk registration is more efficient for leaders. Each attendance generates XP and impact hours automatically.","es":"El registro en lote es más eficiente para líderes. Cada asistencia genera XP y horas de impacto automáticamente."},"action_url":"/attendance","action_label":{"pt":"Registrar Presença","en":"Register Attendance","es":"Registrar Asistencia"},"icon":"📋","estimated_minutes":5,"is_required":true},
   {"key":"track_production","title":{"pt":"Acompanhe produção da tribo","en":"Track tribe production","es":"Acompaña producción de la tribu"},"description":{"pt":"Monitore cards, artigos em pipeline e publicações da tribo.","en":"Monitor cards, articles in pipeline and tribe publications.","es":"Monitorea tarjetas, artículos en pipeline y publicaciones de la tribu."},"action_url":"/workspace","action_label":{"pt":"Ver Board","en":"View Board","es":"Ver Tablero"},"icon":"📈","estimated_minutes":5,"is_required":false},
   {"key":"submit_articles","title":{"pt":"Submeta artigos para curadoria","en":"Submit articles for curation","es":"Envía artículos a curaduría"},"description":{"pt":"Envie artigos prontos da tribo para revisão pelos curadores.","en":"Submit tribe ready articles for review by curators.","es":"Envía artículos listos de la tribu para revisión por los curadores."},"action_url":"/publications","action_label":{"pt":"Ver Publicações","en":"View Publications","es":"Ver Publicaciones"},"icon":"📑","estimated_minutes":5,"is_required":false}
 ]'::jsonb),

-- 3. CURATOR
('curator',
 '{"pt":"Curador","en":"Curator","es":"Curador"}'::jsonb,
 '{"pt":"Avalie e aprove conteúdo acadêmico","en":"Evaluate and approve academic content","es":"Evalúa y aprueba contenido académico"}'::jsonb,
 '📝', 3, true,
 '[
   {"key":"access_curation","title":{"pt":"Acesse o Dashboard de Curadoria","en":"Access Curation Dashboard","es":"Accede al Dashboard de Curaduría"},"description":{"pt":"Veja artigos pendentes de revisão e acompanhe SLAs.","en":"See articles pending review and track SLAs.","es":"Ve artículos pendientes de revisión y acompaña SLAs."},"action_url":"/admin/curatorship","action_label":{"pt":"Ir para Curadoria","en":"Go to Curation","es":"Ir a Curaduría"},"icon":"🔍","estimated_minutes":5,"is_required":true},
   {"key":"evaluate_articles","title":{"pt":"Avalie artigos com rubrica","en":"Evaluate articles with rubric","es":"Evalúa artículos con rúbrica"},"description":{"pt":"Use a rubrica de 5 critérios para avaliar cada artigo submetido.","en":"Use the 5-criteria rubric to evaluate each submitted article.","es":"Usa la rúbrica de 5 criterios para evaluar cada artículo enviado."},"why":{"pt":"A avaliação por rubrica garante consistência e qualidade. Dois revisores independentes avaliam antes do consenso.","en":"Rubric evaluation ensures consistency and quality. Two independent reviewers evaluate before consensus.","es":"La evaluación por rúbrica garantiza consistencia y calidad. Dos revisores independientes evalúan antes del consenso."},"action_url":"/admin/curatorship","action_label":{"pt":"Avaliar","en":"Evaluate","es":"Evaluar"},"icon":"📊","estimated_minutes":30,"is_required":true},
   {"key":"consensus_review","title":{"pt":"Consenso com segundo revisor","en":"Consensus with second reviewer","es":"Consenso con segundo revisor"},"description":{"pt":"Após ambas avaliações, discutam e cheguem a uma decisão final.","en":"After both evaluations, discuss and reach a final decision.","es":"Después de ambas evaluaciones, discutan y lleguen a una decisión final."},"action_url":"/admin/curatorship","action_label":{"pt":"Ver Curadoria","en":"View Curation","es":"Ver Curaduría"},"icon":"🤝","estimated_minutes":15,"is_required":true},
   {"key":"track_sla","title":{"pt":"Acompanhe SLA de curadoria","en":"Track curation SLA","es":"Acompaña SLA de curaduría"},"description":{"pt":"Monitore o tempo de revisão e garanta que artigos sejam avaliados dentro do prazo.","en":"Monitor review time and ensure articles are evaluated within deadline.","es":"Monitorea el tiempo de revisión y garantiza que artículos sean evaluados dentro del plazo."},"action_url":"/admin/curatorship","action_label":{"pt":"Ver SLA","en":"View SLA","es":"Ver SLA"},"icon":"⏱️","estimated_minutes":2,"is_required":false}
 ]'::jsonb),

-- 4. COMMUNICATOR
('communicator',
 '{"pt":"Comunicação","en":"Communications","es":"Comunicación"}'::jsonb,
 '{"pt":"Gerencie conteúdo e canais de comunicação","en":"Manage content and communication channels","es":"Gestiona contenido y canales de comunicación"}'::jsonb,
 '📢', 4, true,
 '[
   {"key":"access_comms","title":{"pt":"Acesse o Hub de Comunicação","en":"Access Communications Hub","es":"Accede al Hub de Comunicación"},"description":{"pt":"Gerencie o board de conteúdo para redes sociais e canais externos.","en":"Manage the content board for social media and external channels.","es":"Gestiona el tablero de contenido para redes sociales y canales externos."},"action_url":"/admin/comms","action_label":{"pt":"Ir para Comunicação","en":"Go to Communications","es":"Ir a Comunicación"},"icon":"📡","estimated_minutes":5,"is_required":true},
   {"key":"manage_cards","title":{"pt":"Gerencie cards de conteúdo","en":"Manage content cards","es":"Gestiona tarjetas de contenido"},"description":{"pt":"Crie e mova cards no Kanban de comunicação (rascunho → revisão → publicado).","en":"Create and move cards on the communication Kanban (draft → review → published).","es":"Crea y mueve tarjetas en el Kanban de comunicación (borrador → revisión → publicado)."},"action_url":"/admin/comms","action_label":{"pt":"Abrir Board","en":"Open Board","es":"Abrir Tablero"},"icon":"📋","estimated_minutes":15,"is_required":true},
   {"key":"track_metrics","title":{"pt":"Acompanhe métricas de canais","en":"Track channel metrics","es":"Acompaña métricas de canales"},"description":{"pt":"Monitore engajamento no Instagram, LinkedIn e outros canais.","en":"Monitor engagement on Instagram, LinkedIn and other channels.","es":"Monitorea el compromiso en Instagram, LinkedIn y otros canales."},"action_url":"/admin/comms","action_label":{"pt":"Ver Métricas","en":"View Metrics","es":"Ver Métricas"},"icon":"📈","estimated_minutes":5,"is_required":false},
   {"key":"coordinate_leaders","title":{"pt":"Coordene com líderes de tribo","en":"Coordinate with tribe leaders","es":"Coordina con líderes de tribu"},"description":{"pt":"Alinhe conteúdo com líderes para garantir representação de todas as tribos.","en":"Align content with leaders to ensure representation of all tribes.","es":"Alinea contenido con líderes para garantizar representación de todas las tribus."},"action_url":"/workspace","action_label":{"pt":"Ver Tribos","en":"View Tribes","es":"Ver Tribus"},"icon":"🤝","estimated_minutes":10,"is_required":false}
 ]'::jsonb),

-- 5. SPONSOR
('sponsor',
 '{"pt":"Patrocinador","en":"Sponsor","es":"Patrocinador"}'::jsonb,
 '{"pt":"Acompanhe resultados e governança do capítulo","en":"Track results and chapter governance","es":"Acompaña resultados y gobernanza del capítulo"}'::jsonb,
 '🏛️', 5, true,
 '[
   {"key":"chapter_report","title":{"pt":"Acesse o Relatório por Capítulo","en":"Access Chapter Report","es":"Accede al Reporte por Capítulo"},"description":{"pt":"Veja dados consolidados do seu capítulo: membros, produção, engajamento.","en":"See consolidated data for your chapter: members, production, engagement.","es":"Ve datos consolidados de tu capítulo: miembros, producción, compromiso."},"why":{"pt":"O relatório por capítulo permite que patrocinadores acompanhem o impacto dos pesquisadores vinculados ao seu capítulo PMI.","en":"The chapter report allows sponsors to track the impact of researchers linked to their PMI chapter.","es":"El reporte por capítulo permite que patrocinadores acompañen el impacto de los investigadores vinculados a su capítulo PMI."},"action_url":"/admin/chapter-report","action_label":{"pt":"Ver Relatório","en":"View Report","es":"Ver Reporte"},"icon":"📊","estimated_minutes":5,"is_required":true},
   {"key":"cycle_report","title":{"pt":"Visualize o Relatório do Ciclo","en":"View Cycle Report","es":"Visualiza el Reporte del Ciclo"},"description":{"pt":"Relatório executivo com KPIs do ciclo atual, métricas consolidadas e gráficos.","en":"Executive report with current cycle KPIs, consolidated metrics and charts.","es":"Reporte ejecutivo con KPIs del ciclo actual, métricas consolidadas y gráficos."},"action_url":"/admin/cycle-report","action_label":{"pt":"Ver Ciclo","en":"View Cycle","es":"Ver Ciclo"},"icon":"📈","estimated_minutes":10,"is_required":true},
   {"key":"export_pdf","title":{"pt":"Exporte PDF para apresentação","en":"Export PDF for presentation","es":"Exporta PDF para presentación"},"description":{"pt":"Use o botão Exportar PDF para gerar uma versão imprimível do relatório.","en":"Use the Export PDF button to generate a printable version of the report.","es":"Usa el botón Exportar PDF para generar una versión imprimible del reporte."},"action_url":"/admin/cycle-report","action_label":{"pt":"Exportar PDF","en":"Export PDF","es":"Exportar PDF"},"icon":"📄","estimated_minutes":1,"is_required":false}
 ]'::jsonb),

-- 6. LIAISON
('liaison',
 '{"pt":"Ponto Focal","en":"Chapter Liaison","es":"Punto Focal"}'::jsonb,
 '{"pt":"Conecte seu capítulo ao Núcleo","en":"Connect your chapter to the Hub","es":"Conecta tu capítulo al Núcleo"}'::jsonb,
 '🔗', 6, true,
 '[
   {"key":"track_chapter","title":{"pt":"Acompanhe membros do seu capítulo","en":"Track your chapter members","es":"Acompaña miembros de tu capítulo"},"description":{"pt":"Veja quantos pesquisadores do seu capítulo estão ativos e o que estão produzindo.","en":"See how many researchers from your chapter are active and what they are producing.","es":"Ve cuántos investigadores de tu capítulo están activos y qué están produciendo."},"action_url":"/admin/chapter-report","action_label":{"pt":"Ver Capítulo","en":"View Chapter","es":"Ver Capítulo"},"icon":"👥","estimated_minutes":5,"is_required":true},
   {"key":"access_chapter_report","title":{"pt":"Acesse o relatório por capítulo","en":"Access chapter report","es":"Accede al reporte por capítulo"},"description":{"pt":"Relatório com dados de produção, engajamento e certificação dos membros do capítulo.","en":"Report with production, engagement and certification data for chapter members.","es":"Reporte con datos de producción, compromiso y certificación de los miembros del capítulo."},"action_url":"/admin/chapter-report","action_label":{"pt":"Ver Relatório","en":"View Report","es":"Ver Reporte"},"icon":"📊","estimated_minutes":5,"is_required":true},
   {"key":"communicate_gp","title":{"pt":"Comunique-se com o GP","en":"Communicate with the PM","es":"Comunícate con el GP"},"description":{"pt":"Use o WhatsApp ou a plataforma para alinhar com o Gerente de Projeto.","en":"Use WhatsApp or the platform to align with the Project Manager.","es":"Usa WhatsApp o la plataforma para alinear con el Gerente de Proyecto."},"action_url":"/help","action_label":{"pt":"Central de Ajuda","en":"Help Center","es":"Centro de Ayuda"},"icon":"💬","estimated_minutes":5,"is_required":false}
 ]'::jsonb),

-- 7. GP/DM (Admin Reference)
('gp',
 '{"pt":"Gestão do Projeto","en":"Project Management","es":"Gestión del Proyecto"}'::jsonb,
 '{"pt":"Referência completa para gestores","en":"Complete reference for managers","es":"Referencia completa para gestores"}'::jsonb,
 '⚙️', 7, true,
 '[
   {"key":"admin_panel","title":{"pt":"Painel Administrativo","en":"Admin Panel","es":"Panel Administrativo"},"description":{"pt":"Acesse todas as funcionalidades de gestão: dados, KPIs, tribos, seleção, parcerias.","en":"Access all management features: data, KPIs, tribes, selection, partnerships.","es":"Accede a todas las funcionalidades de gestión: datos, KPIs, tribus, selección, alianzas."},"action_url":"/admin","action_label":{"pt":"Ir para Admin","en":"Go to Admin","es":"Ir al Admin"},"icon":"🖥️","estimated_minutes":5,"is_required":true},
   {"key":"tribe_dashboards","title":{"pt":"Dashboards de todas as tribos","en":"All tribe dashboards","es":"Dashboards de todas las tribus"},"description":{"pt":"Veja métricas detalhadas de cada uma das 8 tribos de pesquisa.","en":"See detailed metrics for each of the 8 research tribes.","es":"Ve métricas detalladas de cada una de las 8 tribus de investigación."},"action_url":"/admin/tribes","action_label":{"pt":"Ver Tribos","en":"View Tribes","es":"Ver Tribus"},"icon":"📊","estimated_minutes":10,"is_required":true},
   {"key":"config_settings","title":{"pt":"Configurações do sistema","en":"System settings","es":"Configuraciones del sistema"},"description":{"pt":"Gerencie configurações globais, ciclos, metas de KPI e políticas de retenção.","en":"Manage global settings, cycles, KPI targets and retention policies.","es":"Gestiona configuraciones globales, ciclos, metas de KPI y políticas de retención."},"action_url":"/admin/settings","action_label":{"pt":"Configurações","en":"Settings","es":"Configuraciones"},"icon":"⚙️","estimated_minutes":5,"is_required":false}
 ]'::jsonb)

ON CONFLICT (persona_key) DO NOTHING;

-- ============================================================
-- 2. VISITOR LEADS
-- ============================================================
CREATE TABLE IF NOT EXISTS public.visitor_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  chapter_interest text,
  role_interest text,
  message text,
  lgpd_consent boolean NOT NULL DEFAULT false,
  source text DEFAULT 'website',
  status text DEFAULT 'new' CHECK (status IN ('new','contacted','converted','archived')),
  created_at timestamptz DEFAULT now(),
  contacted_at timestamptz,
  contacted_by uuid REFERENCES public.members(id)
);

ALTER TABLE public.visitor_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can submit lead"
  ON public.visitor_leads FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Admin reads leads"
  ON public.visitor_leads FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin OR m.operational_role IN ('manager','deputy_manager')))
  );

CREATE POLICY "Admin updates leads"
  ON public.visitor_leads FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.members m WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin OR m.operational_role IN ('manager','deputy_manager')))
  );

-- ============================================================
-- 3. PROFILE COMPLETED AT
-- ============================================================
ALTER TABLE public.members ADD COLUMN IF NOT EXISTS profile_completed_at timestamptz;

-- ============================================================
-- 4. DATA RETENTION POLICY — 90 days for visitor_leads
-- ============================================================
INSERT INTO public.data_retention_policy (table_name, retention_days, cleanup_type, description)
VALUES ('visitor_leads', 90, 'delete', 'LGPD: unconverted visitor leads auto-deleted after 90 days')
ON CONFLICT DO NOTHING;

-- ============================================================
-- 5. WHATSAPP GP CONFIG — seed in site_config
-- ============================================================
INSERT INTO public.site_config (key, value)
VALUES ('whatsapp_gp', '{"phone":"12678748329","label":"Gerente de Projeto"}'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

-- ============================================================
-- 6. RPC: get_help_journeys — returns all journeys (public)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_help_journeys()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN COALESCE(
    (SELECT jsonb_agg(
      jsonb_build_object(
        'persona_key', hj.persona_key,
        'title', hj.title,
        'subtitle', hj.subtitle,
        'icon', hj.icon,
        'display_order', hj.display_order,
        'is_visible_to_visitors', hj.is_visible_to_visitors,
        'steps', hj.steps
      ) ORDER BY hj.display_order
    ) FROM public.help_journeys hj WHERE hj.is_visible_to_visitors = true),
    '[]'::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_help_journeys() TO anon, authenticated;

-- ============================================================
-- 7. RPC: get_gp_whatsapp — returns GP phone for WhatsApp button
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_gp_whatsapp()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone text;
  v_name text;
  v_config jsonb;
BEGIN
  -- Option B: derive from members table (auto-updates if GP changes)
  SELECT m.phone, m.name INTO v_phone, v_name
  FROM public.members m
  WHERE m.operational_role = 'manager' AND m.is_active = true
  LIMIT 1;

  IF v_phone IS NOT NULL AND v_phone != '' THEN
    RETURN jsonb_build_object(
      'phone', regexp_replace(v_phone, '[^0-9]', '', 'g'),
      'name', v_name,
      'source', 'members'
    );
  END IF;

  -- Fallback: site_config
  SELECT value INTO v_config FROM public.site_config WHERE key = 'whatsapp_gp';
  IF v_config IS NOT NULL THEN
    RETURN jsonb_build_object(
      'phone', v_config->>'phone',
      'name', COALESCE(v_config->>'label', 'Gerente de Projeto'),
      'source', 'site_config'
    );
  END IF;

  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_gp_whatsapp() TO anon, authenticated;
