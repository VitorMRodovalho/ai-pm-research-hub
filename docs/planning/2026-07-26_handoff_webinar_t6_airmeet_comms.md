# Handoff 2026-07-26 - Webinar T6 (04/08): Drive, Airmeet e copy de divulgação

Sessão longa, cobrindo 4 pedidos encadeados. Tudo verificado ao vivo (render da página pública, meta
tags por user-agent de crawler, e `drive-list-folder-files` / SQL para o lado da plataforma).

**Evento:** `webinars.id` `4ff3a888-8959-4262-82e6-a6f54ffc3964` · `board_item_id`
`f5a77542-4007-4229-916b-ead5852b20e6` · `events.id` `17497fca-c035-4d9a-8c37-9b721447c9fe`
**Sala:** https://pmilatam.airmeet.com/e/8d047420-8895-11f1-8e9b-61808b940348
**Dashboard de host:** https://www.airmeet.com/airmeets/8d047420-8895-11f1-8e9b-61808b940348/summary
**Kit no Drive:** https://drive.google.com/drive/folders/1aZYlu4iRASdoZ82Kq86Yhdna_P74ns88

## Entregue

1. **Story v2 corrigido.** A esfera ciano colidia com "Fernando Carvalho" (16 px) e o pill da data
   invadia o rodapé (51 px). Medido antes e depois com `qa_measure.py`: **0 colisões, folga de 37 px**.
   QA visual refeito nas 5 peças, não só na que mudou.
2. **Drive resolvido.** Pasta `04 - Webinar Tribo ROI & Portfólio ... (04ago2026)` dentro de
   "Webinar / Painel", com `divulgacao/`, `airmeet-config/`, `fotos-palestrantes/`, `airmeet-speakers/`
   e LEIA-ME. Os 9 originais conferidos byte a byte. `promo_kit_url` preenchido.
   A parede de 25/07 era falsa: as EFs `drive-create-subfolder` / `drive-upload-to-folder` já existiam.
3. **Copy de divulgação**, 8 textos (3 WhatsApp, 3 Instagram, 2 LinkedIn), em
   `docs/_deliverables/2026-08-04_webinar_t6/COPY_DIVULGACAO.md`. Nenhum texto imprime horário POR
   BLOCO, só "19h00 às 20h30", que é igual nas duas grades do briefing: a decisão pendente do Denis
   não obriga a reescrever copy nenhuma.
4. **Airmeet configurado e auditado** (título com acento, Overview, capa, welcome message do evento
   anterior corrigida, lounge banner novo 960x120, waiting screen). Ver `.claude/skills/airmeet-event-ops/`.
5. **3 speakers cadastrados + convites de backstage disparados** (Denis, Fernando, Clendson):
   "Invite sent" / "Registered".

## Pendências reais

### Decisões de gente (bloqueiam trabalho)
- **Aval do owner na v2 das peças** (fotos +44%). Se aprovar: re-renderizar, trocar os 5 arquivos em
  `divulgacao/` no Drive e atualizar `~/Downloads/nucleo-webinar-t6-04ago/`.
- **Denis não respondeu a divergência de horários** (comentário `a22b8ebd-...` no card, de 26/07 02:49).
  Ele respondeu por WhatsApp só a parte dos e-mails. Programação geral (Fernando 19h10, Clendson 19h45)
  x roteiro detalhado (19h05 / 19h40, sem o bloco da tribo). **As peças, o Overview do Airmeet e o
  pack seguiram a programação geral.**
- **Quem apresenta a tribo: Messias OU Fabricio.** Enquanto não decidir, ficam fora dos speakers do
  Airmeet (só os 3 confirmados estão lá) e as duas linhas seguem no CSV para alguém apagar uma.
- **Organization / City / Country do Fernando e do Clendson** seguem vazios de propósito. O domínio
  `nndigital.com.br` sugere a empresa do Fernando, mas sugerir não é saber e isso vai para perfil
  público. Preencher só com o que o Denis confirmar.

### Manuais, minutos
- **Ordem dos speakers na landing** saiu Denis > Clendson > Fernando; a programação tem Fernando
  (19h10) antes. Ajuste por arrastar em "Rearrange speakers". Não automatizei: drag-and-drop.
- **Dois arquivos v1 sobrando** em `airmeet-speakers/` no Drive (`LEIAME.txt` e
  `Speakers_Airmeet_webinar-t6-04ago2026.csv`), superados por `LEIAME_26jul_ATUALIZADO.txt` e
  `Speakers_Airmeet_t6-04ago2026_26jul_COM-EMAILS.csv`. A lixeira pela UI do Drive não registrou a
  seleção nessa subpasta em 4 tentativas; parei em vez de insistir.

### Não iniciado
- **Publicar a copy.** Nada foi agendado nem publicado. Antes disso: aval da v2 (é a imagem que vai no
  post) e, se possível, a resposta do Denis. Publicação por canal segue a matriz de comms.
- **`sympla_event_url` e `comms_kickoff_at` seguem NULL** (confirmado em query nesta sessão).
- **Checklist do card: 13 de 15 abertos.** "Desenvolver material publicitário" (vence 28/07) está de
  fato pronto mas é do Denis; não marquei item de outra pessoa.

### Follow-up de produto
- **`drive-upload-to-folder` não faz upsert:** reenviar o mesmo nome cria duplicata. Já mordeu duas
  vezes nesta sessão. Fix: procurar por nome na pasta e usar `PATCH /files/{id}` em vez de sempre criar.

## Aprendizados que viraram memória / skill

- `.claude/skills/airmeet-event-ops/` (novo): o que dá e o que não dá para automatizar no Airmeet, o
  fluxo de cada campo, o import em massa de speakers, e 2 scripts testados (`verify_public_page.py`,
  `build_speaker_pack.py`) mais `build_lounge_banner.py` e `qa_measure.py`.
- **`og:description` do Airmeet é string FIXA** e não muda com o Overview. Do preview do link só se
  controla título e imagem, então a copy do post tem que carregar o contexto sozinha.
- **Colisão em peça gráfica se prova medindo o INK do texto** (`Range.getBoundingClientRect` via
  `chrome --dump-dom`), não a caixa do elemento: a caixa do nome tinha 526 px e o texto, 410.
- **Nunca clicar por pixel em ação destrutiva:** o viewport muda de tamanho no meio da sessão e a
  coordenada envelhece. Num right-click assim eu selecionei o arquivo errado no Drive; se tivesse
  seguido, teria apagado a versão boa.
- **Antes de declarar impossível, procurar a capacidade na própria plataforma** (as EFs de Drive) e
  **confirmar o workspace antes de concluir falta de acesso** (caí no PMI Goiás vazio e disse
  "impossível" sobre um evento que vive no PMI LATAM).
