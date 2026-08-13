# PR #1673 - RESOLVIDO. Registro, não arranque.

> 🔴 **Este arquivo nasceu errado e está corrigido.** Foi escrito em 08/08 às 15h47 como
> um "prompt de arranque para a main lane fazer QA e mergear o #1673", **13 horas depois
> de o #1673 já ter sido mergeado**. A lane que o escreveu montou o texto sobre estado
> anterior a uma compactação de contexto e não remediu antes de publicar. O Vitor
> desconfiou na hora ("pois a main já pode ter feito") e a medição deu razão a ele.
>
> A lição está em `reference-git-status-snapshot-can-be-stale`, e esta é a versão cara
> dela: **um handoff é um deliverable, e um deliverable com estado velho manda alguém
> refazer trabalho que já está pronto.** Re-medir tem que ser o primeiro passo de escrever
> um handoff, não o último.

---

## O que aconteceu de fato

**PR #1673 mergeado em 2026-08-08T02:06Z**, commit `5e6e5703`. As duas playlists do Ciclo
4 estão em `origin/main`:

```
{ id: 'PLanpm8h-DzgQ', title: 'Ciclo 4 (2026/2) - Reuniões Gerais' },
{ id: 'PLfWCBF5VAWZM', title: 'Ciclo 4 (2026/2) - Reunião de Liderança' },
```

Com isso morreu o defeito vivo: os três dicionários já diziam "Reuniões Gerais - Ciclo 4"
e `getPlaylistUrl('generalMeetings')` resolvia para o Ciclo 3, porque a playlist do 4 não
existia no canal. O resolver `latestByPattern` agora cai no ciclo certo sozinho.

🟢 **A main lane usou merge, não rebase** (`b8421420`, "merge: main em 6481534c para
desfazer a condicao PROD-AHEAD do validate"), que era exatamente o caminho seguro: o
force-push está bloqueado pelo harness desta máquina.

O vermelho do `validate` era **PROD-AHEAD**, não do PR: prod tinha a migration
`20260807000600_1666_...` cujo arquivo só existia num branch não empurrado de outra
sessão, então `Phase C: body-hash drift` e `ADR-0097: missing-file drift` acusavam a
ausência do arquivo. Resolveu-se sozinho quando o #1666 chegou à main pelo `49a8586f`.

---

## O que continua valendo: o commit órfão

⚠️ **Ainda vivo.** O branch **local** `fix/youtube-playlists-ciclo4-gerais-e-lideranca`
carrega `08a17f2f` (#1666, 5 arquivos, 539 acréscimos) de outra sessão, nunca empurrado.
O remoto está limpo e o risco **não se materializou**: a main tem `AI_CONSENT_VERSION =
'v3'`.

### Ele é seguro de descartar, e foi medido

O #1666 já está na main pelo `49a8586f`:

| arquivo | veredito |
|---|---|
| `20260807000600_1666_...sql` | **idêntico** ao da main |
| `tests/contracts/1666-...test.mjs` | **idêntico** ao da main |
| `database.gen.ts` | as 3 linhas (`evidence`) já estão na main |
| `PMIOnboardingPortal.tsx` | todo o bloco já está na main, **exceto a versão** |
| `package.json` | o teste já está ligado no `npm test` (2 ocorrências) |

🔴 **A única divergência é uma regressão.** O órfão tem `AI_CONSENT_VERSION = 'v2'`; a
main tem **`'v3'`**. O órfão é a versão **mais velha**. Reaplicá-lo rebaixaria a versão do
consentimento de IA, que é o dano que o comentário do próprio arquivo descreve (LGPD art.
8º, §2º: o ônus da prova do consentimento é do controlador).

**Conclusão:** está integralmente superado. Limpeza, quando quem tocou o #1666 decidir:

```bash
git branch -f fix/youtube-playlists-ciclo4-gerais-e-lideranca \
  origin/fix/youtube-playlists-ciclo4-gerais-e-lideranca
```

---

## Residuais desta sessão

| item | situação |
|---|---|
| PR #1673 | ✅ mergeado |
| Worktree `wt-1673` | ✅ removida |
| **#1681** no painel de sessão | ✅ acrescentada |
| `08a17f2f` órfão no branch local | aberto, superado, decisão de quem tocou o #1666 |
| **#1637** Dependabot astro 6 -> 7 | **NÃO mergear**, política #611 |

### Fora do repositório, de dono humano

- **38 action items abertos** entre as Lideranças #8 (23/07) e #9 (06/08).
- **Webinar de patente e PI parado em 28/05/2026** com status `planned`, e **zero**
  webinares agendados em setembro.
- **Card do framework do Marcos** com `forecast_date` 08/09, três semanas depois do
  ~18/08 que ele se comprometeu em 23/07.
- **7 pessoas falaram na #8 sem registro de presença** (Vitor, Fabrício, Roberto,
  Adailson, Hayala, Sarah, Jefferson).
- Playlist `Ciclo 4 (2026/2) - Reuniões Gerais` existe, mas o backfill das Gerais
  **mais antigas** não foi varrido.

### Issues abertas nesta sessão

**#1672** (briefing conta 22 pendências e entrega 0) · **#1675** · **#1676** · **#1681**
(loop de retroalimentação do MCP, com captura do papel de quem faz o request).
**#1601** escalada por decisão do Vitor: não há rota de MCP para vincular gravação a
evento, e o custo está provado no log (ata pelo MCP com `actor_id` nominal, link por SQL
com `actor_id: null`).

Contexto completo na memória `handoff_2026_08_07_bloco_c_fechado_lideranca_8_e_9` e no
painel `docs/planning/2026-08-07_CONTROLE_SESSAO.md`.

⚠️ **Repositório é PÚBLICO.** Gravações, transcrições e mp4 editados ficam em
`~/Downloads/`. A ata retroativa da #8 nomeia voluntários com juízo de desempenho e não
foi commitada de propósito.
