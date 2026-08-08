# Painel de controle — sessão de 07/08/2026

> Documento vivo. Existe para que o plano original (Blocos A→D do prompt de arranque) não se perca
> conforme entram assuntos novos. **Atualizar a cada bloco fechado.**
> Legenda: ✅ feito · 🟡 parcial · ⛔ não iniciado · ⏸️ suspenso por decisão · 🔴 espera decisão do Vitor

---

## 1. O plano original (ordem acordada, não reordenar)

| Bloco | Escopo | Estado |
|---|---|---|
| **A** | Action items e governança da reunião de 06/08 | ✅ **medido E lançado** (07/08 16:21) |
| **B** | Auditoria de cobertura do MCP ao longo da jornada | ✅ **fechado** (07/08 16:55) — detalhe logo abaixo, em "Bloco B, detalhado" |
| **C** | Vídeo: editar → YouTube (não listado **E** na playlist) → publicar → lançar action items | ✅ **FECHADO** (07/08 20:50) — e ampliado: a #8 de 23/07, que estava sem ata e sem gravação há 15 dias, foi fechada junto. Ver seções 2.2, 2.3 e 2.4 |
| **D** | Documentação em dia ao longo de tudo | ✅ em dia — lições da sessão registradas na **[LL] #588** |

### Bloco A, detalhado

| # | Item | Estado | Onde está |
|---|---|---|---|
| A1 | Extrair action items por líder | ✅ **23 itens**, com carimbo de tempo | `docs/planning/2026-08-07_ata_lideranca_06ago_action_items_governanca.md` |
| A2 | Lançar os action items nas superfícies | ✅ **ata publicada + 23 ações rastreáveis** no evento `Reunião de Liderança #9` (22 abertas, 1 resolvida, 19 com dono, 4 com prazo) | evento `2db03506` |
| A3 | Governança: confrontar o dito com o banco | ✅ medido, 7 pessoas | ata, seção 2 |
| A4 | Tarefa pendente do bloco anterior: flag de entregável + cards sem data por tribo | ✅ medido, 12 tribos | ata + #1661 |

### Bloco B, detalhado (fechado 07/08 16:55)

Auditado **exercitando as portas** pelo conector semântico `nucleo-ia` (53 tools), contra a jornada concreta. Mapa completo no comentário da **#1588**.

| etapa da jornada | veredito |
|---|---|
| ata · decisões · action items · governança | ✅ coberto |
| reunião (evento) · cards · presença · ciclo seletivo | 🟡 parcial |
| transcrição/gravação · agenda/recorrência · portfólio/publicação | 🔴 sem porta ou quebrado |

**Aberto:** #1669 (ciclo fantasma no `housekeeping` + `tribe_deliverables` sem escrita) · #1670 (6 ponteiros mortos em `next_actions`) · #1671 (`is_portfolio_item` legível só card a card).

**Comentado com medição:** #1661 (duas falhas empilhadas; a que dispara é `id` ambíguo, não `pb.cycle_code`) · #1658 (MCP: 7 RPCs de recorrência, 1 exposta; tribos 1, 6 e 14 confrontadas contra a regra viva) · #1601 (`update_event` tem 15 params e 0 referências no MCP; 204 de 214 eventos sem gravação) · #1586 (Rogério passa em todos os guards).

**Correções ao que estava escrito:** `interview_manage action='stage_override'` **está vivo** (o manifesto do conector estava em cache). E o Rogério **é** destravável por `execute_sql` — o handoff do Bloco A dizia que não era. Ver seção 3.1.

---

## 2. Entregue nesta sessão

### 2.2 Bloco C — vídeo (07/08 20:20)

**Vídeo publicado:** https://youtu.be/8GJaTby6eRo · não listado · playlist `Ciclo 4 (2026/2) - Reunião de Liderança` (`PLfWCBF5VAWZM`, criada nesta sessão, não listada) · 33 capítulos.

Edição, com tudo medido antes e depois:

| sinal | cru | publicado |
|---|---|---|
| duração | 4530,54 s (75min30s) | **4341,92 s (72min21s)** |
| Integrated | -15,5 LUFS | **-14,2 LUFS** (alvo -14) |
| True peak | **+0,9 dBFS** (estourando) | **-1,1 dBFS** |
| LRA | 7,1 LU | 5,8 LU |
| vídeo | h264 1280x720 | idêntico, `-c:v copy` (sem perda de geração) |

Corte em **188,625 s**, num keyframe dentro do silêncio, tirando 3min08s de conversa política de pré-reunião (Venezuela, comércio global) que antecedia a abertura. Decisão sua.

⚠️ **A armadilha registrada não valia aqui.** [[reference-webinar-recording-publish-traps]] dizia "áudio ~10 dB abaixo no vídeo inteiro" e mandava usar `afftdn`. Medido nesta gravação: o nível estava a **1,5 LU** do alvo e o ruído de fundo em -88 dB nos silêncios. O defeito real era **o pico passando de 0 dBFS**. Denoise **não** foi aplicado, porque não havia ruído a tirar.

**Re-carimbo:** os 23 action items traziam o carimbo cru dentro da própria descrição. Deslocados em -188,6 s por um único UPDATE (`meeting_action_items` só tem trigger de XP em `resolved_at`, então não gerou linha de auditoria). A ata foi reancorada junto, preservando os dois números que **não** são posição: `3min36s` (diferença entre duas criações de evento) e `75min30s` (duração da gravação crua).

**Vínculo:** feito por SQL, por decisão sua ("se não tem rota via MCP é um puta gap, faça por SQL e abra o issue"). A rota não existe mesmo, remedida contra o **servidor deployado**: `update_event` tem 0 referências, `p_youtube_url`/`p_recording_url`/`p_is_recorded` 0, e `youtube_url`/`recording_url` só aparecem em **leitura**, inclusive num filtro `has_recording`. A issue já existia e está aberta: **#1601**, escalada com a medição.

Custo pago, medido no log do próprio evento: a ata publicada às 16:18 **pelo MCP** gravou `actor_id: 880f736c`, `source: user`; o link às 20:30 **por SQL** gravou `actor_id: null`, `source: system`. Mesmo evento, mesmo dia, mesmo autor humano. O que decide se o log guarda o nome é só a existência da rota.

### 2.3 Reunião de Liderança #8 (23/07) — fechada retroativamente

Descoberta ao varrer os 109 uploads do canal: **nenhuma liderança do ciclo 4 tinha sido publicada**, e a #8 estava com `is_recorded=true`, sem link, **sem ata** e com **zero** action items, havia 15 dias.

| entrega | resultado |
|---|---|
| gravação | achada no Drive (739 MB) → **https://youtu.be/5LD9xsXXKjo**, não listada, na playlist, 38 capítulos |
| edição | **sem corte** (a reunião começa em `00:00:03` e a transcrição fecha em `01:32:12`, batendo com os 5532,96 s). Áudio de **-15,9 → -14,2 LUFS**, pico de **+0,5 → -1,1 dBFS** |
| ata | publicada pelo MCP, com ator nominal |
| action items | **18**, com carimbo; 2 já fechados com prova, 16 abertos, 15 com dono |
| mapeamento board/card | na ata, seção 1.1 |

🟢 **Brinde:** a transcrição oficial do Meet (aba do doc `Notes by Gemini`) tem **falantes identificados** — melhor que rodar WhisperX, que não separa quem fala. Não foi preciso transcrever nada.

🔴 **Dois achados do mapeamento:** o webinar de patente e PI **existe** em `webinars` parado em **28/05** com status `planned`, uma data que passou há 71 dias, e **não há nenhum webinar em setembro**. E o card do framework do Marcos está com `forecast_date` **08/09**, três semanas depois do ~18/08 que ele se comprometeu na reunião.

