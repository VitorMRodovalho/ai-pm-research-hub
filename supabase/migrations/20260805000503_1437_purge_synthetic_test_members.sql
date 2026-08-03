-- #1437 pendente 1 — purga das linhas sintéticas de teste que viviam em members.
--
-- CRITÉRIO: e-mail em domínio reservado por RFC 2606 / RFC 6761. É o mesmo critério do gate de
-- envio (#1563) e do guard 1437-synthetic-member-never-reachable. Verificado contra os 131 membros
-- antes de rodar: casa com exatamente as 10 linhas sintéticas e NENHUM membro legítimo.
--
-- POR QUE APAGAR O LOG DE ACESSO A PII (decisão do owner, 2026-08-03):
-- `pii_access_log` existe para provar quem acessou dado pessoal DE QUEM. Não há pessoa por trás
-- dessas linhas: o alvo é uma entidade fictícia criada por tests/contracts/member_emails.test.mjs.
-- Sem titular não há dado pessoal, não há direito de acesso a documentar, e manter o registro não
-- serve a nenhuma finalidade da LGPD — apenas polui a trilha real.
--
-- `target_member_id` É nullable, então orfanar em vez de apagar era possível. Foi descartado de
-- propósito: 633 linhas dizendo "acessou campos de <alvo desconhecido>" são indistinguíveis de
-- anonimização de dado REAL, e um auditor futuro não teria como separar as duas coisas. Apagar com
-- este registro é mais honesto que deixar ambiguidade permanente na trilha.
--
-- NÃO se apaga o registro do envio de 02/08: o destinatário sintético da campanha
-- `webinar-t6-04ago-membros` é convertido em contato externo (member_id NULL, e-mail preservado),
-- porque aquela campanha REALMENTE teve 89 destinatários e reescrever isso seria falsear o histórico.
--
-- Aplicada em 2026-08-03. Antes -> depois medidos: members 131 -> 121; pii_access_log 26395 ->
-- 25762 (633 linhas); v_operational_members 69 -> 69 (inalterado); destinatários da campanha de
-- 02/08 89 -> 89 (1 convertido para externo); check_schema_invariants() 0 violações.

DO $$
DECLARE
  c_reserved constant text := '@([^@]*\.)?(example\.(com|org|net)|test|invalid|localhost)$';
  v_alvo int;
  v_legitimos int;
  v_pii int;
  v_notif int;
BEGIN
  SELECT count(*) INTO v_alvo FROM public.members WHERE email ~* c_reserved;
  SELECT count(*) INTO v_legitimos
    FROM public.members WHERE email ~* c_reserved AND name NOT ILIKE '%\_\_205\_synthetic\_\_%';

  -- Recusa-se a rodar se o alvo não for exatamente o esperado. Uma purga que erra o conjunto é
  -- pior que uma purga que não acontece.
  IF v_alvo <> 10 THEN
    RAISE EXCEPTION 'Abortado: esperava 10 linhas de dominio reservado, encontrei %', v_alvo;
  END IF;
  IF v_legitimos <> 0 THEN
    RAISE EXCEPTION 'Abortado: % linha(s) de dominio reservado NAO sao sinteticas', v_legitimos;
  END IF;

  -- 1. Preserva a verdade do envio de 02/08 convertendo o destinatario em externo.
  UPDATE public.campaign_recipients cr
     SET external_email = m.email, external_name = m.name, member_id = NULL
    FROM public.members m
   WHERE cr.member_id = m.id AND m.email ~* c_reserved;

  -- 2. notifications.recipient_id e NOT NULL, entao a linha nao pode ser orfanada.
  DELETE FROM public.notifications
   WHERE recipient_id IN (SELECT id FROM public.members WHERE email ~* c_reserved);
  UPDATE public.notifications SET actor_id = NULL
   WHERE actor_id IN (SELECT id FROM public.members WHERE email ~* c_reserved);

  -- 3. Log de acesso a PII de entidade sem titular.
  SELECT count(*) INTO v_pii FROM public.pii_access_log
   WHERE target_member_id IN (SELECT id FROM public.members WHERE email ~* c_reserved);
  DELETE FROM public.pii_access_log
   WHERE target_member_id IN (SELECT id FROM public.members WHERE email ~* c_reserved);
  UPDATE public.pii_access_log SET accessor_id = NULL
   WHERE accessor_id IN (SELECT id FROM public.members WHERE email ~* c_reserved);

  -- 4. As linhas. member_emails / member_offboarding_records / preview_gate_eligibles_cache saem
  --    por CASCADE; drive_teardown_scans vira SET NULL.
  DELETE FROM public.members WHERE email ~* c_reserved;

  SELECT count(*) INTO v_notif FROM public.members WHERE email ~* c_reserved;
  IF v_notif <> 0 THEN
    RAISE EXCEPTION 'Abortado: % linha(s) sobreviveram ao DELETE', v_notif;
  END IF;

  RAISE NOTICE 'Purga #1437: 10 membros sinteticos removidos, % linhas de pii_access_log apagadas', v_pii;
END $$;
