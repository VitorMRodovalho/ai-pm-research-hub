# Arranque: o que fica de pé ao encerrar o arco de 09 a 12/09

> **Nada aqui é medição.** Carimbado em 12/09 às 18h BRT. **Re-meça antes de decidir:**

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 40
```

**Estado ao encerrar, para COMPARAR:** `main 02241dd0` · **0 PRs abertas** · último `validate` na main
**verde** · 22 issues abertas criadas nos últimos 3 dias.

---

## 1. Item zero: a árvore compartilhada, e o incidente que quase custou

`~/projects/ai-pm-research-hub` é o clone primário, e **duas sessões operaram nele ao mesmo tempo**
durante todo o arco: esta e a lane `-ff`. Em 11/09 eu rodei `git checkout main` e **movi a árvore
debaixo dela**, sem sinal nenhum para ela. Não quebrou por sorte de sequência: ela já tinha dado
push. Podia ter invalidado build ou teste no meio.

**A saída existe e estava disponível:** `scripts/setup-lane.sh ../.wt-<lane>`. As outras quatro lanes
usam worktree (`.wt-campanha`, `.wt-cpmai`, `.wt-lideranca`, `.wt-pauta`); a `-ff` não tinha.

**Regra para a próxima lane: abrir worktree ANTES de qualquer coisa.** E, antes de trocar de branch
no clone primário, confirmar que ninguém mais está nele (`ListAgents` mostra as sessões vivas).

Nome de sessão, aliás, **não é endereço durável**: três sessões foram renomeadas em 12/09 e a lane
tinha o nome antigo guardado em memória. Guarde o **papel** ("a sessão main"), resolva o nome na hora.

---

## 2. A fila destravou, e as três causas eram diferentes entre si

A `main` estava parada desde 09/09 22:59. Sete PRs entraram em 11-12/09, e o `validate` estava
vermelho por **três defeitos distintos**, não um:

| | causa real | não era |
|---|---|---|
| `#1536` | o gate contava FALTA como presença | conflito de agenda |
| `#676` | a regra dizia `biweekly` depois que a comms virou semanal | duplicação de série |
| `#1945 C` | **amostra sorteada sem `ORDER BY`**, interseção vazia lida como gate morto | vencimento de engajamento |

No `#1945 C`, medido: **24 dos 58** pesquisadores ativos discriminavam no mesmo conjunto de boards. O
helper estava intacto o tempo todo. O conserto foi trocar sorteio por **par construído**, que o teste
irmão `#1953 C` já fazia **no mesmo arquivo**. A lição estava escrita a dois testes de distância e
foi paga duas vezes.

**Sobra da #2233:** só o item 4, que é política. Um check obrigatório que lê dado vivo fica vermelho
sozinho, sem ninguém errar, e a pressão vira contornar o portão.

---

## 3. A suspeita que virou mecanismo: #2231

Começou como "flake no `browser_guards`" e terminou com o mecanismo lido no código do astro 7.2.10.

**O que está estabelecido:**

- o adapter do Cloudflare usa `astro/app/entrypoint/dev`, que chama `setFetchHandler` **incondicionalmente**, sem consultar a bandeira `isDefaultFetchHandler` que o próprio plugin exporta;
- `setFetchHandler` decide por `instanceof`, e os dois lados resolvem o **mesmo arquivo por especificadores diferentes** (bare, pré-bundlado pelo `optimizeDeps`, contra relativo). Duas cópias, duas identidades, `instanceof` falso por construção;
- **o mesmo `instanceof` ROTEIA a requisição** (`base.js:260`), e o ramo errado serve pelo manifesto ambiente, sem os hooks de erro, streaming e `logRequest`;
- por isso **as requisições que falham não têm linha `[200]`**: o `[200]` sai do hook que só existe no ramo certo.

**O critério de falsificação, que não custa medição nova:** avaliações boas e ruins coexistem, e cada
uma é inteiramente boa ou inteiramente ruim. Então **nunca** pode existir uma requisição com os três
WARN **e** `[200]`. Aplicado a 7 runs: **99 `[200]` contra 41 tríades, zero cruzamentos.**

