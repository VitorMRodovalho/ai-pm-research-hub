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

> ✅ **RESOLVIDO no fim da sessão.** O dono habilitou a API e a chamada acima passou. Mas a promessa
> desta seção estava grande demais: veja a seção 14, onde duas das três métricas que eu disse que
> destravariam **não existem nesta API**.

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
| — | ~~habilitar YouTube Analytics API~~ | ✅ **feito pelo dono**, API respondendo (seção 14) |
| — | impressões e CTR do canal | **fora da Analytics API v2**; só Studio ou Reporting API em lote |
| — | ~~mover a pasta de backups para fora da mãe~~ | ✅ **feito e verificado** nos dois lados (seção 13) |
| — | cifrar os backups antes do upload | decidido, **não executado** (seção 13) |
| — | onde mora a CHAVE da cifra | **decisão nova, sem dono** (seção 13) |
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

---

> **Seções 13 e 14 foram acrescentadas depois do merge do handoff**, e cobrem o que aconteceu
> entre o fechamento e o fim da sessão.

## 13. Quase-incidente de PII num Drive compartilhado: a lista de permissões não é o efeito

> ⚠️ **Escrito sem identificadores de propósito.** Repositório público, e o achado descreve
> configuração de Drive de uma organização terceira. Sem e-mail de conta, sem ID de pasta, sem
> nomear a organização. Os identificadores estão na sessão par e devem ir para o tracker
> **privado**, que é onde referência nominal pode viver (norma de 2026-09-13).

Uma sessão par pediu confirmação de que uma pasta nova, criada dentro de uma pasta compartilhada
para receber backup de site **com PII de filiado**, estava restrita. A medição dela: a listagem de
permissões da pasta nova mostrava **só a conta dona**, nenhuma herança. Conclusão dela: restrita.

**A conclusão estava invertida, e a medição dela estava certa.** As duas coisas ao mesmo tempo.

### O que a sonda não-dona mostrou

Usei uma conta que **não é dona** da pasta nova e que tem acesso à pasta-mãe:

| sonda | resultado |
|---|---|
| lê a pasta-mãe (**controle positivo**) | sim, com carimbo de "compartilhada comigo" |
| lê a pasta nova | **sim** |
| `canAddChildren` na pasta nova | **`true`** — escrita, não só leitura |
| carimbo de "compartilhada comigo" na pasta nova | **ausente** |

O carimbo ausente é o ponto: a pasta nova nunca foi compartilhada com a sonda **diretamente**. O
acesso chega **pela mãe**. Isso é a herança, viva.

E a mãe carrega uma permissão de **domínio inteiro** com papel de leitor. Não é "algumas pessoas":
é todo mundo do domínio, herdando na pasta "restrita".

### A regra, que é o que sobrevive a este caso

**Em My Drive, `permissions.list` de um filho NÃO enumera o que ele herda do pai.** "Só o dono" na
lista é perfeitamente compatível com acesso total de todo mundo que tem a mãe. Quem lê a lista está
lendo uma **projeção**, e a projeção não responde à pergunta de efeito.

⇒ Para saber quem enxerga, **olhe com uma conta que não seja a dona, e leve um controle positivo**
(ela precisa enxergar algo que deveria enxergar, senão o "não vejo" é indistinguível de sonda sem
acesso nenhum).

**E não existe conserto por permissão:** My Drive não deixa um filho ser mais restrito que o pai.
Herança só adiciona acesso, nunca subtrai; não há revoke de acesso herdado. Enquanto a pasta estiver
dentro da mãe compartilhada, qualquer aperto aplicado nela é decorativo. Isso mata a classe inteira
de "crio uma subpasta restrita dentro da pasta compartilhada".

### Desfecho

**Não houve vazamento, e isso foi verificado, não suposto.** Consulta por filhos da pasta nova
devolveu vazio; a **mesma forma de consulta** na mãe devolveu 5 itens mais paginação, inclusive a
própria pasta nova. A consulta sabe devolver linha, logo o vazio é ausência real. A pasta foi criada
e nunca recebeu arquivo. O upload foi suspenso antes de subir.

**Decisão do dono, 2026-09-18:** tirar a pasta de dentro da mãe **e** cifrar os arquivos no cliente
antes do upload. As duas, não uma, por defesa em profundidade: se um dia alguém reexpuser a pasta, o
conteúdo ainda é texto cifrado, e a proteção deixa de depender de ninguém errar a ACL para sempre.
Descartadas explicitamente: "só sair da mãe", "Shared Drive novo" e "fora do Drive".

