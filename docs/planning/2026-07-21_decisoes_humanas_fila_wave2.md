# Decisoes humanas pendentes na fila (Wave 2 + follow-ups)

> **RATIFICADO pelo owner em 2026-07-21: em acordo com as 6 recomendacoes abaixo.**
> Direcoes travadas (nao re-litigar). Execucao segue a "Nota de processo" no fim.
>
> Aterrado ao vivo em 2026-07-21 (HEAD `171b721a`, `main ≡ prod`). Estados dos issues
> confirmados via `gh issue view` na mesma sessao. Isto separa o que EU posso executar
> (codigo, SPEC, rascunho) do que depende de decisao SUA (ou de PMI-GO / legal / produto).
> Para cada decisao: quem decide, contexto, cenarios e recomendacao com justificativa.

## Matriz rapida

| # | Decisao | Quem decide | Bloqueia | Minha recomendacao | Urgencia |
|---|---------|-------------|----------|--------------------|----------|
| 1 | #1008 - ratificacao do nome "AI Community Day" + PDU/certificado | Presidencia PMI-GO + legal-counsel + c-level | Divulgacao de qualquer material publico do ACD | Postura conservadora: ratificacao escrita ANTES de publicar; certificado sem claim de PDU | Alta (dependencia externa; recorrente) |
| 2 | #1152 - mapa funcao->gate (Ivan vs Lorena) + committee_majority stub | Voce + confirmacao Ivan/Lorena | Trilha de lock da Politica (Termo e contornavel) | Ratificar leitura do issue: Lorena = contraparte pos-aprovacao, nao gate de versao; policy com cadeia custom explicita | Media |
| 3 | #1424 Fase D - reclassificar tipos imediatos para digest | Voce (produto/UX) | Nada critico (A/B/C sao a alavanca real) | ADIAR D ate a medicao de sabado 25/07; nao mover certificado/welcome | Baixa-media |
| 4 | #1358 - "stakeholder de capitulo" vs "ponto focal do nucleo" | Voce (tem a lista nominal) | Corretude de rosters/campanhas (grupos WhatsApp C4) | Adotar o split de 3 categorias; voce confirma o mapa nominal; eu implemento (so rotulo, sem mudar autoridade) | Media |
| 5 | #1014 - mecanismo de convite de signup direcionado | Voce (produto) + security-engineer | Remediacao do dia-9 a cada virada de ciclo | Comecar por "nudge-to-signup" (a); magic-link (b) so se nudge nao bastar | Media (workaround manual existe) |
| 6 | #485 - modelo de recorrencia + escopo | Voce/PM | Nada (deferred, low) | Estender rows materializadas com frequencia/intervalo; adiar tz selector e GCal sync | Baixa |

---

## 1. #1008 - Ratificacao do nome "AI Community Day" + linguagem de PDU/certificado

**Quem decide:** Presidencia de PMI-GO (ratificacao do nome), com review obrigatorio de
legal-counsel (linguagem) e c-level-advisor (enquadramento vs PMI). Nao e decisao unilateral
do Nucleo. **Meu papel:** preparar os rascunhos; a publicacao e gated por esses reviews (criterio
de aceite do proprio issue).

**Contexto (aterrado no issue, origem council-review 2026-07-01):** coincidencia de nome + data +
tema com o AI Community Day GLOBAL do PMI cria **implied endorsement** (parceiros/imprensa presumem
chancela oficial ou guarda-chuva do novo AI Standard). PMI-GO e a parte contratante (ADR-0104) e a
entidade mais exposta. Reivindicar PDU sem habilitacao formal e o item que pode **fechar o Path A**
(PMI-internal spinoff). O evento de 16/07 ja passou, entao a urgencia aguda caiu, mas nome + PDU e
**recorrente** para ACDs futuros e continua sendo blocker de divulgacao padrao.

**Decisao 1a - ratificacao do nome.**
- Cenario A (conservador): exigir ratificacao escrita da Presidencia PMI-GO antes de qualquer
  material publico usar "AI Community Day".
