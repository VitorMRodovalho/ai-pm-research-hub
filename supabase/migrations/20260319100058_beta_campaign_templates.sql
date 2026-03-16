-- Beta launch campaign templates — 8 tier-specific templates
-- Variables: {member.name}, {member.tribe}, {platform.url}, {unsubscribe_url}

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Pesquisadores', 'beta-pesquisadores',
  '{"pt": "🚀 Seu espaço de trabalho no Hub está pronto — acesse agora"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 🚀</h1><p>O <strong>AI & PM Research Hub</strong> está em beta e seu workspace já está configurado.</p><h2 style=\"color:#0d9488;font-size:16px\">O que você pode fazer agora:</h2><ul><li>📋 Ver os entregáveis da sua tribo ({member.tribe})</li><li>🏆 Conferir seu ranking e XP na Gamificação</li><li>📚 Completar a Trilha PMI (6 cursos gratuitos)</li><li>✅ Registrar presença nas reuniões</li><li>📝 Submeter publicações acadêmicas</li></ul><p><a href=\"{platform.url}/workspace\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Acessar meu Workspace →</a></p><p style=\"font-size:12px;color:#666\">Dúvidas? Use o botão ❓ no canto inferior direito da plataforma.</p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo de Estudos e Pesquisa em IA e GP — PMI Chapters Brasil<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! O AI & PM Research Hub está em beta. Acesse: {platform.url}/workspace"}'::jsonb,
  '{"roles": ["researcher"]}'::jsonb, 'announcement',
  '["member.name", "member.tribe", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Líderes de Tribo', 'beta-lideres',
  '{"pt": "⚡ Hub Beta: seu board e ferramentas de líder estão prontos"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! ⚡</h1><p>Como líder da <strong>{member.tribe}</strong>, você tem acesso a ferramentas exclusivas no Hub Beta:</p><h2 style=\"color:#0d9488;font-size:16px\">Suas ferramentas de líder:</h2><ul><li>📋 <strong>Board Kanban</strong> — Criar e arrastar cards entre colunas</li><li>✅ <strong>Presença em Lote</strong> — Registrar toda a tribo de uma vez</li><li>📅 <strong>Eventos</strong> — Criar reuniões da tribo</li><li>📊 <strong>Checklists</strong> — Acompanhar progresso dos entregáveis</li><li>🏆 <strong>Gamificação</strong> — Ver ranking e engajamento da tribo</li></ul><p><a href=\"{platform.url}/workspace\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Acessar Board da Tribo →</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP — PMI Chapters Brasil<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! Suas ferramentas de líder estão prontas. Acesse: {platform.url}/workspace"}'::jsonb,
  '{"roles": ["tribe_leader"]}'::jsonb, 'announcement',
  '["member.name", "member.tribe", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Sponsors', 'beta-sponsors',
  '{"pt": "🏛️ Hub Beta: painel executivo e métricas do Núcleo disponíveis"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 🏛️</h1><p>O AI & PM Research Hub está em beta. Como <strong>Sponsor/Patrocinador</strong>, você tem acesso ao painel executivo.</p><h2 style=\"color:#0d9488;font-size:16px\">Disponível para você:</h2><ul><li>📊 <strong>Analytics</strong> — Métricas de impacto e ROI</li><li>🏆 <strong>Gamificação</strong> — Ranking geral</li><li>📚 <strong>Publicações</strong> — Pipeline acadêmico</li><li>📅 <strong>Eventos</strong> — Calendário do ciclo</li></ul><p><a href=\"{platform.url}\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Acessar o Hub →</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! O painel executivo está disponível: {platform.url}"}'::jsonb,
  '{"roles": ["sponsor"]}'::jsonb, 'announcement',
  '["member.name", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Pontos Focais', 'beta-liaisons',
  '{"pt": "🔗 Hub Beta: métricas do seu capítulo estão disponíveis"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 🔗</h1><p>As métricas do seu capítulo já estão disponíveis no Hub Beta.</p><h2 style=\"color:#0d9488;font-size:16px\">Disponível:</h2><ul><li>📊 <strong>Analytics do Capítulo</strong></li><li>🏆 <strong>Ranking</strong></li><li>📚 <strong>Publicações</strong></li><li>📅 <strong>Eventos</strong></li></ul><p><a href=\"{platform.url}\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Acessar o Hub →</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! Métricas do capítulo disponíveis: {platform.url}"}'::jsonb,
  '{"roles": ["chapter_liaison"]}'::jsonb, 'announcement',
  '["member.name", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Vice-Gerente', 'beta-deputy',
  '{"pt": "👑 Hub Beta: painel administrativo completo disponível"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 👑</h1><p>O Hub está em beta com painel administrativo completo.</p><h2 style=\"color:#0d9488;font-size:16px\">Acesso completo:</h2><ul><li>⚙️ <strong>Painel Admin</strong></li><li>📊 <strong>Analytics</strong></li><li>📧 <strong>Campanhas</strong></li><li>📋 <strong>Portfólio</strong></li><li>👁️ <strong>Tier Viewer</strong></li></ul><p><a href=\"{platform.url}/admin\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Acessar Admin →</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! Painel admin disponível: {platform.url}/admin"}'::jsonb,
  '{"designations": ["deputy_manager"]}'::jsonb, 'announcement',
  '["member.name", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Equipe de Comunicação', 'beta-comms',
  '{"pt": "📣 Hub Beta: boards de comunicação e blog prontos"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 📣</h1><p>Os boards de comunicação e blog estão prontos.</p><h2 style=\"color:#0d9488;font-size:16px\">Ferramentas:</h2><ul><li>📋 <strong>Board de Comunicação</strong></li><li>📝 <strong>Blog</strong> — Editor WYSIWYG</li><li>📊 <strong>Métricas</strong></li></ul><p><a href=\"{platform.url}/workspace\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Acessar Workspace →</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! Boards de comms prontos: {platform.url}/workspace"}'::jsonb,
  '{"designations": ["comms_leader", "comms_member"]}'::jsonb, 'announcement',
  '["member.name", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Beta Launch — Candidatos', 'beta-candidatos',
  '{"pt": "📋 Acompanhe seu processo seletivo no Hub"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 📋</h1><p>O Hub permite acompanhar seu processo seletivo online.</p><ul><li>📊 <strong>Status do Processo</strong></li><li>📚 <strong>Sobre o Núcleo</strong></li></ul><p><a href=\"{platform.url}\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Conhecer o Hub →</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP<br><a href=\"{unsubscribe_url}\">Descadastrar</a></p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! Acompanhe seu processo: {platform.url}"}'::jsonb,
  '{"roles": ["candidate"]}'::jsonb, 'announcement',
  '["member.name", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();

