# Handoff - encerramento da lane paralela do portfólio (21/08, ~08:30 UTC)

**Branches:** `claude/portfolio-cards-flags-tags-e7x1ar` (mergeada) · `claude/1900-cron-jornada-tribo` (PR #1905)
**Issue guarda-chuva:** #1900

---

## Estado em uma tela

| | |
| --- | --- |
| **#1899** | **mergeada** — `fe268cf2`, tip da main. CI 11/11. |
| **#1905** | **12 de 12 verdes, `mergeStateStatus=CLEAN`**, em draft. Aguarda só sair do draft. |
| Local, com credenciais reais | `npm test` 7013 testes · 7012 pass · 0 fail · 1 skip |

---

## ⚠️ Dois avisos que a sessão principal precisa ler primeiro

**1. A migration `20260821035435` é PROD-AHEAD enquanto a #1905 não mergear.**
Ela já está aplicada no banco compartilhado. Toda branch cujo checkout não tenha o `.sql`
reprova em `Phase C` e `ADR-0097`. **Se sua PR cair nesses dois, procure a palavra
`PROD-AHEAD` na mensagem** — o teste nomeia as versões e diz textualmente
*"This is NOT drift you authored"*. A **#1904** estava `BLOCKED` no fecho desta lane;
vale checar se é essa a causa.

**2. NÃO rodar `git stash drop` nem `git stash clear`.**
O `stash@{0}` ("Teleport auto-stash") ainda guarda as 14 linhas do conserto do
`CardDetail.tsx` da #1903. Os 300 deliverables já foram restaurados ao disco; o patch da
#1903 não.

---

## O que esta lane escreveu em produção

- **12 cards de Jornada da Tribo**, um por tribo ativa (T2 e T3 fora — iniciativa
  arquivada). Dono: GP. Líder: contribuidor. Nenhuma tribo passa de **4 de 8 passos**.
- **Cron `tribe-journey-cards-weekly`** (`20 6 * * 1`, jobid 88, ativo). Provado sem
  sessão: 12 reconciliadas, 0 erros, idempotente (12 cards, máx. 1 por tribo).
- **Nenhum flag de portfólio ou tag de tipo foi alterado.** Os 67 entregáveis sem flag e
  os 30 sem tipo são decisão dos líderes, não da heurística. Relatório card a card em
  `docs/audit/PORTFOLIO_FLAG_TAG_GAPS_2026_08_20.md`.

Os dois passos que quase toda tribo falha são **sistêmicos, não individuais**: gravação em
5 de 110 reuniões e ata em 26 de 110 (janela de 90 dias). Se algum líder reagir mal ao
card, esse é o número que desarma.

---

## #1881 — o item mais urgente, e não é desta lane

O corpo de `trg_board_item_deliverable_xp` exige
`(TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'done')`. O #1880 alargou as colunas
vigiadas (`status, is_portfolio_item, assignee_id`), mas o **portão de transição no corpo
ficou**. Consequência: marcar `done` e só depois marcar entregável **nunca paga XP** — e
essa é a ordem natural na tela.

Custo: derruba o `validate` de **todas** as branches pelo teste comportamental `#1147`.
Duas ocorrências em produção (19/08 e 20/08). A de 20/08 tem trilha completa em
`board_lifecycle_events`, o que fecha a lacuna de auditoria que a própria issue registrava
como impeditiva. Trilha e forma da correção comentadas na issue.

---

## Armadilhas medidas hoje (todas em memória)

1. **`apply_migration` e commit andam JUNTOS.** DDL no banco compartilhado sem o `.sql`
   commitado congela a fila de merge de todas as branches, inclusive PRs só de docs.
   Custou ~13 min de fila vermelha. E não dá para commitar sem aplicar: o `ADR-0097` tem
   baseline exato de arquivos locais sem linha em `schema_migrations`.
2. **`git add -A` neste repo é perigoso.** Varreu 150 deliverables (comunicados com nomes
   de membros, PDFs, handoffs internos) para dentro de um commit. Contido antes do push,
   mas o `pre-commit` **passou verde**: `docs/_deliverables/**` e `.playwright-mcp/**` não
   estão no `.gitignore` e o repositório é público. **Nomear arquivos no `git add`.**
3. **Uma árvore de trabalho para duas sessões custou três incidentes** em um dia. O
   auto-stash do Teleport faz `git status` devolver zero, então "árvore limpa" mede o
   efeito do stash, não a ausência de arquivos. **`git worktree` por lane.**
4. **Gate de CORPO não é gate de TIPO.** Conferir `md5(prosrc)` contra a captura na
   migration não cobre o `database.gen.ts` — são dois guards distintos.
5. **O log da CI não entrega o nome do teste que falha.** A API devolve ~45 KB da cauda,
   que numa saída TAP de 7.000 testes é o cleanup do git. Custou ~5 ciclos. A resposta veio
   rodando a suíte local com credenciais (e o reporter local é `spec`: procure `✖`, não
   `not ok`; confirme `skipped 1`, não `skipped 744`).

---

## Higiene de memória feita nesta sessão

- **`session-log` atualizado.** O log estava sem entradas desde **17/Jul**; anexei a desta
  sessão sem tentar preencher o intervalo.
- **`MEMORY.md` podado de 27.588 para 16.608 bytes.** Estava acima do limite de 25 KB, então
  **~2 KB do fim não carregavam em nenhuma sessão** — justamente os handoffs recentes.
  Detalhe movido para `handoffs-agosto-2026.md`; os relógios vivos (22, 23 e 24/08) ficaram
  no índice. 81 ponteiros antes, 81 depois, nenhum perdido.
- **6 memórias novas** sobre as armadilhas acima.

---

## Sobras, sem dono

- Apagar `backup/pre-rebase-1899` e `claude/portfolio-cards-flags-tags-e7x1ar` (as duas já
  estão na main).
- As **5 decisões do GP** seguem em
  `docs/planning/2026-08-20_handoff_lane_portfolio_flag_tag_e_card_de_jornada.md`:
  correção card a card do portfólio (T5 e T11 primeiro, 32 dos 67), triagem dos 34
  checkboxes do GP × Presidência, baseline em quadro de governança, responsável real dos
  cards "PARKED", e escopo não-tribo (127 de 369 cards).
- Marcar o cron como resolvido no log **só depois** do merge da #1905. PR aberta não prova
  entrega.
