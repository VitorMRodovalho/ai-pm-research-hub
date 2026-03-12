# Design Doc v2: Navegação, Identidade Visual e Dark Mode

**Data:** 12 de março de 2026 — Atualizado com decisões do GP
**Autor:** Claude (a pedido de Vitor Maia Rodovalho, PM)
**Status:** Aprovado para implementação (decisões D1–D6 confirmadas)

---

## DECISÕES APROVADAS PELO GP

| # | Decisão | Escolha |
|---|---------|---------|
| D1 | Home section nav | **B — Dropdown "Seções"** (só na rota `/`) |
| D2 | `/teams` e `/#tribes` | **Manter ambos para público geral.** `/teams` = estrutura completa (ativas + subprojetos + legado). `/#tribes` = seção da home com quadrantes e seleção/info das tribos. Workspace (membros) = evolução do layout de `/teams` com boards e ações |
| D3 | Workspace | **A — `/workspace` como página nova** (não substituir `/teams`) |
| D4 | Admin na nav | **A — Nav primária com badge roxo** |
| D5 | Background | **A — `#F7F4EF` (warm) em tudo** |
| D6 | Mobile drawer | **B — Sidebar direita (atual, menos risco)** |
| D7 | Dark mode | **Sim — dark mode real e funcional em todas as seções** (novo) |

**Clarificação sobre `/teams` vs `/workspace`:**
- `/teams` (público) → Mantém. Mostra a estrutura do Núcleo: tribos ativas, subprojetos (Hub de Comms, Webinars, Comitê de Curadoria), legado dos ciclos anteriores. Qualquer visitante pode ver.
- `/#tribes` (home) → Mantém. Seção da landing com quadrantes e tribos. Usado para seleção durante o período, e para informações gerais durante o ciclo.
- `/workspace` (membros autenticados) → Novo. Evolução do layout de `/teams` mas com **ações**: boards editáveis via BoardEngine, links para produção, métricas pessoais. O workspace é o "cockpit" do membro.

---

## 1. DARK MODE — ESTRATÉGIA COMPLETA

### 1.1 Estado atual

O projeto já tem:
- ✅ Script de detecção no `<head>` (lê `localStorage('ui_theme')`)
- ✅ `data-theme` attribute no `<html>`
- ✅ `dark:` classes no `<body>` e no drawer
- ✅ Toggle visual (o botão existe no nav)

O que falta:
- ❌ Seções da home com backgrounds fixos (`bg-white`, `bg-[#F7F4EF]`, `bg-[#003B5C]`) não respondem
- ❌ Cards com `bg-white` hardcoded ficam brilhantes no dark mode
- ❌ Borders com `border-black/5` ficam invisíveis no dark
- ❌ Text colors como `text-slate-500` ficam ilegíveis em fundo escuro
- ❌ Gradients da hero são fixos
- ❌ Módulos internos (admin, curatorship) não têm dark classes

### 1.2 Abordagem: CSS Custom Properties (não dark: classes)

Em vez de adicionar `dark:bg-xxx` em centenas de elementos, vamos usar CSS custom properties que mudam com o tema. Isso é mais sustentável e evita a explosão de classes.