⚠️ **Presença da #8 não sustenta leitura:** 14 pessoas falaram, existem 8 linhas, e **7 falaram sem registro** (Vitor, Fabrício, Roberto, Adailson, Hayala, Sarah, Jefferson).

### 2.4 Fechamento da série de gravações e higiene de títulos (07/08 21:00-22:40)

| entrega | resultado |
|---|---|
| playlist `Ciclo 4 (2026/2) - Reuniões Gerais` | **`PLanpm8h-DzgQ`**, pública, com Kick-off + Geral de 30/07 |
| títulos com prefixo `yyyy-mm-dd - ` | **31 → 40**; 9 renomeados, nenhum com data chutada |
| série de gravações | **39 de 40** vídeos datados referenciados |
| eventos com link de gravação | **33 → 39** |
| `recording_type` nulo | **22 → 0** |
| webinars de 2025 criados | `5f7048a5` (11/09) e `fdc8a319` (20/11), em `webinars` |
| PR | **#1673** aberto |

**Decisões suas registradas:** vídeos de intro de tribo e institucionais ficam **fora** da regra do prefixo; o `Macedo_Antonio` é o não listado do LIM LATAM e fica como está; os três "Bem-vindo ao Ciclo 04" em duas playlists **não são erro** (a tribo veio do ciclo anterior com o mesmo tema).

⚠️ **PR #1673 está vermelho por herança, não por defeito próprio.** Prod está à frente do `main` pela migração do #1666, cujo arquivo só existe no **PR #1674**. Os dois gates de drift acusam em qualquer PR aberto hoje. Destrava com o merge do #1674, depois um rebase. Medição completa no comentário do #1673.

⚠️ **O working tree foi levado para a branch da outra sessão** (`fix/1666-consentimento-auditavel`) no meio do trabalho. O commit já estava empurrado, nada se perdeu, e não fiz checkout de volta para não arrancar o diretório de quem está usando.

### Issues abertas (7)

| # | Título curto | Origem |
|---|---|---|
| **#1675** | Bloco de pauta reservado é **apagado** junto com o evento por `ON DELETE CASCADE`, sem aviso ao dono e sem ator no log. Prova: o único `delete` da tabela de auditoria é "Calculadora de Token" do Marcos, 20/07 | ata da #8 |
| **#1676** | Duplo clique no criador de recorrência gera a série duas vezes: **65 eventos apagados à mão em 3 dias**, em 3 séries | ata da #8 |
| **#1672** | Briefing da reunião conta 22 ações pendentes e entrega **0**: o #1548 corrigiu 1 das 4 subqueries escopadas de `get_meeting_preparation`. 84 eventos org-wide, 24 briefings, 431 aparições suprimidas | Bloco C, item 4 |
| **#1660** | Falta simples não tem como ser gravada: `mark_member_present(false)` APAGA a linha desde 19/05 | Ana, 23min05s |
| **#1661** | Portfólio Executivo não responde "quais são os webinars": `get_portfolio_items` quebra em 100% (42703) | Vitor, 67min05s e 69min18s |
| **#1662** | Filiação é conversão, não porteiro: painel de ROI alimentado por `Promise.resolve(null)` | regra de produto do Vitor, 07/08 |
| **#1664** | Fila "Reservas de entrevista sem candidatura": 11 das 31 acionáveis são do operador e o rótulo é falso | print do Vitor, 07/08 |

Comentário cruzado no **#1657** ligando a face de escrita (#1660) à de leitura.

### Documentos

| arquivo | o que é |
|---|---|
| `docs/planning/2026-08-07_ata_lideranca_06ago_action_items_governanca.md` | ata + 23 action items + tabela de governança |
| `docs/specs/SPEC_TROCA_DE_TRIBO_JANELA_E_ALERTA.md` | por que o offboard do Marcelo foi suspenso + correção em 4 waves |
| `docs/planning/2026-08-07_CONTROLE_SESSAO.md` | este arquivo |
| memória `feedback-only-term-signing-is-gated-by-pmi-affiliation` | a regra de filiação/conversão |

---

## 3. Decisões — despachadas em 07/08 16:15-16:21

