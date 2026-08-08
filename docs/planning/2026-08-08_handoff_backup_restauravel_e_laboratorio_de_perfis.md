# Handoff — o backup passou a restaurar, e apareceu um laboratório de perfis (08/08/2026)

> `main` em **`2913aede`**. Tudo desta sessão está mergeado.
> Sessão anterior: `2026-08-07_handoff_arco_consentimento_e_acesso.md`.

## Regra zero

Nada aqui pode ser recitado. **Todo número foi medido em 08/08 e a base é viva.** O padrão que mais
custou nesta sessão, de novo, foi **verde sem significado** e **número certo com significado
errado**. Errei os dois três vezes, todas corrigidas por medição e nenhuma por raciocínio:

- "20 pendentes" era o **denominador** do ciclo, não a fila de ninguém.
- "backup quebrado há 3 semanas" era a **limpeza de artefatos**, cosmética; o dump funcionava.
- "não dá para medir sem gente" era falso: havia base restaurável e impersonação custa três linhas.

Um quarto, no fim da sessão, que vale como aviso de método: **armei um monitor de CI no
`git rev-parse HEAD` e depois empurrei outro commit.** O monitor passou a vigiar um head já
superado, devolveu "todos concluídos" de um SHA obsoleto, e eu anunciei um PR como mergeável
enquanto o `validate` do commit atual ainda rodava. O instrumento estava certo; o **alvo** é que
estava errado. Fixe o head pelo PR (`gh pr view N --json headRefOid`), nunca pelo working tree.

---

## Mergeado hoje

| PR | o que era |
|---|---|
| **#1673** | o rodapé dizia "Ciclo 4" e levava à playlist do ciclo 3 |
| **#1683** | versiona o handoff de 07/08 e os arranques da virada |
| **#1684** | seis defeitos no backup, fecha **#618** |

O `validate` vermelho do #1673 era **`PROD-AHEAD`**, não do PR: o banco tinha `20260807000600` e o
checkout parava em `…000500`. Resolvido por merge de `origin/main` **pelo remoto**
(`gh api .../merges`), sem tocar no branch local contaminado.

---

## O que mudou na postura de backup

Antes: duas cópias, ambas na nuvem e alcançáveis pelas mesmas credenciais, um dump que perdia o log
de auditoria inteiro, e um alarme vermelho há três semanas por motivo cosmético.

Os seis defeitos, todos da mesma família:

1. `pg_dump` não excluía `cron`/`net`, carregava `COPY cron.job` (tabela de extensão), o restore
   dava `permission denied` e o psql passava a ler dado como comando: **26.724** erros em cascata.
2. **`admin_audit_log` restaurava vazio**: 67.494 linhas na origem, zero no restaurado.
3. O workflow provava que o arquivo existe, abre e tem mais de 1 KB. Nunca que restaura.
4. A limpeza era **verde e vazia**, e isso só apareceu **depois** de consertar o 403: pedia
   `per_page: 100` sem paginar, e só 8 de 13 backups cabiam na primeira página de 389 artefatos.
5. A sonda de restore tinha corrida de inicialização (ver armadilhas abaixo).
6. Faltava a terceira cópia.

Estado validado em dois disparos no branch:

```
389 artefatos no repo, 13 deles sao db-backup-*   (antes enxergava 8)
Kept 8 backups, deleted 5
syntax errors no restore: 0                       (eram 26.724)
admin_audit_log = 74.283                          (era 0)
216 tabelas, 519 FKs
```

O dump encolheu de 17,4 MB para 13 MB: é a telemetria do `cron` saindo.

**Cópia local instalada e testada sob o systemd.** `scripts/pull-backup-local.sh`, timer
`nucleo-backup-pull.timer`, segunda 09:12, destino `~/.local/share/nucleo-backups` (0600, fora de
qualquer repositório). A unidade foi executada uma vez com `Result=success`.

---

## O laboratório de perfis (o que isto destrava)

