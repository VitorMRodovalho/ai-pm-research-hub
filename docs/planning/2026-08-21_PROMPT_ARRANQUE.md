# Arranque de 21/08 — fila livre, e um relógio que dispara sábado

> Tudo aqui foi medido ao vivo em **20/08/2026** (horários em UTC). **Re-medir antes de agir**:
> número recitado de handoff não vale como medição.
> Sem nome e sem identificador de candidato: este repositório é público.

---

## 1. Estado

### 🔴 PRIMEIRO: a fila está CONGELADA por quebra externa do npm

O check **`deno` é required** (os três são `validate`, `browser_guards`, `deno` — confirmado via
API de proteção em 20/08). Ele passou a falhar em **20/08, entre 04:51 e 18:26**, com:

```
error: Could not find npm package '@bruits/satteri-darwin-arm64' matching '0.10.4'
```

**Não é do repositório.** Medido: o pacote é **transitivo**, é específico de `darwin-arm64` (e o
runner é Linux), o `package-lock.json` fixa **0.9.5**, e no registro do npm o `latest` desse pacote
hoje é **0.10.5** — a 0.10.4 não resolve. A PR em que apareceu tem diff de um `.md` e um teste.

**Consequência: nenhuma PR merga até isso ser resolvido.** A **#1894** (este próprio documento)
está aberta e bloqueada por isso, com `validate` VERDE.

Caminhos a investigar, em ordem: (a) o resolvedor do `deno check` não está honrando o lockfile —
descobrir de onde sai a faixa que permite `0.10.x` quando `@astrojs/markdown-satteri` pede
`satteri: ^0.9.1`; (b) fixar/limpar cache do Deno no workflow; (c) esperar o upstream republicar.
**Não** trate como flake: duas execuções seguidas falharam igual.

---

**Fila de PRs:** vazia antes disso; agora **1 aberta e bloqueada** (#1894). `main` em `0416fcce`. **Zero bypass** consumido em toda a sessão de 19-20/08.

Mergeadas na sessão: **#1879** (auditoria da jornada), **#1883** (trigger de XP), **#1890** (o #1887),
**#1893** (isenção do #1636), **#1892** (docs da lane).

`check_schema_invariants()` devolveu **0 violações** às 13:51, depois do import do VEP.

---

## 2. O que tem data (por urgência)

### 🔴 Sábado 22/08, 15:00 UTC (12:00 BRT) — dispara sozinho

O cron `selection-stuck-scheduled-rescue-daily` (15:00 UTC diário, ativo) alcança pela primeira vez
a entrevista de **19/08 21:30 UTC** que ficou sem desfecho. A conta: carência de 48h
(`sla_policies.stuck_scheduled_grace`) vence 21/08 21:30, e a primeira execução posterior é a de
sábado.

**Se ninguém carregar as notas até lá, a plataforma dispara um convite de agendamento NOVO para
quem já foi entrevistada.**

Não precisa de intervenção manual: `submit_interview_scores` carimba `conducted_at` e marca
`completed` assim que **qualquer** entrevistador submete notas (WATCH-240.A / p241) — a ação do
entrevistador desarma o cron sozinha. Em 20/08 18:22 ainda estava tudo zerado.

### 🔴 24/08 — #1710, o único irreversível

Config conferida ao vivo em 20/08 12:20: `platform_settings.attendance.seal_window` =
`{floor_date: 2026-08-24, grace_days: 14}`. Cron `attendance-seal-window-daily` ativo.

**Re-medir em 23/08.** Os números de 15/08 (43 selam, 80 faltas, 40 pessoas) são **teto**, não
medição atual. `preview_seal_attendance` recusa `service_role` — use a porta MCP ou o predicado
replicado, com `America/Sao_Paulo`.

### ⏳ Sem relógio, mas envelhecendo

Duas candidaturas do ciclo aberto estão com **zero avaliações de qualquer tipo** desde 17/08: uma
em `interview_pending` (travada, não pode ser convidada) e uma em `submitted`. Todo o resto do
funil ativo tem 2 ou mais.

---

## 3. Decisões do PM nesta sessão — não re-litigar

1. **Convidar para entrevista sem o peer review completo está DESCONTINUADO.** Foi feito em julho
   sob pressão de kickoff e pedido de patrocinador; o PM classificou a repetição de 19/08 como
   **erro**. Quando o gate barrar, o desfecho é conseguir as avaliações, não contornar.
2. **Quatro certificados `alumni_recognition` de membros inativos foram REVOGADOS** (decisão de
   mérito do PM, não de cadastro), com `revoked_by` explícito e auditoria. Fila de contra-assinatura
   zerada.

---

## 4. Aberto, sem dono

- **#1888** — a fila de contra-assinatura só tem desfecho positivo (falta a porta de **recusar**,
  com motivo e autoria) **e** esconde certificado de outro capítulo de quem não tem `manage_member`.
