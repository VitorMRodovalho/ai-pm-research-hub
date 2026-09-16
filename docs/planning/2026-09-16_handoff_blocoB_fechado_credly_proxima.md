# Handoff de 16/09: o bloco B fecha, e a tabela de decisao do Credly e a proxima

> **Nada aqui e medicao viva.** Carimbado em 16/09, ~01h BRT. **Re-meca antes de decidir.**
> Repositorio publico: este documento nao nomeia ninguem, nao lista objeto e nao carrega prefixo
> de bucket. O inventario vive no registro privado do PMO.

**Estado ao encerrar, para COMPARAR:** `main 790f0d5f` · 1 PR aberta (#2312, do no pai) ·
issues deste arco: **#2296, #2297, #2313**, mais **#2286** (canal de digest) e a `[LL]` **#588**.

---

## 0. O que foi fechado

| PR / acao | issue | o que |
|---|---|---|
| #2317 | (sem issue) | handoff de 15/09 (noite) |
| #2319 | #2297 | o ranking segmenta por camada, e a camada sai do DADO |
| execucao em producao | (sem PR) | **bloco B fechado**: 6 objetos com dado pessoal de terceiro fora do bucket publico |
| #2313 | #2313 | titulo corrigido e re-medicao comentada (a premissa antiga caiu) |

---

## 1. A PROXIMA COISA A FAZER: tabela de decisao do Credly (#2296 item 3)

**Decisao do dono, 15/09: tabela de decisao por badge PRIMEIRO, canal depois.** A razao esta
medida e vale relembrar, porque ela inverte a ordem intuitiva.

### Por que a tabela vem antes do canal

O aviso do detector **nao manda e-mail nenhum hoje**, e isso foi medido:

- `detect_credly_unmapped_cron` grava `'digest_weekly'` LITERAL no INSERT e **nao chama**
  `_delivery_mode_for`.
- **Nenhuma secao** de `get_weekly_member_digest` renderiza o tipo `credly_unmapped_badges`.
  Cada secao filtra por lista branca de tipos.
- Mas `consumed_notification_ids` **nao filtra por tipo**: varre todo `digest_weekly` pendente na
  janela e carimba `digest_delivered_at`.

⇒ Resultado: **4 linhas do tipo, 4 carimbadas como entregues, 0 renderizadas.** O aviso so existe
na campainha (`get_my_notifications` nao filtra tipo nem modo), e dai 2 das 4 estarem lidas.

⚠️ **E e CLASSE, nao caso.** Medido nos mesmos termos: `agenda_blocks_pending` 74 linhas / 72
carimbadas, `recurrence_stockout` 22 / 20, `credly_unmapped_badges` 4 / 4. **100 linhas, 96
carimbadas sem nunca renderizar.** Cinco crons detectores gravam o literal sem chamar o helper.
Isso e a **#2286**, aberta.

⇒ Por isso a ordem: consertar o canal ANTES da tabela converteria "0 e-mail" em um e-mail mensal
de 39 itens, que e exatamente o ruido que a decisao queria evitar.

### O que a tabela tem de fazer, e o tamanho real do trabalho

O detector lista **39 badges / 64 ocorrencias** (`public._credly_unmapped_rows()`). Todos os 39
estao em `badge`/10 **por decisao**, nao por lacuna. Mas a decisao esta escrita em dois lugares
diferentes e com forca diferente:

| onde a decisao vive hoje | quantos badges | forma |
|---|---:|---|
| nomeados um a um em `tests/edge-functions/classify-badge.test.mjs` | **6** | guard explicito |
| frase de familia em comentario ("participation/recognition + out-of-domain certs") | **33** | prosa |

Os 6 nomeados: `Lifelong Learning`, `Essentials for Projects`, `Oracle Certified Professional,
Java SE 5 Programmer`, `DevOps Essentials Professional Certificate - DEPC`,
`OneTrust Certified Privacy Professional`, `Product and Project Collaboration`. A camada G de
`tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs` repete 5 deles.

⇒ **O trabalho embutido e um passe de julgamento sobre os 33 que ninguem afirmou um a um.**
Agrupaveis em duas familias: fidelidade/participacao/reconhecimento (**29**) e certificacao fora
do dominio IA+GP (**10**). A concentracao e real: `Lifelong Learning` e suas variacoes de ano sao
**21 das 64 ocorrencias**.

### O que ler ANTES de escrever a primeira linha

1. **A camada G do guard da #2296.** Ela diz, com data e razao: a decisao de 15/09 foi tomada sem
   a regra do **#1209** na tela, entao **nao a revoga**. Ate haver decisao nova e informada, o
   limite do #1209 vale e essas certificacoes ficam em 10.
2. **O guard do classificador mora em `tests/edge-functions/`**, nao em `tests/contracts/`, porque
   guarda CODIGO e nao DADO. Varrer so `tests/contracts/` foi o que quase atropelou o #1209.
3. **`gamification_points` e ledger append-only** desde a onda 3 da #1087. Desfazer e linha
   compensatoria, nunca remocao, e todo leitor que CONTA linha precisa passar a ler SALDO.
4. **`grep -rl "<tabela>" tests/contracts/`** antes de escrever no banco compartilhado. Para
   tabela NOVA, checar tambem se algum guard afirma contagem de `pg_proc` ou de migrations.

### Forma sugerida (nao decidida)

Tabela com `badge_name`, decisao, **razao**, **data** e quem decidiu, mais a mudanca em
`_credly_unmapped_rows()` para excluir badge com decisao registrada. Depois disso o detector passa
a listar apenas badge genuinamente novo. Isto e DDL: migration, RLS e guard proprio.

---

## 2. Bloco B: fechado, e o metodo importa mais que o resultado

Seis objetos com dado pessoal de terceiro sairam do bucket publico, em duas tranches autorizadas
pelo dono (4, depois 2). As copias privadas ja existiam, e a remocao ficou **travada em SHA-256
conferido na hora** nos dois lados: divergencia pulava o arquivo em vez de apagar.

| | antes | depois |
|---|---:|---:|
| objetos no bucket publico | 256 | **250** |
| bloco B ainda publico | 6 | **0** |
| bloco B preservado no privado | 6 | **6** |
| `hub_resources` total / ativas | 330 / 231 | **330 / 229** |

Nenhuma linha foi apagada, apenas desativada. O conteudo foi classificado por **estrutura**
(cabecalho de coluna), nao por leitura de linha: tres dos seis carregavam nome, e-mail, cidade,
cargo e organizacao de terceiro, em ordem de centenas de pessoas.

### ⚠️ A licao que vale para qualquer remocao de bucket publico

**A URL publica mente nos dois sentidos, e o "cache-buster" nao busta nada.** Medido:

| medicao | HTTP | `cf-cache-status` |
|---|---:|---|
| objeto vivo | 200 | HIT, `cache-control: public, max-age=3600` |
| objeto vivo com query string **inedita** | 200 | **HIT** |
| objeto apagado ha minutos | 400 | **BYPASS** |
| objeto apagado, query inedita | 400 | BYPASS |

1. **Query string nao entra na chave de cache.** Query inedita devolvendo HIT prova isso, porque
   nao havia como estar cacheada. O controle com `?v=<epoch>` que duas sessoes usaram era
   decoracao.
2. **A janela de exposicao pos-delete e PROPAGACAO da invalidacao, nao o TTL.** `BYPASS` minutos
   depois do delete, muito dentro dos 3600 s, exclui expiracao. A janela ficou **limitada** entre
   "logo depois" (vi 200) e "alguns minutos" (vi 400), e **nao foi cronometrada**. Nao converta
   "uns minutos" em numero.
3. ⇒ **Nunca verifique remocao pela URL publica.** A leitura confiavel e a ORIGEM
   (`storage.objects`, ou o objeto via service-role no bucket privado).

### Consequencia declarada, nao descoberta depois

As 6 linhas correspondentes continuam existindo e agora apontam para objeto que nao esta mais no
publico: **6 ponteiros mortos novos, da mesma classe dos 16 da #2313**. Todas inativas, raio zero,
mesmo conserto. **Nao** foram reescritas para a forma privada de proposito: seria trocar ponteiro
morto por link que navegador nenhum abre.

---

## 3. DECISOES PENDENTES DO DONO

1. **Triagem de direito das 17 obras do bloco A**, que seguem no bucket publico. E ela que decide
   se a #2313 precisa existir: se uma obra nao pode ser redistribuida, o conserto e tirar a linha
   e mover o objeto, sem codigo. Lista e familias juridicas no registro privado do PMO.
2. **A #2286**, canal de digest que carimba como entregue o que nunca renderizou (3 tipos, 100
   linhas, 96 carimbadas). Gate da ordem descrita na secao 1.
