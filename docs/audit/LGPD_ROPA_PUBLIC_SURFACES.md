# LGPD ROPA — Public Surfaces (Núcleo IA)

> **Records of Processing Activities (Art. 37 LGPD)** para superfícies
> de dados intencionalmente públicas da plataforma Núcleo IA.
> Documenta para cada superfície: base legal (Art. 7), categoria de
> dado (Art. 5), finalidade, retenção, titulares, e destinatários.
>
> **Escopo**: 24 tabelas/views + 1 função preservadas com anon SELECT
> grant após Track R Phase R3 (p59) + 1 função PII (`get_gp_whatsapp`)
> com inline LGPD comment + 1 função de agenda sem PII
> (`get_next_general_meeting`, 2026-06-11) + 6 funções do mapa-múndi de
> alcance (seção H — 4 ativas + 2 legadas deprecadas; agregadas k≥3 e
> localização precisa consentida k=1, 2026-06-26).
> Total: **32 superfícies**.
>
> **Atualizado**: 2026-06-26 (seção H expandida — opt-in de localização
> precisa k=1: novas funções `get_public_state_reach_v3`,
> `get_public_precise_country_reach`, `get_public_continent_reach`; PR
> #894/#896 backend+UI + este PR-3 de governança. Itens anteriores:
> 2026-06-23 mapa-múndi PR #852/#853; 2026-06-11 header DPO;
> corpo 2026-04-26, p59)
> **Próxima revisão**: trimestral (cadência sponsor touchpoint)
> **Sponsor**: PMI-GO (Ivan Lourenço, Presidente)
> **Encarregado de Dados (DPO)**: Ivan Lourenço Costa (titular) ·
> Angeline Altair Silva Prado (substituta) — dpo@pmigo.org.br
> (conforme `/privacy` S1/S13 — header corrigido em 2026-06-11 para
> refletir o DPO formalmente designado na política de privacidade;
> ver histórico no SPEC-625 §6.2)

---

## Quadro normativo aplicável

| Norma | Aplicação |
|---|---|
| **LGPD Art. 5, I** | Define "dado pessoal" — qualquer info ligável a pessoa natural |
| **LGPD Art. 5, II** | Define "dado pessoal sensível" — origem racial/étnica, convicção religiosa, etc. |
| **LGPD Art. 5, III** | Define "dado anonimizado" — sem possibilidade de identificação |
| **LGPD Art. 6** | Princípios: finalidade, adequação, necessidade, livre acesso, qualidade, transparência, segurança, prevenção, não discriminação, responsabilização |
| **LGPD Art. 7** | Bases legais para tratamento (10 hipóteses) |
| **LGPD Art. 7, I** | Consentimento do titular |
| **LGPD Art. 7, II** | Cumprimento de obrigação legal |
| **LGPD Art. 7, III** | Pela administração pública |
| **LGPD Art. 7, IV** | Pesquisa por órgão de pesquisa |
| **LGPD Art. 7, V** | Execução de contrato |
| **LGPD Art. 7, VI** | Exercício regular de direitos |
| **LGPD Art. 7, VII** | Proteção da vida ou da incolumidade física |
| **LGPD Art. 7, VIII** | Tutela da saúde |
| **LGPD Art. 7, IX** | **Legítimo interesse** do controlador ou de terceiro |
| **LGPD Art. 7, X** | Proteção do crédito |
| **LGPD Art. 37** | Encarregado deve manter ROPA |
| **LGPD Art. 46** | Medidas técnicas e administrativas adequadas |

**Data subjects predominantes**: voluntários do Núcleo IA (membros
ativos), sponsors (presidentes de chapters), candidatos VEP, visitantes
do site.

**Categoria de dado padrão para superfícies públicas**: dados pessoais
(Art. 5, I) — nome, foto, papel institucional. Nenhuma superfície
expõe dados sensíveis (Art. 5, II).

---

## A. Homepage / Anon-tier Direct Readers (8)

Superfícies queridas via `.from()` por componentes da homepage para
visitantes não-autenticados.

### A.1 `announcements`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional (não-PII) |
| **Base legal** | Art. 7, IX (legítimo interesse) |
| **Finalidade** | Comunicar avisos institucionais a visitantes e membros |
| **Filtro RLS** | `is_active=true AND (ends_at IS NULL OR ends_at > now())` |
| **Titulares** | N/A (não contém dados pessoais) |
| **Destinatários** | Público geral via homepage banner |
| **Retenção** | Indeterminada — soft-delete via `is_active=false` |
| **Caller** | `AnnouncementBanner.astro` (loaded em todas páginas via BaseLayout) |

### A.2 `blog_posts`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Conteúdo público (autor pode ser pessoal) |
| **Base legal** | Art. 7, IX (legítimo interesse) — divulgação institucional |
| **Finalidade** | Publicar conteúdo editorial do Núcleo IA |
| **Filtro RLS** | `status = 'published'` |
| **Titulares** | Autores (membros ativos cuja publicação foi aprovada) |
| **Destinatários** | Público geral via /blog |
| **Retenção** | Indeterminada — drafts podem ser unpublished |
| **PII exposta** | Nome do autor (via `author_member_id` join) |
| **Justificativa PII** | Crédito autoral é parte intrínseca da publicação |

### A.3 `events`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional (metadata de evento) |
| **Base legal** | Art. 7, IX (legítimo interesse) |
| **Finalidade** | Divulgar agenda de eventos públicos (geral + webinar) |
| **Filtro RLS** | `events_read_anon` policy: `type IN ('geral', 'webinar')` |
| **Titulares** | N/A (apenas título, data, link — sem PII de participantes) |
| **Destinatários** | Público geral via homepage |
| **Retenção** | Indeterminada — eventos passados permanecem |
| **Caller** | `HeroSection.astro` + `HomepageHero.astro` |

