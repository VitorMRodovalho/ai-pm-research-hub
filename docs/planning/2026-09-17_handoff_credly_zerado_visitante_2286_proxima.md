# Handoff de 17/09: o Credly zera, o visitante aparece, e a #2286 e a proxima

> **Nada aqui e medicao viva.** Carimbado em 17/09, ~09h40 BRT. **Re-meca antes de decidir.**
> Repositorio publico: este documento nao nomeia ninguem. Casos individuais vivem nos cards do
> Hub de Onboarding e nas issues.

**Estado ao encerrar, para COMPARAR:** `main 2714a362` · **0 PRs abertas** ·
issues deste arco: **#2286, #2296, #2333, #2334** · invariantes **0 de 44**.

---

## 0. O que foi fechado

| PR | issue | o que |
|---|---|---|
| #2324 | #2323 | o detector que conclui passo de onboarding ganha cron — **33 pessoas destravadas** |
| #2326 | #2325 | a cobranca do termo deixa de nascer suprimida |
| #2330 | #2296 | a decisao por badge vira DADO (17 decisoes ja afirmadas em guard) |
| #2331 | #2296 | o dono decide os 22 restantes — **detector 39 -> 0** |
| #2335 | #2334 | o visitante aparece na tribo sem entrar na contagem |

Tambem: LL registrado na **#588**; iniciativa **Hub de Onboarding e Engajamento** criada (workgroup,
com board), com dois cards (um do hub, um da corte do GP).

---

## 1. A PROXIMA COISA: #2286, e o numero da issue esta 17x subestimado

A issue diz "76 de 78 notificacoes de 2 tipos". **Medido em 17/09 na fonte:**

| | |
|---|---:|
| tipos em `digest_weekly` | **31** |
| tipos que alguma secao de `get_weekly_member_digest` renderiza | **9** |
| tipos ENGOLIDOS | **27** |
| linhas carimbadas como entregues sem nunca renderizar | **1277** |

Inclui coisas que importam: `selection_onboarding_overdue` (237), `event_stale_no_attendance` (188),
`card_assigned` (144).

**A premissa da issue se confirma, e o mecanismo e mais sutil do que ela registra.** O
`consumed_notification_ids` TEM filtro por tipo, mas ele serve para ESTENDER a janela, nao para
restringir:

```sql
AND ( n.created_at >= v_window_start                    -- <- pega QUALQUER tipo
      OR (n.type IN ('attendance_reminder','assignment_new')
          AND n.created_at >= v_extended_window) )
```

A primeira condicao varre tudo. Quem ler so a lista de tipos conclui que ha filtro; ha, e ele nao
filtra o que importa.

Os 9 renderizados, lidos sec ao por secao: `assignment_new`; `engagement_welcome`,
`engagement_added`, `volunteer_agreement_signed`; `attendance_reminder`; `tribe_broadcast`;
`governance_vote_reminder`, `ip_ratification_gate_pending`, `change_request_pending`.
(`plenaria`/`webinar`/`workshop_geral` que aparecem no corpo sao tipos de EVENTO, nao de notificacao.)

**Depois da #2286 vem `get_digest_health`, nessa ordem** — ela mede a saude do canal, e instrumentar
um canal quebrado da um verde que nao significa nada. Detalhe medido: ela procura 3 jobs por nome,
um dos quais (`weekly-card-digest-saturday`) **nao existe mais** — foi removido de proposito em maio
(`p89_cron_audit_fixes`) porque duplicava o digest do membro. Ela nao distingue "job ausente" de
"job saudavel": o `WHERE jobname IN (...)` simplesmente nao retorna a linha que falta.

---

## 2. Fatia 2 da #2334: presenca em secao propria (decidida, nao implementada)

