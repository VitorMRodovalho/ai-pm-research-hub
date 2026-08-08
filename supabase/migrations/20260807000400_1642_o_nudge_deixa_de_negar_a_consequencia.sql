-- #1642 — o e-mail de nudge afirmava o contrário do que a plataforma fazia.
--
-- O texto de 20260517100000 instruía: "Se já completou ou prefere não dar consentimento de IA,
-- ignore esta mensagem." Enquanto o gate do #1640 esteve vivo, a ausência de consentimento
-- NEGAVA o convite de entrevista. A instrução, portanto, não era apenas incompleta: mandava o
-- candidato ignorar a única mensagem que o levaria à tela onde ele poderia destravar o próprio
-- processo. Art. 18, VIII da LGPD é textualmente sobre isso (informação sobre a possibilidade de
-- não consentir E sobre as consequências da negativa).
--
-- ORDEM: esta correção só pode vir DEPOIS do #1640 estar em produção, e está. Verificado nesta
-- sessão: nenhuma função em `pg_proc` menciona `GATE_NO_AI` (a consulta devolve 0 linhas). Se o
-- gate ainda existisse, este texto novo passaria a mentir na direção inversa, afirmando que não
-- há consequência enquanto ela ainda houvesse.
--
-- O que muda:
--   1. A frase passa a AFIRMAR a ausência de consequência, em vez de silenciar sobre ela.
--   2. "ignore esta mensagem" fica restrito a quem JÁ completou. Antes, a instrução alcançava
--      também quem não queria consentir, e o onboarding tem outras etapas além do consentimento:
--      ignorar o e-mail por causa do consentimento custava as demais.
--
-- Não é DDL: é UPDATE numa linha de `campaign_templates` (dado, não schema). O bloco abaixo
-- verifica o efeito pela contagem de linhas atingidas, não por `FOUND`.

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.campaign_templates SET
    body_html = jsonb_build_object(
      'pt', '<p>Olá <b>{{first_name}}</b>,</p>'
         || '<p>Sua candidatura como <b>{{role_label}}</b> em {{chapter}} foi recebida e segue em avaliação normalmente.</p>'
         || '<p>Ficou pendente apenas o onboarding, que leva cerca de 2 minutos.</p>'
         || '<p><b>O consentimento para análise por IA é opcional, e não concedê-lo não tem efeito sobre o processo seletivo:</b> sua avaliação, seu convite para entrevista e a decisão final acontecem normalmente com ou sem ele.</p>'
         || '<p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Completar onboarding</a></p>'
         || '<p><small>Link válido por {{expires_in_days}} dias. Se você já completou o onboarding, desconsidere esta mensagem.</small></p>'
         || '<p>Equipe GP — Núcleo IA &amp; GP</p>',
      'en', '<p>Hi <b>{{first_name}}</b>,</p>'
         || '<p>Your application as <b>{{role_label}}</b> at {{chapter}} was received and is progressing normally.</p>'
         || '<p>Only the onboarding is still pending, and it takes about 2 minutes.</p>'
         || '<p><b>The AI analysis consent is optional, and not granting it has no effect on the selection process:</b> your evaluation, your interview invitation and the final decision all happen normally with or without it.</p>'
         || '<p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Complete onboarding</a></p>'
         || '<p><small>Link valid for {{expires_in_days}} days. If you have already completed the onboarding, please disregard this message.</small></p>'
         || '<p>GP Team — Núcleo IA &amp; GP</p>',
      'es', '<p>Hola <b>{{first_name}}</b>,</p>'
         || '<p>Su candidatura como <b>{{role_label}}</b> en {{chapter}} fue recibida y sigue en evaluación normalmente.</p>'
         || '<p>Solo quedó pendiente el onboarding, que toma cerca de 2 minutos.</p>'
         || '<p><b>El consentimiento para análisis por IA es opcional, y no concederlo no tiene ningún efecto sobre el proceso de selección:</b> su evaluación, su invitación a la entrevista y la decisión final ocurren normalmente con o sin él.</p>'
         || '<p><a href="{{onboarding_url}}" style="background:#0066cc;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;">Completar onboarding</a></p>'
         || '<p><small>Link válido por {{expires_in_days}} días. Si ya completó el onboarding, desestime este mensaje.</small></p>'
         || '<p>Equipo GP — Núcleo IA &amp; GP</p>'
    ),
    body_text = jsonb_build_object(
      'pt', 'Olá {{first_name}}!' || E'\n\n'
         || 'Sua candidatura como {{role_label}} em {{chapter}} foi recebida e segue em avaliação normalmente. Ficou pendente apenas o onboarding, que leva cerca de 2 minutos.' || E'\n\n'
         || 'O consentimento para análise por IA é opcional, e não concedê-lo não tem efeito sobre o processo seletivo: sua avaliação, seu convite para entrevista e a decisão final acontecem normalmente com ou sem ele.' || E'\n\n'
         || 'Completar onboarding: {{onboarding_url}}' || E'\n\n'
         || 'Link expira em {{expires_in_days}} dias. Se você já completou o onboarding, desconsidere esta mensagem.' || E'\n\n'
         || 'Equipe GP — Núcleo IA & GP',
      'en', 'Hi {{first_name}}!' || E'\n\n'
         || 'Your application as {{role_label}} at {{chapter}} was received and is progressing normally. Only the onboarding is still pending, and it takes about 2 minutes.' || E'\n\n'
         || 'The AI analysis consent is optional, and not granting it has no effect on the selection process: your evaluation, your interview invitation and the final decision all happen normally with or without it.' || E'\n\n'
         || 'Complete onboarding: {{onboarding_url}}' || E'\n\n'
         || 'Link expires in {{expires_in_days}} days. If you have already completed the onboarding, please disregard this message.' || E'\n\n'
         || 'GP Team — Núcleo IA & GP',
      'es', 'Hola {{first_name}}!' || E'\n\n'
         || 'Su candidatura como {{role_label}} en {{chapter}} fue recibida y sigue en evaluación normalmente. Solo quedó pendiente el onboarding, que toma cerca de 2 minutos.' || E'\n\n'
         || 'El consentimiento para análisis por IA es opcional, y no concederlo no tiene ningún efecto sobre el proceso de selección: su evaluación, su invitación a la entrevista y la decisión final ocurren normalmente con o sin él.' || E'\n\n'
         || 'Completar onboarding: {{onboarding_url}}' || E'\n\n'
         || 'Link expira en {{expires_in_days}} días. Si ya completó el onboarding, desestime este mensaje.' || E'\n\n'
         || 'Equipo GP — Núcleo IA & GP'
    ),
    updated_at = now()
  WHERE slug = 'pmi_consent_nudge';

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION '#1642: esperava atingir exatamente 1 linha de pmi_consent_nudge, atingiu %', v_rows;
  END IF;
END $$;
