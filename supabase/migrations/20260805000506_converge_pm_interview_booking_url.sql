-- Converge a interview_booking_url do PM entre `members` e `selection_committee`.
--
-- Contexto (auditoria da jornada do candidato, 2026-08-03, Achado F):
-- o PM tinha DOIS links cadastrados, `q9urWE15HYZRNymd7` em members (seed do p253/#357) e
-- `MHAmfkgZCwT9KsoKA` em selection_committee do cycle4-2026. Uma versão preliminar da auditoria
-- reportou isso como divergência funcional e como causa do sintoma "às vezes o agendamento sai por
-- uma agenda, às vezes por outra".
--
-- Isso estava ERRADO e foi corrigido: `calendar.app.google/...` é encurtador de
-- `calendar.google.com/appointments/schedules/...`, e os DOIS links resolvem para o MESMO schedule
-- (`AcZssZ23xtPliqd0KjfA1YXt6App_jMFJ-OYN1hYv2GfVc99YfbOYL_9lowvZqerqrxGHDdzBoekTPHr`, verificado
-- pelo Location do redirect em 2026-08-03). Nenhum candidato jamais chegou a página diferente por
-- causa disso.
--
-- Esta migration é portanto HIGIENE, não correção de bug: elimina a segunda representação do mesmo
-- recurso, para que as duas colunas concordem e futuras auditorias não voltem a ler duas strings
-- como dois destinos. Comportamento de roteamento: inalterado.
--
-- A forma vigente (`MHAmfkgZCwT9KsoKA`) foi declarada pelo PM em 2026-08-03 e já era a que saía nos
-- despachos reais desde 2026-06-17 (`selection_dispatch_url_log`, path `committee_override`).
--
-- Idempotente: o WHERE casa apenas o valor antigo.

UPDATE public.members
SET interview_booking_url = 'https://calendar.app.google/MHAmfkgZCwT9KsoKA',
    updated_at = now()
WHERE id = '880f736c-3e76-4df4-9375-33575c190305'
  AND interview_booking_url = 'https://calendar.app.google/q9urWE15HYZRNymd7';
