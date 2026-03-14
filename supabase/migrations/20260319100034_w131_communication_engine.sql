-- ═══════════════════════════════════════════════════════════════
-- W131 — Communication Engine + Blog
-- Tables: campaign_templates, campaign_sends, campaign_recipients, blog_posts
-- RPCs: admin_preview_campaign, admin_send_campaign, admin_get_campaign_stats
-- ═══════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────
-- 1. campaign_templates
-- ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.campaign_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  subject jsonb NOT NULL,
  body_html jsonb NOT NULL,
  body_text jsonb NOT NULL,
  target_audience jsonb NOT NULL DEFAULT '{"roles":[],"designations":[],"chapters":[],"all":false}'::jsonb,
  category text NOT NULL DEFAULT 'operational'
    CHECK (category IN ('operational','onboarding','announcement','newsletter')),
  variables jsonb DEFAULT '["member.name","member.tribe","member.chapter","platform.url","unsubscribe_url"]'::jsonb,
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.campaign_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manages templates" ON public.campaign_templates FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin
           OR m.operational_role IN ('manager','deputy_manager')
           OR 'comms_team' = ANY(m.designations))
  )
);

-- ───────────────────────────────────────────────
-- 2. campaign_sends
-- ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.campaign_sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid REFERENCES public.campaign_templates(id) NOT NULL,
  sent_by uuid REFERENCES public.members(id) NOT NULL,
  audience_filter jsonb NOT NULL,
  recipient_count int NOT NULL DEFAULT 0,
  status text DEFAULT 'draft'
    CHECK (status IN ('draft','scheduled','sending','sent','failed')),
  scheduled_at timestamptz,
  sent_at timestamptz,
  error_log text,
  approved_by uuid REFERENCES public.members(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.campaign_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manages sends" ON public.campaign_sends FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin
           OR m.operational_role IN ('manager','deputy_manager'))
  )
);

-- comms_team can SELECT sends (view history) but not INSERT/UPDATE/DELETE
CREATE POLICY "Comms team reads sends" ON public.campaign_sends FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND 'comms_team' = ANY(m.designations)
  )
);

-- ───────────────────────────────────────────────
-- 3. campaign_recipients
-- ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.campaign_recipients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  send_id uuid REFERENCES public.campaign_sends(id) ON DELETE CASCADE NOT NULL,
  member_id uuid REFERENCES public.members(id),
  external_email text,
  external_name text,
  language text DEFAULT 'pt',
  delivered boolean DEFAULT false,
  opened boolean DEFAULT false,
  unsubscribed boolean DEFAULT false,
  unsubscribe_token uuid DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.campaign_recipients ENABLE ROW LEVEL SECURITY;

-- No direct access — only via RPCs
CREATE POLICY "No direct access to recipients" ON public.campaign_recipients FOR ALL USING (false);

-- ───────────────────────────────────────────────
-- 4. blog_posts
-- ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.blog_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title jsonb NOT NULL,
  excerpt jsonb NOT NULL,
  body_html jsonb NOT NULL,
  cover_image_url text,
  author_member_id uuid REFERENCES public.members(id),
  category text DEFAULT 'case-study'
    CHECK (category IN ('case-study','tutorial','announcement','opinion')),
  tags text[] DEFAULT '{}',
  status text DEFAULT 'draft'
    CHECK (status IN ('draft','review','published')),
  published_at timestamptz,
  is_featured boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public reads published" ON public.blog_posts FOR SELECT USING (status = 'published');

CREATE POLICY "Admin manages posts" ON public.blog_posts FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid()
      AND (m.is_superadmin
           OR m.operational_role IN ('manager','deputy_manager')
           OR 'comms_team' = ANY(m.designations))
  )
);