3. **Capacidade nova, se o dono quiser:** hoje **nao existe** ferramenta MCP que ENVIE campanha de
   e-mail. A superficie MCP tem `get_campaign_analytics` (leitura) e `fork_idea_to_channel` (cria
   rascunho de template). Envio em massa exige `auth.uid()` e sai da tela `/admin/campaigns`
   logado como GP (medido: `Forbidden: authentication required` com service-role). Isso e desenho,
   nao defeito. Criar um tool MCP atras de `manage_platform` e decisao de produto.

---

## 4. Em voo, nao concluido

- **Campanha de reforco da pesquisa da Tribo 4**: template `pesquisa-tribo4-cultura-change-reforco-set2026`
  criado e pronto em `/admin/campaigns`. Audiencia medida: **72** (`researcher` + `tribe_leader`),
  1 nova desde 11/09. A primeira teve 74 entregues, 47 aberturas (63,5%) e **8 cliques (10,8%)**,
  com 0 descadastro e 0 reclamacao. **O envio e do dono, na tela.**
- ⚠️ **Nao da para excluir quem respondeu**: o formulario e Google Form da tribo, as respostas nao
  chegam ao nosso banco e sao anonimas. Por isso o agradecimento vai no ASSUNTO e na primeira
  linha, fazendo o papel do filtro que o dado nao permite. **Clique nao e resposta**: os 8 sao teto
  do canal e-mail, e nao se sabe se o link circulou no WhatsApp.

