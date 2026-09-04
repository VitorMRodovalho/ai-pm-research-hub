# Handoff 04/09/2026: o `actor_kind` fechado nas duas metades, e o rodízio que despacha para porta fechada

> Números medidos entre 01h e 19h UTC de 04/09. Envelhecem sozinhos. Re-meça antes de decidir.

## Estado ao encerrar

`main bd1ef003` · fila **0 PRs** · janela de bypass em **2 de 2**, intocada, sem push direto e sem
`--admin` em nenhuma das quatro PRs · `main` **verde nos 13 checks**, inclusive o `check-invariants`,
que estava vermelho desde 03/09.

Três migrations aplicadas, as três com arquivo local **alinhado à tracking row** (o `apply_migration`
carimba timestamp próprio):

| tracking row | migration |
|---|---|
| `20260904023843` | `2175_gatilho_xp_paga_quem_passou_a_ser_elegivel` |
| `20260904132206` | `2159_actor_kind_no_log_de_pii` |
| `20260904175905` | `2185_escritores_automaticos_declaram_actor_kind` |

Nenhuma Edge Function deployada. `NOTIFY pgrst` executado após a `20260904132206` (coluna nova muda
a superfície do PostgREST) e `database.gen.ts` regenerado, conferido **pelo conteúdo** e não pelo
exit (`actor_kind`: 0 ocorrências antes, 3 depois, diff de exatamente 3 linhas).

⚠️ **`supabase migration repair` não rodou**: esta árvore não tem o projeto linkado. A tracking row
existe no banco de qualquer forma, criada pelo `apply_migration`, e o `rpc-migration-coverage` passou.
Não linkei o projeto por conta própria.

## O que foi entregue

### 1. `#2175`: o gatilho de XP pergunta se o card PASSOU A SER elegível

A `#1880` alargou o `AFTER UPDATE OF` para vigiar as três colunas do predicado e declarou no próprio
cabeçalho que não mexeria no corpo. O corpo exigia `OLD.status IS DISTINCT FROM 'done'`, então num
card já `done` a guarda barrava tudo: o gatilho disparava e não pagava. A classe que a migration
dizia fechar continuou aberta por quinze dias.

A guarda passou a perguntar se o card **não era** elegível antes e é agora, sobre o predicado
inteiro. A comparação de status usa `IS NOT DISTINCT FROM` de propósito: com `=`, um `OLD.status`
nulo tornaria a expressão `NULL`, e `NOT (NULL AND ...)` é `NULL`, o que faria o `IF` não disparar
sem erro nenhum.

**Sem bloco de reparo, de propósito.** Medido antes de aplicar, com controle positivo: 32 elegíveis,
32 pagos, **0 não pagos**. O backfill manual de 03/09 zerou a fila. Reparo sobre conjunto vazio não
prova nada, e foi exatamente esse falso verde que escondeu o defeito da `#1880`.

**Efeito colateral valioso:** o guard do `#1932` reprovou o `structural` e estava certo. A `#1147`
afirmava sobre essa função lendo o `.sql` congelado de 05/08, e **duas asserções dela estavam
vencidas e verdes**: a cláusula do gatilho mentia desde 20/08, e ninguém notou porque um arquivo
superado não muda. Consertado para ler a captura mais nova.

### 2. `#2159` + `#2185`: `actor_kind` fechado nas duas metades

`accessor_id` nulo em `pii_access_log` era ambíguo entre "não há pessoa" e "houve pessoa e ninguém
registrou quem". Relatório por responsável filtra por accessor, então as duas somem igual, e **7.592
leituras de PII** ficavam sem dono.

**Metade receptora (`#2159`):** coluna `actor_kind` NOT NULL com CHECK, backfill medido e trigger.

O backfill não precisou de heurística porque a varredura da tabela inteira mostrou que **exatamente
dois contextos** têm accessor nulo, ambos 100%, e nenhum contexto mistura os dois casos.

Duas decisões de desenho carregam a mudança:

- **o default vem de trigger, não de `DEFAULT` de coluna.** Um `DEFAULT` não distingue "não declarou"
  de "declarou", e sem essa distinção `actor_kind` seria `accessor_id IS NULL` renomeado, com zero
  informação nova;
- **sem declaração e sem pessoa vira `unknown`, nunca `automation`.** Presumir automação abençoaria
  em silêncio a linha inatribuível que a coluna existe para tornar visível.

**Metade escritora (`#2185`):** as três funções passaram a declarar `'automation'`. A declaração é
verdadeira por construção: as três começam com `IF current_caller_role() IS DISTINCT FROM
'service_role' THEN RAISE`, e o teste exige a guarda de papel **junto** da declaração.

Estado final medido: `human` 27.934 · `automation` 7.592 · `unknown` **0**.

