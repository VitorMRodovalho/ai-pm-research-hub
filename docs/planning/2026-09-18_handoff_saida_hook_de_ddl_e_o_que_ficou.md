# Handoff de saída 18/09: o hook que herdou o ponto cego, e o que ficou para a próxima sessão

> **Nada aqui é medição viva.** Carimbado em 18/09 ~14h50 UTC, antes de um reboot da máquina.
> **Re-meça antes de decidir.** Repositório público: este documento não nomeia terceiros.

**Estado ao encerrar:** `main 1ce23694` · **2 PRs abertas** (#2363 e esta) · lane `fix/2351-rota-de-ata`
encerrada, sem pendência.

---

## 1. Antes de qualquer coisa: o portão mudou

**Fila de PRs vazia NÃO é banco livre.** Rode as DUAS:

```bash
gh pr list --state open
gh run list --limit 30 --json name,status \
  --jq '[.[]|select(.status!="completed")|select(.name|test("Validate|Invariants|DB Types"))]|length'
```

Sem `--branch`. O recorte por branch zera no instante do merge, e é ele que cria o ponto cego.

## 2. O achado do dia: o mecanismo herdou o ponto cego da regra

O hook `PreToolUse` instalado em 17/09 para impedir DDL fora de ordem consultava **só**
`gh pr list --state open`, porque era isso que a regra MANDATÓRIA mandava. Medido em 18/09, segundos
após mergear a #2360:

| consulta | resultado |
|---|---|
| `gh pr list --state open` | **vazio** |
| `gh run list` (sem `--branch`) | `CI Validate` e `Schema Invariants` **em voo, na `main`** |

⚠️ **Mergear zera a fila e dispara os jobs de banco no mesmo segundo.** O hook media a condição
exatamente no instante em que ela mais engana, que é também o instante em que mais dá vontade de
escrever. Ele teria liberado uma DDL ali.

**Isto é pior que erro de leitura humana:** um humano relendo corrige; o hook é o que as próximas
sessões obedecem **sem** reler.

Conserto na **PR #2363**, exercitado em quatro braços, e o quarto é o que prova que muda algo:

| braço | resultado |
|---|---|
| estado real do momento | disparou: "0 PR(s) aberta(s) e 1 job(s) de banco em voo" |
| tudo livre | silencioso |
| 0 PRs, 1 job de banco | disparou |
| o mesmo, na versão **ANTIGA** | **silenciosa** — o defeito reproduzido |

✔ **E a PR que conserta o ponto cego é, enquanto roda, a maior ocupante do banco:** 3 dos 4 jobs em
voo são dela. Não é contradição, é a demonstração mais barata de que o sinal consertado é o certo,
medida pela própria PR que o conserta.

✔ **O portão novo já bloqueou o autor dele**, minutos depois de subir: com a #2363 aberta e 4 jobs em
voo, ele barrou a execução dos testes da seção 5. Guard que nunca foi visto agindo não é guard.

## 3. O que foi entregue hoje

- **Reunião de Liderança #12**: ata de 10.998 chars, **15 presenças** (era 6), 21 ações com
  responsável e prazo, 4 decisões, resumo do `close` de 870 chars. Fonte: transcrição integral.
- **PRs mergeadas:** #2359 (rota de ata da #2351), #2358 (adendo), #2360 (handoff).
- **Issues abertas:** #2361 (170 tools absorvidas mas registradas), **#2362** (grants + guard derivado).

⚠️ **Dois denominadores, um `count`.** `meeting_action_items` guarda ação E decisão na mesma tabela.
`count(*)` cru devolve **25** para a Liderança #12; `action_count` do `close` devolve **21**, porque
conta só `kind='action'`. **Conte por `kind`**, ou alguém abre reconciliação que não existe.

## 4. Classe que mordeu TRÊS vezes hoje, em superfícies diferentes

**Esperar por "nenhum pendente" termina pela ausência.**

| superfície | a ausência que engana |
|---|---|
| `gh pr checks` | não lista quem ainda **não reportou**; declarou "todos verdes" com 1 check |
| `check-runs/<id>.output.summary` | vazio **não** é "a instrumentação não escreveu" (é outro campo) |
| log de run em andamento | indisponível **não** é "sem assinatura" |
| `gh pr list --state open` | vazio **não** é banco livre (seção 2) |

Em todas, a ausência se disfarça de resposta. **Toda espera por convergência precisa de denominador
explícito**, não de ausência de pendência.

## 5. ⚠️ ABERTO: dois testes que NÃO rodaram, herdados da lane

A lane `fix/2351-rota-de-ata` encerrou e me passou dois itens de **confirmação** (não de mudança).
**Não rodei**, porque o portão da seção 1 estava fechado: 1 PR aberta e 4 jobs de banco em voo.

```bash
# SÓ quando as DUAS contagens da seção 1 derem zero:
set -a; . ./.env; set +a
node --test tests/contracts/2351-rota-de-ata-unica-e-resumo-sobrevive.test.mjs
node --test tests/contracts/rpc-migration-coverage.test.mjs
```

- **Primeiro:** esperado **5/5, 0 skips**. ⚠️ Se os dois exercidos vierem `skipped`, o `.env` não
  carregou. **Skip silencioso lê como verde** — é o modo de falha, não o sucesso.
- **Segundo:** em 17/09 a única falha local era a tabela órfã `event_type_digest_audience`. Com a
  #2353 mergeada, **espera-se** que tenha sumido. **Isso é expectativa, não medição**, e é o único
  item que a lane deixou em aberto. Outro nome aparece em `New orphan tables:` no corpo do erro.

## 6. ABERTO, o resto

| # | o que | estado |
|---|---|---|
| #2363 | o hook enxerga job de banco | **PR aberta**, precisa de merge |
| #2362 | `REVOKE` + guard derivado de `_test_*` | issue aberta; **o `REVOKE` NÃO foi aplicado** |
| #2361 | 170 tools absorvidas mas registradas | issue aberta, sem dono |
| ata de comunicação 17/09 | sem fonte | doc não compartilhado com a conta do dono |
| ata da tribo 8 17/09 | sem fonte | material está com quem hospeda |
| #2343 | flake do `browser_guards` | ocorrências agora classificadas |

**As duas atas não são trabalho pendente, são acesso.** O 404 foi medido com controle positivo em
três instrumentos (rclone em 4 contas, navegador logado, tela do Google): é compartilhamento, não
ferramenta. Com o texto em mãos, saem rápido — o caminho inteiro foi exercitado hoje.

**Vídeo da Liderança #12:** duração real **2h11m32s**, extraída do átomo `mvhd` lendo só a cauda do
arquivo. **Não precisa de corte:** a transcrição começa em 00:00:00 (chat aos 12s) e o vídeo termina
DENTRO da última seção de fala, não depois dela. **Se foi para o YouTube, não sei:** as colunas
`youtube_url`/`recording_url` estão NULL em TODAS as reuniões de liderança (#11 a #18), então o campo
é morto e NULL ali não é evidência; e o RSS público não enxerga vídeo não listado.

## 7. Máquina

O perfil do Playwright é compartilhado por ~13 servidores MCP, um por sessão, e só um segura o lock.
Foi liberado uma vez hoje por outra lane e **retomado em menos de uma hora**. Se depender dele,
conte com disputa.
