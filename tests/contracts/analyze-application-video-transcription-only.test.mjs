/**
 * analyze-application-video: so transcreve.
 *
 * A funcao de borda transcreve o video enviado (Whisper) e grava o texto em pmi_video_screenings.
 * Ela nao chama API de modelo de texto, nao baixa a miniatura do Drive, nao manda o nome do
 * candidato a modelo nenhum e nao grava pontuacao sugerida.
 *
 * Cada asserção casa a condição junto com o resultado, dentro do bloco que decide, com
 * comentários mascarados (o cabeçalho do arquivo cita estes termos para explicar a regra):
 *
 *   1. a funcao inteira (sem comentarios) nao alcanca a API de mensagens, a miniatura, a tabela de
 *      sugestoes nem o campo de pontuacao;
 *   2. a leitura de selection_applications nao traz o nome do candidato;
 *   3. dentro de processVideosBackground, a transcricao e gravada em pmi_video_screenings depois do
 *      portao de consentimento e depois da chamada ao Whisper, e o log registra o provedor do Whisper;
 *   4. o MCP nao promete nota nem analise de imagem na ferramenta analyze_application_video.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const FN = maskJsComments(readFileSync(join(ROOT, 'supabase/functions/analyze-application-video/index.ts'), 'utf8'));
const MCP = maskJsComments(readFileSync(join(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8'));

/** Corpo de processVideosBackground, do cabecalho ate o inicio de Deno.serve. */
function processBlock(src) {
  const at = src.indexOf('async function processVideosBackground');
  const end = src.indexOf('Deno.serve(');
  assert.ok(at !== -1 && end > at, 'processVideosBackground existe antes de Deno.serve');
  return src.slice(at, end);
}

/** O registro da ferramenta analyze_application_video no MCP, ate o proximo mcp.tool. */
function toolBlock(src) {
  const at = src.indexOf('mcp.tool("analyze_application_video"');
  assert.ok(at !== -1, 'a ferramenta analyze_application_video esta registrada');
  const next = src.indexOf('mcp.tool(', at + 10);
  return src.slice(at, next === -1 ? undefined : next);
}

test('a funcao nao alcanca modelo de texto, miniatura, sugestao nem pontuacao', () => {
  assert.doesNotMatch(FN, /api\.anthropic\.com/, 'sem chamada a API de mensagens');
  assert.doesNotMatch(FN, /anthropic_api_key/, 'sem ler a chave do provedor de texto');
  assert.doesNotMatch(FN, /thumbnailLink/, 'sem metadado de miniatura do Drive');
  assert.doesNotMatch(FN, /selection_evaluation_ai_suggestions/, 'sem gravar sugestao');
  assert.doesNotMatch(FN, /suggested_scores/, 'sem pontuacao sugerida');
  assert.doesNotMatch(FN, /type:\s*"image"/, 'sem parte de imagem em mensagem a modelo');
});

test('a leitura da candidatura nao traz o nome do candidato', () => {
  const block = processBlock(FN);
  const m = block.match(/\.from\("selection_applications"\)\s*\.select\("([^"]*)"\)/);
  assert.ok(m, 'a leitura de selection_applications existe em processVideosBackground');
  assert.doesNotMatch(m[1], /applicant_name/);
  assert.match(m[1], /consent_ai_analysis_at/, 'o portao de consentimento continua lendo o campo');
  assert.match(m[1], /consent_voice_biometric_at/, 'o portao de consentimento de voz continua lendo o campo');
});

test('a transcricao e gravada depois do consentimento e do Whisper, com provedor do Whisper no log', () => {
  const block = processBlock(FN);
  const consent = block.search(/if \(!app\.consent_voice_biometric_at \|\| app\.consent_voice_biometric_revoked_at\)/);
  const whisper = block.indexOf('await whisperTranscribe(');
  const write = block.search(/\.from\("pmi_video_screenings"\)\.update\(\{\s*transcription,/);
  assert.ok(consent !== -1 && whisper !== -1 && write !== -1, 'portao, Whisper e gravacao existem');
  assert.ok(consent < whisper && whisper < write, 'ordem: consentimento, Whisper, gravacao');
  assert.match(block, /model_provider:\s*"openai",\s*model_id:\s*WHISPER_MODEL/);
  assert.match(FN, /const WHISPER_MODEL = "whisper-1"/);
});

test('a ferramenta do MCP nao promete nota nem analise de imagem', () => {
  const block = toolBlock(MCP);
  assert.match(block, /Transcription only/, 'a descricao diz que e so transcricao');
  assert.doesNotMatch(block, /Claude|Haiku|thumbnail|multimodal|score per pillar|generates a suggestion/i);
});
