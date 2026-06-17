# Copy de opt-in e LGPD — canal WhatsApp do Núcleo

> Companheiro de `whatsapp_business_api_viability.md`. Data: 2026-06-17.
> Rascunho de copy para o consentimento e os avisos do canal WhatsApp. **Revisar com quem cuida do jurídico/DPO** antes de publicar; a base legal e a redação final são responsabilidade da governança (a plataforma tem `docs/legal` e ferramentas `lgpd_*`).
> Regra de voz: prosa humana, sem travessão.

## 1. Consentimento no onboarding (checkboxes)

Granular: separar "receber mensagens" de "entrar no grupo", porque o segundo expõe o número da pessoa aos demais membros do grupo.

**Opt-in de mensagens (1:1):**
> [ ] Autorizo o Núcleo IA & GP a me enviar mensagens pelo WhatsApp sobre minhas tribos, iniciativas, eventos e etapas de onboarding. Sei que posso cancelar a qualquer momento respondendo SAIR.

**Opt-in de grupo (separado):**
> [ ] Autorizo ser adicionado(a) ao grupo de WhatsApp da(s) minha(s) tribo(s)/iniciativa(s). Entendo que, ao entrar no grupo, meu número de telefone fica visível para os demais participantes.

Microcopy de apoio (abaixo dos checkboxes):
> Usamos o WhatsApp só para comunicação da comunidade. Não compartilhamos seu número com terceiros. Veja como tratamos seus dados em [Aviso de Privacidade].

## 2. Aviso de privacidade (trecho para o perfil/onboarding)

> **Como usamos seu WhatsApp.** O Núcleo IA & GP usa o WhatsApp Business para enviar comunicações da comunidade (avisos de tribo/iniciativa, eventos, lembretes de onboarding) e para gerir a participação nos grupos. A entrada e a saída dos grupos são geridas a partir da nossa plataforma, conforme sua participação ativa nas tribos e iniciativas. Tratamos seu número e seu consentimento com base na sua autorização e no legítimo interesse de organizar a comunidade, conforme a LGPD. Você pode revogar o consentimento, pedir correção ou exclusão dos seus dados, e sair dos grupos a qualquer momento. Contato do responsável pelo tratamento: [e-mail/DPO].

## 3. Mensagem de boas-vindas (1ª mensagem após opt-in)

> Olá, [Nome]! Aqui é o Núcleo IA & GP. Você ativou as comunicações por WhatsApp. Vamos te avisar sobre suas tribos, eventos e próximos passos por aqui. Para parar de receber, responda SAIR a qualquer momento. 🙂

## 4. Convite para grupo (quando a entrada for por convite/opt-in)

> [Nome], sua participação na tribo [Tribo] foi confirmada. Toque no link para entrar no grupo oficial da tribo: [link]. Ao entrar, seu número fica visível para os demais participantes do grupo.

## 5. Opt-out e confirmação

**Quando a pessoa responde SAIR:**
> Tudo certo, [Nome]. Você não receberá mais mensagens nossas por WhatsApp. Se mudar de ideia, é só responder VOLTAR ou ajustar suas preferências na plataforma. Sua participação nas tribos continua normal.

**Saída de grupo (quando inativada na tribo):**
> [Nome], como sua participação ativa na tribo [Tribo] foi encerrada, removemos você do grupo correspondente. Obrigado pela contribuição. Suas outras participações seguem inalteradas.

## 6. Notas de conformidade (para o time, não é copy)

- **Granularidade:** consentimento de mensagens e de grupo são separados; registrar cada um com data/hora e versão do texto (log de consentimento).
- **Exposição de número em grupo:** deixar explícito no opt-in de grupo (item 1) e no convite (item 4).
- **Opt-out sempre disponível:** instrução de saída em toda comunicação business-initiated.
- **Export de conteúdo de grupo** (se a migração avançar): exige base legal própria + aviso aos participantes; não está coberto por estes textos.
- **Retenção:** definir prazo de guarda de mensagens/logs e ligar às ferramentas `lgpd_*`.
