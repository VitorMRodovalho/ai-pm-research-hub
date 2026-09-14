# Handoff: duas ondas fechadas, e uma fila que nasceu de uma conclusão invertida

> **Nada aqui é medição.** Carimbado em 14/09, ~15h30 BRT. **Re-meça antes de decidir.**
> Repositório público: este documento não nomeia ninguém, por norma.

**Estado ao encerrar, para COMPARAR:** `main fdedb6f9` · **nenhuma PR aberta** · issues abertas
deste arco: **#2275, #2277, #2279, #2281, #2282, #2283**.

---

## 0. O que foi fechado

| PR | issue | o quê |
|---|---|---|
| #2276 | **#2273** | a jornada de entrada fecha: portal fala a língua do catálogo e tem caminho para dentro |
| #2280 | **#2278** | a presença lida pelo MCP para de afirmar que quem faltou esteve na reunião |

Ambas com CI 13/13 e **sem bypass**. Migrations `20260914120519` e `20260914150241` aplicadas, as
duas com o arquivo local **byte-idêntico** ao statement da tracking row (md5 conferido).

Ações sobre pessoas reais, todas autorizadas pelo dono nesta sessão:

- **2 membros ghost ligados** à própria conta (`members.auth_id.manual_link`), com posse da caixa
  provada. Um terceiro **recusado**: e-mail batia, mas `email_confirmed_at` e `last_sign_in_at`
  eram nulos — ninguém jamais provou posse daquela caixa, e é o vetor do incidente do P168.
- **1 link de onboarding reemitido e ENTREGUE** (`delivered` em 7 s), para a candidatura
  `20305c65`, depois que o worker novo publicou. Token vivo até 28/09.

---

## 1. A lição que vale mais que as duas entregas

**Uma conclusão circulou invertida, e quase virou trabalho na direção errada.**

Um líder de tribo leu presença pelo MCP, viu gente que não esteve misturada com gente que esteve,
e o grupo concluiu *"dados e MCP certos, UI errada"*. A medição deu o inverso: a **UI estava
certa**, e a RPC do MCP afirmava `present: true` por literal.

Se alguém tivesse "consertado" a UI a partir daquela conclusão, teria quebrado a única superfície
que estava certa.

⚠️ **O que salvou foi exercer a própria ferramenta em vez de raciocinar sobre o relato.** Duas
chamadas: uma no MCP, uma no banco. A divergência apareceu em segundos.

---

## 2. Como o defeito da #2278 se escondeu por meses, e por que isso vai se repetir

`get_event_detail` montava `'present', true` como **literal**. A premissa — *"existir linha em
`attendance` = compareceu"* — era verdadeira quando ausência não era registrável.

O registro de ausência por mês:

| mês | ausências gravadas |
|---|---|
| 03–07/2026 | 3 a 38 |
| **08/2026** | **174** |
| **09/2026** | 81 |

A função sempre esteve errada. **Antes acertava por acidente, porque quase não havia ausência para
descartar.** Ela passou a mentir exatamente quando o dado melhorou.

Essa é a forma de defeito mais difícil de pegar por teste: o que fica verde enquanto a base é
pobre. Procure irmãos dela perguntando *"esta função assume que o dado ausente não existe?"*.

---

## 3. A fila, na ordem acordada com o dono

1. **Agendar `detect_unlinked_accounts`** (PR própria). ⚠️ **Lacuna conhecida da #2273:** a função
   foi criada e **não tem cron** — `SELECT * FROM cron.job WHERE command ILIKE '%detect_unlinked%'`
   volta vazio. Um detector sem agendamento não falha, apenas nunca roda. Decidido em PR separada
   porque o tema é a jornada de entrada, não a leitura de presença.
2. **#2279** — o smoke intermitente. Custou 3 execuções hoje e gera pressão por `--admin`.
3. **#2281** — o denominador de presença que ignora a data de entrada.
4. **#2282** — a varredura agêntica MCP × frontend (pedido do dono).
5. **#2275** e **#2277** — por último; reais, mas não afetam decisão sobre pessoas.

⚠️ A **#2282 pressupõe #2278 e #2281 fechadas**, senão a varredura redescobre o que já se sabe.

