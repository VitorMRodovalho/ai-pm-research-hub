# Handoff: a jornada de entrada abre, e não fecha

> **Nada aqui é medição.** Carimbado em 14/09, ~07h BRT. **Re-meça antes de decidir** — os comandos
> estão na seção 8. Repositório público: este documento não nomeia ninguém, por norma. O caso vive
> sob o identificador opaco `c9c2058d` (candidatura).

**Estado ao encerrar, para COMPARAR:** `main 38de17ed` · **PR #2270 aberta** (validate verde,
`browser_guards` re-rodando) · issues novas do arco: **#2273**.

---

## 0. A missão da próxima sessão

**Fechar a jornada de entrada ponta a ponta: de "aprovado" até "dentro da plataforma", sem muro no
meio.** Escopo formal em **#2273**. Isto não é uma correção de tela — é decidir qual das duas
jornadas de entrada é a canônica, porque hoje existem duas e elas não se tocam.

O pedido do dono foi explícito: **definitivo**, não remendo.

---

## 1. O caso que forçou o tema, e o que já foi feito por ele

Uma pessoa aprovada em **14/08** como Líder de Tribo nunca conseguiu entrar. Em **13/09** ela voltou
à caixa de entrada de **julho** e clicou num link que morreu em 27/07. Esse clique é o dado mais
forte do arco inteiro: ela está tentando, e a plataforma não tem por onde recebê-la.

Feito, tudo com medição antes e depois:

| quando | o quê |
|---|---|
| 12/09 16:47 | e-mail primário do MEMBRO trocado para o endereço que entrega |
| 12/09 18:50 | reenvio do "aprovado" — `email.delivered`, o primeiro desde 05/08 |
| 14/09 03:34 | **e-mail da CANDIDATURA** corrigido (a troca de 12/09 não o alcançava) |
| 14/09 03:34 | link reemitido pela ação nova do MCP — `email.delivered` em **3 segundos** |

O token está vivo até **28/09**, `access_count` **0**. Ele ainda não abriu.

⚠️ **O dry-run pegou o defeito antes do envio.** A primeira prévia mostrou o endereço ANTIGO como
destinatário, porque a RPC lê `selection_applications.email` e a correção de 12/09 tinha sido feita
em `member_emails`. Sem a prévia consultando o estado real, o link teria ido para um endereço
suprimido. **Esse é o argumento inteiro a favor do dry-run que consulta o banco, contra o preview
sintético do ADR-0018** — está escrito no código da ação.

---

## 2. O que está MEDIDO e não se re-investiga

Cada linha abaixo saiu de consulta viva ao corpo da função ou ao componente, não da spec.

- **`consume_onboarding_token` NÃO filtra por status.** Exige só `expires_at > now()` e
  `source_type = 'pmi_application'`. O risco óbvio de alargar o emissor para `approved` e esquecer o
  consumidor **não existe**. Não gaste sessão nisso.
- **A entrega não é o gargalo.** O reenvio foi `sent` → `delivered` em 3 s.
- **A lista de passos renderiza.** A seção é guardada por `totalCount > 0`, e o caso tem **11**
  linhas de progresso — o tamanho exato do catálogo `onboarding_steps`.
- **O JSONB por ciclo está em 0, e nunca teve os passos do catálogo.** A #2245 filtrou pelo catálogo
  e sobrou vazio porque só continha as 5 chaves órfãs. Não é regressão da #2245.
- **O portal não cria conta.** Nenhum `signUp` nem `signInWithOtp` no componente.
- **As duas jornadas não se tocam.** `grep '/claim'` nas superfícies do portal e do `/onboarding`
  volta **vazio**.
- **56 de 66** membros criados em 150 dias **têm conta**. A jornada não está quebrada; o que
  falha é uma borda de **10 pessoas**. Ver 5b.
- **Não é origem VEP.** VEP: 53 de 57 com conta (93%). Não-VEP: 3 de 9 (33%). A origem explica o
  oposto da hipótese.
- **`request_account_claim` exige `auth.uid()`.** Primeira linha do corpo:
  `IF v_uid IS NULL THEN RETURN 'not_authenticated'`. Ele é o plano B de quem **já entrou** e não foi
  reconhecido. Não é porta de entrada.

---

## 3. Os dois defeitos, em #2273

**A — o passo aparece com a chave crua.** `PMIOnboardingPortal.tsx` faz
`const label = def?.label ?? step.step_key`, e `def` vem do JSONB por ciclo, que está vazio. A pessoa
lê `complete_profile`, `volunteer_term`, `first_meeting`. Os rótulos existem, nas 11 linhas da tabela
`onboarding_steps`. O leitor pergunta à fonte errada.

*Conserto:* `consume_onboarding_token` devolver as definições do **catálogo**, não o JSONB.

