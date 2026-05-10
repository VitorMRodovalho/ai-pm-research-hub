# Research — Sympla landscape + alternatives BR

**Wave 2 council research — p134 Ω-A** · 2026-05-09
**Question:** Replace Sympla com módulo interno OR integrate via API OR continuar?

## TL;DR (5 lines)

1. Sympla cobra **10% taxa serviço + 2-2.5% processamento** (~12-12.5% total) em eventos pagos. Free tier = eventos gratuitos sem fee.
2. **Sympla intermedeia o dinheiro** (D+3 útil pós-evento) e **NÃO emite NF-e em nome do produtor** — chapter PMI tem que emitir NFS-e separately ao participante; Sympla só emite NF-e da própria taxa de serviço pra organizador.
3. **API pública existe** (`api.sympla.com.br/public/v3`) mas é **majoritariamente read-only** (events/orders/participants GET). Sem POST documentado pra criar eventos. Webhook nativo limitado — ecosystem usa Pluga/Zapier/Pipedream pra cobrir gap.
4. **Mercado BR fragmentado**: Even3 (10%, focus acadêmico), Eventick (9.99%), Bilheteria Digital (10-20%), Doity (sem antecipação), Uticket (10% sem processing). **Eventbrite BR existe** mas perde share local.
5. **Recomendação: Hybrid Phase 1 → Replace Phase 2.** Manter Sympla pra eventos pagos públicos no curto prazo (compliance/checkout maduro), construir módulo interno pra eventos gratuitos + member-only (já 80%+ do volume PMI chapter). Build full replacement quando volume justify ou quando fee Sympla acumular >R$10K/ano por chapter.

## Sympla 2026 pricing

| Item | Valor |
|---|---|
| Eventos gratuitos | **R$ 0** (sem fee) |
| Taxa serviço (eventos pagos) | **10%** sobre ticket (até **15%** Sympla Streaming/presencial premium) |
| Taxa processamento | **2% – 2.5%** sobre ticket (não pode ser repassada ao comprador) |
| Mínimo por ticket | **R$ 3.99** (tickets ≤ R$ 39.90) |
| Repasse padrão | **D+3 úteis pós-evento** |
| Adiantamento pré-evento | **3.49% extra** sobre valor antecipado, até 80% das vendas |
| Conteúdo digital (Sympla Play) | D+30 |
| Tier institutional/ONG | **Não documentado público** — coupons restritos disponíveis mas sem desconto fee oficial pra nonprofit |

**Repasse opt-in:** organizador escolhe se passa os 10% ao comprador (ticket fica mais caro, custo zero pro chapter) ou absorve. Os 2-2.5% NÃO são repassáveis — sempre cai no organizador.

## Sympla API capabilities

- **Endpoint base:** `https://api.sympla.com.br/public/v3/`
- **Auth:** Token estático associado à conta do produtor (header `s_token`). **Sem OAuth 2.1**.
- **Scope:** Read-only sobre eventos do dono do token. **Não há documentação pública de endpoints POST pra criar evento programaticamente** — gestão de evento permanece via UI Sympla.
- **Endpoints documentados:**
  - `GET /events` — listar eventos
  - `GET /events/{id}/orders` — pedidos por evento
  - `GET /events/{id}/orders/{order_id}` — detalhe de pedido
  - `GET /events/{id}/participants` — participantes
- **Webhooks nativos:** Limitados / não bem documentados publicamente. Ecosystem (Zapier/Pluga/Pipedream) sugere triggers `New Order` / `New Event Created`, mas configuração e payload exato passam por third-party.
- **Rate limits:** Não publicizados claramente.
- **Doc:** https://developers.sympla.com.br/api-doc/index.html

**Implicação Núcleo IA Hub:** API serve pra **sync attendance pós-evento** (ler `participants`, fazer match com `members.email`). NÃO serve pra criar evento via MCP — tribe lead ainda faria via UI Sympla; nossa plataforma só consumiria post-hoc.

## Sympla NF-e/Cupom handling

- **Sympla NÃO emite NF-e em nome do chapter** ao participante. Quem vende serviço (chapter) é responsável pela emissão NFS-e.
- Sympla emite **uma única NF-e ao organizador** referente à própria taxa de serviço (licenciamento de software).
- Para automatizar emissão NFS-e pro participante, chapter precisa contratar **emissor integrado** (eNotas, NFE.io etc.) — fee adicional ~R$ 0.50-2.00 por nota.
- Em chapters PMI imunes ISS (CNPJ associação sem fins lucrativos categoria adequada) o gap NF-e é menor, mas auditoria fiscal ainda requer trilha documental — Sympla não substitui isso.

## Competitors BR (table)