-- ───────────────────────────────────────────────
-- 5. RPC: admin_preview_campaign
-- ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_preview_campaign(
  p_template_id uuid,
  p_preview_member_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_tmpl record;
  v_member record;
  v_html text;
  v_text text;
  v_subject text;
  v_lang text := 'pt';
BEGIN
  -- Auth check: GP/DM/comms_team
  SELECT id INTO v_caller_id
  FROM public.members
  WHERE auth_id = auth.uid()
    AND (is_superadmin
         OR operational_role IN ('manager','deputy_manager')
         OR 'comms_team' = ANY(designations));
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: insufficient permissions';
  END IF;

  -- Load template
  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  -- Load preview member (or first active member)
  IF p_preview_member_id IS NOT NULL THEN
    SELECT m.*, t.name AS tribe_name, t.chapter
    INTO v_member
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.id = p_preview_member_id;
  ELSE
    SELECT m.*, t.name AS tribe_name, t.chapter
    INTO v_member
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active = true AND m.current_cycle_active = true
    LIMIT 1;
  END IF;

  -- Detect language
  v_lang := COALESCE(v_member.preferred_language, 'pt');
  IF v_lang NOT IN ('pt','en','es') THEN v_lang := 'pt'; END IF;

  -- Render subject
  v_subject := COALESCE(v_tmpl.subject->>v_lang, v_tmpl.subject->>'pt', '');
  v_html := COALESCE(v_tmpl.body_html->>v_lang, v_tmpl.body_html->>'pt', '');
  v_text := COALESCE(v_tmpl.body_text->>v_lang, v_tmpl.body_text->>'pt', '');

  -- Replace variables
  v_subject := replace(v_subject, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_html := replace(v_html, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_html := replace(v_html, '{member.tribe}', COALESCE(v_member.tribe_name, ''));
  v_html := replace(v_html, '{member.chapter}', COALESCE(v_member.chapter, ''));
  v_html := replace(v_html, '{platform.url}', 'https://nucleoiagp.pages.dev');
  v_html := replace(v_html, '{unsubscribe_url}', 'https://nucleoiagp.pages.dev/unsubscribe?token=preview');

  v_text := replace(v_text, '{member.name}', COALESCE(v_member.name, 'Membro'));
  v_text := replace(v_text, '{member.tribe}', COALESCE(v_member.tribe_name, ''));
  v_text := replace(v_text, '{member.chapter}', COALESCE(v_member.chapter, ''));
  v_text := replace(v_text, '{platform.url}', 'https://nucleoiagp.pages.dev');
  v_text := replace(v_text, '{unsubscribe_url}', 'https://nucleoiagp.pages.dev/unsubscribe?token=preview');

  RETURN jsonb_build_object(
    'subject', v_subject,
    'html', v_html,
    'text', v_text,
    'member_name', v_member.name,
    'language', v_lang
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_preview_campaign(uuid, uuid) TO authenticated;

-- ───────────────────────────────────────────────
-- 6. RPC: admin_send_campaign
-- ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_send_campaign(
  p_template_id uuid,
  p_audience_filter jsonb DEFAULT '{}'::jsonb,
  p_scheduled_at timestamptz DEFAULT NULL,
  p_external_contacts jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_send_id uuid;
  v_count int := 0;
  v_ext_count int := 0;
  v_sends_last_hour int;
  v_sends_last_day int;
  v_member record;
  v_tmpl record;
  v_roles text[];
  v_desigs text[];
  v_chapters text[];
  v_all boolean;
  v_ext record;
BEGIN
  -- Auth check: GP/DM only (comms_team cannot send)
  SELECT id INTO v_caller_id
  FROM public.members
  WHERE auth_id = auth.uid()
    AND (is_superadmin
         OR operational_role IN ('manager','deputy_manager'));
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: only GP/DM can send campaigns';
  END IF;

  -- Rate limit: max 1 send per hour, max 3 per day
  SELECT COUNT(*) INTO v_sends_last_hour
  FROM public.campaign_sends
  WHERE sent_by = v_caller_id
    AND created_at > now() - interval '1 hour'
    AND status NOT IN ('draft','failed');
  IF v_sends_last_hour >= 1 THEN
    RAISE EXCEPTION 'Rate limit: max 1 campaign per hour';
  END IF;

  SELECT COUNT(*) INTO v_sends_last_day
  FROM public.campaign_sends
  WHERE sent_by = v_caller_id
    AND created_at > now() - interval '1 day'
    AND status NOT IN ('draft','failed');
  IF v_sends_last_day >= 3 THEN
    RAISE EXCEPTION 'Rate limit: max 3 campaigns per day';
  END IF;

  -- Validate template exists
  SELECT * INTO v_tmpl FROM public.campaign_templates WHERE id = p_template_id;
  IF v_tmpl IS NULL THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  -- Parse audience filter
  v_roles := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'roles', '[]'::jsonb)));
  v_desigs := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'designations', '[]'::jsonb)));
  v_chapters := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_audience_filter->'chapters', '[]'::jsonb)));
  v_all := COALESCE((p_audience_filter->>'all')::boolean, false);

  -- Create send record
  INSERT INTO public.campaign_sends (id, template_id, sent_by, audience_filter, status, scheduled_at)
  VALUES (gen_random_uuid(), p_template_id, v_caller_id, p_audience_filter,
          CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'sending' END,
          p_scheduled_at)
  RETURNING id INTO v_send_id;

  -- Resolve member recipients
  FOR v_member IN
    SELECT m.id, COALESCE(m.preferred_language, 'pt') AS lang
    FROM public.members m
    LEFT JOIN public.tribes t ON t.id = m.tribe_id
    WHERE m.is_active = true
      AND m.current_cycle_active = true
      AND m.email IS NOT NULL
      AND (
        v_all
        OR (array_length(v_roles, 1) > 0 AND m.operational_role = ANY(v_roles))
        OR (array_length(v_desigs, 1) > 0 AND m.designations && v_desigs)
        OR (array_length(v_chapters, 1) > 0 AND t.chapter = ANY(v_chapters))
      )
      -- Respect notification preferences (skip unsubscribed)
      AND NOT EXISTS (
        SELECT 1 FROM public.campaign_recipients cr2
        JOIN public.campaign_sends cs2 ON cs2.id = cr2.send_id
        WHERE cr2.member_id = m.id AND cr2.unsubscribed = true
      )
  LOOP
    INSERT INTO public.campaign_recipients (send_id, member_id, language)
    VALUES (v_send_id, v_member.id, v_member.lang);
    v_count := v_count + 1;
  END LOOP;

  -- Add external contacts (not stored permanently — cascade with send)
  FOR v_ext IN SELECT * FROM jsonb_array_elements(p_external_contacts)
  LOOP
    INSERT INTO public.campaign_recipients (send_id, external_email, external_name, language)
    VALUES (
      v_send_id,
      v_ext.value->>'email',
      v_ext.value->>'name',
      COALESCE(v_ext.value->>'language', 'en')
    );
    v_ext_count := v_ext_count + 1;
  END LOOP;

  -- Update recipient count
  UPDATE public.campaign_sends SET recipient_count = v_count + v_ext_count WHERE id = v_send_id;

  RETURN jsonb_build_object(
    'send_id', v_send_id,
    'member_recipients', v_count,
    'external_recipients', v_ext_count,
    'total_recipients', v_count + v_ext_count,
    'status', CASE WHEN p_scheduled_at IS NOT NULL THEN 'scheduled' ELSE 'sending' END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_send_campaign(uuid, jsonb, timestamptz, jsonb) TO authenticated;

-- ───────────────────────────────────────────────
-- 7. RPC: admin_get_campaign_stats
-- ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_campaign_stats(p_send_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  -- Auth check: GP/DM/comms_team
  SELECT id INTO v_caller_id
  FROM public.members
  WHERE auth_id = auth.uid()
    AND (is_superadmin
         OR operational_role IN ('manager','deputy_manager')
         OR 'comms_team' = ANY(designations));
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Forbidden: insufficient permissions';
  END IF;

  SELECT jsonb_build_object(
    'send_id', cs.id,
    'template_name', ct.name,
    'status', cs.status,
    'sent_at', cs.sent_at,
    'recipient_count', cs.recipient_count,
    'delivered_count', (SELECT COUNT(*) FROM public.campaign_recipients WHERE send_id = cs.id AND delivered = true),
    'open_count', (SELECT COUNT(*) FROM public.campaign_recipients WHERE send_id = cs.id AND opened = true),
    'unsubscribe_count', (SELECT COUNT(*) FROM public.campaign_recipients WHERE send_id = cs.id AND unsubscribed = true),
    'error_log', cs.error_log
  ) INTO v_result
  FROM public.campaign_sends cs
  JOIN public.campaign_templates ct ON ct.id = cs.template_id
  WHERE cs.id = p_send_id;

  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Send not found';
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_campaign_stats(uuid) TO authenticated;

-- ───────────────────────────────────────────────
-- 8. Seed 5 campaign templates
-- ───────────────────────────────────────────────

-- Template 1: Onboarding Pesquisador
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Onboarding Pesquisador',
  'onboarding-researcher',
  '{"pt":"Sua plataforma do Nucleo IA & GP esta no ar — primeiros passos","en":"Your AI & PM Hub platform is live — first steps","es":"Tu plataforma del Nucleo IA & GP esta activa — primeros pasos"}'::jsonb,
  '{"pt":"<h2>Ola {member.name},</h2><p>A plataforma digital do Nucleo de Estudos e Pesquisa em IA & GP esta em fase beta e ja disponivel para voce.</p><h3>O QUE E A PLATAFORMA</h3><p>Um workspace personalizado onde voce encontra sua tribo, trilha de certificacao IA, board de producao Kanban, gamificacao com XP e ranking, e registro de presenca digital.</p><h3>SEUS PRIMEIROS PASSOS</h3><ol><li>Acesse: <a href=\"{platform.url}\">{platform.url}</a></li><li>Faca login com Google ou LinkedIn</li><li>Complete seu perfil — incluindo Credly</li></ol><h3>POR QUE O CREDLY?</h3><p>O Credly e a fonte oficial de certificacoes PMI&reg; (PMP&reg;, CAPM, etc). Ao conectar seu perfil, o sistema valida suas certificacoes automaticamente e computa sua pontuacao na trilha de certificacao IA.</p><h3>SUA TRIBO</h3><p>Voce faz parte da tribo {member.tribe}. Explore o board da sua tribo e conheca seus colegas de pesquisa.</p><h3>PRECISA DE AJUDA?</h3><p><a href=\"{platform.url}/help\">Central de Ajuda</a> · Responda este email</p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudos e Pesquisa em IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar inscricao</a></p>","en":"<h2>Hello {member.name},</h2><p>The AI & PM Research Hub digital platform is now in beta and available for you.</p><h3>WHAT IS THE PLATFORM</h3><p>A personalized workspace with your tribe, AI certification trail, Kanban production board, gamification with XP and rankings, and digital attendance tracking.</p><h3>YOUR FIRST STEPS</h3><ol><li>Visit: <a href=\"{platform.url}\">{platform.url}</a></li><li>Sign in with Google or LinkedIn</li><li>Complete your profile — including Credly</li></ol><h3>WHY CREDLY?</h3><p>Credly is the official source for PMI&reg; certifications (PMP&reg;, CAPM, etc). By connecting your profile, the system automatically validates your certifications and computes your AI certification trail score.</p><h3>YOUR TRIBE</h3><p>You are part of the {member.tribe} tribe. Explore your tribe board and meet your research colleagues.</p><h3>NEED HELP?</h3><p><a href=\"{platform.url}/help\">Help Center</a> · Reply to this email</p><hr><p style=\"font-size:12px;color:#64748B\">AI & PM Study and Research Hub<br><a href=\"{unsubscribe_url}\">Unsubscribe</a></p>","es":"<h2>Hola {member.name},</h2><p>La plataforma digital del Nucleo de Estudios e Investigacion en IA & GP esta en fase beta y ya disponible para ti.</p><h3>QUE ES LA PLATAFORMA</h3><p>Un workspace personalizado con tu tribu, ruta de certificacion IA, tablero de produccion Kanban, gamificacion con XP y ranking, y registro de asistencia digital.</p><h3>TUS PRIMEROS PASOS</h3><ol><li>Accede: <a href=\"{platform.url}\">{platform.url}</a></li><li>Inicia sesion con Google o LinkedIn</li><li>Completa tu perfil — incluyendo Credly</li></ol><h3>POR QUE CREDLY?</h3><p>Credly es la fuente oficial de certificaciones PMI&reg; (PMP&reg;, CAPM, etc). Al conectar tu perfil, el sistema valida tus certificaciones automaticamente.</p><h3>TU TRIBU</h3><p>Eres parte de la tribu {member.tribe}. Explora el tablero de tu tribu.</p><h3>NECESITAS AYUDA?</h3><p><a href=\"{platform.url}/help\">Centro de Ayuda</a> · Responde este email</p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudios e Investigacion en IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar suscripcion</a></p>"}'::jsonb,
  '{"pt":"Ola {member.name},\n\nA plataforma digital do Nucleo de Estudos e Pesquisa em IA & GP esta em fase beta.\n\nSeus primeiros passos:\n1. Acesse: {platform.url}\n2. Faca login com Google ou LinkedIn\n3. Complete seu perfil\n\nVoce faz parte da tribo {member.tribe}.\n\nPrecisa de ajuda? {platform.url}/help\n\nCancelar inscricao: {unsubscribe_url}","en":"Hello {member.name},\n\nThe AI & PM Research Hub digital platform is now in beta.\n\nYour first steps:\n1. Visit: {platform.url}\n2. Sign in with Google or LinkedIn\n3. Complete your profile\n\nYou are part of the {member.tribe} tribe.\n\nNeed help? {platform.url}/help\n\nUnsubscribe: {unsubscribe_url}","es":"Hola {member.name},\n\nLa plataforma digital del Nucleo IA & GP esta en fase beta.\n\nTus primeros pasos:\n1. Accede: {platform.url}\n2. Inicia sesion con Google o LinkedIn\n3. Completa tu perfil\n\nEres parte de la tribu {member.tribe}.\n\nNecesitas ayuda? {platform.url}/help\n\nCancelar suscripcion: {unsubscribe_url}"}'::jsonb,
  '{"roles":["researcher"],"designations":[],"chapters":[],"all":false}'::jsonb,
  'onboarding',
  '["member.name","member.tribe","member.chapter","platform.url","unsubscribe_url"]'::jsonb
);

-- Template 2: Onboarding Lider de Tribo
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Onboarding Lider de Tribo',
  'onboarding-tribe-leader',
  '{"pt":"Seu dashboard de tribo esta pronto — veja os dados da sua equipe","en":"Your tribe dashboard is ready — see your team data","es":"Tu dashboard de tribu esta listo — ve los datos de tu equipo"}'::jsonb,
  '{"pt":"<h2>Ola {member.name},</h2><p>Como lider de tribo, voce tem acesso a ferramentas exclusivas na plataforma do Nucleo IA & GP.</p><h3>SEU DASHBOARD</h3><p>Acesse <a href=\"{platform.url}/admin/tribe/\">seu dashboard de tribo</a> para ver:</p><ul><li>Membros da sua tribo e status de perfil</li><li>Board Kanban com itens de producao</li><li>Metricas de engajamento e presenca</li><li>Envio de broadcasts para sua equipe</li></ul><h3>PRIMEIROS PASSOS COMO LIDER</h3><ol><li>Revise o roster da sua tribo</li><li>Agende o proximo encontro</li><li>Configure as metas do board</li></ol><p>Precisa de ajuda? <a href=\"{platform.url}/help\">Central de Ajuda</a></p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudos e Pesquisa em IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar inscricao</a></p>","en":"<h2>Hello {member.name},</h2><p>As a tribe leader, you have access to exclusive tools on the AI & PM Hub platform.</p><h3>YOUR DASHBOARD</h3><p>Visit <a href=\"{platform.url}/admin/tribe/\">your tribe dashboard</a> to see:</p><ul><li>Your tribe members and profile status</li><li>Kanban board with production items</li><li>Engagement and attendance metrics</li><li>Broadcast messages to your team</li></ul><h3>FIRST STEPS AS LEADER</h3><ol><li>Review your tribe roster</li><li>Schedule the next meeting</li><li>Set up board goals</li></ol><p>Need help? <a href=\"{platform.url}/help\">Help Center</a></p><hr><p style=\"font-size:12px;color:#64748B\">AI & PM Study and Research Hub<br><a href=\"{unsubscribe_url}\">Unsubscribe</a></p>","es":"<h2>Hola {member.name},</h2><p>Como lider de tribu, tienes acceso a herramientas exclusivas en la plataforma del Nucleo IA & GP.</p><h3>TU DASHBOARD</h3><p>Accede a <a href=\"{platform.url}/admin/tribe/\">tu dashboard de tribu</a> para ver:</p><ul><li>Miembros de tu tribu y estado del perfil</li><li>Tablero Kanban con items de produccion</li><li>Metricas de engagement y asistencia</li><li>Envio de mensajes a tu equipo</li></ul><h3>PRIMEROS PASOS COMO LIDER</h3><ol><li>Revisa el roster de tu tribu</li><li>Agenda la proxima reunion</li><li>Configura las metas del tablero</li></ol><p>Necesitas ayuda? <a href=\"{platform.url}/help\">Centro de Ayuda</a></p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudios e Investigacion en IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar suscripcion</a></p>"}'::jsonb,
  '{"pt":"Ola {member.name},\n\nComo lider de tribo, voce tem acesso a ferramentas exclusivas.\n\nAcesse seu dashboard: {platform.url}/admin/tribe/\n\nPrimeiros passos:\n1. Revise o roster\n2. Agende o proximo encontro\n3. Configure metas do board\n\nCancelar inscricao: {unsubscribe_url}","en":"Hello {member.name},\n\nAs a tribe leader, you have access to exclusive tools.\n\nVisit your dashboard: {platform.url}/admin/tribe/\n\nFirst steps:\n1. Review roster\n2. Schedule next meeting\n3. Set up board goals\n\nUnsubscribe: {unsubscribe_url}","es":"Hola {member.name},\n\nComo lider de tribu, tienes herramientas exclusivas.\n\nAccede a tu dashboard: {platform.url}/admin/tribe/\n\nPrimeros pasos:\n1. Revisa el roster\n2. Agenda la proxima reunion\n3. Configura metas del tablero\n\nCancelar suscripcion: {unsubscribe_url}"}'::jsonb,
  '{"roles":["tribe_leader"],"designations":[],"chapters":[],"all":false}'::jsonb,
  'onboarding',
  '["member.name","member.tribe","platform.url","unsubscribe_url"]'::jsonb
);

