# Handoff de 15/09 (noite): o Credly fecha, e um controle que nunca funcionou

> **Nada aqui é medição.** Carimbado em 15/09, ~19h BRT. **Re-meça antes de decidir.**
> Repositório público: este documento não nomeia ninguém nem lista o que estava exposto, por norma.

**Estado ao encerrar, para COMPARAR:** `main 49bc9530` · 0 PRs abertas · issues deste arco:
**#2296, #2297, #2308, #2313**, e a `[LL]` **#588** com seis lições registradas.

---

## 0. O que foi fechado

| PR | issue | o quê |
|---|---|---|
| #2310 | **#2308** (fechada) | o smoke atribui a falha pela janela da própria requisição |
| #2311 | #2296 | a taxonomia dos 86 badges do Credly |
| #2316 | #2297 | o ranking responde "o que eu faço para subir" |
| — | **#2313** (nova) | 16 linhas mortas e a URL de bucket privado que não abre |

---

## 1. A lição que vale mais que as entregas

**Usei como CONTROLE 16 linhas que nunca funcionaram, e o controle certificou o erro.**

Um pedido de nível portfólio queria mover objetos de um bucket público para um privado,
justificado por "16 linhas já servem desse bucket privado hoje, então o caminho está provado em
produção". Conferi que a FORMA da URL nova batia com a das 16. Copiei 24 objetos, reescrevi 23
linhas. Só DEPOIS exerci o caminho:

| requisição ao bucket privado (objeto que EXISTE) | código |
|---|---:|
| anônima | 400 |
| **com a anon key, que é o que o navegador manda** | **400** |
| com service-role | 200 |

E buscando as 16 uma a uma: **as 16 apontavam para objetos que não existem**. Zero delas jamais
funcionou.

⚠️ **Link morto e link privado devolvem a mesma coisa para quem visita.** O estado saudável e o
quebrado tinham a mesma assinatura vista de fora, e foi por isso que ninguém percebeu em meses.

⇒ **Exerça o caminho como o CONSUMIDOR, com a credencial do consumidor.** A chave administrativa é
a que está à mão e a que menos importa.
⇒ **Um caso existente só vira controle depois de provado.** Controle herdado é hipótese.

