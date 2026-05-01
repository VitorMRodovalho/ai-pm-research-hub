-- ============================================================================
-- p87 hotfix — pre_eval_pause email template + Danilo Nascimento status revert
-- ============================================================================
--
-- Trigger: Vice-GP Fabricio Costa reportou via WhatsApp 2026-05-01 09:42 BRT
-- 2 entrevistas marcadas para 2026-05-02 sem que tivesse sido feita análise
-- inicial pela comissão (Vitor + Fabricio). Sweep p87 confirmou:
--   - Thayanne Monteiro: AI fit_for_role=1/5, 0 par-revisões humanas
--   - Danilo Nascimento: AI fit_for_role=3/5, 0 par-revisões, status flipped
--     para interview_pending sem precondições
--   - 0 rows futuras em selection_interviews — Calendar bookings não chegam
--     ao DB (#116)
--
-- Hotfix operacional documenta workflow gate gap. Phase 2 implementation
-- = Issue #117 (RPC precondition + Calendar token-gated + audit log).
-- ADR-0066 Amendment 2026-05-01 captura decisão arquitetural.
--
-- Esta migration é idempotente:
--   - INSERT do template usa ON CONFLICT (slug) DO NOTHING
--   - UPDATE Danilo só toca se status='interview_pending' (já reverted live)
--
-- Rollback: DELETE FROM campaign_templates WHERE slug='pre_eval_pause';
--           (Danilo revert é one-way — não recupera estado pre-hotfix)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Template campaign_templates.pre_eval_pause
--    Email de pausa Calendar booking + opção Card A enrichment
-- ----------------------------------------------------------------------------

INSERT INTO campaign_templates (slug, name, subject, body_html, body_text, target_audience, category, variables)
VALUES (
  'pre_eval_pause',
  'Pré-avaliação pendente — pausar slot Calendar',
  jsonb_build_object(
    'pt', 'Sua candidatura no Núcleo IA & GP — próximos passos',
    'en', 'Your application at Núcleo IA & GP — next steps',
    'es', 'Tu candidatura en el Núcleo IA & GP — próximos pasos'
  ),
  jsonb_build_object(
    'pt', '<p>Olá {{first_name}},</p>' ||
          '<p>Vimos que você reservou um horário para entrevista amanhã. Obrigado pelo interesse no Núcleo IA &amp; GP!{{ack_strengths}}</p>' ||
          '<p>Identificamos um descompasso no nosso processo: a entrevista é a última etapa, e ainda não realizamos a {{review_type}} formal da sua candidatura{{by_committee}}. Vamos pausar o slot agendado e cancelar do nosso lado.</p>' ||
          '<p>{{decision_paragraph}}</p>' ||
          '<p>{{enrichment_paragraph}}</p>' ||
          '<p>Pedimos desculpas pela troca de ordem — a plataforma é nova e estamos aprimorando o fluxo.</p>' ||
          '<p>—<br>Vitor Maia Rodovalho<br>GP do Núcleo IA &amp; GP — PMI Brasil</p>',
    'en', '<p>Hi {{first_name}},</p><p>We saw you booked an interview slot for tomorrow.{{ack_strengths}}</p><p>Process mismatch: the interview is the last step, and we have not completed the formal {{review_type}}{{by_committee}}. We will pause the slot and cancel from our side.</p><p>{{decision_paragraph}}</p><p>{{enrichment_paragraph}}</p><p>—<br>Vitor</p>',
    'es', '<p>Hola {{first_name}},</p><p>Vimos que reservaste un horario.{{ack_strengths}}</p><p>Desajuste de proceso: la entrevista es la última etapa, aún no realizamos la {{review_type}}{{by_committee}}. Pausaremos el slot.</p><p>{{decision_paragraph}}</p><p>{{enrichment_paragraph}}</p><p>—<br>Vitor</p>'
  ),
  jsonb_build_object(
    'pt', 'Olá {{first_name}}, vamos pausar o slot. {{decision_paragraph}} {{enrichment_paragraph}} — Vitor',
    'en', 'Hi {{first_name}}, pausing slot. {{decision_paragraph}} {{enrichment_paragraph}} — Vitor',
    'es', 'Hola {{first_name}}, pausando slot. {{decision_paragraph}} {{enrichment_paragraph}} — Vitor'
  ),
  '{"role":"selection_candidate"}'::jsonb,
  'operational',
  '["first_name","ack_strengths","review_type","by_committee","decision_paragraph","enrichment_paragraph"]'::jsonb
)
ON CONFLICT (slug) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. Danilo Nascimento status revert
--    interview_pending → submitted (sem score, sem par-revisão = não pronto)
--    Idempotente: condição WHERE só toca se ainda for interview_pending
-- ----------------------------------------------------------------------------

UPDATE selection_applications
SET status = 'submitted',
    feedback = COALESCE(feedback || E'\n\n', '') ||
               '[2026-05-01 p87] Status revertido interview_pending → submitted: workflow gap detected (sem par-revisão humana, sem score, Calendar booking sem AI cutoff). Email pre_eval_pause disparado para reagendamento.',
    updated_at = now()
WHERE id = 'd05ddb44-3dea-4d9e-946e-485215122373'
  AND status = 'interview_pending';

-- ----------------------------------------------------------------------------
-- 3. Verification (não-falha — apenas captura no log da migration)
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_template_count int;
  v_danilo_status text;
BEGIN
  SELECT COUNT(*) INTO v_template_count FROM campaign_templates WHERE slug = 'pre_eval_pause';
  SELECT status INTO v_danilo_status FROM selection_applications WHERE id = 'd05ddb44-3dea-4d9e-946e-485215122373';

  RAISE NOTICE 'p87 hotfix migration applied: pre_eval_pause template count=%, Danilo status=%',
    v_template_count, COALESCE(v_danilo_status, 'NOT_FOUND');
END $$;