```css
/* ══════════════════════════════════════════════════ */
/* DESIGN TOKENS — global.css (ou theme.css)        */
/* ══════════════════════════════════════════════════ */

:root {
  /* ── PMI Brand ── */
  --color-navy: #003B5C;
  --color-navy-deep: #0A1628;
  --color-orange: #FF610F;
  --color-orange-muted: #ED7D31;
  --color-teal: #05BFE0;
  --color-teal-deep: #00799E;
  --color-crimson: #BE2027;
  --color-purple: #4F17A8;
  --color-emerald: #10B981;
  --color-amber: #D97706;

  /* ── Surfaces (light mode) ── */
  --surface-base: #F7F4EF;
  --surface-card: #FAFAF8;
  --surface-elevated: #FFFFFF;
  --surface-section-alt: #F0F4F8;     /* alternating sections */
  --surface-section-warm: #F7F4EF;    /* warm sections */
  --surface-section-dark: #003B5C;    /* navy sections (KPIs, Team) */
  --surface-hero: linear-gradient(135deg, #003B5C, #200F3B 40%, #0A1628);

  /* ── Borders ── */
  --border-subtle: rgba(0, 0, 0, 0.05);
  --border-default: rgba(0, 0, 0, 0.08);
  --border-strong: rgba(0, 0, 0, 0.15);

  /* ── Text ── */
  --text-primary: #1E293B;
  --text-secondary: #64748B;
  --text-muted: #94A3B8;
  --text-inverse: #FFFFFF;

  /* ── Overlays ── */
  --overlay-card-hover: rgba(0, 0, 0, 0.02);
  --overlay-backdrop: rgba(0, 0, 0, 0.5);
}

/* ══════════════════════════════════════════════════ */
/* DARK MODE                                         */
/* ══════════════════════════════════════════════════ */

[data-theme="dark"] {
  /* ── Surfaces ── */
  --surface-base: #0C1222;
  --surface-card: #162032;
  --surface-elevated: #1E293B;
  --surface-section-alt: #0F1A2E;
  --surface-section-warm: #121A2C;
  --surface-section-dark: #0A1628;       /* stays dark, just deeper */
  --surface-hero: linear-gradient(135deg, #0A1628, #150D2E 40%, #080E1C);

  /* ── Borders ── */
  --border-subtle: rgba(255, 255, 255, 0.06);
  --border-default: rgba(255, 255, 255, 0.10);
  --border-strong: rgba(255, 255, 255, 0.18);

  /* ── Text ── */
  --text-primary: #E2E8F0;
  --text-secondary: #94A3B8;
  --text-muted: #64748B;
  --text-inverse: #0F172A;

  /* ── Brand colors (slightly adjusted for dark bg legibility) ── */
  --color-teal: #22D3EE;          /* brighter on dark */
  --color-orange: #FB923C;         /* softer on dark */
  --color-crimson: #EF4444;        /* brighter on dark */
  --color-emerald: #34D399;        /* brighter on dark */

  /* ── Overlays ── */
  --overlay-card-hover: rgba(255, 255, 255, 0.03);
  --overlay-backdrop: rgba(0, 0, 0, 0.7);
}
```

### 1.3 Mapping: Current Classes → Token Classes

A migração é feita substituindo classes hardcoded por classes que usam tokens:

| Componente | Antes (light-only) | Depois (themed) |
|---|---|---|
| `<body>` | `bg-slate-50` | `bg-[var(--surface-base)]` |
| Section alt | `bg-[#F7F4EF]` | `bg-[var(--surface-section-warm)]` |
| Section cool | `bg-[#f0f4f8]` | `bg-[var(--surface-section-alt)]` |
| Section navy | `bg-[#003B5C]` | `bg-[var(--surface-section-dark)]` |
| Cards | `bg-white` | `bg-[var(--surface-card)]` |
| Card borders | `border-black/5` | `border-[var(--border-subtle)]` |
| Text main | `text-slate-900` | `text-[var(--text-primary)]` |
| Text secondary | `text-slate-500` | `text-[var(--text-secondary)]` |
| Text muted | `text-slate-400` | `text-[var(--text-muted)]` |
| Hero bg | `background: linear-gradient(...)` | `background: var(--surface-hero)` |

### 1.4 Seções que precisam de atenção especial no dark mode

**Hero section** — Já é escura (gradient navy→purple). Funciona em ambos os modos. Só ajustar o gradient para ficar um pouco mais profundo no dark.

**Quadrantes (`#quadrants`)** — Fundo `bg-white` com cards `bg-[#FAFAF8]`. No dark, os cards precisam de `bg-[var(--surface-card)]` com border `var(--border-subtle)`. A borda esquerda colorida (teal, orange, purple, emerald) mantém a mesma cor — já funciona bem em dark.

**Tribos (`#tribes`)** — Fundo `bg-[#F7F4EF]` com cards `bg-white` e accordion. No dark, o fundo warm vira `--surface-section-warm` e os cards viram `--surface-card`. Os dots verdes de slots mantêm a cor.