### A.4 `home_schedule`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Mostrar próximos compromissos da plataforma na homepage |
| **Filtro RLS** | USING true (todos os registros visíveis) |
| **Titulares** | N/A |
| **Destinatários** | Público geral |
| **Retenção** | Indeterminada |
| **Caller** | `lib/schedule.ts` (loaded em homepage) |

### A.5 `hub_resources`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Conteúdo curado público (não-PII) |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Divulgar biblioteca de recursos (artigos, vídeos, ferramentas) |
| **Filtro RLS** | `is_active=true` |
| **Titulares** | N/A (recursos públicos curados) |
| **Destinatários** | Público geral via /library + ResourcesSection |
| **Retenção** | Indeterminada — soft-delete via is_active |
| **Caller** | `ResourcesSection.astro`, `library.astro` |

### A.6 `site_config`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Configuração de rendering (chapter list, schedule labels) |
| **Filtro RLS** | (key-value, sem filter) |
| **Titulares** | N/A |
| **Destinatários** | Público geral via homepage |
| **Retenção** | Indeterminada |
| **Caller** | `ChaptersSection.astro`, `WeeklyScheduleSection.astro`, `ReportPage.tsx` |

### A.7 `tribe_meeting_slots`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional (horário de reunião) |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Mostrar horários de reuniões de tribos para visitantes |
| **Filtro RLS** | USING true |
| **Titulares** | N/A (sem PII) |
| **Destinatários** | Público geral |
| **Retenção** | Indeterminada — atualizado conforme cadência |
| **Caller** | `TribesSection`, `WeeklyScheduleSection`, `HomepageHero` |

### A.8 `tribes`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional (catálogo de tribos) |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Divulgar tribos de pesquisa do Núcleo IA |
| **Filtro RLS** | USING true |
| **Titulares** | N/A |
| **Destinatários** | Público geral |
| **Retenção** | Indeterminada |
| **Caller** | `TribesSection`, `HeroSection`, `HomepageHero` |

---

## B. Public Reference Data (USING true policies) (8)

Dados de referência intencionalmente abertos (taxonomy, releases, etc.).
Sem PII em nenhum.

### B.1-B.8 — Tabela consolidada

| Tabela | Categoria | Base legal | Finalidade | PII? | Retenção |
|---|---|---|---|---|---|
| `courses` | Catálogo | Art. 7, IX | Catálogo de cursos da trilha | Não | Indeterminada |
| `cycles` | Metadata temporal | Art. 7, IX | Ciclos de pesquisa do Núcleo (ano, etapas) | Não | Indeterminada |
| `help_journeys` | Conteúdo onboarding | Art. 7, IX | Trilhas de ajuda persona-keyed | Não | Indeterminada |
| `ia_pilots` | Showcase | Art. 7, IX | Pilotos de IA do Núcleo (público) | Não | Indeterminada |
| `offboard_reason_categories` | Reference taxonomy | Art. 7, IX | Categorias de motivo de offboarding (form taxonomy) | Não | Indeterminada |
| `quadrants` | Reference taxonomy | Art. 7, IX | Quadrantes de pesquisa | Não | Indeterminada |
| `release_items` | Release notes | Art. 7, IX | Items de release notes (visible=true filter) | Não | Indeterminada |
| `releases` | Release history | Art. 7, IX | Histórico de releases da plataforma | Não | Indeterminada |

**Destinatários**: público geral via /library, /trilha, /changelog,
/curso, etc.

---

## C. Public KPI / Publication / Certification (4)

Dashboards e catálogos públicos de saída institucional.

### C.1 `portfolio_kpi_quarterly_targets`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Agregado institucional (não-PII) |
| **Base legal** | Art. 7, IX (legítimo interesse — transparência institucional) |
| **Finalidade** | Mostrar publicamente metas trimestrais do Núcleo |
| **Filtro RLS** | USING true |
| **Titulares** | N/A |
| **Destinatários** | Público geral, sponsors PMI |
| **Retenção** | Indeterminada — histórico institucional |

### C.2 `portfolio_kpi_targets`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Agregado institucional (não-PII) |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Mostrar publicamente metas anuais do Núcleo |
| **Filtro RLS** | `anon_read_kpi_targets` policy explícita |
| **Titulares** | N/A |
| **Destinatários** | Público geral, sponsors PMI |
| **Retenção** | Indeterminada |

### C.3 `public_publications`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Conteúdo público + PII (autores) |
| **Base legal** | Art. 7, V (execução de contrato — voluntariado) + Art. 7, IX (legítimo interesse — divulgação acadêmica) |
| **Finalidade** | Divulgar publicações do Núcleo (artigos, frameworks, toolkits) |
| **Filtro RLS** | `pub_read_published` filter `is_published=true` |
| **Titulares** | Autores (membros que assinaram acordo de voluntariado) |
| **PII exposta** | Nomes dos autores (via `authors[]` field) |
| **Justificativa PII** | Crédito autoral é parte intrínseca de publicação acadêmica/profissional. Voluntários assinam termo que prevê exposição autoral. |
| **Destinatários** | Público geral via /publications |
| **Retenção** | Indeterminada — registro institucional de produção |

### C.4 `webinars`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Metadata de evento (não-PII direta) |
| **Base legal** | Art. 7, IX |
| **Finalidade** | Catálogo público de webinars do Núcleo |
| **Filtro RLS** | `webinars_read_anon` policy: `status IN ('confirmed', 'completed')` |
| **Titulares** | N/A (apenas título/data/link; palestrantes referenciados via outra view se aplicável) |
| **Destinatários** | Público geral |
| **Retenção** | Indeterminada — registro de eventos realizados |

---

## D. ADR-Documented Public Views (2)