- Cenario B (permissivo): seguir usando o nome, tratando como uso local obvio, sem ratificacao formal.
- **Recomendacao: A.** A assimetria decide: o custo de pedir e um atraso curto; o custo de nao pedir
  e risco institucional ao Path A e a PMI-GO (a entidade mais exposta). Risco reputacional
  irreversivel nao se troca por conveniencia de calendario.

**Decisao 1b - linguagem do certificado / PDU.**
- Cenario A: "Certificado de participacao emitido pelo Nucleo IA & GP"; NUNCA "concede N PDUs"; se
  aplicavel, "PDU pode ser autodeclarado pelo participante conforme a categoria [X] do PMI CCR".
- Cenario B: certificado com mencao a PDUs concedidas (posicionamento mais forte de valor).
- **Recomendacao: A.** Sob o PMI CCR, PDU de educacao pode ser **autodeclarado** pelo participante,
  isso e factual e seguro. "Concede N PDUs" implica autoridade emissora que o Nucleo nao tem, e e
  exatamente o claim que ameaca o Path A. Ganha-se o valor (o participante registra a PDU) sem o risco.

**Decisao 1c - enquadramento do evento.**
- Cenario A: "aftershow / extensao noturna" do ACD (slot 19-21h BRT; o PMI global roda 10-17h BRT).
- Cenario B: "evento paralelo" ou "edicao local oficial".
- **Recomendacao: A.** O slot noturno e a brecha real e verdadeira; posiciona como complementar, nao
  concorrente nem oficial. Evita o implied endorsement e ainda e um enquadramento honesto.

**Decisao 1d - timing / recorte desta rodada.**
Como 16/07 passou, o recorte muda de "blocker desta semana" para: (1) **higiene retroativa** - auditar
se algum material do 16/07 com linguagem arriscada ainda esta publico e ajustar; (2) **politica
forward** - a consulta escrita a PMI-GO/PMI Latam vira politica-padrao para ACDs futuros.
- **Recomendacao:** fazer os dois. Eu preparo (i) o rascunho da consulta a PMI-GO/PMI Latam
  (autorizacao do nome + referencia ao Standard sem parecer emissor + limites de PDU) e (ii) a copy
  travada de certificado e convite. Ambos passam por legal-counsel antes de publicar (gate duro).

---

## 2. #1152 - Mapa funcao->gate (fusao Ivan/Lorena) + committee_majority stub

**Quem decide:** Voce, com confirmacao de Ivan/Lorena sobre a semantica da contraparte. **Meu papel:**
propor o mapa e implementar em `_can_sign_gate` apos ratificado (seguindo o procedimento de 4 etapas
do `docs/reference/V4_AUTHORITY_MODEL.md` antes de qualquer DDL de gate).

**Contexto (aterrado no corpo do issue, schema live 06/07):** o gate `president_go` do
`volunteer_term_template` hoje e satisfeito por duas funcoes distintas via predicado de designacao
sobreposto: Ivan (`legal_signer`, presidente/SEDE) e Lorena (`voluntariado_director`, diretora de
voluntariado). O carve-out `voluntariado_director` dentro de `president_go` funde **aprovacao da
versao do documento** com **assinatura da contraparte da entidade em cada Termo executado**.

**Decisao 2a - a funcao da Lorena e gate de versao ou contraparte por-instrumento?**
- Cenario A (leitura do issue): a assinatura da Lorena e a **contraparte da entidade promotora em
  cada Termo executado** (mecanica pos-aprovacao, por adesao individual), NAO um gate de aprovacao de
  versao. Remover o carve-out `voluntariado_director` de `president_go`.
- Cenario B: manter como esta (ambos satisfazem o gate de versao).
- **Recomendacao: A.** Aprovar a VERSAO do template (vira vigente) e um ato de governanca documental;
  assinar a contraparte de cada Termo executado e outra coisa (por-adesao, pos-aprovacao). Alinha com
  [[reference-volunteer-term-countersign-lorena]] (a contra-assinatura e ato exclusivo da Lorena,
  roteado como fila, nao como gate). Corrige tambem um cheiro de segregacao de funcoes.

