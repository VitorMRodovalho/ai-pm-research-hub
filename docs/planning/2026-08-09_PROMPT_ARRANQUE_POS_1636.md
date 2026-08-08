# Prompt de arranque - depois do #1636

> Colar depois do `/clear`. **Effort: `xhigh`.**
> Handoff completo: `docs/planning/2026-08-08_handoff_1636_personas_sinteticas.md`.
> `main` em **`9044dccf`**. **#1636 fechada** (PR #1690, 6/6 verde, squash). **#1691 aberta**.
> Nenhum PR meu em aberto.
>
> ⚠️ Existem dois arranques homonimos de 09/08 ja **consumidos** (`_PROMPT_ARRANQUE.md` e
> `_PROMPT_ARRANQUE_POS_1643.md`). Este e o que vale.

---

## Regra zero

**Nada deste documento pode ser recitado.** Re-medir com tool call na mesma volta. Os quatro
padroes que ja custaram caro:

- **verde sem significado** (o gate passou, o efeito nao aconteceu)
- **numero certo, significado errado** (a query estava certa, a populacao nao era a da pergunta)
- **vermelho sem defeito** (o gate falhou por infraestrutura, e o dedo aponta para a mudanca nova)
- **verde por vacuidade** (o teste nao exerceu nada, e um `skip`/ramo vazio le como verde)

O quarto e o que esta sessao encontrou cinco vezes num arco so.

---

## Ja medido ao fechar (nao repetir do zero, mas conferir que segue valendo)

**A torneira fechou.** Medido na rodada de CI do proprio PR (run `31271160818`, 18:07→18:18 UTC),
que ja rodava o codigo novo contra producao: **5 linhas por rodada → 0**; 0 candidatura sintetica
sobrevivente, 0 membro sintetico, 0 token novo, 0 token orfao.

⚠️ O que da sentido a esse zero e o numero de **skips**: 6593 testes, 6592 pass, **1 skip**. Sem
credenciais seriam ~548 skips, e "0 linhas novas" ficaria indistinguivel de "o teste nao rodou".

Vale reconferir na primeira volta, porque e barato:

```sql
-- linhas de gate sem ator DEPOIS do cutoff, que caem em candidatura NAO sintetica
SELECT g.attempted_at, g.gate_passed, a.email IS NOT NULL AS app_existe,
       (a.email ~* '@([^@]*\.)?(example\.(com|org|net)|test|invalid|localhost)$') AS sintetica
FROM public.gate_attempts g
LEFT JOIN public.selection_applications a ON a.id = g.application_id
WHERE g.caller_id IS NULL AND g.attempted_at >= '2026-08-09T00:00:00Z'
ORDER BY g.attempted_at DESC;
```

O guard (`tests/contracts/1636-suite-nao-toca-candidatura-real.test.mjs`) ja afirma isto, mas ele
tolera o **cron** (carimbo `selection.%cron_run%` a +/-60s). Ler o resultado a mao uma vez, para
confirmar que o que ele tolera e mesmo cron.

---

## Estado ao fechar a sessao anterior

| item | estado |
|---|---|
| **#1690** | **mergeado** em `9044dccf` (squash, 6/6 verde) |
| **#1636** | **fechada** |
| **#1691** | **aberta** - as outras 35 superficies de escrita em prod |
| `main` | `9044dccf`, sem PR meu em aberto |

Suite completa no CI: **6593 testes, 6592 pass, 0 fail, 1 skip**.

⚠️ **`Fecha #N` NAO fecha issue.** O GitHub so reconhece `close/closes/closed`, `fix/fixes/fixed`,
`resolve/resolves/resolved`. O #1636 ficou aberto depois do merge e teve de ser fechado a mao.

