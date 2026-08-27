# Runbook: recuperar dado de backup

> Como recuperar linhas apagadas ou alteradas, e o que cada mecanismo de backup deste projeto
> **pode e não pode** fazer. Escrito a partir de uma recuperação real em 27/08/2026, com os
> vereditos medidos na ocasião - não deduzidos.
>
> **Leia a seção "Antes de qualquer operação destrutiva" ANTES de precisar deste runbook.** Ela é a
> parte que economiza a noite; o resto é o conserto de quando ela foi pulada.

---

## Os três mecanismos, e para que cada um serve

| mecanismo | onde vive | recupera linha específica? | precisa restaurar? | veredito |
|---|---|---|---|---|
| **Dump lógico diário** | artefato do GitHub Actions + cópia no R2 | **sim** | **não** | **é o caminho padrão** |
| Backup físico do provedor | Supabase, 7 diários | sim, mas só via restauração | sim, e **no lugar** | último recurso |
| PITR | - | - | - | **desabilitado** neste projeto |

### Por que o dump lógico é o caminho padrão

`.github/workflows/backup-database.yml` roda `pg_dump` **diário às 23:00 UTC** e publica o
`.sql.gz` como artefato do Actions (retenção 60 dias), com cópia para o R2. O próprio workflow
documenta a decisão econômica: o PITR de 7 dias do provedor custa cerca de dez vezes o compute do
projeto inteiro, e o dump diário compra o RPO (de 7 dias para 1) por minutos de CI, que são
gratuitos em repositório público.

O que esse arranjo **não** compra, e fica declarado: restauração para um instante arbitrário, e um
alvo de restauração não-destrutivo do lado do provedor.

**RPO efetivo: 24h.** Alterações feitas depois do último dump das 23:00 UTC não estão em lugar
nenhum.

### Por que o backup físico raramente serve

Backup físico não tem download: a operação oferecida é **restaurar**, e restaurar traz o banco
inteiro de volta àquele instante - desfazendo tudo o que foi feito depois, inclusive correções
legítimas. Para recuperar algumas linhas, é uma ferramenta desproporcional.

Se for mesmo necessário, restaure para um **projeto novo** e consulte lá; nunca em produção.

---

## Runbook A - recuperar linhas do dump diário (sem restaurar nada)

O caminho normal. Não sobe infra, não toca em produção, roda em minutos.

### 1. Escolher o backup certo

O dump precisa ser **anterior** ao momento em que o dado foi perdido.

```bash
gh run list --workflow=backup-database.yml --limit 7 \
  --json databaseId,createdAt,conclusion \
  --jq '.[] | "\(.databaseId) \(.createdAt) \(.conclusion)"'
```

Confira o `conclusion`: um run vermelho pode ter falhado **depois** do dump (já aconteceu neste
repo, com o passo de limpeza de artefatos falhando por permissão) - nesse caso o artefato existe e
presta. Confirme pelo tamanho.

```bash
gh api "repos/<owner>/<repo>/actions/runs/<RUN_ID>/artifacts" \
  --jq '.artifacts[] | "\(.name) | \(.size_in_bytes) bytes | expira \(.expires_at) | expirado=\(.expired)"'
```

### 2. Baixar

```bash
gh run download <RUN_ID> --dir ./bkp
```

### 3. Extrair a tabela SEM subir banco

O dump é SQL puro com blocos `COPY ... FROM stdin`, terminados por `\.`. Um `awk` recorta a tabela
inteira em segundos - não é preciso `pg_restore`, container, nem Postgres local.

```bash
zcat ./bkp/*/backup_*.sql.gz | awk '
  /^COPY public\.<TABELA> \(/ {inblk=1; next}
  inblk && /^\\\.$/           {inblk=0}
  inblk                        {print}
' > tabela.tsv
```

⚠️ **A ordem das colunas vem do cabeçalho do bloco, não da sua memória.** Leia-a antes de indexar
campos:

```bash
zcat ./bkp/*/backup_*.sql.gz | grep -m1 "^COPY public\.<TABELA> ("
```

A saída é TSV com `\N` para NULL. A partir daí, `awk -F'\t'` responde quase qualquer pergunta.

