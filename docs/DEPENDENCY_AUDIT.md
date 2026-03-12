# Dependency Audit — March 2026

> Gerado em: 2026-03-12
> Total de dependencias: 15 production + 12 dev = 27 pacotes
> Bundle JS total (dist/_astro): ~1.555 KB (nao-comprimido)

---

## 1. Em Uso Ativo

### 1.1 Production Dependencies

| Pacote | Versao Instalada | Importado em | Uso |
|--------|-----------------|-------------|-----|
| `astro` | 5.18.0 | `astro.config.mjs`, `src/middleware/index.ts`, `src/pages/api/search.ts` | Framework principal SSR |
| `@astrojs/cloudflare` | 12.6.12 | `astro.config.mjs` | Adapter para deploy Cloudflare Pages |
| `@astrojs/react` | 5.0.0 | `astro.config.mjs` | Integracao React (islands) |
| `react` | 19.2.4 | 13+ componentes em `src/components/` e `src/hooks/` | Biblioteca UI (islands architecture) |
| `react-dom` | 19.2.4 | Dependencia implícita do `@astrojs/react` | Renderizacao DOM do React |
| `tailwindcss` | 4.2.1 | `src/styles/global.css` (`@import "tailwindcss"`) | Framework CSS utilitario |
| `@tailwindcss/vite` | 4.2.1 | `astro.config.mjs` | Plugin Vite para Tailwind v4 |
| `@supabase/supabase-js` | 2.98.0 | `src/lib/supabase.ts`, `src/lib/cycles.ts`, `src/pages/api/search.ts` | Cliente Supabase (auth, DB, storage) |
| `@dnd-kit/core` | 6.3.1 | `BoardKanban.tsx`, `BoardEngine.tsx`, `PublicationsBoardIsland.tsx`, `TribeKanbanIsland.tsx`, `CuratorshipBoardIsland.tsx` | Drag-and-drop core |
| `@dnd-kit/sortable` | 10.0.0 | `BoardKanban.tsx`, `PublicationsBoardIsland.tsx`, `TribeKanbanIsland.tsx`, `CuratorshipBoardIsland.tsx` | Ordenacao por DnD |
| `@dnd-kit/utilities` | 3.2.2 | `BoardKanban.tsx`, `PublicationsBoardIsland.tsx`, `TribeKanbanIsland.tsx`, `CuratorshipBoardIsland.tsx` | Utilitarios CSS transforms para DnD |
| `@radix-ui/react-dialog` | 1.1.15 | `CuratorshipBoardIsland.tsx`, `TribeKanbanIsland.tsx` | Modais acessiveis |
| `@radix-ui/react-dropdown-menu` | 2.1.16 | `PublicationsBoardIsland.tsx` | Menus dropdown acessiveis |
| `@radix-ui/react-popover` | 1.1.15 | `TribeKanbanIsland.tsx` | Popovers acessiveis |
| `@radix-ui/react-visually-hidden` | 1.2.4 | `CuratorshipBoardIsland.tsx`, `TribeKanbanIsland.tsx` | Acessibilidade (screen readers) |
| `cmdk` | 1.1.1 | `src/components/ui/GlobalSearchIsland.tsx` | Command palette (busca global) |
| `lucide-react` | 0.577.0 | `PublicationsBoardIsland.tsx`, `TribeKanbanIsland.tsx`, `CuratorshipBoardIsland.tsx`, `GlobalSearchIsland.tsx` | Icones SVG (tree-shakeable) |
| `chart.js` | 4.5.1 | `src/pages/admin/analytics.astro`, `src/pages/admin/comms.astro`, `src/pages/admin/index.astro` | Graficos canvas (admin dashboards) |
| `recharts` | 2.15.4 | `src/components/admin/CommsDashboard.tsx` | Graficos React (comms dashboard) |

### 1.2 Dev Dependencies

| Pacote | Versao Instalada | Usado por | Uso |
|--------|-----------------|----------|-----|
| `typescript` | 5.9.3 | `tsconfig.json`, compilacao geral | Tipagem estatica |
| `@astrojs/check` | 0.9.6 | CLI `astro check` | Verificacao de tipos Astro |
| `eslint` | 9.39.4 | `eslint.config.mjs`, script `lint:i18n` | Linter |
| `@eslint/js` | 9.39.4 | `eslint.config.mjs` | Config base ESLint |
| `eslint-plugin-astro` | 1.6.0 | `eslint.config.mjs` | Regras ESLint p/ arquivos `.astro` |
| `eslint-plugin-react` | 7.37.5 | `eslint.config.mjs` | Regras ESLint p/ JSX/React |
| `astro-eslint-parser` | 1.3.0 | `eslint.config.mjs` | Parser ESLint p/ `.astro` |
| `@typescript-eslint/parser` | 8.57.0 | `eslint.config.mjs` | Parser ESLint p/ TypeScript |
| `@playwright/test` | 1.58.2 | `playwright.config.ts`, scripts `test:visual:dark`, `test:e2e:lifecycle` | Framework de testes E2E |
| `playwright` | 1.58.2 | Script `screenshots:multilang`, `screenshots:setup` | Automacao de browser (screenshots) |
| `dotenv` | 17.3.1 | 12+ scripts em `scripts/` (`import 'dotenv/config'`) | Variaveis de ambiente em scripts |