### ✅ Executado pela sessão par e VERIFICADO, ainda dentro da sessão

A pasta nova nasceu na raiz privada da conta de serviço, fora da mãe, e a antiga (vazia) foi
removida. Nada disso foi tocado por esta sessão: só medido.

| braço | resultado |
|---|---|
| sonda **não-dona** vê a pasta nova? | **não** (`not found`) |
| pasta antiga | **não** (`not found`) — sumiu |
| controle positivo A: listagem da mãe | 5 itens mais paginação |
| controle positivo B: `get_file_metadata` num filho conhecido da mãe | retornou o registro |

O controle B importa porque é **a mesma chamada** que devolveu `not found` nos dois primeiros
braços: o not-found é resposta, não ferramenta quebrada.

**O discriminador que caiu de graça, e que era a hipótese concorrente certa:** a listagem da mãe traz
uma pasta cujo dono é a **mesma conta de serviço** que criou a pasta nova, e a sonda **enxerga essa**.
Logo "a sonda não vê a pasta nova" não é "a sonda não vê pastas dessa conta". O que mudou é a
**posição**, não a titularidade.

Bônus de diferença simétrica: antes do move a pasta antiga era o 5º item da mãe; depois, o 5º item é
outra pasta. A remoção aparece como **mudança na mesma listagem**, não apenas como ausência.

**⚠️ E a ressalva que o braço negativo NÃO cobre, que quase passou:** uma conta não-dona não
distingue "privada" de "inexistente" — as duas devolvem `not found`. Se a criação tivesse falhado em
silêncio, a medição acima seria **idêntica**. A existência só se prova do lado do dono.

Fechada com **instrumento e credencial independentes**, a partir desta máquina e não repetindo a
medição da sessão par: `rclone lsjson` no remote da conta de serviço lista a pasta na raiz, com
`IsDir=true` e o ID batendo, entre 9 diretórios (controle positivo).

⇒ **dono vê (existe) + não-dono não vê (privada) = destino provado privado E real.** As duas metades
precisam existir; nenhuma sozinha decide.

**Decisão nova que esta abre e que ninguém pegou:** onde mora a chave da cifra. Chave junto do
backup anula a cifra.

## 14. ⚠️ A Analytics API foi habilitada, e a seção 9 prometeu mais do que ela entrega

O dono habilitou a API no fim da sessão e a chamada passou. Primeira medição viva do canal, 90 dias
(2026-06-20 → 2026-09-18): **2.151 views · 5.191 minutos · 231 s de duração média · 9,3% assistido
em média · 67 inscritos ganhos**.

**Mas duas das três métricas que a seção 9 prometia destravar não existem nesta API.**

`impressions` e `impressionClickThroughRate` retornam `Unknown identifier (impressions) given in
field parameters.metrics`. Não é escopo, não é permissão, não é propagação: **a Analytics API v2 não
tem essas métricas.** Elas só saem pelo YouTube Studio ou pela Reporting API em lote, que é outro
mecanismo, com outra autenticação e outro formato.

⇒ Destravou **retenção e fontes de tráfego**. **Impressões e CTR seguem fora**, por motivo
estrutural. Das três causas opostas que a seção 3 do handoff anterior queria separar ("o YouTube não
mostra" × "mostra e ninguém clica" × "clicam e abandonam"), a primeira e a segunda **continuam
indistinguíveis** por este caminho.

**Regra:** habilitar o acesso não cria a métrica. Antes de prometer que um portão destravado responde
uma pergunta, confira se a resposta existe no vocabulário da API, e não só se a porta abre.

### O que passou a ser mediável, e já contradiz o senso comum

Fontes de tráfego, 90 dias:

| fonte | views | minutos |
|---|---:|---:|
| feed de Shorts | 716 | **50** |
| link externo | 332 | **1.545** |
| inscritos | 198 | 876 |
| vídeo relacionado | 155 | 827 |
| busca do YouTube | 151 | 165 |

**Os Shorts trazem a maior fatia de views e a menor de minutos**: 716 views rendem 50 minutos,
contra 332 views de link externo rendendo 1.545. Isso sustenta, por caminho independente e agora com
medição direta, o que a seção 3 do handoff anterior tinha inferido por views/dia.
