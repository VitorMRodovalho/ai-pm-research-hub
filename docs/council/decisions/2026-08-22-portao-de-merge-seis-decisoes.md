## Decision: as seis decisoes de portao de merge, aprovadas em bloco (auditoria #1908 / #1912)

**Date:** 2026-08-22  **Decided by:** PM/GP (Vitor)  **Status:** Accepted
**Fonte:** `docs/audit/2026-08-21_AUDITORIA_CI_E_CRITERIOS_DE_MERGE.md` (secao 9), apresentadas
num docket de decisao com opcoes e recomendacao por item.
**Contexto que motivou:** 6 travamentos de fila medidos, sendo o de 21/08 com **5h22m54s** de
congelamento. Ver #1910 para o padrao sistemico.

### Decision

As seis foram aprovadas **conforme a recomendacao apresentada**. Uma delas e uma decisao de
NAO-fazer, e esta registrada como tal de proposito.

| # | decisao | desfecho |
|---|---|---|
| **A1** | partir `npm test` em `structural` + `behavioural`, ambos required | **fazer, depois da A2** |
| **A2** | invariante de DADO sai do check required | **fazer agora** |
| **A3** | `validate` pos-merge: fazer o **deploy depender dele** | **fazer (opcao A)** |
| **A4** | migrar branch protection legada para ruleset | **fazer** |
| **A5** | merge queue e branch efemera do Supabase | **NAO adotar** |
| **C1** | #1586, superficie autenticada para despacho | **priorizar** |

### O racional de cada uma, resumido

**A2 (a que ataca a causa).** Invariante de CODIGO e funcao do diff, entao o autor da PR pode
consertar. Invariante de DADO e funcao do estado do banco, que o autor nao controla e as vezes
nem ve. Um portao required que o autor nao consegue acionar nao e portao, e pedagio, e a resposta
racional a um pedagio e o bypass. Evidencia concreta: a PR #1907 mexia em UM arquivo de teste e
reprovava em tres guards de schema.

**A1 (latencia, nao correcao).** 287 arquivos (47% da suite) nao tocam banco, custam 12,7s, e
esperam p90 14m21s numa faixa que nao e deles. Sequenciada DEPOIS da A2 porque a A2 muda quais
testes existem em cada metade; fazer antes seria fiar duas vezes.

**A3 (portao sem cobertura).** O deploy publica ~12 min ANTES de o `validate` pos-merge terminar,
entao hoje esse run e custo sem cobertura e ainda ocupa a faixa do banco quando a proxima PR
precisa dela. Escolhida a opcao A (deploy depende do validate) em vez da B (parar de rodar no
push): publicar sem portao parece barato ate o dia em que nao e. Custo aceito: o deploy passa de
~1m22s para ~14 min.

**A4 (barata e reversivel).** Ruleset da bypass por ator explicito e auditavel, melhor que o
`enforce_admins: false` atual para sustentar o protocolo de bypass que ja existe aqui.

**A5 (o NAO, registrado para nao voltar).** Sao as duas solucoes que qualquer pessoa proporia ao
ouvir "a fila de merge trava", e as duas falham contra as causas medidas:
- **merge queue** nao ataca nenhuma das duas causas: o que trava nao e colisao entre PRs, e evento
  de producao reprovando todo mundo;
- **branch efemera do Supabase** nasce SEM DADO, e os testes que importam afirmam sobre dado real.
  Contra banco vazio eles passariam por vacuo, trocando vermelho legitimo por verde falso.

**C1 (produto, nao CI).** Enquanto a unica porta para despachar convite for o `service_role`, toda
decisao manual do PM vira linha sem ator e entra no allowlist do #1636 para a fila voltar a andar.
A lista foi de 1 para 6 entradas em dois dias, e 5 das 6 sao a mesma operacao. Registro honesto: o
**gate funcionou** nas cinco (nenhum token emitido, nenhum e-mail enviado). O que cresceu nao e
divida tecnica, e o custo visivel de uma funcionalidade que falta. O allowlist e termometro, nao
sujeira a limpar.

### Sub-decisao dentro da A2 (fronteira)

Saem do required os cinco testes `no NEW ... drift` (Q-C, Phase C, ADR-0097 x3) e a **Camada B** do
#1636. **Ficam** no required a **Camada A** do #1636 (guard de CLASSE, funcao do diff: quem escreve
o teste conserta) e os ratchets `stays in sync` / `baseline size`. A fronteira foi escolhida por
criterio EMPIRICO (quais congelaram a fila), nao por pureza conceitual, e e uma linha no helper se
precisar mudar.

### Invariante que a A2 nao pode violar

**Destravar o portao nunca pode apagar o sinal.** E a mesma regra que o #1850 ja aplica ao
`INVARIANT_STRICT`. Por isso a A2 inclui um job de heartbeat que monitora o `invariants-check` e
abre issue quando ele fica vermelho: sem ele, a mudanca trocaria "fila congelada por evento de
producao" por "sinal que ninguem le", que e pior, porque o primeiro incomoda e o segundo
desaparece. Verificado com defeito injetado, dos dois lados.

### Rastreamento

- **A2** -> PR #1914
- **B1** (conserto mecanico, fora do bloco de decisao) -> PR #1913, mergeada em `8309ab94`
- **A1, A3, A4** -> a executar, uma de cada vez; A1 depende da A2 ter landado
- **A5** -> nada a executar; esta decisao E o registro
- **C1** -> #1586, roadmap
- Padrao sistemico -> #1910
