# Draft email — Lorena Souza (PMI-GO Diretora de Voluntariado) · Brief cron compliance

**Status**: ⛔ **NÃO ENVIAR** (deferido p131 conforme A3 escolhido pelo PM 2026-05-09).

**Por que deferido**: auditoria pré-envio revelou que o draft descrevia 3 nudges (D-60/D-30/D-7) com Lorena em cc — mas a feature real (`v4_notify_expiring_engagements`) envia 1 nudge sem cc Lorena, e os 38 voluntários ativos não têm `end_date` populado, então hoje o cron não dispara nada para esse universo. Comunicar à Lorena uma feature que não existe geraria ruído e perda de credibilidade.

**Backlog para destravar envio (T-3 task #13)**:
1. Backfill `end_date` dos 38 engagements voluntários ativos
2. Estender `v4_notify_expiring_engagements` para 3 nudges D-60/D-30/D-7 (não 1)
3. Adicionar cc Lorena nas notificações D-30 e D-7
4. Emitir via email real (Edge Function send-notification-email), não só `notifications` table
5. Re-draftar este email pós-feature pronta

T-3 reescopado de "5 chapter VPs" para "Lorena apenas" porque vagas voluntariado do Núcleo são institucionalmente abaixo do PMI-GO; ela é o ponta focal único independente do chapter de filiação do voluntário (CE/DF/MG/RS).

---

⚠️ **Conteúdo abaixo está OBSOLETO até implementação completa do backlog acima.** Mantido como referência arquitetural de como o email FINAL deve ler (após feature pronta).

---

---

## Cabeçalho do email

- **Para:** diretoriavoluntariado@pmigo.org.br *(Lorena Souza)*
- **Cc:** vitor.rodovalho@outlook.com (institucional Núcleo IA & GP) · ivan.lourenco@pmigo.org.br *(confirmar email exato do Ivan)*
- **Assunto:** Núcleo IA & GP — você passa a receber alertas pré-vencimento de voluntários
- **Anexos:** nenhum

---

## Corpo do email (PT-BR, institucional-amistoso, conciso)

Olá Lorena, tudo bem?

Quero te dar visibilidade rápida de uma rotina que entrou em produção no Núcleo IA & GP e que coloca você (Diretoria de Voluntariado PMI-GO) no loop antes de cada vencimento de vaga. Como as vagas do Núcleo são institucionalmente posições abaixo do PMI-GO independentemente do capítulo de filiação do voluntário (CE, DF, MG, RS), faz sentido que a Diretoria de Voluntariado seja a ponta focal única de compliance — para evitar que um voluntário entre em desligamento sem você saber.

### O que entrou em produção

A plataforma envia automaticamente **3 nudges** por email antes do vencimento da vaga de cada voluntário:

- **D-60**: 60 dias antes — nudge para o voluntário (você ainda **não recebe**, apenas awareness do próprio voluntário)
- **D-30**: 30 dias antes — nudge para o voluntário **com você em cópia**
- **D-7**: 7 dias antes — nudge para o voluntário **com você em cópia** (último alerta)

O sistema considera o que vier primeiro: o vencimento do termo de adesão (`engagement.end_date`) ou o vencimento da filiação PMI (`pmi_membership.expiryDate`).

### O que se espera de você

Na **maioria dos casos, nenhuma ação ativa**. Os voluntários renovam ou encerram normalmente, e o cc é só para **awareness**. O valor para você é poder agir com antecedência em **casos especiais**: voluntário em transição, conflito não-resolvido, alumni que quer encerrar sem comunicar formalmente, etc.

### Frequência esperada

Com cerca de **60 voluntários ativos** distribuídos em ciclos diferentes, a estimativa é **2 a 5 emails de cc por mês** chegando para você. Volume baixo, projetado para não criar ruído.

### Acesso à plataforma

Não é necessário ter senha ou logar para receber os emails. Caso queira ver o painel completo (relação de voluntários ativos, datas de vencimento, status de renovação), você pode acessar a plataforma como stakeholder em **https://nucleoia.vitormr.dev/stakeholder** — me avisa que eu garanto o acesso configurado.

### O que NÃO precisa fazer agora

- Nenhuma reunião — só confirmar recebimento desta mensagem se quiser
- Nenhuma documentação — sistema é automático
- Nenhuma decisão — você só recebe os nudges, age se julgar necessário em casos pontuais

Qualquer dúvida, eu ou o Ivan estamos disponíveis. Obrigado pela parceria contínua com o Núcleo.

Abraço,

**Vitor M. Rodovalho**
Gerente de Projeto — Núcleo IA & GP
PMI-GO Diretoria de Voluntariado
vitor.rodovalho@outlook.com · (62) … *(seu telefone)*

---

## Notas para você ANTES de enviar

1. **Confirma email do Ivan no cc** — placeholder. Verifique canônico.
2. **Telefone seu** — placeholder `(62) …` para completar.
3. **Tom**: ficou institucional-amistoso. Se quiser mais formal (ela é diretoria de capítulo), pode ajustar para "Senhora Lorena" ou "Diretora Lorena Souza".
4. **Decisão pendente**: você pode optar por **não** colocar Ivan no cc se preferir contato direto sem alarme — o argumento seria "tema operacional, não estratégico". Sua chamada.
5. **Próxima ação dela**: nenhuma esperada. Se ela responder pedindo reunião, é bônus (sinal de engajamento). Se não responder, está OK — assumimos awareness.
6. **Validação técnica**: a feature de cron `cron_volunteer_renewal_nudge` está deployed e ativa? Verificar pg_cron jobs antes de enviar para evitar inconsistência (ela receber o email mas o sistema não estar funcionando).
7. **Política de fallback**: se Lorena sair do cargo, atualizar destinatário para `diretoriavoluntariado@pmigo.org.br` (alias institucional, persiste após troca de pessoa).

## Validação técnica recomendada antes do envio

```sql
-- Verificar se o cron está agendado e ativo
SELECT jobname, schedule, active, command 
FROM cron.job 
WHERE jobname ILIKE '%volunteer%' OR jobname ILIKE '%renewal%' OR jobname ILIKE '%expiry%'
ORDER BY jobname;
```

Se nada aparecer, o cron pode ainda não estar deployed — me avisa que verifico.

## Reminder pós-envio

- Sem necessidade de follow-up se ela não responder em 48h (assumir awareness recebida)
- Caso ela queira reunião / quiser conhecer a plataforma → 30 min onboarding stakeholder dashboard
- Caso receba primeiro D-30 ou D-7 e ela perguntar "o que faço?" → resposta padrão: "Awareness apenas. Voluntário tem ação automática. Se algo te chamar atenção me sinaliza."
