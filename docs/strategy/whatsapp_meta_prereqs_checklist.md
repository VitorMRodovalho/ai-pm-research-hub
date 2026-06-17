# Checklist de pré-requisitos Meta — WhatsApp Business API (Núcleo)

> Companheiro de `whatsapp_business_api_viability.md` e `whatsapp_bsp_discovery_roteiro.md`. Data: 2026-06-17.
> Uso: destravar os pré-requisitos da Meta em paralelo à discovery com BSP. Vários itens têm lead time de dias, então começar cedo. Marque `[x]` ao concluir e preencha owner/data.

## Ordem recomendada (caminho crítico)

1 → 2 → 3 são sequenciais e têm o maior lead time (verificação de negócio). 4 e 5 podem andar junto. 6 só depois de definir o BSP (bloco A do roteiro).

---

## 1. Conta e identidade de negócio

- [ ] **Meta Business Account (Business Manager / business.facebook.com)** ativa para o Núcleo/PMI-GO. Owner: ____  Data: ____
- [ ] **Business Verification** (verificação de negócio) submetida e aprovada. Exige documentos oficiais da organização (registro/CNPJ, comprovante, etc.). Lead time típico: alguns dias úteis. Owner: ____  Status: ____
  - Decisão prévia: a conta vai no CNPJ do **PMI-GO/capítulo** ou em outra entidade? (define quem assina os documentos). Definir: ____

## 2. WhatsApp Business Account (WABA)

- [ ] **WABA criada** dentro do Business Manager (após verificação). Owner: ____  Data: ____
- [ ] Definido se a WABA será criada **direto na Meta** ou **via BSP/Solution Partner** (recomendado pelo roteiro). Decisão: ____

## 3. Official Business Account (OBA) — requisito da Groups API e do membership sync

Sem OBA, a Groups API (objetivo-âncora do piloto) não se aplica. Critérios a cumprir:

- [ ] **30+ dias** de conta na plataforma. Data de início: ____
- [ ] **Business verification** aprovada (item 1).
- [ ] **Two-step verification (2FA)** ativada no número. Owner: ____
- [ ] **Display name aprovado** (nome de exibição do negócio). Submetido: ____  Aprovado: ____
- [ ] (Se aplicável) bom histórico de qualidade de mensageria do número.

## 4. Número de telefone (estratégia Coexistence)

- [ ] **Número definido** que entrará na API. Decisão: usar o número do **WhatsApp Business do Núcleo já em uso** via **Coexistence** (mantém o app no aparelho) — confirmada como preferência. Número: ____
- [ ] Confirmado que o BSP escolhido suporta **Embedded Signup com Coexistence** (item do bloco A do roteiro).
- [ ] **2FA** ativado nesse número (mesmo item do OBA).
- [ ] Acesso ao número para receber o **OTP** de ativação no momento do onboarding. Owner: ____
- [ ] Plano B documentado: se Coexistence não rolar com o BSP, decidir entre número novo dedicado vs. migração (ver memorando).

## 5. Política, consentimento e LGPD (preparar em paralelo)

- [ ] **Opt-in** desenhado: como/onde o membro consente receber mensagens e **ser adicionado ao grupo da tribo** (provável invite-only). Encaixar no onboarding da plataforma.
- [ ] **Aviso de privacidade em PT** vinculado ao perfil de WhatsApp do negócio.
- [ ] **Opt-out** por categoria e **retenção** definidos (a plataforma já tem ferramentas `lgpd_*`).
- [ ] Base legal definida para eventual **export de conteúdo** de grupos antigos (se a migração de grupos avançar).

## 6. Integração técnica (depois de escolher BSP — não bloqueia 1–5)

- [ ] **Webhook URL HTTPS** pública + token de verificação (Cloudflare Worker).
- [ ] Credenciais/API key do BSP ou do app Meta.
- [ ] **Templates** iniciais (utility) submetidos para aprovação (lembrete de evento, passo de onboarding atrasado).
- [ ] Campos novos no schema: `members.whatsapp_phone` (E.164) + `members.whatsapp_opt_in` + tabela de grupos/mapeamento (entra no spec do piloto).

---

## O que NÃO depende deste checklist
- A decisão de qual BSP (bloco A/E do roteiro) e as 4+ questões de viabilidade (B1/B2/B5) seguem em paralelo na discovery.
- O **spec do piloto** só depois das respostas de B5/B1/B2.

## Itens que precisam de informação externa (você confirma)
- CNPJ/entidade da conta Meta; documentos de verificação; número do WhatsApp Business do Núcleo; quem tem acesso ao OTP; status atual de qualquer conta Meta Business já existente.
