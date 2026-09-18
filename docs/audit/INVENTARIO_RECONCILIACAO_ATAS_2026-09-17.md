# Inventario de reconciliacao de atas — 17/09/2026

> Carimbado em 17/09. **Re-meça** com
> `node scripts/audit-minutes-drive-reconciliation.mjs` (precisa de `SUPABASE_URL` +
> `SUPABASE_SERVICE_ROLE_KEY` e do remote rclone `gdrive-nucleo-iagp:`).
>
> Este documento e agregado de proposito: os **caminhos** do Drive carregam nome de pessoa, e o
> repositorio e publico. O detalhe por arquivo sai no `--json` do script, que nao se versiona.

## A premissa que nao se sustentou

O trabalho comecou de "as tribos ja tem as atas, falta subir". Medido, **nao**: a estrutura de
pastas existe e o conteudo quase nao.

| | |
|---|---:|
| reunioes de tribo ja ocorridas | **317** |
| sem ata nenhuma (`minutes_text` vazio e `minutes_url` nulo) | **253** (79,8%) |
| tribos com ZERO atas fechadas na historia | **6** de 14 |
| arquivos no Drive do Nucleo com cara de ata/transcricao | **45** |
| deles, **casados** com uma reuniao cadastrada | **7** |
| **cobertura real da importacao** | **2,8%** |

Dos 45 candidatos: 19 sao atas de **2024-2025** (era anterior, sem evento correspondente), 8 sao
**ambiguos** (data casa mas o caminho nao declara tribo — sao reunioes institucionais do
`Meet Recordings`, nao de tribo), e 30 nao casam com reuniao nenhuma.

## Por tribo: o que a importacao NAO resolve

| tribo | reunioes sem ata e sem nada no Drive | candidatos casados |
|---|---:|---:|
| 4 Cultura & Transformacao Organizacional | 39 | 3 |
| 5 Talentos & Upskilling | 30 | 0 |
| 3 TMO & PMO do Futuro | 29 | 0 |
| 6 ROI & Portfolio | 27 | **0** |
| 7 Governanca & Trustworthy AI | 26 | 0 |
| 8 Inclusao & Colaboracao & Comunicacao | 25 | 4 |
| 2 Agentes Autonomos | 23 | 0 |
| 1 Radar Tecnologico | 21 | 0 |
| 12 Produtividade Aumentada | 9 | 0 |
| 13 Dados em Projetos de IA | 9 | 0 |
| 9 IA em Projetos & Construcao | 7 | 0 |
| 10 Governanca Assistida | 2 | 0 |
| 11 PMO Inteligente | **1** | 0 |
| 14 Fluencia em IA | **1** | 0 |

**A tribo 6 nao tem candidato nenhum**, apesar de ser a que mais registrou atas na plataforma (26
fechadas, ultima em 04/08). PMO Inteligente e Fluencia em IA sao as unicas praticamente em dia.

⚠️ Mesmo os 7 "casados" pedem conferencia humana antes de importar: dois sao **entrevistas de
lider** e um e **chat de kickoff** — material de reuniao, mas nao ata de reuniao de tribo. Os 4 da
tribo 8 sao gravacoes de trabalho e parecem os unicos aproveitaveis de fato.

## Onde esta o resto, e por que nao e problema tecnico

As pastas `Atas/` por tribo existem em 8 tribos. **Cinco estao vazias.** Só duas tem conteudo
(Talentos com 20, e ROI & Portfolio com 5, todas de Ciclo 2 — nenhuma casando com reuniao
cadastrada).

Reuniao de tribo e hospedada pelo **lider**, entao a gravacao e as "Notes by Gemini" caem no Drive
**pessoal dele**, fora do alcance da plataforma e deste inventario. Recuperar o material das ~249
reunioes depende de cada lider entregar — **conversa de lideranca, nao engenharia.**

## Armadilha do instrumento, registrada

A primeira versao do script casava por **data** quando havia exatamente uma reuniao sem ata naquele
dia. Isso produziu **7 falsos positivos de uma vez**: "Reuniao Geral", "Reuniao de Lideranca" e um
1on1 foram atribuidos a tribo 8 porque a data coincidia, e o relatorio afirmava **15 importaveis**
em vez de 7 — cobertura de 5,9% no lugar de 2,8%.

**Data igual e coincidencia, nao identidade.** A versao vigente so casa quando o CAMINHO declara a
tribo, e o resto vai para um quarto estado (`ambiguo`) em vez de virar chute. Classe do
`reference-numero-que-bate-com-o-esperado-pode-bater-pela-fonte-errada`.

## Ordem recomendada (e por que a importacao e o ultimo passo)

1. **Este inventario** — feito. Da o numero real em vez de estimativa.
2. **Pedir o material aos lideres**, tribo por tribo, usando a coluna "sem nada no Drive" como
   pauta. E o passo que move a agulha: 249 de 253.
3. **Só então importar** — item a item (nao ha caminho em massa) e **na ordem correta**: ver #2351,
   porque `write` fecha a reuniao e faz o `close` seguinte descartar o resumo em silencio.

Cross-ref: #2351 (ambiguidade da rota de ata), #2345 (eventos invisiveis no digest).