---

## 2. Instalada Mas Nao Utilizada (candidatas a `npm uninstall`)

| Pacote | Versao | Motivo |
|--------|--------|--------|
| `csv-parse` | 6.1.0 | Nenhuma importacao encontrada em `src/`, `scripts/`, `tests/` ou `supabase/`. Possivelmente utilizada no passado para importacao de dados e nunca removida. |
| `mammoth` | 1.11.0 | Nenhuma importacao encontrada em todo o projeto. Provavelmente instalada para conversao de `.docx` em HTML mas nunca integrada ou ja removida do codigo. |
| `xlsx` | 0.18.5 | Nenhuma importacao `from 'xlsx'` encontrada. Ha apenas referencias a extensao `.xlsx` como string literal em scripts de bulk ingestion, mas nenhum uso da biblioteca em si. |

**Economia estimada ao remover:** ~15 MB em `node_modules` (xlsx sozinha ocupa ~10 MB). Nenhum impacto no bundle de producao pois sao devDependencies.

---

## 3. Analises Especificas

### 3.1 @dnd-kit/* — Status de uso

**Veredicto: ATIVAMENTE UTILIZADO em producao.**

Os tres pacotes `@dnd-kit/core`, `@dnd-kit/sortable` e `@dnd-kit/utilities` sao importados em **5 componentes**:

| Componente | core | sortable | utilities |
|-----------|------|----------|-----------|
| `BoardKanban.tsx` | `useDroppable` | `SortableContext`, `verticalListSortingStrategy`, `useSortable` | `CSS` |
| `BoardEngine.tsx` | `DndContext`, `DragOverlay`, `closestCorners`, sensores | — | — |
| `PublicationsBoardIsland.tsx` | `DndContext`, `DragOverlay`, `closestCorners`, sensores | `SortableContext`, `useSortable`, `arrayMove` | `CSS` |
| `TribeKanbanIsland.tsx` | `DndContext`, `DragOverlay`, `closestCorners`, sensores | `SortableContext`, `useSortable`, `arrayMove` | `CSS` |
| `CuratorshipBoardIsland.tsx` | `DndContext`, `DragOverlay`, `closestCorners`, sensores | `SortableContext`, `useSortable`, `arrayMove` | `CSS` |

Chunk de build `sortable.esm.DPM9dlb0.js` = ~47 KB (nao-comprimido). Todos os boards kanban dependem desta funcionalidade. **Nao remover.**

### 3.2 chart.js vs recharts — Consolidacao?

**Ambos estao em uso ativo, mas para fins diferentes:**

| Biblioteca | Onde | Como | Tamanho no bundle |
|-----------|------|------|-------------------|
| `chart.js` (4.5.1) | `analytics.astro`, `comms.astro`, `index.astro` (admin) | Dynamic import (`await import('chart.js')`) em scripts inline de paginas Astro. Renderiza graficos em `<canvas>`. | `chart.Cns13J0s.js` = **208 KB** |
| `recharts` (2.15.4) | `CommsDashboard.tsx` | Importacao estatica em componente React island. Renderiza graficos como SVG via React. | Incluido em `CommsDashboard.aqRtTZJ6.js` = **413 KB** (inclui React + recharts + logica) |

**Analise de consolidacao:**

- `chart.js` e usado em paginas Astro server-rendered com scripts vanilla — nao pode ser substituido por recharts sem reescrever como React islands.
- `recharts` e usado em um componente React — nao pode ser substituido por chart.js sem perder a reatividade React.
- **Recomendacao:** Manter ambos por enquanto. A longo prazo, se os dashboards admin forem migrados para React islands, consolidar em recharts. Alternativamente, migrar `CommsDashboard.tsx` para chart.js reduziria significativamente o bundle (recharts traz ~200 KB de overhead vs chart.js ja carregado).

### 3.3 Supabase Client — Versao e atualizacao

| | Valor |
|---|---|
| Versao instalada | **2.98.0** |
| Versao mais recente (npm) | **2.99.1** (publicada em 2026-03-12) |
| Diferenca | 1 minor version atras |
| Breaking changes? | Nao (patch/minor dentro de v2) |

