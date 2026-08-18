# Handoff da noite de 18/08: a filiação abriu um veio, e seis issues saíram dele

> Sessão de 18:50 a 22:40 UTC. Todo número foi medido nesse intervalo. **Re-medir antes de usar.**
> Continua `docs/planning/2026-08-18_handoff_1844_1850_e_a_raiz_com_pavio.md` (tarde do mesmo dia).

## Estado

`main` em **`418b9d8d`**, **zero PRs abertas**. Bypass: **1 de 2** na janela.
**43 invariantes, 1 violação** — a do #1850, **aberta de propósito** (ver abaixo).

---

## Mergeadas

- **#1851** — conserto do CI (#1844). **11/11 verde, sem bypass.** E provou-se no ambiente que
  conserta: `validate` fechou em **12 minutos** contra as quatro travas de 95.
- **#1849** — arranque atualizado + handoff da tarde.

---

## 🔴 #1850: reparei 1, revertemos 1, e a lição é sobre PROCEDÊNCIA

### O que aconteceu, em ordem

1. Reparei o caso de procedência verificada (`GO` / `admin_import`). Mantido.
2. Reparei o segundo com `source = 'pmi_vep'`, a partir do `serviceHistoryChapters` do export.
   ⚖️ **O PM perguntou: "ela ser voluntária do PMI-DF não significa que é filiada. Está constando
   como filiada?"** Estava. E o rótulo `pmi_vep` é reservado ao que **o worker de sync** alimenta —
   eu escrevi à mão e assinei como se fosse ele.
3. Corrigi para `self_declared`. ⚖️ **O PM decidiu apagar**, e a decisão ficou mais certa depois:
   a função canônica **carimba `verified_at` em toda linha que escreve**. Não havia como registrar
   a alegação sem afirmar, no próprio dado, que alguém a verificou.

### 📌 As três lições, em ordem de utilidade

1. **Reconhecer a distinção no texto não impede de apagá-la no `INSERT`.** Eu já tinha escrito na
   issue que histórico de serviço ≠ *membership*, e mesmo assim escolhi `pmi_vep` na gravação. **O
   campo de procedência é onde a distinção precisa sobreviver.**
