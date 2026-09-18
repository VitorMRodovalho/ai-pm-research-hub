#!/usr/bin/env node
/**
 * Inventario de reconciliacao de atas: o que existe no Drive x o que falta na plataforma.
 *
 * POR QUE ESTE SCRIPT EXISTE. Em 17/09/2026 a premissa de trabalho era "as tribos ja tem as atas,
 * falta subir". Medido: **253 de 317 reunioes de tribo ja ocorridas estao sem ata (79,8%)**, 6 das
 * 14 tribos tem ZERO atas fechadas, e o Drive do Nucleo tem **45** arquivos com cara de ata ou
 * transcricao — cobertura maxima teorica de ~18%, antes de verificar se cada arquivo casa com uma
 * reuniao cadastrada. A pasta `Atas/` de 5 das 8 tribos que a tem esta VAZIA.
 *
 * Reuniao de tribo e hospedada pelo lider, entao gravacao e "Notes by Gemini" caem no Drive
 * PESSOAL dele, fora do alcance da plataforma. Este script mede o que esta ao alcance, e por
 * diferenca mostra o que depende de cada lider entregar.
 *
 * TRES ESTADOS, de proposito (nunca dois):
 *   casado          candidato do Drive com evento correspondente na plataforma
 *   sem_evento      arquivo no Drive que nao casa com reuniao cadastrada
 *   sem_candidato   reuniao sem ata e sem nada no Drive que a explique
 *
 * O terceiro e o numero que importa para a decisao: e a parte que NAO se resolve com importacao.
 *
 * Uso:
 *   node scripts/audit-minutes-drive-reconciliation.mjs [--drive-list <arquivo>] [--json]
 *
 * Sem `--drive-list`, chama o rclone (remote `gdrive-nucleo-iagp:`). Com, le a lista de um arquivo
 * (uma linha por caminho), o que permite rodar sem credencial de Drive.
 */
import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Faltam SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.');
  process.exit(2);
}
const args = process.argv.slice(2);
const listArg = args.indexOf('--drive-list');
const asJson = args.includes('--json');
const RCLONE = `${process.env.HOME}/.local/bin/rclone`;
const REMOTE = 'gdrive-nucleo-iagp:';
const PADRAO_CANDIDATO = /ata de reuniao|ata_|_ata|notes by gemini|transcri|minuta/i;

function listarDrive() {
  if (listArg !== -1) return readFileSync(args[listArg + 1], 'utf8').split('\n').filter(Boolean);
  // `／` (fullwidth solidus) aparece nos nomes vindos do Meet; nao e separador de caminho.
  const out = execFileSync(RCLONE, ['lsf', REMOTE, '--recursive', '--files-only'],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 300_000 });
  return out.split('\n').filter(Boolean);
}

