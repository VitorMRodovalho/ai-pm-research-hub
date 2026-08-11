-- Correcao de referencia. A migration 20260811000816 foi escrita antes de a issue existir e citava
-- "#1727", numero que acabou sendo atribuido a OUTRA issue (a janela do selo em UTC). A issue destas
-- duas RPCs e a #1728. Nada de comportamento muda aqui: COMMENT ON nao toca o corpo da funcao, e o
-- md5 de `prosrc` continua o mesmo de antes desta migration.

COMMENT ON FUNCTION public.mark_member_present(uuid, uuid, boolean) IS
  '#1728: gate escopado ao evento (_can_manage_event), nao resourceless. Ramo de autoatendimento preservado.';
COMMENT ON FUNCTION public.clear_member_attendance(uuid, uuid) IS
  '#1728: gate escopado ao evento (_can_manage_event), nao resourceless. Apaga a linha, inclusive linha selada — por isso o escopo importa.';
