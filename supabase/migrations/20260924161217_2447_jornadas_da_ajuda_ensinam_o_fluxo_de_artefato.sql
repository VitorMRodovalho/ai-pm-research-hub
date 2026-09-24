-- ============================================================================
-- #2447 fatia B — as jornadas da Ajuda passam a ensinar o fluxo real de artefato e curadoria
-- ============================================================================
--
-- WHAT: troca 3 passos de help_journeys (dado, nao schema):
--   * tribe_leader.submit_articles  -> artifacts_review (classificar + revisao do lider), /guia-artefatos
--   * researcher.submit_curation    -> publication_flow (peer review -> lider -> curadoria), /guia-artefatos
--   * curator.consensus_review      -> assigned_reviews (pareceres designados por rodizio), /admin/curatorship
-- WHY: medido em 24/09/2026, as jornadas eram de 14/03, anteriores ao peer review e a revisao do lider,
--   e os passos de "submeter para curadoria" de lider e pesquisador apontavam para /publications, o
--   caminho paralelo que nao passa pelo fluxo do card.
-- A troca e por CHAVE do passo, preservando a ordem; os demais passos ficam intactos.
-- ROLLBACK: reaplicar os 3 objetos antigos pela mesma chave (estao na historia do repo e no dump).
-- CROSS-REF: #2447 · #2444 · W130
-- ============================================================================

UPDATE public.help_journeys hj
   SET steps = (
         SELECT jsonb_agg(
                  CASE x.s->>'key'
                    WHEN 'submit_articles' THEN jsonb_build_object(
                      'key', 'artifacts_review',
                      'icon', '📚',
                      'title', jsonb_build_object('pt', 'Classifique artefatos e conduza a revisão',
                                                  'en', 'Classify artifacts and run the review',
                                                  'es', 'Clasifica artefactos y conduce la revisión'),
                      'description', jsonb_build_object(
                        'pt', 'Marque as entregas da tribo como entregável de portfólio, com o tipo certo, e faça a revisão do líder nas publicações antes da curadoria.',
                        'en', 'Mark the team''s deliveries as portfolio deliverables, with the right type, and do the leader review on publications before curation.',
                        'es', 'Marca las entregas de la tribu como entregable de portafolio, con el tipo correcto, y haz la revisión del líder en las publicaciones antes de la curaduría.'),
                      'why', jsonb_build_object(
                        'pt', 'É a classificação que faz a entrega aparecer no portfólio, e só publicações seguem para a curadoria.',
                        'en', 'Classification is what makes the delivery show up in the portfolio, and only publications go on to curation.',
                        'es', 'La clasificación es lo que hace que la entrega aparezca en el portafolio, y solo las publicaciones siguen a la curaduría.'),
                      'action_url', '/guia-artefatos',
                      'action_label', jsonb_build_object('pt', 'Ver o guia', 'en', 'See the guide', 'es', 'Ver la guía'),
                      'is_required', true,
                      'estimated_minutes', 10)
                    WHEN 'submit_curation' THEN jsonb_build_object(
                      'key', 'publication_flow',
                      'icon', '📚',
                      'title', jsonb_build_object('pt', 'Leve sua publicação à curadoria',
                                                  'en', 'Take your publication to curation',
                                                  'es', 'Lleva tu publicación a la curaduría'),
                      'description', jsonb_build_object(
                        'pt', 'Com o card classificado como publicação pelo líder, faça o peer review com a tribo; depois vêm a revisão do líder e a curadoria, com 2 pareceristas designados.',
                        'en', 'Once the leader classifies the card as a publication, do the peer review with the team; then come the leader review and curation, with 2 assigned reviewers.',
                        'es', 'Con la tarjeta clasificada como publicación por el líder, haz la revisión de pares con la tribu; luego vienen la revisión del líder y la curaduría, con 2 revisores designados.'),
                      'why', jsonb_build_object(
                        'pt', 'É o caminho para a sua publicação sair com o selo do Núcleo.',
                        'en', 'It is the path for your publication to be released with the Núcleo seal.',
                        'es', 'Es el camino para que tu publicación salga con el sello del Núcleo.'),
                      'action_url', '/guia-artefatos',
                      'action_label', jsonb_build_object('pt', 'Ver o guia', 'en', 'See the guide', 'es', 'Ver la guía'),
                      'is_required', false,
                      'estimated_minutes', 10)
                    WHEN 'consensus_review' THEN jsonb_build_object(
                      'key', 'assigned_reviews',
                      'icon', '🗂️',
                      'title', jsonb_build_object('pt', 'Responda aos pareceres designados a você',
                                                  'en', 'Answer the reviews assigned to you',
                                                  'es', 'Responde a los pareceres designados a ti'),
                      'description', jsonb_build_object(
                        'pt', 'Cada peça recebe 2 pareceristas por rodízio, com prazo de 7 dias e lembrete 2 dias antes. Se o prazo vencer, outro curador pode ser designado.',
                        'en', 'Each piece gets 2 reviewers by rotation, with a 7-day deadline and a reminder 2 days before. If the deadline passes, another curator may be assigned.',
                        'es', 'Cada pieza recibe 2 revisores por rotación, con plazo de 7 días y recordatorio 2 días antes. Si vence el plazo, se puede designar a otro curador.'),
                      'why', jsonb_build_object(
                        'pt', 'O parecer tem dono: é o que evita que uma peça fique parada na fila.',
                        'en', 'Each review has an owner: that is what keeps a piece from stalling in the queue.',
                        'es', 'El parecer tiene dueño: es lo que evita que una pieza quede parada en la cola.'),
                      'action_url', '/admin/curatorship',
                      'action_label', jsonb_build_object('pt', 'Ir para Curadoria', 'en', 'Go to Curation', 'es', 'Ir a Curaduría'),
                      'is_required', true,
                      'estimated_minutes', 15)
                    ELSE x.s
                  END
                  ORDER BY x.ord)
           FROM jsonb_array_elements(hj.steps) WITH ORDINALITY AS x(s, ord)
       ),
       updated_at = now()
 WHERE hj.persona_key IN ('tribe_leader', 'researcher', 'curator');