⚠️ **Nao commitar docs na `main` com um PR seu aberto.** Um commit de docs move a `main`, o repo
exige branch em dia, e `gh pr update-branch` **recomeca todos os gates** (custou uma rodada inteira
no #1689).

---

## Nao re-litigar (decidido, medido, ou em producao)

- **Recorte do #1636**: fixture **efemera em producao** (convencao do #1437), escopo **so na
  familia do gate de entrevista**. A proposta anterior (base restaurada) foi medida e **nao
  fecharia o dano**: `ci.yml:95` injeta secrets de **producao** no `npm test`.
- Os **4 tokens** do #1636: **registrar, nao revogar** (decisao do PM, 08/08). Expiram **21/08**.
- As **627 linhas historicas** de `gate_attempts` ficam. Apaga-las seria falsificar auditoria de
  tentativas que de fato aconteceram; o guard afirma a **direcao**, a partir do cutoff.
- **#1643**, **#1682**, **#618** fechadas. Decisoes de backup de 08/08 seguem valendo.

---

## Ordem sugerida

### 1. Confirmar que a torneira fechou (ver "A primeira coisa a fazer")
Se a rodada da `main` pos-merge deixou zero, registrar na #1636 e seguir. Se deixou linha nova,
o guard falhou em detectar - e ai o alvo e o guard, nao a suite.

⚠️ Habito que vale reter: **depois de empurrar correcao num PR, cancelar os runs do SHA velho**.
Nesta sessao os dois SHAs competiram pela faixa de banco e o novo ficou `queued` atras do antigo.

### 2. #1691 - as outras 35 superficies
Inventario e encaminhamento ja estao na issue. ⚠️ A lista veio de **grep**, que nao distingue
chamar de citar (o proprio guard do #1636 apareceu nela, por causa do controle negativo). Triar com
`tests/helpers/rpc-call-scanner.mjs` antes de concluir qualquer coisa sobre um arquivo.

### 3. Residuos escolhidos, ainda intocados
- observador por URL direta ainda recebe a fila em `get_my_pending_evaluations`
- `route-acl.test.mjs` **reimplementa** o `canAccess` em vez de importar `getItemAccessibility`
- exigir evidencia no consentimento de IA (`RAISE`), depois de confirmado o front no ar

---

## Ainda em aberto, sem decisao

- Os quatro defeitos recortaveis do **#1679** viram issues?
- R2 sem lifecycle (~5 GB/ano). Se ganhar poda, a retencao de 30 do artefato precisa subir.

---

## Ferramenta nova desta sessao

- `tests/helpers/selection-fixtures.mjs` - monta candidatura sintetica na forma que o gate exige
  (recusa P0002, passagem, `reuse_prior`, alvo de rescue) e apaga tudo no fim. **Use isto** em vez
  de escolher alvo por predicado sobre producao.
- `tests/helpers/rpc-call-scanner.mjs` - distingue **chamar** uma RPC de **menciona-la** num
  literal. Serve para qualquer guard de classe sobre o codigo da suite.

Tres armadilhas que o helper ja paga por voce, e que voltam em qualquer fixture nova:

1. coluna **derivada** tem de ser gravada **por ultimo** (criar os filhos dispara o recompute e a
   apaga)
2. vinculo **polimorfico** (`source_id` sem FK) **escapa do CASCADE** - apagar a mao, antes
3. o ciclo "mais recente" pode nao ter a **capacidade** que o teste precisa; perguntar ao SSOT em
   vez de escolher por recencia

---

## Regras da casa

- Merge a `main` e da sessao main; lane leva o PR ate verde e para.
- **Force-push esta bloqueado pelo harness.** Atualizar branch de PR por `git merge origin/main`.
- Conflito na linha do `test` no `package.json`: resolver **por script**, tomando a lista do `main`
  e reinserindo o arquivo do branch. Transcrever a mao e como se perde um teste calado.
- Commit: `Assisted-By:`, nunca `Co-Authored-By`.
- Repo **PUBLICO**: nenhum candidato ou membro nomeado, so contagens.
- **Postura de backup nao vai para issue publica.**
- Nao rodar `npm test` com CI em voo. **Monitorar por RUN**, nao por `gh pr checks`.