O que salvou foi a cláusula de parada do dono ("se algo não bater com a sua medição, pare e me diga
antes de escrever"). Reverti as 23 linhas e reli: estado idêntico ao inicial, nada apagado.

---

## 2. Duas estimativas minhas, as duas desmentidas pela primeira medição

| eu disse | medido |
|---|---|
| "#2313 é onda **pequena**" | **5** superfícies renderizam `hub_resources`, mais resolvedor e guard |
| "o bug do cache é **uma linha**" | a coluna é lida por **14 funções** e 3 telas, e **5 CONTAM** o tamanho do array, incluindo uma de LGPD |

⇒ **Eu estimava pelo lugar onde o defeito APARECE, não por quem DEPENDE dele.** Para coluna de
banco, pergunte especificamente **quem CONTA** (`count(`, `array_length`, `jsonb_array_length`).

---

## 3. O limite que eu quase atropelei (#2296)

Levei ao dono "DEPC, OneTrust e Oracle são certificação real, subam de faixa", e ele aprovou. O
**#1209 (GP, 08/07)** já tinha decidido o contrário, com razão escrita: *out-of-domain certs
(núcleo = IA + GP)* ficam em 10.

⚠️ Eu tinha varrido `tests/contracts/` atrás de guard, como manda a regra do repo. **Esse guard mora
em `tests/edge-functions/`**, porque guarda código e não dado. Quem pegou foi rodar a **suíte
inteira**: 5 falhas, todas guard rails explícitos.

Voltei ao dono COM a regra na tela e com a incoerência medida (14 linhas/8 pessoas/140 pontos sob o
limite, contra 29 linhas/8 pessoas/**725 pontos** já valendo 25 sendo igualmente fora de IA+GP). Ele
**manteve o #1209**. As 5 mudanças conflitantes foram revertidas e o conflito ficou registrado em
comentário no classificador e na camada G do guard novo.

---

## 4. Escrita em produção, antes e depois

### Credly (`reason ILIKE 'Credly:%'`)

| categoria | linhas antes | depois | pontos antes | depois |
|---|---:|---:|---:|---:|
| `badge` | 118 | **64** | 1.180 | 640 |
| `course` | 5 | **37** | 75 | 555 |
| `specialization` | 84 | **104** | 2.100 | 2.600 |

- **Backfill:** 54 linhas, 23 pessoas, +480 pontos. SQL **gerado de `classify-badge.ts`**, para não
  haver segunda fonte de verdade entre código e dado.
- **Estornos:** 10 linhas, 8 pessoas, −100 pontos, cada uma com o `occurred_at` do crédito revertido.
  **0 dentro do `cycle_4`**, medido antes e confirmado depois.
- 47 dos 86 badges reclassificados; **39 permanecem em 10**, sendo 29 por participação e 10 pelo
  limite de domínio.

⚠️ **Leia o saldo por CATEGORIA, não pelo prefixo `Credly:`.** O `reason` do estorno não carrega
esse prefixo, então uma consulta filtrando por ele enxerga o defeito e não o conserto. Foi o que me
fez anunciar um defeito inexistente por alguns minutos.

### Storage

- `documents`: **261 → 256** objetos. As 256 linhas apontam para ele: relação **1:1, zero órfãos**.
- 5 órfãos retirados do bucket público e preservados no privado, com **tamanho em bytes conferido
  origem contra destino** antes de qualquer remoção.
- `governance-archive`: 16 → **44** objetos, dos quais **28 foram pré-posicionados e ainda não têm
  linha**. É proposital, não lixo: com a #2313, reescrever as linhas passa a ser o único passo.

---

## 5. DECISÕES PENDENTES DO DONO

1. **Canal de exceção do detector do Credly** (#2296 item 3). O detector lista 39 badges, e 29 estão
   em 10 **por decisão**. Ligar o aviso assim embarca e-mail mensal sobre o que ninguém vai mexer.
   Opções: tabela de decisão por badge (recomendada: a exceção vira dado com razão e data) ou delta
   contra a última notificação (mais barato, a razão não fica escrita).
   ⚠️ E o conserto que a issue prescreve **não teria efeito sozinho**: `detect_credly_unmapped_cron`
   grava `'digest_weekly'` literal no INSERT e **não chama** `_delivery_mode_for` (o precedente do
   #2285 funciona porque o cron dele chama). Não há trigger que sobrescreva.
2. **Triagem de direito dos 19** que seguem no bucket público. É ela que decide se a #2313 precisa
   existir: se uma obra não pode ser redistribuída, o conserto é tirar a linha da biblioteca e mover
   o objeto, sem código.

---

## 6. Próxima prioridade, se nada mudar

**A segmentação por camada da #2297** — a segunda metade do pedido do GP, e o único item substancial
que **não depende de decisão de ninguém**. Fonte já decidida e medida:

`operational_role` **particiona** os 96 ativos sem sobra: researcher 58, tribe_leader 14,
chapter_liaison 10, guest 7, sponsor 5, manager 1, deputy_manager 1. `designations` cobre só **26 de
96** e é dela que vinham os zeros. Comms pela grafia real (`comms_member` 6 + `comms_leader` 1 = 7
pessoas); `curator` sai da proposta (0 nas três fontes).

---

## 7. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
npm run test:verdict        # DOIS blocos; o veredito consolida. NAO rode com o CI rodando
```

```sql
-- Credly, por categoria (o filtro que os leitores de placar usam)
SELECT category, count(*), sum(points) FROM public.gamification_points
WHERE category IN ('badge','course','specialization','knowledge_ai_pm') GROUP BY 1;

-- o detector, e quantos dos que ele lista estão em 10 POR DECISÃO
SELECT count(*), sum(occurrences) FROM public._credly_unmapped_rows();

SELECT count(*) FILTER (WHERE violation_count > 0) FROM public.check_schema_invariants();
```

```bash
# storage: o bucket publico e as linhas que apontam para ele (tem de bater 1:1)
# a API de list NAO recursa: varra por prefixo (knowledge-bulk/geral e /adm) ou reporta 2 onde ha 256
```

---

## 8. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-15_handoff_credly_fecha_e_um_controle_que_nunca_funcionou.md`.
> Re-medir a seção 7 antes de decidir. A seção 5 tem **duas decisões do dono**, e a 6 diz a próxima
> prioridade se nada mudar (segmentação por camada da #2297, já desbloqueada e com a fonte medida).
> **Antes de mexer em qualquer tabela ou coluna, rode o grep de dependentes e pergunte quem CONTA** —
> a seção 2 tem duas estimativas minhas que a primeira medição desmentiu.