**Hipóteses MORTAS, medidas. Não reabrir:**

1. degradação ao longo da vida do dev server — refutada por um `[200]` **entre** duas falhas;
2. o reload do optimizer como gatilho — nos dois logs está **46 s antes** da primeira falha, com 7 e 8 requisições boas no meio;
3. `src/fetch.ts` existir na árvore — não existe; o nome é **texto fixo** na mensagem do astro.

**Isto atinge a MAIN.** Três runs pós-merge de 11/09 falharam em `validate` e `browser_guards`, e o
monitor abriu 5 issues em 3 dias, **todas auto-fechadas**. Alerta que sempre se fecha sozinho é
alerta que ninguém abre na sexta vez.

**Consequência para a #2217:** se é forma de código no core mais a escolha de pré-bundlar, **não se
resolve escolhendo versão dentro da linha 7.2**. A #2217 não deveria continuar esperando.

---

## 4. Entrega de e-mail: o que foi consertado e o que não foi

**Consertado, com gente real esperando:** um líder de tribo ativo estava **94 dias** sem receber
e-mail, e um guest nunca recebeu **nenhum** e-mail de onboarding. Os dois por supressão do provedor
após reclamação de spam. Supressões removidas; a lista caiu de 6 para 4, e os 4 restantes não são
membros.

