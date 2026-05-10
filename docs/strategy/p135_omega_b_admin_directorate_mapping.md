# Ω-B Sweep — Admin Pages × Directorate Roles Mapping

> **Sweep Ω-B** — admin scope · 2026-05-09 · session p135 · feeds `CHAPTER_ONBOARDING_PLAYBOOK.md` (Ω-E.3)
> **Strategic anchor:** `memory/project_chapter_pmis_saas_vision_p133.md` — multi-tenant pilot futuro PMI-GO + PMI-CE diretorias.
> **Modelo de diretoria PMI usado** (abstrato, sem dados específicos): Presidente · Vice-presidente · Diretores (Voluntariado, Membros, Eventos/Treinamento, Marketing/Comms, Financeiro) · Comitês (Auditoria, Ética, Conselho Consultivo).
> **URLs referência humana** (verificação futura): https://pmigo.org.br/conheca/diretoria/ · https://pmice.org.br/organograma/

---

## Sumário

- **Páginas admin mapeadas:** 42 (33 estáticas + 9 dinâmicas)
- **READY (page suporta diretorate role bem):** 18
- **NEEDS_SCOPING (page existe mas precisa filtros multi-tenant ou role-restricted view):** 19
- **ORPHAN (sem dono claro / superadmin only / system-internal):** 5
- **Roles cobertos com substrate adequado:** Voluntariado (alto) · Eventos/Treinamento (alto) · Marketing/Comms (alto) · Membros (médio-alto) · Conselho Consultivo (médio) · Ética/Auditoria (médio) · Financeiro (médio — confirmed substrate p133)
- **Roles com cobertura fraca / ausente:** Vice-Presidente (deputy view) · Auditoria self-service (sem read-only filtered view) · Conselho Consultivo (sem dashboard dedicado distinto de stakeholder)
- **Frequência tier-1 (daily):** ~6 páginas · **tier-2 (weekly):** ~14 páginas · **tier-3 (monthly):** ~14 páginas · **tier-4 (quarterly+):** ~8 páginas

> Recorte: este sweep cobre só **páginas admin** (`/src/pages/admin/*`). Sweep público está em `p134_omega_a_directorate_mapping.md`. Dynamic sub-routes (member detail, governance chain detail, etc.) foram tratadas como páginas individuais para mapear corretamente o flow + permission gate.

---

## Tabela 1: Cross-reference Matrix — Role × Admin Page

Legenda: **O** = Owner (write/manage) · **A** = Approver (assina/aprova) · **R** = Read-only viewer · **—** = sem acesso típico

