# Roteiro de discovery com BSP — WhatsApp Business API (Núcleo)

> Companheiro de `whatsapp_business_api_viability.md`. Data: 2026-06-17.
> Uso: pauta para conversa/teste com 1 ou 2 Business Solution Providers (BSP) ou para avaliar integração direta na Meta, antes de comprometer com um piloto.
> Regra de ouro: **exigir confirmação por escrito / demonstração**, não promessa de vendedor. As 4 questões críticas (bloco B) decidem o escopo; se o BSP titubear, é sinal.

## 0. Contexto curto para dar ao BSP

- Comunidade do Núcleo (PMI), com governança por tribos/iniciativas, papéis (presidentes, pontos focais, membros), pré-onboarding e onboarding por etapas.
- Já existe plataforma própria (Cloudflare Workers + DB) com sistema de notificações vivo em 3 modos (imediato transacional, digest semanal, suppress). Queremos **WhatsApp como 4º canal**.
- Número atual é um **WhatsApp Business app** em uso diário; **não** queremos perdê-lo. Logo, **Coexistence é requisito**.
- Objetivos no D0: avisos/governança (outbound) + onboarding/pré-onboarding. Ingestão de conversas no knowledge base é hipótese a validar, não requisito.

## A. Qualificação do BSP (rápida)

1. Vocês são **Solution Partner oficial** da Meta? Desde quando? Listados no diretório oficial?
2. Suportam **Embedded Signup com Coexistence** (onboarding de número que já roda no WhatsApp Business app)? É GA no seu produto ou beta?
3. Atendem **Brasil** com faturamento/rate card em **BRL**? Mostram o rate card por categoria (marketing/utility/authentication)?
4. **Markup** sobre a tarifa Meta: quanto e como (por mensagem, mensalidade, setup)? Há custo de número/linha?
5. Onde ficam hospedados os dados (data residency)? Têm **DPA/LGPD** e suporte a opt-out e retenção configurável?
6. Dão **API pura** (preferência) ou forçam uma UI/inbox proprietária? Webhooks crus repassados para nosso Worker?
7. SLA de suporte, limites de rate (msg/seg), sandbox/ambiente de teste.

## B. As 4 questões críticas (pedir confirmação por escrito + teste)

Estas definem se a ambição maior (KB / grupos) entra ou fica de fora.

**B1. Webhook em Coexistence (decide ingestão 1:1 no KB).**
Com Coexistence ativo no nosso número, o webhook recebe:
- (a) mensagens 1:1 que **chegam** ao número enquanto o app está em uso no celular?
- (b) mensagens que o **humano envia/recebe pelo aparelho** (não pela API)?
- Pedido: confirmar por escrito o que aparece no webhook em cada caso e **demonstrar num número de teste**.

**B2. Grupos (decide governança de grupos via plataforma).**
- A Groups API consegue **ler/gerenciar grupos criados manualmente** no app (os que já temos), ou só grupos **criados pela própria API**?
- Em grupo onde nosso número é admin, o webhook entrega as **mensagens dos membros**?
- Quais requisitos de Official Business Account (OBA) precisamos cumprir? Em quanto tempo?
- Pedido: confirmar por escrito + demonstrar (criar grupo via API e adicionar um número de teste; tentar plugar um grupo existente).
- **Contexto nosso (peso alto):** já temos ≥10 grupos ativos criados manualmente (7 tribos + Hub + CPMAI + LATAM, ver bloco D). Se a API só opera grupos criados por ela, a governança dos grupos atuais **não** migra, e esse objetivo cai. Perguntar explicitamente se há caminho para "adotar" um grupo existente.

**B3. Rate card BRL (decide custo real).**
- Tabela por categoria em BRL, vigente, com data. O que é grátis (serviço/utility dentro da janela de 24h, free entry point de 72h)?
- Estimativa para nosso volume (ver bloco D).

**B4. Persistência e reversibilidade do número.**
- Confirmar que, com Coexistence, o número **continua ativo no aparelho**.
- Como é o **rollback** (sair da API e voltar ao app puro) e o que acontece com o histórico nesse processo?

**B5. Sincronização de membership (governança automatizada — provável objetivo do piloto).**
Cenário: a plataforma é a fonte da verdade de "quem está em qual tribo/iniciativa"; o grupo do WhatsApp passa a ser projeção dela.
- **Remover** participante via API (membro inativado na tribo sai do grupo): suportado para o número de negócio como admin? É confiável/imediato?
- **Adicionar**: é **add direto** ou apenas **envio de convite** que o usuário precisa aceitar (opt-in)? (esperamos invite-only). Como funciona o link/convite por participante?
- A API emite **webhook de mudança de participante** (entrou/saiu, incl. saídas manuais pelo app)?
- Dá para **listar os participantes atuais** de um grupo (necessário para job de **reconciliação** plataforma × grupo)?
- **Co-admin humano**: líderes de tribo podem ser admins do grupo, ou é single-admin (só o número de negócio)?
- Limites de rate para add/remove em lote (ex.: virada de ciclo com muitos movimentos).