*Prova:* injete o defeito. Catálogo vazio → o teste tem de REPROVAR. JSONB vazio com catálogo cheio →
tem de passar. Um teste que só afirma "tem rótulo" fica verde pelo fallback e não discrimina nada.

**B — para `approved`, a única ação à frente é um botão para `/onboarding`, que fica atrás de login.**
A pessoa percorre: e-mail → portal → botão → muro → e-mail. É o mesmo muro do e-mail de 12/09.

*Conserto proposto:* no ramo `isApproved`, quando não há membro com `auth_id`, oferecer a criação de
acesso no próprio portal. O token já carrega identidade verificada; o portal é o único ponto da
jornada onde ela está provada e ainda não virou conta.

---

## 4. A armadilha que decide o desenho

**O reconhecimento liga conta nova a membro pelo e-mail PRIMÁRIO do membro.** Se o acesso for criado
com outro endereço, a pessoa entra como **ghost** — some do próprio registro, e o suporte vira
arqueologia.

E os dois endereços divergem por caminhos diferentes: o da CANDIDATURA envelhece sozinho (foi o que
aconteceu aqui), o do MEMBRO é o que o login consulta. Qualquer fluxo de criação de conta tem de ler
**o primário do membro**, nunca o e-mail da candidatura.

---

## 5. A pergunta de arquitetura, que ninguém respondeu ainda

> ⚠️ **Leia a 5b antes de agir sobre esta seção.** A premissa abaixo — "ninguém cria conta" —
> foi **desmentida por medição** na mesma sessão. A seção fica de pé porque o mapa das duas jornadas
> continua correto; o que caiu foi a conclusão que eu tirei dele.

Hoje existem **duas jornadas de entrada**, completas e desconexas:

| | portal do token | claim |
|---|---|---|
| entra por | link no e-mail, identidade provada pelo token | já estar autenticado |
| faz | perfil, vídeo, consentimento | liga auth existente a membro |
| cria conta? | **não** | **não** (pressupõe) |

Ninguém cria conta. É por isso que o muro existe, e é por isso que remendar a tela não resolve: o
passo "virar conta" não tem dono em nenhuma das duas.

**A decisão que a próxima sessão precisa levar ao dono**, com medição antes:

1. **O portal do token passa a criar acesso** (o token vira o comprovante de identidade que autoriza
   o signup, amarrado ao primário do membro). Menos saltos, e a identidade já está provada.
2. **O `/onboarding` reconhece anônimo com token** e oferece entrada, em vez de ser um muro.
3. **O e-mail de aprovado deixa de apontar para o portal do candidato** e passa a apontar para um
   fluxo de criação de acesso, ficando o portal só para quem ainda está em avaliação.

Não recomendo escolher sem antes contar **quantas pessoas estão hoje em cada estado** (aprovado sem
conta, aprovado com conta, em avaliação) — o desenho certo depende de qual população é a maior, e
essa contagem não foi feita.

---

## 5b. A pergunta do dono, e por que ela desmonta a seção 5

> *"Quero explicação do porquê algo que funciona parou de funcionar."*

A cobrança é certeira e **corrige a seção 5**. Se "nenhuma das duas jornadas cria conta" fosse a
história inteira, ninguém teria conta — e **56 de 66** membros criados em 150 dias têm. A jornada
não está estruturalmente quebrada. Há um terceiro caminho, e eu não o tinha olhado.

**Primeira medição, feita em 14/09.** Tempo médio entre o registro de membro e a criação da conta,
por mês de entrada:

| mês | entrantes | criaram conta | dias médios até a conta | sem conta há +14d |
|---|---|---|---|---|
| 05/2026 | 4 | 3 | **+0,1** | 1 |
| 06/2026 | 32 | 30 | **−6,3** | 2 |
| 07/2026 | 13 | 12 | **−11,1** | 1 |
| 08/2026 | 14 | 11 | **−18,5** | 3 |
| 09/2026 | 2 | 0 | — | 0 |

O número é **negativo e cresce em módulo**: a conta existe ANTES do registro de membro. O caminho
que funciona não é "vira membro → recebe e-mail → cria conta", é o inverso — a pessoa já se
cadastrou sozinha lá atrás, na candidatura, e o registro de membro veio depois.

Se isso se confirmar, a resposta muda de forma: **talvez o e-mail de onboarding nunca tenha sido um
caminho de entrada.** Não haveria regressão com data, e sim uma dependência num passo anterior que
ninguém mediu.

**Hipótese rival, MORTA na mesma sessão.** "Os que ficam sem conta são importados do VEP e nunca
tocaram o site":

| origem | tem conta | pessoas |
|---|---|---|
| VEP | **sim** | **53** |
| VEP | não | 4 |
| não-VEP | sim | 3 |
| não-VEP | não | 6 |

VEP tem **93%** de contas. A origem VEP explica o contrário do que a hipótese dizia.