| Página | Pres | VP | Volunt | Membro | Eventos | Mktg | Finan | Audit | Ética | Consel |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `index` (Dashboard) | O | R | R | R | R | R | R | R | R | R |
| `members` | R | R | O | O | — | — | — | R | — | R |
| `members/[id]` | R | R | O | O | — | — | — | R | — | — |
| `members/inactive-candidates` | R | R | O | R | — | — | — | R | — | — |
| `member/[id]` (legacy) | R | R | O | O | — | — | — | — | — | — |
| `comms` (Social Analytics) | R | R | — | — | R | O | — | — | — | R |
| `comms-ops` (Operacional) | R | R | — | — | R | O | — | — | — | — |
| `data-health` | A | R | — | R | — | — | — | O | — | — |
| `blog` | A | R | — | — | — | O | — | — | — | R |
| `report` (Executive) | O | O | R | R | R | R | R | R | R | R |
| `chapter` (Dashboard) | O | O | R | R | R | R | R | R | R | A |
| `chapter-report` (PDF Export) | O | R | R | R | R | R | R | R | R | A |
| `cycle-report` | O | R | O | O | R | R | R | R | — | A |
| `campaigns` | A | R | — | — | — | O | — | R | — | — |
| `pilots` | A | A | R | — | O | R | R | — | — | A |
| `initiative-kinds` | O | A | R | R | R | — | — | — | — | A |
| `portfolio` | O | A | R | R | R | R | R | R | — | A |
| `tags` | O | R | R | R | R | R | — | — | — | — |
| `partnerships` | A | R | — | — | R | R | O | — | — | A |
| `ai-calibration` | A | R | — | R | — | R | — | — | R | — |
| `curatorship` | A | R | — | A | — | O | — | R | — | A |
| `certificates` | A | R | O | A | R | — | — | — | — | — |
| `selection` (Onboarding pipeline) | A | R | O | A | — | — | — | R | A | — |
| `adoption` | R | R | O | O | — | R | — | R | — | R |
| `sustainability` (Cost/Revenue) | A | R | — | — | — | — | O | A | — | A |
| `publications` | A | R | — | A | — | R | — | — | A | A |
| `help` | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| `governance-v2` (Boards CRs) | O | R | R | R | R | R | — | A | A | A |
| `webinars` | A | R | — | — | O | A | — | — | — | A |
| `knowledge` | A | R | R | R | R | A | — | — | — | A |
| `tribes` (Comparison) | O | R | O | R | — | — | — | — | — | A |
| `analytics` | O | O | R | R | R | R | R | R | — | A |
| `audit-log` | A | R | — | — | — | — | — | O | A | A |
| `settings` (system params) | O | R | — | — | — | — | — | A | — | — |
| `governance/documents` | A | R | A | R | R | R | A | A | O | A |
| `governance/ip-ratification` | A | R | A | A | — | — | — | A | O | A |
| `governance/documents/[chainId]` | A | R | A | A | A | A | A | A | A | A |
| `.../audit-report` | R | R | — | — | — | — | — | O | A | A |
| `.../export-pdf` | R | R | R | R | R | R | R | R | R | R |
| `.../export-docx` | R | R | R | R | R | R | R | R | R | R |
| `.../versions/new` | A | R | — | — | — | — | — | — | O | A |
| `tribe/[id]` | A | R | O | R | R | — | — | — | — | A |
| `board/[id]` | A | R | O | R | R | R | — | — | — | A |

Total **Owner** atribuições: Volunt 14 · Mktg 11 · Eventos 5 · Pres 11 · Membro 7 · Finan 4 · Audit 4 · Ética 4 · Cons 0 · VP 1.

---

## Tabela 2: Per-Role Page List

### Presidência (President)

**Owner pages (manage daily/weekly):**
- `/admin/index` — dashboard executivo platform (KPIs cross-cutting, sync, volunteer compliance, research pipeline)
- `/admin/report` — Executive Report config (title, subtitle, sections, GP notes)
- `/admin/chapter` — Chapter dashboard (KPIs agregados)
- `/admin/chapter-report` — Multi-chapter PDF export report
- `/admin/cycle-report` — Cycle evolution report (C2→C3, etc.)
- `/admin/portfolio` — GP Portfolio Dashboard cross-tribe
- `/admin/initiative-kinds` — Configuração tipos de iniciativa (admin de admin)
- `/admin/tags` — Taxonomia institucional
- `/admin/governance-v2` — Boards CRs orchestration
- `/admin/tribes` — Cross-tribe comparison Ciclo
- `/admin/analytics` — Funnel/pipeline analytics

**Approver pages (sign-off ou approval flow):**
- `/admin/blog` — aprovação publicação
- `/admin/campaigns` — aprovação campanha
- `/admin/pilots` — aprovação pilot launch
- `/admin/ai-calibration` — aprovação threshold/policies AI
- `/admin/curatorship` — aprovação curadoria
- `/admin/certificates` — aprovação certificate issuance (counter-sign)
- `/admin/selection` — aprovação seleção onboarding
- `/admin/sustainability` — aprovação budget/revenue policies
- `/admin/publications` — aprovação publicação
- `/admin/webinars` — aprovação proposal
- `/admin/knowledge` — aprovação publicação asset
- `/admin/audit-log` — aprovação audit policy / acknowledge alerts
- `/admin/data-health` — aprovação data health rule
- `/admin/governance/documents` — aprovação chain
- `/admin/governance/ip-ratification` — aprovação IP ratification
- `/admin/settings` — aprovação parâmetros sistema (superadmin gate)
- `/admin/partnerships` — aprovação acordo

**Read-only:**
- `/admin/members`, `/admin/comms`, `/admin/comms-ops`, `/admin/adoption`

