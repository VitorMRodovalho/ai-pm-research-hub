-- #2323 — o detector que conclui passo de onboarding passa a ter quem o acione.
--
-- MEDIDO EM 16/09, e e a razao de existir desta migration:
--
--   * `auto_detect_onboarding_completions()` existe desde sempre e NUNCA teve cron. A consulta
--     `cron.job WHERE command ILIKE '%onboarding%'` devolvia UM job — `detect_onboarding_overdue`,
--     que marca ATRASO e nunca conclusao. O vazio era ausencia real, nao tabela vazia.
--   * Efeito: `start_trail` estava em 18,9% de conclusao (20 de 106) com a ULTIMA conclusao em
--     09/04 — cinco meses. Os outros tres passos que esta mesma funcao cobre estao em 85-90%
--     porque cada um tem trigger PROPRIO (`trg_auto_complete_first_meeting` em attendance,
--     `trg_complete_volunteer_term_on_cert` em certificates, `check_pre_onboarding_auto_steps`
--     para o perfil). `start_trail` e o unico sem trigger: a unica coisa que o conclui e esta
--     funcao batch, e ela nao era chamada por ninguem.
--   * 45 pessoas ja tinham pontos de `trail` lancados com o passo ainda `pending`. Delas, 33
--     tinham a trilha como UNICO pendente do onboarding inteiro — prontas, e o sistema sem saber.
--     (Os dois "45" desta nota sao conjuntos diferentes que coincidem no valor; a intersecao e 33.)
--
-- POR QUE 12:40 UTC, e nao a hora cheia:
--   * 20 minutos ANTES de `detect-onboarding-overdue-daily` (13:00 UTC). A ordem importa: se a
--     conclusao rodasse depois, o detector de atraso marcaria como `overdue` quem acabou de
--     concluir, e o alarme nasceria falso.
--   * Minuto deslocado de proposito (#1844): hora cheia concentra jobs e o pool e compartilhado
--     com trafego real. 12:40 UTC = 09:40 em Sao Paulo.
--
-- POR QUE AGENDAR A FUNCAO DIRETO, sem o wrapper que a #2285 exigiu:
--   A armadilha da #2285 e da #1548 e o gate de SESSAO: sob pg_cron nao ha JWT, `auth.uid()` e
--   NULL, e uma RPC com portao de usuario roda vermelha (ou verde e vazia) em toda execucao.
--   `auto_detect_onboarding_completions` NAO tem gate de sessao — o corpo abre direto no INSERT.
--   A protecao dela ja e o ACL, que e o desenho certo: medido hoje, `proacl` e
--   `postgres=X/postgres | service_role=X/postgres`, ou seja, anon e authenticated JA nao
--   alcancam. Nao ha o que revogar, e um wrapper aqui seria cerimonia sem funcao.
--
-- NAO reescreve o corpo da funcao de proposito: o guard p277-419 (PR11 seal track) afirma o
-- texto do `first_meeting` batch (`FROM attendance a WHERE a.present = true`) contra a migration
-- que a define. Recriar o corpo aqui moveria a captura e daria trabalho a um guard que nao
-- regrediu em nada.
--
-- Cross-ref: #2323, #2285 (o padrao de "detector sem cron"), #1844 (minuto deslocado),
--            #1548 (pg_cron nao tem sessao), p277-419 (o guard do corpo).

SELECT cron.unschedule('onboarding-auto-complete-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'onboarding-auto-complete-daily');

SELECT cron.schedule(
  'onboarding-auto-complete-daily',
  '40 12 * * *',
  $cron$SELECT public.auto_detect_onboarding_completions();$cron$
);
