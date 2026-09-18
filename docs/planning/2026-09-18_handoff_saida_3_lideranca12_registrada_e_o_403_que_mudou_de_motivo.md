# Handoff de saída 18/09 (3): a Liderança #12 está registrada, e o 403 do Analytics mudou de motivo

> **Nada aqui é medição viva.** Carimbado em 18/09 entre ~17h40 e ~19h20 UTC.
> **Re-meça antes de decidir.** Repositório público: este documento não nomeia terceiros.

**Estado ao encerrar:** `main de8ff0e2` · **0 PRs abertas** · **0 jobs de banco em voo** ·
zero vermelhos no SHA da `main` · deploy Cloudflare verde.

---

## 1. A Liderança #12 está registrada no evento

Aplicado no banco compartilhado com o portão aberto e re-medido por mim antes de escrever.

Alvo: `events.id = 47a8f557-2b45-4156-a02d-b9f1625fd8a1` (`Reunião de Liderança #12`, 2026-09-17).

```sql
UPDATE events
SET youtube_url    = 'https://youtu.be/JodNJgeltgw',
    recording_url  = 'https://youtu.be/JodNJgeltgw',
    recording_type = 'youtube'
WHERE id = '47a8f557-2b45-4156-a02d-b9f1625fd8a1';
```

Antes → depois, ambos de consulta viva, o depois lido com consulta **nova** e não pelo `RETURNING`:

| medida | antes | depois |
|---|---:|---:|
| liderança com `youtube_url` | 8 | **9** |
| liderança com `recording_url` | 8 | **9** |
| liderança com URL e `recording_type` nulo | 0 | **0** |
| eventos com `youtube_url` (todos os tipos) | 49 | **50** |
| linhas com esse link | 0 | **1** |
| total de eventos `type='lideranca'` | 24 | 24 |

`is_recorded` já era `true` e não foi tocado.

## 2. ⚠️ O `UPDATE` do handoff anterior estava incompleto

O handoff das 17h40 propunha o `UPDATE` **sem** `recording_type`. Medido antes de aplicar: entre as
24 reuniões de liderança, quantas têm URL e `recording_type` nulo são **0**. As sete de YouTube
carregam `'youtube'` e a oitava carrega `'google_drive'`. Aplicar como estava criaria a **primeira
exceção da série**, e ninguém reclamaria, porque nenhum guard olha essa coluna.

**Regra que isto instancia:** convenção com zero contra-exemplos é invariante de fato, mesmo sem
`CHECK` e sem guard. Antes de escrever numa tabela, conte as exceções da convenção; se o número for
zero, a coluna faz parte do contrato.

## 3. ⚠️ E o denominador que eu mesmo mediu primeiro estava errado

Recortei por título (`title ILIKE 'Reunião de Liderança #%'`) e achei **16 com 6**, e cheguei a
anunciar que o handoff anterior estava errado ao dizer 24 com 8. **O errado era o meu recorte.**

O recorte certo é `type = 'lideranca'`, que devolve os **24 com 8** do handoff. Os títulos variam
demais para servir de chave: há `Reuniao de Lideranca #1` sem acento, `Reunião Liderança C2 (01/Oct)`,
`[Núcleo IA] Reunião de Liderança — Bate-papo GP + Líderes (pré-Geral)` e um `Alinhamento Equipe de
Mídias` que também é `type='lideranca'`.

**Regra:** título é rótulo editável, tipo é chave. Divergiu do número de outra fonte? Antes de
corrigir a outra fonte, pergunte se o SEU predicado é o mesmo predicado.

Nota de esquema para a próxima sessão, porque custou duas consultas: a tabela usa **`type`** e
**`date`**, não `event_type` nem `start_time`.

## 4. Exposição do vídeo não listado: medida e descartada

A #12 está **não listada** no YouTube, e `src/components/sections/HeroSection.astro:258` consulta
`events` **sem filtrar por `type`** e renderiza um botão público de gravação. A pergunta era real.

Exercendo a RLS como `anon`, antes e depois da escrita, números idênticos:

