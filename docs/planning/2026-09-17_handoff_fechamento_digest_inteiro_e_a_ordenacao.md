# Handoff de fechamento 17/09: o digest inteiro auditado, e a ordenação que mordeu quatro vezes

> **Nada aqui e medicao viva.** Carimbado em 18/09 ~02h UTC (23h BRT de 17/09).
> **Re-meca antes de decidir.** Repositorio publico: este documento nao nomeia ninguem.

**Estado ao encerrar:** `main b95c4b31` · **0 PRs abertas** · invariantes **0 de 44** ·
deploy da main **success** · EF `send-notification-email` **v40** · lane `fix/2351-rota-de-ata` **aberta**.

---

## 1. O arco fechado: o digest saiu de "carimba mentira" para "audiencia declarada"

| PR | issue | o que |
|---|---|---|
| #2337 | #2286 | o carimbo do digest passa a DERIVAR do que foi renderizado |
| #2344 | #2341 | o gate do digest passa a enxergar job ausente |
| #2353 | #2345 | a audiencia de cada tipo de evento vira dado |
| #2352 | — | inventario de reconciliacao de atas |
| #2346 | — | regra MANDATORIA de assercao de guard |
| #2339 · #2350 | — | handoffs |

**As tres issues eram a MESMA classe em tres lugares da mesma familia**, e isso e o achado que
vale levar adiante:

| # | o gate procurava | o que acontecia |
|---|---|---|
| #2286 | lista branca de `type` de notificacao | 27 tipos sem secao; **das 2.661 que o digest carimbou, ZERO chegaram ao e-mail** |
| #2341 | 3 crons por nome num `WHERE IN` | um removido em maio; **job ausente = job saudavel**, remover o digest passaria em VERDE |
| #2345 | lista branca de `type` de evento | 13 eventos invisiveis, e **2 dos 3 nomes da lista nem existiam na base** |

⇒ **A forma do defeito e uma: a condicao e verificada num lugar e o resultado produzido em outro,
e nada amarra os dois.** (Formulacao da sessao `laptop-ops`, melhor que a minha — ver secao 5.)

### O que cada conserto fez de estrutural

- **#2286:** UMA classificacao decide secao E carimbo. O `ELSE` recolhe o resto ⇒ tipo novo
  **aparece** por default. Provado ao vivo: 13 montados, 13 carimbados, **diferenca simetrica zero**.
- **#2341:** expectativa de cron virou tabela, com aposentadoria como DADO e CHECK que recusa
  aposentar sem motivo. Provado: expectativa sem cron ⇒ **`red`** (antes: verde).
- **#2345:** audiencia por tipo virou tabela, com gate **por papel** derivado de `engagements` (25
  pessoas contra 99). Provado nos dois sentidos: com papel ve `lideranca`, sem papel **nao ve**, e
  `entrevista` (151 eventos privados) **nao aparece para ninguem**.

⚠️ **O default da #2345 e o INVERSO do da #2286, de proposito.** Notificacao nasce endereçada, entao
mostrar o nao-declarado e seguro. Evento nao: `entrevista` tem 151 e `1on1` tem 22. Quem impede o
silencio de se instalar la e o `ELSE`; aqui e a **assercao da volta** no guard.

---

## 2. A LICAO CARA: ordenacao de DDL, QUATRO mordidas no mesmo dia

| # | o que fiz | custo medido |
|---|---|---|
| 1 | `test:verdict` local durante o CI da propria PR | fixture orfa violou invariante, **15 assercoes** caidas |
| 2 | branch criada da main DEPOIS de aplicar DDL | PR de 1 `.md` reprovou por tabela orfa |
| 3 | DDL aplicada com a `main` sem o arquivo | **3 alertas do CI Monitor**, ~1h de producao desalinhada |
| 4 | (evitada) a #2345 so foi aplicada com a fila VAZIA | zero custo — a unica que fiz certo |

**O padrao:** `apply_migration` atinge o banco compartilhado na hora, e enquanto o `.sql` nao esta
no ref sob teste, aquele ref **nao explica o estado do banco** — o vermelho esta correto. A `main`
nao e excecao, o que eu tratava implicitamente como se fosse.

⇒ **Recomendacao para decisao do dono** (a regra vive so em memoria, recuperada por relevancia):
1. regra MANDATORIA no `CLAUDE.md`;
2. **hook `PreToolUse`** interceptando `apply_migration` para checar PR aberta.
Somente (2) e mecanismo. Hoje **nada** impede aplicar DDL com a fila cheia. Ver #2340.

---

## 3. A PROXIMA COISA: as tres reunioes de 17/09, todas pendentes

