# Handoff: a jornada de entrada fecha, e a pergunta do dono tinha outra resposta

> **Nada aqui é medição.** Carimbado em 14/09, ~13h BRT. **Re-meça antes de decidir** — os
> comandos estão na seção 7. Repositório público: este documento não nomeia ninguém, por norma.
> O caso que abriu o arco vive sob o identificador opaco `c9c2058d` (candidatura).

**Estado ao encerrar, para COMPARAR:** `main 86f29b7b` · **PR #2276 aberta** (aguardando
`CI Validate`) · issues novas: **#2275**, **#2277** · **#2273 fechada pela PR**.

---

## 0. O que esta sessão entrega

A **#2273** inteira: os dois defeitos e o ponto cego que a medição revelou atrás deles. Migration
`20260914120519` aplicada, EF `send-portal-account-setup` deployada, PR #2276.

Mas a entrega não é o que mais importa neste handoff. **A medição mudou o desenho que a própria
#2273 propunha**, e é isso que a próxima sessão precisa saber antes de tocar em qualquer coisa
deste arco.

---

## 1. A pergunta do dono tinha uma resposta, e não era a que o handoff anterior supunha

> *"Quero explicação do porquê algo que funciona parou de funcionar."*

**Não parou.** E eu quase consertei um mecanismo íntegro.

`members.auth_id.first_link` tinha 68 eventos e o último em **29/08** — 16 dias de silêncio. Lido
sozinho, isso é uma regressão com data, e eu cheguei a escrever exatamente isso antes de medir o
controle.

O controle é **quantas pessoas ficaram ELEGÍVEIS ao vínculo por semana** (existe `auth.users` com
o e-mail do membro, e `auth_id` nulo):

| semana | elegíveis | ligaram |
|---|---|---|
| 29/06 | 11 | 11 |
| 06/07 | 6 | 5 |
| 10/08 | 3 | 3 |
| 24/08 | 6 | 6 |
| 07/09 | **1** | 0 |

**27 elegíveis desde 29/06, 25 ligados.** O zero de setembro é fila seca. Os três mecanismos de
reconhecimento estão vivos: `first_link` 68, `rotated_secondary` 14, `claim` self-service 2.

Isto virou memória: `reference-evento-que-cai-a-zero-meca-quantos-ficaram-elegiveis`.

---

## 2. As 10 pessoas, caso a caso. E seis delas não eram a pergunta

O handoff anterior mandou, com razão, não usar agregado. Caso a caso, o grupo se desfaz:

| classe | n | o que é |
|---|---|---|
| `chapter_liaison` criados administrativamente | 3 | nunca tiveram candidatura nem token |
| `guest` idem | 1 | tem conta criada em 01/06, nunca voltou ao site |
| **fixtures de teste órfãs de 27/08** | **2** | não são pessoas — issue **#2275** |
| **candidaturas aprovadas** | **4** | a população real da #2273 |

As quatro que importam:

| candidatura | token | sinal |
|---|---|---|
| `c9c2058d` | vivo até 28/09, `access_count` **0** | o caso do arco; ainda não abriu |
| `20305c65` | expirou 10/09, `access_count` **1** | **clicou e não virou conta** |
| `4303cd58` | expirou 09/09, `access_count` **3** | clicou 3×, TEM conta, e não está ligada |
| `c78b885b` | expirou 19/05, `access_count` 0 | janela fechou; membro hoje `inactive` |

⚠️ **O caso mais forte do arco não é o `c9c2058d`.** É o `20305c65`: clicou no portal e não
conseguiu entrar. E o `4303cd58` é o segundo: fez login em **11/09** com o membro criado em
**10/09**, e-mail idêntico, e continua sem vínculo.

---

## 3. O que decidiu o desenho, e por que duas opções da seção 5 anterior morreram

**88% das contas nascem de OAuth**: google 107, linkedin_oidc 31, azure 7, contra 23 de OTP por
e-mail. A pessoa **já criava conta sozinha**. O que faltava era o portal dizer **com qual e-mail**.

Isso derruba a premissa "ninguém cria conta" e reformula a opção 1: o portal não precisa de um
quarto mecanismo de identidade, precisa de conectar aos três que funcionam.

⚠️ **E o e-mail é a armadilha inteira.** O reconhecimento liga conta nova a membro pelo **primário
do MEMBRO**. Quem entra por outro endereço nasce ghost. Por isso, no que foi entregue, **nenhuma
superfície aceita e-mail vindo do cliente**: a RPC não o recebe por parâmetro, e a EF re-resolve
tudo do zero.

**Decisão do dono, 14/09:** OAuth em destaque **e** magic link como alternativa (as duas), e o
reconciliador entra como **detector que alerta**, nunca como algo que liga sozinho.

---

## 4. O ponto cego, que não estava na #2273 e é o achado estrutural

**O reconhecimento só existe no navegador da pessoa.** `get_member_by_auth` (step 3) e
`try_auto_link_ghost` fazem o `first_link`, e as duas só rodam quando o navegador DELA carrega o
`Nav`. Quem cria conta e não volta ao site fica sem vínculo indefinidamente, e **nada no servidor
percebe** — não há erro, não há log, não havia detector.

