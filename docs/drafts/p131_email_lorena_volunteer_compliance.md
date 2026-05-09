# Draft email — Lorena Souza (PMI-GO Diretora de Voluntariado) · Brief cron compliance

**Status**: ✅ Draft v2 (2026-05-09 pós T-3 C3 implementação). Pronto para envio. T-3 reescopado para Lorena apenas (vagas voluntariado Núcleo são institucionalmente abaixo do PMI-GO; ela é ponta focal única independente do chapter de filiação do voluntário).

---

## Cabeçalho do email

- **Para:** diretoriavoluntariado@pmigo.org.br *(Lorena Souza)*
- **Cc:** vitor.rodovalho@outlook.com (institucional Núcleo IA & GP) · ivan.lourenco@pmigo.org.br (Ivan Lourenço, Sponsor PMI-GO)
- **Assunto:** Núcleo IA & GP — você passa a receber alertas urgentes pré-vencimento de voluntários (D-7)
- **Anexos:** nenhum

---

## Corpo do email (PT-BR, institucional-amistoso)

Olá Lorena, tudo bem?

Quero te dar visibilidade rápida de uma rotina que entrou em produção no Núcleo IA & GP e que coloca você (Diretoria de Voluntariado PMI-GO) no loop em casos de **vencimento iminente** das vagas de voluntários do Núcleo. Como as vagas do Núcleo são institucionalmente posições abaixo do PMI-GO independentemente do capítulo de filiação do voluntário (CE, DF, MG, RS), faz sentido que a Diretoria de Voluntariado seja a ponta focal de **escalation** — para evitar que um voluntário entre em desligamento sem você ter chance de intervir.

### Como funciona

A plataforma envia automaticamente alertas ao voluntário e ao GP nos seguintes pontos pré-vencimento da vaga PMI VEP do voluntário:

- **D-60** (60 dias antes) — alerta agregado **somente para o GP** no resumo semanal dele. O voluntário ainda não recebe nudge nesse ponto. Objetivo: planejamento prévio do GP sobre quem precisa renovar.
- **D-30** (30 dias antes) — alerta para o **voluntário** ("sua vaga vence em 30 dias, cadastre renovação no PMI VEP") + GP recebe agregado. Tanto voluntário quanto GP veem isso no resumo semanal.
- **D-7** (7 dias antes) — alerta **URGENTE** transactional para o voluntário (email real-time, fora do resumo) + GP cc real-time + **você cc real-time**. Esse é o ponto onde você entra: caso de escalation, voluntário ainda não cadastrou renovação, está prestes a vencer.

### Fluxo de renovação (como o sistema enxerga)

A vaga é considerada renovada quando o voluntário **se re-cadastra na vaga PMI VEP** atual do Núcleo (manager, leader ou pesquisador). A plataforma detecta automaticamente a re-candidatura via VEP sync, e a partir daí a "bola" passa do voluntário (precisava cadastrar) para o **GP** (precisa rodar o processo seletivo e ativar a vaga antes do vencimento). Você não precisa se preocupar com esse fluxo intermediário — só recebe escalation se o voluntário não chegou nem a se re-cadastrar até o D-7.

### Datas dos vínculos

Para cada voluntário, a data de vencimento da vaga vem do PMI VEP individual (não da data genérica do anúncio). Voluntários que entraram em pontos diferentes do ciclo têm datas de vencimento diferentes — o sistema sincroniza com o PMI Community via worker dedicado.

### O que se espera de você

Na **maioria dos casos, nenhuma ação ativa**. A maior parte das renovações fluem normalmente — voluntário se re-cadastra, GP roda seleção, vaga é ativada. O cc no D-7 é uma **rede de segurança**: se o voluntário ainda não tomou ação a 7 dias do vencimento, vale uma checagem informal sua para entender se há algum caso especial (transição, conflito, alumni implícito, dúvida operacional).

### Frequência esperada