-- Template 3: Beta Launch — All Members
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Lancamento Beta — Todos os Membros',
  'beta-launch-all',
  '{"pt":"Plataforma Nucleo IA & GP em Beta — conheca e de seu feedback","en":"AI & PM Hub Platform in Beta — explore and give your feedback","es":"Plataforma Nucleo IA & GP en Beta — conoce y da tu feedback"}'::jsonb,
  '{"pt":"<h2>Ola {member.name},</h2><p>Apos meses de desenvolvimento, a plataforma digital do Nucleo esta em beta aberto para todos os colaboradores.</p><h3>O QUE JA ESTA FUNCIONANDO</h3><ul><li>Workspace personalizado por papel</li><li>Board de producao por tribo (Kanban)</li><li>Trilha de Certificacao IA (8 cursos)</li><li>Gamificacao com XP e ranking</li><li>Registro de presenca em 1 clique</li><li>Relatorios por capitulo e ciclo</li><li>Dashboard de tribo para lideres</li><li>Processo seletivo digital</li><li>Conformidade LGPD completa</li></ul><h3>O QUE PRECISAMOS DE VOCE</h3><ol><li>Acesse e complete seu perfil</li><li>Explore sua tribo e board</li><li>Nos de feedback — o que funciona, o que nao funciona</li></ol><p><a href=\"{platform.url}\" style=\"display:inline-block;padding:12px 24px;background:#0D9488;color:white;border-radius:8px;text-decoration:none;font-weight:600\">Acessar Plataforma</a></p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudos e Pesquisa em IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar inscricao</a></p>","en":"<h2>Hello {member.name},</h2><p>After months of development, the Hub digital platform is in open beta for all collaborators.</p><h3>WHAT IS ALREADY WORKING</h3><ul><li>Role-based personalized workspace</li><li>Tribe production board (Kanban)</li><li>AI Certification Trail (8 courses)</li><li>Gamification with XP and ranking</li><li>1-click attendance tracking</li><li>Chapter and cycle reports</li><li>Tribe dashboard for leaders</li><li>Digital selection process</li><li>Full LGPD compliance</li></ul><h3>WHAT WE NEED FROM YOU</h3><ol><li>Access and complete your profile</li><li>Explore your tribe and board</li><li>Give us feedback — what works, what doesn''t</li></ol><p><a href=\"{platform.url}\" style=\"display:inline-block;padding:12px 24px;background:#0D9488;color:white;border-radius:8px;text-decoration:none;font-weight:600\">Access Platform</a></p><hr><p style=\"font-size:12px;color:#64748B\">AI & PM Study and Research Hub<br><a href=\"{unsubscribe_url}\">Unsubscribe</a></p>","es":"<h2>Hola {member.name},</h2><p>Despues de meses de desarrollo, la plataforma digital del Nucleo esta en beta abierto para todos los colaboradores.</p><h3>QUE YA ESTA FUNCIONANDO</h3><ul><li>Workspace personalizado por rol</li><li>Tablero de produccion por tribu (Kanban)</li><li>Ruta de Certificacion IA (8 cursos)</li><li>Gamificacion con XP y ranking</li><li>Registro de asistencia en 1 clic</li><li>Reportes por capitulo y ciclo</li><li>Dashboard de tribu para lideres</li><li>Proceso de seleccion digital</li><li>Conformidad LGPD completa</li></ul><h3>QUE NECESITAMOS DE TI</h3><ol><li>Accede y completa tu perfil</li><li>Explora tu tribu y tablero</li><li>Danos feedback — que funciona, que no funciona</li></ol><p><a href=\"{platform.url}\" style=\"display:inline-block;padding:12px 24px;background:#0D9488;color:white;border-radius:8px;text-decoration:none;font-weight:600\">Acceder a la Plataforma</a></p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudios e Investigacion en IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar suscripcion</a></p>"}'::jsonb,
  '{"pt":"Ola {member.name},\n\nA plataforma digital do Nucleo esta em beta aberto.\n\nO que ja funciona: Workspace, Board Kanban, Trilha IA, Gamificacao, Presenca, Relatorios, Dashboard, Processo Seletivo, LGPD.\n\nO que precisamos:\n1. Acesse e complete seu perfil\n2. Explore sua tribo\n3. De feedback\n\nAcesse: {platform.url}\n\nCancelar inscricao: {unsubscribe_url}","en":"Hello {member.name},\n\nThe Hub digital platform is in open beta.\n\nAlready working: Workspace, Kanban Board, AI Trail, Gamification, Attendance, Reports, Dashboard, Selection, LGPD.\n\nWhat we need:\n1. Access and complete your profile\n2. Explore your tribe\n3. Give feedback\n\nAccess: {platform.url}\n\nUnsubscribe: {unsubscribe_url}","es":"Hola {member.name},\n\nLa plataforma del Nucleo esta en beta abierto.\n\nYa funciona: Workspace, Tablero Kanban, Ruta IA, Gamificacion, Asistencia, Reportes, Dashboard, Seleccion, LGPD.\n\nQue necesitamos:\n1. Accede y completa tu perfil\n2. Explora tu tribu\n3. Da feedback\n\nAccede: {platform.url}\n\nCancelar suscripcion: {unsubscribe_url}"}'::jsonb,
  '{"roles":[],"designations":[],"chapters":[],"all":true}'::jsonb,
  'announcement',
  '["member.name","platform.url","unsubscribe_url"]'::jsonb
);

