-- #1099 + #1094 — on-ramp "conteúdo → fila → rede" para comms_scheduled_posts.
--
-- Contexto: a fila multi-canal (mig 271/277) e os publishers (publish-instagram,
-- publish-linkedin) existem e funcionam, mas NENHUMA superfície escrevia na fila
-- (os 27 rows Instagram foram INSERTs manuais de sessão; LinkedIn = 0 rows ever,
-- o bug #1094). Este migration cria o trio canônico de RPCs que o MCP (e futura
-- UI admin) envolvem: schedule_comms_post / cancel_scheduled_comms_post /
-- list_scheduled_comms_posts. Gate = can_manage_comms_metrics() (o MESMO gate
-- function-anchored das policies RLS da tabela — mig 271), fail-closed.
--
-- Também: (a) idea_id opcional liga o row à publication_idea (proveniência do
-- pipeline editorial; fecha o gap V1 Opção B do fork_idea_to_channel, que só
-- gravava brief); (b) media_type CHECK ganha DOCUMENT (post de documento/carrossel
-- nativo do LinkedIn — o publisher ganha o upload em /rest/documents no mesmo PR)
-- e perde LINK (nunca implementado em publish-linkedin, 0 rows vivos — enfileirar
-- LINK produzia um row destinado a falhar no publish); (c) o bucket comms-media
-- aceita application/pdf (o publisher busca os bytes do documento por URL pública).
--
-- Rollback (não trivial — documentado por completude): DROP dos 3 RPCs; DROP COLUMN
-- idea_id (perde proveniência); restaurar o CHECK da mig 277 exige antes migrar/apagar
-- quaisquer rows DOCUMENT vivos na fila (violariam o CHECK antigo); reverter o array
-- de MIME do bucket. Preferir roll-forward.

begin;

-- 1) proveniência editorial: fila ← publication_ideas (opcional)
alter table public.comms_scheduled_posts
  add column if not exists idea_id uuid references public.publication_ideas(id) on delete set null;

comment on column public.comms_scheduled_posts.idea_id is
  'Optional provenance link to the publication_ideas pipeline row this post came from (#1099).';

-- 2) media_type: + DOCUMENT (LinkedIn document post), - LINK (never implemented; 0 rows)
alter table public.comms_scheduled_posts
  drop constraint if exists comms_scheduled_posts_media_type_check;

alter table public.comms_scheduled_posts
  add constraint comms_scheduled_posts_media_type_check
  check (media_type in (
    'IMAGE', 'CAROUSEL', 'REELS', 'STORIES',          -- Instagram
    'TEXT', 'VIDEO', 'ARTICLE', 'DOCUMENT'            -- LinkedIn (organization share)
  ));

-- 3) comms-media bucket: PDF permitido (fonte dos bytes de DOCUMENT via URL pública)
update storage.buckets
  set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'application/pdf']
  where id = 'comms-media';