### D.1 `public_members` (ADR-0024 — accepted ERROR)

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | **PII institucional** (Art. 5, I) |
| **Base legal** | Art. 7, V (execução de contrato — voluntariado) + Art. 7, IX (legítimo interesse — diretório institucional PMI) |
| **Finalidade** | Diretório público de liderança do Núcleo (homepage TeamSection, TribesSection, CpmaiSection) |
| **Filtro view** | SECURITY DEFINER — view creator filtra para colunas public-safe (id, nome, photo, chapter, designations, operational_role, tribe_id) |
| **Titulares** | Membros ativos com papel de liderança (tribe_leader, comms_leader, manager, sponsor, etc.) |
| **PII exposta** | Nome, foto, chapter, papel — sem email/telefone/PMI ID |
| **Justificativa PII** | Liderança institucional é intencionalmente pública (padrão PMI internacional para chapter directories). Voluntário consente via termo que prevê exposição de papel. |
| **Destinatários** | Público geral via homepage |
| **Retenção** | Enquanto member ativo + 1 ano post-offboarding (per ADR-0014 retention) |
| **ADR específico** | ADR-0024 (accepted risk SECURITY DEFINER view) |

### D.2 `members_public_safe` (ADR-0010)

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | **PII institucional** (subset da D.1) |
| **Base legal** | Art. 7, V + Art. 7, IX |
| **Finalidade** | View segura de members para queries internas que não precisam de PII completa |
| **Filtro view** | SELECT-list reduzido: `id, name, operational_role, tribe_id, current_cycle_active, photo_url`. Exclui email, phone, pmi_id, auth_id |
| **Titulares** | Todos members ativos |
| **PII exposta** | Nome + papel + tribo + foto |
| **Justificativa PII** | Subset minimizado per Art. 6 (necessidade) — só os campos necessários para UIs internos. |
| **Destinatários** | Member-tier UIs (rendered post-login) |
| **Retenção** | Conforme members table |
| **ADR específico** | ADR-0010 (wiki scope) menciona; documentação primária inline COMMENT |

---

## E. Gamification Leaderboard (2)

### E.1 `gamification_points`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Atividade de membro (PII indireta via member_id) |
| **Base legal** | Art. 7, V (execução de contrato — voluntariado prevê gamificação) + Art. 7, IX (legítimo interesse — leaderboard público gamificado) |
| **Finalidade** | Leaderboard público de pontos (gamification.astro) |
| **Filtro RLS** | v4 org_scope (todos org members enxergam) |
| **Titulares** | Members ativos |
| **PII exposta** | member_id (linkable via public_members ⇒ nome) + categoria de pontos + razão de obtenção (ex: "Credly:CPMAI cert") |
| **Justificativa PII** | Padrão community gamificada — pontos de membros são intencionalmente visíveis. Voluntário consente ao aceitar termo. |
| **Destinatários** | Público geral via /gamification |
| **Retenção** | Permanente (histórico de XP do membro) |
| **Risco potencial** | Categoria de pontos pode revelar atividade detalhada (ex: cert obtida) — accepted per ADR-0024 pattern |

### E.2 `tribe_selections`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Operacional + PII indireta |
| **Base legal** | Art. 7, V + Art. 7, IX |
| **Finalidade** | Mostrar contagem de membros por tribo (homepage TribesSection) + ranking de tribos no leaderboard |
| **Filtro RLS** | `Public tribe counts USING true` + `anon_read_tribe_selections` |
| **Titulares** | Members ativos selecionados em tribos |
| **PII exposta** | member_id + tribe_id (linkable via public_members) |
| **Justificativa PII** | Membership de tribo é institucionalmente pública (similar a public_members) |
| **Destinatários** | Público geral |
| **Retenção** | Por ciclo (mantido para histórico) |

---

## F. PII Function (1)

### F.1 `get_gp_whatsapp()` (function, not table)

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | **PII direta** (telefone do GP — Art. 5, I) |
| **Base legal** | Art. 7, V (consentimento via assinatura de termo de voluntariado para papel de GP) + Art. 7, IX (legítimo interesse institucional — fluxo de suporte do Núcleo IA) |
| **Finalidade** | Botão "WhatsApp GP" em help.astro para visitantes obterem suporte direto |
| **Output** | Telefone (regexp_replace digits-only) + nome + label de fonte |
| **Data minimization** | Apenas telefone + nome do GP atual; sem endereço, email, ou PII estendida |
| **Titular** | GP em exercício (atualmente: Vitor Maia Rodovalho) |
| **Justificativa PII** | GP role aceita exposição de contato como parte do termo (institucional). Sucessores assumem mesmo padrão. |
| **Destinatários** | Visitantes anônimos via help.astro |
| **Retenção** | Enquanto member é GP ativo |
| **ADR específico** | Comment inline na função (Track R Phase R3 p59) |

**Risco residual identificado pelo security-engineer (p59)**:
- Phone exposure não tem consent record explicitamente vinculado
  no Art. 18 cycle (LGPD subject rights). Mitigation: no termo de
  GP role, incluir cláusula explícita de consent para exposição
  pública de WhatsApp + cadência de revisão.

---

## G. Public Agenda Function (1)

### G.1 `get_next_general_meeting()` (function, not table)

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Nenhum dado pessoal (agenda institucional: data, hora de início, duração da próxima Reunião Geral) |
| **Base legal** | N/A — não há tratamento de dado pessoal (LGPD Art. 5º, I não alcançado) |
| **Finalidade** | Linha "Reunião Geral" data-driven na homepage (substitui string i18n hardcoded que dessincronizava da cadência real) |
| **Filtro** | SECURITY DEFINER; `type='geral' AND initiative_id IS NULL AND status<>'cancelled' AND date>=CURRENT_DATE LIMIT 1`; retorna SÓ `{date, time_start, duration_minutes}` |
| **Titulares** | N/A |
| **Destinatários** | Público geral via homepage |
| **Retenção** | N/A (leitura derivada de `events` — ver A.3) |
| **Caller** | `WeeklyScheduleSection.astro` |
| **Migration** | `20260805000143` (2026-06-11). Nota: anon já lia `events` direto (A.3, policy `type IN ('geral','webinar')`); esta função é superfície *mais estreita* que o read direto. |