- **5 linhas fantasma** no ciclo 3 (fechado): candidaturas de líder carregando o
  `vep_application_id` da candidatura de pesquisador da mesma pessoa. **Observado**, não inferido:
  um import completo do VEP passou por cima em 20/08 e não as viu (`vep_last_seen_at` segue nulo
  nas 5, enquanto as gêmeas foram tocadas às 13:49). Inflam a contagem de líderes daquele ciclo.
  Sem issue.
- **Gargalo do comitê:** quatro pessoas cadastradas como `evaluator`/`lead`, e **duas** fizeram
  298 das 299 avaliações objetivas. Uma fez 1 (em abril), outra **nunca** avaliou. Não é falta de
  cadastro, é falta de exercício. Sem issue.
- Itens da lane #1877 (documento de entrega): 4 ferramentas MCP que falham desde maio/julho
  (`update_checklist_item` 9/9, `delete_checklist_item` 4/4, `get_selection_health` 3/3 com erro de
  SQL vivo), **169 MB** de log sem política de retenção (`admin_audit_log` 137 MB, `pii_access_log`
  12 MB ⚠️), e 273 FKs sem índice.
- **#1664**, **#1728**, **#1729**, **#1742**, **#1744**, **#1592**, **#1205**, **#1842**, **#1844**,
  **#1850** (violação aberta de propósito, vence 30/09), **#1876**, **#1877** (épica), **#1880**,
  **#1881**, **#1882**, **#1884**, **#1885**, **#1886**.

---

## 5. Armadilhas MEDIDAS nesta sessão (custaram tempo real)

**A CI tem duas armadilhas que se combinam.** (a) `wait-for-db-lane` (#1509) falha *fail-closed*
quando não consegue ler a fila na API do GitHub — atualizar duas branches no mesmo segundo faz as
duas disputarem a faixa e caírem juntas. **Escalone.** (b) `cancel-in-progress: false` faz um push
durante um run criar um segundo run `pending` que **não despacha** até o primeiro terminar —
cancele o obsoleto, senão a espera é indefinida.

**`CREATE OR REPLACE` recusa se você omitir o DEFAULT do parâmetro** (42P13). E
`pg_get_function_identity_arguments()` **não mostra defaults** — leia `pg_get_function_arguments()`.

**Mensagem de falha de guard nomeia a HIPÓTESE do autor, não o diagnóstico.** O guard do #1636
acusa "algum teste escolheu alvo por predicado"; a causa real eram chamadas manuais. O experimento
decisivo e barato é **re-rodar a suíte inteira e ver se o contador anda**.

**Uma CTE que escreve não enxerga a própria escrita no mesmo statement.** Contar "quantos restam"
na mesma query do `UPDATE` devolve o snapshot anterior e parece que o conserto falhou.

**O `apply_migration` cria a linha de rastreio com timestamp PRÓPRIO.** Renomeie o arquivo local
para o timestamp da fantasma — foi assim que o #1883 e o #1890 fecharam.

---

## 6. Import do VEP — o padrão que funcionou

Rodado pela interface em 20/08 13:48-13:49. **167 candidaturas tocadas, nenhuma linha nova criada**
(preencheu o `vep_application_id` de uma linha existente em vez de duplicar), **0 violações** de
invariante depois. Total permaneceu em 173.

Rodar `check_schema_invariants()` **depois de todo import** continua sendo a regra (#1834), e desta
vez ela passou limpa.