---

## 5. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
npm run test:verdict   # DOIS blocos; o veredito consolida. NAO rode com o CI rodando.
                       # ⚠️ confira SUPABASE_ANON_KEY no .env: 41 arquivos de teste dependem
                       # dela, e sem ela eles PULAM em silencio (872 pulos na corrida de 15/09)
```

```sql
-- o detector, e o tamanho do passe de julgamento
SELECT count(*), sum(occurrences) FROM public._credly_unmapped_rows();

-- a classe da #2286: tipo gravado como digest_weekly que nenhuma secao renderiza
SELECT type, count(*) AS linhas,
       count(*) FILTER (WHERE digest_delivered_at IS NOT NULL) AS carimbadas
FROM public.notifications
WHERE type IN ('credly_unmapped_badges','agenda_blocks_pending','recurrence_stockout')
GROUP BY 1 ORDER BY 1;

-- Credly por CATEGORIA (nunca pelo prefixo `Credly:`: o estorno nao carrega o prefixo)
SELECT category, count(*), sum(points) FROM public.gamification_points
WHERE category IN ('badge','course','specialization','knowledge_ai_pm') GROUP BY 1;

SELECT count(*) FILTER (WHERE violation_count > 0) FROM public.check_schema_invariants();
```

---

## 6. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-16_handoff_blocoB_fechado_credly_proxima.md`.
> A tarefa e a **tabela de decisao por badge do Credly (#2296 item 3)**, decidida pelo dono:
> tabela primeiro, canal (#2286) depois. Re-medir a secao 5 antes de escrever.
> **Ler a camada G de `tests/contracts/2296-taxonomia-dos-badges-do-credly.test.mjs` e o guard do
> classificador em `tests/edge-functions/`, nessa ordem, ANTES da primeira linha de SQL**: o
> limite do #1209 continua valendo e ja foi quase atropelado uma vez.
> O trabalho embutido e um passe de julgamento sobre **33 badges** que ninguem afirmou um a um.
> `gamification_points` e ledger append-only: estorno e linha compensatoria, nunca remocao.