INSERT INTO campaign_templates (name, slug, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'Reengajamento — Membros Inativos', 'reengagement-inactive',
  '{"pt": "👋 Sentimos sua falta no Núcleo IA & GP"}'::jsonb,
  '{"pt": "<div style=\"font-family:sans-serif;max-width:600px;margin:0 auto;padding:24px\"><h1 style=\"color:#1e1b4b;font-size:22px\">Olá, {member.name}! 👋</h1><p>Faz um tempo que não vemos você. Muita coisa aconteceu:</p><ul><li>🚀 Plataforma digital com boards Kanban e gamificação</li><li>📊 Dashboard de impacto em tempo real</li><li>🏆 Sistema de XP e ranking</li><li>📚 Pipeline de publicações</li></ul><p>Seu espaço continua reservado na <strong>{member.tribe}</strong>.</p><p><a href=\"{platform.url}/workspace\" style=\"display:inline-block;padding:12px 24px;background:#0d9488;color:#fff;text-decoration:none;border-radius:8px;font-weight:bold\">Voltar ao Hub →</a></p><p style=\"font-size:12px;color:#666\"><a href=\"{unsubscribe_url}\">Descadastrar</a></p><hr style=\"border:none;border-top:1px solid #eee;margin:24px 0\"><p style=\"font-size:11px;color:#999\">Núcleo IA & GP</p></div>"}'::jsonb,
  '{"pt": "Olá, {member.name}! Sentimos sua falta. Acesse: {platform.url}/workspace"}'::jsonb,
  '{"include_inactive": true, "all": true}'::jsonb, 'operational',
  '["member.name", "member.tribe", "platform.url", "unsubscribe_url"]'::jsonb
) ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, target_audience = EXCLUDED.target_audience, updated_at = now();