⚠️ **A migration `20260904132206`, já mergeada, contém uma afirmação FALSA** que a `20260904175905`
corrige no cabeçalho: ela diz que os escritores são Edge Functions. São três funções de banco. Ver
"Erros meus" abaixo.

### 3. `#2171`: as 4 tentativas nomeadas com a causa fechada

O guard da Camada B do `#1636` reprovava o `check-invariants` desde 03/09 por dado de produção. As 4
tentativas entraram no allowlist por um motivo **diferente** das seis anteriores: a causa foi
encontrada e está fechada (o defeito da `#2004`, cuja promoção indevida precede a primeira tentativa
em 4,5 segundos).

E a premissa da `#2171` caiu na medição: ela separava estas 4 das 6 por `dispatch_source` ser nulo.
A chave **não existe em nenhuma das 29 linhas** sem ator pós-cutoff, e é estrutural, porque a função
que escreve `gate_attempts` não recebe o parâmetro que a originaria.

## Operação, fora do repositório

**Duas atas gravadas** (Reunião de Liderança #11 e Alinhamento Comunicação), com o dado sensível
generalizado e o documento de origem no `minutes_url`. As notas do Gemini registram motivo de saúde
de integrantes, que é dado sensível sob a LGPD e não entrou na plataforma.

**16 ações rastreáveis** criadas (15 na liderança, 1 na comunicação), só as que têm dono nomeado. As
7 do "[O grupo]" ficaram na ata de propósito: ação sem dono vira linha aberta que ninguém fecha.

**13 presenças marcadas** nas duas reuniões, pela lista de quem de fato falou na transcrição, com
`registered_by` gravado. A transcrição prova presença, nunca ausência, então quem ficou calado não
foi marcado e a janela de auto-registro segue aberta até 06/09 19:00.

**3 presenças removidas**, todas em reunião cancelada, todas marcadas DEPOIS do cancelamento (11, 5
e 3 dias). Rastro escrito à mão em `admin_audit_log`, porque `clear_member_attendance` não audita.

**Fila de seleção medida e comunicada** a Fabricio e Fernando, em mensagens individuais: 8 candidatos
sem nenhuma avaliação objetiva (3 esperando há mais de duas semanas) e 4 com a fase objetiva completa
esperando só a entrevista, os mais antigos há 50 dias.

## O achado que vale mais que as entregas

**O rodízio despacha convite de entrevista sem checar se a agenda tem horário livre** (`#2188`).

Começou como "um candidato diz que o e-mail não chega". Os logs mostravam sete entregas e cinco
aberturas. O candidato clicou **uma vez**, em 31/07, e caiu numa agenda que hoje mostra **zero
disponibilidade**. Nunca mais clicou.

| agenda | despachos | candidaturas | reservas | horários livres 04 a 10/09 |
|---|---:|---:|---:|---|
| GP (dois links curtos, mesmo schedule) | 69 | 44 | 2 | 21 |
| **avaliador B** | **39** | **22** | **2** | **0** |
| avaliador C | 17 | 7 | 2 | 6 |
| institucional | 7 | 5 | 0 | 20 |
| **total** | **132** | | **6** | |

**132 despachos, 6 reservas.** O despacho para porta fechada é indistinguível do despacho para porta
aberta em todas as tabelas: `gate_passed`, token emitido, `email.delivered`, linha instrumentada.

⚠️ **A disponibilidade foi medida hoje, não na data de cada despacho.** O log guarda a URL, não o
estado dela. Essa impossibilidade de reconstruir é parte do defeito, não limitação da investigação.

**Presos no momento: 4**, todos apontando para a agenda do GP, que tem 21 horários. O dano é
histórico, não corrente. O GP avisou os dois avaliadores para abrirem as agendas, e a linha de base
para verificar isso está registrada na própria issue.

## Erros meus, e o que cada um custou

**1. Afirmei em migration mergeada que os escritores eram Edge Functions.** Procurei em `pg_proc` por
funções CHAMADAS `reconcile_initiative_drive_access`, que é o valor da coluna `context`, não nome de
função nenhuma. O vazio virou conclusão e foi publicado no cabeçalho, no commit e na PR. Corrigido no
cabeçalho da `20260904175905`. **Antes de tratar um vazio como fato, pergunte se a chave da busca é
do mesmo TIPO que a coisa buscada.**

**2. Injeção de defeito que não injetou, e teste que não rodava.** Removi uma entrada de allowlist
esperando vermelho, deu exit 0, e quase concluí que a correção era decoração. Duas causas em série:
não verifiquei que a linha saiu do arquivo, e a camada que importa estava atrás de
`DATA_INVARIANT_GATE=1` (o arquivo roda **4 testes sem a variável e 8 com**). **Toda injeção precisa
de três asserções: o defeito entrou, o teste rodou, ele reprovou.**

**3. Monitor de CI declarou "nenhum vermelho" com três required rodando.** O filtro perguntava
`.conclusion == null` e um check em curso traz string **vazia**. `BLOCKED` foi lido como anomalia
quando era o estado normal.

**4. Matei um build achando que estava travado.** Levava ~9 minutos e eu o matei aos 7, lendo `utime`
congelado como morte. E das quatro tentativas, três morreram porque `pkill -f "astro build"` casa o
próprio shell que o executa. Saída: `[a]stro build`.

**5. Declarei "não é defeito da plataforma" tendo verificado uma de três agendas.** `curl` devolvia
200 e a agenda estava vazia: 3.501 bytes de casca em JS. Corrigido no `admin_audit_log`. **Para
página de aplicação, `curl` responde sobre o servidor, não sobre o que a pessoa vê.**

As cinco estão no `[LL]` `#588` e as duas mais transferíveis foram anexadas às memórias existentes,
em vez de criar entradas novas: o índice está no teto de 200 linhas e a regra é que quem acrescenta
arquiva outra.

## Issues abertas hoje

| # | assunto |
|---|---|
| `#2177` | 22 sítios que desestruturam só `data` de `sb.rpc` e convertem falha de banco em diagnóstico de domínio |
| `#2179` | o guard do `#1636` precisa de discriminador que não seja allowlist |
| `#2180` | `clear_member_attendance` apaga presença sem rastro, e nenhum código a chama |
| `#2181` | OAuth do MCP pendurou para um membro, e a requisição não chegou ao Supabase |
| `#2187` | presença em reunião cancelada: sem portão, `uncancel` sem botão, limpeza sem agendamento |
| `#2188` | o rodízio despacha para agenda sem horário livre |

**Quatro delas são a mesma coisa vista de ângulos diferentes:** `#2176`, `#2179`, `#2180` e `#2188`.
A plataforma executa o ato e não registra quem o executou, nem o que a pessoa viu. Está na mesa uma
proposta de tratá-las como frente única em vez de quatro consertos que se sobrepõem. **O PM não
decidiu.**

## Dois relógios correndo sozinhos

**05/09 às 04:00 UTC.** O cron de `reconcile_initiative_drive_access` grava ~136 linhas (medido: um
lote por dia, sem exceção nos últimos 15 dias). A previsão é que caiam em `automation` e `unknown`
continue em **0**. Se caírem em `unknown`, alguma premissa da `#2185` está errada e o ratchet avisa.

**As agendas dos dois avaliadores.** Linha de base registrada na `#2188`: `0 / 6 / 21 / 20`. Reabrir
os quatro links e recontar é a verificação.

## O que espera decisão do PM

1. **A frente única do cluster de rastro** (`#2176`, `#2179`, `#2180`, `#2188`) contra quatro
   consertos separados.
2. **`#2187` item 3:** o destino das 5 linhas de presença em evento cancelado. Agendar a limpeza
   resolve as cinco, mas apaga registro alheio sem rastro. Talvez a ordem certa seja dar rastro à
   remoção (`#2180`) antes de agendar.
3. **`#2152` decisão 1:** o selo deve ler o VEP quando ele for mais recente? Medido hoje: divergência
   **0**. Virou desenho sem dano vivo.
4. **`#2153`:** gravar a linha com o que a listagem deu e deixar as métricas nulas? A pós-condição
   fechou verde (29 de 51 com imagem e URN), então o item perdeu urgência.

## O que continua parado do lado do PM, e tem prazo

**Os cinco pontos da pauta** que o Fernando cita como esqueleto da descrição de cada produto para o
PMOGA, e **a atribuição da mensagem das 8:56** no WhatsApp (se a mudança de cidade e a
indisponibilidade até meados da semana são do PM ou do coordenador do PMOGA).

As duas seguram o mesmo entregável, e a Reunião Geral de **10/09** tem 70 dos 90 minutos livres,
medido hoje pela Agenda Viva.

## A regra da sessão, que vale para a próxima

> **Este controle tinha como falhar?**

Quatro dos cinco erros acima foram pegos por essa pergunta, e o quinto foi pego por outra sessão que
mediu antes de afirmar que meus itens eram reincidência (não eram). O prático:

- injeção de defeito tem três asserções, não uma, e **contar os testes executados** é a que faltava;
- vazio de uma consulta só é fato depois de você conferir que a chave é do mesmo tipo do dado;
- `null`, `""`, `undefined` e chave ausente são quatro estados, e a linguagem trata os quatro
  diferente;
- para o que o usuário vê, renderize; `curl` responde sobre o servidor.