/** Extrai a data do NOME do arquivo. `／` e digito-a-digito porque o Meet usa fullwidth. */
function dataDoNome(caminho) {
  const m = caminho.match(/(\d{4})[-_／/](\d{2})[-_／/](\d{2})/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
}

/** Numero da tribo, quando o CAMINHO o declara (`Tribo 06 - ...`). Nunca inferido do titulo. */
function triboDoCaminho(caminho) {
  const m = caminho.match(/Tribo\s*0?(\d{1,2})\b/i);
  return m ? Number(m[1]) : null;
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// Le as tabelas direto, de proposito: este inventario nao justifica DDL nova, e assim ele roda
// em qualquer momento da fila (aplicar migration com PR aberta derruba o CI alheio — mordeu tres
// vezes em 17/09).
const hoje = new Date().toISOString().slice(0, 10);
const { data: brutos, error } = await sb
  .from('events')
  .select('id, date, title, minutes_text, minutes_url, minutes_posted_at, initiatives!inner(legacy_tribe_id, title)')
  .lte('date', hoje)
  .not('initiatives.legacy_tribe_id', 'is', null)
  .order('date', { ascending: false })
  .limit(2000);
if (error) {
  console.error('Falha ao ler events:', error.message);
  process.exit(3);
}
const eventos = (brutos ?? []).map((e) => ({
  event_id: e.id,
  data: e.date,
  titulo: e.title,
  tribo: e.initiatives?.legacy_tribe_id ?? null,
  iniciativa: e.initiatives?.title ?? null,
  sem_ata: (!e.minutes_text || e.minutes_text.trim() === '') && !e.minutes_url,
  fechada: e.minutes_posted_at != null,
}));

const candidatos = listarDrive().filter((c) => PADRAO_CANDIDATO.test(c));
const semAta = (eventos ?? []).filter((e) => e.sem_ata);

const porData = new Map();
for (const e of semAta) {
  if (!porData.has(e.data)) porData.set(e.data, []);
  porData.get(e.data).push(e);
}

const casados = [];
const semEvento = [];
const ambiguos = [];
for (const c of candidatos) {
  const d = dataDoNome(c);
  const tribo = triboDoCaminho(c);
  const alvos = d ? (porData.get(d) ?? []) : [];
  // ⚠️ SO casa quando o CAMINHO declara a tribo e ela corresponde.
  //
  // A primeira versao deste script tinha um `alvos.length === 1 ? alvos[0] : null` como fallback:
  // sem tribo no caminho, casava com a unica reuniao sem ata daquela data. Isso produziu **7 falsos
  // positivos** de uma vez — "Reuniao Geral", "Reuniao de Lideranca" e um 1on1 (todos eventos
  // INSTITUCIONAIS, do Meet Recordings) foram atribuidos a tribo 8 porque a data coincidia. Data
  // igual e coincidencia, nao identidade; e um relatorio que afirma 15 importaveis onde ha menos
  // manda alguem gastar tempo em cima de arquivo que nao serve.
  //
  // Sem tribo declarada no caminho, o destino e `ambiguo` — terceiro estado, nunca um chute.
  const escolhido = tribo ? alvos.find((a) => a.tribo === tribo) : null;
  if (escolhido) casados.push({ arquivo: c, ...escolhido });
  else if (!tribo && alvos.length > 0) ambiguos.push({ arquivo: c, data: d, candidatos_na_data: alvos.length });
  else semEvento.push({ arquivo: c, data: d, tribo, candidatos_na_data: alvos.length });
}

const idsCasados = new Set(casados.map((c) => c.event_id));
const semCandidato = semAta.filter((e) => !idsCasados.has(e.event_id));

const resumo = {
  reunioes_ocorridas: (eventos ?? []).length,
  sem_ata: semAta.length,
  candidatos_no_drive: candidatos.length,
  casado: casados.length,
  sem_evento: semEvento.length,
  ambiguo_sem_tribo_no_caminho: ambiguos.length,
  sem_candidato: semCandidato.length,
  cobertura_pct: semAta.length ? Number(((casados.length / semAta.length) * 100).toFixed(1)) : null,
};

if (asJson) {
  console.log(JSON.stringify({ resumo, casados, ambiguos, sem_evento: semEvento, sem_candidato: semCandidato }, null, 2));
} else {
  console.log('\n=== INVENTARIO DE RECONCILIACAO DE ATAS ===\n');
  console.table(resumo);
  console.log('\n--- CASADO (importavel): arquivo do Drive com reuniao correspondente ---');
  if (!casados.length) console.log('  (nenhum)');
  for (const c of casados) console.log(`  tribo ${String(c.tribo).padStart(2)} · ${c.data} · ${c.arquivo}`);
  console.log('\n--- AMBIGUO: data casa, mas o caminho NAO declara tribo (nao e importavel sem conferencia humana) ---');
  for (const a of ambiguos.slice(0, 10)) console.log(`  ${a.data} · ${a.candidatos_na_data} reuniao(oes) naquela data · ${a.arquivo}`);
  if (ambiguos.length > 10) console.log(`  ... e mais ${ambiguos.length - 10}`);
  console.log('\n--- SEM_EVENTO: no Drive, sem reuniao cadastrada que case ---');
  for (const s of semEvento.slice(0, 20)) {
    console.log(`  ${s.data ?? 'sem data no nome'} · tribo ${s.tribo ?? '?'} · ${s.arquivo}`);
  }
  if (semEvento.length > 20) console.log(`  ... e mais ${semEvento.length - 20}`);
  console.log('\n--- SEM_CANDIDATO por tribo: o que NAO se resolve com importacao ---');
  const porTribo = new Map();
  for (const e of semCandidato) porTribo.set(e.tribo, (porTribo.get(e.tribo) ?? 0) + 1);
  for (const [t, n] of [...porTribo.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  tribo ${String(t).padStart(2)}: ${n} reunioes sem nada no Drive`);
  }
  console.log('\nO ultimo bloco depende de cada lider entregar o material — nao e importacao.\n');
}
