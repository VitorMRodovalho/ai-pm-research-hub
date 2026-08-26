# Handoff 25/08 (noite) - #1987 fechada, e a fila cruzada entre duas lanes

**Estado final:** main `b091cc9a`, **fila VAZIA**, zero bypass. Merges da noite: **#1992** (#1990) e
**#1991** (#1987). Duas issues fechadas: #1990 e #1987.

O arranque apontava a #1987 como "a unica coisa aberta, e e barata". Ela era barata mesmo, mas
levantou uma pedra maior, e a noite virou tanto entrega quanto coordenacao de fila.

---

## 1. #1987 - a duplicacao da escada e DELIBERADA, e o ADR-0023 estava desatualizado

A pergunta era se a copia inline da escada dentro de `check_schema_invariants().A3` devia virar
chamada a `_derive_operational_role()`. **Resposta: nao.** A A3 deriva com algebra propria de
proposito; se as duas chamarem a mesma funcao, um erro DENTRO da escada fica invisivel para o
invariante que existe para pega-lo.

A "saida 2" que o corpo da issue propunha (criar um guard de paridade) **ja existia**:
`role-ladder-parity.test.mjs`, nascido em `19d4bd4f` (2026-04-24), **um dia antes da data do proprio
ADR**, e reapontado para o SSOT pela #1925. Sao 8 testes.

**A Amendment C registra o que faltava:** duplicacao e guard sao UMA unidade. Quem colapsar a copia
da A3 transforma o guard em tautologia, e provavelmente vai apaga-lo por parecer redundante. Nesse
momento a independencia da A3 acaba sem nada ficar vermelho.

### A pedra embaixo: o ADR descrevia uma producao que nao existe mais

Tres frentes, todas medidas contra o `prosrc` vivo:

1. **Nomeava a funcao errada.** Mandava atualizar "a CASE expression em `sync_operational_role_cache()`",
   onde nao ha CASE nenhum desde a #1925.
2. **A "Canonical CASE (2026-05-15, current)" lista 11 degraus; a producao tem 12.** A escada andou
   **4 vezes** desde maio, cada uma com decisao de PM registrada na propria migration, e nenhuma
   chegou ao ADR:

| mudanca | migration | decisao |
|---|---|---|
| `sponsor` sobe acima de `researcher` | `20260805000282` | Wave 1: dos 5 sponsors, so 1 mudava |
| `chapter_board` sobe acima de `researcher`/`observer` | `20260805000285` | PM 2026-06-28, "governanca vence" |
| degrau `institutional_auditor` (12o) | `20260805000292` | Onda 2 FU-3 (#952), ADR-0111, dormente |
| `co_gp`: `manager` -> `deputy_manager` | `20260822032921` | PM 2026-08-21, direcao A |

   A ultima **afeta 1 pessoa ativa hoje** (1 engajamento autoritativo `volunteer x co_gp`). Nao era
   clausula latente: o ADR descrevia errado um degrau em uso.
3. **"Sem enforcement automatico ... Futuro: script CI" nasceu falso**, ja que o script existia na
   vespera.

**A licao, que virou memoria:** o guard compara **codigo com codigo**, e ninguem le o `.md`. A
Amendment B ficou errada por tres meses com a CI verde o tempo todo, e uma das migrations **ate cita**
o guard pelo nome. Regra nova no `Priority ladder amendment rule` (passo 6): a PR que muda a escada
emenda o ADR **no mesmo PR**.

Tambem marcou o `Drift 1` (`comms_leader`) como RESOLVIDO: a Amendment B adotou o `tribe_leader` que a
Decisao pedia. Medido: 0 engajamentos com `role='comms_leader'`.

---

## 2. A fila cruzada, e por que a ordem importou

Duas lanes trabalharam em paralelo em worktrees separados (`ai-pm-research-hub` e `.wt-can-anywhere`).
A lane da #1990 aplicou DDL no banco compartilhado as **19:37 UTC** e so empurrou depois. Entre esses
dois momentos, **toda PR aberta ficava vermelha**, inclusive uma que so toca um `.md`.

A #1991 apanhou nos **dois** checks, cada um acusando uma funcao que ela nunca tocou:

| check | funcao acusada | causa |
|---|---|---|
| `check-invariants` | `create_next_geral_meeting` | Phase C body-hash drift |
| `validate` | `get_comms_pipeline` | `#1977 A'`: corpo vivo diverge da captura |

O proprio teste antecipa a situacao: *"Live bodies are EXPECTED to diverge from this checkout's
captures while that lag exists (DDL-lag, not authored drift). Land/rebase the missing .sql first."*

**Encaminhamento decidido pelo PM: #1990 primeiro, rebase da #1991 depois.** Sem bypass: nao havia
urgencia que justificasse gastar um evento num PR de documentacao, e o rebase resolveu os dois de
graca. Depois que a #1992 entrou, os dois vermelhos sumiram sozinhos e a #1991 fechou **13/13**.

### O aviso que se realizou

Antes de a #1992 existir, medi que `get_comms_pipeline` ja tinha perdido o "ramo vizinho" que o guard
`#1977 A (INVERSA)` exigia, e avisei que ele iria reprovar com **diagnostico invertido**: acusaria
*"ESTREITOU o portao"* com o portao **alargado**. Aconteceu exatamente assim.

O conserto foi na lane da #1990, e ela foi **alem do sintoma**: a assercao passou a nomear a **action**
em vez da chamada, e o guard virou **dois modos de falha com mensagens deliberadamente diferentes**
(a action sumiu -> "estreitou" e certo; a action esta la atras de helper desconhecido -> a lista de
helpers envelheceu, some o helper, nao mexa no portao).

---

## 3. Armadilhas medidas hoje

- **`_can_anywhere` recebe `person_id`; `can_by_member` recebe `member_id`.** Os dois sao `uuid`, a
  troca ingenua **compila** e mede **0 de 94**. Formas corretas medidas: `_can_anywhere(m.person_id)`
  = 16 e `_can_anywhere_by_member(m.id)` = 16. **O empate e coincidencia**: a segunda resolve por
  `persons.legacy_member_id` e alcanca so 92 dos 94.
- **Injecao que erra o alvo prova o CONTRARIO do que parece.** Na lane da #1990, a primeira injecao
  mirou `create_next_geral_meeting`, que nem esta na lista que aquele guard percorre. O teste passou,
  e passar quase foi lido como "a assercao nao pega".
- **`assert` de contagem antes da escrita salva o arquivo.** Meu script de edicao do ADR abortou
  quando um ancora tinha acento que eu escrevi sem til, sem gravar nada. Mas ele **nao era atomico
  entre arquivos**: o primeiro ja tinha sido escrito. Asserçoes de TODOS os alvos antes de QUALQUER
  escrita, nao por arquivo.
- **O namespace de memoria e compartilhado entre lanes.** As duas gravaram a mesma licao do `uuid` com
  nomes diferentes. Consolidado na versao melhor
  (`reference-dois-uuid-com-significados-diferentes-...`), que traz o ponto fino: **o guard tem de ser
  ESTATICO**, porque no vivo `false` por id errado e indistinguivel de `false` por nao ter a
  capacidade. Procure pelo CONTEUDO antes de criar arquivo de memoria novo, nao so pelo nome.
- **Detector apontado para o sintoma errado.** Armei relogio para a main andar; o que travava era a
  **decisao de mergear**, nao a CI. A #1992 ficou verde e ociosa por horas. Vigie a PR ficar `CLEAN`,
  que e o instante em que alguem precisa agir.

---

## 4. O que tem relogio

- ⏰ **27/08 08h40 BRT: o selo de presenca grava** (#1948). Decisao mantida: gravar as 77 e corrigir
  depois, em **3 passos, ou os tres ou nenhum**. Efeito 77 -> 66. O cron dispara sozinho.
- 🆕 **`operational-role-reconcile-daily` confirmado VIVO:** `jobid 90`, `4 0 * * *`, `active=true`,
  comando `SELECT public._operational_role_reconcile_cron();`. Primeira execucao 25/08 21:04 BRT. Na
  primeira semana, conferir `admin_audit_log` por `members.operational_role_reconciled`: ele **so
  grava quando houve mudanca ou erro**, entao ausencia de linha e o esperado.
- ⏳ Radar Tecnologico 13/07 segue o unico item de presenca aberto.
- ⏰ **28/08** funil · **09/09** retencao · **30/09** anonimizacao.

## 5. Higiene

`MEMORY.md` em **24.528** de 24.985 (folga **457**). A consolidacao da memoria duplicada devolveu 183
bytes, e a linha da #1987 foi comprimida para gancho de fechamento. Duas licoes novas entraram em
arquivos-topico **existentes**, sem custo de indice.

## 6. Proximo passo sugerido

Nada aberto desta sessao. Backlog remedido ao fechar: **62 high / 129 medium / 58 low**, mais **3 sem
prioridade** (#1985, #1963, #1951) que merecem um passe rapido.

⚠️ **Cuidado ao remedir isso:** a primeira contagem desta sessao usou `gh issue list --limit 200` e
devolveu 62/97/38, que **nao e o backlog, e o teto do comando**. Total real 252. Mesma familia de
[[reference-meca-o-denominador-que-o-guard-realmente-enxerga]]: o limite do cliente vira denominador
silencioso, e o numero sai plausivel.