Medido em 18/09:

| reuniao | type | ata | presencas | acoes estruturadas |
|---|---|---|---:|---:|
| Alinhamento Comunicacao (semanal) | `comms` | **falta** | **0** | 0 |
| Reuniao de Lideranca #12 | `lideranca` | **falta** | 6 | 0 |
| Inclusao & Colaboracao — Semanal | `tribo` | **falta** | 6 | 0 |

⚠️ **O time de comunicacao esta com ZERO presencas registradas.** As outras duas tem 6 cada.

E o que cada uma precisa, alem da ata: desdobramento em acoes com responsavel e data, atualizacao
dos cards vigentes, e comentarios nos artefatos. **Nada disso tem caminho em massa** — e item a item.

⚠️⚠️ **ANTES de subir qualquer ata, leia a #2351.** `upsert_event_minutes` (a rota `write`) **grava
`minutes_posted_at`**, e `meeting_close` anexa o `p_summary` **somente dentro de
`IF NOT v_already_closed`**. Logo a sequencia natural `write` → `close` com resumo **perde o resumo,
sem erro, retornando sucesso.** A ordem segura hoje e `close` com o `summary` PRIMEIRO, ou o `write`
carregando tudo no `content`. A lane `fix/2351-rota-de-ata` esta consertando isso.

**A gravacao da lideranca vai para o YouTube**, e as institucionais tem "Notes by Gemini" no Drive do
Nucleo (`Meet Recordings/`, 39 itens) — diferente das reunioes de tribo, cujo material cai no Drive
**pessoal** de quem hospeda.

---

## 4. Reconciliacao de atas: a premissa nao se sustentou

Inventario em `docs/audit/INVENTARIO_RECONCILIACAO_ATAS_2026-09-17.md` (script reexecutavel em
`scripts/audit-minutes-drive-reconciliation.mjs`):

| | |
|---|---:|
| reunioes de tribo ocorridas | 317 |
| **sem ata** | **253 (79,8%)** |
| tribos com ZERO atas fechadas | **6** de 14 |
| candidatos no Drive do Nucleo | 45 |
| que **casam** com reuniao cadastrada | **7** |
| **cobertura real da importacao** | **2,8%** |

**A tribo 6 tem zero candidatos** — e e a que MAIS registrou atas (26 fechadas, parou em 04/08).
Cinco das oito pastas `Atas/` estao vazias. As ~249 restantes dependem de cada lider entregar:
**conversa de lideranca, nao engenharia.**

⚠️ **Armadilha do proprio instrumento, corrigida antes de entregar:** a primeira versao do script
casava por DATA quando havia uma unica reuniao sem ata no dia, e afirmou **15 importaveis / 5,9%**.
Eram falsos positivos (Reuniao Geral, Reuniao de Lideranca e um 1on1 atribuidos a tribo 8). **Data
igual e coincidencia, nao identidade.** Numero honesto: 7 / 2,8%.

---

## 5. Guard cego por presenca de string: tres vezes, e o caso irmao de outro dominio

Tres guards que eu acabara de escrever passaram com o mecanismo **REMOVIDO**, e as tres foram pegas
pelo **teste de mutacao** — nenhuma por leitura:

| # | assercao | por que ficou verde |
|---|---|---|
| #2335 | `/is_visitor/` solto | a string sobrevivia nos **comentarios** |
| #2286 | `ef.includes('other_notifications')` | casava **o comentario que eu escrevi** |
| #2341 | `/retired_at IS NOT NULL/` | casava a contagem no `RETURN` |