---

## H. Public Reach Map Functions (6)

Funções `SECURITY DEFINER` que alimentam o **mapa-múndi de distribuição de
membros** na homepage (`#capitulos`, "Capítulos PMI Integrados"). Originadas em
PR #852/#853 (2026-06-23) e expandidas em PR #894/#896 (2026-06-26) com o opt-in
unificado de **localização precisa** (k=1). Substituíram o choropleth Brasil-only
(`BrazilMap.astro`, deletado).

**Dois regimes coexistem, por base legal distinta** (parecer legal-counsel 2026-06-25):

- **Agregado (Art. 7, IX — legítimo interesse, k≥3):** país (H.1) e continente
  residual (H.4). Contagens com piso de anonimato; nenhuma linha individual.
- **Consentido (Art. 7, I — consentimento específico):** estado BR/US (porção
  precise de H.2) e país não-BR/US (H.3). Exibem a localização do membro **mesmo
  a k=1** (um único membro), exclusivamente para quem ativou o opt-in específico e
  informado `allow_precise_location_in_public_map`. A população legada
  `allow_state_in_public_map` permanece **k≥3** ("nunca individual").

As populações agregada e precise são tratadas em **subconsultas segregadas** e
**jamais somadas** quando a contagem agregada é inferior a 3 (regra "d" do parecer —
evita reconstruir indiretamente a população legada sub-k). Nenhuma função expõe PII
direta; o output é sempre `(localização, contagem)`. **A premissa anterior "nenhuma
expõe linha individual" não vale mais** para a porção precise/H.3, que é exibição
individual por consentimento explícito.

### H.1 `get_public_country_reach()`

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | Agregado estatístico — contagem de membros ativos por país. O *output* não contém dado pessoal individual (Art. 5, I não alcançado no output); o *processamento* opera sobre o país de residência de membros (dado pessoal). Piso k≥3 impede singularização no output. *(Não classificado como "anonimizado" Art. 5, III — o doc documenta vetor residual de inferência adiante; ver Riscos.)* |
| **Base legal** | Art. 7, IX (legítimo interesse — transparência do alcance institucional) sobre o agregado |
| **Teste de balanceamento (Art. 10, §2º)** | Interesse legítimo: comunicar publicamente o alcance geográfico do Núcleo a sponsors (PMI-GO), candidatos e público. Impacto ao titular: mínimo — output agregado sem quasi-identificadores individuais, titular não identificável sob k≥3. Expectativa razoável: membro de organização voluntária de alcance internacional espera que a presença geográfica institucional seja pública. **Resultado: o interesse prevalece.** |
| **Finalidade** | Pins por país no mapa-múndi da homepage (alcance internacional do Núcleo) |
| **Output** | `(country_code, member_count)`; países com contagem < k são colapsados no bucket `ZZ` (apenas chip de legenda, nunca pin) |
| **k-anonimato** | k≥3; nenhum país com < 3 membros é identificado |
| **Titulares** | Membros ativos (apenas país de residência, agregado) |
| **PII exposta** | Nenhuma no output — contagem agregada; país não é ligável a indivíduo sob k≥3 |
| **Destinatários** | Público geral via homepage |
| **Transferência internacional** | Não há transferência de dado pessoal individual ao exterior. Output agregado entregue via CDN (Cloudflare); dados de entrada (país de residência) permanecem em Supabase sa-east-1 (Brasil). Art. 33 não acionado sobre o output. |
| **Retenção** | N/A (derivado ao vivo de `members`; sem persistência própria) |
| **Medidas técnicas (Art. 46)** | SECURITY DEFINER; REVOKE ALL FROM PUBLIC + GRANT EXECUTE só a anon/authenticated/service_role |

### H.2 `get_public_state_reach_v3(p_min_k int DEFAULT 3)` — dual-população (ATIVA)