**Decisao 2b - segregacao de funcoes.**
- Cenario A: proibir que a mesma pessoa aprove o template E assine a contraparte.
- Cenario B: nao restringir.
- **Recomendacao: A.** Controle interno basico. Custo zero na pratica (ja sao pessoas diferentes:
  Ivan aprova, Lorena assina a contraparte). Trava o precedente antes de virar problema.

**Decisao 2c - committee_majority stub trava o lock da Politica.**
`resolve_default_gates('policy')` devolve `committee_majority` (retorna FALSE ate o roster do Comite
de Curadoria ser definido em §7.1) no gate 1, entao a Politica nunca atinge maioria e fica presa.
- Cenario A: destravar o roster do Comite de Curadoria (§7.1) agora.
- Cenario B: travar a policy com uma cadeia custom explicita (ex.: Ivan `president_go` +
  `partner_consultation` consultivo), deixando `committee_majority` de fora ate §7.1 existir.
- **Recomendacao: B, a menos que o Comite ja esteja de fato constituido.** Um stub que retorna FALSE
  nunca atinge maioria: depender dele bloqueia a trilha da Politica indefinidamente. Uma cadeia
  custom e honesta sobre quem realmente aprova hoje. Nao afeta a Onda 1 (Termo), que segue contornavel
  (threshold 1, Ivan assina a SEDE).

---

## 3. #1424 Fase D - Reclassificar tipos de e-mail imediatos para digest

**Quem decide:** Voce (produto/UX). **Meu papel:** implementar apos a decisao; Fases A/B/C sao da lane
dev independentemente.

**Contexto:** as Fases A (agrupar por destinatario) + B (cap diario compartilhado) + C (escalonar o
digest de sabado) atacam a raiz do estouro da cota Resend. A Fase D e incremental: mover tipos nao-
urgentes de alto volume (`volunteer_agreement_signed`, `certificate_issued`, `certificate_ready`,
`engagement_welcome`) de `transactional_immediate` para `digest_weekly`.

**Decisao 3a - fazer a Fase D, e para quais tipos?**
- Cenario A: mover os 4 tipos para digest agora.
- Cenario B: adiar D; re-medir apos A/B/C e so mover um tipo se ainda estourar o headroom.
- **Recomendacao: B, com veto a mover certificado e welcome.** A/B/C atacam a raiz (o fan-out de
  `volunteer_agreement_signed` a 7,3/pessoa e do digest de lider a 4,8/pessoa cai para 1/pessoa so com
  a Fase A). Certificado ficar pronto e um **momento** que o membro quer saber na hora (baixa/compartilha,
  loop de reconhecimento/gamificacao); welcome atrasado uma semana e um sinal ruim de onboarding.
  Mover esses troca UX (tempestividade) por volume que A/B/C ja resolvem. Recomendo amarrar a decisao
  de D a **medicao pos-deploy de sabado 25/07** (item 1 da fila): se o cap nao morder, D e desnecessaria.

---

## 4. #1358 - "Stakeholder de capitulo" distinto de "ponto focal do nucleo"

**Quem decide:** Voce (detem a lista nominal com PII, fora do repo publico). **Meu papel:** implementar
a derivacao de categoria (so rotulo/categoria, SEM mudanca de autoridade; respeitando o procedimento do
`V4_AUTHORITY_MODEL.md` para nao mexer em `engagement_kind_permissions` indevidamente).

**Contexto:** 5 de 7 membros tagueados como ponto focal/liaison sao na verdade VP/diretor/PMO de
capitulo parceiro (stakeholders): acessam dados do portfolio por conta do papel no capitulo, mas nao
tem papel operacional no nucleo. So ~2-3 sao pontos focais reais. Descoberto ao montar os grupos de
WhatsApp por funcao do C4 (grupo "Pontos Focais" inflado). O acesso a dado deles e legitimo; o errado
e o **rotulo**.

**Decisao 4a - adotar o split de categoria.**
- Cenario A: criar categoria "stakeholder de capitulo" distinta de "ponto focal do nucleo"; aposentar
  `chapter_liaison` como guarda-chuva.
