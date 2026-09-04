# Arranque 05/09/2026: o que ler, o que re-medir, o que decidir

> **Nada aqui é medição.** Foi carimbado no fim de 04/09 e envelhece sozinho.
> Antes de qualquer decisão, rode os quatro comandos da seção seguinte.

## Primeiro: re-meça (4 comandos, cerca de 15s)

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh run list --limit 10 --json headSha,conclusion,status,name
gh issue list --state open --limit 30
```

Estado ao encerrar 04/09, para você comparar e **não** para acreditar:
`main bd1ef003` · fila 0 PRs · 3 migrations de 04/09 aplicadas e na main · `main` verde nos 13
checks · janela de bypass em **2 de 2**, sem push direto e sem `--admin` em nenhuma das quatro PRs.

## A primeira coisa da manhã, e ela é uma previsão que pode estar errada

**A `#2185` deixou uma previsão falsificável, e o cron das 04:00 UTC já a exerceu.** Meça antes de
qualquer outra coisa, porque se ela falhou é premissa minha caída e não bug novo:

```sql
SELECT actor_kind, count(*) AS linhas,
       count(*) FILTER (WHERE accessed_at >= CURRENT_DATE) AS de_hoje
FROM pii_access_log GROUP BY actor_kind ORDER BY linhas DESC;
```

Ao encerrar 04/09: `human` **27.934** · `automation` **7.592** · `unknown` **0**.

O esperado é que `automation` tenha subido cerca de **136** (o lote diário de
`reconcile_initiative_drive_access`, medido sem exceção nos últimos 15 dias) e que **`unknown`
continue em 0**.

**Se `unknown` subiu**, alguma premissa da `#2185` está errada, e a pergunta é qual caminho gravou
sem declarar. O `context` responde:

```sql
SELECT context, count(*) FROM pii_access_log
WHERE actor_kind = 'unknown' GROUP BY context ORDER BY 2 DESC;
```

Um `context` que você não reconhece é caminho de escrita novo. Um que você reconhece é escritor que
ficou de fora da `20260904175905`.

## A segunda, e ela depende de terceiros

**As agendas do Fabricio e do Fernando.** O GP pediu em 04/09 para os dois abrirem. A verificação é
reabrir os quatro links de agendamento **em navegador** (fetch devolve 200 com a agenda vazia: são
3.501 bytes de casca em JS) e recontar contra a linha de base registrada na `#2188`:

| agenda | horários livres em 04/09, janela de 04 a 10/09 |
|---|---:|
| avaliador B (a fechada) | **0** |
| avaliador C | 6 |
| GP | 21 |
| institucional | 20 |

Os links estão em `selection_dispatch_url_log.resolved_url`. Se as quatro tiverem horário, o caso
corrente fecha e sobra só o item estrutural da `#2188`.

⚠️ **Não despache convite novo para desempatar isso.** O rodízio é LRD e o GP é o último da fila:
um despacho agora resolveria para a agenda que estava fechada. Os 4 candidatos presos já têm token
vivo apontando para a agenda do GP, e o mais antigo vence **09/09**.

## Antes de mergear ou pushar qualquer coisa

**A janela de bypass segue em 2 de 2** (`#2157`). Em 04/09 ela não avançou: quatro PRs mergeadas por
squash, nenhuma com `--admin`, nenhum push direto. Mantenha: **tudo por PR, inclusive handoff e
planning.**

⚠️ **`check-invariants` foi as duas coisas em 04/09**: dado de produção legítimo pela manhã e sinal
real à tarde. Ele **não é required** (o ruleset exige `validate`, `browser_guards`, `deno`,
`structural`), então vermelho nele não bloqueia, mas também não é ruído. Leia antes de mergear por
cima.

## O que espera decisão sua

1. **A frente única do cluster de rastro.** `#2176` (marcação de presença sem autor), `#2179` (guard
   raciocinando sobre campo que ninguém escreve), `#2180` (remoção de presença sem rastro) e `#2188`
   (despacho sem verificar destino) são quatro faces de **a plataforma executa o ato e não registra
   quem, nem o que a pessoa viu**. Tratar como frente única ou como quatro consertos separados?
   Quatro consertos custam quatro migrations e quatro guards que se sobrepõem.
