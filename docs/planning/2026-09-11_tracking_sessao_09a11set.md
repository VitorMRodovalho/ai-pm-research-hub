# Rastreamento da sessão de 09 a 11/09: missão, entregue, e o que ficou amarrado a quê

> Carimbado em 11/09 às 01h20 BRT. **Nada aqui é medição viva.** Re-meça antes de agir:
> `gh issue list --state open` · `gh pr list --state open` · `git log --oneline -1 origin/main`

**Estado ao fechar:** `main e98b7ee1` · fila vazia · **0 alertas** no Dependabot · **0 bypass**.

---

## 1. A missão, como estava escrita no arranque de 09/09

| # | item | resultado |
| --- | --- | --- |
| 1 | **#2204**: decidir entre investigar o React ou fatiar. Segurava a fila. | **FECHADO** por caminho diferente do previsto |
| 2 | Os **27 npm + zod**, plano de 4 ondas | **PARCIAL**: onda 0 feita, plano re-medido |
| 3 | **Pesquisa das docs dos 45 dias** nos 8 provedores + latência do MCP | **FECHADO** |
| 4 | Os **3 convites de entrevista** que precisam do caminho que envia e-mail | **JÁ ESTAVA FEITO**, o arranque é que estava velho |

---

## 2. O que foi entregue

### 2.1 A causa da #2204, que não era nenhuma das duas hipóteses

Medição no lockfile derrubou o React: `react`, `react-dom`, `vite`, `rolldown`, `esbuild` e
`@vitejs/plugin-react` estavam **idênticos** nos dois lados. A causa era `astro 7.2.2 -> 7.3.2`,
arrastado pelo `npm audit fix` sem nenhum alerta exigir.

Substituída pela **#2210** (5 pacotes em vez de 115). Regressão virou a **#2211**.

### 2.2 Um RCE critical apareceu no meio, e fechou no mesmo dia

`astro` RCE por otimização de imagem AVIF. Piso do advisory na linha 7.2, não na 7.3, então deu
para fechar sem tocar a versão quebrada: **#2215**. Worker `pmi-vep-sync`: **#2216**.

**17 alertas tratados, 0 abertos.** O `extract-zip`, sem patch existente, foi dispensado como
`not_used` com justificativa medida, e a correção de premissa ficou na **#611**.

### 2.3 A pesquisa dos 45 dias (#2212)

