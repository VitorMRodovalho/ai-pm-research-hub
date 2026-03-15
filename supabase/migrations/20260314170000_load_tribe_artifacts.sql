-- Load 60 tribe artifacts as board cards with baseline dates and unified tags
-- Each artifact gets: board_item + board_item_tag_assignments

DO $$
DECLARE
  -- Board IDs
  b1 uuid := '430df293-6676-4507-b893-98421a1397ca';
  b2 uuid := '10d4c04a-a256-40ce-93d6-8ae745e7875d';
  b3 uuid := '50474fd3-adbc-4980-ba2e-6dffec420321';
  b4 uuid := 'e62bf41c-a762-4e07-8a18-4f8fff23c2f7';
  b5 uuid := 'bb0c431c-3269-4b03-b24e-cf406b59ee77';
  b6 uuid := '118b55be-9dcd-4b2d-82c7-5c457fb1fc1e';
  b7 uuid := '38cc997c-9345-4ee1-acb5-ed2ddf33b734';
  b8 uuid := '2865743d-a121-4f75-866a-2736b238f7c0';

  -- Leader IDs
  l1 uuid := 'f64ee70a-5d37-4670-9306-a5efe4666cd3'; -- Hayala Curto
  l2 uuid := 'a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7'; -- Débora Moura
  l3 uuid := 'e25c829f-6ba3-47a9-bf15-b72c6b74450d'; -- Marcel Fleming
  l4 uuid := 'c8b930c3-62ec-4d38-881e-307cd57a44f7'; -- Fernando Maquiaveli
  l5 uuid := '622ab18b-a8b4-46ff-b151-7bbd34394ed3'; -- Jefferson Pinto
  l6 uuid := '92d26057-5550-4f15-a3bf-b00eed5f32f9'; -- Fabricio Costa
  l7 uuid := 'c204ac61-4d39-42f2-8d28-814727b62e90'; -- Marcos Klemz
  l8 uuid := '63b87315-78ab-43f7-bb05-cc2e89682bbf'; -- Ana Carla Cavalcante

  -- Tag IDs
  t_pesquisa          uuid := '1e08be00-704c-4e2f-8a76-e66168257df0';
  t_publicacao        uuid := 'afeef1bc-a1ff-4827-99ae-1d2d01156ab1';
  t_artigo_linkedin   uuid := '20d099e0-7742-418e-b1f9-845ed4b2a26d';
  t_quick_win         uuid := '3fb76a73-20b2-42aa-88ff-c28fb369eadd';
  t_framework         uuid := '31d72613-1d27-4b8e-a049-7ecc5cf2de19';
  t_poc               uuid := '18bb511c-ea54-4290-8682-91c2c6ecf6ce';
  t_artigo_academico  uuid := '8c7b99bc-e5f9-43d7-9ad7-3560fe8c653c';
  t_webinar           uuid := 'c3846065-d7ff-4454-b779-863907f48951';
  t_entrega_final     uuid := '4dfdc382-518b-4956-89ce-548782a9d1fb';
  t_ferramenta        uuid := 'a691fe61-f352-4d74-b84c-19e7f61f1d48';
  t_infografico       uuid := '9bd13441-40f0-4c4c-8800-b7f49a811c65';
  t_report            uuid := '12189be2-d92a-4d27-9900-d1705a0e7037';
  t_estudo_caso       uuid := '82e6b510-1460-4f9a-87d9-5a6e713eeb20';
  t_workshop_artifact uuid := 'ab083419-76cf-4173-bf73-a84a5357399e';
  t_gate_a            uuid := 'fa11b088-ba7b-4825-8b66-7dd71bf03178';
  t_gate_b            uuid := '50a9f2dc-5d59-437d-b816-7121a39d2eb4';

  -- Position offsets (start after existing items)
  p1 int; p2 int; p3 int; p4 int; p5 int; p6 int; p7 int; p8 int;

  -- Item IDs (reusable for tag assignments)
  item_id uuid;
