# ADR-0010: Wiki Scope — Narrative Knowledge Only

- Status: Accepted
- Data: 2026-04-14
- Aprovado por: Vitor (PM) em 2026-04-14
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Wiki & Knowledge Management — Fronteira wiki vs SQL

## Contexto

A plataforma possui 73 MCP tools que servem dados operacionais ao vivo via SQL (RPCs + RLS). Em paralelo, 3 wiki tools (`search_wiki`, `get_wiki_page`, `get_decision_log`) servem markdown do repositório `nucleo-ia-gp/wiki` → tabela `wiki_pages` com FTS.

Problema: **~45% das páginas wiki duplicam dados operacionais** já disponíveis ao vivo pelos tools SQL. Exemplos:
- Páginas de tribo listam membros e stats → `get_tribe_dashboard`, `get_my_tribe_members`, `get_tribe_stats_ranked` já servem isso ao vivo.
- Pipeline de parcerias → `get_partner_pipeline` é a fonte de verdade.
- Tabela de engagement kinds no onboarding → `get_active_engagements` é a fonte de verdade.

Estes dados ficam desatualizados na wiki porque mudanças acontecem no banco, não no markdown. O wiki agrega valor real para:
- ADRs e documentação de decisões arquiteturais
- Documentos de governança (manual, política de IP, termo de voluntariado)
- Contexto narrativo de tribos (cultura, acordos de trabalho, guias internos)
- Descrições de processos e frameworks

## Decisão

1. **Wiki = conhecimento narrativo.** Regra: "Se o dado muda >1x/mês → SQL é source of truth. Se é decisão, documento ou contexto narrativo → Wiki."

2. **O que PERTENCE à wiki:**
   - ADRs e documentação de decisões
   - Documentos de governança (manual, política de IP, termo de voluntariado)
   - READMEs e índices de domínio
   - Contexto narrativo de tribos (cultura, acordos de trabalho, guias internos)
   - Descrições de processos e frameworks

3. **O que PERTENCE ao SQL (servido por MCP tools):**
   - Listas de membros e rosters
   - Estatísticas de attendance e performance
   - Pipeline de parcerias e status
   - Tabelas de engagement kinds
   - Qualquer dado relacional/queryable

4. **Páginas de tribo especificamente:** Mantidas como espaço de contexto narrativo. Seções que duplicam dados operacionais (rosters de membros, tabelas de stats) devem ser removidas em follow-up — esses dados são servidos ao vivo por `get_tribe_dashboard`, `get_my_tribe_members`, etc.

5. **Novas páginas wiki devem passar o teste "narrativo vs operacional"** antes de serem criadas. Nenhuma página nova para dados que existem em tabelas SQL.

## Consequências

**Positivas:**
- **Fim da duplicação** — cada dado tem uma única fonte de verdade.
- **Wiki não fica stale** — contém apenas conteúdo que muda por decisão humana explícita.
- **MCP tools são canônicos** — AI assistants sempre recebem dados ao vivo para perguntas operacionais.
- **Manutenção reduzida** — menos páginas para manter sincronizadas.

**Negativas / custos:**
- Cleanup das páginas existentes requer trabalho no repositório wiki (follow-up).
- Contribuidores precisam internalizar a regra antes de criar novas páginas.

**Neutras:**
- Páginas de tribo continuam existindo — apenas com escopo ajustado para contexto narrativo.

## Alternativas consideradas

- **(A) Manter status quo (wiki duplica SQL)** — rejeitado, causa dados stale e confusão sobre fonte de verdade.
- **(B) Deletar todas as páginas com dados operacionais** — rejeitado, perderíamos contexto narrativo valioso nas páginas de tribo.
- **(C) Wiki = narrativo, SQL = operacional, com cleanup gradual (escolhida)** — preserva valor narrativo, elimina duplicação progressivamente.

## Relações com outros ADRs

- Complementa ADR-0005 (initiatives como primitivo — dados de initiative vivem no SQL)
- Complementa ADR-0007 (authority via `can()` — dados de autoridade vivem no SQL)
- Complementa ADR-0009 (initiative kinds como config — configuração vive no SQL)

## Follow-up checklist (repositório wiki, não este PR)

- [ ] Clean tribe pages: manter contexto narrativo, remover tabelas de roster de membros
- [ ] Clean `partnerships/cooperation-agreements.md`: manter análise de IP gap, remover tabela de pipeline
- [ ] Clean `onboarding/guide.md`: manter narrativa de processo, remover tabela de engagement-kinds

## Critérios de aceite

- [x] ADR-0010 documentado seguindo formato padrão
- [x] Descrições dos wiki MCP tools atualizadas para refletir escopo narrativo
- [x] CLAUDE.md referencia ADR-0010 na linha do Wiki