| Campo ROPA | Valor |
|---|---|
| **Status** | **Ativa** — função de estado em uso pela homepage (`ChaptersSection.astro`) desde PR #896 (2026-06-26). Substituiu a v2 (H.5) no frontend. |
| **Categoria de dado** | Localização de residência por **estado/UF** (BR) e **state** (US) de membros que consentiram. Duas populações: **(a)** agregada (`allow_state_in_public_map AND NOT allow_precise…`) e **(b)** precisa (`allow_precise_location_in_public_map`). |
| **Base legal** | **Art. 7, I (consentimento) — base primária e vinculante** das duas porções: legado `allow_state_in_public_map` ("nunca individual", k≥3) + novo `allow_precise_location_in_public_map` ("mesmo que eu seja o único", k=1). Revogado o consentimento, o membro sai da próxima consulta. *Nota:* a porção agregada k≥3 seria independentemente defensável por Art. 7, IX (como H.1), mas, tendo-se **solicitado** o consentimento, IX **não** é base alternativa para essa população (evita stacking de bases — orientação ANPD). |
| **Finalidade** | Pins de estado (BR/EUA): a porção precise exibe o estado **mesmo a k=1**; a agregada só a partir de k≥3. |
| **Output** | `(country_code, region_code, member_count)` com `member_count = count_precise + (count_aggregate SE count_aggregate ≥ GREATEST(p_min_k,3), senão 0)`. Pin aparece se `count_precise ≥ 1 OR count_aggregate ≥ GREATEST(p_min_k,3)`. |
| **Regra de segregação (parecer "d")** | As duas populações são contadas em `FILTER`s separados e **jamais somadas** quando `count_aggregate < 3` — impede reconstruir a população legada sub-k a partir do total exibido. Um precise-consenter sai da população agregada (`is_aggregate = allow_state AND NOT allow_precise`). |
| **k-anonimato** | **Precise: k=1** (o consentimento específico cobre a exibição individual). **Agregada: piso rígido k≥3** via `GREATEST(p_min_k, 3)` — inbypassável independentemente do parâmetro do caller. |
| **Denominador** | Membros `is_active AND current_cycle_active AND NOT pré-onboarding` que ativaram pelo menos um dos dois flags. |
| **Texto de consentimento** | Agregado: `profile.allowStateMapLabel` ("apenas de forma agregada · nunca individual", país-agnóstico, sem citar k). Precise: `profile.allowPreciseLocationMapLabel` (estado BR/US **ou** país; "mesmo que eu seja o único"; ciente de que a origem fica identificável no contexto da comunidade). |
| **Grandfather** | Quem consentiu só o flag legado permanece em k≥3; migrar para k=1 exige **re-consentimento ativo** (marcar o toggle novo). Silêncio ≠ aceite (Art. 7, I) — k=1 retroativo é vedado. |
| **Titulares** | Membros ativos que ativaram um dos opt-ins de localização. |
| **Revogação** | Desativar o toggle correspondente em `/profile` ⇒ removido no próximo render. |
| **Transferência internacional** | Igual a H.1 — sem transferência de dado individual; output via CDN, entrada em sa-east-1. |
| **Retenção** | Output: N/A (derivado ao vivo de `members`). Flags de consentimento: persistem enquanto membro ativo; anonimizados pelo cron `anonymize_inactive_members` 5 anos após offboarding (ADR-0014). |
| **Medidas técnicas (Art. 46)** | SECURITY DEFINER, STABLE, `search_path=''`; piso k≥3 inbypassável na porção agregada via `GREATEST(p_min_k,3)`; segregação de populações; carrega o fix `LIMIT 1` da colisão `br_lookup` (mig `…250`). ACL alinhada ao padrão: `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE` a anon/authenticated/service_role (mig `…252`, PR-3). |
| **Migration** | `20260805000250` (fix colisão `br_lookup`) + `20260805000251` (v3 dual-população + coluna/RPCs do opt-in precise) |

### H.3 `get_public_precise_country_reach()` — NOVA (consentida, k=1)

| Campo ROPA | Valor |
|---|---|
| **Status** | **Ativa** — PR #894/#896 (2026-06-26). |
| **Categoria de dado** | País de residência de membros **fora de BR/US** que ativaram o opt-in de localização precisa. |
| **Base legal** | **Art. 7, I (consentimento específico e informado)** — `allow_precise_location_in_public_map`, texto `profile.allowPreciseLocationMapLabel`. |
| **Finalidade** | Pin de país (teal) no mapa-múndi para o membro consentente, **mesmo a k=1** (único membro do país). |
| **Output** | `(country_code, member_count)` — só países reconhecidos (PT, IT, ES, AR, GB, CA, FR, DE); `member_count` = nº de consententes. Países não reconhecidos não recebem pin (caem no residual de continente/`ZZ`). BR/US são excluídos (sempre pin nomeado; a precisão deles é a camada de estado, H.2). |
| **k-anonimato** | **k=1** — o consentimento explícito cobre a exibição individual. |
| **Denominador** | Membros `is_active AND current_cycle_active AND NOT pré-onboarding` com `allow_precise_location_in_public_map = true`. |
| **Titulares** | Membros ativos fora de BR/US que ativaram o opt-in precise. |
| **Revogação** | Desativar o toggle em `/profile` ⇒ removido no próximo render. |
| **Transferência internacional** | Sem transferência de dado individual ao exterior; output via CDN, entrada em sa-east-1. |
| **Retenção** | Output: N/A (derivado ao vivo). Flag: igual a H.2 (anonimizado 5 anos pós-offboarding, ADR-0014). |
| **Medidas técnicas (Art. 46)** | SECURITY DEFINER, STABLE, `search_path=''`; output só código de país + contagem (zero-PII direta). ACL REVOKE-PUBLIC alinhada (mig `…252`, PR-3). |
| **Migration** | `20260805000251` |

### H.4 `get_public_continent_reach()` — NOVA (agregada residual, k≥3)