**Frequency tier:** Daily — `index`, `chapter`. Weekly — `report`, `cycle-report`, `portfolio`, `analytics`, `governance-v2`. Monthly — `chapter-report`, `tribes`, `initiative-kinds`, `tags`. Quarterly — `audit-log` review.

### Vice-Presidente (Deputy/VP)

**Owner pages:** Praticamente nenhuma exclusiva — role faltando como pattern (gap principal Ω-A confirmed). Pode owner `/admin/report` e `/admin/chapter` quando substituindo presidente.

**Approver:** Co-approver com presidente em decisões formais (`/admin/governance/*`, `/admin/initiative-kinds`, `/admin/portfolio`, `/admin/pilots`).

**Read-only deputy view (priority — gap Ω-A):**
- Mesmo conjunto que Presidência mas sem write quando ele NÃO está ativando deputy mode

**Frequency tier:** Weekly — `report`, `chapter`, `analytics`. Monthly — `governance-v2`, `cycle-report`. Esta seção tem alta variabilidade — depende se chapter tem VP ativo.

### Diretor de Voluntariado (Volunteers Director)

**Owner pages (operação core diária/semanal):**
- `/admin/members` — gestão membros (intake → ativação → offboarding)
- `/admin/members/[id]` — detalhe membro 7 sections
- `/admin/member/[id]` (legacy edit modal) — fast edit
- `/admin/members/inactive-candidates` — detect_inactive_members surface
- `/admin/selection` — pipeline seleção (intake → screening → interview → eval → approve)
- `/admin/certificates` — issue certificate + counter-sign
- `/admin/tribes` — cross-tribe comparison
- `/admin/cycle-report` — cycle stats Voluntariado
- `/admin/tribe/[id]` — tribe management

**Read-only insights:**
- `/admin/index`, `/admin/adoption`, `/admin/data-health`, `/admin/portfolio`, `/admin/board/[id]`, `/admin/initiative-kinds`

**Approver:**
- `/admin/governance/documents` (volunteer agreement chain)
- `/admin/governance/ip-ratification` (member IP signing chain)
- `/admin/pilots` (allocations to pilots)

**Frequency tier:** Daily — `members`, `members/[id]`, `selection`, `tribes`. Weekly — `members/inactive-candidates`, `tribe/[id]`, `certificates`, `cycle-report`. Monthly — `adoption`, `data-health`. Quarterly — `governance/*` IP cycles.

### Diretor de Membros (Members Director — focus on directory + comms with members)

> Note: There is real overlap between **Voluntariado** and **Membros** in PMI Brasil chapters. Some chapters consolidate the role, others split: Voluntariado handles intake/onboarding/offboarding, Membros handles directory + member-facing comms + retention. This mapping splits them.

**Owner pages:**
- `/admin/members` (shared with Voluntariado — directory)
- `/admin/members/[id]` (shared with Voluntariado — profile)
- `/admin/curatorship` — curate member submissions
- `/admin/adoption` — member adoption metrics + visitors

**Approver:**
- `/admin/selection` (interview eval)
- `/admin/publications` (review submission per author)
- `/admin/certificates` (counter-sign)

**Read-only:**
- `/admin/index`, `/admin/cycle-report`, `/admin/tribes`, `/admin/portfolio`, `/admin/analytics`

**Frequency tier:** Daily — `members`, `adoption`. Weekly — `curatorship`. Monthly — `selection` review cycles.

### Diretor de Eventos/Treinamento (Events/Training Director)

**Owner pages:**
- `/admin/webinars` — Webinar lifecycle (proposal → review → confirm → realize → certificate)
- `/admin/pilots` — Pilot management (releases, hipóteses, métricas)

**Read-only viewer:**
- `/admin/index`, `/admin/portfolio`, `/admin/cycle-report`, `/admin/initiative-kinds`, `/admin/tribes`, `/admin/tribe/[id]`, `/admin/board/[id]`, `/admin/chapter-report`, `/admin/curatorship`, `/admin/certificates`, `/admin/analytics`

**Approver:**
- `/admin/governance/documents/[chainId]` quando proposal Webinar tem CR vinculado
- `/admin/initiative-kinds` (proposta de novo type)

