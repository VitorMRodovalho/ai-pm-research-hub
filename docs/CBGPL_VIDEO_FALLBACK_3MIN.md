# Video Fallback — 3 min (CBGPL 2026)

**Uso:** Plano B se Wi-Fi falhar na Arena durante o demo de 20min. Vídeo pré-gravado reproduz o núcleo do pitch sem depender de rede ao vivo. Também serve como pré-evento/pós-evento share (LinkedIn, WhatsApp, email).

**Formato:** screen-recording + voice-over (sem face-cam obrigatório). 1080p, H.264, arquivo `.mp4` < 150MB.
**Ritmo:** ~150 palavras/minuto → total ~450 palavras.
**Idioma:** português (versão `pt.mp4`). Versão `en.mp4` opcional para AIPM Ambassadors.
**Produção:** 30-45min gravação + 30min edição. Ferramentas: OBS/Loom + DaVinci Resolve ou iMovie.

---

## Preparação

- [ ] Chrome limpo, 1920x1080, dark mode OFF
- [ ] Tab 1: `nucleoia.vitormr.dev` (homepage)
- [ ] Tab 2: `nucleoia.vitormr.dev/governance`
- [ ] Tab 3: Claude.ai com MCP Núcleo conectado (76 tools)
- [ ] Cursor tracking: destacar com Focusly ou macOS built-in
- [ ] Áudio: microfone USB, ambiente silencioso, sem pop filter = sem P explosion
- [ ] Script em teleprompter (prompsmart/TeleprompterPro) ou monitor secundário

---

## Roteiro (3 min)

### 0:00–0:25 — Hook (25s)

**CUE:** logo do Núcleo em fade-in + texto "CBGPL 2026 — Gramado, 28-30 Abr"

> "Ricardo Vargas vai abrir o CBGPL falando de copiloto de IA para projetos. Gêmeos digitais. O futuro do gerenciamento de projetos.

> O Núcleo de Pesquisa em IA e GP — uma iniciativa de cinco capítulos PMI no Brasil — já está operando exatamente isso. Com 52 voluntários, 7 tribos de pesquisa, e 76 ferramentas de IA acessíveis por qualquer host compatível."

---

### 0:25–1:15 — Plataforma pública (50s)

**CUE:** Tab 1 — Homepage. Scroll suave até "A plataforma em números".

> "Isto é a homepage pública. 52 pesquisadores, 5 capítulos PMI, 7 tribos ativas, 267 eventos realizados. Tudo operacional, tudo atualizado em tempo real. Zero planilha, zero overhead manual."

**CUE:** scroll até quadrantes de pesquisa (4 quadrants) + tribos.

> "As quatro frentes de pesquisa cobrem desde o praticante de GP individual até governança ética de IA. Cada tribo tem sua página, seu board kanban, seu quadro de entregáveis."

**CUE:** Tab 2 — `/governance`. Expand 1 section (ex: "Processo de Seleção").

> "E este é o manual de governança. Público. Qualquer pessoa pode ler nossas regras, processos, papéis, e decisões. Documento assinado no DocuSign — código de verificação B2AFB185. Transparência é valor PMI."

---

### 1:15–2:25 — IA ao vivo (70s)

**CUE:** Tab 3 — Claude.ai. Mostrar "MCP Núcleo conectado · 76 tools".

> "Agora o que diferencia: a plataforma expõe 76 ferramentas via Model Context Protocol. Qualquer host de IA compatível — Claude, ChatGPT, Cursor, Perplexity — pode operar a plataforma com OAuth 2.1 e permissões por papel."

**CUE:** Digitar prompt: "Qual o status do portfolio do Núcleo?"

> "Eu pergunto ao Claude: qual o status do portfolio do Núcleo?"

**CUE:** Claude executa `get_portfolio_overview`. Mostrar tool call visível + resposta.

> "Ele chama a ferramenta `get_portfolio_overview`, retorna os KPIs, saúde das tribos, entregas em curso. Não é chatbot genérico — é IA operando na base de dados real com LGPD compliance, audit log, e RLS por linha."

**CUE:** Segunda query: "Quem são os próximos líderes?"

> "Segunda pergunta, segunda ferramenta, mesmo fluxo. A IA é copiloto operacional, não assistente decorativo."

---

### 2:25–2:55 — Escala e convite (30s)

**CUE:** Split-screen com métricas: 1186 testes · 22 Edge Functions · R$ 0/mês · Open source.

> "1186 testes automatizados. 22 Edge Functions. Custo de infraestrutura: zero — free tier Cloudflare e Supabase. Código aberto. Qualquer capítulo PMI pode replicar."

**CUE:** Logo AIPM Ambassadors + URL `nucleoia.vitormr.dev`.

> "Vitor Rodovalho e Fabrício Nóbrega são embaixadores AIPM oficialmente — programa de Ricardo Vargas e Antonio Nieto-Rodriguez. Converse conosco em Gramado."

---

### 2:55–3:00 — Sign-off (5s)

**CUE:** Card final com URL, GitHub, e-mail de contato.

> "Núcleo IA. Pesquisa aberta. Plataforma aberta. nucleoia.vitormr.dev."

---

## Pós-gravação

- [ ] Renderizar em `.mp4` 1080p, bitrate 5-8 Mbps
- [ ] Comprimir com Handbrake se > 150MB (target: compatível com WhatsApp/email)
- [ ] Subir em 3 locais (redundância):
  - YouTube unlisted (link curto para apresentação)
  - Google Drive (download offline para a Arena — pen drive backup)
  - Repo `nucleo-ia-gp/frameworks` pasta `assets/` (permanência pública)
- [ ] Testar reprodução offline em notebook de apresentação antes de viajar
- [ ] Versão em inglês: re-gravar com mesmo script, mesmo timing, inglês americano neutro

---

## Métricas a citar (verificar antes de gravar)

| Fonte de verdade | Número atual (17/Abr) |
|---|---|
| `CLAUDE.md` — Platform version | v3.2.0 |
| `CLAUDE.md` — MCP tools | 76 (61R + 15W) |
| `CLAUDE.md` — Edge Functions | 22 |
| `CLAUDE.md` — Tests | 1186 unit + 40 e2e |
| Homepage `nucleoia.vitormr.dev` | 52 pesquisadores, 7 tribos, 5 capítulos |
| Homepage | 267 eventos (verificar via admin dashboard D-1) |

> **Anti-drift:** Re-verificar esses números no dia 27/Abr antes da viagem. Se mudarem, re-gravar apenas os segmentos afetados (modular editing).

---

## Variantes de uso

| Contexto | Duração | Corte |
|---|---|---|
| Fallback Arena (plano B integral) | 3:00 | versão completa |
| Social pré-congresso (LinkedIn/Insta) | 0:45 | Hook + plataforma pública |
| Social pós-congresso | 1:30 | Hook + IA ao vivo + convite |
| Conversão (abordagem direta a chapter) | 0:25 | Hook isolado, dropbox link pro demo completo |