Com cerca de **38 voluntários ativos** distribuídos em datas diferentes ao longo do ano, a estimativa é **2 a 5 cc real-time D-7 por mês** chegando para você nos próximos meses. Volume baixo. Os primeiros vencimentos começam **fevereiro/2027** com datas espalhadas até abril/2027 (cohort do ciclo 3 atual), depois espalhamento natural.

### Acesso à plataforma

Não é necessário ter senha ou logar para receber os emails. Caso queira ver o painel de voluntários e suas datas de vencimento, você pode acessar como stakeholder em **https://nucleoia.vitormr.dev/stakeholder** — me avisa que eu garanto o acesso configurado.

### O que NÃO precisa fazer agora

- Nenhuma reunião — só confirmar recebimento desta mensagem se quiser
- Nenhuma documentação — sistema é automático
- Nenhuma decisão — você só recebe os escalations D-7, age caso a caso conforme julgar

Qualquer dúvida, eu ou o Ivan estamos disponíveis. Obrigado pela parceria contínua com o Núcleo.

Abraço,

**Vitor M. Rodovalho**
Gerente de Projeto — Núcleo IA & GP
PMI-GO Diretoria de Voluntariado
vitor.rodovalho@outlook.com · (62) … *(seu telefone)*

---

## Notas para você ANTES de enviar

1. **Cron deployed e funcional**: ✅ `v4_engagement_expiry_notify` (job pg_cron `0 8 * * *`) com nova RPC `v4_notify_expiring_engagements()` que faz 3 nudges separados (D-60/D-30/D-7).
2. **38 voluntários têm end_date populado**: ✅ 36 via placeholder `signed_at + 365d`, 2 ainda pending E2 worker. Vencimentos espalhados de 18/fev/2027 a 13/abr/2027.
3. **Worker pmi-vep-sync vai corrigir end_dates**: quando deploy do hotfix do worker rodar (next deploy), datas placeholder vão ser sobrescritas pelas reais do PMI VEP API individual.
4. **Telefone seu** — placeholder `(62) …` para você completar.
5. **Tom** ficou institucional-amistoso. Se quiser mais formal (ela é diretoria de capítulo), pode ajustar para "Senhora Lorena" ou "Diretora Lorena Souza".
6. **Cc Ivan opcional** — você pode optar por NÃO colocar Ivan no cc se preferir contato direto sem alarme. Tema operacional, não estratégico — sua chamada.
7. **Próxima ação dela**: nenhuma esperada. Se ela responder pedindo reunião, é bônus (sinal de engajamento). Se não responder, está OK — assumimos awareness.
8. **Política de fallback**: se Lorena sair do cargo, atualizar destinatário continua sendo `diretoriavoluntariado@pmigo.org.br` (alias institucional, persiste após troca de pessoa). E a RPC do cron usa `'voluntariado_director' = ANY(designations)` para localizar a pessoa correta automaticamente.

## Validação técnica pós-implementação

```sql
-- Verifica os 3 tipos de notification estão no catálogo delivery_mode
SELECT 
  public._delivery_mode_for('engagement_renewal_d60_gp_aggregate') AS d60_mode,  -- digest_weekly
  public._delivery_mode_for('engagement_renewal_d30') AS d30_mode,               -- digest_weekly
  public._delivery_mode_for('engagement_renewal_d7_urgent') AS d7_mode;          -- transactional_immediate

-- Status do cron
SELECT jobname, schedule, active FROM cron.job WHERE jobname='v4_engagement_expiry_notify';

-- Voluntários ativos com end_date populado pronto para o cron
SELECT COUNT(*) FROM engagements 
WHERE kind='volunteer' AND status='active' AND end_date IS NOT NULL;
```

## Reminder pós-envio

- Sem necessidade de follow-up se ela não responder em 48h (assumir awareness recebida)
- Caso ela queira reunião / quiser conhecer a plataforma → 30 min onboarding stakeholder dashboard
- Caso receba primeiro D-7 cc e ela perguntar "o que faço?" → resposta padrão: "Awareness apenas. Se identificar caso especial me sinaliza."
