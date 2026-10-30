---
description: Guard and contract-test rules — bind the CONDITION to the RESULT inside the deciding block, mutation that really changes the file, live layer proved by direct evidence plus positive control
paths:
  - "tests/**"
  - "scripts/**"
  - ".github/workflows/**"
---

# Asserção de guard amarra CONDIÇÃO ao RESULTADO — presença de string não é prova
Movido verbatim do CLAUDE.md em 30/10/2026; o resumo MANDATÓRIO fica lá.

**IMPORTANT — YOU MUST:** ao escrever um guard que afirma sobre um corpo (SQL, TS, `.astro`), a
asserção tem de casar **a condição junto com o resultado que ela produz**, dentro do bloco que
decide. `includes('x')` ou `/x/` solto num corpo de centenas de linhas fica **verde com o
mecanismo removido**, porque a string sobrevive em algum lugar que não decide nada.

- Três incidentes em 17/09/2026, todos pegos pelo teste de mutação e **nenhum por leitura**:
  1. `#2335`: `/is_visitor/` solto passava com o campo **removido do UNION** — a string sobrevivia
     nos comentários.
  2. `#2286`: `ef.includes('other_notifications')` passava com o **bloco do e-mail removido** —
     casava o comentário que eu mesmo escrevi para explicar a seção.
  3. `#2341`: `/retired_at IS NOT NULL/` passava com a **classificação inteira neutralizada** —
     casava a contagem de `retired_jobs` no `RETURN`.
- **A forma que funciona:** recortar o bloco que decide e afirmar dentro dele, ligando os dois lados
  — `assert.match(bloco, /retired_at IS NOT NULL\s+THEN\s+'aposentado'/)`, não
  `assert.match(corpo, /retired_at/)`. Para TS, mascarar comentários antes de medir
  (`maskJsComments`); para SQL, `maskLineComments`.
- **Mutação é obrigatória, e a mutação tem de MUDAR O ARQUIVO de fato** (compare o md5 antes e
  depois; uma mutação que não aplicou lê como "guard aprovou"). Cada asserção precisa de uma
  mutação que a faça reprovar, e o controle sem mutação precisa passar no fim.
- **Mutar o ARQUIVO não exercita camada VIVA.** Quando o guard afirma sobre o banco, a prova é
  evidência direta + controle positivo — exercer a função com impersonação e mostrar o estado
  mudando nos dois sentidos, como em `#2341` (expectativa sem cron ⇒ `red`).