-- Template 4: PMI Key Personnel (External)
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'PMI Key Personnel Outreach',
  'pmi-key-personnel',
  '{"pt":"Hub de Pesquisa em IA & GP — Uma Iniciativa Multi-Capitulos","en":"AI & Project Management Research Hub — A Cross-Chapter Initiative","es":"Hub de Investigacion en IA & GP — Una Iniciativa Multi-Capitulos"}'::jsonb,
  '{"pt":"<h2>Prezado(a) {member.name},</h2><p>Escrevo para compartilhar uma iniciativa colaborativa entre cinco Capitulos PMI&reg; no Brasil (GO, CE, DF, MG, RS) que pode ser de seu interesse.</p><h3>O QUE CONSTRUIMOS</h3><p>O Hub de Pesquisa em IA & GP e uma plataforma voluntaria onde profissionais de gerenciamento de projetos investigam como a IA esta transformando nossa profissao. Organizado em tribos tematicas de pesquisa, o grupo produziu artigos publicados no ProjectManagement.com e acumulou horas de impacto colaborativo.</p><h3>O QUE TORNA UNICO</h3><ul><li>Arquitetura de custo zero (plataforma inteira em free tiers)</li><li>Processo seletivo estruturado com avaliacao cega</li><li>Governanca digital com Manual R2 formal</li><li>Plataforma conforme LGPD com privacy by design</li><li>Interface trilingue (PT-BR, EN-US, ES-LATAM)</li><li>Finalista Carlos Novello Voluntario do Ano 2025</li></ul><h3>A PLATAFORMA</h3><p><a href=\"{platform.url}/about\">{platform.url}/about</a></p><p>Acreditamos que este modelo e replicavel por outros capitulos e regioes. Se voce gostaria de saber mais ou explorar colaboracao, ficarei feliz em apresentar nossa metodologia e resultados.</p><p>Atenciosamente,<br><strong>Vitor Maia Rodovalho, PMP&reg;</strong><br>Gerente de Projetos — PMI&reg; AI & GP Research Hub<br>+1 (267) 874-8329</p><hr><p style=\"font-size:12px;color:#64748B\">Voce recebeu este email por ser um lider na comunidade PMI&reg;.<br><a href=\"{unsubscribe_url}\">Cancelar inscricao</a></p>","en":"<h2>Dear {member.name},</h2><p>I am writing to share a collaborative initiative between five PMI&reg; Chapters in Brazil (GO, CE, DF, MG, RS) that may be of interest to you.</p><h3>WHAT WE BUILT</h3><p>The AI & PM Research Hub is a volunteer-driven research platform where project management professionals investigate how AI is transforming our profession. Organized in thematic research tribes, the group has produced published articles on ProjectManagement.com and accumulated hours of collaborative impact.</p><h3>WHAT MAKES IT UNIQUE</h3><ul><li>Zero-cost architecture (entire platform on free tiers)</li><li>Structured selection process with blind evaluation</li><li>Digital governance with formal Manual R2</li><li>LGPD-compliant platform with privacy by design</li><li>Trilingual interface (PT-BR, EN-US, ES-LATAM)</li><li>Carlos Novello Volunteer of the Year 2025 finalist</li></ul><h3>THE PLATFORM</h3><p><a href=\"{platform.url}/about\">{platform.url}/about</a></p><p>We believe this model is replicable by other chapters and regions. If you would like to learn more or explore collaboration, I would welcome the opportunity to present our methodology and results.</p><p>Best regards,<br><strong>Vitor Maia Rodovalho, PMP&reg;</strong><br>Project Manager — PMI&reg; AI & GP Research Hub<br>+1 (267) 874-8329</p><hr><p style=\"font-size:12px;color:#64748B\">You received this because you are a leader in the PMI&reg; community.<br><a href=\"{unsubscribe_url}\">Unsubscribe</a></p>","es":"<h2>Estimado(a) {member.name},</h2><p>Le escribo para compartir una iniciativa colaborativa entre cinco Capitulos PMI&reg; en Brasil (GO, CE, DF, MG, RS) que puede ser de su interes.</p><h3>QUE CONSTRUIMOS</h3><p>El Hub de Investigacion en IA & GP es una plataforma voluntaria donde profesionales de gestion de proyectos investigan como la IA esta transformando nuestra profesion.</p><h3>QUE LO HACE UNICO</h3><ul><li>Arquitectura de costo cero</li><li>Proceso selectivo con evaluacion ciega</li><li>Gobernanza digital con Manual R2</li><li>Plataforma conforme LGPD</li><li>Interfaz trilingue (PT-BR, EN-US, ES-LATAM)</li><li>Finalista Carlos Novello Voluntario del Ano 2025</li></ul><h3>LA PLATAFORMA</h3><p><a href=\"{platform.url}/about\">{platform.url}/about</a></p><p>Creemos que este modelo es replicable. Si desea saber mas, sera un placer presentar nuestra metodologia.</p><p>Saludos cordiales,<br><strong>Vitor Maia Rodovalho, PMP&reg;</strong><br>Gerente de Proyectos — PMI&reg; AI & GP Research Hub<br>+1 (267) 874-8329</p><hr><p style=\"font-size:12px;color:#64748B\">Recibio este email por ser lider en la comunidad PMI&reg;.<br><a href=\"{unsubscribe_url}\">Cancelar suscripcion</a></p>"}'::jsonb,
  '{"pt":"Prezado(a) {member.name},\n\nCompartilho uma iniciativa entre 5 Capitulos PMI no Brasil.\n\nO Hub de Pesquisa em IA & GP e uma plataforma voluntaria de pesquisa.\n\nDestaques: custo zero, avaliacao cega, LGPD, trilingue, finalista Novello 2025.\n\nSaiba mais: {platform.url}/about\n\nVitor Maia Rodovalho, PMP\n+1 (267) 874-8329\n\nCancelar: {unsubscribe_url}","en":"Dear {member.name},\n\nSharing a collaborative initiative between 5 PMI Chapters in Brazil.\n\nThe AI & PM Research Hub is a volunteer-driven research platform.\n\nHighlights: zero-cost, blind evaluation, LGPD, trilingual, Novello 2025 finalist.\n\nLearn more: {platform.url}/about\n\nVitor Maia Rodovalho, PMP\n+1 (267) 874-8329\n\nUnsubscribe: {unsubscribe_url}","es":"Estimado(a) {member.name},\n\nComparto una iniciativa entre 5 Capitulos PMI en Brasil.\n\nEl Hub de Investigacion en IA & GP es una plataforma voluntaria.\n\nDestaques: costo cero, evaluacion ciega, LGPD, trilingue, finalista Novello 2025.\n\nMas informacion: {platform.url}/about\n\nVitor Maia Rodovalho, PMP\n+1 (267) 874-8329\n\nCancelar: {unsubscribe_url}"}'::jsonb,
  '{"roles":[],"designations":[],"chapters":[],"all":false}'::jsonb,
  'announcement',
  '["member.name","platform.url","unsubscribe_url"]'::jsonb
);

