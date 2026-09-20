-- #1571, correcao imediata: o DROP + CREATE da migration anterior REINTRODUZIU
-- `EXECUTE` para PUBLIC (e portanto para anon), porque `CREATE FUNCTION` nasce com
-- esse grant por padrao. Medido antes do DROP, a funcao tinha apenas
-- authenticated + service_role + postgres, e os GRANT explicitos que escrevi
-- restauraram esses, mas nao removeram o default que veio de graca.
--
-- Isto e alargamento de privilegio que a migration anterior causou, nao um estado
-- herdado. A funcao e SECURITY DEFINER com portao interno (`can_by_member`), entao
-- anon seria recusado, mas a superficie exposta nao volta a ser o que era sem este
-- REVOKE, e superficie e o que se audita.
REVOKE EXECUTE ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.offboard_member_with_handoffs(uuid, text, text, text, jsonb, date, date) FROM anon;