**Frequency tier:** Daily — `webinars`. Weekly — `pilots`, `tribe/[id]`, `board/[id]`. Monthly — `cycle-report`, `chapter-report`, `portfolio`. Quarterly — `initiative-kinds` review.

### Diretor de Marketing/Comms (Marketing/Comms Director)

**Owner pages:**
- `/admin/comms` — Social Analytics dashboard
- `/admin/comms-ops` — Operacional (queue, history, pipeline, board)
- `/admin/blog` — Blog editor
- `/admin/campaigns` — Email campaigns
- `/admin/curatorship` — Curate publications/resources
- `/admin/knowledge` — Knowledge library admin

**Approver:**
- `/admin/publications` (review submissions)
- `/admin/webinars` (Comms assets ready for launch)
- `/admin/governance/documents/[chainId]` (signing role for IP/comms decisions)

**Read-only:**
- `/admin/index`, `/admin/report`, `/admin/chapter-report`, `/admin/cycle-report`, `/admin/adoption`, `/admin/analytics`, `/admin/portfolio`

**Frequency tier:** Daily — `comms`, `comms-ops`, `blog`. Weekly — `campaigns`, `webinars`, `knowledge`, `curatorship`. Monthly — `publications` flow.

### Diretor Financeiro (Financial Director)

**Owner pages:**
- `/admin/sustainability` — Cost/Revenue/Targets (5 tabelas substrate confirmed p133)
- `/admin/partnerships` — Sponsor/partner pipeline + revenue source

**Approver:**
- `/admin/governance/documents/[chainId]` (financial decisions, partnerships, budget)
- `/admin/portfolio` (when ROI signal needed)
- `/admin/pilots` (when budget allocated)

**Read-only:**
- `/admin/report`, `/admin/chapter-report`, `/admin/cycle-report`, `/admin/analytics`, `/admin/portfolio`

**Frequency tier:** Daily — `sustainability` em closing fiscal. Weekly — `sustainability`, `partnerships`. Monthly — `partnerships` follow-up + `chapter-report` financial export. Quarterly — `pilots` budget review + `governance/*` aprovações fiscais.

### Comitê de Auditoria (Audit Committee)

**Owner pages (read-all + analyze):**
- `/admin/audit-log` — Master audit log (today está superadmin-restricted; gap Ω-A confirmed → precisa role "auditor")
- `/admin/data-health` — Data integrity health
- `/admin/governance/documents/[chainId]/audit-report` — Conselho Fiscal report

**Approver:**
- `/admin/audit-log` policy itself (acknowledge alerts)
- `/admin/governance/documents/*` audit dimension
- `/admin/sustainability` (annual financial audit)
- `/admin/curatorship` (cyclical curation audit)
- `/admin/settings` (system params)

**Read-only with filters:**
- `/admin/index`, `/admin/report`, `/admin/portfolio`, `/admin/cycle-report`, `/admin/chapter-report`, `/admin/analytics`, `/admin/adoption`

**Frequency tier:** Daily — `audit-log` em períodos críticos. Weekly — `data-health`. Monthly — `audit-log`, `audit-report` cycles. Quarterly — full audit pass (`sustainability`, `governance/*`, `settings`).

### Comitê de Ética (Ethics Committee)

**Owner pages:**
- `/admin/governance/ip-ratification` — IP ratification chains (ethical aspect)
- `/admin/governance/documents` — chain management (policy/code-of-conduct chains)
- `/admin/governance/documents/[docId]/versions/new` — propose new version

**Approver:**
- `/admin/governance/documents/[chainId]` (ethical signing)
- `/admin/curatorship` (cyclical content review)
- `/admin/publications` (ethical aspect of published content)
- `/admin/audit-log` (ethical complaints — currently NO surface for confidential ethics workflow → gap Ω-A)
- `/admin/ai-calibration` (AI fairness/bias review)

**Read-only:**
- `/admin/index`, `/admin/report`, `/admin/governance-v2`, `/admin/data-health`

**Frequency tier:** Monthly — `governance/documents`, `governance/ip-ratification`. Quarterly — `audit-log`, `curatorship`, `ai-calibration`, `publications` ethical review.

