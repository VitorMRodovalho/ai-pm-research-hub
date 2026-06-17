# WhatsApp Business API (Meta): memorando de viabilidade para o Núcleo

> Estudo de viabilidade / decisão. Data: 2026-06-17. Status: recomendação registrada, aguardando discovery com BSP.
> Contexto: **executável no D0** na plataforma viva do Núcleo (este repo). Doc-espelho (ponteiro) em `pmigo-plataforma/docs/` para o contexto da plataforma futura.

## Contexto

O Núcleo opera grande parte da comunidade pelo WhatsApp (grupos com presidentes, pontos focais, membros; pré-onboarding; governança de "pessoa certa no grupo certo"). Pergunta: a **API oficial da Meta (WhatsApp Business Cloud API)** abre possibilidades para (a) o knowledge base do Núcleo e (b) o fluxo de informação entre projetos.

Este memorando existe porque a primeira leitura assumiu informação **desatualizada** em dois pontos decisivos (persistência do número e grupos). A verificação contra `developers.facebook.com` corrigiu o veredito. Objetivo: registrar **o que dá e o que não dá hoje (jun/2026)**, com citações, e recomendar um caminho de ambição **calibrada**, sem arquitetar em cima de capacidade que a Meta não confirma.

Escopo definido: objetivos = **canal de avisos/governança** + **onboarding/pré-onboarding** + **estudo de viabilidade**. Número = **Coexistence** (manter o número no aparelho). Como o Núcleo executa no D0 (a plataforma deste repo já tem o sistema de notificações vivo, com 3 modos de entrega), o caminho viável pode começar aqui sem esperar a projetização da plataforma PMI-GO.

## 1. O que a API oficial faz e NÃO faz hoje (verificado, com fonte)