2. **Voluntariado num capítulo ≠ filiação a ele.** Relações diferentes, mesma sigla.
3. 🔴 **Eu não tinha achado o fluxo de verificação porque procurei a palavra errada.** Procurei
   tabela de *filiação* e parei em `member_chapter_affiliations`. **Existe
   `member_affiliation_verifications`** (#625 F1) — histórico append-only da **Diretoria de
   Filiação da sede**, 129 linhas, 63 membros, com RPCs próprias. **Nunca perguntei "quem valida
   isso hoje?".**

### O estado dos 3 casos

| caso | ação |
|---|---|
| capítulo verificado (`affiliation_unverified=false`) | ✅ reparado (`GO`/`admin_import`) |
| capítulo não verificado | ⛔ **revertido** — mantém o CI vermelho, com causa documentada |
| ainda `guest`, sem certificado | ⏸️ intocado |

🔴 **O vermelho de `U_active_person_has_primary_chapter_affiliation` NÃO é flake e NÃO é o #1844.**
Quem topar com ele deve resolver a filiação na fonte — **não reparar o dado para calar o check**.

### ⚠️ Correção de algo que eu repeti três vezes

Eu disse que havia um **"pavio aceso"**: alguém `guest` que faria o invariante acender ao assinar o
termo. **Não existe.** Ao medir com `is_active` e capítulo, os candidatos ao pavio são inativos ou
têm capítulo `Outro` (que o invariante exclui por desenho). Quando afirmei o risco, filtrei só por
papel e **não filtrei por atividade nem por capítulo**.

**A exposição real é uma pessoa, conhecida.** Nada armado esperando detonar.

---

## As seis issues novas

| # | o que | por que importa |
|---|---|---|
| **#1852** | filiação do VEP **parada há 4 meses** (434 linhas, todas de 01/04 a 21/04) | quem entrou depois de abril **nunca teve** filiação — buraco de coorte, não de pessoa |
| **#1854** | **2 filiações vencidas**, **6 vencem em 31/08**, 2 em 30/09 | as 63 verificações dizem `membership_active = true` porque o campo guarda o dia da verificação; **o vencimento envelhece sozinho** |
| **#1855** | o radar F3 **alcança 5 de 16** | avisa D-30 e D-7 e **nunca depois** (`days_until_expiry` negativo não casa em faixa nenhuma); e ignora quem **nunca** foi verificado |
| **#1856** | link de WhatsApp com `/\\D/g` + tela que só deixa **preencher** | o regex casa "barra invertida seguida de D"; e os inputs só renderizam com o campo **vazio** |
| **#1857** | **34 telefones e 12 LinkedIns** já estão no texto do CV | a extração roda e guarda; **ninguém colhe** |
| **#1858** | `card_write` pede aprovação em **toda** ação | anotação é por **ferramenta**, destrutividade é por **ação** |

### Detalhes que valem mais que a linha da tabela

**#1855 — o radar existe, roda todo dia e está em dry-run.**
`v4-affiliation-expiry-notify`, `0 9 * * *`, `active = true`, sempre `p_dry_run := true`. O texto da
notificação **já está escrito** e já cita o Termo, `pmi.org` e opt-out. **Não é caso de criar
campanha — é tirar o freio.** Mas ligar sem fechar a faixa de já-vencidos **institucionaliza o
abandono**: avisa duas vezes e esquece quem não respondeu.
⚖️ Trava uma decisão: **o que "vencida" implica?** Aviso, restrição, ou nada além do lembrete?

**#1857 — a hipótese do PM sobre o cabeçalho foi descartada, e a real é melhor.**
A extração **não pula o topo** (`unpdf`, corte em 50k a partir do início). Ela simplesmente **não
procura nada**: zero referências a telefone ou LinkedIn no código.
🔴 **E o PM apontou o caso que teria passado batido:** quando a URL está num **hiperlink** sobre a
palavra "LinkedIn", ela mora numa anotação `/Link` do PDF e **texto puro não a vê**. Medido:
**4 de 47** têm a palavra sem a URL. **Ausência por limitação da ferramenta ficaria indistinguível
de ausência real** — a forma de erro mais cara deste repositório.

**#1856 — o servidor nunca foi o limitante.**
`update_application_contact` usa `COALESCE(NULLIF(p_phone,''), phone)`: **sobrescreve**. A RPC
sempre soube corrigir; a tela é que só oferece o campo quando está vazio. **O gate ficou no lugar
errado** — virou "quando o campo aparece" em vez de "quem pode escrever".
⚖️ Pendente: hoje **observador não escreve** (decisão de 18/08). Se a correção de contato deve valer
para **todo** o comitê, é uma linha — mas é reversão consciente.

---

## A entrevista de hoje

**Dayane Guimarães · Pesquisadora · 18/08 20:00 BRT · entrevistador Fernando Maquiaveli.**

✅ **Briefing gravado** (2.726 chars) via `interview_manage action='set_notes'`. A ficha dela é
curta — motivação em uma frase, disponibilidade só "Sim.", sem tema proposto nem liderança —, então
o briefing diz isso com todas as letras e amarra perguntas a **cada critério da régua**, citando as
faixas. **Comunicação vale 40 dos 130** (31%), e o papel é de Redação Técnica.

📌 **Confirmado por impersonação:** o Fernando alcança `get_evaluation_form(interview)` pelo MCP, e
recebe `criteria_with_weights`, `max_weighted_subtotal`, `pert_cutoff` e a candidatura. **Ele tem a
régua e o teto.**

⏳ **Falta marcar o desfecho** com `interview_manage action='mark'`. A próxima é **19/08 21:30 UTC**.

---

## Próxima sessão

1. 🔴 **Marcar o desfecho da entrevista de 18/08**, e a de **19/08 21:30 UTC**.
2. ⚖️ **#1855: decidir o que "vencida" implica**, e então tirar o `dry_run` **junto** com a faixa de
   vencidos. **6 pessoas vencem em 31/08** — 13 dias.
3. ⚖️ **#1850: submeter à verificação** quem está sem — a saída é a Diretoria, não escrita manual.
4. **#1856** é o conserto mais barato do lote: um caractere em dois lugares, mais renderizar o input
   sempre.
5. **#1858: reproduzir antes de consertar.** A mensagem é do cliente, não do servidor.
6. Segue: **#1710 re-medir em 23/08** (prazo 24/08), funil (28/08), **#588 `[LL]` parado há 70
   dias**, **#92** (118 dias, raiz da #1614).

## Achados sem issue

- `mark` carimba `conducted_at` com a hora do **registro** (16 de 99 divergem, máx. 64 dias).
- O envelope do `mark` relata `application_status` que **não gravou**.
- **`upsert_chapter_affiliation` não audita**, sendo a única porta de escrita da tabela que ancora o
  capítulo.
- **Duas convenções de código de capítulo em três tabelas** (`GO`/`DF` no registro e nas afiliações,
  `PMI-DF`/`Outro` em `members.chapter`) — foi isso que fez minha reconstrução do predicado devolver
  zero e quase declarar a violação fantasma.
- **25 de 86** ativos não-`guest` **nunca foram verificados**; 107 têm filiação, 63 têm verificação.