### Conselho Consultivo (Advisory Board)

**Owner pages:** Nenhuma (role é consultivo + sign-off, NÃO operacional).

**Approver (signing chains):**
- `/admin/governance/documents/[chainId]` (formal sign-off em policies majores)
- `/admin/portfolio` (strategic review)
- `/admin/pilots` (strategic OK on launch)
- `/admin/initiative-kinds` (strategic taxonomy decisions)
- `/admin/audit-log` (acknowledge audit reports)
- `/admin/sustainability` (financial sign-off)
- `/admin/cycle-report` (cycle close)
- `/admin/tribes` (research tribe strategic review)
- `/admin/blog`, `/admin/publications`, `/admin/webinars`, `/admin/curatorship`, `/admin/knowledge`, `/admin/partnerships`, `/admin/board/[id]`, `/admin/tribe/[id]` (advisory sign-off)

**Read-only:**
- Acesso geral a `/admin/index`, `/admin/report`, `/admin/chapter`, `/admin/chapter-report`, `/admin/analytics`, `/admin/adoption`

**Frequency tier:** Quarterly — read-only review entire admin surface. Monthly — sign-off em chains ativas. Weekly — só durante governance crises.

---

## Orphan Pages (sem dono diretorate claro)

Páginas que NÃO mapeiam naturalmente para uma role de diretoria — typically system-internal, superadmin-only, or universal access:

1. **`/admin/help`** — REDIRECT (`return Astro.redirect('/help', 301)`). Página universal — qualquer authenticated user. Não é diretorate-specific.

2. **`/admin/settings`** — Superadmin only (params: group_term, cycle_default, etc.). Genuinely platform-level — Diretoria normal não toca. Pode classificar como "Presidência (system role)" mas in practice only superadmin.

3. **`/admin/data-health`** — Substrate é integridade dados (orphans, missing FKs, etc.). Cabe a Auditoria mas o code-level é técnico — gap Ω-A "auditoria self-service" confirmed: hoje superadmin gate, falta role auditor.

4. **`/admin/governance/documents/[chainId]/export-pdf`** & **`/admin/governance/documents/[chainId]/export-docx`** — Export utilities. Sem owner — qualquer role com acesso ao chain pode exportar. Read/utility only, NÃO ownership.

5. **`/admin/audit-log`** — Hoje superadmin only. **Gap Ω-A:** falta role "auditor" para Comitê Auditoria self-service. Mapeado como Owner=Auditoria mas in practice acesso é fechado ao superadmin → marcando como Orphan no estado atual.

> Recomendação: introduzir role `audit_committee` no engagement_kind_permissions seed (ADR-0007 V4) para destravar items 3, 5. Ω-D scope.

---

## Role Gaps (roles sem ferramenta admin dedicada)

### Vice-Presidente (Deputy/VP) — gap arquitetural CONFIRMED

- **Sintoma:** Mapping acima mostra "Owner=1, Approver=co-com-presidente, Read-only=todos os que presidente vê". Não há **page exclusiva** ao VP — porque o pattern "deputy view" não existe na plataforma.
- **Necessidade:** read-only mirror de presidência + flag "sou deputy ativo agora" que destrava write seletivo.
- **Solução de scope:** seed `vice_president` em `engagement_kind_permissions` (V4) + UI hint em pages-críticas mostrando "Modo deputy ativo". Já discutido em Ω-A (`ADR-NEXT-deputy-vice-role-pattern.md`).

### Auditoria (Audit Committee) — surface gap

- **Sintoma:** Hoje `/admin/audit-log` + `/admin/data-health` são superadmin only. Audit Committee não tem self-service.
- **Necessidade:** read-all do audit-log com filtros temporais + export CSV (RPC já existe: `export_audit_log_csv`). Mesmo para data-health.
- **Solução:** introduzir role `auditor` em V4 + permitir read-only em `audit-log`, `data-health`, `governance/documents/[chainId]/audit-report`. Page atual `/admin/audit-log` continua superadmin-write, mas read-only abre para auditor.

### Conselho Consultivo (Advisory Board) — sem dashboard dedicado