| Capacidade | Veredito atual | Fonte oficial |
|---|---|---|
| **Coexistence** (app + Cloud API no MESMO número, simultâneos; número fica no aparelho) | SIM, estável. Onboarding via Solution Partner / Embedded Signup. O dono segue usando o app no celular enquanto a API opera. | [Onboarding business app users (Coexistence)](https://developers.facebook.com/docs/whatsapp/embedded-signup/custom-flows/onboarding-business-app-users/); [Migrate existing number](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/migrate-existing-whatsapp-number-to-a-business-account/) |
| **Grupos** | MUDOU (2 jun 2026): Groups API liberada para **todas as Official Business Accounts** (OBA: 30+ dias, verificação de negócio, 2FA, display name aprovado). Sem limiar de 100k/mês. | [Group messaging](https://developers.facebook.com/documentation/business-messaging/whatsapp/groups/groups-messaging/); [Changelog](https://developers.facebook.com/documentation/business-messaging/whatsapp/changelog) |
| **Grupos criados MANUALMENTE no app (os do Núcleo)** | NÃO CONFIRMADO. A doc cobre criar/enviar/ler em grupos via API; não afirma gerenciar/ler grupos pré-existentes criados no app. Pivô do "puxar conversas pro KB". | (mesma acima, ambiguidade explícita) |
| **Webhook entrega o que passa pelo aparelho em Coexistence?** | UNCERTAIN. A doc não especifica se mensagens que o humano envia/recebe pelo celular chegam ao webhook. Decide a ingestão de conversas no KB. | [Webhooks](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks/) |
| **Histórico de conversas (conteúdo)** | NÃO. Coexistence "preserva" o histórico no aparelho, não sincroniza pra API. Message History API = só metadados de entrega (enviado/entregue/lido), não o texto. Sem bulk import. | [Message History Events API](https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/message-history/whatsapp-business-message-history-events-api) |
| **Mensagens 1:1 recebidas (dali pra frente, via webhook)** | SIM | [messages webhook](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages) |
| **Flows (formulários) + mensagens interativas (botões/listas)** | GA, ótimo para onboarding | [WhatsApp Flows](https://developers.facebook.com/docs/whatsapp/flows/); [Interactive messages](https://developers.facebook.com/docs/whatsapp/guides/interactive-messages/) |
| **Opt-in + janela de 24h** | Opt-in explícito obrigatório p/ business-initiated; janela de atendimento de 24h permite mensagens de serviço livres | [Opt-in](https://developers.facebook.com/documentation/business-messaging/whatsapp/getting-opt-in); [Policy](https://developers.facebook.com/documentation/business-messaging/whatsapp/policy-enforcement) |
| **Preço (modelo desde 1 jul 2025)** | Por mensagem entregue. Serviço dentro da janela 24h = grátis; utility dentro da janela = grátis; marketing/auth = cobrados. Free entry point abre janela de 72h. BR fatura em BRL a partir de 1 jul 2026; rate card BRL não é público (pedir ao BSP). | [Pricing](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing); [Pricing updates Jul 2025](https://developers.facebook.com/docs/whatsapp/pricing/updates-to-pricing/) |

**Rota não-oficial** (Baileys / whatsapp-web.js) lê grupos e histórico, mas viola os Termos da Meta e arrisca banimento do número. Incompatível com o contexto de governança/LGPD do Núcleo. Desaconselhada para a org.

## 2. Veredito por objetivo

1. **Canal de avisos/governança (outbound)**: VIÁVEL JÁ. Lembretes de evento/webinar, alerta de onboarding atrasado, avisos de governança, digest. Encaixa como 4º modo de entrega no sistema de notificações que a plataforma do Núcleo já tem vivo (`transactional_immediate` / `digest_weekly` / `suppress`). Custo baixo (boa parte cai em utility/serviço dentro de janela = grátis).
2. **Onboarding / pré-onboarding**: VIÁVEL JÁ. Flows + botões + utility templates para lembrar o passo pendente. A plataforma já modela `pre_onboarding`, passos com CTA e dashboard de atrasados; falta só `whatsapp_phone` + `opt_in`.
3. **Ingerir conversas/grupos da comunidade no KB (ambição original)**: NÃO para histórico; forward-only 1:1 com opt-in; grupos manuais = não confirmado. Não arquitetar em cima disso até validar com um BSP. É o ponto fraco real; tratar como hipótese a testar, não como capacidade dada.

## 3. Arquitetura recomendada (alto nível)

- **Onboarding via Solution Partner (BSP) com Coexistence** no número do Núcleo que já existe, mantendo o app no celular funcionando.
- **Webhook → Cloudflare Worker → DB da plataforma** (mesma stack da plataforma viva do Núcleo). Acrescentar `members.whatsapp_phone` (E.164) + `members.whatsapp_opt_in` + log de consentimento.
- **WhatsApp como 4º canal** no sistema de notificações existente (reuso, não greenfield paralelo).
- **Flows** para passos de onboarding; **utility templates** para governança/eventos (grátis dentro da janela).
- **LGPD**: opt-in na entrada, log de consentimento, opt-out por categoria, aviso de privacidade em PT, retenção definida. A plataforma já tem ferramentas `lgpd_*` para apoiar.
- **BSP candidatos**: 360dialog (markup baixo, API pura), Twilio (ecossistema), Gupshup (LATAM), ou BSP BR (Zenvia/Take Blip). Direto na Meta = custo menor, mas constrói-se tudo.

## 4. Questões abertas a resolver ANTES de comprometer

> Roteiro de discovery pronto para a conversa/teste com BSP: [`whatsapp_bsp_discovery_roteiro.md`](./whatsapp_bsp_discovery_roteiro.md) (pauta, perguntas verificáveis, critérios de decisão e mini-teste de validação).

Resolver com 1 ou 2 BSPs numa conversa de discovery / teste curto:

1. Em Coexistence, o webhook entrega mensagens que chegam/saem pelo aparelho? (decide ingestão 1:1 no KB)
2. A Groups API gerencia/lê grupos criados manualmente no app, ou só os criados pela API? (decide governança de grupos via plataforma, provavelmente não)
3. Rate card BRL para o Brasil (pedir ao BSP).
4. BSP escolhido vs. integração direta na Meta.

## 5. Recomendação

Seguir com ambição calibrada: WhatsApp como **canal outbound + de onboarding** da plataforma (objetivos 1 e 2), via Coexistence no número atual (mantém o app). Tratar "ingerir conversas/grupos da comunidade no KB" como fora de escopo até validação, sem desenhar nada dependente disso. Próximo passo: discovery com BSP para fechar as 4 questões; só então um spec de piloto.

Ângulo de portfólio: o padrão "webhook → Worker → DB" + "WhatsApp como N-ésimo canal de notificação opt-in" é reusável em outros projetos (incl. a futura `pmigo-plataforma`).