| sonda | valor |
|---|---:|
| anon vê eventos (total) | 77 |
| anon vê eventos com `youtube_url` | 20 |
| anon vê `type='lideranca'` | **0** |
| anon vê linhas com o link novo | **0** |

Os 77 e os 20 são o **controle positivo**: a sonda sabe devolver linha, então o zero é ausência de
verdade e não instrumento quebrado. Gravar o link **não** publicou o vídeo.

`HomepageHero.astro:248` filtra `.eq('type','geral')` e nunca alcança liderança.

## 5. Formato do link: escolha mantida, com o número na mesa

Nenhum dos **55** pontos que leem `youtube_url` em `src/` e `supabase/functions/` extrai ID de vídeo;
todos usam o valor direto como `href`. O único que classifica (`src/components/board/CardDetail.tsx:247`)
aceita as duas formas. Então o formato não tem consumidor que se importe.

Registro para decisão futura: o dominante nos dados é o **longo** (`youtube.com/watch`, 7 de 8) e a
#12 entrou no **curto** (`youtu.be`), copiando a #10, que era a única curta. Nada quebra; é
cosmético e reversível.

## 6. Guards: nenhum, e o controle prova que a pergunta foi feita

```
tests/contracts/ que leem youtube_url    : 0
tests/contracts/ que leem recording_url  : 0
tests/contracts/ que leem recording_type : 0
tests/contracts/ que citam events        : 79   ← controle positivo
```

## 7. PR #2367 mergeada, e o `browser_guards` cobrou de novo

Mergeada por squash, sem `--admin`. `main` em `de8ff0e2`.

O `browser_guards` (required via ruleset `21186263`, junto com `deno`, `structural` e `validate`)
reprovou com a assinatura da #2343 e exigiu **3 execuções do job**:

| execução | tentativa interna | resultado | locator |
|---|---|---|---|
| 1 (`105703777011`) | 1/2, 2/2 | fail, fail | `#sel-panel`, `#sel-denied` |
| 2 (`105720691399`) | 1/2, 2/2 | fail, fail | `#tribe-denied`, `#sel-denied` |
| 3 (`105721897643`) | 1/2 | **pass** | — |

**5 tentativas internas, 4 falhas.** Assinatura idêntica nas quatro:
`workerd-nao-resolve-BaseLayout workerd-jsg-throw timeout-playwright`.

**O locator variou nas quatro, a raiz não.** Sintoma que passeia com causa parada é o contrário do
que um defeito de página produziria. Ocorrência registrada na #2343 com a tabela dos dois níveis.

Depois do merge a `main` também ficou vermelha pelo mesmo flake (job `105722622712`), com **0**
falhas fora da assinatura conhecida; passou na primeira re-execução.

## 8. O portão de DDL fez exatamente o que a CLAUDE.md prevê

Segundo depois do merge: **0 PRs abertas e 3 jobs de banco em voo** (`Schema Invariants`,
`DB Types Drift`, `CI Validate`), todos disparados pelo próprio merge que zerou a fila.

É o instante que a regra descreve, observado ao vivo. Esperei os três fecharem e **re-medi eu mesmo**
em vez de aceitar o código de saída do vigia, porque confirmação do executor não prova pós-condição.

Ordem que importou: apliquei o `UPDATE` **antes** de re-rodar o `browser_guards` da `main`, porque
re-rodar re-dispara o `CI Validate` e fecharia o portão de novo.

## 9. ⚠️ `auth_analytics`: o token saiu, e o 403 mudou de motivo

**Feito:** `token_analytics.json` existe, com os escopos certos, confirmados no próprio token:
`yt-analytics.readonly` + `youtube.readonly`. Conta: `nucleoia@pmigo.org.br`. Permissão do arquivo
ajustada para `600`, igual aos outros tokens. Canal confirmado pelo token de upload:
`Núcleo de Estudos e Pesquisa em IA e GP` (`UCIEiHte8f_AVwCXP2wZ7DjQ`).

O consentimento foi dado pelo navegador, com os dois escopos conferidos na tela antes do clique:
ambos de leitura, nenhum de escrita.