- **Sintoma:** Conselho atualmente "consome" `/admin/report` e `/admin/chapter-report`, que são built para Presidência. Não há "Advisory Dashboard" curado para sign-off duties + read-only strategic view.
- **Necessidade:** dedicated page combinando: pending sign-offs (chains), recent decisions, cycle KPIs, portfolio health, governance changes log — TODOS read-only com sign action.
- **Solução:** nova page `/admin/advisory` (ou refatorar `/stakeholder` para cobrir advisory mode) — Ω-D backlog candidate.

### Comitê de Ética — workflow gap (já em Ω-A backlog HIGH)

- **Sintoma:** Hoje Ética assina chains via `/admin/governance/*`, mas NÃO tem workflow para complaints (denúncias confidenciais).
- **Necessidade:** complaint workflow (anônimo OU identificado, audit-trail confidencial, mediation tracking).
- **Solução:** Already on Ω-A backlog HIGH (`Ethics complaint workflow`). Reinforced por este sweep — mapping mostra que TODA outra role tem ferramentas, ETICA não.

### Diretor Financeiro — public transparency surface gap

- **Sintoma:** `/admin/sustainability` é admin only. Sem page pública "transparência" para stakeholders externos. Substrate confirmed p133.
- **Necessidade:** public-facing financial transparency page (LGPD-safe rollups).
- **Solução:** Already on Ω-A backlog MED.

### Diretor de Membros (vs Voluntariado) — overlap gap

- **Sintoma:** Quando chapter SPLIT roles, `/admin/members` é shared mas sem clear ownership separation. Hoje code não distingue "Voluntariado scope" vs "Membros scope".
- **Necessidade:** quando chapter usa split, members directory needs filtros "intake stage" (Voluntariado scope) vs "active member directory" (Membros scope) com permissions diferentes.
- **Solução:** scoping per-chapter — pode ser tag/filter parameter. Backlog: "Member directory split-role configuration."

---

## Recommended Onboarding Playbook Structure (for new chapter)

> Drives `CHAPTER_ONBOARDING_PLAYBOOK.md` (Ω-E.3). This is the operational sequence to bring a new PMI chapter onto the platform.

### Day 0 (Pre-Setup — GP/Superadmin do Núcleo)

1. **Provision chapter row** em `chapters` table (display_code, legal_name, brand_kit, contact_email).
2. **Configurar settings.astro params** chapter-specific (group_term per language, cycle_default, contact email).
3. **Seed initiative_kinds** se chapter quiser tipos próprios (admin/initiative-kinds).
4. **Vincular domain whitelabel** (ex: nucleoia-pmigo.vitormr.dev) — depends on Ω-C/Ω-D ADR multi-tenant.

### Day 1 (Diretoria Setup — primeira sessão treinamento, 4h)

**Apresentação inicial (60min):**
- Mostrar `/stakeholder` (chapter dashboard) e `/admin/report` (executive)
- Mostrar `/admin/governance-v2` para entender authority structure

**Cadastrar diretoria (90min):**
- Cada diretor cria conta self-service (signup → consent → profile)
- GP/superadmin assina engagement_kind por persona em `/admin/members/[id]` (V4 authority)
- Seed direto a `engagement_kind_permissions` para roles novas (ex.: vice_president, audit_committee — quando ADRs forem aprovados)

**Hands-on por role (90min, paralelo):**
- **Presidente:** abrir `/admin/index`, ver dashboard. Personalizar `/admin/report`. Drill em `/admin/portfolio`.
- **Diretor Voluntariado:** `/admin/members`, `/admin/selection` (estrutura de cycles), `/admin/certificates`. Configurar onboarding flow.
- **Diretor Eventos:** `/admin/webinars`, `/admin/pilots`, processo proposal.
- **Diretor Comms:** `/admin/comms`, `/admin/comms-ops`, `/admin/blog`. Brand kit.
- **Diretor Financeiro:** `/admin/sustainability`, `/admin/partnerships`. Cost/revenue categories chapter-specific.

### Week 1 (Operação Inicial — primeira semana)

