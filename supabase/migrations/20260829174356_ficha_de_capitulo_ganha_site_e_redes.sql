-- A ficha do capitulo passa a guardar site e redes, com procedencia.
--
-- Por que existe. Para marcar tres capitulos num post de webinar em 29/08/2026 foram gastas
-- quatro buscas na web, e UMA DELAS teria saido errada por deducao: `@pmiam` e o Facebook do
-- PMI Amazonia, e o Instagram e `@pmiamoficial`. Isso e fato sobre o CAPITULO, nao sobre o
-- evento, e estava sendo redescoberto a cada campanha. Marcar a conta errada num post publico
-- e um erro que nao da para desfazer depois de publicado.
--
-- Onde. `chapter_registry` ja e a SSOT dos 15 capitulos do Brasil (lida pelo worker de VEP
-- sync, pela fila de afiliacao do admin e pelo TeamSection) e ja carrega `logo_url`, entao a
-- ficha ja existia e so nao tinha estes campos. A tabela tambem ja demonstra o padrao de
-- preenchimento incremental que estes campos vao seguir: medido em 29/08, 9 dos 15 capitulos
-- estao sem logo, e isso nunca impediu os outros 6 de terem.
--
-- ── Por que a arroba e GERADA, e nao uma coluna a mais ───────────────────────────────────
-- O que a copy precisa para marcar e a arroba; o que identifica sem ambiguidade e a URL.
-- Guardar as duas lado a lado seria convidar a divergencia, e divergencia entre duas copias
-- da mesma informacao ja custou caro nesta base HOJE: o nome de um palestrante foi corrigido
-- na lista da campanha e ficou errado numa SEGUNDA lista, dentro do gerador das telas do
-- evento, que seguiu anunciando o nome antigo no ar. Aqui a arroba e `generated always`: ela
-- nao pode divergir da URL porque nao e escrita, e sim derivada.
--
-- ── Por que o CHECK e por dominio, e nao so `https://` ───────────────────────────────────
-- O erro que se quer impedir nao e URL malformada, e sim guardar `@pmigo` numa coluna que
-- todo consumidor vai ler como URL, ou trocar o Instagram pelo Facebook. Por isso o dominio
-- entra na regra. Subdominio fica livre (`br.linkedin.com` e legitimo) e query string e
-- proibida, porque `?hl=pt` no fim quebraria a derivacao da arroba.
--
-- ── Procedencia ─────────────────────────────────────────────────────────────────────────
-- `links_verified_at` e `links_source` valem para a LINHA, nao por link. E uma simplificacao
-- consciente: quando um campo novo for preenchido, re-carimbe a linha e diga de onde veio.
-- Se um dia a procedencia por link fizer falta, o caminho e uma tabela `chapter_links` ao
-- lado, e nao mais colunas aqui.

alter table public.chapter_registry
  add column if not exists website_url       text,
  add column if not exists instagram_url     text,
  add column if not exists linkedin_url      text,
  add column if not exists youtube_url       text,
  add column if not exists links_verified_at timestamptz,
  add column if not exists links_source      text;

comment on column public.chapter_registry.website_url       is 'Site oficial do capitulo, com https://.';
comment on column public.chapter_registry.instagram_url     is 'URL do perfil no Instagram. A arroba sai daqui, gerada.';
comment on column public.chapter_registry.linkedin_url      is 'URL da company page no LinkedIn.';
comment on column public.chapter_registry.youtube_url       is 'URL do canal no YouTube.';
comment on column public.chapter_registry.links_verified_at is 'Quando os links desta linha foram conferidos pela ultima vez.';
comment on column public.chapter_registry.links_source      is 'Onde foram conferidos. Ex.: "rodape do site oficial do capitulo".';

alter table public.chapter_registry
  drop constraint if exists chapter_registry_links_sao_urls_do_dominio_certo;
alter table public.chapter_registry
  add constraint chapter_registry_links_sao_urls_do_dominio_certo check (
        (website_url   is null or website_url   ~ '^https://[^?]+$')
    and (instagram_url is null or instagram_url ~ '^https://([a-z0-9-]+\.)?instagram\.com/[^?]+$')
    and (linkedin_url  is null or linkedin_url  ~ '^https://([a-z0-9-]+\.)?linkedin\.com/[^?]+$')
    and (youtube_url   is null or youtube_url   ~ '^https://([a-z0-9-]+\.)?youtube\.com/[^?]+$')
  );