**E mesmo assim a Analytics API continua devolvendo 403. Mas é outro 403.**

| | antes (handoff 17h40) | agora |
|---|---|---|
| diagnóstico | "nenhum token tem `yt-analytics.readonly`" | escopo **resolvido** |
| razão do 403 | falta de escopo | **`accessNotConfigured`** |
| mensagem | — | "YouTube Analytics API has not been used in project 768053773084 before or it is disabled" |

**O escopo era metade do bloqueio.** A outra metade é a API não estar habilitada no projeto GCP
`768053773084` (`ai-pm-research-hub`).

**Regra:** registre o MODO da falha, não só a falha. Os dois são "403 na Analytics", e têm consertos
diferentes. Se eu tivesse parado no "403" teria concluído que o consentimento não funcionou.

**⚠️ Parede, e ela é sua:** habilitar a API exige o Cloud Console, e o console abre na conta padrão,
que **não tem acesso** ao projeto (falta `resourcemanager.projects.get`). Forçando `authuser=2`, a
conta do Núcleo cai em **desafio de senha**. Senha eu não digito.

**Próximo passo, e ele depende de você:** logar como `nucleoia@pmigo.org.br` e habilitar em

```
https://console.cloud.google.com/apis/api/youtubeanalytics.googleapis.com/overview?project=768053773084&authuser=2
```

Depois disso, o teste que reprova hoje e deve passar:

```bash
cd ~/projects/_pmo/youtube && ~/.venvs/youtube/bin/python -c "
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
c = Credentials.from_authorized_user_file('token_analytics.json')
print(build('youtubeAnalytics','v2',credentials=c).reports().query(
  ids='channel==MINE', startDate='2026-06-20', endDate='2026-09-18',
  metrics='views,estimatedMinutesWatched,averageViewPercentage').execute())"
```

Só depois disso as perguntas de impressões, CTR e retenção ficam mediáveis, e só então o SEO do
canal deixa de ser palpite.

## 10. ⚠️ Achado novo: `Knowledge Insights Auto Sync` está vermelho há semanas, em silêncio

Não fui procurar; apareceu na lista de runs da `main` e eu abri.

- **20 de 20** execuções recentes falharam. Todas `schedule`, nenhuma `push`.
- A mais antiga que olhei é de **31/08**; ou seja, pelo menos três semanas.
- Causa, do log: `{"success":false,"error":"Unauthorized"}` e `sync failed with HTTP 401`.

É credencial, não código: o workflow chama a Edge Function e leva 401.

**Por que passou despercebido:** é agendado, não bloqueia PR nenhuma, e um workflow agendado
vermelho não aparece em `gh pr checks`. O portão que ninguém consulta não avisa.

**Não abri issue** — fica a seu critério. As issues existentes de knowledge (#1751, #2261) tratam de
ingestão que grava zero linhas, que é sintoma vizinho mas não este: aqui a corrida nem chega a
gravar, morre no 401.

## 11. ABERTO

| # | o que | estado |
|---|---|---|
| — | habilitar YouTube Analytics API no projeto `768053773084` | **precisa de você** (login + console) |
| — | `Knowledge Insights Auto Sync` 401, 20/20 vermelho | achado novo, **sem issue** |
| — | 23 vídeos não listados ainda sem idioma declarado | fora do escopo autorizado |
| — | `upload.py` corrigido mas **não versionado** (`_pmo` ignora `youtube/*`) | só no disco |
| #2343 | `browser_guards` intermitente | ocorrência nova registrada |
| #2362 | `REVOKE` + guard derivado de `_test_*` | issue aberta, não aplicado |
| #2361 | 170 tools absorvidas mas registradas | issue aberta, sem dono |
| — | alertas do Dependabot | política #611: PR local de higiene |
| — | `MEMORY.md` no teto: **1 linha já foi cortada** no carregamento | precisa de poda |

## 12. Máquina

O aviso do handoff anterior sobre `nvidia-smi` (NVML 595.91 contra kernel 595.84, lido como "sem
GPU") **não foi re-medido nesta sessão**. Se houve reboot, re-meça antes de confiar nos dois
sentidos.