| # | Decisão | Desfecho |
|---|---|---|
| 1 | Fabrícia Maciel | ✅ **offboard concluído** → `alumni`, 1 engajamento encerrado, 1 card reatribuído ao Fernando, certificado de alumni emitido |
| 2 | Vinicyus Saraiva | ✅ **offboard concluído** → `alumni`, 1 engajamento encerrado, sem cards abertos |
| 3 | Marcelo Pereira | ✅ **movido para a tribo 5** via `engagement_write` (add na 5 → remove da 13). `tribe_id=5` e engajamento `5:active` casam, sem órfão |
| 4 | 23 action items | ✅ **ata publicada + 23 ações rastreáveis** no evento `Reunião de Liderança #9` |
| 5 | Rogério Severo | ✅ **RESOLVIDO** 07/08 17:00 — convite reemitido com token governado (expira 21/08). Ver seção 3.1 |

### 3.1 ✅ Rogério Severo — RESOLVIDO em 07/08 17:00 UTC

Por decisão sua no fechamento do Bloco B, executado por `execute_sql` (opção 2 das três). `selection_rescue_unbooked_invite` passou em todos os guards, `gate_mode: full`, `email_sent: true`.

| sinal | antes 17:00:06 | depois 17:00:20 |
|---|---|---|
| token `interview_booking` | **0** | **1**, expira 21/08 |
| `interview_auto_rescue_count` | 0 | 1 (cap consumido) |
| `cutoff_approved_email_sent_at` | 31/07 | 07/08 17:00:11 |

**Custo pago, e anotado na #1586:** duas linhas de `admin_audit_log` com `actor_id: null` e `dispatch_source: 'cron'`. 4ª ocorrência do defeito.

**Achado de brinde:** a linha de auditoria de 31/07 não tem `link_kind` nem `token_prefix`, enquanto a de hoje tem `governed_token` / `XwiUjRYp`. Está provado no próprio log que o e-mail de 31/07 saiu sem token. ⚠️ O avaliador resolvido mudou (Fabrício → Fernando), então os dois e-mails levam a calendários diferentes.

<details><summary>Diagnóstico original (histórico)</summary>

Único dos 11 `interview_pending` sem token. Nota **191,50**, a 2ª maior. Despacho de 31/07 saiu **sem token emitido** (o `GATE_NO_AI` recusou a emissão e o e-mail foi assim mesmo) — é isso que o Fabrício leu como "abriu duas vezes e não marcou".

Às **04:01 de 07/08 você reemitiu manualmente** para 4 (Jonas, Marina, Rafael, Patrícia); o Ramon pegou o dele às 03:23 por tráfego de teste. **O Rogério ficou fora da leva.**

Não consigo fazer por dois motivos, ambos medidos:
- `issue_interview_booking_token` **não está exposta no MCP** (só `get_application_gate_attempts`, que a menciona na descrição)
- ela é gateada por `auth.uid()`, então service_role não passa
- `interview_manage action='rescue'` **não cobre**: só aceita `interview_scheduled`, e ele está em `interview_pending`

**Ação:** mesma tela e mesmo botão que você usou às 04:01, para o Rogério. `application_id` `4303cd58-bd5c-49e7-ba04-a3ded1ec236c`.

</details>

> ⚠️ **Corrigido no Bloco B (07/08 16:53), e depois EXECUTADO às 17:00.** O parágrafo acima está incompleto: existe `selection_rescue_unbooked_invite`, que atende exatamente `interview_pending`, e o Rogério passa em **todos** os guards dela — ciclo `cycle4-2026` aberto, status `interview_pending`, `interview_auto_rescue_count = 0`. O `GATE_NO_AI` que o recusou em 31/07 saiu de produção com o #1640. Ela **não** tem superfície no MCP (é a #1586), então por `execute_sql` a auditoria grava `actor_id = NULL` e `dispatch_source: 'cron'` — um ato seu registrado como automação, a 4ª ocorrência. **São três opções, não duas:** (1) UI, auditoria limpa; (2) `execute_sql` agora, com o registro falso anotado na #1586; (3) consertar a #1586 primeiro e usar a porta certa, que pelo conector sai com ator nominal. Não executei nada. Medição completa no comentário da #1586.