-- Template 5: Blog Post Announcement
INSERT INTO public.campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Anuncio de Blog Post',
  'blog-announcement',
  '{"pt":"Novo artigo no Blog — Como construimos uma plataforma de pesquisa com custo zero","en":"New blog post — How we built a research platform at zero cost","es":"Nuevo articulo en el Blog — Como construimos una plataforma de investigacion con costo cero"}'::jsonb,
  '{"pt":"<h2>Ola {member.name},</h2><p>Publicamos um novo artigo no blog do Nucleo IA & GP:</p><h3>Como 5 Capitulos PMI&reg; Construiram uma Plataforma de Pesquisa com Custo Zero</h3><p>Neste artigo, compartilhamos a jornada de construcao da plataforma digital que conecta pesquisadores de 5 capitulos PMI&reg; no Brasil — desde o problema inicial ate os resultados alcancados.</p><p><a href=\"{platform.url}/blog/plataforma-custo-zero\" style=\"display:inline-block;padding:12px 24px;background:#0D9488;color:white;border-radius:8px;text-decoration:none;font-weight:600\">Ler Artigo</a></p><p>Compartilhe no LinkedIn e ajude a divulgar o trabalho do Nucleo!</p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudos e Pesquisa em IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar inscricao</a></p>","en":"<h2>Hello {member.name},</h2><p>We published a new article on the AI & PM Hub blog:</p><h3>How 5 PMI&reg; Chapters Built a Research Platform at Zero Cost</h3><p>In this article, we share the journey of building the digital platform that connects researchers from 5 PMI&reg; chapters in Brazil — from the initial problem to the results achieved.</p><p><a href=\"{platform.url}/blog/plataforma-custo-zero\" style=\"display:inline-block;padding:12px 24px;background:#0D9488;color:white;border-radius:8px;text-decoration:none;font-weight:600\">Read Article</a></p><p>Share on LinkedIn and help spread the word!</p><hr><p style=\"font-size:12px;color:#64748B\">AI & PM Study and Research Hub<br><a href=\"{unsubscribe_url}\">Unsubscribe</a></p>","es":"<h2>Hola {member.name},</h2><p>Publicamos un nuevo articulo en el blog del Nucleo IA & GP:</p><h3>Como 5 Capitulos PMI&reg; Construyeron una Plataforma de Investigacion con Costo Cero</h3><p>En este articulo, compartimos el viaje de construccion de la plataforma digital que conecta investigadores de 5 capitulos PMI&reg; en Brasil.</p><p><a href=\"{platform.url}/blog/plataforma-custo-zero\" style=\"display:inline-block;padding:12px 24px;background:#0D9488;color:white;border-radius:8px;text-decoration:none;font-weight:600\">Leer Articulo</a></p><p>Comparte en LinkedIn y ayuda a difundir!</p><hr><p style=\"font-size:12px;color:#64748B\">Nucleo de Estudios e Investigacion en IA & GP<br><a href=\"{unsubscribe_url}\">Cancelar suscripcion</a></p>"}'::jsonb,
  '{"pt":"Ola {member.name},\n\nNovo artigo: Como 5 Capitulos PMI Construiram uma Plataforma com Custo Zero\n\nLeia: {platform.url}/blog/plataforma-custo-zero\n\nCompartilhe no LinkedIn!\n\nCancelar inscricao: {unsubscribe_url}","en":"Hello {member.name},\n\nNew article: How 5 PMI Chapters Built a Research Platform at Zero Cost\n\nRead: {platform.url}/blog/plataforma-custo-zero\n\nShare on LinkedIn!\n\nUnsubscribe: {unsubscribe_url}","es":"Hola {member.name},\n\nNuevo articulo: Como 5 Capitulos PMI Construyeron una Plataforma con Costo Cero\n\nLeer: {platform.url}/blog/plataforma-custo-zero\n\nComparte en LinkedIn!\n\nCancelar suscripcion: {unsubscribe_url}"}'::jsonb,
  '{"roles":[],"designations":[],"chapters":[],"all":true}'::jsonb,
  'newsletter',
  '["member.name","platform.url","unsubscribe_url"]'::jsonb
);

