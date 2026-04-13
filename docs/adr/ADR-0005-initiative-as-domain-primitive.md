# ADR-0005: Initiative como Primitivo do Domínio

- Status: Accepted
- Data: 2026-04-11
- Aprovado por: Vitor (PM) em 2026-04-11
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Modelo de Domínio V4 — Decisão 2/6

## Contexto

Hoje o domínio tem `tribes` como unidade de trabalho privilegiada (8 tribos fixas, `tribe_id` referenciado em board_items, meeting_notes, events, members, etc). Funciona para tribos de pesquisa — mas o Núcleo e a plataforma estão crescendo para abrigar outros tipos de trabalho coletivo:

- **Grupo de Estudos Preparatório CPMAI** (Herlon/Pedro Henrique) — tem tabelas `cpmai_*` dedicadas, ou seja, foi modelado como caso especial
- **Congresso CBGPL 2026** — tratado como evento + comitê ad-hoc, sem contêiner formal
- **Workshops pontuais** — sem modelo
- **Book clubs / reading groups** — sem modelo
- **Comitê de Change Requests** — hoje distribuído em board + designations

Cada "coisa nova" hoje exige migration + código + RPCs dedicadas. Isto é incompatível com a meta de ser plataforma reutilizável: cada nova org ou novo tipo de iniciativa vira um fork do modelo.

## Decisão

1. **Introduzir `initiatives` como a entidade raiz** para qualquer agrupamento durável de trabalho voluntário com governança. Tribos de pesquisa, grupos de estudo, congressos, workshops, book clubs — todos são `initiatives` com `kind` diferente.
2. **`initiative_kind` é uma configuração**, não código. Uma tabela `initiative_kinds` define os tipos válidos com suas propriedades (lifecycle, termo template, campos customizados, duração padrão). Ver ADR-0009.
3. **`tribes` vira uma view materializada de `initiatives WHERE kind = 'research_tribe'`**. Campos hoje em `tribes` (name, focus, etc) migram para `initiatives.title` + `initiatives.metadata jsonb` (para campos kind-específicos).
4. **`tribe_id` em todas as FKs do domínio é renomeado para `initiative_id`** via alias + migração em fases. Durante a transição, mantém-se uma view de compat `tribes` apontando para a view materializada.
5. **Cada iniciativa tem `organization_id` obrigatório** (cf. ADR-0004) e opcionalmente `parent_initiative_id` para hierarquias (ex: congresso → comitê de programa).
6. **Board, meeting_notes, events, deliverables** passam a se ancorar em `initiative_id` (já que tribo é um kind de initiative). Não há mudança de semântica para quem usa hoje via tribe.

## Consequências

**Positivas:**
- Novos tipos de iniciativa não exigem migration — manager cria via UI (ADR-0009).
- CPMAI, congresso, workshops, book clubs caem no mesmo modelo.
- Relatórios agregados por tipo de trabalho viram naturais (`GROUP BY kind`).
- Hierarquia de sub-iniciativas modelada (congresso → track → palestra).
- Onboarding de nova org vira: criar org → configurar kinds → criar initiatives.

**Negativas / custos:**
- Refactor grande em tabelas que hoje usam `tribe_id`: retrofit em board_items, meeting_notes, events, deliverables, e todas RPCs correspondentes.
- Testes existentes que fixture "tribe with id 1-8" precisam migrar para "initiative of kind research_tribe".
- Dashboards que hoje assumem 8 tribos fixas precisam tolerar variabilidade.

**Neutras:**
- Semanticamente, uma tribo continua sendo uma tribo — o conceito não muda. A implementação é que generaliza.

## Alternativas consideradas

- **(A) Manter `tribes` especial + tabelas dedicadas por tipo** (CPMAI já começou assim) — rejeitado: explosão de casos especiais e migrations.
- **(B) Criar `projects` genérico como peer de `tribes`** — rejeitado: fragmenta o modelo, dois contêineres paralelos.
- **(C) Initiative como primitivo único (escolhida)** — unifica e permite extensão via config.

## Relações com outros ADRs

- Depende de ADR-0004 (tenancy) — `initiatives.organization_id`
- Referenciado por ADR-0006 (Person/Engagement) — engagements apontam para initiative
- Referenciado por ADR-0007 (Authority) — permissões escopadas por initiative
- Referenciado por ADR-0008 (Lifecycle) — lifecycle varia por `initiative_kind`
- Referenciado por ADR-0009 (Config-driven) — kinds são config

## Critérios de aceite

- [x] `initiatives` + `initiative_kinds` tabelas criadas com seed inicial (8 tribos) — `20260413200000`, `20260413210000`. CPMAI + congresso pendentes (Fase 6).
- [ ] View materializada `tribes` apontando para `initiatives WHERE kind='research_tribe'` — **POSTERGADO Fase 7** (17 FKs impedem conversão agora)
- [x] FKs em board_items, meeting_notes, events, deliverables migradas para `initiative_id` — `20260413220000` (13 tabelas), dual-write triggers `20260413230000`
- [x] Todas RPCs tribe-* têm versão initiative-* — 9 RPCs `_by_initiative` em `20260413240000`; `_by_tribe` como alias deprecado
- [ ] Frontend de board, atas, events lê `initiative_id` sem mudança visível — **PENDENTE Fase 7** (frontend ainda usa tribe_id via dual-write)
- [x] CPMAI migrado para `initiative_kind='study_group'` + engagements — Migration `20260413630000` (Phase 6): 1 initiative criada, 7 tabelas cpmai_* deprecated (`20260413640000`)