**Recomendacao:** Atualizar com `npm update @supabase/supabase-js`. A atualizacao e segura (semver minor). Node.js 18 foi descontinuado na v2.79.0 — verificar que o ambiente de deploy usa Node >= 20.

### 3.4 Polyfills e libs legadas

**Nenhum polyfill classico encontrado** (core-js, regenerator-runtime, whatwg-fetch, etc.).

O unico polyfill existente e o **MessageChannel polyfill** em `scripts/patch-worker-polyfill.mjs`, que e injetado pos-build nos chunks do Cloudflare Worker. Isso e necessario porque o React 19 (`react-dom/server`) chama `new MessageChannel()` durante inicializacao do modulo, e o ambiente de validacao do Cloudflare Pages nao disponibiliza essa API.

**Veredicto:** O polyfill e necessario e especifico ao ambiente de deploy. Nao ha libs legadas desnecessarias.

---

## 4. Top-5 Maiores Dependencias (impacto no bundle)

Baseado nos chunks de build em `dist/_astro/`:

| # | Chunk / Pacote | Tamanho (nao-comprimido) | Tamanho estimado (gzip) | Notas |
|---|---------------|-------------------------|------------------------|-------|
| 1 | `CommsDashboard` (recharts + React) | 413 KB | ~120 KB | Maior chunk. Recharts e a principal causa. |
| 2 | `chart.js` | 208 KB | ~65 KB | Carregado via dynamic import apenas em paginas admin. |
| 3 | `client` (React runtime) | 183 KB | ~55 KB | React 19 core. Inevitavel. |
| 4 | `supabase` (supabase-js) | 172 KB | ~45 KB | Cliente Supabase. Inevitavel. |
| 5 | `index` (pagina admin principal) | 97 KB | ~25 KB | Logica de dashboard admin. |

**Observacao:** O bundle total de JS e ~1.555 KB nao-comprimido. chart.js e recharts juntos representam ~621 KB (~40% do bundle). Consolidar em uma unica biblioteca de graficos economizaria ~200 KB.

---

## 5. Recomendacoes de Substituicao/Atualizacao

| # | Pacote atual | Recomendacao | Motivo | Esforco |
|---|-------------|-------------|--------|---------|
| 1 | `csv-parse` 6.1.0 | **Remover** (`npm uninstall csv-parse`) | Sem nenhuma importacao no projeto | Trivial |
| 2 | `mammoth` 1.11.0 | **Remover** (`npm uninstall mammoth`) | Sem nenhuma importacao no projeto | Trivial |
| 3 | `xlsx` 0.18.5 | **Remover** (`npm uninstall xlsx`) | Sem nenhuma importacao no projeto. Nota: `xlsx` (SheetJS) tem licenca restritiva na v0.20+; a v0.18.5 usada aqui e a ultima versao OSS. | Trivial |
| 4 | `@supabase/supabase-js` 2.98.0 | **Atualizar** para 2.99.1 | 1 minor atras, sem breaking changes | Trivial |
| 5 | `recharts` 2.15.4 | **Considerar migrar para chart.js** | Reduz bundle em ~200 KB. chart.js ja esta presente. Requer reescrever `CommsDashboard.tsx` com canvas em vez de React components. | Medio (~4h) |
| 6 | `chart.js` 4.5.1 | **Alternativa: migrar para recharts** | Se preferir manter tudo em React. Requer reescrever graficos em `analytics.astro`, `comms.astro`, `index.astro` como React islands. | Alto (~8h) |
| 7 | `lucide-react` 0.577.0 | Manter, mas **auditar icones importados** | Apenas 4 arquivos importam icones. Tree-shaking funciona bem, mas verificar se o build esta eliminando icones nao usados. | Baixo |
| 8 | `@astrojs/check` 0.9.6 | **Verificar se esta em uso** | Nao ha script `astro check` no `package.json`. Se nao e executado manualmente ou em CI, pode ser removido. | Trivial |

---

## Resumo Executivo

- **3 pacotes podem ser removidos imediatamente**: `csv-parse`, `mammoth`, `xlsx` — nenhum codigo os importa.
- **1 pacote deve ser atualizado**: `@supabase/supabase-js` (2.98.0 -> 2.99.1).
- **@dnd-kit/*** esta em uso ativo em 5 componentes — manter.
- **chart.js + recharts** coexistem por necessidade arquitetural (Astro pages vs React islands), mas consolidar economizaria ~200 KB de bundle.
- **Nenhum polyfill legado** encontrado — o projeto esta limpo.
- **Bundle total JS**: ~1.555 KB nao-comprimido, estimado ~310 KB gzip.
