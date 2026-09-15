# Handoff de 14/09 (tarde): quatro ondas fechadas, e três muros que não existiam

> **Nada aqui é medição.** Carimbado em 14/09, ~21h BRT. **Re-meça antes de decidir.**
> Repositório público: este documento não nomeia ninguém, por norma.

**Estado ao encerrar, para COMPARAR:** `main ecb36a59` · **nenhuma PR aberta** · issues abertas
deste arco: **#2286, #2291, #2292, #2295, #2296, #2297**. Lições na `[LL]` **#588**.

> **Seção 9 é a mais nova** e cobre o que aconteceu DEPOIS da primeira versão deste documento:
> sync das instruções globais, medição dos buckets públicos, e **duas decisões pendentes do dono**.

---

## 0. O que foi fechado

| PR | issue | o quê |
|---|---|---|
| #2284 | — | handoff da manhã |
| #2288 | **#2285** | o detector de contas não ligadas ganha cron (nasceu sem) |
| #2289 | **#2279** | o dev server que morre nomeia a causa, e o retry volta a poder passar |
| #2293 | **#2287** | o detector ganha superfície no MCP, e o aviso para de prometer urgência |

Todas com CI verde e sem bypass. Migrations `20260914160416` e `20260914181156`, cada uma com
**uma** tracking row e md5 normalizado idêntico ao arquivo local. EF `nucleo-mcp` publicada
(`--use-api`, ver #2277) e com smoke de `initialize` + `tools/list` passando: 54 tools no
`/semantic`, zero erro de Zod, scope novo presente.

**#2236 fechada** como resolvida pela #1948. **#2281 rebaixada**: o defeito que ela descreve mede
zero.

Ações sobre pessoas reais, todas autorizadas pelo dono nesta sessão:

- **Duas reuniões descanceladas** com presença registrada (18/08 e 04/09), com auditoria que diz o
  que é restauração e o que é registro novo.
- **XP órfão religado** à linha restaurada, evitando crédito em dobro.
- **1 e-mail de detector disparado**, 2 destinatários, `delivered` em 34 s.

---

## 1. A lição que vale mais que as quatro entregas

**Três vezes declarei que uma capacidade não existia, e ela existia.** Nas três o passo errado foi
o mesmo: `grep -rl "<nome>" src/`, achar só `database.gen.ts`, e deslizar de **"nenhuma superfície
chama"** para **"não existe"**.

| o que eu disse | o que havia |
|---|---|
| "falta construir o descancelar" | `uncancel_event_occurrence`, com portão de `manage_event` e escopo de líder |
| "não há drill-down de XP de terceiro" | `get_member_points_ledger(p_member_id, …)`, portão `view_pii` + capítulo + org |
| "vou construir um piso de data de entrada" | `_member_operational_since()`, já usada pela selagem desde a #1948 |

São coisas diferentes, e a segunda é **rara** neste repo: há centenas de RPCs e o frontend chama
uma fração. A frase correta, quando o grep no frontend volta vazio, é *"existe e nenhuma tela
chama"* — o que é um ACHADO (superfície ausente, trabalho pequeno), não um muro (feature nova,
trabalho grande). A diferença muda a estimativa por uma ordem de grandeza.

⚠️ **A varredura de capacidade se faz em `pg_proc`, não em `src/`**, e o corpo tem de ser lido
antes de concluir — o portão costuma estar lá.

---

## 2. O quase-erro mais caro do dia, e como foi evitado

A **#2281** pedia para filtrar o denominador de presença pela data de entrada, em
`_attendance_eligible_events`. Eu estava a um passo de fazer isso. O comentário da **#1948**, no
corpo da função de selagem, diz literalmente:

> "a coorte NAO muda — quem entrou depois do evento continua nela, e a distincao vai na COLUNA da
> linha, nao na presenca dela. Tirar da coorte quebraria 'selado => linha existe'."

Antes de escrever, medi o defeito **na definição exata da issue**: evento elegível anterior à
entrada em que a pessoa é COBRADA. Resultado nos 96 ativos: 90 ocorrências, das quais 35 com linha
excusada, 55 sem linha nenhuma, e **0 faltas cobradas**.

Ou seja: eu ia quebrar uma invariante de selagem para consertar um defeito que mede zero.

**E antes disso quase recomendei outra coisa pior.** Para a data de entrada, recomendei
`members.created_at`. Medido depois: teria **apagado 385 presenças reais** de 31 pessoas que
compareceram antes de a linha delas existir no banco (importações em lote de 05/03 com 27 membros e
09/06 com 22). O erro foi medir dentro do recorte que o próprio defeito define — os 14 —, em vez de
validar a regra contra a população inteira.

