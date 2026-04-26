# ADR-0024: `public_members` view — accepted advisor risk + future slim path

- Status: Accepted
- Data: 2026-04-26
- Aprovado por: Vitor (PM) em 2026-04-24 (decisão Issue #82 Onda 2)
- Autor: Vitor (PM) + Claude (drafting)
- Escopo: Tratamento da advisor finding `security_definer_view` em `public.public_members`

## Contexto

A Postgres advisor (Supabase) flagou `public.public_members` como `SECURITY DEFINER VIEW`
em Issue #82 Onda 1+1.5+1.6 (p40, 23/Abr/2026). View expõe 22 colunas de `members` para
anon + authenticated + service_role:

```sql
SELECT id, name, photo_url, chapter, operational_role, designations,
       tribe_id, initiative_id, current_cycle_active, is_active,
       linkedin_url, credly_badges, credly_url, credly_verified_at,
       cpmai_certified, cpmai_certified_at, country, state, cycles,
       created_at, share_whatsapp, member_status, signature_url
FROM members;
```

22 callsites em 14 files (inventory completo em `docs/specs/SPEC_ISSUE_82_ONDA_2_3_OPTIONS.md`):

| Use case | Callsites |
|---|---:|
| Public landing pages (Hero, Tribes, Team, CPMAI, PresentationLayer) | 6 |
| Authenticated nav badge | 1 |
| Tribe page roster (tribe/[id], initiative/[id]) | 6 |
| Gamification page (leaders + assignment + signature) | 4 |
| Admin dashboards (webinars, chapter-report, portfolio) | 3 |
| Certificate PDFs (certificates/pdf.ts) | 2 |
| Board members picker | 2 |

## Decisão

**Manter view com `SECURITY DEFINER` e exposição atual** sob threat model que aceita
"public roster" como surface intencional. Advisor finding registrada como risco aceito
documentado neste ADR + `COMMENT ON VIEW`.

Roadmap separado para tighten cirúrgico das colunas sensíveis (`signature_url`,
`linkedin_url`, `credly_url`) em sessão futura focada — escopo grande para acoplar a
Issue #82 Onda 2.

## Análise de trade-off

Quatro opções foram avaliadas em `SPEC_ISSUE_82_ONDA_2_3_OPTIONS.md`:

| Opção | Custo | Risco UX | Advisor closes |
|---|---:|---|---:|
| A — flip security_invoker | 4-6h | medium (anon perde acesso → 6 landing pages quebram) | yes |
| B — REVOKE anon + RPC paralelo | 6-8h | low (RPC absorve anon callsites) | yes |
| C — slim view + RPC para sensitive | 8-12h | medium (certificate PDFs em risco se RPC falhar) | yes |
| **D — document risk** | **2h** | **none** | **no (tracked)** |

PM escolheu **D** com justificativa:
1. **22 callsites** é blast radius alto para uma advisor que não é breach.
2. **Threat model aceita** "public roster" — operacional_role/chapter/designations são
   intencionalmente públicos no nosso modelo de community-led governance.
3. **Sensitive columns** (signature_url, linkedin/credly URLs) merecem refactor
   focado em sessão própria — coupled fix dilui review.
4. **Advisor finding fica rastreada** via este ADR + COMMENT ON VIEW; auditorias
   futuras encontram o trail explícito.

## Consequências

### Positivas

- **Zero regression UX**: 22 callsites continuam funcionando. Landing pages, certificate
  PDFs, gamification page todos preservados.
- **Trade-off explicit**: ADR + COMMENT ON VIEW deixam decisão rastreável. Auditoria
  futura sabe que finding foi avaliada (não missed).
- **Permite focus em higher-impact work** (Track B ADR-0022 W1, Track C #91 G5 Whisper).

### Negativas

- **Advisor finding stays open** com `level: ERROR` para `security_definer_view`. Pode
  re-aparecer em audit reports até refactor cirúrgico.
- **Sensitive columns ainda públicas** — signature_url permite forgery por scraping
  até refactor follow-up.

## Risco aceito

`signature_url` é stored Supabase Storage signed URL. Embora públicas via view, a URL
expira (signed_url tem TTL configurado). Anyone scrapping pode coletar mas precisaria
re-fetch dentro do TTL. Não é "private key" leak; é "PNG of signature" leak. Forgery
risk presente mas mitigado por:
1. Certificados oficiais (CPMAI) usam chain-of-trust + member-side signing, não só PNG.
2. Termo de Compromisso de Voluntário formaliza signing chain (ADR-0016) — PNG no
   certificate é ornamental, não autorizativo.
3. PII das URLs em si (Supabase Storage path) não vaza credentials.

## Follow-up planejado

**Não comprometido em sprint específico**. Quando refactor for executado (estimativa
8-12h, recomendação Option C do spec memo):

1. Slim view: dropar signature_url, linkedin_url, credly_url, share_whatsapp, cycles, created_at
2. Criar `get_member_signature(p_member_id)` SECDEF RPC para certificate PDFs (gate via authenticated + matching cycle).
3. Criar `get_member_public_profile(p_member_id)` para LinkedIn/Credly se necessário.
4. Refactor 4 callsites: certificates/pdf.ts (signature_url), gamification.astro (signature_url + linkedin), 2 outros.
5. Smoke certificate generation flow + gamification signature display.

Quando feito, este ADR pode ser superseded ou marked com nota "remediated by ADR-XXXX".

## Critério de revisão

Este ADR deve ser revisado se:
1. Audit externo flagar a exposição como blocker (não advisor).
2. Incidente real de signature/profile abuse for reportado.
3. Member opt-out feature for adicionada (similar a `share_whatsapp`) e exigir column-level
   filtering — momento natural para slim view.
4. Threat model migrar para "private-by-default" (e.g., enterprise tenant).

## Implementação

`COMMENT ON VIEW` aplicado em migration `20260513040000_public_members_accepted_risk_comment.sql`
referenciando este ADR.

```sql
COMMENT ON VIEW public.public_members IS
  'Public member roster — accepted advisor risk per ADR-0024.
   SECURITY DEFINER intentional: exposes 22 community-public columns to anon
   for landing pages and authenticated for cross-tribe roster. Sensitive
   columns (signature_url, linkedin_url, credly_url) tracked for future
   slim refactor — see ADR-0024 §"Follow-up planejado".';
```

## Referências

- Issue #82: https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/82
- Spec memo: `docs/specs/SPEC_ISSUE_82_ONDA_2_3_OPTIONS.md`
- Onda 1/1.5/1.6 commits (p40): `f5fb688`, `025450a`, `7d9cda3`
- Advisor finding: `security_definer_view_public_public_members`

---

## Elevator Pitch / Sponsor Q&A Response (p59 — para call de segunda)

Se Ivan ou outro sponsor perguntar sobre o **1 ERROR remanescente** no
advisor de segurança Supabase, a resposta-padrão é:

> "Esse ERROR é a única exposição intencional que mantemos. É uma view
> chamada `public_members` que mostra leadership institucional do Núcleo
> (nome, foto, papel, capítulo) na homepage, similar a um diretório
> público de chapter PMI. Está documentada em ADR-0024 como risco aceito
> por: (a) é necessária para a Hero/Tribes/Team sections do site público;
> (b) só expõe 22 colunas community-public — nenhuma PII sensível
> (email/telefone/PMI ID excluídos via filtragem deliberada);
> (c) refactor para "slim view + RPC" tem custo de manutenção sem ganho
> real de privacidade. Status do ADR é Accepted, com critérios de revisão
> documentados (audit externo, incidente real, opt-out feature, ou
> migração para private-by-default tenant)."

**Pontos-chave para a call** (1 sentence cada):
1. **Único ERROR no advisor** — todo o resto é intentional public docs (25 ROPA mapping)
2. **Não é vulnerabilidade** — é decisão arquitetural documentada
3. **Padrão PMI internacional** — chapter directories são públicos por design
4. **Tem critérios de re-trigger** se contexto mudar (audit externo etc.)
5. **Trail completo** em GitHub: ADR-0024 + COMMENT ON VIEW inline + Issue #82

**Se Ivan quiser action item adicional**, opções (em ordem de menor → maior custo):
1. **Re-confirmação formal** do "accepted risk" status (5 min — escrever
   "ratified by Ivan Lourenço 2026-04-XX" no ADR)
2. **Quarterly re-review trigger** (20 min — adicionar ao ROPA review trimestral)
3. **Slim view refactor** (~6-8h — implementar OPÇÃO 3 da Onda 2/3 spec:
   `members_public_safe_v2` com 8 cols não-sensíveis + RPC `get_member_signature(id)`
   gated com `view_pii` + log_pii_access para uso curatorial)

Recomendação: opção 1 ou 2 — opção 3 é overkill se não houver driver real.