BEGIN
  -- Get max positions per board
  SELECT COALESCE(MAX(position), 0) INTO p1 FROM board_items WHERE board_id = b1;
  SELECT COALESCE(MAX(position), 0) INTO p2 FROM board_items WHERE board_id = b2;
  SELECT COALESCE(MAX(position), 0) INTO p3 FROM board_items WHERE board_id = b3;
  SELECT COALESCE(MAX(position), 0) INTO p4 FROM board_items WHERE board_id = b4;
  SELECT COALESCE(MAX(position), 0) INTO p5 FROM board_items WHERE board_id = b5;
  SELECT COALESCE(MAX(position), 0) INTO p6 FROM board_items WHERE board_id = b6;
  SELECT COALESCE(MAX(position), 0) INTO p7 FROM board_items WHERE board_id = b7;
  SELECT COALESCE(MAX(position), 0) INTO p8 FROM board_items WHERE board_id = b8;

  -- ═══════════════════════════════════════════════════════════════
  -- T1 — Hayala Curto (Radar Tecnológico) — 5 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 1.1 Pesquisa: artefatos GP + IA | pesquisa | Mar/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b1, 'Pesquisa: artefatos GP + IA', 'Levantamento e análise de artefatos de GP potencializáveis por IA', l1, 'in_progress', ARRAY['pesquisa'], '2026-03-31', '2026-03-31', p1+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_pesquisa);

  -- 1.2 Artigo LinkedIn (Quick Win) | publicacao, artigo_linkedin, quick_win | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b1, 'Artigo LinkedIn (Quick Win)', 'Artigo rápido para LinkedIn sobre radar tecnológico de GP', l1, 'backlog', ARRAY['publicacao','artigo_linkedin','quick_win'], '2026-04-30', '2026-04-30', p1+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_linkedin), (item_id, t_quick_win);

  -- 1.3 Matriz de artefatos potencializáveis | framework | Mai/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b1, 'Matriz de artefatos potencializáveis', 'Framework de classificação de artefatos de GP potencializáveis por IA', l1, 'backlog', ARRAY['framework'], '2026-05-31', '2026-05-31', p1+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 1.4 Implementação de 2 padrões agênticos | poc | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b1, 'Implementação de 2 padrões agênticos', 'Prova de conceito com 2 padrões agênticos aplicados a artefatos de GP', l1, 'backlog', ARRAY['poc'], '2026-06-30', '2026-06-30', p1+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_poc);

  -- 1.5 Artigo Acadêmico | publicacao, artigo_academico | Ago/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b1, 'Artigo Acadêmico', 'Artigo acadêmico sobre radar tecnológico e padrões agênticos em GP', l1, 'backlog', ARRAY['publicacao','artigo_academico'], '2026-08-31', '2026-08-31', p1+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_academico);

  -- ═══════════════════════════════════════════════════════════════
  -- T2 — Débora Moura (Agentes Autônomos) — 4 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 2.1 Plano Inicial + Framework EAA | framework | Mar/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b2, 'Plano Inicial + Framework EAA', 'Plano inicial e framework de Engenharia de Agentes Autônomos', l2, 'in_progress', ARRAY['framework'], '2026-03-31', '2026-03-31', p2+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 2.2 Artigo LinkedIn | publicacao, artigo_linkedin | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b2, 'Artigo LinkedIn', 'Artigo LinkedIn sobre agentes autônomos em gestão de projetos', l2, 'backlog', ARRAY['publicacao','artigo_linkedin'], '2026-04-30', '2026-04-30', p2+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_linkedin);

  -- 2.3 Webinar comunitário | webinar | Mai/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b2, 'Webinar comunitário', 'Webinar aberto à comunidade PMI sobre agentes autônomos', l2, 'backlog', ARRAY['webinar'], '2026-05-31', '2026-05-31', p2+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_webinar);

  -- 2.4 Publicação Final (E-book/Guia/Artigo) | publicacao, entrega_final | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b2, 'Publicação Final (E-book/Guia/Artigo)', 'Entrega final da tribo: e-book, guia ou artigo sobre agentes autônomos', l2, 'backlog', ARRAY['publicacao','entrega_final'], '2026-06-30', '2026-06-30', p2+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_entrega_final);

  -- ═══════════════════════════════════════════════════════════════
  -- T3 — Marcel Fleming (TMO & PMO do Futuro) — 5 artifacts (NULL dates)
  -- ═══════════════════════════════════════════════════════════════

  -- 3.1 Ideação do Projeto Piloto | pesquisa | NULL
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b3, 'Ideação do Projeto Piloto', 'Ideação e definição de escopo do projeto piloto TMO/PMO do Futuro', l3, 'backlog', ARRAY['pesquisa'], NULL, NULL, p3+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_pesquisa);

  -- 3.2 Arquitetura do Modelo | framework | NULL
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b3, 'Arquitetura do Modelo', 'Desenho da arquitetura do modelo TMO/PMO do Futuro', l3, 'backlog', ARRAY['framework'], NULL, NULL, p3+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 3.3 Construção da PoC | poc | NULL
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b3, 'Construção da PoC', 'Desenvolvimento da prova de conceito TMO/PMO do Futuro', l3, 'backlog', ARRAY['poc'], NULL, NULL, p3+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_poc);

  -- 3.4 Execução da PoC | poc | NULL
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b3, 'Execução da PoC', 'Execução e validação da prova de conceito', l3, 'backlog', ARRAY['poc'], NULL, NULL, p3+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_poc);

  -- 3.5 Relatório / Artigo Final | publicacao, entrega_final | NULL
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b3, 'Relatório / Artigo Final', 'Relatório ou artigo final consolidando resultados do piloto TMO/PMO', l3, 'backlog', ARRAY['publicacao','entrega_final'], NULL, NULL, p3+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_entrega_final);

  -- ═══════════════════════════════════════════════════════════════
  -- T4 — Fernando Maquiaveli (Cultura & Change) — 11 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 4.1 Roadmap de pesquisa T4 | framework | Mar/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Roadmap de pesquisa T4', 'Roadmap de pesquisa da tribo Cultura & Change', l4, 'in_progress', ARRAY['framework'], '2026-03-31', '2026-03-31', p4+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 4.2 Biblioteca de prompts | ferramenta | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Biblioteca de prompts', 'Biblioteca curada de prompts para gestão de mudanças', l4, 'backlog', ARRAY['ferramenta'], '2026-04-30', '2026-04-30', p4+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_ferramenta);

  -- 4.3 Infográfico v1 | publicacao, infografico | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Infográfico v1', 'Primeira versão do infográfico sobre cultura e IA', l4, 'backlog', ARRAY['publicacao','infografico'], '2026-04-30', '2026-04-30', p4+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_infografico);

  -- 4.4 Playbook v1 | framework | Mai/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Playbook v1', 'Primeira versão do playbook de cultura e change management com IA', l4, 'backlog', ARRAY['framework'], '2026-05-31', '2026-05-31', p4+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 4.5 Report de resultados | publicacao, report | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Report de resultados', 'Relatório de resultados intermediários da pesquisa T4', l4, 'backlog', ARRAY['publicacao','report'], '2026-06-30', '2026-06-30', p4+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_report);

  -- 4.6 Infográfico v2 | publicacao, infografico | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Infográfico v2', 'Segunda versão do infográfico com dados atualizados', l4, 'backlog', ARRAY['publicacao','infografico'], '2026-06-30', '2026-06-30', p4+6, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_infografico);

  -- 4.7 Estudo de caso prático | publicacao, estudo_caso | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Estudo de caso prático', 'Estudo de caso prático sobre implementação de mudança cultural com IA', l4, 'backlog', ARRAY['publicacao','estudo_caso'], '2026-06-30', '2026-06-30', p4+7, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_estudo_caso);

  -- 4.8 Artigo publicado | publicacao, artigo_academico, entrega_final | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Artigo publicado', 'Artigo acadêmico publicado — entrega final da tribo', l4, 'backlog', ARRAY['publicacao','artigo_academico','entrega_final'], '2026-09-30', '2026-09-30', p4+8, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_academico), (item_id, t_entrega_final);

  -- 4.9 Webinar | webinar | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Webinar', 'Webinar da tribo Cultura & Change para a comunidade', l4, 'backlog', ARRAY['webinar'], '2026-09-30', '2026-09-30', p4+9, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_webinar);

  -- 4.10 Playbook v2 | framework | Oct/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Playbook v2', 'Segunda versão do playbook incorporando feedbacks e resultados', l4, 'backlog', ARRAY['framework'], '2026-10-31', '2026-10-31', p4+10, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 4.11 Proposta de workshop | workshop_artifact | Nov/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b4, 'Proposta de workshop', 'Proposta de workshop sobre cultura e change management com IA', l4, 'backlog', ARRAY['workshop_artifact'], '2026-11-30', '2026-11-30', p4+11, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_workshop_artifact);

  -- ═══════════════════════════════════════════════════════════════
  -- T5 — Jefferson Pinto (Talentos & Upskilling) — 8 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 5.1 Taxonomia de competências | framework | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Taxonomia de competências', 'Definição da taxonomia de competências para profissionais de projetos com IA', l5, 'backlog', ARRAY['framework'], '2026-04-30', '2026-04-30', p5+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 5.2 Matriz de Competências | framework | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Matriz de Competências', 'Matriz mapeando competências x proficiência x ferramentas de IA', l5, 'backlog', ARRAY['framework'], '2026-04-30', '2026-04-30', p5+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 5.3 Rubricas de Proficiência | framework | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Rubricas de Proficiência', 'Rubricas detalhadas de proficiência em competências de IA para GP', l5, 'backlog', ARRAY['framework'], '2026-06-30', '2026-06-30', p5+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 5.4 Checklist de Evidências | ferramenta, gate_a | Jul/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Checklist de Evidências', 'Checklist de evidências para validação de competências — Gate A', l5, 'backlog', ARRAY['ferramenta','gate_a'], '2026-07-31', '2026-07-31', p5+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_ferramenta), (item_id, t_gate_a);

  -- 5.5 Toolkit v1.0 | ferramenta, gate_b | Ago/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Toolkit v1.0', 'Toolkit completo v1.0 de talentos e upskilling — Gate B', l5, 'backlog', ARRAY['ferramenta','gate_b'], '2026-08-31', '2026-08-31', p5+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_ferramenta), (item_id, t_gate_b);

  -- 5.6 Artigo Aplicado | publicacao, artigo_academico | Oct/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Artigo Aplicado', 'Artigo acadêmico aplicado sobre talentos e upskilling em IA', l5, 'backlog', ARRAY['publicacao','artigo_academico'], '2026-10-31', '2026-10-31', p5+6, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_academico);

  -- 5.7 Webinário de Discussão | webinar | Oct/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Webinário de Discussão', 'Webinário de discussão com a comunidade sobre competências de IA', l5, 'backlog', ARRAY['webinar'], '2026-10-31', '2026-10-31', p5+7, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_webinar);

  -- 5.8 Relatório Final | publicacao, report, entrega_final | Dez/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b5, 'Relatório Final', 'Relatório final consolidando toolkit, competências e resultados — entrega final', l5, 'backlog', ARRAY['publicacao','report','entrega_final'], '2026-12-31', '2026-12-31', p5+8, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_report), (item_id, t_entrega_final);

  -- ═══════════════════════════════════════════════════════════════
  -- T6 — Fabricio Costa (ROI & Portfólio) — 8 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 6.1 Pesquisa inicial + escopo | pesquisa | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, 'Pesquisa inicial + escopo', 'Pesquisa inicial e definição de escopo de ROI e portfólio com IA', l6, 'backlog', ARRAY['pesquisa'], '2026-04-30', '2026-04-30', p6+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_pesquisa);

  -- 6.2 Artigo LinkedIn | publicacao, artigo_linkedin, quick_win | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, 'Artigo LinkedIn', 'Artigo LinkedIn quick win sobre ROI de IA em portfólios', l6, 'backlog', ARRAY['publicacao','artigo_linkedin','quick_win'], '2026-04-30', '2026-04-30', p6+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_linkedin), (item_id, t_quick_win);

  -- 6.3 1º Webinar comunidade | webinar | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, '1º Webinar comunidade', 'Primeiro webinar aberto à comunidade sobre ROI e portfólio de IA', l6, 'backlog', ARRAY['webinar'], '2026-06-30', '2026-06-30', p6+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_webinar);

  -- 6.4 Protótipo v1 plataforma | poc | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, 'Protótipo v1 plataforma', 'Primeira versão do protótipo de plataforma de ROI', l6, 'backlog', ARRAY['poc'], '2026-06-30', '2026-06-30', p6+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_poc);

  -- 6.5 Artigos contínuos | publicacao | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, 'Artigos contínuos', 'Série de artigos contínuos sobre ROI e portfólio de IA', l6, 'backlog', ARRAY['publicacao'], '2026-09-30', '2026-09-30', p6+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao);

  -- 6.6 Submissão artigo formal | publicacao, artigo_academico | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, 'Submissão artigo formal', 'Submissão de artigo acadêmico formal sobre ROI de IA', l6, 'backlog', ARRAY['publicacao','artigo_academico'], '2026-09-30', '2026-09-30', p6+6, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_academico);

  -- 6.7 2º Webinar | webinar | Nov/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, '2º Webinar', 'Segundo webinar da tribo ROI & Portfólio', l6, 'backlog', ARRAY['webinar'], '2026-11-30', '2026-11-30', p6+7, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_webinar);

  -- 6.8 Plataforma final | poc, entrega_final | Nov/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b6, 'Plataforma final', 'Versão final da plataforma de ROI — entrega final da tribo', l6, 'backlog', ARRAY['poc','entrega_final'], '2026-11-30', '2026-11-30', p6+8, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_poc), (item_id, t_entrega_final);

  -- ═══════════════════════════════════════════════════════════════
  -- T7 — Marcos Klemz (Governança & Trustworthy AI) — 9 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 7.1 Estruturação pilares Risco/Compliance | framework | Abr/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Estruturação pilares Risco/Compliance', 'Estruturação dos pilares de risco e compliance para IA em GP', l7, 'backlog', ARRAY['framework'], '2026-04-30', '2026-04-30', p7+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 7.2 Framework de Governança de IA | framework | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Framework de Governança de IA', 'Framework completo de governança de IA para organizações', l7, 'backlog', ARRAY['framework'], '2026-06-30', '2026-06-30', p7+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 7.3 Matriz Qualidade de Dados para IA | framework | Jun/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Matriz Qualidade de Dados para IA', 'Matriz de avaliação de qualidade de dados para projetos de IA', l7, 'backlog', ARRAY['framework'], '2026-06-30', '2026-06-30', p7+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 7.4 Piloto e Workshop | workshop_artifact, gate_a | Jul/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Piloto e Workshop', 'Piloto de governança de IA + workshop de validação — Gate A', l7, 'backlog', ARRAY['workshop_artifact','gate_a'], '2026-07-31', '2026-07-31', p7+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_workshop_artifact), (item_id, t_gate_a);

  -- 7.5 Guia de Métricas de Valor | ferramenta | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Guia de Métricas de Valor', 'Guia de métricas de valor para projetos de IA', l7, 'backlog', ARRAY['ferramenta'], '2026-09-30', '2026-09-30', p7+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_ferramenta);

  -- 7.6 Checklist Critérios Aceite GenAI/RAG | ferramenta | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Checklist Critérios Aceite GenAI/RAG', 'Checklist de critérios de aceite para projetos GenAI e RAG', l7, 'backlog', ARRAY['ferramenta'], '2026-09-30', '2026-09-30', p7+6, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_ferramenta);

  -- 7.7 Toolkit v1.0 | ferramenta, gate_b | Sep/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Toolkit v1.0', 'Toolkit completo v1.0 de governança de IA — Gate B', l7, 'backlog', ARRAY['ferramenta','gate_b'], '2026-09-30', '2026-09-30', p7+7, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_ferramenta), (item_id, t_gate_b);

  -- 7.8 Treinamento comunidade + feedbacks | workshop_artifact | Nov/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Treinamento comunidade + feedbacks', 'Treinamento da comunidade com coleta de feedbacks', l7, 'backlog', ARRAY['workshop_artifact'], '2026-11-30', '2026-11-30', p7+8, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_workshop_artifact);

  -- 7.9 Relatório Final | publicacao, report, entrega_final | Dez/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b7, 'Relatório Final', 'Relatório final consolidando framework, toolkit e resultados — entrega final', l7, 'backlog', ARRAY['publicacao','report','entrega_final'], '2026-12-31', '2026-12-31', p7+9, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_report), (item_id, t_entrega_final);

  -- ═══════════════════════════════════════════════════════════════
  -- T8 — Ana Carla Cavalcante (Inclusão & Colaboração) — 6 artifacts
  -- ═══════════════════════════════════════════════════════════════

  -- 8.1 Artigo revisão crítica cérebro neuroatípico | publicacao, artigo_academico | Mai/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b8, 'Artigo revisão crítica cérebro neuroatípico', 'Artigo acadêmico de revisão crítica sobre cérebro neuroatípico e IA', l8, 'backlog', ARRAY['publicacao','artigo_academico'], '2026-05-31', '2026-05-31', p8+1, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_publicacao), (item_id, t_artigo_academico);

  -- 8.2 Protocolo Metodológico Framework | framework | Ago/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b8, 'Protocolo Metodológico Framework', 'Protocolo metodológico para framework de inclusão e neurodiversidade', l8, 'backlog', ARRAY['framework'], '2026-08-31', '2026-08-31', p8+2, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 8.3 Modelo Alinhamento Cognitivo com IA | framework | Nov/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b8, 'Modelo Alinhamento Cognitivo com IA', 'Modelo de alinhamento cognitivo entre perfis neuroatípicos e ferramentas de IA', l8, 'backlog', ARRAY['framework'], '2026-11-30', '2026-11-30', p8+3, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework);

  -- 8.4 Palestra/Webinar explicativo | webinar | Nov/26
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b8, 'Palestra/Webinar explicativo', 'Palestra ou webinar explicativo sobre neurodiversidade e IA em projetos', l8, 'backlog', ARRAY['webinar'], '2026-11-30', '2026-11-30', p8+4, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_webinar);

  -- 8.5 Estudo de Campo Neuro-Advantage | pesquisa | Mar/27
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b8, 'Estudo de Campo Neuro-Advantage', 'Estudo de campo sobre vantagens neuro-cognitivas em ambientes de projeto', l8, 'backlog', ARRAY['pesquisa'], '2027-03-31', '2027-03-31', p8+5, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_pesquisa);

  -- 8.6 Neuro-Advantage Framework 1.0 | framework, entrega_final | Jul/27
  INSERT INTO board_items (board_id, title, description, assignee_id, status, tags, baseline_date, forecast_date, position, cycle)
  VALUES (b8, 'Neuro-Advantage Framework 1.0', 'Framework Neuro-Advantage 1.0 — entrega final da pesquisa multi-ciclo', l8, 'backlog', ARRAY['framework','entrega_final'], '2027-07-31', '2027-07-31', p8+6, 3)
  RETURNING id INTO item_id;
  INSERT INTO board_item_tag_assignments (board_item_id, tag_id) VALUES (item_id, t_framework), (item_id, t_entrega_final);

  RAISE NOTICE 'Loaded 60 tribe artifacts across 8 boards';
END $$;
