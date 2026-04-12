# ADR-0004: Multi-Tenancy Posture — Organizations as First-Class

- Status: Accepted
- Data: 2026-04-11
- Aprovado por: Vitor (PM) em 2026-04-11
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Modelo de Domínio V4 — Decisão 1/6

## Contexto

A plataforma nasceu como produto single-tenant para o Núcleo IA & Gerenciamento de Projetos (hospedado no PMI Goiás). O roadmap declarado pelo PM exige que a plataforma evolua para:

1. **Referência nacional** — Núcleo escalando para 5+ capítulos federados (GO, CE, DF, MG, RS e novos).
2. **Plataforma reutilizável** — outros projetos voluntários poderão usar a base para gerenciar suas próprias iniciativas (ex.: AI PM Compass, PMI-WDC initiative, futuros projetos).
3. **LGPD defensável por fronteira organizacional** — dados de uma organização não podem vazar para outra, mesmo em caso de bug em RLS.

Hoje `chapter` é um campo `text` em `members`, e a identidade "Núcleo IA" é implícita (não existe linha em lugar nenhum). RPCs, RLS policies e gates assumem um único dono de dados. Isso fecha a porta para multi-org sem refactor retroativo.

Adiar a decisão é o único erro irrecuperável da refatoração V4: as outras decisões (initiative, person, authority, lifecycle, config) podem ser migradas incrementalmente; multi-tenancy retroativo é cirurgia de coração em todas as tabelas simultaneamente.

## Decisão

1. **Adotar `organizations` como entidade first-class** da plataforma. Toda tabela de domínio ganha `organization_id uuid NOT NULL REFERENCES organizations(id)` (com default inicial apontando para a org "Núcleo IA" durante migração).
2. **Toda RPC nova recebe `p_org_id uuid`** (com fallback para a org do caller quando omitido), e toda RLS policy nova filtra por `organization_id = auth_org()`.
3. **`chapters` passa a ser entidade filha de `organization`** — um capítulo pertence a uma org. Núcleo IA tem 5 capítulos federados (PMI-GO, CE, DF, MG, RS). PMI-WDC seria outra org com seu próprio capítulo.
4. **OAuth / MCP audience inclui `org_id`** — o JWT emitido identifica o usuário e a org ativa. Usuários com acesso a múltiplas orgs alternam via parâmetro.
5. **Implementação em fases** — adicionar coluna + default + backfill + policies em uma fase dedicada (F1 do refactor), **antes** de qualquer outra decisão arquitetural começar. Não aceitar qualquer nova migration sem `organization_id` a partir do commit que aprovar este ADR.

## Consequências

**Positivas:**
- Porta aberta para plataforma multi-org sem refactor retroativo catastrófico.
- RLS com uma segunda camada de defesa em profundidade (`organization_id` + `operational_role/engagement`).
- Export LGPD por organização vira query natural.
- Auditoria cruzada impossível por design (outro org nunca vê dados do Núcleo).

**Negativas / custos:**
- Todo código existente que hoje assume single-org precisa ser auditado. Custo estimado: alto mas mecânico, não criativo.
- Migrações V4 Phase 1 bloqueiam outras features até consolidar.
- Complexidade adicional em testes (fixtures precisam de multiple orgs).

**Neutras:**
- Por enquanto só existe 1 org (Núcleo IA). A infraestrutura fica pronta sem usuários finais imediatos para multi-tenancy.

## Alternativas consideradas

- **(A) Continuar single-tenant com `chapter text`** — rejeitado por fechar roadmap nacional/multi-projeto.
- **(B) Multi-tenant só no schema (prefix de tabela por org)** — rejeitado por fragmentar consultas cross-org (relatórios agregados, benchmarks).
- **(C) Row-level multi-tenancy com `organization_id` (escolhida)** — maior flexibilidade, RLS nativa do Postgres.

## Relações com outros ADRs

- Pré-requisito de ADR-0005 (Initiative), ADR-0006 (Person), ADR-0007 (Authority).
- Não substitui ADR-0001 (Source of Truth) nem ADR-0002 (Role Model V3) — complementa.

## Critérios de aceite

- [ ] Tabela `organizations` criada com linha inicial para "Núcleo IA & GP"
- [ ] `chapters` virou entidade com FK para `organizations`
- [ ] Todas tabelas de domínio com `organization_id NOT NULL` + backfill
- [ ] Helper `auth_org()` disponível em RLS policies
- [ ] RPCs novas recebem `p_org_id` (ou usam `auth_org()`)
- [ ] Testes fixture-based com 2 orgs de exemplo
- [ ] MCP OAuth carrega `org_id` no JWT