**KPIs (`#kpis`)** — Fundo `bg-[#003B5C]` com cards `bg-white/6`. Já é dark-friendly! No dark mode, apenas descer o background para `--surface-section-dark` e manter os cards com opacidade.

**Team (`#team`)** — Mesmo que KPIs. Já é dark-friendly. Ajustar ligeiramente o contraste dos cards.

**Breakout, Rules, Vision, Resources** — Fundo `bg-[#F7F4EF]` ou `bg-white`. Migrar para tokens.

**Módulos admin** — Fundo `bg-slate-50` com cards `bg-white`. Migrar para tokens.

**Navbar** — Já é escura (`bg-navy/97`). Funciona em ambos os modos.

**Modals (auth, card detail)** — `bg-white` com text escuro. Precisam de `bg-[var(--surface-elevated)]` + `text-[var(--text-primary)]`.

### 1.5 Esforço estimado

| Tarefa | Estimativa | Risco |
|---|---|---|
| Criar `theme.css` com tokens | 2h | Baixo |
| Migrar `<body>`, sections backgrounds | 3h | Baixo |
| Migrar cards e borders (home) | 4h | Médio (muitos componentes) |
| Migrar módulos admin | 3h | Médio |
| Migrar modals e drawers | 2h | Baixo |
| Migrar nav e sub-navs | 1h | Baixo (já são dark) |
| Migrar forms e inputs | 2h | Médio (focus states) |
| Testar em todos os módulos | 3h | — |
| **Total** | **~20h** (~3 dias dev) | Médio |

O dark mode pode ser feito incrementalmente. A ordem sugerida é:

1. Criar `theme.css` com todos os tokens
2. Migrar backgrounds de seção (impacto visual imediato, maior)
3. Migrar cards e borders (segundo maior impacto)
4. Migrar text colors (sutil mas importante para legibilidade)
5. Migrar módulos internos (admin, profile, etc.)
6. Migrar modals e formulários
7. QA visual em cada rota

### 1.6 Armadilhas comuns (para o time dev evitar)

**Não usar `dark:` inline para tudo.** O Tailwind `dark:` funciona mas explode o número de classes. Com tokens, uma mudança no `theme.css` afeta todo o site de uma vez.

**Imagens e avatars.** Fotos de perfil ficam bem em qualquer tema. Mas ícones SVG que usam `fill="currentColor"` vão herdar a cor do texto — isso é bom. Os que usam `fill="#003B5C"` hardcoded vão precisar de ajuste.

**Charts e badges.** Chart.js e os badges de gamificação usam cores fixas. Os backgrounds dos charts (`bg-white`) precisam migrar, mas as cores das barras/linhas (teal, orange, etc.) mantêm bem em dark.

**Inputs e selects.** No dark mode, `bg-white` em inputs fica brilhante. Usar `bg-[var(--surface-elevated)]` com `text-[var(--text-primary)]` e `border-[var(--border-default)]`.

**Gradients de texto.** A hero usa `bg-clip-text text-transparent bg-gradient-to-r from-[#05BFE0] to-[#B465FF]`. Funciona em ambos os modos — fica bonito em dark.

---

## 2. WORKSPACE — DESIGN EXPANDIDO

### 2.1 Relação com `/teams`

```
/teams (público)              /workspace (membro+)
├── Ativas (Pesquisa)         ├── Meus Boards (com ações)
│   T1...T8 (cards simples)   │   Board da minha tribo (BoardEngine)
│                              │   Boards globais que tenho acesso
├── Subprojetos (Operação)    │
│   Hub de Comunicação         ├── Subprojetos
│   Webinars                   │   Hub de Comunicação (BoardEngine)
│   Comitê de Curadoria        │   Pipeline Webinars (BoardEngine)
│                              │   Curadoria (cross-board view)
├── Legado (Read-only)         │   Grupo de Liderança
│   Ciclo 1, Ciclo 2           │
│   (cards com badge READ ONLY)├── Produção
                               │   Artefatos (meus + da tribo)
                               │   Publicações & Submissões
                               │
                               ├── Recursos
                               │   Biblioteca
                               │   Apresentações
                               │
                               └── Legado (se admin/observer)
                                   Ciclos anteriores (read-only)
```