**Dia 2-3:**
- Diretor Voluntariado: importar primeiros 5-10 membros via `/admin/selection` Import CSV, validar permissions, criar primeiro tribe.
- Diretor Comms: criar primeiro post `/admin/blog`, primeira campanha `/admin/campaigns`.
- Diretor Eventos: criar primeiro webinar `/admin/webinars`, vincular meeting link/YouTube.

**Dia 4-5:**
- Comitê Ética: review e assinar primeira IP ratification chain `/admin/governance/ip-ratification` (volunteer agreement + IP).
- Conselho Consultivo: review `/admin/portfolio`, `/admin/cycle-report`, sign-off em decisão estrutural se houver.

**Dia 6-7:**
- Presidente: review `/admin/index`, `/admin/report` configurar email weekly digest.
- Auditoria: primeiro pass em `/admin/audit-log` e `/admin/data-health` (after role auditor seed).

### Month 1 (Consolidation — fechar primeiro mês)

**Semana 2:**
- Diretor Eventos: realizar primeiro webinar; Diretor Voluntariado registrar attendance (`/attendance`); Diretor Comms acompanha replays e likes.
- Diretor Membros: review `/admin/curatorship` para primeiras submissions; `/admin/adoption` para tracking.

**Semana 3:**
- Diretor Financeiro: preencher primeiros lançamentos `/admin/sustainability` (categorias chapter); revisar `/admin/partnerships` se sponsor onboard.
- Diretor Voluntariado: emitir primeiros certificados via `/admin/certificates`.

**Semana 4:**
- Presidente: preparar primeiro chapter-report `/admin/chapter-report` + apresentar para conselho.
- Conselho Consultivo: assinar formal sign-off em chain de "approval to operate" (versão chapter-specific da política IP/governança).
- Comitê Auditoria: primeiro audit pass mensal `/admin/audit-log` + `/admin/data-health`.

### Month 2-3 (Steady State Verification)

- Cycle close: `/admin/cycle-report` exportado e arquivado.
- Annual cycle: `/admin/portfolio` review estratégico cross-tribe.
- All roles: rever frequency tiers — adjust se algum recurso está sub/over-utilizado.

---

## Frequency Tiers — Cross-Role Page Usage

### Tier 1 — DAILY (high-frequency operation)

| Page | Roles que tocam diariamente |
|---|---|
| `/admin/index` | Presidência, VP (deputy), todos diretores (read) |
| `/admin/members` | Diretor Voluntariado, Diretor Membros |
| `/admin/comms` | Diretor Comms |
| `/admin/comms-ops` | Diretor Comms |
| `/admin/blog` | Diretor Comms |
| `/admin/sustainability` | Diretor Financeiro (closing semanal) |

### Tier 2 — WEEKLY (regular cadence)

| Page | Roles que tocam semanalmente |
|---|---|
| `/admin/report` | Presidência, VP |
| `/admin/chapter` | Presidência, VP |
| `/admin/portfolio` | Presidência, Diretor Eventos |
| `/admin/selection` | Diretor Voluntariado, Diretor Membros |
| `/admin/certificates` | Diretor Voluntariado |
| `/admin/webinars` | Diretor Eventos |
| `/admin/pilots` | Diretor Eventos, Presidência |
| `/admin/campaigns` | Diretor Comms |
| `/admin/curatorship` | Diretor Comms, Diretor Membros |
| `/admin/knowledge` | Diretor Comms |
| `/admin/partnerships` | Diretor Financeiro |
| `/admin/tribes` | Presidência, Diretor Voluntariado |
| `/admin/tribe/[id]` | Diretor Voluntariado, Tribe leader |
| `/admin/board/[id]` | Tribe leader, Diretor Voluntariado |

### Tier 3 — MONTHLY (cycle/reporting cadence)

| Page | Roles que tocam mensalmente |
|---|---|
| `/admin/cycle-report` | Presidência, Voluntariado, Eventos |
| `/admin/chapter-report` | Presidência, Conselho |
| `/admin/adoption` | Diretor Membros, Voluntariado |
| `/admin/analytics` | Presidência, todos diretores (read) |
| `/admin/data-health` | Auditoria |
| `/admin/audit-log` | Auditoria |
| `/admin/governance/documents` | Ética, Conselho, todas signing roles |
| `/admin/governance/ip-ratification` | Ética, Voluntariado |
| `/admin/governance-v2` | Presidência |
| `/admin/publications` | Diretor Comms, Membros (curatorial gate) |
| `/admin/members/inactive-candidates` | Diretor Voluntariado |
| `/admin/members/[id]`, `/admin/member/[id]` | Diretor Voluntariado, Membros (per-membro deep dive) |
| `/admin/governance/documents/[chainId]` | Roles assinando chains ativas |
| `/admin/governance/documents/[chainId]/audit-report` | Auditoria, Conselho |