### Nota de desenho — visibilidade do link e jornada de entrada
Para grupos governados, **não** expor link de auto-entrada no frontend (link público mata o "pessoa certa no grupo certo"). Recomendado: `group_id`/link em **tabela** (a API opera por ele + break-glass) + **jornada de entrada por aprovação** numa área de governança (diretoria/presidência/ponto focal solicita → aprovador aprova → API envia convite → logado no audit trail). Entrar/sair é **derivado** da participação na tribo/iniciativa; a área de governança trata exceções. A automação só é confiável com **job de reconciliação** (drift é inevitável: saídas manuais, convites não aceitos).

## C. Capacidades para os casos de uso do D0

1. **Templates utility/marketing/auth**: fluxo e prazo de aprovação; quantos templates; categorização automática.
2. **WhatsApp Flows** (formulários) e **mensagens interativas** (botões/listas) para onboarding: suportados? exemplos?
3. **Janela de 24h / free entry point**: como o produto ajuda a manter conversas dentro da janela (grátis)?
4. **Opt-in**: como capturam e registram consentimento; double opt-in; opt-out por categoria.
5. **Identidade/marca**: aprovação de display name; selo de conta verificada.

## D. Dados nossos para a estimativa (preenchido via plataforma, snapshot 2026-06-17)

Fonte: MCP da plataforma viva (`get_admin_dashboard`, `get_onboarding_dashboard`, `list_initiatives`, `search_members`). Campos com `____` ainda dependem de dado externo ao sistema.

- **Membros ativos:** 47.
- **Pré-onboarding:** 27 membros com status `pre_onboarding` (todos `term_status: amber`, aguardando o termo de voluntário). O dashboard ainda sinaliza "29 pesquisadores sem tribo" (mesma ordem de grandeza).
- **Pipeline de onboarding (7 passos):** 74 pessoas no total; 17 não iniciaram, ~44 em progresso, 13 concluídas. Alvo direto de lembretes por WhatsApp (~61 ainda não concluíram).
- **Tribos/iniciativas:** 16 iniciativas ativas, das quais **7 tribos de pesquisa** (de 8 no modelo) + Hub de Comunicação, Comitê de Curadoria, Publicações & Submissões, Grupo de Estudos CPMAI, Capilarização CPMAI, Newsletter e 3 eventos (Webinar 30/jun, Mesa Vassouras, LATAM LIM).
- **Grupos de WhatsApp já existentes (relevante para B2):** ao menos **10 grupos** já registrados na própria plataforma (campo `whatsapp_url`): as 7 tribos + Hub de Comunicação + Grupo de Estudos CPMAI + LATAM LIM. **Todos criados manualmente** (links `chat.whatsapp.com/...`), exatamente o caso que a Groups API provavelmente NÃO gerencia. Tamanho médio de cada grupo não está na plataforma (dado externo do WhatsApp): ____.
- **Volume estimado/mês (refinar):** reuniões de tribo recorrentes (~7 tribos, cadência semanal) ≈ ~28 lembretes/mês; eventos/webinars ≈ 1 a 3/mês; lembretes de passo de onboarding para ~61 pessoas. A maioria cai em utility/serviço dentro da janela de 24h (custo baixo ou zero).
- **Número(s) que entrariam em Coexistence:** número do WhatsApp Business do Núcleo (não consta na plataforma): ____.
- **Verificação de negócio na Meta Business?** não consta na plataforma; confirmar (sim/não): ____.
- **Telefone dos membros:** a plataforma hoje guarda e-mail, **não** telefone. `members.whatsapp_phone` (E.164) + `whatsapp_opt_in` são campos novos a criar (previsto no memorando §3).

## E. Critérios de decisão (comparar BSPs)

| Critério | Peso | BSP A | BSP B | Meta direto |
|---|---|---|---|---|
| Coexistence GA (B1/B4) | alto | | | |
| Clareza grupos (B2) | alto | | | |
| Custo total BRL (B3) | alto | | | |
| API pura / webhooks crus | médio | | | |
| LGPD / data residency | médio | | | |
| Suporte / SLA | médio | | | |
| Esforço de integração nosso | médio | | | |

## F. Mini-teste de validação (antes de fechar)

Pedir ao BSP um ambiente de sandbox e rodar, num número de teste:
1. Coexistence ligado → mandar 1:1 de fora e do aparelho → conferir o que cai no webhook (B1).
2. Criar grupo via API + adicionar número de teste → conferir webhook de mensagem de membro (B2).
3. Tentar plugar um grupo **já existente** → confirmar se dá ou não (B2).
4. Enviar 1 utility template dentro e fora da janela de 24h → conferir cobrança (B3).

## G. Próximos passos

1. Preencher bloco D.
2. Rodar discovery com 2 BSPs (sugestão: um de markup baixo/API pura tipo 360dialog + um BR tipo Zenvia/Take Blip) e, em paralelo, checar viabilidade direta na Meta.
3. Registrar respostas na tabela E + anexar confirmações por escrito.
4. **Objetivo provável do piloto = membership sync governado** (remove automático na inativação + entrada por convite aprovado, link fora do frontend), em 1 grupo criado pela API. É mais sólido que o KB e serve direto a "pessoa certa no grupo certo"; depende de B5 (e de migrar o grupo, ver lição [LL]).
5. Se B5 vier favorável (remove confiável + webhook de participante + listar participantes): piloto de membership sync em 1 grupo, com job de reconciliação. KB de conversas fica para 2ª onda (depende de B1/B2).
6. Se B1/B2/B5 vierem negativos: manter escopo em outbound + onboarding (sem grupos/KB) e seguir para spec de piloto desse recorte.
