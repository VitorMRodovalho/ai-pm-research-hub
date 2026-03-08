# Frontend Hardening Roadmap (2026-03)

## Contexto
A arquitetura de dados e governança no Supabase está madura, mas o frontend ainda concentra riscos operacionais: renderização imperativa com `innerHTML`, páginas monolíticas e autenticação resolvida apenas no client em pontos críticos.

Este roadmap formaliza a intervenção técnica para reduzir regressões, risco de XSS e custo de manutenção, sem romper a estratégia de baixo custo da stack atual.

## Diagnóstico consolidado
- Alto uso de manipulação de DOM via strings (`innerHTML`) em fluxos administrativos.
- Componentes/páginas grandes com mistura de UI + agregação + regras (ex.: `/admin`).
- Fluxos com auth gate client-side que podem gerar flicker e UX inconsistente.
- Agregações pesadas feitas no navegador em vez de RPC/view já agregada.

## Objetivos
1. Reduzir superfície de XSS e regressões de eventos.
2. Reduzir acoplamento frontend por componentização progressiva.
3. Mover agregações para backend/RPC quando o volume justificar.
4. Evoluir auth para SSR/cookies nas rotas críticas.

## Sprints propostos

### S-FE1 — XSS & DOM Safety Baseline
- Escopo:
  - mapear pontos de `innerHTML` com dados de banco;
  - introduzir utilitário padrão de escaping/safe render;
  - eliminar injeção direta em telas críticas (`/admin`, `/artifacts`, `/profile`).
- Critério de aceite:
  - checklist de pontos críticos saneados;
  - sem renderização direta de campos textuais sem sanitização.

### S-FE2 — Admin Modularization v1
- Escopo:
  - quebrar `/admin/index.astro` em blocos funcionais por responsabilidade;
  - separar carregamento de dados do rendering da UI;
  - remover dependência de `window.*` global onde possível.
- Critério de aceite:
  - módulo admin dividido em componentes menores;
  - redução de regressões em interações de aba/modais.

### S-FE3 — Auth SSR Gate v1
- Escopo:
  - migrar rotas críticas para gate SSR baseado em cookie/session;
  - reduzir flicker de página pública antes do bloqueio por permissão.
- Critério de aceite:
  - `/admin`, `/profile` e `/artifacts` com gate de acesso decidido no server render path.

### S-FE4 — Executive RPC Binding
- Escopo:
  - trocar agregações client-side do painel executivo por RPCs (`exec_*`);
  - manter fallback observável para erro de fonte analítica.
- Critério de aceite:
  - painel executivo consumindo somente modelos agregados do backend;
  - tempo de resposta e payload reduzidos.

## Guardrails
- Não introduzir framework pesado; priorizar incremental (`Astro islands` leves quando necessário).
- Preservar a estratégia no-cost de operação e deploy.
- Toda mudança relevante deve atualizar:
  - `backlog-wave-planning-updated.md`
  - `docs/RELEASE_LOG.md`
  - GitHub Project (status + commit trace)