-- ───────────────────────────────────────────────
-- 9. Seed first blog post (draft)
-- ───────────────────────────────────────────────
INSERT INTO public.blog_posts (slug, title, excerpt, body_html, category, tags, status, is_featured)
VALUES (
  'plataforma-custo-zero',
  '{"pt":"Como 5 Capitulos PMI Construiram uma Plataforma de Pesquisa com Custo Zero","en":"How 5 PMI Chapters Built a Research Platform at Zero Cost","es":"Como 5 Capitulos PMI Construyeron una Plataforma de Investigacion con Costo Cero"}'::jsonb,
  '{"pt":"A jornada de construcao de uma plataforma digital que conecta pesquisadores de 5 capitulos PMI no Brasil — do problema a solucao, com custo zero.","en":"The journey of building a digital platform connecting researchers from 5 PMI chapters in Brazil — from problem to solution, at zero cost.","es":"El viaje de construccion de una plataforma digital que conecta investigadores de 5 capitulos PMI en Brasil — del problema a la solucion, con costo cero."}'::jsonb,
  '{"pt":"<article><h1>Como 5 Capitulos PMI&reg; Construiram uma Plataforma de Pesquisa com Custo Zero</h1><p><em>Por Vitor Maia Rodovalho, PMP&reg; — Gerente de Projetos do Nucleo IA & GP</em></p><h2>1. O Problema</h2><p>Em 2024, o Nucleo de Estudos e Pesquisa em IA e Gerenciamento de Projetos reunia voluntarios de cinco capitulos PMI&reg; brasileiros (GO, CE, DF, MG, RS). A comunicacao acontecia por WhatsApp, o controle era em planilhas, e a producao cientifica era descentralizada. Nao havia uma plataforma que integrasse governanca, producao e engajamento.</p><h2>2. A Solucao</h2><p>Construimos uma plataforma digital completa usando exclusivamente ferramentas com tier gratuito:</p><ul><li><strong>Astro</strong> — Framework web com SSR e ilhas React</li><li><strong>Supabase</strong> — PostgreSQL gerenciado com RLS e Edge Functions</li><li><strong>Cloudflare Pages</strong> — Deploy global com CDN</li><li><strong>Tailwind CSS</strong> — Design system responsivo</li></ul><p>O custo total de infraestrutura: <strong>R$ 0,00/mes</strong>.</p><h2>3. Governanca</h2><p>O Manual R2 define papeis em 3 eixos (hierarquico, operacional, designacoes), processo seletivo com avaliacao cega, e ciclos semestrais estruturados.</p><h2>4. Seguranca</h2><p>A plataforma implementa LGPD completa: Row Level Security em todas as tabelas, SECURITY DEFINER em RPCs, mascaramento de PII, Sentry para monitoramento, e politicas de retencao de dados.</p><h2>5. Resultados</h2><ul><li>44 pesquisadores ativos</li><li>8 tribos de pesquisa</li><li>10+ artigos publicados no ProjectManagement.com</li><li>1.800+ horas de impacto colaborativo</li><li>520+ testes automatizados</li><li>Interface trilingue (PT-BR, EN-US, ES-LATAM)</li><li>Finalista Carlos Novello Voluntario do Ano 2025</li></ul><h2>6. Licoes Aprendidas</h2><p>A principal licao: voluntarios engajados + ferramentas modernas + governanca estruturada = resultados profissionais sem orcamento. O modelo e replicavel por qualquer capitulo PMI&reg; do mundo.</p><h2>7. Saiba Mais</h2><p>Visite nossa pagina de impacto e conheca o projeto em detalhes.</p></article>","en":"<article><h1>How 5 PMI&reg; Chapters Built a Research Platform at Zero Cost</h1><p><em>By Vitor Maia Rodovalho, PMP&reg; — Project Manager, AI & PM Research Hub</em></p><h2>1. The Problem</h2><p>In 2024, the AI & Project Management Study and Research Hub brought together volunteers from five Brazilian PMI&reg; chapters (GO, CE, DF, MG, RS). Communication was via WhatsApp, tracking was in spreadsheets, and research output was decentralized.</p><h2>2. The Solution</h2><p>We built a complete digital platform using exclusively free-tier tools:</p><ul><li><strong>Astro</strong> — Web framework with SSR and React islands</li><li><strong>Supabase</strong> — Managed PostgreSQL with RLS and Edge Functions</li><li><strong>Cloudflare Pages</strong> — Global CDN deployment</li><li><strong>Tailwind CSS</strong> — Responsive design system</li></ul><p>Total infrastructure cost: <strong>$0.00/month</strong>.</p><h2>3. Governance</h2><p>Manual R2 defines 3-axis roles (hierarchical, operational, designations), blind selection, and structured semester cycles.</p><h2>4. Security</h2><p>Full LGPD compliance: Row Level Security, SECURITY DEFINER RPCs, PII masking, Sentry monitoring, data retention policies.</p><h2>5. Results</h2><ul><li>44 active researchers</li><li>8 research tribes</li><li>10+ published articles on ProjectManagement.com</li><li>1,800+ hours of collaborative impact</li><li>520+ automated tests</li><li>Trilingual interface (PT-BR, EN-US, ES-LATAM)</li><li>Carlos Novello Volunteer of the Year 2025 finalist</li></ul><h2>6. Lessons Learned</h2><p>The main lesson: engaged volunteers + modern tools + structured governance = professional results without a budget. The model is replicable by any PMI&reg; chapter worldwide.</p><h2>7. Learn More</h2><p>Visit our impact page to learn about the project in detail.</p></article>","es":"<article><h1>Como 5 Capitulos PMI&reg; Construyeron una Plataforma de Investigacion con Costo Cero</h1><p><em>Por Vitor Maia Rodovalho, PMP&reg; — Gerente de Proyectos, Nucleo IA & GP</em></p><h2>1. El Problema</h2><p>En 2024, el Nucleo de Estudios e Investigacion en IA y GP reunia voluntarios de cinco capitulos PMI&reg; brasilenios (GO, CE, DF, MG, RS). La comunicacion era por WhatsApp y el control en planillas.</p><h2>2. La Solucion</h2><p>Construimos una plataforma digital completa usando herramientas gratuitas:</p><ul><li><strong>Astro</strong> — Framework web con SSR e islas React</li><li><strong>Supabase</strong> — PostgreSQL con RLS y Edge Functions</li><li><strong>Cloudflare Pages</strong> — Deploy global con CDN</li><li><strong>Tailwind CSS</strong> — Sistema de diseno responsivo</li></ul><p>Costo total: <strong>$0.00/mes</strong>.</p><h2>3. Gobernanza</h2><p>El Manual R2 define roles en 3 ejes, seleccion ciega y ciclos semestrales.</p><h2>4. Seguridad</h2><p>Conformidad LGPD completa: RLS, SECURITY DEFINER, mascaramiento de PII, Sentry, politicas de retencion.</p><h2>5. Resultados</h2><ul><li>44 investigadores activos</li><li>8 tribus de investigacion</li><li>10+ articulos publicados</li><li>1.800+ horas de impacto</li><li>520+ tests automatizados</li><li>Interfaz trilingue</li><li>Finalista Novello 2025</li></ul><h2>6. Lecciones Aprendidas</h2><p>Voluntarios + herramientas modernas + gobernanza = resultados profesionales sin presupuesto.</p></article>"}'::jsonb,
  'case-study',
  ARRAY['zero-cost', 'pmi', 'ai', 'platform', 'case-study'],
  'draft',
  true
);

-- ───────────────────────────────────────────────
-- 10. GRANTS
-- ───────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.campaign_sends TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.campaign_recipients TO authenticated;
GRANT SELECT ON public.blog_posts TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.blog_posts TO authenticated;