| Campo ROPA | Valor |
|---|---|
| **Status** | **Ativa** — PR #894/#896 (2026-06-26). |
| **Categoria de dado** | Agregado estatístico — contagem do **residual** de membros por continente (os que as camadas mais finas não exibem). |
| **Base legal** | **Art. 7, IX (legítimo interesse)** — **sem novo consentimento**: agrega o residual com piso de anonimato (mesma base de H.1). |
| **Teste de balanceamento (Art. 10, §2º)** | Idêntico a H.1: interesse legítimo em comunicar o alcance continental; impacto mínimo (output agregado k≥3, sem singularização); **o interesse prevalece**. |
| **Finalidade** | Pin de continente (navy, no centroide) + chip de legenda para o residual; bucket `ZZ` (Internacional) para o resto. |
| **Output** | `(continent_code, member_count)` agrupado por continente quando ≥3, senão colapsado em `ZZ`. **Exclui**: BR/US (pin nomeado) e, **entre os países reconhecidos**, os com total ≥3 (pin nomeado) e os precise-consententes (já exibidos em H.3) — **sem double-count**. O bucket sintético `XX` (países não-mapeados) **nunca** é excluído — não vira pin nomeado nem preciso (sem centroide), então todo membro `XX` permanece no residual → `ZZ` (fix #897, mig `…253`). |
| **k-anonimato** | **k≥3 por continente nomeado** (EU/SA/NA); abaixo disso → `ZZ`. O bucket residual `ZZ` (Internacional) **não tem piso próprio** — é o catch-all de todo membro cujo continente não atingiu k=3 **ou** cujo país é não-mapeado (`XX`); pode portanto exibir `count` < 3 (já era assim em H.1 antes do mapa). Não singulariza país nem indivíduo: revela só "existem ≥N membros fora dos pins nomeados". `ZZ` é chip de legenda, nunca pin. |
| **Titulares** | Membros ativos (processados; output sem localização individual — apenas agregado continental k≥3). |
| **Transferência internacional** | Igual a H.1. |
| **Retenção** | N/A (derivado ao vivo de `members`). |
| **Medidas técnicas (Art. 46)** | SECURITY DEFINER, STABLE, `search_path=''`; exclui precise-consententes **de países reconhecidos** para não double-contar; **`XX` (não-mapeado) sempre mantido no residual** (#897, mig `…253`); k≥3 por continente. ACL REVOKE-PUBLIC alinhada (mig `…252`, PR-3). |
| **Migration** | `20260805000251` (criação) · `20260805000253` (fix #897 — `XX` sempre no residual) |

### H.5 `get_public_state_reach_v2(p_min_k)` + `get_public_state_reach()` — legados (deprecados)

| Campo ROPA | Valor |
|---|---|
| **Status** | **Deprecados** — superados pela v3 (H.2). A v2 deixou de ser chamada pelo frontend em PR #896; referências remanescentes a `_v2` em `WorldReachMap.astro`/`worldMap.ts` são **comentários stale**, não chamadas. A v1 já estava deprecada desde a v2. |
| **Categoria / base legal** | Idêntico à porção agregada de H.2 (Art. 7, I — `allow_state_in_public_map` + IX). v2: piso k≥3; v1: piso original k≥5. |
| **Diferença p/ v3** | População **única** (só agregada `allow_state`); sem a porção precise k=1. A v2 tinha o bug de colisão `br_lookup` (#893), **resolvido em `…250`** (LIMIT 1); a v3 incorpora o mesmo fix nativamente em `…251`. |
| **ACL** | v2/v1 = REVOKE-PUBLIC (mig `…242`); as 3 funções novas (H.2/H.3/H.4) foram alinhadas ao mesmo padrão em `…252` (PR-3). |
| **Ação recomendada** | `DROP FUNCTION` de v1 e v2 após confirmar 0 callers residuais (limpar também os comentários stale que citam v2/k≥3 em `WorldReachMap.astro`, `worldMap.ts` e `ChaptersSection.astro`). |

**Riscos residuais identificados (revisão do mapa + pareceres legal-counsel, 2026-06-23 + 2026-06-25):**

- **Disclosure do bucket `ZZ`**: a contagem do bucket `ZZ` (países sub-k) é
  publicamente visível. Revela que *existe* membro em país com < 3 membros,
  **não a identidade nem qual país** (Art. 6, III — necessidade/finalidade; aceitável).
  *Vetor secundário (variação temporal):* sem cache, a oscilação do `ZZ` entre renders
  poderia servir de monitor indireto de ingresso/saída em países sub-k. Mitigação: a home
  SSR **não é edge-cacheada** (verificado 2026-06-23: resposta sem `cf-cache-status`); o
  follow-up de `Cache-Control: no-store` é defensivo, não corretivo (ver nota de cache abaixo).
- **Inferência por exclusão**: combinar a contagem de país (H.1) com a de estado
  (H.2) pode permitir inferência residual (ex.: país com 4 membros e único estado
  exibido com 3 ⇒ infere-se que o 4º reside em estado não exibido). Avaliação: o vetor
  existe mas **não singulariza indivíduo** (conclui "há membro neste país fora dos estados
  exibidos", não "fulano reside em X"); impacto ao titular mínimo. **Decisão PM (2026-06-23):
  aceitar o risco residual** — suprimir a simultaneidade país+estado teria custo de UX
  superior ao ganho marginal de privacidade. Rever se o nº de membros em países sub-k crescer.
- **Camadas de localização são opt-in puro**: membros sem nenhum dos toggles nunca
  entram em H.2/H.3 — ausência de pin não é, por si, dado sobre o membro.
- **Disclosure individual por consentimento (precise, k=1)** — *por design*: a porção
  precise de H.2 (estado BR/US) e H.3 (país) tornam a origem geográfica do membro
  **identificável no contexto da comunidade mesmo quando ele é o único** de sua
  localização. Isto **não é um vazamento**: é exibição individual sob consentimento
  específico e informado (Art. 7, I), com texto `profile.allowPreciseLocationMapLabel`
  que declara expressamente esse efeito, revogável a qualquer momento. A população
  legada (`allow_state`, "nunca individual") **não** é arrastada para k=1 sem
  re-consentimento ativo. Sem consentimento precise, nada individual aparece.
- **Follow-up de transparência (`/privacy`) — ✅ RESOLVIDO (PR-3, 2026-06-26)**: o
  gap de Art. 6, VI (o `/privacy` não descrevia a garantia de agregação mínima nem o
  nível precise) foi fechado pela nova subseção **3.1 "Exibição pública de localização
  no mapa geográfico"** (chaves `privacy.s3map.*`, 3 idiomas), que descreve os dois
  níveis (agregado mínimo de 3 · localização precisa consentida) + revogação. O texto
  do opt-in em `/profile` **não** foi alterado.
- **Hardening de ACL — ✅ RESOLVIDO (PR-3, mig `…252`)**: H.2 (`_v3`), H.3
  (`precise_country_reach`) e H.4 (`continent_reach`) estavam com **ACL default
  `PUBLIC EXECUTE`** (`=X/postgres`), divergindo do `REVOKE ALL FROM PUBLIC` de
  H.1/H.5 (mig `…242`). Benigno (SECDEF, `search_path=''`, output agregado/zero-PII
  direta), mas inconsistente com o padrão de hardening deste RoPA. **Alinhado no
  PR-3** via `REVOKE ALL ... FROM PUBLIC` + `GRANT EXECUTE` só a
  anon/authenticated/service_role (mig `…252`) — verificado ao vivo (antes:
  `=X/postgres` presente; depois: ausente).
- **precise-consenter em país não-suportado some do mapa — ✅ RESOLVIDO (#897, mig
  `…253`, 2026-06-26)**: `get_public_precise_country_reach` reconhece só 8 países
  (PT, IT, ES, AR, GB, CA, FR, DE); um membro com `allow_precise=true` em país fora
  dessa lista não recebe pin preciso (H.3, `ELSE NULL`). O bug: `get_public_continent_reach`
  o excluía **também** do residual (`AND NOT n.is_precise`) ⇒ sumia das duas camadas
  — pior que não consentir (um não-consenter no mesmo país ainda cairia no `ZZ`).
  **Buraco-irmão descoberto no fix:** o filtro `ct.total<3` também era aplicado ao
  bucket sintético `XX`, derrubando **qualquer** conjunto de ≥3 membros espalhados
  por países não-mapeados (mesmo não-precise), já que `XX` nunca vira pin nomeado
  (`get_public_country_reach` sempre dobra `XX`→`ZZ`). **Fix:** `XX` bypassa **ambos**
  os filtros e permanece sempre no residual → chip `ZZ` (mesma exposição agregada
  Art. 7,IX que um não-consenter já tem; **menos** do que o precise-consenter
  autorizou). Behavior-neutral hoje (0 precise / 0 `XX`); provado por simulação no
  engine PG (predicado antigo: `ZZ`=1, 5 membros sumindo; predicado novo: `ZZ`=6,
  todos presentes). **Opção 1** (pin preciso para países arbitrários — exige
  centroides novos em `worldMap.ts` + asset) fica como enhancement separado, fora
  deste fix. Guard em `cycle4-coverage-map.test.mjs`.

---

## Resumo por base legal

| Base legal Art. 7 | Quantidade de superfícies | Lista |
|---|---|---|
| **I (consentimento)** | 4 | get_public_state_reach_v3, get_public_precise_country_reach, get_public_state_reach_v2 (legado), get_public_state_reach (legado) — opt-ins de localização (`allow_state_in_public_map` k≥3 + `allow_precise_location_in_public_map` k=1; combinada com IX na porção agregada) |
| **V (execução de contrato)** | 6 | public_publications, public_members, members_public_safe, gamification_points, tribe_selections, get_gp_whatsapp |
| **V + IX (combinada)** | ↳ mesmas 6 de V | (sub-nota, **não soma** — predominante para PII institucional) |
| **IX (legítimo interesse) — apenas** | 21 | Demais operacional/agregado/reference — inclui get_public_country_reach + get_public_continent_reach (agregados k≥3) |
| **N/A (sem dado pessoal)** | 1 | get_next_general_meeting (agenda institucional — Art. 5, I não alcançado) |

**Predominância Art. 7, IX** reflete natureza voluntária + transparente
do Núcleo IA. Onde há PII, Art. 7, V documenta o termo de voluntariado
como base contratual.

---

## Categorias por sensibilidade

| Sensibilidade | Quantidade | Treatment |
|---|---|---|
| **Não-PII / agregado / referência / N/A** | 21 | Anon access OK — risco zero (inclui get_public_country_reach + get_public_continent_reach — agregados k≥3, sem singularização; e get_next_general_meeting, sem dado pessoal) |
| **Localização consentida (estado/país, Art. 7, I)** | 4 | get_public_state_reach_v3 + get_public_precise_country_reach **podem singularizar a k=1** sob consentimento específico e informado; v2/v1 legados só agregam k≥3. Output sem identificador direto (só localização + contagem). |
| **PII institucional (nome, papel, foto)** | 6 | Anon access OK per consent + termo (inclui blog_posts — nome do autor) |
| **PII direta (telefone)** | 1 | Anon access OK per consent explícito de GP role |
| **PII sensível (Art. 5, II)** | 0 | N/A — nenhuma superfície |

---

## Direitos do titular (Art. 18 LGPD)

Para qualquer superfície com PII (D.1, D.2, E.1, E.2, F.1), o titular
pode exercer:

| Direito | Mecanismo |
|---|---|
| Confirmação de tratamento (Art. 18, I) | Member loga + visualiza próprio member record + leaderboard rank |
| Acesso (Art. 18, II) | Self-service via /profile + /gamification |
| Correção (Art. 18, III) | Self-service edit em /profile (campos públicos) |
| Anonimização (Art. 18, IV) | Cron `anonymize_inactive_members` (5y após offboarding) + manual `admin_anonymize_member` sob solicitação |
| Portabilidade (Art. 18, V) | Self-service export `export_my_personal_data` |
| Eliminação (Art. 18, VI) | `delete_my_personal_data` self-service + admin escalation se necessário |
| Informação sobre uso compartilhado (Art. 18, VII) | Privacy policy `/privacy` + ROPA público via solicitação |
| Revogação de consentimento de localização (Art. 18, IX) | Self-service: desativar o toggle em `/profile` (Configurações → Meu Perfil) ⇒ removido no próximo render do mapa; não requer offboarding. Aplica-se a `allow_state_in_public_map` e `allow_precise_location_in_public_map` (seções H.2/H.3) |
| Revogação de consentimento — geral (Art. 18, IX) | Offboarding via `offboard_member` ⇒ remove engagements ⇒ removes from public_members |

---

## Auditoria

**Trilha**: cada superfície tem inline `COMMENT ON TABLE/VIEW/FUNCTION`
documentando:
- Padrão "Public-by-design"
- Caller ou justificativa
- Referência a ADR ou doc relacionado
- Track R Phase R3 (p59) tag

**Migrations**:
- `20260426161441_track_r_phase3_intentional_public_comments.sql` — 24 superfícies
- `20260426162019_track_r_phase3_lgpd_comment_get_gp_whatsapp.sql` — 1 função
- `20260805000241_*` — `get_public_state_reach_v2` (mapa-múndi, piso k≥3; agora legado H.5)
- `20260805000242_revoke_public_get_public_state_reach.sql` — alinha ACL do legado ao padrão REVOKE-PUBLIC (2026-06-23)
- `20260805000250_fix_state_reach_v2_br_lookup_collision.sql` — fix `LIMIT 1` da colisão `br_lookup` (#893; reaproveitado pela v3)
- `20260805000251_precise_location_optin_backend.sql` — coluna `allow_precise_location_in_public_map` + `get_public_state_reach_v3` (dual-população) + `get_public_precise_country_reach` + `get_public_continent_reach` (seções H.2/H.3/H.4; PR #894)
- `20260805000252_revoke_public_precise_reach_funcs.sql` — alinha ACL das 3 funções novas (H.2/H.3/H.4) ao padrão `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE` a anon/authenticated/service_role; corrige o cross-ref do COMMENT da coluna (`RoPA H.4` → `H.2/H.3`); PR-3
- `20260805000253_fix_continent_reach_unmapped_country_vanish_897.sql` — `get_public_continent_reach` (H.4): `XX` (países não-mapeados) sempre mantido no residual → não some do mapa; fecha #897 (precise-consenter em país não-suportado) + o buraco-irmão `XX`≥3; behavior-neutral (0 precise/0 `XX` hoje)

**Trilha imutável**: GitHub commits assinados (`2ff39e8`, `ca072c8`; mapa precise: `d6dfe5c0`, `0c6404a6`).

---

## Próxima revisão

**Cadência**: trimestral, alinhada com sponsor touchpoint (PMI-GO).
**Próxima revisão**: 2026-07-26 (próximo trimestre Q3).

## G. Eventos com convidados externos (1)

Tratamento novo (2026-07): coleta ativa de PII de **não-membros** para inscrição/presença/certificado
em eventos abertos do Núcleo. Primeira instância: Aftershow Núcleo IA & GP, 16/07/2026 (Airmeet).
Entrada criada ANTES da abertura das inscrições (aceite do issue #1009; decisões GP 2026-07-03).

### G.1 Inscrição de convidados externos — Aftershow 16/07/2026 (Airmeet)

| Campo ROPA | Valor |
|---|---|
| **Categoria de dado** | PII direta: nome, e-mail; opcional: capítulo PMI de origem. Registro de presença (tempo de sala via Airmeet). |
| **Base legal** | Art. 7, I (**consentimento** ativo no ato da inscrição — não-membros não têm contrato com PMI-GO/Núcleo; checkbox obrigatório no formulário) |
| **Finalidade** | Inscrição no evento, controle de presença e emissão de certificado de participação |
| **Operadora / transferência** | **Airmeet** (formulário nativo + lista de participantes) — transferência internacional Arts. 33–36; citar DPA/SCC da Airmeet se existente, senão consentimento específico Art. 33 VIII no texto do formulário |
| **Titulares** | Convidados externos (não-membros) inscritos no evento |
| **Destinatários** | Organização do evento (GP/Co-GP + produção); dado NÃO entra em superfícies públicas |
| **Retenção** | **1 ano a contar do evento** (16/07/2027) — cobre reemissão/contestação de certificado; depois, deleção. Implementado: `event_guest_certificates.retention_until = data do evento + 1 ano` (mig 20260805000338, #1098) |
| **Deleção** | Mecanismo **separado** do cron de membros (anonymize 5y não se aplica — convidados não têm `members` row). **Implementado (#1098): RPC `delete_expired_event_guest_certificates(p_dry_run)`** — dry-run por default; execução real (gate manage_platform ou service_role) deleta certs expirados + `persons` órfãos guest-only (auth_id NULL, sem legacy link, marker `consent_version LIKE 'event-guest%'`, sem engagements, sem outros certs; FK-safe por linha) e registra em `admin_audit_log` (action `lgpd_event_guest_cert_retention_deletion`). **Passo DPO documentado**: (1) rodar dry-run após 16/07/2027; (2) rodar com `p_dry_run=false`; (3) purgar do bucket `certificates` os paths retornados em `storage_paths_to_purge` (prefixo `guests/`); (4) conferir a entrada no audit log. Convidado pode solicitar antes via canal Art. 18. |
| **Certificado** | **Implementado (#1098, mig 20260805000338)**: tabela `event_guest_certificates` ancorada em `persons` (`certificates.member_id` NOT NULL preservado); emissão via `issue_event_guest_certificate` (gate manage_event/manage_platform; cria/reusa `persons` por lower(email)); verificação pública por código preservada — `verify_certificate` resolve ambos os caminhos, oracle-free (#991); PDF no bucket `certificates` sob `guests/<person_id>/` (purga de retenção segmentada) |
| **Notas** | Aviso de privacidade condensado na página do evento + texto de consentimento no formulário (PT/EN/ES, mobile-first). Gravação/uso de imagem: consentimento informado no ato (cross-ref #729). |

---

**Triggers para revisão antecipada**:
- Nova superfície adicionada ao schema com anon SELECT
- Mudança em LGPD ou regulamentação aplicável
- Solicitação de titular relativa a uma das superfícies
- Auditoria PMI Brasil ou ANPD

**Owner desta revisão**: PM (Vitor) + DPO (mesmo).

---

## Cross-references

- `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md` — Track R section
- `docs/adr/ADR-0010-wiki-scope-narrative-knowledge-only.md`
- `docs/adr/ADR-0014-log-retention-policy.md`
- `docs/adr/ADR-0024-public-members-view-accepted-risk.md`
- `docs/council/2026-04-26-tracks-qd-r-security-hardening-decision.md`
- `docs/BRIEFING_IVAN_QD_DISCLOSURE_26ABR2026.md`
- `/privacy` — Privacy policy pública para visitantes