### 3.2 Ainda sem resposta

| item | situação |
|---|---|
| Issue da defasagem de `vep_opportunities` | metadados de vaga de 01/04 exibidos no admin como vivos (42 vagas × 67 pessoas). Perguntado, sem resposta |
| Responder a Maria Driele | resolvido sozinho: candidatura de 16/07, entrevista concluída 04/08, `final_eval` com 157 (corte 154,7). Opcional |
| Confirmação Adailson × Jefferson | o action item ficou **aberto de propósito**: o Marcelo já foi movido por decisão sua, mas os dois líderes ainda não conversaram |

---

## 4. Assuntos que entraram fora do plano (e o que fizeram com ele)

| assunto | o que gerou | custou o quê ao plano |
|---|---|---|
| Offboard do Marcelo Pereira | SPEC + ⏸️ suspensão | ~30 min |
| 5 PDFs de e-mail | 5 casos medidos, 2 viraram decisão | ~20 min |
| Regra de filiação/conversão | auditoria + memória + #1662 | ~30 min |
| JSON do VEP + tabela de reservas | Maria Driele localizada + #1664 | ~30 min |

**Nenhum deles avançou os Blocos B ou C.** É por isso que este arquivo existe.

---

## 5. O que sobra, e de quem é

Os quatro blocos do plano estão fechados. O que resta não é continuação deles.

**Esperando merge alheio:** o **PR #1673** precisa do **#1674** (#1666) entrar primeiro; depois, rebase. Não é desta lane mergear.

**Dos líderes:** **38 action items abertos** (16 da #8, 22 da #9), todos com carimbo e a maioria com dono.

**Do Vitor, nominalmente:**

| item | estado medido |
|---|---|
| Webinar de patente e PI | 🔴 linha em `webinars` parada em **28/05** com status `planned`, data vencida há 71 dias. **Zero** webinares agendados em setembro |
| Transparência das aplicações a eventos | 🔴 sem card; existe só no quadro de alinhamento com o Ivan |
| Varrer cards marcando entregável + metadata | aberto desde 06/08 |
| Adicionar líderes como gestores do canal | aberto desde 06/08 |
| Recorrência do Paulo (quinzenal → semanal) | aberto desde 06/08 |

**Decisões que ficaram com você:**

- Card do framework do Marcos com `forecast_date` **08/09**, três semanas depois do ~18/08 que ele se comprometeu em 23/07. Confirmar com ele ou ajustar.
- **7 pessoas falaram na #8 e não têm registro de presença** (Vitor, Fabrício, Roberto, Adailson, Hayala, Sarah, Jefferson). Dá para inserir, mas é dado de presença e não deve ser fabricado sem palavra sua.

---

## 6. Estado do repositório

- `origin/main` em **`6221e990`** (o #1642 e o #1649 entraram às 20:38)
- **PR #1673** (playlists do ciclo 4 no SSOT) aberto, 1 arquivo, `validate` vermelho **por herança** — ver seção 2.4
- **PR #1674** (#1666, consentimento auditável) aberto pela outra sessão; é ele que destrava o #1673
- **PR #1647** (Paulo, #1644 + #1645) segue **aberto**, vermelho por falhas provadas pré-existentes. É da main lane decidir
- **#1637** Dependabot astro 6→7: **não mergear** (política #611)
- ⚠️ O working tree está na branch **da outra sessão**. Conferir `git log -1` antes de qualquer `checkout -b`
- Os `docs/planning/*` desta sessão seguem **não commitados**, e as **atas continuam fora do git de propósito**: o repositório é público e elas nomeiam voluntários com juízo de desempenho, motivo de desligamento e estado de saúde

---

_Atualizado em 07/08/2026, 22:45._
