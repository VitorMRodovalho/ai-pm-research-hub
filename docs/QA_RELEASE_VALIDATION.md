# QA/QC — Validação de Release

Checklist de qualidade para garantir que cada release não afeta usabilidade nos ambientes principais. **Executar antes de considerar release concluído.**

---

## 1. Validação de Scripts (Console F12)

### Regra: nenhum erro de script no console

- [ ] Abrir DevTools (F12) → aba **Console**
- [ ] Navegar pelas rotas principais sem erros em vermelho
- [ ] Rotas obrigatórias: `/`, `/profile`, `/attendance`, `/gamification`, `/artifacts`, `/admin`

### Erro conhecido evitado (março 2026)

**"Cannot use import statement outside a module"** — Ocorria em páginas Astro com `<script define:vars={{ ... }}>` e `import` no mesmo bloco. A diretiva `define:vars` força `is:inline`, impedindo o bundler de processar imports.

**Solução aplicada**: Separar em dois scripts:
1. Um `is:inline define:vars` que injeta valores em `window.__*`
2. Um script normal com imports que lê de `window.__*`

**Páginas que usavam esse padrão**: admin, profile, admin/member/[id].

### Checklist rápido pós-deploy

- [ ] `/admin` carrega sem travar em "Verificando acesso"
- [ ] Console sem `SyntaxError` ou `Uncaught` em rotas críticas

---

## 2. Validação Cross-Browser

Toda release deve ser validada nos principais tipos de browser em **Windows**, **Mac**, **iPhone** e **Android**.

### Matriz mínima

| Plataforma | Browsers | Foco |
|------------|----------|------|
| **Windows** | Chrome, Edge, Firefox | Desktop padrão |
| **macOS** | Safari, Chrome | Desktop Apple |
| **iPhone** | Safari, Chrome (se instalado) | Mobile iOS |
| **Android** | Chrome | Mobile Android |

### Checklist por rota (amostra em 2+ ambientes)

- [ ] Login (OAuth LinkedIn) funciona
- [ ] Profile: visualização e edição
- [ ] Attendance: lista de eventos, check-in
- [ ] Gamification: leaderboard, Meus Pontos
- [ ] Admin: painel principal carrega (tier apropriado)
- [ ] Artifacts: catálogo e submissão

### Problemas comuns por ambiente

| Ambiente | Atenção |
|----------|---------|
| Safari (iOS) | Paste em input Credly pode exigir delay; CSP e cookies |
| Chrome Android | Viewport, touch targets |
| Firefox | Alguns recursos de auth |

---

## 3. Integração com Release Process

- Antes de marcar release como concluído: executar seção 1 (Console) + amostra da seção 2 (Cross-Browser).
- Registrar evidência em `docs/RELEASE_LOG.md` quando houver validação explícita.
- Falhas encontradas: criar issue, referenciar no release log.
