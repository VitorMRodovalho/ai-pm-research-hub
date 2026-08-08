# Prompt de arranque - MAIN LANE - QA e merge do PR #1673

> Escrito pela lane do Bloco C em 07/08/2026, com tudo re-medido no momento da escrita.
> Números datados; **re-medir antes de agir** (regra de grounding do `CLAUDE.md`).

---

## O pedido

Fazer QA e mergear o **PR #1673**, que está pronto e desbloqueado, tomando o cuidado
descrito na seção "O risco" abaixo. Depois, decidir sobre os residuais da seção final.

---

## 1. O que o PR #1673 faz

**Um arquivo, `src/data/youtube-playlists.ts`.** Acrescenta duas playlists ao bloco
`GENERATED` e uma nota no cabeçalho.

Corrige um defeito **vivo em produção**: os três dicionários de i18n já diziam
"Reuniões Gerais - Ciclo 4", mas `getPlaylistUrl('generalMeetings')` resolvia para a
playlist do **Ciclo 3**, porque a do Ciclo 4 não existia no canal. Ela foi criada nesta
sessão (`PLanpm8h-DzgQ`, pública), junto com a de Liderança (`PLfWCBF5VAWZM`, não
listada). O resolver `latestByPattern` passa a cair no ciclo certo sozinho.

A nota do cabeçalho registra que **id curto não é id truncado**: playlists criadas de
07/2026 em diante recebem id de 13 caracteres, as antigas têm 34. Confirmado criando uma
pela API e lendo de volta. Estava listado como suspeita no arranque anterior; foi
resolvido, e a nota existe para ninguém "consertar" isso depois.

---

## 2. O risco (leia antes de tocar no branch)

O branch `fix/youtube-playlists-ciclo4-gerais-e-lideranca` tem **duas pontas diferentes**:

```
remoto (origin/...)  ->  55bb9265   1 commit, 1 arquivo. É o que o PR #1673 mostra. LIMPO.
local  (.git local)  ->  08a17f2f   commit EXTRA por cima, de outra sessão, nunca empurrado.
                         55bb9265
```

O `08a17f2f` é trabalho do **#1666** (5 arquivos, 539 acréscimos) que outra sessão deixou
no branch errado. **Se alguém empurrar o branch local, esses 539 acréscimos entram no PR
#1673.**

### Ele é seguro de descartar, e foi medido

O #1666 **já está na main** pelo commit `49a8586f`. Comparando arquivo a arquivo:

| arquivo | veredito |
|---|---|
| `20260807000600_1666_...sql` | **idêntico** ao da main |
| `tests/contracts/1666-...test.mjs` | **idêntico** ao da main |
| `database.gen.ts` | as 3 linhas (`evidence`) já estão na main |
| `PMIOnboardingPortal.tsx` | todo o bloco já está na main, **exceto a versão** |
| `package.json` | o teste já está ligado na main (2 ocorrências, regra do `npm test`) |

🔴 **A única divergência é uma regressão.** O órfão tem `AI_CONSENT_VERSION = 'v2'`; a
main tem **`'v3'`**. O órfão é a versão **mais velha**. Reaplicá-lo rebaixaria a versão
do consentimento de IA, que é exatamente o dano que o comentário do próprio arquivo
descreve (LGPD art. 8º, §2º: o ônus da prova do consentimento é do controlador).

**Conclusão:** o `08a17f2f` está integralmente superado. Descartá-lo não perde nada.
A lane do Bloco C não o apagou porque apagar trabalho de outra sessão não é decisão dela.

### O caminho seguro

Trabalhe a partir do **remoto**, nunca do branch local:

```bash
git fetch origin
git log --oneline origin/main..origin/fix/youtube-playlists-ciclo4-gerais-e-lideranca
# deve imprimir EXATAMENTE uma linha: 55bb9265. Se imprimir duas, pare.
```

Para atualizar o PR, **merge, não rebase**: force-push está bloqueado pelo harness desta
máquina, e um rebase exigiria force-push.

Se e quando quiser limpar o branch local (decisão sua, não da lane do Bloco C):

```bash
git branch -f fix/youtube-playlists-ciclo4-gerais-e-lideranca origin/fix/youtube-playlists-ciclo4-gerais-e-lideranca
```

---

## 3. Por que o CI está vermelho, e por que já não deveria estar

O `validate` do #1673 falhou em **2 de 6.483** testes:

- `Phase C: body-hash drift`
- `ADR-0097: missing-file drift`

