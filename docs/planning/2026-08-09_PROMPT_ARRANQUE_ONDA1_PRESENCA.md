# Prompt de arranque - Onda 1: Presença (épica #1652)

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-09_handoff_onda0_trilha_a_estado_do_backlog.md` (trilhas a e b da Onda 0).
> O plano por ondas vive em `~/.claude/plans/` (fora do repo). **Ler antes de escolher trabalho.**

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número aqui tem data e foi medido em 09/08/2026;
re-medir com tool call na mesma volta em que o número entrar numa decisão, num commit, numa issue
ou numa pergunta ao PM. Os padrões que já custaram caro, agora sete:

- **verde sem significado** (o gate passou, o efeito não aconteceu)
- **número certo, significado errado** (a query estava certa, a população não era a da pergunta)
- **vermelho sem defeito** (o gate falhou por infraestrutura, e o dedo aponta para a mudança nova)
- **verde por vacuidade** (o teste não exerceu nada; `skip` e ramo vazio leem como verde)
- **medido no lugar errado** (a varredura certa sobre o recorte errado)
- **citada em PR mergeado não prova entrega** (o #1354 tinha o sintoma resolvido e **1 de 5**
  critérios; conferir critério a critério, nunca pelo PR que cita)
- **o denominador se move** (a divergência de presença foi medida sobre 89 membros; hoje são 87)

⚠️ **Nunca escreva `close #N` / `fixes #N` / `resolves #N` num corpo de PR sem intenção de fechar,
nem para CITAR o padrão.** Aspas, crase, itálico e negação **não** protegem, porque o parser do
GitHub não olha o contexto: em 09/08 o PR #1698, que era só de documentação, fechou a #96 porque o
corpo dele citava uma frase em que o verbo de fechamento vinha colado ao número dela. Era a segunda
vez, pela mesma causa. Para citar o padrão, quebre-o (`clos&#101; #N`, `close #<!-- -->N`) ou
descreva sem pôr o verbo junto do número.

E o espelho: **`Fecha #N` (português) não fecha nada** - só `close/closes`, `fix/fixes`,
`resolve/resolves`.

⚠️ **Esta linha vale para o próprio arquivo:** ao copiar qualquer trecho deste arranque para um
corpo de PR, confira antes se ele carrega um verbo de fechamento colado a um número.

---

## Estado

`main` em **`557124f2`**. Nada em voo.

A Onda 0 fechou as trilhas (a) e (b). Backlog: **191 abertas**, **0 sem onda atribuída**, todas com
exatamente um rótulo `onda:*`. Consulta: `gh issue list --state open --label "onda:1"`.

**Decisão do PM (09/08): a próxima é a Onda 1, Presença.** Ordenar as 6 famílias novas
(`onda:legal-ops`, `onda:admin-ui`, `onda:dados-metricas`, `onda:comms`, `onda:suite-ci`,
`onda:certificados`) **não** é pré-requisito: elas ficaram fora da sequência porque nenhuma tem
relógio correndo. Presença tem.

---

## Por que esta onda, e o relógio dela

O problema foi levantado **ao vivo** por duas líderes na Reunião de Liderança de 06/08: os números
de presença não batem entre duas telas da própria plataforma. Não é dívida técnica achada em
varredura, é gente reclamando de dado errado.

Medido em 09/08/2026 (re-medir antes de usar):

| medida | valor |
|---|---:|
| linhas em `attendance` | **2.029** |
| presenças | **1.935** |
| **faltas simples** (`present=false`, `excused=false`) | **3** |
| faltas justificadas | 91 |
| linhas sem `marked_by` | **1.724** (85%) |
| membros ativos (denominador) | **87** |
| eventos nos próximos 30 dias | **74** |
| funções em `public` que leem `attendance` | **95** |

**Três faltas simples na base inteira.** Não porque todos comparecem: porque
`public.mark_member_present(p_present := false)` **APAGA a linha** desde 19/05 (p199-c). Confirmado
no corpo vivo em 09/08: a função ainda tem `DELETE`. A plataforma não consegue expressar "faltou",
então toda métrica precisa **inferir** a falta da ausência de linha, e é daí que saem as três
semânticas.

---

## A épica #1652 e a ordem, que é de dependência e não de gosto

A épica lista 4 filhas, e na trilha (b) adotou mais duas: **#1660 é a raiz e estava fora dela**.

```
#1653  alívio curto      → o WHERE que compara com NULL
   ↓
#1660  a raiz            → falta simples volta a ser gravável
   ↓
#1657  a inferência      → parar de inventar falta a partir de linha ausente
   ↓
#1656  o contrato        → uma semântica, uma escala, e a tela diz qual métrica exibe
   ↓
#1655 → #1654  a superfície → unificar as grades, depois a coluna de nome fixa
```

### Primeiro passo concreto (#1653)

`get_tribe_attendance_grid` filtra com `(e.initiative_id IS NULL OR i.legacy_tribe_id = p_tribe_id)`.
Iniciativa avulsa tem `legacy_tribe_id` **NULL**, então a comparação é NULL para **qualquer** tribo
e o evento cai de **todas** as grades. Confirmado em 09/08: o predicado `legacy_tribe_id` continua
no corpo vivo. Fix curto, ganho visível na hora, e é o que produz a divergência que as líderes veem.

⚠️ **Antes de aplicar: medir a divergência.** O aceite da onda é "0 membros vendo dois percentuais",
e o número de partida **precisa ser medido nesta sessão**, não recitado - o denominador já mudou de
89 para 87 desde que o plano foi escrito. Rodar a query de divergência (painel × grade de tribo)
antes e depois, e publicar os dois.

### Risco declarado, a carregar até o fim

O **#1660 muda o significado de uma linha ausente**. Antes de aplicar:

1. **contar** quantas superfícies leem `attendance` por ausência (partida: 95 funções em `public`
   mencionam `attendance`; quantas inferem por ausência é a pergunta, e é outra query)
2. tratar as **1.724 linhas sem `marked_by`** como dado histórico que **não** pode ser
   reinterpretado retroativamente
3. o p199-c tinha intenção legítima: "tirar presença" precisa continuar existindo, como ato
   **distinto** de "marcar falta". Não apagar a capacidade, separar os dois atos.

---

## Aceite da Onda 1 (do plano, com o denominador re-ancorado)

- [ ] **0 membros** com percentual divergente entre painel e grade de tribo, com a query rodada
      antes e depois e os dois números publicados (o denominador é 87 hoje, não 89 - re-medir)
- [ ] **0 líderes** divergentes
- [ ] falta simples **gravável e legível**: registrar uma em **fixture sintética**
      (`tests/helpers/selection-fixtures.mjs` é a convenção; nunca alvo real), ler de volta nas três
      semânticas, e **provar por mutação** que o teste fica vermelho se o `DELETE` voltar
- [ ] `_attendance_eligible_events` é a **única** fonte de elegibilidade
- [ ] **uma** escala no contrato das RPCs e **zero** ocorrências do coalesce `rate <= 1` no front
      (o tell está em `src/components/tribes/TribeAttendanceTab.tsx`)
- [ ] **uma** grade membro × evento viva; a órfã apagada
- [ ] toda tela de presença **nomeia a métrica que exibe**
- [ ] a falta fantasma de 09/07 resolvida, com o par duplicado tratado e a decisão registrada

---

## Vizinhança: o que NÃO é filho desta épica

A trilha (b) recusou explicitamente, e a recusa vale tanto quanto a aceitação:

- **#1699** (épica nova): série recorrente sem chave de idempotência. `events.recurrence_group`
  não tem índice único, e havia **2 pares repetidos vivos** em 09/08. Alimenta a mesma tabela
  `attendance`, então **cruza** com esta onda, mas tem causa própria. Filhas: #1676, #1528, #1565.
- **#1700** (épica nova): `get_current_cycle()` existe e **0 de 133** corpos SQL a chamam. É a causa
  de "o número que a plataforma reporta". Filhas: #1669, #1607, #1603.

Se algo da Onda 1 esbarrar em recorte de ciclo ou em evento duplicado, o destino é uma dessas duas,
não o escopo desta.

---

## Três decisões do PM ainda em aberto

1. **Ordenar as 6 famílias novas** na sequência das ondas (`onda:legal-ops` é a maior, 19, e a que
   mais depende de terceiro; inclui o #334 do Art. 48).
2. **#233** segue `status:blocked` **sem bloqueador nomeado** desde 21/05: nomear, atribuir onda ou
   fechar.
3. **#727** ficou aberta só pelo farol 🔴 vencido, cujo pré-requisito (#571) está **fechado**. Vale
   retitular para o resíduo.

Pendências antigas que não mudaram: **reescrita de histórico** (force-push bloqueado pelo harness,
é ação do mantenedor, e avisar o audit de bypass antes) e **notificação LGPD Art. 48** (#334,
`status:blocked`).

---

## Ferramentas e armadilhas já pagas

- `tests/helpers/selection-fixtures.mjs` - fixture sintética. **Use isto** em vez de escolher alvo
  por predicado sobre produção.
- `tests/helpers/rpc-call-scanner.mjs` - distingue **chamar** uma RPC de **mencioná-la** num literal.
- `tests/contracts/pii-nenhum-dado-pessoal-versionado.test.mjs` - guard de PII, allow-list.

1. coluna **derivada** tem de ser gravada **por último** (criar os filhos dispara o recompute)
2. vínculo **polimórfico** (`source_id` sem FK) **escapa do CASCADE**
3. `.gitignore` **não desrastreia** o que já está rastreado
4. `grep -I` ignora binário
5. **função de 19 KB**: mudar por replace **ancorado** e extrair por script, nunca transcrever
6. **`CREATE OR REPLACE` de função compartilhada**: basear no corpo **vivo** (`pg_get_functiondef`),
   não no arquivo de migration

---

## Verificação, antes de declarar qualquer coisa fechada

1. `npx astro build` passa
2. `npm test` com `.env` **exportado**: 0 fail e **1 skip** (não ~548 - senão o verde não significa
   nada). O número de skips é o que dá sentido ao resultado.
3. `SELECT * FROM public.check_schema_invariants()` com `violation_count` 0
4. as queries de aceite rodadas **na volta** em que o número é afirmado
5. **CI: monitorar por RUN** (`gh run list --json headSha,name,status,conclusion`), **nunca** por
   `gh pr checks` - ele **omite** gate enfileirado em vez de mostrá-lo pendente, e isso já produziu
   um "CI completo" falso com dois gates que não tinham começado
6. depois de empurrar correção, **cancelar os runs do SHA velho** - eles seguram a fila e os novos
   ficam `pending` atrás
7. não mergear com CI de outro PR em voo (satura o `wait-for-db-lane`, #1509)

---

## Regras da casa

- Merge à `main` é da sessão main; lane leva o PR até verde e para.
- **Force-push bloqueado pelo harness.** Atualizar branch por `git merge origin/main`.
- Conflito na linha do `test` no `package.json`: resolver **por script**.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PÚBLICO**: nenhum candidato ou membro nomeado, só contagens. E não descrever onde dado
  pessoal está no histórico enquanto a reescrita não acontecer.
- DDL vai por `apply_migration`, nunca por `execute_sql`, e exige o sync manual do arquivo local +
  `migration repair` + `NOTIFY pgrst, 'reload schema'`.
- Não rodar `npm test` com CI em voo.