`docs/research/2026-09-09_docs_45d_oito_provedores_e_latencia_mcp.md`. Dois achados que mudam
trabalho: a spec do MCP virou `2026-07-28` e o SDK não acompanhou (#2214); e a rota MCP está
saudável, com o p99 assustador vindo de um episódio de três dias em agosto (#2213).

### 2.4 Reunião do time de comunicação de 10/09

Evento `127ab9d3` criado, ata completa, **6 presenças com ator**, 4 decisões e **8 ações
rastreáveis** com responsável e prazo.

**Cadência corrigida:** 8 terças futuras canceladas com motivo e ator, quintas viraram semanais,
horário alinhado em **18:30 America/Sao_Paulo** nas 8 ocorrências.

### 2.5 Pesquisa da Tribo 4 enviada

**78 destinatários**, todos com consentimento LGPD: 74 por campanha (`488c955e`, com métrica por
pessoa) e 4 por envio individual, todos com confirmação de entrega.

### 2.6 Currículo recuperado

**Patrícia Sebastião** (`36b3cc78`), uma das três candidatas com entrevista pendente, estava sem
currículo na plataforma por falha transitória de upload. Recuperado a cerca de 23 horas da
assinatura de origem expirar.

---

## 3. Pendências derivadas, e a quem cada uma se amarra

**Nenhuma destas existia antes desta sessão.** Todas nasceram de algo que foi tocado aqui.

### Cadeia do CI e do stack

| issue | nasceu de | estado |
| --- | --- | --- |
| **#2211** | a investigação da #2204 | astro 7.3.2 quebra o dev server; 7.3.2 é a última publicada, sem correção upstream |
| **#2219** | o merge do próprio handoff | retry do `browser_guards` não limpa o daemon; **escopo corrigido**, cobre só a tentativa 2 |
| **#2231** | a pergunta do GP sobre repetir o ciclo | **suspeita de regressão no astro 7.2.10**; 0 falhas em 87 runs antes, 3 em 13 depois |

**Esta cadeia é a mais quente.** A #2219 é **pré-requisito** da #2231: sem consertar o retry,
qualquer bateria de repetição reporta o dobro da taxa real.

### Cadeia do MCP

| issue | nasceu de | estado |
| --- | --- | --- |
| **#2213** | a medição da rota MCP | timer só mede de dentro do handler; 35 chamadas gastaram 93,7 s para entregar falha |
| **#2214** | a pesquisa dos 45 dias | spec `2026-07-28` contra SDK `2025-11-25`; vigia, sem ação hoje |
| **#2225** | criar o evento da reunião pelo MCP | `event_write` autoriza pelo `initiative_id` e não o grava |

### Cadeia do modelo de identidade

| issue | nasceu de | estado |
| --- | --- | --- |
| **#2226** | conferir o time nas três rotas | home e MCP mostram nomes diferentes; 9 de 135 pares divergem |
| **#2227** | montar a audiência do e-mail | curadoria não existe no modelo; curadores só entram por memória humana |
| **#2228** | a mesma audiência | 1 líder de tribo e 2 pesquisadores sem tribo nenhuma, invisíveis a todo filtro por tribo |

### Dependências

| issue | estado |
| --- | --- |
| **#2217** | plano de 4 ondas com inventário **re-medido**: 30 atrasados, não 27. **Bloqueado de fato pela #2231**: subir mais dependência antes de entender a regressão do astro é repetir o ciclo |

---

## 4. O que ainda tem por fazer

### Do lado da plataforma

1. **#2231**, e é o primeiro.** Estabelecer a taxa real do `browser_guards` com repetição, bissecar
   entre 7.2.6 e 7.2.8, e descartar os caronas da #2210. **Não voltar ao 7.2.2**: tem o RCE.
2. **#2219** antes ou junto, por ser pré-requisito de medição.
3. **#2213 item 1**, o timer de ponta a ponta do MCP. Pequeno, e vem antes de qualquer otimização.
4. **Ondas 1 a 4 da #2217**, depois que a #2231 fechar.

### Do lado do GP

1. **Os cinco pontos do PMOGA.** Só existem na thread do WhatsApp do grupo
   "Núcleo Tribos PMO / PMO GA LATAM", no complemento que o Fernando fez à sugestão do Fabricio.
   Varri banco, Gmail, Drive e 9 exports de WhatsApp: não estão em lugar alcançável. O caminho é
   exportar aquele grupo ou colar a mensagem.
2. **A resposta do Jefferson** sobre se a reunião de 18/08 aconteceu. Decide se há presença legítima
   a recuperar, porque as linhas foram apagadas em 03/09.
3. **Regularizar o VEP de Sarah e Roberto**, que são curadores sem VEP ativo (planejado para este
   mês).
4. **Os 3 candidatos** seguem sem reserva de entrevista, com e-mail entregue. Se não reservarem, o
   gargalo é outro e precisa ser medido, não reemitido.

### Aberto por outra lane, não por esta sessão

**#2229**, sobre confirmar bloco de protagonismo creditar XP. Fica citado aqui só para o
rastreamento ficar completo.

### Solto, sem dono

A branch **`docs/2208-skill-youtube-publicacao`** tem um run de CI de 10/09 às 14:36 que falhou em
`browser_guards` **e** `validate`, e não foi re-rodado. É a terceira ocorrência que alimenta a
#2231.

---

## 5. Quatro lições que esta sessão pagou caro para aprender

**Premissa de handoff vale como hipótese, não como fato.** A frase sobre o `extract-zip` sobreviveu
a três PRs sendo repetida e só caiu quando foi preciso assinar uma dispensa com ela. Precisar da
premissa para uma ação irreversível é o último momento possível de conferi-la.

**`^` não segura o que você decidiu segurar.** `^7.2.10` readmitiria a 7.3 na instalação seguinte,
em silêncio. Quando a intenção é prender numa linha, o operador é `~`.

**Contagem igual não prova conjunto igual.** VEP e plataforma deram 72 dos dois lados, e a diferença
simétrica mostrou 12 pessoas de um lado e 2 do outro. Duas delas eram a mesma pessoa com e-mails
diferentes.

**Re-run reescreve a conclusão do job.** Medir falha histórica de CI pela conclusão mede o acervo
depois da intervenção. Conte `run_attempt > 1` e leia `/attempts/1/jobs`.