| Tool | Fee total | API | NF-e auto | Free tier | Notes |
|---|---|---|---|---|---|
| **Sympla** | 10% + 2-2.5% (mín R$ 3.99) | Read-only, token | Não (chapter emite) | Gratuito ilimitado | Líder BR; checkout robusto; D+3 |
| **Even3** | 10% (mín R$ 2.50) | API limitada | Não | Gratuito | Forte em acadêmico/científico; cobra extra por certificado e submission |
| **Eventick** | 9.99% (Professional) | Sim, OAuth | Não | Limitado | Empresa menor, foco SMB |
| **Doity** | ~9-10% | Sim básica | Não | Gratuito | D+14 sem antecipação (limitação caixa) |
| **Bilheteria Digital** | 10-20% (variável) | Limitada | Não | N/D | Foco shows/entretenimento, não nicho corporativo |
| **Bilheteria Express** | 12% (Basic) ou 15%+2% (Premium) | N/D | Não | N/D | Nicho B2B, premium tier |
| **Uticket** | 10% (sem processing) | N/D | Não | N/D | Posiciona "sem armadilha"; menor share |
| **Eventbrite BR** | ~3.7-8.5% + fee fixo | Sim, REST + Webhooks maduros | Não BR-compliant | Eventos gratuitos sem fee | Internacional; integração superior; fricção fiscal BR |

**Observação share:** Sympla domina vertical evento corporativo/profissional/PMI no BR. Eventbrite tem brand global mas ferramentas fiscais BR fracas. Even3 ganha em academic.

## Build vs Buy analysis

### Custos atuais (per chapter)
Hipótese chapter PMI médio: 12 eventos/ano, 8 pagos × ~50 attendees × R$ 80 ticket médio = **R$ 32K/ano gross**. Sympla fee ~12% = **R$ 3.840/ano fee Sympla por chapter**.

### Custo build módulo interno (Núcleo IA Hub)
Componentes necessários:
- **Checkout + payment gateway** (Stripe BR / Pagar.me / Mercado Pago) — ~3-4% + R$ 0.40 transação (já mais barato que Sympla 12%)
- **Emissão NFS-e** — eNotas API ~R$ 0.50-2.00/nota (já necessário independente da escolha)
- **Frontend** ticket purchase + QR check-in — ~80-120h dev (~R$ 16-30K one-time)
- **Compliance fiscal** — review jurídico ~R$ 5-10K
- **Manutenção** — embedded em roadmap existing (não isolado)

### Break-even
- **Per chapter isolado**: R$ 21-40K build / R$ 3.8K fee/ano = **6-10 anos payback**. NÃO justifica per-chapter.
- **Multi-chapter SaaS**: 8 chapters × R$ 3.8K = R$ 30K/ano economizado. **Payback ~1 ano se vertical PMIS escalar**. Justifica STRONG na visão p133 chapter_pmis_saas.
- **Adicionar fee próprio Núcleo (1-2%)** pra cobrir infra: ainda 80% mais barato que Sympla pro chapter.

### Decisão financeira
Build SE roadmap PMIS multi-chapter está confirmado (p133 strategic anchor). Em isolado pra UM chapter = não vale.

## Look-alikes nonprofit/community