Virou regra MANDATORIA no `CLAUDE.md` (PR #2346) e **LL na #588**. Na #2345 as 6 mutacoes
reprovaram **de primeira** — a regra funcionou no mesmo dia.

**A sessao `laptop-ops` aplicou a licao e achou falha real no detector de paridade dela**, em bash:
`grep -q` confere presenca do marcador e o `awk` liga/desliga por ocorrencia — se o marcador
aparecer duas vezes, religa depois do END e concatena. Como os 3 espelhos vem do mesmo `sync.sh`,
uma duplicata entraria identica nos tres, os hashes concordariam e o detector daria **VERDE sobre
corpo extraido errado**. A formulacao dela e melhor que a minha e esta na #588 para o PMO promover
na skill `detector-design`, com os dois exemplos (SQL e bash), porque **so o par atravessa dominio**.

E o parentesco que ela nomeou: o meu #2341 era **detector que nao detectava**, o `ufw` dela era
**protecao que nao protegia**, e os dois passam no teste que a pessoa naturalmente roda, **porque o
teste natural e o braco positivo**.

---

## 6. `browser_guards`: 10 ocorrencias, e o pedagio ja e maior que o risco

| PR | conteudo | execucoes | falhas |
|---|---|---:|---:|
| #2339 · #2346 · #2350 | so `.md` | 3 cada | 2, 2, 3 |
| #2353 | migration + guard | 3 | 2 |
| #2344 · #2352 | codigo / script | 1 cada | **0** |

**As PRs de documentacao falham repetidamente; as de codigo passaram de primeira.** Isso e o inverso
de qualquer leitura por conteudo e reforca a hipotese ambiental. Raiz sempre igual:
`Unable to resolve BaseLayout.astro` no workerd + timeout, pagina variando.

⇒ **Recomendacao: rebaixar de `required`** ate a fase 2 da investigacao fechar (#2343 tem as fases
com critério de saída). Custo de hoje: ~10 execucoes de um job de 3 min mais um `validate` de 16 min
por re-run, para mergear texto.

---

## 7. Aberto, com diagnostico pronto

| # | o que | decisao pendente |
|---|---|---|
| #2351 | rota de ata: 8 tools, 4 absorvidas expostas; `write` engole resumo | **na lane** — dois caminhos de conserto, contar leitores de cada |
| #2343 | flake do `browser_guards` | **rebaixar de required?** |
| #2340 | serializacao local x CI + cleanup de fixture | qual camada |
| #2342 | purgador carimba 1.993 como entregues | nomenclatura do campo |

**Fora do tracker, na mesa do dono:** a sessao `laptop-ops` mediu duas linhas inertes em
`.claude/settings.json` (53 e 54: `Write(.env)` e `Write(.git/*)` — o matcher so avalia `Edit(`), e
o `Edit(` equivalente **ja existe** nas duas, logo **nao ha brecha**, so o aviso de startup. Ela
varreu 18 arquivos de settings do portfolio: **0 lacunas reais**. **Nao executei**: settings de
permissao nao se edita por pedido de par, mesmo correto — par nao concede escalacao.

---

## 8. Comandos para re-medir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open && gh issue list --state open --limit 8
npm run test:structural          # ANTES de abrir PR
# NAO rode test:verdict com CI de PR sua no ar (secao 2, mordida 1)
# ANTES de qualquer apply_migration: gh pr list --state open TEM de estar vazio
node scripts/audit-minutes-drive-reconciliation.mjs   # inventario de atas
```

```sql
-- as reunioes de 17/09 continuam sem ata?
SELECT e.title, e.type, (COALESCE(e.minutes_text,'')='' AND e.minutes_url IS NULL) AS sem_ata,
       (SELECT count(*) FROM public.attendance a WHERE a.event_id=e.id) AS presencas,
       (SELECT count(*) FROM public.meeting_action_items m WHERE m.event_id=e.id) AS acoes
FROM public.events e WHERE e.date = '2026-09-17' ORDER BY e.type;

-- #2345: todo type vivo tem audiencia declarada? (tem de ser 0)
SELECT count(*) FROM public._audit_event_type_digest_coverage()
WHERE eventos_na_base > 0 AND NOT declarado;

-- #2341: o gate continua enxergando?
SELECT p.jobname, (p.retired_at IS NOT NULL) AS aposentado, (j.jobid IS NOT NULL) AS existe
FROM public.digest_cron_expectations p LEFT JOIN cron.job j USING (jobname) ORDER BY 1;

-- estado do arco
SELECT (SELECT count(*) FILTER (WHERE violation_count>0) FROM public.check_schema_invariants()) AS invariantes,
       (SELECT count(*) FROM public.notifications WHERE delivery_mode='digest_weekly'
          AND digest_delivered_at IS NULL) AS pendentes_para_o_digest;
```

---

## 9. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-17_handoff_fechamento_digest_inteiro_e_a_ordenacao.md`.
> A tarefa sao **as tres reunioes de 17/09** (secao 3): ata, acoes com responsavel e data,
> presenca (o time de comunicacao esta com **ZERO**), e atualizacao dos cards. **Leia a #2351
> ANTES de subir ata** — `write` fecha a reuniao e faz o `close` seguinte descartar o resumo; a
> ordem segura e `close` com `summary` primeiro. Checar antes se a lane `fix/2351-rota-de-ata` ja
> consertou.
> **ANTES de qualquer DDL: `gh pr list --state open` vazio.** A ordenacao mordeu quatro vezes em
> 17/09 (secao 2), inclusive contra a propria `main`.
> Tres decisoes esperando o dono: rebaixar `browser_guards` de required (#2343), o hook de
> `apply_migration` (#2340), e as duas linhas inertes do `settings.json` (secao 7).
