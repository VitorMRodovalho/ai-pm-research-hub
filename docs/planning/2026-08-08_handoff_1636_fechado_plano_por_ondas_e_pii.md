# Handoff - 08/08 (noite): #1636 fechado, plano por ondas, e a PII do repo publico

> ⚠️ Este arquivo e PUBLICO. Nao descreve onde dado pessoal esta no historico - so classes e
> contagens. O detalhe do incidente vive na memoria da sessao, fora do repositorio.

`main` em **`6b33bd01`**. PR **#1692** aberto (branch `fix/pii-remocao-de-dado-pessoal-do-repo-publico`).

---

## O que fechou

| item | estado |
|---|---|
| **#1636** | **fechada** pelo PR #1690 (`9044dccf`, squash, 6/6 verde) |
| **#1691** | aberta - as outras 35 superficies de teste que escrevem em prod |
| **#1692** | PR de remocao de PII, aberto |
| **#1693** | politica de dado pessoal + guard + divida do historico |
| **#1694** | scrub de nomes, dimensionado |

### #1636: a torneira fechou, e esta medido

Antes: **5 linhas por rodada de CI** em `gate_attempts`, sobre **3 candidaturas reais**. Depois:
**0**, medido em duas rodadas independentes do codigo mergeado. Tambem 0 fixture sobrevivente, 0
membro sintetico, 0 token novo, 0 token orfao.

⚠️ O que da sentido a esse zero e o numero de **skips**: 6.593 testes, 6.592 pass, **1 skip**. Sem
credenciais seriam ~548 skips, e "0 linhas novas" ficaria indistinguivel de "o teste nao rodou".

---

## O plano por ondas

O backlog tem **195 issues abertas** e vinha sendo consumido por proximidade, nao por prioridade.
O plano vive em `~/.claude/plans/` (fora do repo). Resumo da ordem decidida pelo PM:

- **Onda 0** - triagem, agrupamento e PII *(a trilha da PII foi entregue nesta sessao)*
- **Onda 0.5** - superficie publica (README, blog, `frameworks`, `SITE_MAP`)
- **Onda 1** - presenca (epica #1652 + #1657 + #1660)
- **Onda 2** - ciclo seletivo · **Onda 3** - agenda · **Onda 4** - seguranca · **Onda 5** - MCP

Tres relogios correm: **20 candidaturas em voo** no funil, **65 eventos** nos proximos 30 dias, e
**48 de 89 membros** vendo percentual de presenca divergente hoje - levantado ao vivo por duas
lideres na Reuniao de Lideranca de 06/08.

### O achado que reordenou a Onda 1

A epica #1652 lista 4 filhas, mas **#1660 e a raiz e esta fora dela**:
`mark_member_present(p_present := false)` **APAGA a linha** desde 19/05. Medido: `attendance` tem
**2.028 linhas, 1.934 presencas e 3 faltas simples** na base inteira, com **1.723** (85%) sem
`marked_by`. A plataforma nao consegue expressar "faltou", entao toda metrica **infere** a falta da
ausencia de linha - que e o mecanismo do #1657 e a razao de existirem tres semanticas.

---

## A PII do repositorio publico

A regra ja estava no `CLAUDE.md` ("repo publico: nenhum candidato ou membro nomeado, so contagens")
e nao havia nada que a fizesse valer.

| classe | antes | depois |
|---|---|---|
| e-mails pessoais versionados | **342** ocorrencias, **89** enderecos, **52** arquivos | **0** |
| telefones reais | **52** ocorrencias | **0** |
| contato de seguranca | endereco pessoal no `SECURITY.md` | `vitor@vitormr.dev` |
| `supabase/.temp/` | 7 arquivos versionados apesar do `.gitignore` | desrastreados |

**82% estava em seed de migration**, nao em docs.

### Metodo, que e o que se leva daqui

**Ler `git ls-files`, nao o diretorio de trabalho.** O que importa e o que vai para o GitHub. Foi
essa escolha que achou o que toda varredura por `grep` pulava: `grep -I` ignora binario, e ha
documento com texto extraivel servido em `public/`.

**O guard e allow-list, nao deny-list.** Uma lista de dominios proibidos deixa passar o proximo
dominio que ninguem previu, e falha para o lado silencioso. Endereco novo custa uma linha de
decisao consciente.

**`.gitignore` nao desrastreia.** `supabase/.temp/` estava ignorado desde antes e mesmo assim com 7
arquivos versionados, porque a regra chegou depois dos arquivos.

**Nao nomear onde o dado esta enquanto o historico nao foi reescrito.** O primeiro commit deste PR
citava a origem, num repo publico. Republicado sem o ponteiro.

**O guard nao se enxerga enquanto esta untracked.** Ele varre `git ls-files`, e o arquivo dele so
entra ali depois do `git add`. Resultado: verde local, vermelho no CI, acusando as **proprias
fixtures** do controle positivo. A isencao do proprio arquivo e legitima, mas tem de ser
**estreita** - um teste irmao afirma que os enderecos la dentro sao exatamente as fixtures
declaradas, senao a isencao vira esconderijo.

### O gate vermelho era o mensageiro

O `Phase C` acusou drift porque **a migration E a captura** que ele compara com o corpo vivo, e o
scrub encurtou uma funcao em 6 bytes. Fui ver o que era: `notify_privacy_policy_change` dispara o
e-mail que avisa **todos os titulares** quando a politica de privacidade muda, e dizia "em caso de
duvidas, entre em contato com o DPO" apontando para um endereco **pessoal**. Medido: era a **unica**
funcao viva de `public` com dominio de e-mail pessoal, enquanto a pagina `/privacy` e os 3
dicionarios ja publicavam o DPO institucional. Duas superficies, dois canais, para a mesma pergunta.

Corrigido no arquivo **e em producao** (ritual GC-097 completo). Live: **0** funcoes com dominio
pessoal.

⚠️ Varredura que vale reter: `SELECT proname FROM pg_proc WHERE prosrc ~* '<padrao>'` alcanca o que
vive no banco e **nenhum grep no repositorio encontra**. Repo e banco derivam separado.

### A fronteira dos dois contatos

- **Dentro do site, o canal e o DPO** (`dpo@pmigo.org.br`): quem le e o titular exercendo direito da
  LGPD, e ele tem de achar o mesmo canal em qualquer superficie da plataforma.
- **No GitHub, o canal e o mantenedor** (`vitor@vitormr.dev`): contato de seguranca do repositorio
  e valvula de sandbox das Edge Functions, onde quem le e pesquisador de seguranca ou o operador.

---

## ⚠️ Pendente, e depende do mantenedor

1. **Reescrita de historico.** O PR #1692 limpa o HEAD; tudo segue nos commits antigos. Force-push
   e bloqueado pelo harness. A reescrita de 04/07 orfanou associacao commit-PR e gerou **69 falsos
   positivos** no audit semanal de bypass (#1142) - avisar o audit antes.
2. **Notificacao LGPD Art. 48.** Nao avaliada. A **#334** ja existe para essa cadeia e esta
   `status:blocked`. Envolve legal-counsel.

---

## Correcao registrada

O levantamento marcou o **"$0 monthly cost"** do README como falso. **Nao e.** O mantenedor absorve
o custo (licencas de LLM, APIs, Cloudflare, Supabase, tempo) e o PMI e os capitulos pagam zero; o
projeto ainda nao tem contribuicao de terceiros. O ajuste da Onda 0.5 passa a ser **explicitar de
quem e o zero**, nao corrigir o numero.

Segue valendo o resto da deriva do README (parado em 17/07): 52 vs **86** membros, 7 vs **12**
tribos, 209 vs **493** eventos, 5.306 vs **6.592** testes, 342 vs **395** registros de tool.

---

## Proximo

1. Mergear o **#1692** quando verde. Depois, commitar este handoff e o arranque, e **deployar as 3
   Edge Functions tocadas** (`send-allocation-notify`, `send-global-onboarding`,
   `send-tribe-broadcast` - a valvula de sandbox mudou de endereco). Nao deployar antes: deploy
   bundla a **arvore de trabalho**, nao o PR, e poria codigo de branch em producao.
2. Retomar a Onda 0: trilhas (a) estado e (b) agrupamento - a (c) esta entregue.
3. Onda 0.5 (superficie publica) e depois Onda 1 (presenca).