-- 4) schedule_comms_post — o on-ramp. Valida canal × media_type × payload ANTES de
--    enfileirar (espelha os requisitos dos publishers, para o erro aparecer na hora
--    do agendamento e não silenciosamente no drain 3 tentativas depois).
create or replace function public.schedule_comms_post(
  p_channel text,
  p_media_type text,
  p_payload jsonb,
  p_scheduled_at timestamptz,
  p_label text default null,
  p_idea_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
AS $$
declare
  v_row public.comms_scheduled_posts%rowtype;
  v_idea public.publication_ideas%rowtype;
  v_children jsonb;
  v_child jsonb;
  v_n int;
  v_caption_limit int;
  v_caption text;
  -- canal → media_types que o publisher correspondente implementa hoje.
  -- Espelho de: publish-instagram (IMAGE/CAROUSEL/REELS/STORIES) e
  -- publish-linkedin (TEXT/IMAGE/VIDEO/ARTICLE/DOCUMENT). Se um publisher
  -- ganhar um tipo, atualizar aqui + o CHECK acima (contract test 1099 pina).
  v_channel_types jsonb := jsonb_build_object(
    'instagram', jsonb_build_array('IMAGE', 'CAROUSEL', 'REELS', 'STORIES'),
    'linkedin',  jsonb_build_array('TEXT', 'IMAGE', 'VIDEO', 'ARTICLE', 'DOCUMENT')
  );
begin
  if not public.can_manage_comms_metrics() then
    raise exception 'Unauthorized: manage_comms required';
  end if;

  if p_channel is null or not (v_channel_types ? p_channel) then
    raise exception 'unknown channel ''%'' (expected: instagram | linkedin)', coalesce(p_channel, '<null>');
  end if;

  if p_media_type is null or not (v_channel_types -> p_channel) ? p_media_type then
    raise exception 'media_type ''%'' not supported on channel ''%'' (allowed: %)',
      coalesce(p_media_type, '<null>'), p_channel, (v_channel_types -> p_channel);
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a jsonb object (the publish-% body)', p_channel;
  end if;

  -- coerência fila→publisher: o drain repassa o payload CRU ao publisher, e o
  -- discriminador que o publisher lê (post_type no LinkedIn — default TEXT!;
  -- media_type no Instagram — default IMAGE) NÃO é a coluna media_type do row.
  -- Sem isto, um row DOCUMENT com payload sem post_type publicaria como TEXT.
  if p_channel = 'linkedin' then
    if p_payload ? 'post_type' and p_payload ->> 'post_type' <> p_media_type then
      raise exception 'payload.post_type (''%'') must match media_type (''%'')', p_payload ->> 'post_type', p_media_type;
    end if;
    p_payload := jsonb_set(p_payload, '{post_type}', to_jsonb(p_media_type));
  else
    if p_payload ? 'media_type' and p_payload ->> 'media_type' <> p_media_type then
      raise exception 'payload.media_type (''%'') must match media_type (''%'')', p_payload ->> 'media_type', p_media_type;
    end if;
    p_payload := jsonb_set(p_payload, '{media_type}', to_jsonb(p_media_type));
  end if;

  if p_scheduled_at is null then
    raise exception 'scheduled_at is required';
  end if;
  if p_scheduled_at < now() - interval '1 minute' then
    raise exception 'scheduled_at must be now or in the future (got %)', p_scheduled_at;
  end if;
  if p_scheduled_at > now() + interval '1 year' then
    raise exception 'scheduled_at more than 1 year out — provavelmente um typo (got %)', p_scheduled_at;
  end if;

  -- validação payload × media_type (espelha o que o publisher exige na hora do publish)
  if p_media_type = 'IMAGE' and coalesce(p_payload ->> 'image_url', '') = '' then
    raise exception 'IMAGE requires payload.image_url';
  end if;
  if p_media_type = 'REELS' and coalesce(p_payload ->> 'video_url', '') = '' then
    raise exception 'REELS requires payload.video_url';
  end if;
  if p_media_type = 'VIDEO' and coalesce(p_payload ->> 'video_url', '') = '' then
    raise exception 'VIDEO requires payload.video_url';
  end if;
  if p_media_type = 'STORIES'
     and coalesce(p_payload ->> 'image_url', '') = ''
     and coalesce(p_payload ->> 'video_url', '') = '' then
    raise exception 'STORIES requires payload.image_url or payload.video_url';
  end if;
  if p_media_type = 'TEXT' and coalesce(p_payload ->> 'text', '') = '' then
    raise exception 'TEXT requires payload.text';
  end if;
  if p_media_type = 'ARTICLE' and coalesce(p_payload ->> 'article_url', '') = '' then
    raise exception 'ARTICLE requires payload.article_url';
  end if;
  if p_media_type = 'DOCUMENT' then
    if coalesce(p_payload ->> 'document_url', '') = '' then
      raise exception 'DOCUMENT requires payload.document_url (public PDF URL)';
    end if;
    if coalesce(p_payload ->> 'title', '') = '' then
      raise exception 'DOCUMENT requires payload.title (LinkedIn renders it on the card)';
    end if;
  end if;
  if p_media_type = 'CAROUSEL' then
    v_children := p_payload -> 'children';
    if v_children is null or jsonb_typeof(v_children) <> 'array' then
      raise exception 'CAROUSEL requires payload.children (array of {image_url|video_url})';
    end if;
    v_n := jsonb_array_length(v_children);
    if v_n < 2 or v_n > 10 then
      raise exception 'CAROUSEL requires 2-10 children (got %)', v_n;
    end if;
    for v_child in select * from jsonb_array_elements(v_children) loop
      if coalesce(v_child ->> 'image_url', '') = '' and coalesce(v_child ->> 'video_url', '') = '' then
        raise exception 'each CAROUSEL child needs image_url or video_url';
      end if;
    end loop;
  end if;

  -- limites de texto por canal (IG caption 2200; LinkedIn commentary 3000)
  v_caption := coalesce(p_payload ->> 'caption', p_payload ->> 'text');
  v_caption_limit := case p_channel when 'instagram' then 2200 else 3000 end;
  if v_caption is not null and length(v_caption) > v_caption_limit then
    raise exception '% text/caption exceeds the channel limit of % chars (got %)',
      p_channel, v_caption_limit, length(v_caption);
  end if;

  -- proveniência editorial: só ideas aprovadas/publicadas viram post agendado
  if p_idea_id is not null then
    select * into v_idea from public.publication_ideas where id = p_idea_id;
    if v_idea.id is null then
      raise exception 'Idea not found: %', p_idea_id;
    end if;
    if v_idea.stage not in ('approved', 'published') then
      raise exception 'Idea % is at stage ''%'' — only approved/published ideas can be scheduled', p_idea_id, v_idea.stage;
    end if;
  end if;

  insert into public.comms_scheduled_posts (channel, media_type, payload, scheduled_at, label, idea_id)
  values (p_channel, p_media_type, p_payload, p_scheduled_at, nullif(trim(coalesce(p_label, '')), ''), p_idea_id)
  returning * into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'channel', v_row.channel,
    'media_type', v_row.media_type,
    'scheduled_at', v_row.scheduled_at,
    'status', v_row.status,
    'label', v_row.label,
    'idea_id', v_row.idea_id
  );