---

## 3. O que o sintoma era de verdade (#2295)

O relato dos líderes de 11/09 era real. Nenhuma das duas issues acertou o mecanismo:

- **#2236** dizia "o defeito é a linha existir" — diagnóstico certo, conclusão invertida. A linha
  PRECISA existir; é a coluna `excused` que a torna inofensiva.
- **#2281** dizia "o denominador ignora a data de entrada" — ele a considera, via #1948.
- O real é o terceiro: **quando o evento nunca foi selado, não há linha para carregar o `excused`**,
  e o painel conta o evento como devido.

**55 ocorrências, 10 pessoas**, pesando de 50% a 83% do denominador delas. Reproduzido: uma pessoa
citada no relato original aparece com **exatamente 16,7%**, e duas aparecem com **0,0%**.

---

## 4. A fila, na ordem acordada com o dono

**Três coisas bloqueiam o desenho da métrica de ranking**, e só três:

1. **#2292** — as **224 duplicatas (2.240 pontos, 40 pessoas, 26 ativas)**. Qualquer baseline
   calculado hoje carrega pontos falsos. Ordem interna acordada: 3 → 2 → 1.
2. **#2296** — a taxonomia dos **86 badges** do Credly no fallback. Se "Chapter Leader" passar a
   valer 30 em vez de 10, a distribuição por camada muda.