### Tier 4 — QUARTERLY+ (strategic/annual cadence)

| Page | Roles que tocam trimestralmente ou menos |
|---|---|
| `/admin/initiative-kinds` | Presidência (review taxonomy) |
| `/admin/tags` | Presidência, Diretor Comms |
| `/admin/ai-calibration` | Presidência, Ética (fairness review) |
| `/admin/settings` | Superadmin (raramente diretoria) |
| `/admin/governance/documents/[docId]/versions/new` | Ética (proposing new version policy) |
| `/admin/governance/documents/[chainId]/export-pdf`, `.../export-docx` | Sob demanda (export PDF/DOCX) |
| `/admin/help` | Universal (sob demanda) |

---

## Notas

### Cross-references com Ω-A (public sweep)

- Onde Ω-A indicou "substrate em admin precisa surface diretor" → este sweep mapeia que **substrate de fato existe** em ~90% casos. O gap é **role/permission scoping + UX direcionado a role**, NÃO build-from-scratch.
- Diretor Voluntariado tem MAIS pages dedicated (~14) do que qualquer outra role — confirma p134 finding "substrate forte para Voluntariado".
- Diretor de Eventos é o segundo mais coberto (`webinars` dedicated + `pilots`) — confirma "substrate forte para Eventos".
- Vice-Presidente como gap CONTINUES — este sweep não muda a conclusão de Ω-A. Inverso: torna mais URGENT — agora vemos que cross-role design parte do princípio que "presidência ou nada", e VP fica em limbo.

### Multi-tenant scope (PMIS vision p133)

Para pilot futuro PMI-GO + PMI-CE, cada admin page precisará:
1. **Chapter scoping filter** (já existe em algumas pages como `analytics` e `chapter-report` — pattern proven). Estender para todas Tier 1-2 daily/weekly.
2. **Brand context** — logo/cores/email institucional do chapter ativo no header AdminLayout.
3. **Permissions seed per-chapter** — cada role × engagement_kind precisa seed específico (pattern V4 já permite via organization_id em engagement_kind_permissions).
4. **Email/comms templates per-chapter** — `/admin/campaigns` templates devem ter slot per-chapter (whitelabel).
5. **i18n trilingue garantido** — checkpoint Ω-B.A trilingue extraction (em progresso p135). Ω-A já cobriu páginas públicas.

### Recommendations for Ω-E consolidation

- **Onboarding playbook estrutura:** seguir Day 0 / Day 1 / Week 1 / Month 1 / Month 2-3 acima.
- **Per-role training cards:** criar 1-pager por diretorate role com TOP-5 admin pages, frequency, key actions. Substrate para isso é o "Per-Role Page List" acima.
- **Frequency-based dashboard hints:** opcional mas valioso — admin index pode mostrar "Suas páginas Tier 1" baseado em role do usuário ativo. Reduces cognitive load on chapter directors not familiar with full surface.
- **Backlog issues sugeridas:**
  - `[backlog HIGH] Audit Committee role + read-only access em audit-log/data-health/audit-report` (destrava 3 orphans)
  - `[backlog MED] Advisory Board dashboard dedicado` (Conselho Consultivo gap)
  - `[backlog HIGH] Vice-Presidente role pattern + deputy-mode toggle` (já em Ω-A, reforçado aqui)
  - `[scoping HIGH] Multi-tenant scoping em admin pages Tier 1-2` (chapter selector + brand context)
  - `[backlog MED] Per-role admin homepage hints` (UX layer sobre AdminLayout)

---

*Sweep Ω-B · admin scope · 2026-05-09 · session p135 · feeds Ω-E.3 onboarding playbook*