2. **`#2187` item 3:** o destino das 5 linhas de presença em evento cancelado. Agendar
   `_cleanup_cancelled_event_attendance` resolve as cinco de uma vez, mas apaga registro alheio sem
   rastro. A ordem provavelmente certa é dar rastro à remoção (`#2180`) **antes** de agendar.
3. **`#2153`:** vale gravar a linha com o que a listagem deu e deixar as métricas nulas? A
   pós-condição fechou verde em 04/09 (29 de 51 com imagem e URN), então o item perdeu urgência mas
   o desenho continua na mesa.
4. **`#2152` decisão 1:** o selo da tela deve ler o VEP quando ele for mais recente que a
   verificação? Medido em 04/09: divergência **0**, e os nove casos da issue foram reescritos pelo
   `vep_sync` em 02/09. A premissa da issue caiu; virou desenho sem dano vivo.

## Registrado e sem issue própria

- **A migration `20260904132206`, já mergeada, contém uma afirmação falsa** sobre os escritores
  serem Edge Functions. Corrigida no cabeçalho da `20260904175905`, que aponta a causa. Se alguém
  ler só a primeira, sai com a informação errada.
- **`supabase migration repair` não roda nesta árvore** (projeto não linkado). As tracking rows
  existem no banco de qualquer forma, criadas pelo `apply_migration`, e o `rpc-migration-coverage`
  passa. Não foi linkado por decisão de escopo.
- **Três flakes em portão required num único dia:** uuid `"null"` num teste de roster, `ECONNRESET`
  num teste de agenda recorrente, e um `check-invariants` que era dado real. O primeiro tipo é a
  `#2177`: o teste desestrutura só `data` de `sb.rpc` e converte falha de banco em diagnóstico de
  domínio.
- **`uncancel_event_occurrence` e `clear_member_attendance` existem no banco e nenhum código as
  chama.** As duas só são alcançáveis por fora do produto.

## Prazos vivos

- **08/09** publicação do webinar (lane `.wt-campanha`)
- **09/09** vence o token de agendamento mais antigo dos 4 candidatos presos
- **10/09** Reunião Geral. Medido em 04/09 pela Agenda Viva: 1 bloco reservado, 20 minutos ocupados,
  **70 livres**
- **11/09** aprovação do TAP do Grupo de Estudos CPMAI (lane `.wt-cpmai`)

## O que continua parado do lado do PM, e é o que segura o dia 10

**Os cinco pontos da pauta**, que o Fernando cita duas vezes na thread do PMOGA como esqueleto da
descrição de cada produto, e **a atribuição da mensagem das 8:56** (se a mudança de cidade e a
indisponibilidade até meados da semana são do PM ou do coordenador do PMOGA).

Atravessaram 04/09 inteiro sem sair do lado dele. Sem os cinco pontos, o esqueleto das descrições
não se escreve, e é o material que a Reunião Geral de 10/09 usaria.

## A regra da sessão, que vale para a próxima

> **Este controle tinha como falhar?**

Quatro dos cinco erros de 04/09 foram pegos por essa pergunta, e nenhum deles teria sido pego pela
suíte. O prático:

- **injeção de defeito tem TRÊS asserções, não uma:** o defeito entrou no arquivo, o teste-alvo
  **rodou** (conte os testes executados, porque o alvo pode estar atrás de variável de ambiente e o
  arquivo roda 4 sem ela e 8 com), e ele reprovou;
- **vazio só vira fato depois de conferir que a chave da busca é do mesmo TIPO que a coisa buscada.**
  Procurar função pelo nome quando o que você tem é valor de coluna devolve vazio legítimo com cara
  de conclusão;
- **`null`, `""`, `undefined` e chave ausente são quatro estados**, e a linguagem trata os quatro
  diferente. Teste o campo que declara terminação, não a ausência do que só existe depois dela;
- **para o que o usuário vê, renderize.** `curl` responde sobre o servidor: devolveu 200 numa agenda
  que estava vazia;
- **`pkill -f <padrão>` mata o shell que o executa**, porque a linha dele contém o padrão. Use
  `[p]adrão`. E antes de declarar processo travado, compare o tempo decorrido com uma execução de
  referência.
