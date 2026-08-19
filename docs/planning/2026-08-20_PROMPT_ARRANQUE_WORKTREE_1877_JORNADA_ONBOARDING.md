# Prompt de arranque: worktree da #1877, auditoria da jornada de onboarding

> Colar numa sessão NOVA, em worktree própria. **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> Esta worktree **não mergeia**. Ela entrega handoff + PR verde; a sessão principal faz o QA e o merge.

---

## Missão

Auditar a jornada de onboarding **exercendo-a**, agrupar o que já existe aberto, e devolver o material
para uma sessão de planejamento. **Não desenhar a melhoria.** Metade das perguntas da Diretoria já tem
resposta "existe e não é usado", e desenhar por cima disso constrói a segunda cópia do que está lá.

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em 19/08/2026, entre 21:20 e 22:00 UTC.
Re-meça com tool call na mesma volta em que o número entrar numa conclusão, issue ou comentário.

Regras de varredura que já custaram caro **nesta investigação**:

- 🔴 **Contar da tabela de LINHAS em vez do CATÁLOGO produz um denominador que não é o do produto.**
  Consultei `onboarding_progress` direto, contei 12 linhas e conclui "4 de 12" sobre um membro que a
  plataforma mostra como **4 de 7**. Publiquei a conclusão errada na #1875 e tive que corrigir. O
  catálogo é `onboarding_steps`; a tabela de progresso aceita qualquer `step_key`.
- 🔴 **Ausência de dado só vale COM o controle do campo.** Meça a taxa de preenchimento na população
  antes de afirmar que algo não existe.
- 🔴 **`instrumented` separa "não mediu" de "não aconteceu".** Vale para toda tabela que tenha a coluna.
- ⚠️ **Ler código não é exercer o caminho.** A pergunta "o candidato consegue X?" só se responde
  **logado, com o estado dele**. Foi assim que o beco sem saída apareceu.

---

## O que JÁ está medido. NÃO refaça.

### O passo 5 é beco sem saída sem tribo

`src/components/onboarding/OnboardingChecklist.tsx`:

```jsx
{s.step_id === 'meet_tribe' && member?.tribe_id && (
  <a href={`${lp}/tribe/${member.tribe_id}`}>🔬 Visitar tribo</a>
)}
```

Sem `tribe_id`, o botão **não renderiza**. O passo aparece sem ação e sem explicação. O comentário no
mesmo arquivo promete o oposto: *"so no step is ever a dead-end"*.

### O fluxo de escolha e aprovação existe, e parou

| notificação | destinatário | linhas | mais recente |
|---|---|---|---|
| `tribe_request` | o líder | 40 | **20/07/2026** |
| `tribe_request_reviewed` | o candidato | 39 | **20/07/2026** |
| `tribe_request_nudge` | lembrete | 2 | 10/07/2026 |
| `engagement_welcome` (controle) | — | 142 | **19/08/2026** |

O componente que oferece a escolha é `TribeRequestBlock`, e ele mora em **`/workspace`**, não na jornada.

### O catálogo tem 11 passos, não 12

`onboarding_steps`: 7 gerais (`code_of_conduct`, `complete_profile`, `volunteer_term`, `vep_acceptance`,
`meet_tribe`, `start_trail`, `first_meeting`) + 4 só de `tribe_leader` (`leader_*`).
`get_my_onboarding` calcula contra esse catálogo.

### Conclusão por passo, população inteira

| step_key | linhas | concluídas | % |
|---|---|---|---|
| `volunteer_term` | 96 | 91 | 94,8 |
| `first_meeting` | 112 | 101 | 90,2 |
| `complete_profile` | 100 | 85 | 85,0 |
| `vep_acceptance` | 97 | 80 | 82,5 |
| `meet_tribe` | 97 | 71 | 73,2 |
| `code_of_conduct` | 97 | 70 | 72,2 |
| `leader_capture_video` | 13 | 4 | 30,8 |
| **`start_trail`** | **98** | **20** | **20,4** |
| `leader_refine_theme` / `leader_review_tribe` | 13 | 3 | 23,1 |
| `leader_roadmap` | 13 | 2 | 15,4 |
| **5 chaves órfãs** (`accept_terms`, `join_whatsapp`, `kick_off`, `platform_access`, `profile_complete`) | 24 cada | **0** | **0,0** |

