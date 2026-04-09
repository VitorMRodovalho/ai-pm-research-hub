# Demo Script — CBGPL 2026 (Congresso Brasileiro de GP e Lideranca)

**Evento:** 21o CBGPL, 28-30 Abr 2026, Gramado/RS
**Duracao:** 20 min demo (Arena slot) + 5 min live Q&A
**Objetivo:** Apresentar a plataforma como implementacao real de "IA Copiloto para Projetos" — conectar com keynote do Ricardo Vargas
**URL:** `nucleoia.vitormr.dev`

---

## Preparacao Pre-Demo

- [ ] Chrome limpo (sem extensoes visiveis, dark mode OFF)
- [ ] Tab 1: Homepage (nao logado)
- [ ] Tab 2: /governance (nao logado — manual publico)
- [ ] Tab 3: Pre-logado como GP (Vitor)
- [ ] Tab 4: Admin dashboard
- [ ] Tab 5: Claude.ai com MCP conectado (56 tools)
- [ ] Wi-Fi testado + hotspot backup
- [ ] Screenshot fallback de cada tela (caso offline)

---

## Roteiro (20 min)

### ACT 1: Impacto Publico (5 min) — "O que qualquer pessoa ve"

#### 1.1 Homepage (2 min)
- **URL:** `nucleoia.vitormr.dev`
- Scroll ate "A plataforma em numeros": **52 pesquisadores, 7 tribos, 5 capitulos, 209 eventos, 330+ recursos**
- Mostrar quadrantes de pesquisa + tribos com videos
- > "Tudo isso operacional, atualizado em tempo real, zero overhead manual"

#### 1.2 Governanca Publica (2 min) — NOVO
- **URL:** `nucleoia.vitormr.dev/governance`
- Manual de Governanca e Operacoes R2 — 33 secoes, navegacao completa
- > "Nosso manual de governanca e publico. Qualquer pessoa pode ler nossas regras, processos, e como operamos. Transparencia e valor PMI."
- Expandir 1-2 secoes (ex: "Processo de Selecao", "Governanca de Dados")
- Destacar: "DocuSign B2AFB185 — documento assinado, versionado, acessivel"

#### 1.3 Blog + Webinars (1 min)
- Scroll rapido: `/blog` (artigos publicados), `/webinars` (calendario publico)
- > "Producao intelectual e engajamento comunitario abertos"

---

### ACT 2: Experiencia do Membro (5 min) — "O dia-a-dia do pesquisador"

#### 2.1 Perfil (1.5 min)
- Login ja feito (Tab 3) → Perfil
- XP, nivel, badges, streak de presenca
- Onboarding checklist (100% completo)
- > "Self-service total — o pesquisador ve tudo sem pedir ao lider"

#### 2.2 Tribo + Kanban (2 min)
- Tribe dashboard: membros, presenca, entregaveis
- Board kanban: cards com SLA, tags, lifecycle
- > "Cada tribo opera como um mini-projeto com visibilidade total"

#### 2.3 Gamificacao + Certificados (1.5 min)
- `/gamification`: Leaderboard, XP por acao, sistema de niveis
- `/certificates`: Certificados emitidos com QR code de verificacao
- > "Reconhecimento formal — PDUs, horas voluntarias, competencias"

---

### ACT 3: Governanca Inteligente (5 min) — "Como a IA opera nos bastidores"

#### 3.1 Admin Dashboard (2 min)
- Tab 4: KPI cards com progresso real-time
- SyncHealth widget (cron job monitoring)
- > "Dashboard executivo: 18 KPIs com auto-refresh via Artia + Supabase"

#### 3.2 Selecao + Diversidade (1.5 min)
- `/admin/selection`: Pipeline de selecao
- Diversity Dashboard: genero, setor, senioridade — 70/70 preenchidos
- > "Processo seletivo estruturado com analytics de diversidade — LGPD compliant"

#### 3.3 Termo de Voluntariado (1.5 min)
- `/admin/certificates`: Painel de termos
- Template preview → assinatura → contra-assinatura pelo chapter board
- Verificacao publica: `/verify/[code]`
- > "Workflow completo: criacao, assinatura, contra-assinatura, verificacao publica"

---

### ACT 4: IA Copiloto ao Vivo (5 min) — "A conexao com o tema do Vargas"

#### 4.1 MCP — 56 Ferramentas (3 min)
- Tab 5: Claude.ai com MCP conectado
- Mostrar tools list: 56 ferramentas (47 leitura + 9 escrita)
- **Query ao vivo:** "Qual o status do portfolio do Nucleo?"
  - Claude consulta `get_portfolio_overview` → retorna KPIs, tribos, saude
- **Segunda query:** "Liste os proximos eventos da minha tribo"
  - Claude consulta `get_near_events` → retorna calendario
- > "A IA nao e um chatbot generico — ela OPERA na plataforma com OAuth 2.1, permissoes por papel, e audit log"

#### 4.2 Escala e Reproducibilidade (2 min)
- > "Esta plataforma roda em 21 Edge Functions, 56 ferramentas MCP, 779 testes automatizados"
- > "Custo de infraestrutura: R$ 0/mes (free tier Cloudflare + Supabase)"
- > "Qualquer capitulo PMI pode replicar: codigo aberto, documentacao completa"
- > "O que o Ricardo Vargas descreve como futuro — nos ja estamos operando"

---

## Pontos-Chave para Q&A

| Pergunta provavel | Resposta curta |
|---|---|
| "Quanto custa?" | R$ 0/mes — free tier Cloudflare Workers + Supabase |
| "Quantas pessoas usam?" | 52 pesquisadores ativos, 5 capitulos, 6 hosts MCP verificados |
| "A IA substitui o lider?" | Nao — ela AMPLIFICA. O lider decide, a IA executa consultas e relatorios |
| "Como garantem LGPD?" | RLS por linha, SECURITY DEFINER RPCs, zero PII para anon, audit log |
| "Podem replicar para outro capitulo?" | Sim — plataforma e multi-tenant ready, manual de governanca publico |
| "Quais IAs sao suportadas?" | Claude.ai, ChatGPT, Cursor, Perplexity, Manus AI, Claude Code — 6 hosts verificados |

---

## Evitar Durante o Demo

- Admin pages com poucos dados (partnerships, pilots detalhado)
- Features em desenvolvimento (auto_query KPI refresh)
- Temas sensiveis (membros inativos, dropout)
- Detalhes tecnicos profundos (save para 1:1 com interessados)

---

## Metricas para Citar

| Metrica | Valor |
|---|---|
| Pesquisadores ativos | 52 |
| Tribos de pesquisa | 7 |
| Capitulos participantes | 5 |
| Eventos realizados | 209 |
| Horas de encontros | 72h |
| Recursos na biblioteca | 330+ |
| Ferramentas MCP | 56 |
| Edge Functions | 21 |
| Testes automatizados | 779 |
| Custo infra/mes | R$ 0 |