**A causa continua de pé (#2130).** O Resend responde **200 para endereço suprimido**: aceita,
devolve id, e suprime depois por webhook. E `notifications` **não guarda o `resend_id`**, então o
webhook não tem onde pousar. Por isso 12 dos 15 sinais de parada ficam órfãos.

**Achado que fecha o diagnóstico:** `email.suppressed` **nem está** na lista de eventos válidos do
webhook. Daí `processed = false` em 43 linhas desde sempre, mais 4.513 de `email.sent` e 57 de
`delivery_delayed`. Os cinco tipos tratados estão 100% processados; os três de fora, 0%.

**Spec de implementação pronta** no comentário 5641960282 da #2130, com ordem, rollback, detector e o
adendo da dívida histórica. **Decisão do dono: executar com fila fria e alguém olhando os primeiros
envios**, porque o modo de falha é silencioso (se o envio parar, nada avisa).

> **Correção que eu devo:** afirmei duas vezes, em issue pública, que `email_sent_at` era gravado sem
> olhar a resposta do provedor. **É falso.** O código sempre condicionou ao `res.ok`. Recitei uma
> premissa antes de abrir o arquivo.

---

## 5. Onboarding e presença: quatro defeitos novos

| # | o que |
|---|---|
| **#2245** | as 5 chaves fora do catálogo **voltaram 8 dias** depois de removidas: a migration apagou as linhas e **não a fonte**, que é um JSONB por ciclo (`selection_cycles.onboarding_steps`), presente nos **três** ciclos, inclusive o aberto |
| **#2241** | dos 8 guests reais, 4 nunca criaram conta e **3 não têm nenhuma linha de trilha** |
| **#2246** | auto check-in e escrita sem autor são **indistinguíveis**: 36 de 38 com `registered_by` nulo, e isso é o esperado para auto check-in |
| **#2247** | arquivar iniciativa **não fecha a série de reuniões**: 5 eventos são tentados pelo cron todo dia, para sempre |

**A #2245 é a única que piora sozinha:** toda aprovação futura no ciclo aberto recria o defeito.

**Sobre presença, para não refazer a conta:** as quatro últimas reuniões **estão registradas**. As
duas mais recentes não estão seladas porque o **prazo não venceu** (`grace_days: 14`); a Liderança
#11 sela ~17/09 e o Geral de 10/09 ~24/09. O cron está vivo e rodou todo dia.

⚠️ **Armadilha:** o Geral de 27/08 está selado desde **31/08**, quatro dias depois, que é **menos**
que a carência. Aquele selo foi **manual**. Quem comparar datas sem saber vai inferir uma carência de
4 dias que não existe.

---

## 6. Do lado do dono: sete decisões abertas

1. **#2238** — o que a equipe de comunicação pode fazer em Campanhas. Hoje **7 pessoas** são nomeadas pela tela e **0** passam. Exige o procedimento de 4 etapas do V4 antes de qualquer seed.
2. **#2245** — o destino de cada uma das 5 chaves (o mapa já está na issue).
3. **#2241** — os 3 guests sem trilha, e se o nudge de onboarding sai de digest para transacional.
4. **#2236** — o alvo do conserto, que a medição mostrou **não** ser o cron de selagem.
5. **#2229**, **#2227**, **#2228** — portão de XP, curadoria fora do modelo, 3 pessoas sem tribo.
6. **#2233 item 4** — a política sobre check obrigatório que lê dado vivo.
7. **#2217** — seguir sem esperar a #2231 (recomendado acima).

---

## 7. Feito e NÃO refazer

- **Sete PRs mergeadas** em 11-12/09: #2235, #2240, #2237, #2232, #2230, #2223, #2244.
- **`_drive/` fora do scanner de build** (#2239, fechada). O `astro build` pendurava porque andava para dentro do mount FUSE do Drive. Com a linha, **4,5 s**.
- **Supressões removidas** para dois membros; nenhum membro está bloqueado hoje.
- **E-mail primário de um guest trocado** (registro com antes/depois no comentário 5648638208 da #2241). Consertou entrega **e** reconhecimento no login: `get_member_by_auth` liga conta nova a membro **só pelo e-mail primário**, então ele logaria como ghost.
- **Duas notificações vencidas aposentadas** para `suppress` (mesmo registro). Anunciavam reunião 16 dias no passado e teriam saído num disparo em lote.
- **Gravação de 10/09 publicada** com legenda trilíngue servindo, ata de 6.781 caracteres no evento.
- **2,0 GB de mídia de trabalho apagados** em `_pmo/youtube/geral-2026-09-10/`, mantendo os 3,4 MB de registro (capítulos, chat, notas do Gemini, legendas, logs). Fonte original preservada no Drive e publicado no YouTube.

---

## 8. Três arquivos órfãos, não reivindicados

Não rastreados, todos de **29/08 17:27**, duas semanas antes deste arco. **Não toquei.**

| arquivo | o que é |
|---|---|
| `docs/specs/SPEC_TROCA_DE_TRIBO_JANELA_E_ALERTA.md` | SPEC em **PLAN**, de 07/08, sobre offboardar alguém da Tribo 13. Execução **suspensa** porque a jornada termina em porta fechada. Irmão de vários SPECs commitados. |
| `scripts/design-kit/_t11_airmeet_tmp.py` | peças Airmeet da T11. Existe `build_t11_airmeet.py` **commitado**, que parece sucedê-lo. |
| `scripts/design-kit/_t11_formas.py` | exploração de três recortes de retrato; a decisão (forma geométrica, medida) importa mais que o script. |

**Não commitei o SPEC de propósito:** é trabalho de outra pessoa e misturá-lo numa PR de arranque
tiraria a decisão de quem deve tomá-la. Mas ele é **trabalho pendente invisível** há duas semanas e
complementa a #1877 e a #1885. Dois estão sob `scripts/`, caminho crítico do `issue_reference_gate`:
se entrarem num commit sem issue, o portão reprova.

---

## 9. As lições que o arco pagou

Registradas na **#588** (comentário 5647972360). As três que valem fora deste repo:

**Limpar o efeito sem tocar a fonte faz o defeito voltar com data marcada.** Antes de apagar linhas,
perguntar *quem as escreve, e essa fonte muda com a limpeza?*

**"O provedor aceitou" e "a pessoa recebeu" são dois fatos com tempos diferentes**, e quem não guarda
o identificador da mensagem no aceite não consegue descobrir o segundo depois.

**Correlação perfeita vale mais que amostra grande**, quando a hipótese rival a proíbe. Foi o que
converteu uma observação em critério de falsificação que se confirma de graça.

E a de processo, que foi minha: **recitei uma premissa duas vezes antes de abrir o arquivo**, e as
duas viraram correção pública. Abrir o arquivo custava dois minutos.
