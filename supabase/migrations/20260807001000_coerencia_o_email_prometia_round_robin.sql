-- Coerência do convite de avaliação: o e-mail prometia um modelo que a plataforma não tem.
--
-- O DESCOMPASSO, MEDIDO EM 07/08/2026
-- `peer_review_request` dizia, nas 3 línguas: *"Você foi escolhido(a) (round-robin) para avaliar a
-- candidatura de X"*. Isso descreve atribuição individual.
--
-- `get_my_pending_evaluations` implementa outra coisa: escolhe o ciclo em `phase='evaluating'`,
-- confere participação no comitê e devolve **todos** os candidatos não-terminais que a pessoa
-- ainda não submeteu. Não há tabela de atribuição, não há round-robin, não há dono. Hoje isso são
-- 20 candidatos avaliáveis, e os mesmos 20 aparecem para todo o comitê.
--
-- Ou seja: o e-mail prometia dono e a tela entregava fila. Quem recebia podia concluir que só ele
-- avaliaria aquele candidato — ou o contrário, ignorar por achar que "não era o dele".
--
-- A DECISÃO (PM, 07/08/2026): a FILA COMPARTILHADA é o modelo. É o que a plataforma faz, é o que
-- produziu as 455 avaliações do ciclo, e é coerente com "mínimo de 2 avaliadores por candidato":
-- quem pega, pega. O texto é que muda.
--
-- TRÊS AFIRMAÇÕES SAEM, e todas eram falsas de formas diferentes:
--
--   1. "escolhido (round-robin)" — descreve mecanismo inexistente.
--
--   2. "Pré-análise IA concluída" — INCONDICIONAL, e o template não tem variável de IA nenhuma
--      (as 5 declaradas são first_name, applicant_name, chapter, role_applied, eval_url). A
--      análise depende de consentimento opcional: das avaliações já registradas na base, a MAIORIA
--      é sobre candidatura sem análise. O avaliador era informado de um artefato que muitas vezes
--      não existe. Sai por completo: a tela mostra a sugestão quando ela existe, e é lá que essa
--      informação pertence.
--
--   3. "outro avaliador será designado" — pressupõe atribuição de novo. Numa fila compartilhada,
--      quem não pode avaliar simplesmente não pega; o candidato continua disponível para os demais.
--
-- Nada aqui muda autoridade: o convite é comunicação. Quem pode avaliar continua sendo decidido
-- por `submit_evaluation`, que na migration 20260807000900 passou a recusar observador.
--
-- Não é DDL: é UPDATE numa linha de `campaign_templates`. O bloco verifica o efeito pela contagem
-- de linhas atingidas, não por `FOUND`.
--
-- Refs #1591, #1643

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.campaign_templates SET
    body_html = jsonb_build_object(
      'pt', '<p>Olá {{peer_first_name}},</p>'
         || '<p>A candidatura de <strong>{{applicant_name}}</strong> ({{chapter}}, vaga de {{role_applied}}) está na fila de avaliação do comitê.</p>'
         || '<p>A fila é <strong>compartilhada</strong>: qualquer avaliador do comitê pode assumir esta candidatura. Esperamos 2 avaliações por candidato.</p>'
         || '<p><a href="{{eval_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Avaliar candidato</a></p>'
         || '<p style="color:#666;font-size:13px;">Se você não puder avaliar (conflito de interesse, indisponibilidade), não precisa responder: a candidatura segue na fila para os demais avaliadores.</p>'
         || '<p>Obrigado!<br/>Núcleo IA &amp; GP — Comitê de Seleção</p>',
      'en', '<p>Hello {{peer_first_name}},</p>'
         || '<p><strong>{{applicant_name}}</strong>''s application ({{chapter}}, role: {{role_applied}}) is in the committee''s review queue.</p>'
         || '<p>The queue is <strong>shared</strong>: any committee evaluator can take this application. We expect 2 evaluations per candidate.</p>'
         || '<p><a href="{{eval_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Review candidate</a></p>'
         || '<p style="color:#666;font-size:13px;">If you cannot review it (conflict of interest, unavailability), no reply is needed: the application stays in the queue for the other evaluators.</p>'
         || '<p>Thank you!<br/>Núcleo IA &amp; GP — Selection Committee</p>',
      'es', '<p>Hola {{peer_first_name}},</p>'
         || '<p>La candidatura de <strong>{{applicant_name}}</strong> ({{chapter}}, rol de {{role_applied}}) está en la fila de evaluación del comité.</p>'
         || '<p>La fila es <strong>compartida</strong>: cualquier evaluador del comité puede tomar esta candidatura. Esperamos 2 evaluaciones por candidato.</p>'
         || '<p><a href="{{eval_url}}" style="background:#0066cc;color:#fff;padding:10px 20px;text-decoration:none;border-radius:4px;">Evaluar candidato</a></p>'
         || '<p style="color:#666;font-size:13px;">Si no puede evaluarla (conflicto de interés, indisponibilidad), no hace falta responder: la candidatura sigue en la fila para los demás evaluadores.</p>'
         || '<p>¡Gracias!<br/>Núcleo IA &amp; GP — Comité de Selección</p>'
    ),
    body_text = jsonb_build_object(
      'pt', 'Olá {{peer_first_name}},' || E'\n\n'
         || 'A candidatura de {{applicant_name}} ({{chapter}}, vaga de {{role_applied}}) está na fila de avaliação do comitê.' || E'\n\n'
         || 'A fila é compartilhada: qualquer avaliador do comitê pode assumir. Esperamos 2 avaliações por candidato.' || E'\n\n'
         || 'Avaliar: {{eval_url}}' || E'\n\n'
         || 'Se você não puder avaliar, não precisa responder: a candidatura segue na fila para os demais.' || E'\n\n'
         || 'Núcleo IA & GP — Comitê de Seleção',
      'en', 'Hello {{peer_first_name}},' || E'\n\n'
         || '{{applicant_name}}''s application ({{chapter}}, role: {{role_applied}}) is in the committee''s review queue.' || E'\n\n'
         || 'The queue is shared: any committee evaluator can take it. We expect 2 evaluations per candidate.' || E'\n\n'
         || 'Review: {{eval_url}}' || E'\n\n'
         || 'If you cannot review it, no reply is needed: it stays in the queue for the others.' || E'\n\n'
         || 'Núcleo IA & GP — Selection Committee',
      'es', 'Hola {{peer_first_name}},' || E'\n\n'
         || 'La candidatura de {{applicant_name}} ({{chapter}}, rol de {{role_applied}}) está en la fila de evaluación del comité.' || E'\n\n'
         || 'La fila es compartida: cualquier evaluador del comité puede tomarla. Esperamos 2 evaluaciones por candidato.' || E'\n\n'
         || 'Evaluar: {{eval_url}}' || E'\n\n'
         || 'Si no puede evaluarla, no hace falta responder: sigue en la fila para los demás.' || E'\n\n'
         || 'Núcleo IA & GP — Comité de Selección'
    ),
    updated_at = now()
  WHERE slug = 'peer_review_request';

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'esperava atingir exatamente 1 linha de peer_review_request, atingiu %', v_rows;
  END IF;
END $$;
