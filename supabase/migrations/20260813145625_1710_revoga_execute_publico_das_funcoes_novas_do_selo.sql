-- #1710 — `CREATE FUNCTION` concede EXECUTE a PUBLIC por padrao, e foi o que aconteceu com as duas
-- funcoes criadas nesta onda. Medido logo apos aplicar: `unseal_event_attendance` (SECURITY
-- DEFINER, que APAGA linhas de presenca) estava alcancavel por `anon`, enquanto as irmas
-- (`seal_event_attendance`, `preview_seal_attendance`, `mark_member_present`) so tem
-- authenticated + service_role.
--
-- O primeiro portao da funcao ja recusa quem nao tem `auth.uid()`, entao nao houve exposicao de
-- dado; o que se corrige aqui e a superficie: uma RPC de escrita publicada para anon depende de o
-- gate interno nunca falhar. E a classe do #1592 ("falta barreira contra DDL nova").

REVOKE EXECUTE ON FUNCTION public.unseal_event_attendance(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._roster_seal_marker() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.unseal_event_attendance(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._roster_seal_marker() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
