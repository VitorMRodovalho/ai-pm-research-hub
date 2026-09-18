# Handoff 18/09: a Liderança #12 fechada, e a PR que não rodava CI porque estava em conflito

> **Nada aqui é medição viva.** Carimbado em 18/09 ~13h40 UTC.
> **Re-meça antes de decidir.** Repositório público: este documento não nomeia terceiros.

**Estado ao encerrar:** `main d10baca9` · **0 PRs abertas** · PRs #2359 e #2358 mergeadas.

---

## 1. O que foi entregue: a Reunião de Liderança #12

Medido antes e depois, das duas pontas, com consulta nova em cada lado:

| | antes | depois |
|---|---:|---:|
| ata (`minutes_text`) | ausente | **10.998 chars** |
| `notes` (resumo do `close`) | 0 | **870 chars** |
| presenças | 6 | **15** |
| ações estruturadas | 0 | **21** |
| decisões registradas | 0 | **4** |

⚠️ **Dois denominadores, um `count`, e é assim que nasce reconciliação fantasma.** `meeting_action_items`
guarda **ação e decisão na mesma tabela**, discriminadas por `kind`. Um `count(*)` cru devolve **25** para
esta reunião; o `action_count` do retorno do `close` devolve **21**, porque conta só `kind='action'`. Os dois
estão certos. Quem comparar os números sem o `WHERE kind` vai achar que perdeu 4 linhas. **Conte por `kind`,
sempre.**

**A fonte foi a transcrição integral da gravação** (notas automáticas do Google Meet, 156 KB),
puxada por `rclone cat`. Nada foi inferido.

### As 15 presenças saíram da transcrição, e isso é o ponto

A plataforma tinha 6 presenças auto-registradas. A transcrição nomeia **15 pessoas que falaram**.
Registrei as 9 faltantes, porque **fala na transcrição é prova de presença**. A ata declara o limite
explicitamente: quem participou sem falar não é distinguível por esta fonte, então a ausência de
registro não afirma falta.

### O `close` exercitou o conserto da #2351 em produção

A sequência foi `write` (que carimba `minutes_posted_at`) e depois `close` com resumo. **Antes do
conserto isso perdia o resumo em silêncio.** O retorno veio com `already_closed: true` **e**
`summary_appended: true` na mesma chamada, que é exatamente o par que não existia antes. Confirmado
na fonte, não pelo retorno: `notes` saiu de 0 para 870 chars, com a âncora e o texto presentes.

### Convenção de prazo, declarada na própria ata