O visitante ja APARECE na lista de membros (#2335), mas **nao na tab de presenca**. Causa exata:

```sql
grid_members AS (
  -- ramo 1: quem esta em v_tribe_active_members   <- filtra kind='volunteer'
  UNION
  -- ramo 2: quem tem presenca E member_status IN ('observer','alumni','inactive')
)
```

O visitante nao entra em nenhum: nao esta na view de vagas (e observer por ENGAJAMENTO, nao por
`member_status`), e o `member_status` dele e `active`. O ramo 2 ja e o precedente do que se quer —
ele existe para mostrar quem compareceu sem ser membro efetivo.

**Decisao do dono: SECAO PROPRIA**, separada da grade principal, fora da metrica da tribo. A razao
esta registrada e vale repetir: na grade principal seria preciso excluir o visitante em QUATRO
agregacoes (`eligibility`, `member_stats`, `detractor_calc` e a taxa), cada uma um ponto de
esquecimento; com secao propria, `grid_members` fica intacta e a prova de que a metrica nao mudou e
que o codigo dela nao foi tocado.

---

## 3. O que NAO fazer: a view `v_initiative_roster` fica fechada

⚠️ A tentacao obvia da #2334 era abrir a view (ela exclui observer nas duas pontas). **Nao abra.**
Medido: **12 funcoes** a consomem (`pg_depend` confirma que nenhuma OUTRA view depende dela):

| grupo | funcoes |
|---|---|
| **autoridade** | `_can_sign_gate`, `_can_manage_recurring_rule` |
| **contagem** | `get_initiative_roster_count`, `get_tribe_stats`, `get_initiative_stats` |
| **gamificacao** | `get_tribe_gamification`, `get_initiative_gamification` |
| **paineis** | `exec_tribe_dashboard`, `exec_cross_initiative_comparison`, `get_gp_cohort_health`, `get_initiative_detail`, `get_initiative_roster_members` |

Os dois portoes de autoridade sao seguros hoje porque exigem `role = 'leader'` explicitamente —
medido, e era a duvida que valia medir. Mas bastaria UM consumidor de contagem esquecido para o
visitante contar em silencio. A #2335 uniu os visitantes so na RPC da tela: risco de 12 para 1.

---

## 4. Licoes de processo desta sessao (e duas mordidas reais)

1. **`test:structural` antes de abrir PR.** Pulei, e o meta-guard **#1932** pegou no CI o que teria
   pego na maquina: ao redefinir `get_initiative_roster_members`, o guard `1217` passou a afirmar
   sobre o corpo de agosto — verde sobre codigo morto. Consertado (le a captura vigente; o ACL saiu
   do corpo porque `CREATE OR REPLACE` PRESERVA grants).
2. **`browser_guards` e NAO-DETERMINISTICO.** Provado: mesmo SHA, re-run isolado, verde. Falhou 2x
   antes com sintomas DIFERENTES (`/webinars`, depois `#sel-denied`), sempre precedido de
   `Unable to resolve BaseLayout.astro` no workerd. Nao reproduz local (as 3 paginas dao 200).
   **Fica sem explicacao** por que o erro apareceu 3x na branch e 0x no run verde da main — candidato
   a investigacao propria, porque job assim gasta a confianca de quem o le.
3. **Teste de mutacao achou defeito nos PROPRIOS guards, duas vezes.** Na #2330 o regex casava o
   `CREATE TABLE IF NOT EXISTS` em vez do filtro; na #2335, `/is_visitor/` solto passava com o campo
   REMOVIDO do UNION (a string sobrevivia nos comentarios). ⇒ **Mutacao obrigatoria, e a mutacao tem
   de mudar o arquivo de fato** — uma das minhas nao mudou e eu quase li o verde como prova.
4. **Mutar o ARQUIVO nao exercita camada VIVA.** Ela le o banco, que continua com a versao aplicada.
   Camada viva se prova por evidencia direta + controle positivo, nao por mutacao de arquivo.
5. **Quatro vezes li uma medicao que nao podia falhar como confirmacao**: `grep` com regex invalida
   (saida vazia lida como "nada encontrado"), `0 passos` por recorte errado (juncao por candidatura
   e nao por pessoa), a camada B do guard, e bytes comparados contra chars. Todas pegas, nenhuma por
   disciplina previa.

---

## 5. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh issue list --state open --limit 10
npm run test:structural     # RODE ANTES DE ABRIR PR (a licao 1 acima)
npm run test:verdict        # DOIS blocos; confira SUPABASE_ANON_KEY no .env ou 800+ testes PULAM
```

```sql
-- a #2286: o tamanho real do que e carimbado sem renderizar
WITH renderizados AS (
  SELECT DISTINCT m[1] AS tipo FROM pg_proc p,
  LATERAL regexp_matches(p.prosrc, '''([a-z_]{4,40})''', 'g') AS m
  WHERE p.pronamespace='public'::regnamespace AND p.proname='get_weekly_member_digest'
    AND m[1] IN (SELECT DISTINCT type FROM public.notifications)),
digest AS (SELECT type, count(*) linhas,
  count(*) FILTER (WHERE digest_delivered_at IS NOT NULL) carimbadas
  FROM public.notifications WHERE delivery_mode='digest_weekly' GROUP BY 1)
SELECT (SELECT count(*) FROM digest) tipos, (SELECT sum(carimbadas) FROM digest d
  WHERE d.type NOT IN (SELECT tipo FROM renderizados)) carimbadas_sem_renderizar;

-- o estado do arco
SELECT (SELECT count(*) FROM public._credly_unmapped_rows()) detector_credly,       -- esperado 0
       (SELECT count(*) FROM public.credly_badge_decisions) decisoes,               -- 39
       (SELECT count(*) FROM public.engagements WHERE kind='observer' AND status='active'
        AND initiative_id IS NOT NULL) visitas_ativas,                              -- 2
       (SELECT count(*) FROM public.engagements WHERE kind='volunteer' AND role='leader'
        AND status='active' AND initiative_id IS NULL) lideres_em_formacao,         -- 2
       (SELECT count(*) FILTER (WHERE violation_count>0)
        FROM public.check_schema_invariants()) invariantes;                         -- 0
```

---

## 6. Decisoes e acoes que seguem com o dono

1. **Reuniao de sexta (19/09)** com o lider em formacao LIMPO — desenhar o fluxo, nao consertar o
   caso. Criterio: o que sair tem de servir ao outro lider sem retrabalho. Resumo e as 4 perguntas
   estao no card `Decisoes do GP sobre lideres em formacao`.
2. **O onboarding de lider pressupoe tribo que JA EXISTE** (#2334): os 4 passos falam em quadrante,
   artefatos, pagina da tribo e cards "herdados". E fluxo de TRANSICAO, nao de FUNDACAO.
3. **Card digest orfao** — ja aposentado em maio por decisao registrada; sobra decidir se a funcao
   `generate_weekly_card_digest_cron` some de vez.
4. **3 termos pendentes**: dois bloqueados por campos de cadastro, um deles tambem sem conta. Os
   e-mails ja sairam em 17/09.
5. **Dev server orfao** na maquina do dono (pid 898586, desde 09:11) impede `test:browser:guards`
   local. Nao foi morto de proposito — pode estar em uso. `npx astro dev stop` resolve.

---

## 7. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-17_handoff_credly_zerado_visitante_2286_proxima.md`.
> A tarefa e a **#2286** (o digest carimba como entregue o que nenhuma secao renderiza), e depois
> `get_digest_health`, NESSA ORDEM — instrumentar um canal quebrado da um verde que nao significa nada.
> Re-medir a secao 5 antes de escrever. O numero da issue esta 17x subestimado: sao **1277 linhas em
> 27 tipos**, nao 76 em 2.
> **Rodar `npm run test:structural` ANTES de abrir PR** — o meta-guard #1932 pega guard que passou a
> afirmar sobre captura vencida, e foi exatamente o que aconteceu em 17/09.
> Guard novo exige **mutacao que MUDE o arquivo de fato**; duas vezes nesta sessao a mutacao achou
> defeito no proprio guard.