---

## 4. As issues abertas, em uma linha cada

- **#2275** — 2 fixtures de teste órfãs de 27/08 contam como membro real e contaminam qualquer
  contagem de "membro sem conta". Duas das "10 pessoas" da #2273 eram elas.
- **#2277** — bridge do Docker sem saída nesta máquina; deploy de EF só passa com `--use-api`
  (reconfirmado hoje com controle positivo e negativo).
- **#2279** — `smoke:routes` falha intermitente. A hipótese específica está na issue: o marcador
  `*-denied` é client-side e o script do `BaseLayout` falha ao resolver no workerd, com frequência
  que acompanha o desfecho (1 no run verde, 8 e 14 nos vermelhos).
- **#2281** — `_attendance_eligible_events` usa `cycles.cycle_start` e **nunca** a data de entrada
  da pessoa. 14 de 96 ativos entraram depois do início do ciclo (09/07), e há 7 gerais no ciclo.
- **#2282** — a varredura sistemática MCP × frontend, com o registro de qual é a canônica.
- **#2283** — `member_get` devolveu 0 engajamentos onde há 2. **Não confirmado na fonte**; a issue
  diz o que falta medir.

---

## 5. Armadilhas que esta sessão pagou, e que a próxima não precisa pagar

- **Exercer o caminho de sucesso em produção escreve nas tabelas LATERAIS.** A sonda ponta a ponta
  criou linha em `auth.users`, `campaign_recipients` e `campaign_sends`. Limpei a entidade e
  esqueci as laterais; horas depois o guard **#1437**, de outra onda, reprovou — e a linha era
  minha. Antes de exercer, liste os `INSERT` de toda a cadeia.
- **O guard estático casa o próprio comentário.** A camada que afirma a ausência de
  `'open-auth-modal'` reprovou o código correto, porque o arquivo cita a string para explicar por
  que ela não deve existir. Use `maskJsComments` / `maskLineComments` antes de medir.
- **`gh pr checks` não lista quem não reportou.** "Zero pendentes" pode ser ausência: cruze com
  `gh run list` filtrando pelo **SHA completo**.
- **Série que cai a zero ≠ mecanismo quebrado.** O `first_link` zerou em 29/08 e parecia regressão
  com data; o controle (elegíveis por semana: 27 elegíveis, 25 ligados) mostrou fila seca.

---

## 6. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh issue list --state open --limit 20
docker run --rm redis:7-alpine sh -c 'ping -c2 -W3 1.1.1.1 && echo OK'   # se falhar: --use-api
```

```sql
-- o detector existe mas tem quem o acione? (hoje: NAO)
SELECT jobid, schedule, jobname FROM cron.job WHERE command ILIKE '%detect_unlinked_accounts%';
SELECT public.detect_unlinked_accounts();

-- a #2278 continua consertada? (o corpo vivo nao pode voltar ao literal)
SELECT (prosrc ~ '''present'', true') AS voltou_o_literal,
       (prosrc ~ 'COALESCE\(a\.present, false\)') AS le_a_coluna
FROM pg_proc WHERE proname='get_event_detail' AND pronamespace='public'::regnamespace;

-- a #2281, para dimensionar antes de consertar
WITH c AS (SELECT cycle_start FROM cycles WHERE is_current LIMIT 1)
SELECT count(*) FILTER (WHERE m.created_at::date > (SELECT cycle_start FROM c)) AS entraram_depois,
       count(*) AS ativos
FROM members m WHERE m.is_active AND m.current_cycle_active;
```

---

## 7. Candidata a memória, não gravada por falta de espaço

`MEMORY.md` está no teto de 200 linhas e esta sessão já gravou três e arquivou três. Fica a
candidata, para quem tiver uma linha sobrando:

> **Função que assume que o dado ausente não existe fica correta enquanto a base é pobre, e passa a
> mentir quando o dado melhora.** `get_event_detail` afirmou presença por literal durante meses e
> acertava por acidente: só havia 3 a 38 ausências por mês. Em agosto foram 174, e ela começou a
> mentir em escala. Ao ler uma função antiga, pergunte o que ela assume sobre o que *ainda não era
> registrado* quando foi escrita.