**`/teams` é vitrine. `/workspace` é oficina.**

### 2.2 Layout do Workspace

```
┌──────────────────────────────────────────────────────────────────────┐
│  Workspace                                                    [🔍]  │
│  Seu espaço de trabalho no Núcleo                                    │
│                                                                      │
│  ── Minha Tribo ─────────────────────────────────────────────────── │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ T6: ROI & Portfólio                              [Abrir →] │    │
│  │ 📋 12 itens · 3 pendentes · 📅 Próx: Qui 19:30           │    │
│  │ ██████░░░░ 60% progresso                                   │    │
│  │ 👤 Fabricio Costa (Líder) · 5 membros                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ── Subprojetos ─────────────────────────────────────────────────── │
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐    │
│  │ 📡 Hub de Comms  │ │ 🎬 Webinars      │ │ 🔍 Curadoria     │    │
│  │ 45 itens         │ │ Pipeline eventos │ │ 6 pendentes      │    │
│  │ 8 pendentes      │ │ 3 em andamento   │ │ [Cross-board →]  │    │
│  └──────────────────┘ └──────────────────┘ └──────────────────┘    │
│  ┌──────────────────┐ ┌──────────────────┐                         │
│  │ 👥 Grupo de      │ │ 📑 Publicações   │                         │
│  │    Liderança     │ │ & Submissões     │                         │
│  │ Próx: 15 Mar     │ │ 23 itens         │                         │
│  └──────────────────┘ └──────────────────┘                         │
│                                                                      │
│  ── Produção & Recursos ─────────────────────────────────────────── │
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐    │
│  │ 📄 Artefatos     │ │ 📚 Biblioteca    │ │ 🎬 Apresentações │    │
│  │ 18 produzidos    │ │ 230+ recursos    │ │ 4 gravações      │    │
│  └──────────────────┘ └──────────────────┘ └──────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

Cada card é clicável e leva para a página/board correspondente.
O card "Minha Tribo" é destacado (maior, com mais informação) porque é o contexto principal do membro.
A seção de Subprojetos só mostra os que o membro tem acesso (via permissions matrix).

---

## 3. NAV PRIMÁRIA (atualizado com decisões)

### Visitante

```
[Logo]   [Seções ▾]   Tribos   Trilha IA   Gamificação   Biblioteca   [🔍]  [🇧🇷]  [Entrar]
```
"Seções ▾" só aparece na rota `/`. Abre dropdown com as 9 âncoras.
"Tribos" leva a `/#tribes` (scroll) ou `/teams` dependendo da rota.

### Membro autenticado

```
[Logo]   Workspace   Minha Tribo   Trilha IA   Gamificação   [🔍]  [👤]
```

### Admin (tier >= observer)

```
[Logo]   Workspace   Minha Tribo   Trilha IA   Gamificação   [⚙️ Admin]   [🔍]  [👤]
```

---

## 4. PLANO DE IMPLEMENTAÇÃO CONSOLIDADO

### Sprint N1 — Design Tokens + Dark Mode Foundation (1 semana)

- [ ] Criar `theme.css` com tokens light/dark (seção 1.2)
- [ ] Migrar backgrounds de seção da home (hero, quadrantes, tribos, KPIs, team, etc.)
- [ ] Migrar cards e borders da home
- [ ] Migrar navbar (já dark — ajustar detalhes)
- [ ] Migrar auth modal
- [ ] QA visual: home em light e dark
- **Entrega:** Home page funciona perfeitamente em dark mode

### Sprint N2 — Dark Mode Módulos + Nav Restructure (1 semana)

- [ ] Migrar módulos admin (admin panel, analytics, comms, curatorship)
- [ ] Migrar profile, attendance, presentations
- [ ] Migrar forms e inputs em todos os módulos
- [ ] Reestruturar drawer do avatar com seções agrupadas
- [ ] Remover duplicação "Explorar Tribos" da nav
- [ ] Implementar dropdown "Seções ▾" (home-only)
- [ ] Reduzir nav primária para 5-6 items
- **Entrega:** Dark mode completo + nav limpa

