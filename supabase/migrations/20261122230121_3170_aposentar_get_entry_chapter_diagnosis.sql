-- #3170: aposenta get_entry_chapter_diagnosis, que ficou sem chamador.
-- A ultima leitora era o nudge_entry_chapter_cohort antigo, e a #3110 (20261120204018) trocou
-- essa leitura. O classificador classify_entry_chapter continua: approve_selection_application
-- o chama. Sem CASCADE: se algo depender da funcao, o DROP falha em vez de levar junto.
DROP FUNCTION public.get_entry_chapter_diagnosis(uuid);