end;
$$;

revoke all on function public.schedule_comms_post(text, text, jsonb, timestamptz, text, uuid) from public, anon;
grant execute on function public.schedule_comms_post(text, text, jsonb, timestamptz, text, uuid) to authenticated;

comment on function public.schedule_comms_post(text, text, jsonb, timestamptz, text, uuid) is
  '#1099 on-ramp: valida e enfileira um post datado em comms_scheduled_posts (drain = publish-scheduled cron). Gate: can_manage_comms_metrics().';

-- 5) cancel_scheduled_comms_post — undo do agendamento (só pending; publicação já
--    disparada não é des-publicável daqui).
create or replace function public.cancel_scheduled_comms_post(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
AS $$
declare
  v_row public.comms_scheduled_posts%rowtype;
begin
  if not public.can_manage_comms_metrics() then
    raise exception 'Unauthorized: manage_comms required';
  end if;

  update public.comms_scheduled_posts
     set status = 'canceled'
   where id = p_id
     and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'No pending scheduled post with id % (already published/failed/canceled, or not found)', p_id;
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'channel', v_row.channel,
    'media_type', v_row.media_type,
    'label', v_row.label,
    'status', v_row.status
  );
end;
$$;

revoke all on function public.cancel_scheduled_comms_post(uuid) from public, anon;
grant execute on function public.cancel_scheduled_comms_post(uuid) to authenticated;

comment on function public.cancel_scheduled_comms_post(uuid) is
  '#1099: cancela um post agendado ainda pending (pending → canceled). Gate: can_manage_comms_metrics().';

-- 6) list_scheduled_comms_posts — visibilidade da fila (MCP/ops) sem expor payload
--    inteiro por default (o payload pode ser grande; include_payload=true o inclui).
create or replace function public.list_scheduled_comms_posts(
  p_channel text default null,
  p_status text default null,
  p_limit int default 50,
  p_include_payload boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
AS $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_items jsonb;
begin
  if not public.can_manage_comms_metrics() then
    raise exception 'Unauthorized: manage_comms required';
  end if;

  if p_status is not null
     and p_status not in ('pending', 'publishing', 'published', 'failed', 'canceled') then
    raise exception 'unknown status ''%''', p_status;
  end if;

  select coalesce(jsonb_agg(item order by ((item ->> 'scheduled_at'))::timestamptz desc), '[]'::jsonb)
    into v_items
    from (
      select jsonb_build_object(
               'id', q.id,
               'channel', q.channel,
               'media_type', q.media_type,
               'label', q.label,
               'status', q.status,
               'scheduled_at', q.scheduled_at,
               'published_at', q.published_at,
               'attempts', q.attempts,
               'error', q.error,
               'permalink', q.permalink,
               'idea_id', q.idea_id
             )
             || case when p_include_payload then jsonb_build_object('payload', q.payload) else '{}'::jsonb end
             as item
        from public.comms_scheduled_posts q
       where (p_channel is null or q.channel = p_channel)
         and (p_status is null or q.status = p_status)
       order by q.scheduled_at desc
       limit v_limit
    ) sub;

  return jsonb_build_object('items', v_items, 'count', jsonb_array_length(v_items));
end;
$$;

revoke all on function public.list_scheduled_comms_posts(text, text, int, boolean) from public, anon;
grant execute on function public.list_scheduled_comms_posts(text, text, int, boolean) to authenticated;

comment on function public.list_scheduled_comms_posts(text, text, int, boolean) is
  '#1099: lista a fila comms_scheduled_posts (filtros channel/status, payload opcional). Gate: can_manage_comms_metrics().';

commit;
