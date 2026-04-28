# ADR-0063: WhatsApp MCP — non-use policy in production

**Status:** Accepted (2026-04-28)
**Decision date:** p77 session (Decision #3 A — PM-confirmed)
**Supersedes:** —
**Related:** Issue #93 Op #3, Issue #91 (Lídia 4 audios offboarding gap)

---

## Context

Issue #93 Op #3 surfaceou `FelixIsaac/whatsapp-mcp-extended` (41 tools incluindo
reactions, groups, polls, presence, newsletters, media). Use case real
documentado:

- Núcleo opera fortemente em WhatsApp (chats liderança, comms, GP-presidentes
  de chapter)
- Lídia Do Vale (offboarding 22/Abr) deixou 4 áudios WhatsApp não-transcritos
  — gap explícito em #91 G3

Apesar do match operacional real, há riscos materiais que tornam adoção em
produção inviável.

## Decision

**WhatsApp MCP NÃO pode rodar em produção do Núcleo IA.**

Especificamente:
- Não instalar em servidor compartilhado/cloud (nem Supabase Edge Function,
  nem Cloudflare Worker, nem máquina externa hospedando MCP).
- Não exposer no nucleo-mcp como tool acessível por members/líderes.
- Não automatizar ingestão massa de chats WhatsApp.

**Uso autorizado restrito:** GP local (máquina pessoal do Vitor Rodovalho)
para tarefas operacionais 1:1 com consent explícito e escrito de TODOS os
participantes do thread/chat sendo processado.

## Riscos materiais

### 1. API não-oficial — risco de ban

`whatsapp-mcp-extended` opera via `WhatsMeow`, biblioteca Go reverse-engineered
do protocolo WhatsApp Web. WhatsApp oficialmente proíbe automação não-Business
API:

- Conta operadora pode ser banida sem aviso
- Ban afeta toda atividade do número (não só MCP)
- Histórico precedente: bots WhatsApp similares baniram >100 contas em rounds
  de enforcement em 2024-2025

**Severity:** alta. Conta WhatsApp banida do GP poderia paralizar operação
diária do Núcleo (chat liderança, chats de tribo, comms PMI-GO).

### 2. LGPD — dados pessoais de terceiros

Chats WhatsApp contêm dados pessoais de TODOS os participantes — não apenas
do GP. Requisitos LGPD aplicáveis (Lei 13.709/2018):

- **Art. 7º**: base legal explícita necessária (consent escrito ou interesse
  legítimo documentado)
- **Art. 8º**: consent deve ser específico, livre, informado e inequívoco
- **Art. 11º** (dados sensíveis): se chat contiver dados de saúde, religião,
  opinião política, dados raciais, requer consent reforçado

Automação de transcrição/processamento de chats sem consent explícito de
todos os participantes = **violação direta**. Notificação para ANPD pode
gerar multa de até 2% do faturamento anual (cap R$ 50M por infração).

### 3. WhatsApp Terms of Service

Section 2.b dos ToS proíbe:
> "use any non-licensed third-party data extraction methods to access our
> Services [...] including automated bulk message scraping or content
> mirroring"

Uso massivo viola ToS mesmo sem ban automation triggered.

### 4. Auditoria difícil

MCP rodando em máquina local-GP não tem audit_log central nem RLS. Quando
operador (GP) sair (offboarding eventual), conhecimento + logs vão junto.
Sem trilha verificável de "quais chats foram processados e quando", há gap
de accountability institucional.

## Critérios para reabertura desta decisão

A decisão pode ser revisitada quando TODOS os critérios abaixo forem
satisfeitos:

1. **Framework LGPD PMI Brasil aprovado**: PMI institucional (PMI Brasil
   ou PMI Global) emite framework formal autorizando processamento de dados
   WhatsApp em volunteering contexts.

2. **Template de consent**: existe template de consent escrito (português
   legal-grade) que TODOS os participantes assinam antes de inclusão em
   automação. Template revisado por jurídico-externo.

3. **WhatsApp ToS explicitação**: WhatsApp publica explicitamente API ou
   exception para uso research/governance non-profit (improvável short-term).

4. **Audit trail centralizado**: design de audit_log que captura toda
   operação WhatsApp MCP em sistema central acessível à governança PMI
   (não só máquina local do operador).

5. **Backup operacional**: caso conta WhatsApp do GP seja banida, plano
   documentado de continuidade (segunda conta admin, fallback signal,
   etc) testado em drill.

Sem TODOS os 5, decisão de não-uso permanece.

## Uso autorizado (1:1 local)

Permitido SOMENTE em casos específicos onde:

1. **Sujeito é o próprio dono do conteúdo**: ex. Lídia pediu transcrição
   dos próprios áudios para inclusão em exit interview formal — consent
   explícito da única pessoa relevante.

2. **Operação local apenas**: ferramenta roda em máquina pessoal do GP
   (Vitor), não em servidor compartilhado. Output (transcrição) entra
   no sistema via record_offboarding_interview() ou outra RPC oficial,
   com fonte = "WhatsApp transcript via Whisper API local, consent
   <data> + <hash do áudio original>".

3. **Audit imediato no sistema**: cada uso registrado em
   admin_audit_log com action='whatsapp_local_processing' + metadata
   {consent_date, audio_hash, target_member_id}.

## Caso concreto: Lídia 4 áudios

Aplicação dos critérios acima:
- ✅ Sujeito é a própria Lídia (consent implícito ao mandar áudios para
  o GP em contexto de offboarding interview)
- ⚠️ Recomendação: Lídia confirma por escrito (mensagem WhatsApp ou
  email) "autorizo Vitor a transcrever esses 4 áudios para inclusão em
  exit interview" — formaliza o consent
- ✅ Operação local Vitor's machine + Whisper API (não MCP — Whisper é
  speech-to-text, não automação WhatsApp)
- ✅ Output gravado via `record_offboarding_interview` em
  exit_interview_full_text + admin_audit_log

Nesse caso específico, `whatsapp-mcp-extended` ainda **não é necessário**
— Whisper API resolve diretamente. Caso real não escala para "todos chats
do Núcleo" sem reabrir os 5 critérios.

## Audit / governance

- Esta ADR fica linkada em CLAUDE.md (rules) + faq dos prompts MCP
- check_code_schema_drift() monitora se whatsapp-mcp-extended aparece
  em Edge Functions
- Próximo session-log review (2026-Q3) revalida critérios

## Provenance

- Issue #93 Op #3 (2026-04-22) — surfaced opportunity
- Handoff 2026-04-25 — confirmed real use case (4 audios Lídia)
- p77 session 2026-04-28 — Decision #3 A confirmed por PM
- ADR escrito 2026-04-28

Assisted-By: Claude (Anthropic)
