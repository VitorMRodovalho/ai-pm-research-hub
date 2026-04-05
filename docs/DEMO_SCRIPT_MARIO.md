# Demo Script — Mario Trentim
**Data:** 3 Abril 2026, 10:00 ET | **Meet:** wzh-tsmg-ven
**Duração:** 30 min (20 demo + 10 Q&A)
**Objetivo:** Mostrar a plataforma como case de inovação em governança de pesquisa com IA

---

## Roteiro (20 min)

### 1. Homepage Pública (3 min) — Impacto imediato
- **URL:** `nucleoia.vitormr.dev`
- Mostrar seção **"A plataforma em números"** (F1): 51 pesquisadores, 7 tribos, 5 capítulos, 268 eventos, 330 recursos, 77% retenção
- Scroll rápido: quadrantes de pesquisa, tribos com vídeos, trilha CPMAI, time
- **Ponto-chave:** "Tudo operacional, zero overhead manual"

### 2. Webinars Públicos (2 min) — Abertura para comunidade
- **URL:** `nucleoia.vitormr.dev/webinars`
- 3 webinars confirmados (Abr 15, 22, 29)
- Mostrar que é público — qualquer pessoa PMI pode acessar
- **Ponto-chave:** "Pipeline de webinars integrado com attendance e comms"

### 3. Login + Perfil (3 min) — Experiência do pesquisador
- Login com Google (OAuth)
- Página de perfil: completude, XP, nível, badges, streak
- **Novo (F5):** Histórico de presença pessoal — barra de progresso + tabela
- **Ponto-chave:** "Self-service — pesquisador vê tudo sem pedir ao líder"

### 4. Biblioteca com Busca (2 min) — Gestão do conhecimento
- **URL:** `nucleoia.vitormr.dev/library`
- **Novo (F4):** Buscar "agile" → resultados via RPC server-side
- Filtros por tipo + tribo + tags
- 247 recursos categorizados
- **Ponto-chave:** "Knowledge management com busca inteligente"

### 5. Attendance (3 min) — Governança operacional
- Mostrar eventos com check-in, tipos, tags
- Tab Ranking: filtro por papel operacional (S3.2)
- Quadro de presença (grid tab)
- **Ponto-chave:** "Presença automatizada, dropout risk, ranking transparente"

### 6. Board Kanban (3 min) — Gestão de artefatos
- Entrar numa tribo → tab Board
- Drag-and-drop de cards
- Status pipeline: backlog → in_progress → review → done
- Curadoria com SLA badges
- **Ponto-chave:** "Cada tribo é um mini-projeto com seu próprio board"

### 7. Admin Panel (2 min) — Visão do GP
- Dashboard admin: analytics, PostHog events nativo
- Webinar CRUD com **co-gestores** (F2) — mostrar o selector
- Governance: CRs, manual R2/R3 preview, **approval workflow com quorum 3/5**
- **Novo (Sprint 12):** Permissões por Board — BoardMembersPanel no admin
- **Ponto-chave:** "GP tem visibilidade total sem micromanagement"

### 7b. Governança Digital (2 min) — Diferenciação máxima
- **URL:** `nucleoia.vitormr.dev/governance?view=approvals`
- Mostrar: 29+ CRs pendentes, votação de sponsors, quorum automático
- Toggle **R2 (aprovado) vs Simulação R3** — diff visual (azul=novo, amarelo=atualizado)
- **Termo de Voluntariado digital** — 12 cláusulas DocuSign, assinatura SHA-256
- **Ponto-chave:** "Nenhuma CoP do PMI opera governança digital a este nível"

### 8. MCP + i18n + Diversidade (2 min) — Diferenciação técnica
- Mencionar **54 MCP tools** (Claude pode consultar a plataforma)
- Trocar para `/en/` — tudo em inglês
- **Novo:** Tab Diversidade no seletivo — 5 dimensões (gênero, capítulo, setor, senioridade, região)
- Smoke test: 11/11 (mostrar terminal se der tempo)
- **Ponto-chave:** "Trilíngue, integrável com IA, testado automaticamente, LGPD-compliant"

---

## Métricas para Citar
| Métrica | Valor |
|---------|-------|
| Pesquisadores ativos | 51 |
| Tribos de pesquisa | 7 |
| Capítulos PMI parceiros | 5 (CE, DF, GO, MG, RS) |
| Eventos realizados | 268 |
| Recursos na biblioteca | 330 |
| Retenção | 77% |
| MCP Tools | 52 |
| Edge Functions | 19 |
| Testes automatizados | 779 unit + 40 e2e |
| Smoke checks | 11/11 |

---

## Perguntas Antecipadas

**"Como escalar para outros capítulos?"**
→ Modelo multi-capítulo já funciona. Cada webinar tem chapter_code. Bastaria onboarding + CNAME.

**"Qual é o modelo de governança?"**
→ 3-eixos: operational_role (hierarquia) + designations (acumuláveis) + is_superadmin (técnico). Manual R3 no DocuSign.

**"Como funciona a IA na plataforma?"**
→ MCP Server com 54 ferramentas. Claude Chat consulta dados em tempo real. 6 hosts verificados (Claude.ai, Claude Code, ChatGPT, Perplexity, Cursor, Manus AI). PostHog analytics com dashboards nativos.

**"Qual o custo?"**
→ Supabase free tier + Cloudflare Workers free tier + domínio custom. Zero custo operacional.

---

## Checklist Pré-Demo
- [ ] Testar login OAuth (Google)
- [ ] Verificar homepage stats carregam (~51 members, 278 events, 330 resources)
- [ ] Verificar /webinars mostra 3 confirmados
- [ ] Verificar /library busca funciona
- [ ] Verificar /profile mostra attendance history
- [ ] Verificar /governance — toggle R2 vs Simulação R3
- [ ] Verificar /governance?view=approvals — 11 CRs pendentes com sponsor panel
- [ ] Verificar /volunteer-agreement — 12 cláusulas + anexo Lei 9.608
- [ ] Verificar /admin/selection tab Diversidade carrega gráficos
- [ ] Verificar /admin/governance-v2 — BoardMembersPanel visível
- [ ] Testar dark mode toggle
- [ ] Testar /en/ English version
- [ ] `npm run smoke` → 11/11
- [ ] Meet link wzh-tsmg-ven testado