As 5 órfãs **não estão no catálogo** e nenhuma tela as lê. São 120 linhas de dívida (#1875).

### Tribos

12 tribos de pesquisa ativas. **6 não publicam nenhum horário de reunião** (Dados em Projetos de IA,
Fluência em IA, Governança Assistida, IA em Projetos & Construção, PMO Inteligente, Produtividade
Aumentada). Menores: Governança Assistida (2), Dados em Projetos de IA (2), Talentos & Upskilling (3).

---

## O TRABALHO: o que NÃO está medido

1. **Exercer a jornada logado**, com um membro sem tribo, e registrar o que ele vê em cada um dos 7 passos.
2. **`EntryChapterNudge`** (`src/components/onboarding/`): está montado? Dispara quando? Para quem?
3. **Filiação e capítulo na jornada**: aparece? E a escolha entre múltiplos capítulos?
4. **Não filiado**: a jornada informa que filiar-se é pré-requisito e benefício?
5. **Vídeos**: existe vídeo de tribo que ajude a escolher? (Há `leader_capture_video`, só de líder.)
6. **Por que `start_trail` está em 20,4%.** É o passo visível mais abandonado.
7. **Por que `tribe_request` parou em 20/07.** Mudança de processo, defeito, ou decisão?

---

## Issues a triar (18 levantadas, agrupadas na #1877)

**Jornada:** #1277 · #873 · #1014 · #809 · #1875 · #1171
**Tribo:** #1219 · #1356 · #1777
**Filiação e capítulo:** #1863 · #1866 · #1867 · #1852 · #1581 · #1580 · #1095 · #1358
**Adjacentes:** #1876 · #617

Para cada uma: **é a mesma coisa que outra? está obsoleta? entra no redesenho ou sai?**

---

## Critério de aceite / encerramento

A worktree encerra quando entregar, num documento em `docs/audit/`:

1. **Mapa do estado atual por passo**, com o que o membro **vê** (exercido logado, não lido do código).
2. **As 7 lacunas acima respondidas**, cada uma com medição ou com "não deu para medir, e por quê".
3. **Triagem das 18 issues** em: mesma-coisa-que-#N · obsoleta · entra no escopo · fica fora.
4. **A decisão pendente formulada**, não tomada: qual caminho de entrada em tribo é o oficial,
   `tribe_request` ou alocação administrativa. Hoje existem os dois e nenhum é.
5. **Handoff** em `docs/planning/`, no formato dos existentes, com o que a sessão de planejamento
   precisa decidir.

**PR verde** com esses arquivos. Sem migration, sem mudança de código de produto.

---

## Armadilhas desta worktree

1. 🔴 **NÃO rode a suíte completa.** O `validate` fala com o **banco de produção** e a lane serializa.
   Duas worktrees testando ao mesmo tempo reproduzem a saturação da #1869. Rode só os arquivos que
   você tocar.
2. 🔴 **Banco é somente LEITURA aqui.** Esta worktree audita. Qualquer escrita é da sessão principal.
3. ⚠️ **Repo PÚBLICO.** Nome, e-mail e identificador não entram em issue, PR nem doc. **Conte a população.**
4. ⚠️ **`git checkout -b <nome> origin/main`.** Branch nova nasce do HEAD, e a árvore é compartilhada.
   **Nunca `git add -A`** (há ~60 arquivos não rastreados).
5. ⚠️ **`Fecha #N` NÃO fecha. Use `Closes #N`**, e nunca escreva o padrão sem intenção — escrever
   sobre a palavra-chave dispara.
6. ⚠️ **O build leva 4 a 6 min:** rode em background e confira o `Complete!`.
7. 📌 **`check-invariants` vermelho é ESPERADO.** A violação do #1850 está declarada em
   `tests/helpers/invariant-exceptions.mjs` e o job dedicado roda em modo estrito de propósito.
   O `validate` (required) fica verde. **Não tente consertar isso.**
8. ⚠️ **Merge à main é só da sessão principal.** Entregue PR verde e handoff.

---

## Contexto de fila

A sessão principal está atacando o **#1710 (prazo 24/08)**. Não disputem CI: se você precisar de
`validate`, avise no handoff antes de abrir a PR.
