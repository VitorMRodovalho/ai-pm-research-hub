# Product Leader — p134 Ω-A Final Synthesis & Roadmap Recommendation

**Date:** 2026-05-09
**For:** PM Vitor decision
**Inputs:** 5 sub-agent strategy reports + 11 council perspectives + 5 web research deep-dives + strategic anchors (handoff_p134, project_chapter_pmis_saas_vision_p133, project_multi_client_architecture_principle, feedback_trilingue_full_system_not_just_data)

---

## TL;DR

Ω-A deve fechar esta sessão com o escopo cirúrgico que UX Leader e Senior Engineer validaram: 5 páginas críticas de i18n (4-6h) + composite DB index (30min) + doc refresh README/INDEX (30min). Tudo mais entra em gates formais pré-piloto. A razão é simples: trilingue nas páginas críticas é o único entregável que desbloqueia TRÊS demo windows simultâneas (Natália PMI Latam, LIM Lima 13-Ago, CPMAI Latam Sep-Oct) com esforço de uma tarde. Os 7 ADRs multi-tenant são reais e urgentes, mas misturá-los com Ω-A mata atomicidade do diff e atrasa demo unblocking que é gating event estratégico. **Trade-off explícito**: aceita que PMI-CE pilot ainda não pode começar esta semana — mas chega no LIM com site trilingue funcional e whitepaper honesto, em vez de chegar com nada funcionando. **Dois riscos vivos** que não podem ficar no backlog genérico: RLS `USING(true)` nas tabelas financeiras expõe dados HOJE (Data Architect RF-1), e curador Roberto tem 5 comentários abertos criando audit trail de "problemas conhecidos não resolvidos na expansão" (Accountability red flag).

---

## Decisão #1 — Escopo Ω-A esta sessão

**Recomendação:** Opção B — Cirúrgica 5 páginas críticas + composite index + doc refresh. NÃO tentar 25 páginas com hardcoded.

**Scope exato:**

| Entregável | Esforço | Criticidade |
|---|---|---|
| `governance/glossario.astro` — lang fix + 14 chrome keys | 1.5h | Demo PMI int'l quebra hoje |
| `settings/notifications.astro` — zero t(), ~20 strings | 1.5h | Blocker pós-onboarding loop |
| `onboarding.astro` — 20 keys + mailto cross-chapter | 1.5h | Perda candidato PMI-CE D1 |
| `teams.astro` — 8-10 keys | 1h | Diretor Voluntariado entry-point |
| `profile.astro` — LGPD confirm PT em fluxo irreversível | 4-6h | Risco legal LGPD + alto tráfego |
| `events (type, date DESC)` composite index CONCURRENTLY | 30min | 10x I/O reduction homepage hero |
| README.md 13 stat fixes + `docs/INDEX.md` rewrite | 30min | Credibilidade institucional |
| `docs/adr/README.md` — ADR-0076 entry | 5min | Pendência tracking |

**Total estimado: 10-12h trabalho real. Candidato a 2 sessões se profile.astro atrasar.**

**O que Ω-A NÃO faz:**
- NÃO toca `attendance.astro` (2197L — defer Ω-B)
- NÃO aplica 180 i18n keys das páginas Medium/Low (defer Ω-B)
- NÃO migração DB org_id em cost/revenue (é ADR-F, own sprint)
- NÃO whitelabel/branding hardcoded (requer ADR-NEW-B Ω-E)
- NÃO fiscal docs (requer DPA + ADR-0079)

**Commits esperados:**
1. `feat(p134 Ω-A.1): trilingue wrappers /en/ /es/ ausentes` (Phase A — mechanical, 0 wrappers ausentes confirmado)
2. `feat(p134 Ω-A.2): i18n 5 critical pages + glossario lang fix + onboarding mailto`
3. `perf(p134 Ω-A.3): idx_events_type_date CONCURRENTLY`
4. `docs(p134 Ω-A.4): README stats + INDEX rewrite + ADR-0076 entry`

**Rationale:** UX Leader confirmou que 2 blockers mais perigosos são structural (lang hardcoded + zero t()), não volume. Corrigir esses 5 pages = 80% demo-readiness com 40% esforço. Senior Engineer validou estimativas. GP Leader Stakeholder Persona disse glossario PT para membro espanhol convidado é "vergonha institucional" — feedback concreto de quem vai usar. LIM Lima 13-Ago fixada — site PT-only é risco credibilidade documentado c-level.