- Cenario B: manter a tag unica.
- **Recomendacao: A.** Os criterios de aceite ja sao claros e a correcao e de modelagem, baixa
  controversia. O unico julgamento humano e o **mapa nominal** (quais 5 sao stakeholders vs quais 2-3
  sao focais reais), que exige o seu conhecimento. Preserva o acesso a dado (nao e mudanca de autoridade).
- **O que preciso de voce:** a lista nominal de reclassificacao (fica na sessao dev / arquivo local,
  fora do issue publico por PII).

---

## 5. #1014 - Mecanismo de convite de signup direcionado (aceitos sem conta)

**Quem decide:** Voce (produto) + security-engineer no desenho do mecanismo escolhido. **Meu papel:**
escrever a SPEC apos a escolha; implementar depois.

**Contexto (aterrado no audit #1004):** na virada C3->C4, 4 de 36 aceitos tem `auth_id IS NULL` e nao
conseguem logar no dia 9. Nao ha mecanismo direcionado e seguro para reenviar convite de cadastro a
esses membros especificos. `request_account_claim` exige caller autenticado (fluxo errado);
admin auth-invite nao existe; `send-global-onboarding` e broadcast de coorte (over-send). O gap recorre
a cada virada de ciclo. Workaround imediato: nudge manual (nao bloqueia o dia 9).

**Decisao 5a - qual mecanismo.**
- Cenario A (nudge-to-signup): e-mail direcionado a `member_ids` especificos apontando para o cadastro
  self-service com o e-mail da candidatura. Nao cria conta, so orienta. Reusa Resend/templates.
- Cenario B (magic-link / auth-invite): a plataforma emite link de primeiro acesso
  (`generateLink`/`inviteUserByEmail` ou token proprio) que cria/vincula a conta. Mais robusto.
- **Recomendacao: comecar por A, escalar para B so se A nao bastar.** A resolve o gap recorrente do
  dia-9 com o menor custo: reusa infra existente e **nao abre superficie de auth nova** (evita o custo
  de seguranca + LGPD + escopo de token que B introduz). B e mais robusto mas so se justifica se os
  membros nao se auto-cadastrarem via nudge. Requisitos comuns a qualquer opcao (gate de autoridade,
  idempotencia/TTL, log de acesso PII Art. 37, alvo por lista explicita) entram na SPEC.

---

## 6. #485 - Recorrencia flexivel + timezone + Google Calendar sync

**Quem decide:** Voce/PM. Prioridade **baixa** (deferred, nao urgente). **Meu papel:** implementar apos
a decisao de modelo.

**Contexto:** `create_recurring_weekly_events` e weekly-only, count-based. Pedidos: quinzenal, 2x/semana,
mensal; selector de timezone; import/sync com Google Calendar (reusaria a infra de webhook do #472).

**Decisao 6a - modelo de recorrencia (decidir ANTES de construir).**
- Cenario A: estender o modelo atual de **rows materializadas** com parametros de frequencia/intervalo.
- Cenario B: adotar um modelo de **regra de recorrencia (RRULE-style)**.
- **Recomendacao: A para o curto prazo.** A plataforma ja materializa event rows discretas (attendance,
  board links referenciam eventos concretos por `recurrence_group`); um modelo RRULE completo e um
  refactor grande com payoff incerto na escala atual. Estender rows com frequencia/intervalo entrega o
  valor pedido com risco menor.

**Decisao 6b - escopo.**
- **Recomendacao:** construir a **frequencia flexivel** primeiro (maior valor pedido pelos membros),
  adiar tz selector (demanda menor) e GCal sync (reusa #472 depois). Coerente com a prioridade low.

---

## Nota de processo

Nada aqui e executado sem a sua decisao. Depois que voce fechar cada ponto, a divisao e:
- **Eu executo (codigo/SPEC/rascunho):** #1152 (apos ratificar o mapa), #1358 (com o mapa nominal),
  #1014 (SPEC do mecanismo escolhido), #485, e os rascunhos do #1008.
- **Voce roteia externamente:** #1008 (Presidencia PMI-GO + legal-counsel + c-level), #1152
  (confirmacao Ivan/Lorena sobre a contraparte).
- **Gate duro:** nenhum material do #1008 sai antes de PMI-GO ratificar o nome + legal revisar a linguagem.
