# LGPD ROPA — Public Surfaces (Núcleo IA)

> **Records of Processing Activities (Art. 37 LGPD)** para superfícies
> de dados intencionalmente públicas da plataforma Núcleo IA.
> Documenta para cada superfície: base legal (Art. 7), categoria de
> dado (Art. 5), finalidade, retenção, titulares, e destinatários.
>
> **Escopo**: 24 tabelas/views + 1 função preservadas com anon SELECT
> grant após Track R Phase R3 (p59) + 1 função PII (`get_gp_whatsapp`)
> com inline LGPD comment. Total: **25 superfícies**.
>
> **Atualizado**: 2026-04-26 (p59)
> **Próxima revisão**: trimestral (cadência sponsor touchpoint)
> **Sponsor**: PMI-GO (Ivan Lourenço, Presidente)
> **Encarregado de Dados (DPO)**: Vitor Maia Rodovalho
> (vitor.rodovalho@outlook.com — contato listado em `/privacy`)

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

## Resumo por base legal

| Base legal Art. 7 | Quantidade de superfícies | Lista |
|---|---|---|
| **V (execução de contrato)** | 5 | public_publications, public_members, members_public_safe, gamification_points, tribe_selections, get_gp_whatsapp |
| **V + IX (combinada)** | 5 | (mesmas acima — predominante para PII institucional) |
| **IX (legítimo interesse) — apenas** | 19 | Todas as outras (operacional, agregado, reference) |

**Predominância Art. 7, IX** reflete natureza voluntária + transparente
do Núcleo IA. Onde há PII, Art. 7, V documenta o termo de voluntariado
como base contratual.

---

## Categorias por sensibilidade

| Sensibilidade | Quantidade | Treatment |
|---|---|---|
| **Não-PII / agregado / referência** | 18 | Anon access OK — risco zero |
| **PII institucional (nome, papel, foto)** | 5 | Anon access OK per consent + termo |
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
| Revogação de consentimento (Art. 18, IX) | Offboarding via `offboard_member` ⇒ remove engagements ⇒ removes from public_members |

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

**Trilha imutável**: GitHub commits assinados (`2ff39e8`, `ca072c8`).

---

## Próxima revisão

**Cadência**: trimestral, alinhada com sponsor touchpoint (PMI-GO).
**Próxima revisão**: 2026-07-26 (próximo trimestre Q3).

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