A fonte não datou nenhuma das próximas etapas. As 21 ações receberam prazo em **01/10/2026**, data
da Reunião de Liderança #13, que é o próximo ponto de cobrança do fórum. Onde a discussão indicou
horizonte maior (novembro, dezembro), o prazo continua sendo o da próxima reunião e o horizonte está
descrito no item. **16 das 21 têm responsável nominal**; 5 são coletivas ("o grupo", "líderes das
tribos") ou citam alguém sem cadastro de membro, e nesse caso o nome ficou na descrição em vez de
virar atribuição errada.

## 2. As outras duas continuam sem ata, e o motivo é acesso, não trabalho

| reunião | presenças | ata | por quê |
|---|---:|---|---|
| Alinhamento Comunicação | **0** | falta | material existe, **inacessível** |
| Inclusão & Colaboração (tribo 8) | 5 + 1 justificada | falta | material no Drive de quem hospeda |

**Duas correções ao handoff anterior, ambas medidas:**

1. **A reunião de comunicação ACONTECEU.** O handoff de 17/09 a listava com zero presenças, e eu
   cheguei a levantar a hipótese de que não tivesse ocorrido. O calendário mostra que sim: 18h30 às
   19h30, organizada por outra pessoa, com gravação, chat e notas do Gemini anexados. **A gravação
   não está no Drive do dono porque ele não organizou aquela ocorrência.** Ausência num lugar não é
   ausência.
2. **A tribo 8 tem 5 presentes e 1 justificada**, não 6 presenças. A sexta linha tem
   `present=false, excused=true`. Contar linhas não é contar presentes.

### O 404 foi medido com controle positivo, três vezes

O doc de notas de 17/09 da reunião de comunicação não abre. Isso foi verificado por três instrumentos
independentes, e **com controle positivo em dois deles**:

| instrumento | alvo (17/09) | controle (03/09 e 10/09) |
|---|---|---|
| `rclone`, 4 contas de Drive | **404** | baixam, 85.488 e 54.362 bytes |
| navegador real, sessão do dono | **403 "You need access"** | n/a |
| tela do próprio Google | "não compartilhado" | n/a |

**O controle é o que transforma isto de hipótese em fato.** Sem ele, o 404 leria como "instrumento
quebrado" ou "escopo de OAuth". Com ele, a conclusão é única: o arquivo não foi compartilhado.

⚠️ **E vale o registro do sentido inverso:** a regra "403 de fetch programático não prova fonte
indisponível" continua valendo, e foi por ela que eu fui ao navegador. Só que desta vez **o navegador
concordou com a API**. O navegador é o desempate, não a resposta automática.

**O que destrava:** compartilhar o doc de 17/09 com a conta do dono. Para a tribo 8, o material é de
quem hospeda e não está em nenhuma conta conectada.

## 3. A LIÇÃO DO DIA: PR em conflito não roda CI, e o sintoma se disfarça de lentidão

A PR #2359 ficou parada com **1 check reportado contra os 12 de uma PR irmã**. A leitura natural é
"CI lento". Estava errada.

**`mergeable: CONFLICTING` significa que o merge ref não existe, e sem merge ref nenhum workflow
dispara.** Medido: **zero** runs para aquele SHA. Resolvido o conflito, os checks saltaram de 1 para
11 no mesmo minuto.

⇒ **Quando o CI "não começa", meça `mergeable` antes de esperar.** O tempo esperando é o custo, e a
espera não tem fim próprio.

### O conflito era uma whitelist em string única, e eu errei ao resolvê-lo

`package.json` tem **três** scripts que carregam listas de arquivos de teste. A main acrescentou o
guard da #2345 e a lane o da #2351, na mesma linha, e colidiram.

Resolvi mantendo as duas entradas, **mas só em `test:behavioural`**, porque eu tinha medido duas
listas e não três. O guard `1109-contract-whitelist-completeness` pegou: ele afirma que todo
`tests/contracts/*.test.mjs` está em **AMBAS** as listas.

**Isto é a mesma classe que este projeto vem documentando:** eu produzi o resultado a partir de um
denominador incompleto. Refiz genérico, fazendo a união em **toda** lista compartilhada em vez das
que eu lembrei de olhar, e validando antes de gravar.

⚠️ **O CI reprovou com título e resumo vazios** (classe do #1910). O diagnóstico só apareceu ao
reproduzir local. `npm run test:structural` é a metade hermética e **pode** ser rodada com CI no ar,
ao contrário do `test:verdict`.

## 4. Ordenação de DDL: a quinta mordida, agora vinda de uma lane

A DDL da #2351 ficou **~12h no banco compartilhado sem o `.sql` na `main`**. Consequência medida na
#2358, que é uma PR de **um arquivo `.md`**:

| check | falhou por |
|---|---|
| `gen-types-drift` | a função nova no `pg_proc` sem tipo no arquivo |
| `Track Q-C` | função órfã sem `CREATE FUNCTION` em migration |
| `Phase C` | corpo do `meeting_close` divergente da captura |
| `ADR-0097` | tracking row sem arquivo local |

**As quatro curaram só com o merge da #2359, sem nenhuma outra mudança.** Isso é a prova de
atribuição: nenhuma era do diff da #2358.

⇒ **O hook de `apply_migration` protege a sessão que aplica, e não protege quem está na fila.** Ele
pergunta antes de aplicar; não impede que a DDL aplicada fique sem ser mergeada. A regra operacional
que falta é a outra metade: **aplicar e mergear são um passo, não só aplicar e commitar.**

## 5. `browser_guards`: a instrumentação da decisão 1 funcionou

Na #2358 (só `.md`) reprovou nas **duas** tentativas internas, classificando corretamente:

```
assinatura: workerd-nao-resolve-BaseLayout workerd-jsg-throw timeout-playwright
```

Re-rodado, passou. Ocorrência registrada na #2343.

**O contraste do dia reforça a hipótese ambiental, e é forte:** a #2358, de texto puro, reprovou duas
vezes; a #2359, que carrega migration, Edge Function, manifest e guard novo, passou **de primeira em
dois SHAs seguidos**. Uma PR de código verde e uma de documentação vermelha, no mesmo dia e no mesmo
runner, é o inverso de qualquer leitura por conteúdo.

⚠️ **Armadilha de instrumento, para quem for ler a assinatura:** ela chega ao `GITHUB_STEP_SUMMARY`
do job, que **não** é o mesmo campo que `check-runs/<id>.output.summary` da API. Consultar o segundo
devolve vazio e lê como "a instrumentação não escreveu". Ela escreveu. Leia pelo log do job.

## 6. Monitor de CI: "nenhum pendente" termina pela ausência

O primeiro monitor declarou **"todos verdes" com 1 check listado**, porque a condição de parada era
"nenhum pendente" e `gh pr checks` **não lista quem ainda não reportou**. Rearmado exigindo
denominador explícito (`n >= 12`), passou a medir certo.

⇒ **Toda espera por convergência precisa de denominador, não só de ausência de pendência.** E o
verde final foi reconferido por consulta direta antes do merge, porque um monitor que já mentiu uma
vez não é fonte.

## 7. Aberto

| # | o que | o que destrava |
|---|---|---|
| ata de comunicação 17/09 | sem fonte | compartilhar o doc de notas com a conta do dono |
| ata da tribo 8 17/09 | sem fonte | material está com quem hospeda |
| #2343 | flake do `browser_guards` | fase 2, com as ocorrências agora classificadas |
| #2340 | eixo local × CI | qual camada |
| #2342 | purgador carimba entregues | nomenclatura do campo |

**Fora do tracker:** o perfil do Playwright é compartilhado por ~13 servidores MCP, um por sessão, e
só um segura o lock. Foi liberado por outra lane e **retomado por outra sessão em menos de uma hora**.
Se depender disso com frequência, a saída é cleanup no `SessionEnd` ou perfil por sessão. Medido
hoje: 18 processos, 2.978 MB, um renderer com 53% de um núcleo contínuo por 11h45.

## 8. Comandos para re-medir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh pr view <N> --json mergeable,mergeStateStatus   # ANTES de esperar CI que nao comeca
npm run test:structural                            # metade hermetica, pode rodar com CI no ar
```

```sql
-- as tres reunioes de 17/09
SELECT e.type, e.title,
       (COALESCE(e.minutes_text,'')='' AND e.minutes_url IS NULL) AS sem_ata,
       (SELECT count(*) FROM public.attendance a WHERE a.event_id=e.id AND a.present)  AS presentes,
       (SELECT count(*) FROM public.attendance a WHERE a.event_id=e.id AND a.excused)  AS justificados,
       -- separe por kind: a tabela guarda acoes E decisoes na mesma relacao
       (SELECT count(*) FROM public.meeting_action_items m
          WHERE m.event_id=e.id AND m.kind='action')   AS acoes,
       (SELECT count(*) FROM public.meeting_action_items m
          WHERE m.event_id=e.id AND m.kind='decision') AS decisoes
FROM public.events e WHERE e.date='2026-09-17' ORDER BY e.type;

-- o conserto da #2351 continua vivo? (o resumo tem de aparecer DUAS vezes no corpo)
SELECT count(*) FROM regexp_matches(
  (SELECT prosrc FROM pg_proc WHERE proname='meeting_close'
     AND pronamespace='public'::regnamespace), 'Meeting close summary', 'g');
```
