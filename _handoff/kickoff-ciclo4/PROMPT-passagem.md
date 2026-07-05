# Prompt de passagem — executar na sessão do hub (ai-pm-research-hub)

> Cole o bloco abaixo na sessão Claude do projeto `ai-pm-research-hub`. Todos os arquivos citados já estão em `_handoff/kickoff-ciclo4/` (caminhos relativos ao repo).

---

Você está no projeto `ai-pm-research-hub`. Vamos operacionalizar o **Kickoff do Ciclo 4 (evento 09/07)** criando uma iniciativa, o board e as tarefas, e engajando os líderes, via MCP do Núcleo (`nucleo-ia`).

**Leia primeiro (estão em `_handoff/kickoff-ciclo4/`):**
- `HANDOFF-iniciativa-kickoff-ciclo4.md` — a fonte da verdade (roster, ações, wiring MCP, diagrama, [LL]).
- `ROTEIRO-kickoff-ciclo4.md` — run-of-show do evento.
- `GUIA-videos-tribo-e-boas-praticas-ciclo4.md` — template de vídeo + gaps do site + boas práticas de registro.
- `BRIEF-video-tribo.md` — descrição a colar em cada card de vídeo.
- `SCRIPT-tribo06-fabricio-EXEMPLO.md` — exemplo de vídeo pronto (referência).
- `verticais.png` / `verticais.mmd` — diagrama das verticais.

**Fatos que valem (não re-derivar):**
- Iniciativa: **"Kickoff Ciclo 4 + Onboarding dos Líderes"**. Líder = **Fabrício Costa**. Coordenador = **Fernando Maquiaveli**.
- Teto por tribo = **7** (não 10). Tribo 03 (Marcel) **fora** (desligamento no C3).
- Pasta Drive temporária dos vídeos: **https://drive.google.com/drive/folders/1T1ATHvJ-G3Tk7D05QoHALvfk15bTNG2m** (id `1T1ATHvJ-G3Tk7D05QoHALvfk15bTNG2m`).
- Convenção de nome do vídeo: `TriboNN-Tema-Nome.mp4` / `Vertical-Tema-Nome.mp4`. Baseline dos vídeos: **08/07**.
- O **[LL] já foi registrado** no #588 (não duplicar).
- Roster de líderes e a tabela de 1 card por líder estão na **seção 6** do HANDOFF.

**Faça, nesta ordem (confirmando comigo antes de qualquer ação externa/irreversível):**
1. **Roster:** rode `search_members` para resolver os registros oficiais de: novo líder da **T2** (Débora passou o bastão, nome a definir comigo), e os líderes de vertical Henrique Diniz (Construção), Messias (PMO), Jonathá (Ágil/Negócio), Felipe/PMI-MG (ESG). Me traga o que encontrou antes de convidar.
2. **Iniciativa:** crie "Kickoff Ciclo 4 + Onboarding dos Líderes" (Fabrício líder). Engaje Fernando como coordenador e todos os líderes do roster: `invite_to_initiative` / `manage_initiative_engagement`. Vincule a pasta do Ciclo 4 com `link_initiative_to_drive`.
3. **Board + Drive:** crie/associe o board da iniciativa e vincule à pasta Drive dos vídeos com `link_board_to_drive` (folder `1T1ATHvJ-G3Tk7D05QoHALvfk15bTNG2m`).
4. **Cards de vídeo (1 por líder):** para cada linha da tabela da seção 6, `create_board_card` + `update_card_fields` (responsável = líder, due = 08/07, descrição = conteúdo de `BRIEF-video-tribo.md`).
5. **Cards das 4 frentes:** crie as ações das Frentes 1, 3 e 4 (seção 2 do HANDOFF) como `create_action_item`/cards, com responsável e data baseline; use `update_card_forecast` para baseline+forecast dos artefatos de roadmap.
6. **Acompanhamento:** quando os líderes subirem os MP4, `register_card_drive_file` para anexar ao card; fechar com `update_card_status`. Lote via `list_board_cards` / `get_board_drive_links`.

**Guardrails:**
- Antes de disparar convites (`invite_to_initiative`), me mostre o roster resolvido e espere meu OK.
- Não recrie o [LL] (#588 já tem).
- Duas correções ainda dependem de mim: **nome do novo líder da T2** e confirmação final das cadências (T2 08h30×20h30, T6 "a definir"). Deixe placeholders e me pergunte.
- Isto roda pelo fluxo do próprio hub (dev/model routing do projeto), não pelo nó Pai.

Ao final, me devolva: id da iniciativa, id do board, lista de cards criados (com responsável e due), e o que ficou pendente de confirmação.