Gates que resolvem por `auth.uid()` eram tidos como não-mediveis. Numa cópia restaurada:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '<auth_id do alvo>', true);
select public.a_rpc();
rollback;
```

⚠️ A imagem define `auth.uid()` lendo **`request.jwt.claim.sub`** (singular).
⚠️ A cópia é da **data do backup**: para testar código de hoje, aplique as migrations posteriores.
Rodar cru mede o comportamento **antigo**, o que é ótimo como controle e enganoso como validação.

### #1591 — confirmado sem depender de humano

| perfil | `selection_committee_role` | `submit_evaluation` |
|---|---|---|
| avaliador não-GP | `evaluator` | atravessou o gate, parou em `Missing score for criterion` |
| observador | `observer` | `Unauthorized: observer role does not evaluate` |

O que prova o gate são as **duas classes de recusa diferentes**. Se ambos falhassem igual, o teste
não provaria nada.

⚠️ **Resíduo confirmado:** observador por URL direta ainda recebe **20 pendentes** de
`get_my_pending_evaluations`.

### #1682 — reproduzido, corrigido e validado

Defeito **anterior ao #1666** (a versão de 03/08 já filtrava por `member_id`). Reproduzido com o
ledger local em 53 linhas, corrigido com a ponte de e-mail, **controle negativo** segurou. Alcance
**34**, batendo com a medição feita em produção por consulta independente.

---

## Investigações fechadas

**#1679 (curadoria)** — nenhuma das duas leituras da issue. As "37 submissões" são 29 de backfill
legado (autor nulo) mais 8 a veículo externo; `publication_submissions` não é a fila da curadoria.
A fila real tem **2 itens**. Sobre 87 ativos: **57 veem, 18 podem emitir parecer, 3 são designáveis,
3 são avisadas**. A maquinaria foi usada (2 `submitted_for_curation`, 11 `peer_review_completed`);
o passo final nunca. O item de 19/05 nunca gerou aviso porque o broadcast só existe desde 05/06.

**#1643** — parcial registrado. O único gate por consentimento em caminho de avanço é o de
`visitor_leads`, com **coorte bloqueada = 0** (ausência medida). Falta a terceira classe nas funções
de despacho e o `sign_proposer_consent`.

---

## 🔴 Aberto e não investigado: 10 membros sumiram sem rastro

Medido em 08/08:

| | |
|---|---|
| `members` no backup de 03/08 | **131** |
| `members` em produção hoje | **121** |
| criados desde 03/08 | **0** |
| ações de remoção/anonimização no `admin_audit_log` na janela | **0** |

A diferença estava concentrada em `inactive` (16 → 7). `admin_anonymize_member` anonimiza **no
lugar**, não apaga, então uma queda de contagem não deveria acontecer por ali.

**Próximo passo, e custa um minuto:** a cópia de 03/08 está em
`~/.local/share/nucleo-backups/backup_20260803_000010.sql.gz`. Restaurar, extrair os IDs de
`members` e comparar com produção diz **quais** 10 sumiram e o que elas eram.

---

## 🔴 Usuários de teste: o teste roda em produção, contra gente real

Levantado pelo PM ao ver que eu impersonei **pessoas reais** na base restaurada. O problema é maior
que o meu uso: a suíte de contrato já bate em produção contra candidaturas reais (#1636).

Medido em 08/08, `gate_attempts`:

| | |
|---|---|
| tentativas em `_issue_interview_booking_token_core` desde 04/08 | **542** |
| delas **sem ator** (service_role/cron) | **537**, em 5 dias distintos |
| candidaturas **reais** tocadas | **15** |
| tentativas que **passaram** o gate | **159** |

Para comparação, `schedule_interview` tem 31 tentativas espalhadas de 06/05 a 04/08: esse é o
perfil de tráfego orgânico. Os 542 em 5 dias não são.

⚠️ **A ser verificado, não afirmado:** `gate_attempts` registra a checagem do gate. Se as 159
passagens efetivamente emitiram token de agendamento para candidatos reais é outra pergunta, e ela
se responde cruzando com as tabelas de token e de entrevista. Isso **não** foi medido.

### A proposta

Personas sintéticas semeadas **na base restaurada**, nunca em produção, uma por perfil relevante
(visitante, membro, líder de tribo, avaliador, observador, curador, GP, ghost). Com elas:

1. os testes de contrato deixam de escolher candidatura real de produção (#1636);
2. o teste deixa de depender de **quem por acaso** ocupa o papel — hoje "o avaliador não-GP" é uma
   pessoa específica, e o teste quebra quando ela muda de papel;
3. some a PII do laboratório: hoje a base restaurada carrega 121 membros e 81 candidatos reais.

O ambiente já existe (`scripts/pull-backup-local.sh --restore`). Falta o seed de personas e apontar
a suíte DB-aware para ele em vez de para produção. É trabalho de sessão inteira e não foi começado.

---

## Decisões ratificadas pelo PM no fim da sessão

| # | decisão | estado |
|---|---|---|
| 1 | o schema `auth` **não** entra no dump | registrada em `docs/reference/RECUPERACAO_DE_DESASTRE.md`, com a consequência aceita escrita |
| 2 | **PITR não**; em vez dele, **dump diário** | PR **#1687** |
| 3 | abrir ticket pelos diários ausentes | rascunho em `docs/planning/2026-08-08_ticket_supabase_diarios_ausentes.md`; **envio é do PM** |
| 4 | implementar a correção do **#1682** | autorizada, **não começada** |

A decisão 2 foi tomada com o preço medido, não suposto: PITR de 7 dias custa **US$ 100/mês** contra
**~US$ 10/mês** do compute Micro do projeto inteiro. Eu havia recomendado "levantar o custo e
ligar"; com o número na mão, reabri a recomendação e o PM escolheu o dump diário.

⚠️ **As decisões 1 e 2 se somam numa dívida que precisa estar visível:** sem `auth` no dump e sem
PITR, um desastre de identidade se resolve **recriando contas via OAuth na mão**. É consequência
aceita, não esquecimento.

O #1687 traz três ajustes que a cadência exigiu, e o terceiro é defeito e não redação: retenção
8 → 30 no artefato (senão 8 dias de alcance onde antes eram 8 semanas), `concurrency` sem
cancelamento, e o aviso de backup velho recalibrado de **9 para 2 dias** — com dump diário, o limite
antigo ficaria mudo por mais de uma semana de falhas.

---

## Armadilhas medidas hoje

- **O `Schema Invariants` pode ficar vermelho por CONTENÇÃO, não por invariante quebrada.** Ele
  espera **900s** pela faixa de banco do #1509 e falha em vez de rodar concorrente contra produção,
  o que está **certo**. Só que quem segura a faixa é o `CI Validate` **do mesmo commit**, e ele
  levou **19 minutos** em 08/08. O teto de espera está calibrado abaixo da duração real de quem
  espera-se. Histórico: **2 falhas em 40** execuções, então não é rotina nem flake aleatório — é a
  condição específica de o `validate` esticar. A mensagem de erro nomeia o run que segurava, então
  classificar custa uma leitura de log. **Re-rodar só depois de a faixa liberar**; re-rodar com
  outro `validate` em voo repete a falha pelo mesmo motivo.

- **`pg_isready` no socket unix NÃO é prontidão.** A imagem sobe um servidor temporário que escuta
  só no socket e o desliga antes do definitivo. t=3s socket aceita e TCP não; t=4s TCP aceita.
  Conectar no temporário mata o restore no meio e devolve **banco vazio**, que é exatamente como um
  backup ruim se parece. Esperar por TCP.
- **Corrigir a causa barulhenta revela a silenciosa que ela escondia.** O 403 mascarava a paginação
  quebrada. Depois de consertar, verifique o **efeito**, nunca só a cor.
- **Compare o restaurado contra a DATA DO BACKUP, não contra produção agora.** Dezenas de tabelas
  "divergentes" eram crescimento. O controle: uma tabela que só ganhou linhas depois do dump deve
  voltar **vazia**.
- **Tabela ausente pode ter nascido depois** — datar pela migration (`git log` do arquivo).
- **Qualquer `syntax error` no log do restore é perda silenciosa**, não ruído. O tell é o token do
  erro ser um dado (`localhost`, `3`) e não um identificador SQL.
- **`gh api --paginate` emite um JSON por página**, e `--slurp` é incompatível com `--jq`.
- **Guard de âncora precisa de uma transação por função**, senão uma âncora ruim reverte o patch
  bom que já tinha passado.
- **Ao editar uma função grande, `replace` ancorado sobre `pg_get_functiondef` com `RAISE`** se a
  âncora não casar. Nunca transcrever.

---

## Regras da casa

- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens.
- **Postura de backup não vai para issue pública** (sem PITR, RPO, falhas do diário): é informação
  útil para quem ataca. Mesmo canal privado dos achados do #1383.
- Não rodar `npm test` com CI em voo. Gatear, não só imprimir o número.
