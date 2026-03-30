# Dependency Upgrade Roadmap — Sprint 6 Assessment

**Data:** 2026-03-30
**Contexto:** 5 major versions disponveis. Avalicao de risco, esforco e priorizacao.

---

## Resumo Executivo

| Package | Current | Latest | Impacto | Recomendacao | Sprint |
|---------|---------|--------|---------|--------------|--------|
| lucide-react | 0.577.0 | 1.7.0 | Baixo (14 arquivos, sem brand icons) | **Upgrade agora** | Sprint 7 |
| recharts | 2.15.4 | 3.8.1 | Baixo (1 componente) | **Upgrade agora** | Sprint 7 |
| eslint | 9.39.4 | 10.1.0 | Medio (config ja flat) | **Upgrade proximo** | Sprint 7-8 |
| typescript | 5.9.3 | 6.0.2 | Medio (tsconfig ajustes) | **Testar em branch** | Sprint 8 |
| @tiptap/* | 2.27.2 | 3.21.0 | Alto (rewrite packages) | **Sprint dedicado** | Sprint 9+ |

---

## 1. lucide-react 0.577.0 -> 1.7.0

### Breaking Changes
- Brand icons removidos (logos de empresas). Pressao legal.
- Build UMD removido (apenas ESM + CJS agora)
- `aria-hidden` adicionado por default em todos os icones
- Novo: Context providers para config global de icones

### Impacto no Projeto
- **14 arquivos** importam lucide-react
- Nenhum uso de brand icons (verificado: usamos apenas icones genericos como Search, Clock, Award, etc.)
- Ja usamos ESM (Astro 6 + Vite)
- **Risco: BAIXO**

### Acao
```bash
npm install lucide-react@1
npx astro build && npm test
```
Esforco estimado: **30min** (instalar, build, verificar se algum icone sumiu)

### Referencia
- [Migration Guide](https://lucide.dev/guide/react/migration)
- [Version 1 Overview](https://lucide.dev/guide/version-1)

---

## 2. recharts 2.15.4 -> 3.8.1

### Breaking Changes
- State management reescrito internamente
- `recharts-scale` e `react-smooth` removidos como dependencias (internalizados)
- `CategoricalChartState` removido (props internas limpas)
- Z-index determinado pela ordem de render no SVG
- `activeIndex` prop removido

### Impacto no Projeto
- **1 arquivo**: `src/components/islands/CrossTribeIsland.tsx` (274 linhas, usa BarChart, LineChart, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, Cell)
- Tambem: `src/components/admin/CommsDashboard.tsx`
- Uso standard (BarChart + Tooltip + Legend) — nenhum uso de CategoricalChartState ou activeIndex
- **Risco: BAIXO-MEDIO** (testar visual dos charts)

### Acao
```bash
npm install recharts@3
npx astro build && npm test
# Visual check: /admin/comms-ops + attendance cross-tribe
```
Esforco estimado: **1h** (instalar, build, verificar visual dos 2 componentes)

### Referencia
- [3.0 Migration Guide](https://github.com/recharts/recharts/wiki/3.0-migration-guide)

---

## 3. eslint 9.39.4 -> 10.1.0

### Breaking Changes
- Node.js >= 20.19 requerido (nos: Node 24 — OK)
- `.eslintrc` formato removido (nos ja usamos flat config `eslint.config.mjs` — OK)
- Config lookup agora parte do diretorio do arquivo (nao CWD)
- `/* eslint-env */` comments nao mais suportados
- JSX reference tracking habilitado
- Metodos de context removidos (afeta plugins)

### Impacto no Projeto
- Ja usamos flat config (`eslint.config.mjs`) — breaking change principal nao nos afeta
- Node 24 — requisito atendido
- Risco: plugins (`eslint-plugin-astro`, `eslint-plugin-react`, `@typescript-eslint/parser`) precisam ser compativeis com ESLint 10
- **Risco: MEDIO** (depende dos plugins)

### Acao
1. Verificar compat dos plugins:
   - `eslint-plugin-astro` — verificar se suporta ESLint 10
   - `eslint-plugin-react` — verificar
   - `@typescript-eslint/parser` — verificar
2. Se todos compativeis:
```bash
npm install eslint@10 @eslint/js@10
npx astro build && npm test && npm run lint:i18n
```
Esforco estimado: **1-2h** (pesquisa compat + upgrade + fix eventuais)

### Referencia
- [ESLint v10 Migration Guide](https://eslint.org/docs/latest/use/migrate-to-10.0.0)

---

## 4. typescript 5.9.3 -> 6.0.2

### Breaking Changes
- `target: es5` removido (nos nao usamos — astro/vite controlam target)
- `moduleResolution: classic` removido
- `esModuleInterop` e `allowSyntheticDefaultImports` sempre true
- `downlevelIteration` deprecated
- "use strict" emitido incondicionalmente em CJS

### Impacto no Projeto
- tsconfig.json **nao tem** target, moduleResolution, esModuleInterop, downlevelIteration (Astro gerencia)
- Nosso tsconfig herda de `@astrojs/check` — precisamos verificar compat Astro 6.1.1 + TS 6
- TS 6 e a ultima versao JS-based (TS 7 sera Go-native)
- **Risco: MEDIO** (types podem mudar comportamento, precisa teste amplo)

### Acao
1. Verificar se `@astrojs/check` suporta TS 6
2. Testar em branch:
```bash
git checkout -b test/ts6
npm install typescript@6
npx astro build && npm test
# Se falhar, analisar erros de tipo
```
Esforco estimado: **2-4h** (pode ser trivial ou requerer ajustes de tipos)

### Ferramenta de Migracao
- [`ts5to6`](https://github.com/nicolo-ribaudo/ts5to6) — ajusta automaticamente baseUrl e rootDir

### Referencia
- [TypeScript 6.0 Announcement](https://devblogs.microsoft.com/typescript/announcing-typescript-6-0/)
- [Migration Guide (GitHub)](https://github.com/microsoft/TypeScript/issues/62508)

---

## 5. @tiptap/* 2.27.2 -> 3.21.0

### Breaking Changes
- Packages reestruturados: novo `@tiptap/extensions` combina multiplas extensoes
- `setContent(content, options)` — assinatura mudou
- `insertContent` nao mais split text nodes no inicio
- `getPos()` em NodeViewRendererProps pode retornar `undefined`
- StarterKit inclui Underline + Link por default
- `history: false` renomeado para `undoRedo: false`
- BubbleMenu/FloatingMenu movidos para `@tiptap/react/menus`
- SSR: `immediatelyRender: false` necessario

### Impacto no Projeto
- **1 arquivo**: `src/components/shared/RichTextEditor.tsx`
- Usa: `@tiptap/react`, `@tiptap/starter-kit`, `@tiptap/extension-link`, `@tiptap/extension-image`, `@tiptap/extension-placeholder`, `@tiptap/pm`
- Componente usado em meeting notes e blog editor
- **Risco: ALTO** (mudancas de package structure + API)

### Acao
1. Ler migration guide completo
2. Sprint dedicado:
   - Atualizar imports (packages podem ter mudado)
   - Ajustar StarterKit config (history → undoRedo)
   - Testar `setContent` e `insertContent` behaviors
   - Verificar se BubbleMenu/FloatingMenu sao usados
3. Testar meeting notes CRUD end-to-end

Esforco estimado: **4-6h** (sprint dedicado recomendado)

### Referencia
- [Tiptap v2 to v3 Upgrade Guide](https://tiptap.dev/docs/guides/upgrade-tiptap-v2)

---

## Sequencia Recomendada

```
Sprint 7:  lucide-react v1 (30min) + recharts v3 (1h)     = ~2h
Sprint 8:  eslint v10 (2h) + typescript v6 (3h)            = ~5h
Sprint 9:  @tiptap/* v3 (5h, sprint dedicado)              = ~5h
```

**Princípio:** menor risco primeiro, maior valor de reducao de debt.

---

## MCP New Tool Candidates (S6.11)

152 RPCs no frontend, 19 expostos via MCP. Candidatos priorizados por demanda real:

### Tier 1 — Alta demanda (personas existentes pedem)
| Tool | RPC | Persona | Justificativa |
|------|-----|---------|---------------|
| `get_tribe_dashboard` | exec_tribe_dashboard | Líder | Dashboard completo da tribo (cards, membros, métricas) |
| `get_attendance_ranking` | get_attendance_panel | Líder/GP | Ranking de presença da tribo/global |
| `get_portfolio_overview` | get_portfolio_dashboard | GP | Visão executiva de todos os boards |

### Tier 2 — Média demanda (facilita operação)
| Tool | RPC | Persona | Justificativa |
|------|-----|---------|---------------|
| `get_operational_alerts` | detect_operational_alerts | GP | Alertas de inatividade, atraso, drift |
| `get_cycle_report` | exec_cycle_report | GP/Sponsor | Relatório de ciclo completo |
| `get_annual_kpis` | get_annual_kpis | Sponsor | KPIs anuais agregados |

### Tier 3 — Nicho (features futuras)
| Tool | RPC | Persona | Justificativa |
|------|-----|---------|---------------|
| `verify_my_credly` | (EF call) | Membro | Trigger verificação de badge |
| `get_board_activities` | get_board_activities | Líder | Log de atividades do board |
| `get_cross_tribe_comparison` | exec_cross_tribe_comparison | GP | Comparativo entre tribos |

**Recomendação:** Implementar Tier 1 (3 tools) no Sprint 7, junto com os dep upgrades.

---

## SDK 1.28.0 Tracking (S6.12)

- **Latest:** 1.28.0 (sem releases novas desde nossa avaliação)
- **Status:** Bloqueado em Deno — `mcp.tool()` requer Zod nativo, `WebStandardStreamableHTTPServerTransport` crasha
- **Monitorar:** https://github.com/modelcontextprotocol/typescript-sdk/releases
- **Trigger para re-avaliação:** Release 1.29.0+ ou Supabase EF upgrade de Deno runtime
- **Nosso estado atual:** SDK 1.27.1 + Zod @3 + manual SSE = estável e funcional