### Sprint N3 — Workspace Page (1 semana)

- [ ] Criar `/workspace` com layout da seção 2.2
- [ ] Integrar `list_active_boards()` RPC (do BoardEngine)
- [ ] Cards com contagem de items e status
- [ ] Card destacado "Minha Tribo" com progresso
- [ ] Seção de subprojetos com permissões
- [ ] Sub-nav contextual do workspace
- [ ] Dark mode nativo (usa tokens desde o início)
- **Entrega:** Workspace funcional, integrado com BoardEngine

### Sprint N4 — Polish + QA (1 semana)

- [ ] Mobile responsiveness em todas as rotas com dark mode
- [ ] i18n para novos labels (PT-BR, EN-US, ES-LATAM)
- [ ] Testar dark mode em: iOS Safari, Android Chrome, desktop Chrome/Firefox
- [ ] Verificar contraste WCAG AA em todos os tokens
- [ ] Smoke tests em todas as rotas com ambos os temas
- [ ] Documentar tokens no `docs/DESIGN_TOKENS.md`
- **Entrega:** Production-ready, acessível, documentado

---

## 5. CHECKLIST DE QA PARA DARK MODE

Para cada rota, verificar em ambos os temas (light + dark):

### Home (`/`)
- [ ] Hero gradient suave, sem "flash" branco
- [ ] Quadrantes: cards legíveis, borders visíveis
- [ ] Tribos: accordion funciona, dots verdes visíveis
- [ ] KPIs: mantém estilo dark original
- [ ] Breakout: gradient card legível
- [ ] Rules: timeline visível
- [ ] Trilha IA: ranking panel legível
- [ ] CPMAI: cards de certificados legíveis
- [ ] Team: fotos com bom contraste
- [ ] Resources: cards com links legíveis

### Módulos autenticados
- [ ] Profile: inputs legíveis, Credly URL field
- [ ] Attendance: tabelas legíveis
- [ ] Tribe view: board cards legíveis
- [ ] Gamification: leaderboard contraste
- [ ] Presentations: lista legível

### Admin
- [ ] Admin panel: todas as seções legíveis
- [ ] Analytics: charts com fundo correto
- [ ] Comms dashboard: Recharts com fundo correto
- [ ] Curatorship: Kanban cards legíveis
- [ ] Selection: tabelas LGPD legíveis

### Cross-cutting
- [ ] Auth modal: inputs legíveis, botões contrastantes
- [ ] Drawer do avatar: separadores visíveis
- [ ] Announcements: banners legíveis
- [ ] Toast notifications: legíveis
- [ ] Search modal: inputs e resultados legíveis
- [ ] Scroll: sem "flash" branco entre seções

---

## 6. EXEMPLO DE MIGRAÇÃO — COMPONENTE REAL

### Antes (light-only):

```html
<section class="py-16 px-6 bg-[#F7F4EF]" id="tribes">
  <div class="bg-white rounded-2xl overflow-hidden border border-black/5">
    <h3 class="text-[.95rem] font-bold text-slate-900">Radar Tecnológico</h3>
    <p class="text-[.82rem] text-slate-500">Hayala Curto, MSc</p>
  </div>
</section>
```

### Depois (themed):

```html
<section class="py-16 px-6 bg-[var(--surface-section-warm)]" id="tribes">
  <div class="bg-[var(--surface-card)] rounded-2xl overflow-hidden border border-[var(--border-subtle)]">
    <h3 class="text-[.95rem] font-bold text-[var(--text-primary)]">Radar Tecnológico</h3>
    <p class="text-[.82rem] text-[var(--text-secondary)]">Hayala Curto, MSc</p>
  </div>
</section>
```

**Zero mudança visual em light mode.** A diferença só aparece quando `data-theme="dark"`.

---

*Este design doc consolida: reestruturação de navegação (3 camadas), identidade visual (design tokens PMI), dark mode completo, e a nova página Workspace. Todas as decisões foram confirmadas pelo GP. Nenhuma permissão da PERMISSIONS_MATRIX.md é alterada.*