-- A arroba que a copy usa, derivada da URL. `stored` para poder ser indexada e lida sem custo.
alter table public.chapter_registry
  drop column if exists instagram_handle;
alter table public.chapter_registry
  add column instagram_handle text
    generated always as (
      case when instagram_url is null then null
           else '@' || split_part(rtrim(instagram_url, '/'), '/', -1)
      end
    ) stored;
comment on column public.chapter_registry.instagram_handle is
  'Derivada de instagram_url. NAO escreva aqui: e generated always, justamente para nao divergir.';

-- ── Semente: os tres conferidos em 29/08/2026, cada um no rodape do site do proprio capitulo.
-- Os outros 12 ficam nulos de proposito. Nulo aqui diz "ainda nao conferimos", que e verdade,
-- e e diferente de preencher por deducao, que foi o erro que esta migration existe para evitar.
update public.chapter_registry set
  website_url   = 'https://pmigo.org.br/',
  instagram_url = 'https://www.instagram.com/pmigo/',
  linkedin_url  = 'https://www.linkedin.com/company/pmigo/',
  youtube_url   = 'https://www.youtube.com/channel/UC3SQWDmxwLPPfbFfM5Wgn2g',
  links_verified_at = '2026-08-29T00:00:00Z',
  links_source  = 'rodape do site oficial do capitulo'
where chapter_code = 'GO';

update public.chapter_registry set
  website_url   = 'https://pmisp.org.br/',
  instagram_url = 'https://www.instagram.com/pmisaopaulo/',
  linkedin_url  = 'https://www.linkedin.com/company/pmi-sao-paulo/',
  youtube_url   = 'https://www.youtube.com/user/PMISaoPaulo',
  links_verified_at = '2026-08-29T00:00:00Z',
  links_source  = 'rodape do site oficial do capitulo'
where chapter_code = 'SP';

-- O capitulo se chama PMI Amazonia e o site e `pmiam.org`, sem `.br`. O Instagram e
-- `@pmiamoficial`: `@pmiam` existe e NAO e deles, e foi exatamente a deducao que esta
-- migration impede de acontecer de novo.
update public.chapter_registry set
  website_url   = 'https://pmiam.org/',
  instagram_url = 'https://www.instagram.com/pmiamoficial/',
  linkedin_url  = 'https://www.linkedin.com/company/pmiam/',
  links_verified_at = '2026-08-29T00:00:00Z',
  links_source  = 'pagina de contato do site oficial do capitulo'
where chapter_code = 'AM';

-- ── Segunda leva: os 12 capitulos restantes ganham Instagram ─────────────────────────────
-- Fonte diferente da primeira leva, e por isso `links_source` diz outra coisa: a lista de
-- contas MARCADAS num post do proprio Nucleo, lida pelo dono em 29/08/2026. Cada linha
-- casou pelo NOME EXIBIDO da conta contra o `legal_name` da ficha, 15 de 15, sem conta
-- sobrando de um lado nem capitulo sobrando do outro.
--
-- Vale registrar a forca dessa fonte: os tres capitulos da primeira leva, verificados de
-- forma independente no rodape do site de cada um, aparecem na lista com a arroba
-- IDENTICA. Duas fontes independentes concordando em 3 de 3 e o que sustenta aceitar as
-- outras 12 pela lista.
--
-- So o Instagram entra aqui. Site, LinkedIn e YouTube destes 12 seguem NULOS, porque a
-- lista de marcados nao diz nada sobre eles, e preencher por analogia com a arroba seria
-- exatamente a deducao que esta migration existe para impedir.

update public.chapter_registry set
  instagram_url = 'https://www.instagram.com/' || h.handle || '/',
  links_verified_at = '2026-08-29T00:00:00Z',
  links_source = 'lista de contas marcadas em post do Nucleo no Instagram, casada pelo nome exibido'
from (values
  ('BA','pmibahia'),
  ('PE','pmipe'),
  ('MG','pmiminasgerais'),
  ('CE','pmiceara'),
  ('RS','pmi_riograndedosul'),
  ('PR','pmipr'),
  ('SE','pmisergipe'),
  ('DF','pmidf'),
  ('ES','pmiespiritosanto'),
  ('RJ','pmi_rio'),
  ('SC','pmi.sc'),
  ('PB','pmiparaiba')
) as h(code, handle)
where chapter_registry.chapter_code = h.code;