### 4. Comparar, e provar que a comparação funciona

Se a pergunta for do tipo "quem estava em A e não está em B", use conjuntos:

```bash
comm -13 <(sort -u a.ids) <(sort -u b.ids)   # so em B
comm -23 <(sort -u a.ids) <(sort -u b.ids)   # so em A
comm -12 <(sort -u a.ids) <(sort -u b.ids)   # intersecao
```

⚠️ **Nunca publique um "zero" sem controle positivo.** `0 registros na diferença` é
indistinguível de uma junção quebrada, de um arquivo vazio ou de um campo trocado. Publique junto a
**interseção** e a **diferença na outra direção**: se elas forem não-vazias, o zero é um fato; se
todas derem zero, você mediu o próprio erro.

Foi exatamente esse controle que sustentou a conclusão de 27/08 - a diferença numa direção era 0 em
três semanas seguidas, e só as interseções não-vazias (5, 6 e 3) e a diferença oposta (2, 1 e 3)
mostraram que a comparação enxergava diferença quando ela existia.

---

## Runbook B - restauração completa

Só quando a perda for ampla o bastante para a recuperação linha a linha não fazer sentido.

1. **Nunca restaure em produção sem inventariar o que será desfeito.** Toda alteração posterior ao
   ponto de restauração some - inclusive correções feitas em resposta ao próprio incidente.
2. Prefira restaurar para um **destino separado** (projeto novo, ou o dump lógico carregado num
   Postgres local) e mover só o que precisa.
3. Um dump lógico sobe em qualquer Postgres de versão compatível ou superior:
   ```bash
   createdb restore_tmp && zcat backup_*.sql.gz | psql restore_tmp
   ```
   O cliente precisa ser de versão **maior ou igual** à do servidor que gerou o dump.

---

## Antes de qualquer operação destrutiva

A lição que este runbook existe para transmitir. Cancelar, arquivar, apagar, mudar estado em massa:

1. **Saiba onde está a cópia e como se lê ela** - antes, não depois. Se não souber responder "de
   onde eu recupero isso?", não execute.
2. **Leia os gatilhos da tabela, não só a função que você vai chamar.** Ler o corpo de uma RPC e
   concluir que ela "não mexe em X" não é ler o efeito: um trigger em `AFTER UPDATE` pode apagar X
   sem que a função saiba.
   ```sql
   SELECT tgname, pg_get_triggerdef(oid)
   FROM pg_trigger WHERE tgrelid = '<schema>.<tabela>'::regclass AND NOT tgisinternal;
   ```
3. **Salve o estado que vai mudar** - mesmo que só as contagens, mesmo que num arquivo temporário.
   É a diferença entre "sei o que procurar no backup" e "descobrir o que faltava".
4. **Prefira o caminho oficial** (RPC/serviço) ao `UPDATE` direto: ele carrega as validações, a
   autoria e o registro de auditoria que a escrita crua não tem.
5. **Faça em lote pequeno e verifique entre lotes.** Serviços de renderização, APIs e a própria
   fila de CI têm limites que só aparecem sob volume.

---

## O que nunca vai para o repositório

**Dado operacional não é versionado, e isto é deliberado.** Este repositório é público; presença,
identidade, contato e vínculo de pessoas são dado pessoal.

O que existe no git é **schema, código e seeds estruturais** (catálogos, capítulos, cartões
iniciais). O backup de dado vive no **artefato do Actions e no R2** - fora da árvore versionada,
com retenção própria.

Se um dump aparecer versionado num commit, trate como incidente de exposição, não como
conveniência.

---

## Referência rápida

| pergunta | resposta |
|---|---|
| Qual o RPO? | 24h (dump diário às 23:00 UTC) |
| Quanto tempo o artefato dura? | 60 dias no Actions, mais a cópia no R2 |
| Dá para recuperar sem restaurar? | Sim - Runbook A, e é o caminho padrão |
| Dá para restaurar para um instante? | Não - PITR está desabilitado |
| Backup físico do provedor baixa? | Não; ele restaura no lugar |
| O git tem o dado? | Não, e não deve ter |
