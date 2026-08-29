# Arranque — #2062 passo B: a autoridade do time de comunicação

> Sessão **limpa por decisão do PM** (29/08). O assunto é modelo de autoridade e merece contexto
> próprio, sem herdar viés do que veio antes.

## Primeiro, re-meça

Os números abaixo são de **29/08** e envelhecem. Nenhum deles vale como fato: re-execute antes de
decidir qualquer coisa. Handoff não é medição.

- `main` estava em `86c10d42`. A PR **#2065** (passo C) podia estar em voo — confira se entrou.
- Confira a fila: outras lanes trabalham em paralelo, com worktrees em `.wt-campanha`,
  `.wt-capitulos` e `.wt-handoff`. Branch em uso por worktree **não** aceita checkout aqui.

## A tarefa: #2062

Leia a issue inteira. O enunciado está pronto e os números foram medidos; o que falta é o
procedimento e a decisão.

**Não pule isto:** a issue exige as **4 etapas** de `docs/reference/V4_AUTHORITY_MODEL.md` antes de
qualquer `INSERT INTO engagement_kind_permissions`. O próprio doc registra que auditoria mecânica ali
produz falso positivo recorrente e nomeia "seed expansion como atalho" como anti-pattern. Se alguma
etapa achar caminho alternativo, a conclusão muda — e a issue registra isso em vez de seguir.

### O que já se sabe (re-meça mesmo assim)

- O portão de `/admin/comms` é `can_view_comms_analytics()`: passa por capacidade
  `view_internal_analytics`, por `manage_comms`, ou por designação `comms_leader`/`comms_member`.
  **Nunca olha o engajamento na iniciativa.**
- `manage_comms` tinha **4 combos semeados, todos em `kind = volunteer`**. Os engajamentos do Hub de
  Comunicação (`9ea82b09-55c6-4cc3-ab7f-178518d0ab47`) são `workgroup_member`, papéis `leader` e
  `coordinator`. **Nenhum combo para `workgroup_member`.**
- A designação é `text[]` **sem ciclo de vida**: zero colunas de histórico, contra `granted_at`,
  `revoked_at`, `granted_by`, `revoked_by` e `role` no engajamento. O Hub já tinha **5 saídas
  registradas** no vínculo.

### Duas armadilhas medidas nesta sessão

1. **O guard que a issue pede nasce VERDE por vacuidade.** Em 29/08 havia **0** pessoas com
   designação sem engajamento ativo. Um teste escrito hoje passa sem medir nada — ele precisa de
   controle positivo.
2. **O passo A piorou o que o B vai consertar.** Foram concedidas designações `comms_member` a 4
   coordenadores para destravar acesso, o que subiu de 3 para 7 as designações que ninguém vai
   lembrar de remover na próxima saída. Foi escolha consciente de sequência, não conserto.

## Decidido — não re-litigar

- **#2062 é A → C → B.** A (designações) e C (link na página da iniciativa) estão feitos.
- **#1910: caminho 3** — o guard passa a distinguir "corpo divergente" de "função viva sem `.sql` em
  nenhuma branch mergeada", e o segundo caso **continua reprovando**; a mudança é de diagnóstico,
  não de severidade. Aceite escrito na issue.
- **#2023 backfill: B depois C** — fluxo novo primeiro, backfill dos 87 em lotes depois.
- **#2004: opção C**, portão primeiro (feito), rótulo depois (falta).
- **#1995: opção B** — a tela explica, não só lista.

## Depois do #2062, na ordem

1. **#2004**, parte do rótulo: o contador do funil ainda soma quem passou a fase objetiva com quem
   só escolheu entrevista ao vivo.
2. **#1995**: tela que separa "não se aplica" de "travado". Em 29/08: 33 sem tribo, dos quais 7
   esperando alocação, 7 travados e 19 que não precisam — mais 1 `tribe_leader` sem tribo.
3. **#2023**: anexo por e-mail ao voluntário e depósito na pasta Drive com ACL verificada.
4. **#2043**: o alerta de token vigia o prazo que se renova sozinho e ignora o que exige humano.

## Regras que custaram caro nesta sessão

- **Leia o campo certo antes de afirmar.** `_audit_list_public_function_bodies` devolve `proname`,
  não `function_name`. E o helper de drift devolve `driftedDefinite`/`driftedSuspect`/`orphansTrue`,
  não `drifted`/`orphans`. Ler o campo errado devolve `undefined` e `(undefined || []).length` dá
  **0** — um "zero" que parece medição e não é. Isso me fez reportar "sem drift" o dia todo sem
  medir nada.
- **`i_attended` e afins são calculados para o CHAMADOR.** Ler como `service_role` responde sobre a
  sua sessão, não sobre a pessoa. Impersone.
- **Ausência de check não é pendência.** Um vigia que só olha "nada pendente" tenta mergear PR
  `BLOCKED` por required que nem apareceu.
- **Publique o zero junto do controle positivo.** Zero sobre conjunto vazio é indistinguível de
  acerto.