**A causa não é do PR.** Provado na hora: a main em `6221e990` passou verde às 20:38, e
prod tinha a migration `20260807000600_1666_...` cujo arquivo só existia num branch não
empurrado de outra sessão. Os dois gates comparam prod contra os arquivos do repositório,
então acusavam a ausência do arquivo, não o conteúdo do #1673.

**Isso acabou.** O arquivo chegou à main pelo `49a8586f`. Confirmado:

```bash
git cat-file -e origin/main:supabase/migrations/20260807000600_1666_consentimento_de_ia_vira_registro_auditavel.sql
```

Basta o CI rodar de novo sobre a base atual. Um merge de `origin/main` no branch remoto
dispara isso.

⚠️ O PR **#1674** foi **fechado sem merge**, mas o conteúdo entrou por outro caminho. Não
conclua pelo estado do #1674 que o #1666 não subiu.

---

## 4. QA sugerido

O commit é de um arquivo só e de dado, não de lógica. O que vale conferir:

```bash
npx astro build                                   # tem que passar
npm test                                          # exportar o .env antes, senão 548 testes PULAM calado
node --test tests/contracts/youtube-playlists-ssot.test.mjs   # 4/4 na lane
```

⚠️ `npm test` sem `.env` exportado pula centenas de testes **sem falhar**. Conferir o
número de skips, não só o "0 failures"
(memória `reference-npm-test-needs-env-exported-or-548-skip`).

Verificação funcional, se quiser ir além do gate: o rodapé e a `TribesSection` resolvem
por `getPlaylistUrl(key)`, então o link de "Reuniões Gerais" deve passar a apontar para
`PLanpm8h-DzgQ`. Em produção, **furar o cache de borda** para ver o efeito.

Estado no momento da escrita: `origin/main` em `6481534c`; #1673 `OPEN`, `mergeable
UNKNOWN`, `validate FAILURE` (execução antiga). Havia 12 PRs abertos.

---

## 5. Residuais que sobraram desta sessão

Nenhum bloqueia o merge.

| item | situação |
|---|---|
| `08a17f2f` órfão no branch local | medido acima, superado, decisão de quem tocou o #1666 |
| Painel `2026-08-07_CONTROLE_SESSAO.md` não cita a **#1681** | uma linha na tabela de issues |
| Worktree `wt-1673` | **já removida** pela lane do Bloco C |
| PR **#1647** (Paulo) segue aberto | as 5 falhas do `validate` foram provadas pré-existentes; é decisão da main lane |
| **#1637** Dependabot astro 6 -> 7 | **NÃO mergear**, política #611 |

### Fora do repositório, e de dono humano

- **38 action items abertos** entre as Lideranças #8 (23/07) e #9 (06/08).
- **Webinar de patente e PI parado em 28/05/2026** com status `planned`, e **zero**
  webinares agendados em setembro.
- **Card do framework do Marcos** com `forecast_date` 08/09, três semanas depois do
  ~18/08 que ele se comprometeu em 23/07.
- **7 pessoas falaram na #8 sem registro de presença** (Vitor, Fabrício, Roberto,
  Adailson, Hayala, Sarah, Jefferson).
- Playlist `Ciclo 4 (2026/2) - Reuniões Gerais` existe, mas o backfill das Gerais
  **mais antigas** não foi varrido.

### Issues abertas nesta sessão, todas com medição fresca

**#1672** (briefing conta 22 pendências e entrega 0) · **#1675** · **#1676** ·
**#1681** (loop de retroalimentação do MCP, com captura do papel de quem faz o request).
**#1601** foi escalada por decisão do Vitor: não há rota de MCP para vincular gravação a
evento, e o custo está provado no log (ata pelo MCP com `actor_id` nominal, link por SQL
com `actor_id: null`).

---

## Contexto que a main lane talvez não tenha

O Bloco C fechou e se ampliou: as Lideranças **#9 e #8** foram publicadas, vinculadas e
com ata mais 41 action items. A **#8, de 23/07, estava abandonada havia 15 dias**, sem
ata, sem link e com zero ações. Detalhe completo na memória
`handoff_2026_08_07_bloco_c_fechado_lideranca_8_e_9` e no painel
`docs/planning/2026-08-07_CONTROLE_SESSAO.md`.

⚠️ **Repositório é PÚBLICO.** Gravações, transcrições e mp4 editados ficam em
`~/Downloads/`. A ata retroativa da #8 nomeia voluntários com juízo de desempenho e não
foi commitada de propósito.