- **Toastmasters easy-Speak** (https://easy-speak.org) — **NÃO é ticketing**. É booking de speech roles + tracking de progress. Eventos pagos do TMI passam por **Stripe direto** ou Eventbrite ad-hoc. Volunteer-maintained, doação based.
- **WordPress for Toastmasters / Toastmost** — open source plugin, hospedado em qualquer WP. Sem ticketing nativo robusto.
- **Rotary International** — usa **plataforma própria** pra Convention global; chapters locais usam **Ticketbud** (special non-profit rates), **Eventgroove**, **MyEventsCenter**, **TicketSource** (free).
- **Lions International** — similar Rotary, fragmentado per district, Ticketbud é parceiro frequente.
- **Wild Apricot** — membership AMS com event registration **integrado**. From **$56.7/mo** flat (não per-transaction). 60-day trial. **Modelo fee fixo + sem processing fee** = sweet spot pra associations.
- **MemberClicks (MC Pro)** — AMS US heavy, **$4.5K/ano starting**. Robusto mas pesado pra chapter BR.

**Pattern observado:** associations grandes globais (Rotary, Lions) NÃO usam ticketing genérico mass-market (Sympla equivalent). Usam ou platform própria white-label, ou **AMS integrado** (Wild Apricot/MemberClicks) que combina membership + events em um único fee fixo. Isso é **exatamente o positioning Núcleo IA Hub vertical PMIS**.

## Recommendation Núcleo IA Hub

**HYBRID Path → Phase 1 (now) + Phase 2 (Q4 2026/Q1 2027)**

### Phase 1 — Sympla integration via API (now)
- Manter Sympla como ticketing provider pra eventos pagos públicos (premium webinars, paid workshops).
- Construir módulo interno SÓ pra eventos gratuitos + member-only (já cobertos por `events` table; sem checkout monetário).
- Usar Sympla API GET (`/orders`, `/participants`) como **ingestion path** — sync pós-evento pra `event_attendance` table via cron diário (pattern similar ao `pmi-vep-sync` worker).
- Webhook setup via Pluga ou Pipedream se necessário trigger imediato (~R$ 50/mo).
- **Custo:** R$ 0 build adicional (cron + RPC já no toolkit). Fee Sympla absorvido enquanto for marginal.

### Phase 2 — Replace Sympla quando triggers acontecerem
**Triggers concretos pra replace:**
1. Volume agregado multi-chapter > **R$ 30K/ano fee Sympla** (≥ 3 chapters ativos pagos).
2. Demanda de **whitelabel + own domain** validada por chapter pilot (PMI-GO/CE — diretivas p133).
3. Bug bloqueante Sympla: API mudança breaking, repasse delay, regulamentação.

**Build em Phase 2:**
- Checkout próprio (Stripe BR + Pix via Mercado Pago) com fee 1-2% Núcleo (transparente, ainda 80% mais barato que Sympla).
- NF-e/NFS-e auto via eNotas integration.
- Refund flow + chargeback management (essencial pra compliance).
- Migração gradual chapter-by-chapter (não big bang).

### Anti-recommendations (NÃO fazer)
- **NÃO** investir em build agora se PMIS multi-chapter SaaS não estiver confirmado em roadmap. Custo isolado per-chapter não justifica.
- **NÃO** depender de webhook nativo Sympla — não é confiável, usar polling + Pluga/Pipedream como fallback.
- **NÃO** assumir que Sympla emite NF-e — chapter sempre tem que emitir paralelamente (gap independe de Sympla vs interno).
- **NÃO** considerar Eventbrite pra BR — fricção fiscal pior que Sympla, brand não compensa.

## Sources

- [Sympla — Quanto Custa (preço oficial)](https://produtores.sympla.com.br/quanto-custa/)
- [Sympla — Taxa de Serviço explicada](https://blog.sympla.com.br/blog-do-produtor/taxa-de-servico-sympla/)
- [Sympla — Termos taxa e nota fiscal](https://termos-e-politicas.sympla.com.br/hc/pt-br/articles/360030732232-12-Taxas-e-emiss%C3%A3o-de-nota-fiscal)
- [Sympla — Repasse e adiantamento](https://blog.sympla.com.br/blog-do-produtor/repasse-na-sympla/)
- [Sympla — Adiantamento de Repasse 3.49%](https://produtores.sympla.com.br/funcionalidades/antecipacao-de-pagamento-sympla/)
- [Sympla — NF-e produtor responsável](https://blog.sympla.com.br/blog-do-produtor/nota-fiscal-para-eventos/)
- [Sympla API — Documentação oficial](https://developers.sympla.com.br/api-doc/index.html)
- [Sympla API integrations — Pipedream](https://pipedream.com/apps/sympla)
- [Sympla webhooks via Zapier](https://zapier.com/apps/sympla/integrations/webhook)
- [Sympla via Pluga Webhooks](https://pluga.co/ferramentas/sympla/integracao/pluga_webhooks/)
- [Even3 — Planos e preços](https://plataforma.even3.com.br/planos-e-precos/)
- [Even3 — Taxa de serviço](https://ajuda.even3.com.br/hc/pt-br/articles/204182645-Como-funciona-a-taxa-de-servi%C3%A7o-da-Even3)
- [Bilheteria Digital — Comercial](https://bilheteriadigital.com/comercial)
- [Bilheteria Express — Soluções](https://bilheteriaexpress.com.br/solucoes/index.html)
- [Doity — Plataforma](https://doity.com.br/)
- [Doity — Como escolher plataforma](https://doity.com.br/blog/melhor-plataforma-de-venda-de-ingressos/)
- [Uticket — Comparativo taxas](https://uticket.com.br/blog/comparando-taxas-de-plataformas-de-ingressos-5-armadilhas-que-reduzem-seu-lucro/)
- [Eventbrite BR — Taxas](https://www.eventbrite.com.br/help/pt-br/articles/755615/quanto-custa-para-os-organizadores-utilizarem-a-eventbrite/)
- [Toastmasters easy-Speak](https://easy-speak.org/)
- [Toastmost (WordPress for Toastmasters)](https://toastmost.org/)
- [Ticketbud — Rotary & Lions tier](https://www.ticketbud.com/event-types/rotary-club/)
- [Rotary International Convention](https://convention.rotary.org/en-us/)
- [Wild Apricot — Pricing](https://www.wildapricot.com/pricing)
- [MemberClicks — Pricing](https://memberclicks.com/membership-software-pricing/)
- [Wild Apricot vs MemberClicks (GetApp)](https://www.getapp.com/customer-management-software/a/wild-apricot/compare/memberclicks/)