### O que fazer com isto, e como NÃO medir

São **10 pessoas** sem conta em 150 dias. Com 10 casos, agregado é ruído: **reconstrua o caminho de
cada uma**, uma a uma. A pergunta por pessoa é "qual passo ela não deu, e existia caminho para
dar?".

⚠️ **Duas armadilhas na métrica, e eu caí na primeira antes de perceber.**

1. `avg` esconde a distribuição. Um punhado de contas muito antigas puxa a média para −18 sem que a
   maioria tenha esse comportamento. Use **mediana**, e olhe o histograma.
2. "Tem conta hoje" **mistura quem nunca vai ter com quem ainda não teve tempo**. A comparação entre
   coortes só vale com **janela fixa**: criou conta em até N dias da entrada. Sem isso, a coorte
   recente sempre parece pior, e a conclusão "parou de funcionar" nasce do próprio recorte.

O caso `c9c2058d` é um dos 10 e tem um sinal extra que os outros não têm: a pessoa **clicou** num
link morto, o que prova intenção. Comece por ela, mas não generalize a partir dela.

---

## 6. Estado operacional, para não redescobrir

- **PR #2270** aberta na lane `lane/entrada-e-onboarding` (worktree `../.wt-entrada`). Traz a ação
  `reissue_onboarding` no MCP. `validate` **verde**; `browser_guards` caiu e está re-rodando — é o
  mecanismo conhecido da **#2231**, não regressão desta PR.
- **A EF `nucleo-mcp` já está em produção na v269**, aplicada ANTES do merge, de propósito: sem ela a
  ação não teria superfície e a pessoa continuaria travada. A PR ficou aberta para não pôr na main
  código que a produção não roda — a deriva que a **#2271** descreve.
- **Deploy de EF nesta máquina só passa com `--use-api`** (bundle no servidor). Ver seção 7.
- **#2265 H4 continua aberta:** lembrete antes do vencimento para quem deixou a janela de 10,5 dias
  fechar. Outro conserto, outra PR.

---

## 7. Hipóteses MORTAS, medidas. Não reabrir

1. **"O deploy falha por rede intermitente".** Falso. Seis quedas seguidas, todas determinísticas: o
   bundler roda **dentro de container**, e a rede bridge do Docker desta máquina está sem saída
   (`--network host` passa, bridge falha **até no `ping 1.1.1.1`**). Medi o host com curl — 9/9,
   30/30, 100 em paralelo, 60 conexões frescas ao MESMO URL, todas verdes. **O instrumento saía por
   outra pilha e não tinha como acusar.** Registrado em memória.
2. **"IPv6 quebrado é a causa".** O v6 desta máquina está morto mesmo, e o `jsr.io` publica AAAA —
   parecia fechado. Mas o **próprio deno do bundler** buscou o URL em 0,26 s, status 200.
3. **"Tailscale subiu depois do Docker e reescreveu o firewall".** A ordem batia (tailscaled 11/09
   19:50, docker 08/09 10:29). Mas duas EF deployaram com sucesso em **12/09 22:08**, 26 h depois.
4. **`sudo systemctl restart docker` conserta.** **Não consertou** — foi executado e o container
   continua sem saída. A causa raiz do bridge segue **aberta e sem issue**.

---

## 8. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr view 2270 --json state,mergeStateStatus,statusCheckRollup
gh issue view 2273

# a rede do container, que é o que decide se dá para deployar daqui
docker run --rm redis:7-alpine sh -c 'ping -c2 -W3 1.1.1.1 && echo OK'
# se falhar, o deploy é: supabase functions deploy <fn> --use-api --project-ref <ref>
```

```sql
-- o estado do link reemitido (access_count > 0 significa que a pessoa clicou)
SELECT issued_at, expires_at, consumed_at, access_count
-- prefixo, nao o identificador inteiro: o scanner de segredo barra UUID completo em doc publico
FROM onboarding_tokens WHERE source_id::text LIKE 'c9c2058d%'
ORDER BY issued_at DESC;

-- a contagem que a seção 5 pede e que ninguém fez
SELECT sa.status, (m.auth_id IS NOT NULL) AS tem_conta, count(*)
FROM selection_applications sa
LEFT JOIN members m ON lower(m.email) = lower(sa.email)
GROUP BY 1,2 ORDER BY 3 DESC;
```

---

## 9. A lição do arco, e ela não é sobre onboarding

**Um instrumento que sai por outro caminho não pode reprovar.** Custou seis tentativas de deploy
chamadas de flake, e quase custou um e-mail para um endereço suprimido — foi o dry-run que consulta
o banco, e não a prévia sintética, que pegou o destinatário errado.

Antes de chamar algo de intermitente, pergunte **de qual namespace a ferramenta que falhou sai**. E
antes de confiar numa prévia, pergunte **se ela consultou o estado ou o fabricou**.