A condição é verificável inteiramente em SQL, e mesmo assim ninguém no servidor a consultava.
`detect_unlinked_accounts` passa a alertar. Ela **não liga**: ligar por match de e-mail no servidor
reintroduziria o ramo que o P168 R3-a removeu do cliente depois do incidente de identidade.

Memória: `reference-mecanismo-que-so-roda-no-navegador-da-pessoa-nao-tem-quem-o-acione`.

---

## 5. O que foi entregue, e como foi provado

- **Defeito A** — `consume_onboarding_token` devolve `step_catalog` (11 linhas do catálogo, 3
  línguas). Aditivo: `cycle.onboarding_steps` fica no payload, porque RPC e componente são dois
  veículos de deploy e a versão antiga renderizaria `[object Object]`.
- **Defeito B** — o ramo `isApproved` mostra o e-mail mascarado, abre o login ali mesmo, e oferece
  a segunda via (`request_portal_account_setup` + EF). Teto de 3/hora por candidatura.
- **A RPC não consome o token.** `access_count` é o único sinal de clique no e-mail, e somar um
  pedido de acesso ali apagaria a métrica de intenção — a métrica que produziu a tabela da seção 2.

**Exercido ponta a ponta** contra fixture em domínio reservado: RPC → pg_net → EF → `generateLink`
→ envio, com audit de pedido e de envio. Uma medição corrigiu o código: `generateLink` com
`magiclink` **cria** a identidade para endereço inexistente, então o fallback `invite` é rede, não
caminho esperado.

**7 camadas de teste.** A camada B existe porque um teste que só afirmasse "tem rótulo" ficaria
verde pelo fallback — ela exige reprovação com catálogo vazio, com chave ausente e com **rótulo
igual à chave**. A E exerce os grants com a chave anon, com controle positivo e negativo.

---

## 6. Duas coisas que esta sessão quebrou e consertou, e valem como aviso

1. **A sonda ponta a ponta derrubou um guard de outra onda.** Exercer o caminho de sucesso escreveu
   em `auth.users`, `campaign_recipients` e `campaign_sends`. Limpei a entidade e esqueci as
   laterais; horas depois o **#1437** reprovou, e a linha era minha. Memória:
   `reference-exercer-em-producao-deixa-rastro-nas-tabelas-laterais`.
2. **O guard estático casou o próprio comentário.** A camada G afirma a ausência de
   `'open-auth-modal'`, e o arquivo cita essa string para explicar por que ela não deve existir.
   Resolvido com `maskJsComments`. É a armadilha já registrada, e ela reaparece.

---

## 7. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr view 2276 --json state,mergeStateStatus,statusCheckRollup
gh issue view 2275   # fixtures orfas contadas como membro
gh issue view 2277   # rede bridge do Docker

# a rede do container, que decide se da para deployar daqui
docker run --rm redis:7-alpine sh -c 'ping -c2 -W3 1.1.1.1 && echo OK'
# se falhar: supabase functions deploy <fn> --use-api --project-ref <ref>
```

```sql
-- o caso do arco: access_count > 0 significa que a pessoa clicou
SELECT issued_at, expires_at, consumed_at, access_count
FROM onboarding_tokens WHERE source_id::text LIKE 'c9c2058d%' ORDER BY issued_at DESC;

-- o ponto cego, agora com detector proprio
SELECT public.detect_unlinked_accounts();

-- o CONTROLE da secao 1: elegiveis x ligados por semana. Sem ele, o zero mente.
WITH pares AS (
  SELECT m.auth_id IS NOT NULL AS ligou, greatest(m.created_at, u.created_at) AS elegivel_desde
  FROM members m JOIN auth.users u ON lower(u.email) = lower(m.email)
)
SELECT date_trunc('week', elegivel_desde)::date AS semana,
       count(*) AS elegiveis, count(*) FILTER (WHERE ligou) AS ligaram
FROM pares WHERE elegivel_desde >= '2026-07-01' GROUP BY 1 ORDER BY 1;
```

---

## 8. O que fica aberto

- **PR #2276** aguardando `CI Validate`. Migration e EF **já estão em produção**, de propósito:
  sem elas a superfície não existiria e o componente chamaria o vazio.
- **#2265 H4** — lembrete antes do vencimento para quem deixou a janela fechar. Não é desta onda.
- **#2275** — as duas fixtures órfãs. Apagar membro é operação de ciclo de vida; a decisão ficou
  registrada em vez de executada em silêncio.
- **#2277** — a bridge do Docker. Contorno (`--use-api`) funciona e foi exercido hoje.
- **As quatro pessoas seguem sem conta.** A plataforma agora tem por onde recebê-las, mas nenhuma
  foi contatada nesta sessão. O token de `c9c2058d` vence em **28/09**; os outros três já
  expiraram e precisam de reemissão (`selection_decide action='reissue_onboarding'`) — **decisão do
  dono**, porque manda e-mail para pessoa real.

---

## 9. A lição do arco

**Uma série que cai a zero e um mecanismo que quebrou produzem exatamente o mesmo gráfico.** O que
os separa é o denominador de elegíveis, e ele nunca está na série. Custou quase uma reescrita de um
mecanismo com 68 acertos.

E a segunda, do mesmo tamanho: **agregado de 10 é ruído — e de 10, seis não eram a pergunta.** Duas
nem eram pessoas. O caso a caso não foi rigor extra; foi o que evitou desenhar para a população
errada.
