-- webinar_audience_snapshots: público dos webinars medido na plataforma de transmissão, só agregado
-- (decisão do GP, 14/11/2026).
--
-- A presença da plataforma (attendance) registra só membros do Núcleo. O público externo dos webinars está nos
-- relatórios "master" do Airmeet. Esta tabela guarda os totais por webinar e por exportação, sem nenhum dado
-- pessoal: nem nome, nem e-mail, nem presença por pessoa. Os arquivos brutos, que têm dado pessoal de terceiros,
-- ficam numa pasta do Drive da conta do Núcleo sem compartilhamento; raw_file_ref guarda só o id do arquivo.
--
-- Uma linha por (webinar, fonte, exportação): uma exportação nova vira linha nova, e quem lê pega a mais recente.
-- A carga inicial são as 6 exportações de 14/11/2026, com os números da aba "Event Summary" de cada arquivo.
--
-- Acesso: anon nada; authenticated só lê (é agregado, sem dado pessoal); service_role tudo. A escrita é da
-- orquestradora, por migration ou pela chave de serviço.
--
-- Rollback: DROP TABLE public.webinar_audience_snapshots.

CREATE TABLE public.webinar_audience_snapshots (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webinar_id          uuid NOT NULL REFERENCES public.webinars(id) ON DELETE CASCADE,
  source              text NOT NULL CHECK (source IN ('airmeet')),
  source_event_id     text NOT NULL,
  exported_at         timestamptz NOT NULL,
  registrations       integer NOT NULL CHECK (registrations >= 0),
  attendees           integer NOT NULL CHECK (attendees >= 0),
  attendees_live      integer CHECK (attendees_live >= 0),
  new_registrants     integer CHECK (new_registrants >= 0),
  repeat_registrants  integer CHECK (repeat_registrants >= 0),
  raw_file_ref        text,
  notes               text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid REFERENCES public.members(id),
  UNIQUE (webinar_id, source, exported_at)
);

COMMENT ON TABLE public.webinar_audience_snapshots IS
  'Público dos webinars na plataforma de transmissão (Airmeet), só agregado e sem dado pessoal. Uma linha por exportação; o bruto fica no Drive restrito do Núcleo (raw_file_ref = id do arquivo).';

ALTER TABLE public.webinar_audience_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY was_select_authenticated ON public.webinar_audience_snapshots
  FOR SELECT TO authenticated
  USING (true);

REVOKE ALL ON public.webinar_audience_snapshots FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.webinar_audience_snapshots TO authenticated;
GRANT ALL ON public.webinar_audience_snapshots TO service_role;

-- Carga inicial: exportações de 14/11/2026 (horário do nome do arquivo, UTC). O 04/08 casa pelo link do Airmeet
-- gravado no webinar; os demais pelo título, um webinar por evento.
INSERT INTO public.webinar_audience_snapshots
  (webinar_id, source, source_event_id, exported_at, registrations, attendees, attendees_live,
   new_registrants, repeat_registrants, raw_file_ref, created_by)
VALUES
  ('5f7048a5-e3a7-4a33-97e7-10b018fe6320', 'airmeet', '5f114f50-79ca-11f0-8329-b7f0be3f3d68', '2026-11-14 03:01:00+00', 179, 105,  94, 106,  73, '1znkJhPPc4XW0khgXtIEECsjVSKlDKCLp', '880f736c-3e76-4df4-9375-33575c190305'),
  ('fdc8a319-a6f8-462d-b238-7c55ad7676d1', 'airmeet', '151fa390-c625-11f0-8233-55c1b2dada64', '2026-11-14 02:59:57+00', 215,  93,  90, 133,  82, '1EstjqPwJSLHJntTTGXrFrJxNRtVE3HbD', '880f736c-3e76-4df4-9375-33575c190305'),
  ('67103120-67dd-4720-9410-4289dcdf4bbd', 'airmeet', '8b688020-6914-11f1-afd4-6ba786a688f1', '2026-11-14 02:58:13+00', 289, 137, 130, 152, 137, '182ScGEIvJKhlnMhAXLxpk5PBz1WQY85n', '880f736c-3e76-4df4-9375-33575c190305'),
  ('cf433a4a-629f-4cb0-8aba-0032cc912971', 'airmeet', '825807c0-7f04-11f1-bdcc-3f0a0117d887', '2026-11-14 02:57:17+00', 441, 247, 189, 261, 180, '1_QJOB_x33Yt2do4A6-TxwFibT1lRTyki', '880f736c-3e76-4df4-9375-33575c190305'),
  ('4ff3a888-8959-4262-82e6-a6f54ffc3964', 'airmeet', '8d047420-8895-11f1-8e9b-61808b940348', '2026-11-14 02:56:18+00', 127,  61,  60,  62,  65, '1GidphSAVkGrqUYkwAUOCKUT6m9tT0yJ3', '880f736c-3e76-4df4-9375-33575c190305'),
  ('209660d2-585e-4065-845e-60f037adc16d', 'airmeet', '53199c90-a28a-11f1-8ea1-31fd900afede', '2026-11-14 02:54:20+00', 138,  59,  58,  28, 110, '1HUvuJwe8ptktjzqNJ9cIM-bQTGoEPJ7s', '880f736c-3e76-4df4-9375-33575c190305');

-- Pós-condição: as 6 linhas entraram e cada uma aponta para um webinar realizado.
DO $postcondition$
DECLARE
  v_n int;
  v_bad int;
BEGIN
  SELECT count(*) INTO v_n FROM public.webinar_audience_snapshots;
  SELECT count(*) INTO v_bad FROM public.webinar_audience_snapshots s
    JOIN public.webinars w ON w.id = s.webinar_id WHERE w.status IS DISTINCT FROM 'completed';
  IF v_n <> 6 OR v_bad <> 0 THEN
    RAISE EXCEPTION 'webinar_audience_snapshots: % linhas, % fora de webinar realizado', v_n, v_bad;
  END IF;
END;
$postcondition$;