---

## Decisão #2 — Sequência pós Ω-A (p135 → p140+)

**Roadmap em 6 ondas:**

| Onda | Sessão | Escopo | Gate entrada | Entrega estratégica |
|---|---|---|---|---|
| **Ω-B** | p135 | Trilingue admin (42 pages) + attendance.astro + 5 inline-dict files | Ω-A clean | Site trilingue 100% (demo-ready LIM) |
| **Ω-C** | p136 | UI dashboards (ARM-12 Observability, ARM-1 funnel) | Ω-B clean | PMIS demo + stakeholder chapter dashboard |
| **Ω-D** | p137 | Newsletter Frontiers (#96, owner Fabricio) | Ω-C clean | ARM-10 Communication 2.8→3.0 |
| **Ω-E.1** | p138 | ADR-F financial org_id + RLS RF-1 fix | ADR log entries criados | Bloqueia PMI-CE financial pilot |
| **Ω-E.2** | p139 | ADR-NEW-A URL routing path-first + ADR-NEW-B brand schema + organization_settings | ADR-F shipped | Chapter whitelabel MVP |
| **Ω-E.3** | p140 | ADR-NEW-C contact emails + CHAPTER_ONBOARDING_PLAYBOOK + CHAPTER_GOVERNANCE_CONTINUITY | Ω-E.2 clean | Pilot PMI-CE pode começar |

**ADRs — ordem com dependências:**

```
ADR-F (financial org_id) → ADR-NEW-A (URL routing) → ADR-NEW-B (brand schema)
                                                     → ADR-NEW-C (contact emails)
ADR-NEW-A → ADR-NEW-D (per-chapter MCP) [post-ADR-0076 sign-off]
ADR-NEW-B → ADR-NEW-E (per-chapter privacy policy) [legal-counsel co-sign mandatory]
ADR-NEW-B → ADR-NEW-G (i18n chapter-aware) [chapter sign-off mandatory]
ADR-NEW-A + ADR-0079 (NF-e cert) → ADR-0078 (internal ticketing)
```

**Rationale sequencing:** Ω-E.1 NÃO em paralelo Ω-A — atomicidade diff crítica. Senior Eng + Data Arch unânimes. ADR-NEW-A URL routing pre-condition TUDO multi-tenant — c-level marcou "pre-condition todas demo windows". Startup Advisor "kill scenario simultaneous". ADR-NEW-G i18n chapter-aware (150+ keys) é XL + chapter sign-off — último cadeia.

---

## Decisão #3 — Commercial action (VC/Angel challenge)

**Recomendação:** Aceitar lógica VC/Angel, REJEITAR timing esta sessão. Agendar para janela específica pós-Ω-A.

**Por que aceitar lógica:** VC/Angel correto que zero receita após 43 membros + 15 chapters seeded = core commercial risk. "Trilingue gera zero receita" factualmente verdadeiro. Startup Advisor + GP Leader confirmam financeiro cross-chapter primeiro bloqueador adoção real.

**Por que rejeitar timing:** Proposta paid pilot PMI-GO/CE agora, antes de ADR-F + whitelabel básico, coloca Vitor em posição de prometer o que ainda não existe tecnicamente. GP Leader explícito: "não assino sem branding básico". Propor contrato antes de gates técnicos mínimos = queimar relacionamento primeiro cliente potencial.

**Ação recomendada (pós-Ω-E.1):** Proposta formal written PMI-GO paid pilot em paralelo com Ω-E.2. Framing: "operational cost recovery R$299-499/mo" (Startup Advisor pricing), não "SaaS fee". Zero pressão. Get written response.

**O que pode acontecer agora sem esperar Ω-E:** Perguntar a Natália diretamente próxima interação: "Vocês exportam attendance via API ou planilha manual? Recordings vão para YouTube ou ficam no Airmeet?" Pergunta design partner research Airmeet — custo zero, informa integration depth, abre conversa sem comprometer comercialmente.

---

## Decisão #4 — NFeWizard-io vs node-sped-nfe vs TransmiteNota

**Recomendação:** Adotar REST API direct `nfse.gov.br` como caminho primário. NFeWizard-io DESCARTADO. node-sped-nfe é fallback limitado. TransmiteNota é safety net.

| Opção | Status | Razão |
|---|---|---|
| NFeWizard-io GPL-3.0 | DESCARTADO definitivo | Requer JDK + filesystem = incompatível Workers. Debate licença nem se coloca — tecnicamente impossível. ADR-0079 documenta descarte por incompatibilidade técnica, não só licença. |
| node-sped-nfse (kalmonv) | FALLBACK NÃO RECOMENDADO | 8 stars, zero releases, 16 commits. Não confiável produção fiscal. Referência implementação, nunca dependência. |
| REST API direct `nfse.gov.br` | ADOTAR | mTLS via Cloudflare Workers `mtls_certificates` binding game-changer confirmado pesquisa. PFX A1 funciona. Workers Paid plan requerido. MVP <4 semanas. |
| PlugNotas/NFE.io | SAFETY NET | Se complexidade XMLDSIG inviabilizar REST direct MVP <4 sem, SaaS emissão fallback. Fee ~R$0.50-2.00/nota mas elimina complexidade técnica signing. |

**Pré-requisitos inegociáveis antes NFS-e produção (Accountability Gate 2):**
1. DPA Núcleo (operador) ↔ chapter (controlador) via Ângelina
2. UI fiscal disclaimer: "Responsabilidade fiscal pela NFS-e/NFC-e emitida é inteiramente do capítulo como pessoa jurídica"
3. Cert A1 stored Supabase Vault (ADR-0077 opção A), NÃO coluna readable, NÃO env vars
4. Chapter fiscal responsibility terms aceitos UI antes primeira emissão
5. `admin_audit_log` entry cada `nfe_cert_accessed`

**ADR a criar: ADR-0079** (NF-e cert storage + library choice + DPA requirement).

---

## Decisão #5 — Sympla strategy

**Recomendação:** Hybrid Phase 1 (ingestion API read-only, R$0) → Phase 2 (internal RSVP/waitlist, zero payment, zero NF-e) → Phase 3 (direct payment + NFS-e) sequencial com gate explícito.

| Phase | O que faz | Pré-requisito | Quando |
|---|---|---|---|
| **Phase 1 — NOW** | Sympla API `GET /events/{id}/participants` → match `members.email` → popula attendance automaticamente. Custo R$0. | Nenhum — API read-only token estático | Ω-C ou Ω-D |
| **Phase 2 — Ω-E.3** | Internal RSVP + waitlist + PMI member discount. Sympla parallel para pagamento. Núcleo captura subscriber data. | ADR-F financial + ADR-0078 internal ticketing scope | pós-Ω-E.2 |
| **Phase 3 — H2 2026** | Direct payment + NFS-e auto-emission. Gate: 1 evento Phase 2 validado PMI-GO. | NFS-e REST direct + DPA + Cert A1 + ADR-0078 completo | pós-gate |

**Gate explícito Phase 2 → Phase 3 (Startup Advisor week-8):** Chapter usou Phase 2 ≥1 evento? N registrations visíveis painel? Sim → proceed. Não → entender razão antes construir stack pagamento.

**Por que não construir tudo agora:** Sympla replacement full-stack antes ADR-F financial = dados single-tenant commingled = LGPD violation. Startup Advisor "kill scenario #1". GP Leader: diretora Eventos não migraria até ver beta rodando evento baixo risco primeiro.

**Economia para pitch:** 5 chapters × 3 paid events × R$8K avg Sympla fee = R$120K/ano eliminados quando Phase 3 completo. Número para Financeiro Director. Use como pitch, NÃO como projeção receita.

---

## Decisão #6 — Airmeet posture

**Recomendação:** Integrate NÃO compete. HÍBRIDO Zoom + Airmeet seletivo. NÃO construir integração completa antes Natália confirmar design partnership.

- **Zoom:** manter tribe weekly meetings. Barato, funciona, recording flow OK. NÃO tocar.
- **Airmeet:** adotar seletivamente CPMAI Latam + Detroit Summit + LIM-class. 3-4 eventos/ano onde engagement + multilingue + brand quality justificam custo.
- **Recording purge 60d:** constraint crítico research. Mirror para YouTube unlisted dentro 7 dias após cada evento. Encaixa workflow token-gated existente.
- **Interprefy:** tradução simultânea add-on ~$500-1000/dia, não native Airmeet. Orçar separadamente Detroit/LIM.

**O que construir e quando:**

| Integração | Esforço | Quando | Gate |
|---|---|---|---|
| Webhook `registrant.added` → Núcleo `event_attendance` | M | Ω-D/E | Natália confirmar API access |
| Certificate auto-emit pós attendance Airmeet | M | Ω-E | Substrate webinars + ADR-0078 |
| Recording sync → YouTube + token-gated | M | Ω-E | 60d purge workaround |

**O que NÃO construir ainda:** Full attendee management via Airmeet API (Startup Advisor risco #2 — 2 sprints stranded se Natália não comprometida). Aguardar resposta design partner antes alocar.

**PMI Latam piggyback opportunity:** PMI Latam Enterprise license Airmeet desde 2020 (2000 attendees). Se Núcleo integrar como parceiro CPMAI Latam, pode piggyback sem custo próprio. Perguntar Natália: "Podemos incluir integração Airmeet caso uso whitepaper Detroit?" Custo zero pergunta, upside alto.

**Airmeet vs Sympla prioridade:** GP Leader claro — Sympla > Airmeet em urgência adoção chapter. Honrar.

---

## Decisão #7 — Multi-tenant ADR sequencing

**Recomendação:** 7 ADRs em 3 grupos com dependências explícitas. Nenhum entra antes do decision log estar criado.

**Grupo 1 — Pré-piloto (Ω-E.1, p138):**

| ADR | Escopo | Complexidade | Depende |
|---|---|---|---|
| **ADR-F (=ADR-0080)** | `cost/revenue/sustainability_kpi_targets` org_id + RLS RF-1 fix | L | Decision log entry criado |
| **ADR-0079** | NF-e cert storage + library choice | M | Security-engineer sign-off + Ângelina DPA review |

**Grupo 2 — Whitelabel MVP (Ω-E.2, p139):**

| ADR | Escopo | Complexidade | Depende |
|---|---|---|---|
| **ADR-NEW-A** | URL routing Phase 1 path-first `/org/[slug]/` | M | Nenhum (decisão arquitetura pura) |
| **ADR-NEW-B** | Brand schema: `chapter_brand_config` jsonb + CSS `[data-chapter]` selector override | M | ADR-NEW-A |
| **ADR-NEW-C** | Contact emails per-chapter via `organization_settings` | S | ADR-NEW-B + `site_config` migration |

**Grupo 3 — Post-pilot (Ω-E.3+, p140+):**

| ADR | Escopo | Complexidade | Depende |
|---|---|---|---|
| **ADR-NEW-D** | Per-chapter MCP (JWT org_id claim) | M | ADR-0076 Wave 4 Ivan DPO sign-off |
| **ADR-NEW-E** | Per-chapter privacy policy | M | Legal-counsel co-sign + PMI-CE DPO formal |
| **ADR-NEW-G** | i18n chapter-aware overrides | XL | ADR-NEW-B + chapter sign-off |
| **ADR-0078** | Internal ticketing module | XL | ADR-F + NFS-e Phase 2 gate |

**Multi-tenant architecture decision:** Single Supabase project + JWT org_id claim + RLS row-per-tenant. NÃO schema-per-tenant, NÃO database-per-tenant. Limite ~50 chapters confortável. Research confirmou schema-per-tenant quebra past 500 tenants e impossibilita cross-org analytics Detroit/LIM/Latam.

**URL routing Phase 1:** Path-first `/org/[slug]/`. Zero DNS work, single Worker, Astro v6 SSR friendly. Subdomain quando primeiro paying chapter solicitar. Custom domain enterprise tier only.

---

## Decisão #8 — Hard blockers ESCALATE backlog

Itens NÃO entram Ω-A mas precisam gates formais, NÃO backlog genérico.

| Item | Severidade | Gate | Label |
|---|---|---|---|
| `cost/revenue` sem `organization_id` — RLS `USING(true)` expõe financial HOJE | CRITICAL | Pré-Ω-E.1 | `blocks PMI-CE pilot (financial)` |
| `supabase.ts` FALLBACK hardcoded `ldrfrvwhxsmgaabwmaik` | HIGH | Pré-chapter-2 | `blocks multi-tenant isolation` |
| `middleware.ts` CANONICAL_HOST hardcoded | HIGH | Pré-ADR-NEW-A | `blocks whitelabel routing` |
| `anonymize_rejected_applicants` sem `p_organization_id` | MED | Pré-chapter-2 | `LGPD cross-org scope` |
| `pii_access_log` sem `org_id` accessor/target | MED | Pré-chapter-2 | `LGPD Art. 37 ROPA` |
| Governance PDFs `PMI-GO` footer (`ChainPDFDocument.tsx:377,390,519,548`) | HIGH | Pré-pilot-PMI-CE | `blocks pilot legal docs` |
| `mcp_usage_log` sem `organization_id` | HIGH | Pré-ADR-NEW-D | `cross-org analytics indistinguishable` |
| `nucleo-guide` prompt hardcoded chapter list literal | MED | Pré-ADR-NEW-D | `blocks MCP multi-tenant` |
| DPA Núcleo↔chapter — NÃO existe | CRITICAL | Pré-qualquer-chapter-externo | `LGPD Art. 42 joint controller` |
| `revenue_entries` sem `event_id` FK | HIGH | ADR-F sprint | `per-event P&L impossible` |
| `sustainability_kpi_targets` UNIQUE(cycle, kpi_name) | HIGH | ADR-F sprint | `blocks second chapter immediately` |

**Ação:** criar GitHub Issues individuais com labels esta semana, antes Ω-B começar.

---

## Decisão #9 — CHAPTER_ONBOARDING_PLAYBOOK + governance continuity

**Recomendação:** Criar 2 docs antes Ω-E.3 (pré-pilot PMI-CE). NÃO antes — sem ADRs base não há o que documentar.

**CHAPTER_ONBOARDING_PLAYBOOK.md** (C-Level red flag):
- Provisioning script novo org_id
- Chapter admin role seed
- Whitelabel config mínimo
- PMI VEP sync per chapter
- Checklist Day 1 / Week 1 / Month 3 (GP Leader já articulou)

**CHAPTER_GOVERNANCE_CONTINUITY.md** (Accountability red flag):
- Admin transfer procedure (diretoria entry/exit)
- Data obligations per chapter (LGPD, governance, financial)
- Financial year-end reconciliation
- Minimum viable handover audit trail
- Referência DISASTER_RECOVERY.md + RUNBOOK.md existentes

**Justificativa:** PMI chapters trocam diretoria anualmente. Sem este documento, Núcleo torna-se dependência que chapter não consegue transferir. Bloqueador adoção que NÃO é feature — é governança operacional.

---

## Decisão #10 — Decision log entries (governance compliance)

**Recomendação:** Criar entries em `docs/council/decisions/` para todos 7 ADRs com status "Proposed" ANTES de qualquer código tocar componente. Accountability confirmou exigência governance compliance, não formalidade.

| Arquivo | ADR | Status inicial |
|---|---|---|
| `2026-05-09-adr-f-financial-org-id.md` | ADR-F (=ADR-0080) | Proposed |
| `2026-05-09-adr-0079-nfe-cert-storage.md` | ADR-0079 | Proposed |
| `2026-05-09-adr-new-a-url-routing.md` | ADR-NEW-A | Proposed |
| `2026-05-09-adr-new-b-brand-schema.md` | ADR-NEW-B | Proposed |
| `2026-05-09-adr-new-c-contact-emails.md` | ADR-NEW-C | Proposed |
| `2026-05-09-adr-new-d-mcp-multitenant.md` | ADR-NEW-D | Proposed (blocked ADR-0076) |
| `2026-05-09-adr-new-e-privacy-per-chapter.md` | ADR-NEW-E | Proposed (blocked legal-counsel) |
| `2026-05-09-adr-new-g-i18n-chapter-aware.md` | ADR-NEW-G | Proposed (blocked ADR-NEW-B) |
| `2026-05-09-adr-0078-internal-ticketing.md` | ADR-0078 | Proposed (blocked ADR-F + NFS-e gate) |

**Quando criar:** pode ser Ω-A close ou início Ω-E, mas ANTES de qualquer code commit tocar middleware/financial/MCP/i18n-bundle.

---

## Trade-offs explícitos

**O que prioriza:**
- Demo windows sobre pilot técnico. LIM 13-Ago e CPMAI Sep-Oct são datas fixas. Trilingue funcional chega tempo; pilot técnico PMI-CE não chegaria mesmo se começar hoje.
- Atomicidade de diff. Cada onda revertível. Misturar i18n com org_id migration com ADR routing em uma sessão = diff irreversível invalida testes regressão.
- Receita sequenciada sobre receita imediata. Propor paid pilot antes whitelabel básico queima primeiro cliente potencial.

**O que sacrifica:**
- Velocidade pilot PMI-CE. Sequência proposta = pilot técnico PMI-CE provavelmente p139-p140 (ago-set). VC/Angel corretamente aponta 3 meses zero receita nova. Aceitável porque alternativa é onboard chapter sem isolamento financial = LGPD violation = consequência pior.
- Feature velocity nas 20 páginas Medium/Low i18n. Ficam Ω-B. Nenhuma bloqueia demo windows.
- Airmeet integration antes confirmação. Perguntar Natália primeiro antes alocar sprint. 2-3 semanas espera resposta. Aceitável porque stranded sprint custaria mais.

---

## Justificativa estratégica

**Preservação optionality Trentim (A/B/C):**

- **Path A (PMI internal):** Trilingue Ω-A unlock imediato. Sem ES funcional, demo Natália é PT-only = contexto perdido reunião LATAM multilíngue. C-Level: "Path A APROXIMADO por 33 READY pages + trilingue". Single-host blockers FECHAM Path A enquanto não resolvidos — gate Ω-E.2.
- **Path B (consulting):** Sub-agents C/D/E geraram deliverables consulting prontos: directorate needs mapping table, gap multi-tenant severities, tool replacement roadmap ROI, NFS-e research Workers mTLS discovery. C-Level: "artifacts são deliverables consulting prontos". Em `docs/strategy/` + `docs/research/` IP reutilizável.
- **Path C (community):** Trilingue = community-growth blocker. Com Ω-A fechado, contribuidor ES pode navegar sem context loss. Startup Advisor: "Natalia incident (Vargas 'ação PMI') = brand bleed organic when product good" — produto precisa estar bom primeiro.

**Demo windows criticality:**

- **LIM Lima 13-Ago (session #747 accepted):** Tighter constraint. Site trilingue + directorate cross-ref table (Agent D output) appendix verbatim whitepaper = apresentação concreta. Sem Ω-A: apresentação PT-only audiência LATAM multilíngue.
- **Detroit/LIM (Sep-Oct 2026):** Highest stakes. Narrative risk: "multi-client gap" 40 items, mas framing correto = "roadmap honesto com substrate 33 pages READY". Agent D directorate mapping artefato central pitch.
- **CPMAI Latam multi-país:** Frequência maior. `/cpmai.astro` precisa funcionar ES. Página com mais frequência visita audiência internacional.

**Game-changers não-óbvios:**

1. **Cloudflare Workers mTLS binding** NFS-e: o que parecia XL é agora L (REST direct via mtls binding). Muda completamente ROI Sympla replacement Phase 3. Não estava radar antes research Wave 2.
2. **PMI Latam Enterprise Airmeet customer desde 2020:** piggyback via parceria CPMAI Latam pode eliminar custo licença. Pergunta a Natália pode unlocar isso. Custo zero pergunta.
3. **Data Architect RF-1 (RLS USING(true) financial):** qualquer membro autenticado pode hoje `SELECT * FROM cost_entries` via PostgREST direct. NÃO é multi-tenant — é exposição single-tenant TODAY. Finding precisa ser escalado como bug, NÃO roadmap item.

---

## Risk gates por milestone

**Gate 1 — Ω-A close:**
- `npx astro build` clean + `npm test` 0 failures
- Smoke trilingue: `/governance/glossario` PT/EN/ES sem `lang="pt-BR"` hardcoded
- `settings/notifications` renderiza t() em EN e ES sem fallback PT
- `/onboarding` sem `mailto:nucleoia@pmigo.org.br` hardcoded
- EXPLAIN ANALYZE confirma `idx_events_type_date` em uso planner

**Gate 2 — Pré-LIM (13-Ago):**
- Ω-A + Ω-B completos (trilingue admin incluído)
- directorate cross-ref table (Agent D) integrado whitepaper draft
- 33 READY pages navegáveis EN/ES sem context loss

**Gate 3 — Pré-chapter-2 deploy:**
- ADR-F shipped (cost/revenue/kpi_targets org_id + RLS RF-1 fix)
- `supabase.ts` FALLBACK removido ou env var obrigatório
- CANONICAL_HOST dinâmico (ADR-NEW-A shipped)
- DPA template redigido (Ângelina)
- CHAPTER_ONBOARDING_PLAYBOOK.md criado
- Roberto curator open comments resolvidos (Gate 0 Accountability)

**Gate 4 — Pré-fiscal module:**
- ADR-0079 accepted (cert storage + DPA + UI fiscal terms)
- NFS-e sandbox testado com cert real
- DPA chapter ↔ Núcleo assinado PMI-CE

**Rollback plan Ω-A:** i18n é somente código + dicionários, sem DB. Rollback = `git revert` 2 commits. Zero risco dado perdido. DB index CONCURRENTLY safe e reversível com `DROP INDEX CONCURRENTLY`.

---

## Decision points marcados PM

PM precisa confirmar/negar explicitamente:

1. **Escopo Ω-A:** Aprovar Opção B (cirúrgica 5 pages) OU preferir tentar 25 pages (13-21h)? Se 25 pages, aceita vazar p135?
2. **Commercial action timing:** Aprovar defer paid pilot proposal pós-Ω-E.2 (p139)? OU quer iniciar conversa comercial informal PMI-GO agora, mesmo sem whitelabel?
3. **Pergunta a Natália:** Autorizar perguntar Airmeet API access + attendance export próxima interação? Posiciona Núcleo design partner não cliente.
4. **Workers Paid plan:** Confirmar se projeto já está em Workers Paid (necessário mTLS bindings). Se não, decisão antes ADR-0079.
5. **Roberto curator:** Confirmar se quer escalar resolução 5 comentários abertos antes Ω-E (Gate 0) OU aceita seguir expansão com audit trail "pendência conhecida".
6. **ADR-NEW-A URL routing:** Confirmar preferência naming: path `/org/[slug]/` com redirect `/` → `/org/nucleo-ia-gp/` OU manter single-tenant URL até pilot real? Impacta SEO e refactoring scope.
7. **DPA Ângelina:** Autorizar briefar Ângelina sobre DPA template ainda em Ω-E.1? Async, pode andar paralelo sprints técnicos.

---

## Open questions to escalate

1. **Ivan DPO sign-off ADR-0076 Wave 4:** Status atual desconhecido. Desbloqueia ADR-NEW-D. Vitor verificar antes p139.
2. **Airmeet tier PMI Latam:** Exato tier desconhecido. Pode ser Enterprise (2000 attendees). Resposta Natália informa custo piggyback.
3. **Workers Paid plan status:** Não confirmado inputs. mTLS binding requer Paid plan.
4. **Roberto Macedo 5 comentários abertos:** Status comentários específicos Política IP v2.7 + Termo Voluntário. Vitor resolver assincronamente.
5. **Ângelina revisão §15.4:** Mecanismo "ciência prévia" como substituto consentimento expresso — pendência legal não técnica. Vitor acionar.
6. **TAM validação:** VC/Angel flagou Wild Apricot pricing + comparables UNVALIDATED (WebFetch bloqueado). Antes pitch Detroit, validar pricing real. Visitar site diretamente OU perguntar chapter treasurer PMI que usa.

---

## Anti-recommendations (NÃO fazer mesmo se tentado)

1. **NÃO misturar ADR-F financial com Ω-A i18n.** Senior Eng + Data Arch + C-Level + Startup Advisor unânimes. Atomicidade diff é carga real — se algo quebrar, não saberá o que.
2. **NÃO propor paid pilot PMI-GO/CE antes whitelabel básico pronto.** GP Leader explícito: "não assino sem branding básico". Primeiro evento dando errado = "perda confiança equipe + participantes meses recuperar".
3. **NÃO usar NFeWizard-io.** Incompatível Workers razões técnicas (JDK), independente questão licença GPL-3. Debate licença irrelevante — software não roda.
4. **NÃO registrar cost_entries sem org_id após ADR-F.** Data Architect: write-path SECURITY DEFINER bypassa RLS — após backfill, qualquer INSERT sem org_id no SECURITY DEFINER body corromperia silenciosamente dados multi-chapter.
5. **NÃO construir integração Airmeet completa antes Natália confirmar design partnership.** Startup Advisor: 2 sprints stranded se ela não comprometida.
6. **NÃO linkar ADR-NEW-D (per-chapter MCP) antes ADR-0076 Wave 4 fechar.** Accountability: "ADR-NEW-D afeta LGPD Art. 7 IX base legal scope (ADR-0076 pending Wave 4). Don't finalize until ADR-0076 closes."
7. **NÃO implementar `get_member_homepage_bundle()` composite RPC em Ω-A.** Senior Engineer explícito: premature optimization, blast radius marginal benefit. One sub-query failure = total bundle failure.
8. **NÃO construir Sympla replacement full-stack antes Phase 1 API ingestion validar.** Kill scenario confirmado Startup Advisor.
9. **NÃO onboar chapter externo sem DPA.** Legal: "DPA por chapter ANTES pilot PMI-CE = MANDATORY". Accountability: "NF-e cert A1 = chapter legal signing credential — breach = chapter-level legal event".
10. **NÃO citar Hopin como comparable em nenhuma apresentação.** VC/Angel confirmou: Hopin UK liquidation Feb 2024. Citar empresa liquidada em pitch Detroit = credibilidade destruída.

---

## Execution plan se decisões aprovadas

**Esta sessão (assumindo PM aprova Opção B):**

```
Sequência recomendada (10-12h):

1. Phase A: re-audit fresh /en/ /es/ wrappers ausentes (45min)
   → 0 wrappers ausentes confirmado já feito esta sessão
   → commit "feat(p134 Ω-A.1): trilingue wrappers /en/ /es/ ausentes" (no-op se 0 missing)

2. Phase B core — 5 páginas críticas (7-8h):
   → glossario lang fix + 14 chrome keys (1.5h)
   → settings/notifications ~20 keys (1.5h)
   → onboarding 20 keys + mailto fix (1.5h) — VERIFICAR interpolação t({var}) antes
   → teams 8-10 keys (1h)
   → profile LGPD confirm + toasts + fallbacks (4-6h) — TESTAR 3 langs browser antes commit
   → commit por página ou 2 commits agrupados

3. DB index (30min):
   → CREATE INDEX CONCURRENTLY idx_events_type_date ON events(type, date DESC);
   → NOTIFY pgrst, 'reload schema';
   → Verificar EXPLAIN ANALYZE
   → commit "perf(p134 Ω-A.3): idx_events_type_date"

4. Docs refresh (30min):
   → README.md 13 stat fixes (Edit tool por Edit tool — NÃO sed)
   → docs/INDEX.md full rewrite (Write tool)
   → docs/adr/README.md ADR-0076 entry (1 linha)
   → .claude/rules/mcp.md linha 9: 283→284
   → commit "docs(p134 Ω-A.4): README stats + INDEX rewrite + ADR-0076 entry"

5. Quality gates (30min):
   → npx astro build
   → npm test
   → smoke curl /governance/glossario /en/governance/glossario /es/governance/glossario

6. Push + handoff p135 (30min):
   → push origin/main
   → criar handoff_p135_omega_b_boot.md com boot prompt Ω-B
   → atualizar MEMORY.md sediment Ω-A close
```

**Sessão p135 (Ω-B):**
- Trilingue admin (42 pages) — mesmo padrão 5-agent sweep escopo admin/
- `attendance.astro` 2197L — isolated sprint
- 5 inline-dict files migração para global bundles
- Parity test upgrade (key-by-key name equality)

**Sessão p138 (Ω-E.1):**
- ADR-F migration: Phase A (nullable + backfill) → verificação → Phase B (NOT NULL + UNIQUE fix)
- RLS RF-1 fix: `cost_entries` + `revenue_entries` policies
- `revenue_entries` FK parity: `event_id` + `submission_id`
- `sustainability_kpi_targets` UNIQUE constraint fix
- ADR-0079 rascunho

---

## Referências carregadas nesta síntese

- `docs/strategy/p134_omega_a_i18n_extraction.md` (566L)
- `docs/strategy/p134_omega_a_docs_audit.md` (436L)
- `docs/strategy/p134_omega_a_multi_client_gaps.md` (323L)
- `docs/strategy/p134_omega_a_directorate_mapping.md` (260L)
- `docs/strategy/p134_omega_a_tools_opportunities.md` (299L)
- `docs/council/p134_omega_a_council_consolidated.md` (620L — 11 council perspectives)
- `docs/research/p134_sympla_landscape.md` (154L)
- `docs/research/p134_airmeet_landscape.md` (253L)
- `docs/research/p134_nfse_nacional_2026.md` (362L)
- `docs/research/p134_chapter_mgmt_best_practices.md` (307L)
- `docs/research/p134_multitenant_saas_patterns.md` (462L)
- `memory/handoff_p134_omega_a_trilingue_boot.md`
- `memory/project_chapter_pmis_saas_vision_p133.md`
- `memory/project_multi_client_architecture_principle.md`
- `memory/feedback_trilingue_full_system_not_just_data.md`

---

**Total inputs synthesized:** 4244 lines across 11 documents + 4 memory anchors.

**Synthesis date:** 2026-05-09
**Next: PM decision on 7 marked decision points → execute Ω-A close OR adjust scope.**