3. **As camadas vazias** (na #2297): `curator` e `comms_team` têm **0 pessoas**; chapter_liaison
   (10), guest (7) e sponsor (5) ficariam sem camada. Não se desenha segmentação sobre papel que
   ninguém tem.

**Correm em paralelo, sem bloquear:** os dois itens baratos de UX (#2297 R1/R2), ligar o aviso
mensal do Credly (#2286 + #2296), e o mecanismo das 55 sem linha (#2295).

⚠️ **Vermelho de pé que NÃO é desta sessão:** o ratchet do CodeQL falha na `main` desde
`fdedb6f9` (15:27) — um alerta `js/stack-trace-exposure` em
`send-portal-account-setup/index.ts:191` (`String(err)` no catch externo). **Escopado é pequeno**
(base 96 → vivo 97, uma instância), mas o padrão é sistêmico: 36 alertas da mesma regra já estão na
linha de base e há 54 ocorrências de `String(err)` nas EFs. **Não puxar esse fio** — consertar só o
alerta novo e republicar a EF.

Ele não aparece nos checks de PR (só roda na main, depois do merge), e por isso mergeei três PRs
por cima dele sem notar. **Confira o estado da main antes de mergear**, não só os checks da PR.

---

## 5. As issues abertas, em uma linha cada

- **#2286** — o digest carimba como entregue o que nunca renderizou: `consumed_notification_ids`
  não filtra por tipo. **76 de 78** linhas de dois tipos irmãos engolidas.
- **#2291** — cancelar reunião é porta de mão única: `uncancel_event_occurrence` existe e nenhuma
  superfície chama. Mais grave: um trigger apaga toda a presença ao cancelar, **sem registrar
  quem**, com comentário afirmando que as linhas "had no irreplaceable signal" — premissa que este
  caso falsificou.
- **#2292** — três defeitos de XP: limpar presença não limpa o XP (62 órfãs), a EF e a RPC
  discordam da regra, e restaurar presença gera crédito duplo. Mais o passivo de 224 duplicatas.
- **#2295** — o mecanismo real da presença (seção 3 acima).
- **#2296** — Credly: **81% classificado** e captura sem falhas (68 de 68 com URL têm badges), mas
  86 badges no fallback, 29% dos ativos sem URL, e o aviso mensal morre no digest.
- **#2297** — ranking opaco para auditoria, com a síntese de três análises independentes (UX,
  persona, produto) e a proposta de segmentação por camada do dono.

---

## 6. Armadilhas que esta sessão pagou, e que a próxima não precisa pagar

- **Medir dentro do recorte que o defeito define preserva a origem do erro.** Os 14 contra os 96:
  a recomendação errada teria apagado 385 presenças.
- **Zero de uma consulta é ambíguo entre dado e chamada.** Aconteceu 4 vezes: o `cron.job` vazio
  (era ausência real, provada por 71 jobs de controle), o `get_attendance_panel` com 0 linhas (era
  o portão), o `tools/list` sem o scope novo (superfície errada — `/mcp` em vez de `/semantic`), e
  os logs antigos do CI (o GitHub já os podou, e a extração voltou zeros que pareciam dados).
- **Campo que parece o melhor candidato pode ser de coorte.** `serviceStartDateUTC` do VEP é o mais
  antigo de todos e tem **103 candidaturas em 10 datas** (48 numa só) — é janela de oportunidade,
  não entrada. `acceptanceDateUTC` é individual (101 em 35 datas).
- **Campo de sistema externo não é o nosso.** `formsSignedDateUTC` é do VEP do PMI global, não o
  termo da plataforma. Correção do dono depois de eu ter feito essa inferência.
- **Guard escrito para o estado de hoje reprova quando algo muda sem quebrar.** Meu próprio
  contrato da #2285 exigia EXATAMENTE UMA migration definindo o wrapper, e a #2287 redefiniu três
  horas depois. Guard que confunde "mudou" com "quebrou" é guard que alguém desliga.
- **O re-run de um job do `validate` escreve fixtures em produção.** O `check-invariants` da main
  ficou vermelho logo depois, com `57014` (statement timeout) — assinatura documentada de
  contenção, não defeito. Classifique antes de caçar causa de código.

---

## 7. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh issue list --state open --limit 20
gh run list --workflow=codeql-baseline.yml --limit 3   # o ratchet ainda está vermelho?
```

```sql
-- o passivo de crédito duplo continua o mesmo?
WITH r AS (
  SELECT gp.member_id, COALESCE(a.event_id, e.id) AS evento
    FROM public.gamification_points gp
    LEFT JOIN public.attendance a ON a.id = gp.ref_id
    LEFT JOIN public.events     e ON e.id = gp.ref_id
   WHERE gp.category='attendance' AND COALESCE(a.event_id, e.id) IS NOT NULL)
SELECT count(*) AS pares_duplicados, sum(n-1) AS creditos, sum((n-1)*10) AS pontos
  FROM (SELECT member_id, evento, count(*) n FROM r GROUP BY 1,2 HAVING count(*)>1) x;

-- o defeito das 55 sem linha (#2295)
WITH base AS (
  SELECT m.id AS member_id, public._member_operational_since(m.id) AS entrada, ee.event_id, ee.event_date
    FROM public.members m CROSS JOIN LATERAL public._attendance_eligible_events(m.id, NULL) ee
   WHERE m.is_active AND m.current_cycle_active)
SELECT count(*) FILTER (WHERE a.id IS NULL)                                   AS sem_linha,
       count(*) FILTER (WHERE a.id IS NOT NULL AND a.excused IS TRUE)         AS excusadas,
       count(*) FILTER (WHERE a.id IS NOT NULL AND a.excused IS NOT TRUE AND NOT a.present) AS cobradas
  FROM base b LEFT JOIN public.attendance a ON a.event_id=b.event_id AND a.member_id=b.member_id
 WHERE b.event_date < b.entrada;

-- as camadas da proposta de segmentação ainda estão vazias?
SELECT count(*) FILTER (WHERE designations && ARRAY['curator'])    AS curador,
       count(*) FILTER (WHERE designations && ARRAY['comms_team']) AS comms_team
  FROM public.members WHERE is_active AND current_cycle_active;
```

---

## 8. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-14_handoff_presenca_xp_e_tres_muros_que_nao_existiam.md`. Re-medir o
> estado (seção 7) antes de decidir qualquer coisa. Seguir a fila da seção 4, começando pelo item
> 1 (#2292, ordem interna 3 → 2 → 1), com o conserto escopado do CodeQL junto por ser rápido.
> **Não** implementar segmentação de ranking antes de os três bloqueadores fecharem.

---

## 9. Adendo — o que veio DEPOIS da primeira versão deste documento

### Instruções globais: cinco meses de divergência silenciosa, corrigida

O PMO pai reportou "CLI do Gemini ausente". **Medição certa, conclusão errada:** o consumidor do
`~/.gemini/GEMINI.md` é o **Antigravity**, que está instalado (`~/.local/bin/antigravity`,
`/usr/share/antigravity`, perfil com `mcp`/`skills`/`knowledge`/`conversations`). O arquivo nunca
foi para um CLI. É a mesma classe da seção 1: procurar o consumidor pelo nome do arquivo em vez de
procurar quem lê.

**O achado real estava ao lado.** O próprio `GEMINI.md` declara: *"the same content lives in
`~/.codex/AGENTS.md` and `~/.claude/CLAUDE.md`. **Keep the three in sync — divergence here is
silent**"*. A divergência já tinha acontecido:

| arquivo | bytes | modificado | seções |
|---|---|---|---|
| `~/.gemini/GEMINI.md` | 3961 | 13/09 | 5 |
| `~/.codex/AGENTS.md` | 3865 | 13/09 | 5 |
| **`~/.claude/CLAUDE.md`** | **1789** | **19/04** | **2** |

Faltavam três seções inteiras no do Claude: **Measurement discipline**, **Machines** e **Repository
visibility**. Sincronizado por união (os bullets de atribuição mais ricos do Claude foram
preservados, não substituídos): 5.326 bytes, 5 seções, dentro do teto de 12.000.

⚠️ **E eu editei a cópia, não a autoridade.** Existe `~/projects/claude-config-global` (repo
privado, 13/09) cujo `sync.sh` copia repo → `~/.claude/`. Descobri isso **depois** de já ter
editado, lendo o `MEMORY.md` do PMO pai. Terminou bem por acaso: a lane do pai commitou o conteúdo
e o `sync.sh` reporta `IN SYNC`.

O pai corrigiu o `sync.sh` a partir deste caso: agora compara mtime, devolve `OVERTAKEN` com exit 4
quando a cópia é mais nova, e **recusa** oferecer o `--apply` que descartaria o trabalho.

### Medição dos buckets públicos (autorizada, sem ação)

**Três** buckets públicos, não dois — `member-photos` (112 objetos) também é, e não estava no
escopo.

| bucket | objetos | tamanho | natureza |
|---|---|---|---|
| `comms-media` | 184 | 362 MB | material de divulgação já publicado (Instagram 72, LinkedIn 30, reels 27). Mime restrito, teto de 50 MB. **Público por desenho** |
| `documents` | 261 | 231 MB | **importação única de 10/03**, tudo sob `knowledge-bulk/`: 163 PDF, 62 jpeg, 21 planilhas, 10 png, 5 txt. Sem restrição de mime nem de tamanho |

⚠️ **Falso positivo meu, e ele quase virou incidente.** A primeira classificação acusou 12 arquivos
com nome sugerindo documento pessoal (`cpf|rg|identidade`). A regex usou `rg` **sem fronteira de
palavra** e casou "emergente", "organization", "organizations", "vargas". Com fronteira:
**0 rg, 0 cpf, 0 identidade**. Reportar os 12 teria criado uma suspeita de vazamento inexistente,
e alguém teria agido sobre ela.

**O que a medição NÃO alcança**, e não deve ser apresentado como se alcançasse: o conteúdo das 21
planilhas (nome de planilha não diz o que há dentro) e se o acervo de 10/03 foi importado com
intenção de ser público — há material de terceiros ali, e a pergunta de direito autoral é separada
da de privacidade.

### DUAS DECISÕES PENDENTES DO DONO

1. **Bloco de ponteiro no topo do `~/.claude/CLAUDE.md`**, dizendo que o arquivo é cópia e que a
   fonte é `~/projects/claude-config-global`. Hoje nada no arquivo diz isso — foi por isso que a
   edição saiu do sistema de registro. O PMO pai concorda com o texto e **recusou fazer a pedido de
   par**, corretamente. Precisa sair do dono para ele. Alternativa levantada e não decidida: uma
   linha idêntica nos três arquivos, o que torna o drift entre eles visível pelo próprio `diff`.
2. **A pergunta de design de métrica do ranking** (#2297): se 56% dos pontos do topo vêm de uma
   dimensão exercida por 93% dos líderes e **1,7% dos pesquisadores**, o ranking mede contribuição
   ou papel? Bloqueada pelos três itens da seção 4.

### Lição de canal entre agentes, que serve à ADR de roteamento do PMO pai

Uma mensagem do PMO pai **nunca chegou** a esta sessão. O envio devolveu `success` com `msg_id`, a
sessão nunca girou (mesma referência, 6 dias de pé), e o conteúdo não existe no contexto.

**`success` do envio não é entrega** — a mesma lição da onda #2130 deste repo, agora no canal entre
sessões. Requisito que entra na ADR: todo passo entre agentes precisa de confirmação de
**recebimento pelo destinatário**, não de confirmação de envio pelo remetente. Se uma mensagem
Claude-para-Claude some em silêncio, um handoff Claude-para-Codex some também.

### Nota de CI

A PR deste handoff reprovou com **24 testes** no `validate`, todos DB-aware, com **HTTP 522** em
chamadas sem relação entre si. É infraestrutura (origem não respondeu), não dado nem código:
controle independente mostrou o Supabase em HTTP 200 / 0,32 s minutos depois, e o re-run passou
12/12 sem nenhuma mudança. **Classifique 522 e 57014 como indisponibilidade antes de caçar causa
de código** — e não mergeie por cima, porque o re-run é barato.
