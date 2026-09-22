// tests/contracts/2418-welcome-le-o-par-nao-so-o-kind.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: este arquivo
// toca o banco, e o guard #1908 exige que DB-gated rode na faixa SERIALIZADA (#1509).
/**
 * O texto de boas-vindas le o PAR (kind, role), porque e o par que concede autoridade.
 *
 * O CASO (#2418): `_enqueue_engagement_welcome` escolhia o texto com `CASE v_eng.kind`, so pelo
 * kind. A tabela de permissao e chaveada pelo par. Resultado medido em 22/09/2026: quem entra como
 * `observer x participant` — que a #2416 fez conceder `write_board` com escopo `initiative` — recebia
 * "Voce tem acesso de LEITURA aos materiais e reunioes da iniciativa".
 *
 * E ISSO SAI POR E-MAIL: `delivery_mode='transactional_immediate'`, e medido no historico,
 * **173 de 173** notificacoes `engagement_welcome` tiveram `email_sent_at` preenchido. Nao e uma
 * campainha que ninguem olha; e a primeira coisa que a pessoa le sobre o que pode fazer ali.
 *
 * Mesma familia do defeito nº 19 do registro de 21/09 (ler uma tabela de permissao por metade da
 * chave). A diferenca e que aqui o leitor errado nao e uma consulta de diagnostico: e um texto que
 * chega a pessoa real.
 *
 * ⚠️ A ASSERCAO AMARRA CONDICAO A RESULTADO, DENTRO DO BLOCO QUE DECIDE.
 * `prosrc.includes('participant')` ficaria verde com o ramo inteiro removido, porque a palavra
 * sobrevive no `CASE` de outro kind e nos comentarios. Entao este guard RECORTA o ramo `observer`,
 * parte o ramo em braco-participant e braco-else, e afirma dentro de cada um: o participante e
 * convidado a CONTRIBUIR e nao pode receber "acesso de leitura"; o resto continua recebendo leitura.
 * Comentarios sao mascarados antes de medir (`maskLineComments`), porque o cabecalho que explica o
 * anti-padrao contem as proprias palavras que o guard procura.
 *
 * Cross-ref: #2418, #2400, #2417, PR #2416, ADR-0131.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const LEITURA = /acesso de leitura/i;
const CONTRIBUIR = /contribuir/i;

/**
 * Recorta o ramo `WHEN 'observer' THEN` ate o fim DELE: o bloco que DECIDE.
 *
 * ⚠️ Conta profundidade de IF em vez de parar no primeiro `ELSE`. A primeira versao deste recorte
 * parava ali e cortava o ramo no ELSE do PROPRIO IF que o guard precisa ler, entregando um bloco
 * mutilado — o controle sem mutacao reprovou e foi assim que o defeito apareceu. Um recorte que
 * corta cedo demais nao acusa: ele devolve menos texto, e menos texto passa em assercao de ausencia.
 */
export function ramoObserver(prosrc) {
  const corpo = maskLineComments(prosrc);
  const m = corpo.match(/WHEN\s+'observer'\s+THEN/i);
  if (!m) return null;
  const resto = corpo.slice(m.index + m[0].length);
  const re = /\b(END\s+IF|END\s+CASE|ELSIF|IF|ELSE|WHEN)\b/gi;
  let profundidade = 0;
  let t;
  while ((t = re.exec(resto)) !== null) {
    const tok = t[1].toUpperCase().replace(/\s+/g, ' ');
    if (tok === 'IF') profundidade += 1;
    else if (tok === 'END IF') profundidade -= 1;
    else if (tok === 'ELSIF') continue;
    else if (profundidade === 0) return resto.slice(0, t.index);
  }
  return resto;
}

/**
 * Violacoes do ramo observer. Lista vazia = saudavel.
 *
 * E a MESMA funcao que julga o corpo vivo e os corpos adulterados do teste de mutacao: uma mutacao
 * que nao passa pelo avaliador e parafrase, e so afirma que a string mudou.
 */
export function violacoes(prosrc) {
  const v = [];
  const ramo = ramoObserver(prosrc);
  if (ramo === null) {
    return ['o ramo WHEN \'observer\' sumiu de _enqueue_engagement_welcome: externo entra sem texto nenhum'];
  }

  const mIf = ramo.match(/IF\s+v_eng\.role\s*=\s*'participant'\s+THEN([\s\S]*?)\n\s*ELSE\b([\s\S]*?)\n\s*END\s+IF\s*;/i);
  if (!mIf) {
    v.push(
      'o ramo observer nao ramifica por role: o texto passa a descrever o mesmo para ' +
      'observer x participant (que escreve no quadro, #2416) e para observer x observer (que nao ' +
      'recebe autoridade nenhuma). O welcome voltou a ler metade da chave (#2418).',
    );
    return v;
  }

  const [, bracoParticipant, bracoResto] = mIf;

  if (!CONTRIBUIR.test(bracoParticipant)) {
    v.push('o braco participant nao convida a CONTRIBUIR: e exatamente a autoridade que o par concede');
  }
  if (LEITURA.test(bracoParticipant)) {
    v.push('o braco participant continua dizendo "acesso de leitura" a quem recebeu write_board (#2418)');
  }
  if (!LEITURA.test(bracoResto)) {
    v.push('o braco nao-participant perdeu o texto de leitura: curator/reviewer/observer ficam sem descricao correta');
  }
  return v;
}

test('#2418 — o welcome vivo de observer ramifica por role e nao promete leitura a quem escreve',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb().rpc('_audit_function_source', {
      p_proname: '_enqueue_engagement_welcome',
    });
    assert.ifError(error);
    assert.ok(data?.length > 0, '_enqueue_engagement_welcome nao existe no banco');
    assert.equal(data.length, 1, `sobrecarga inesperada: ${data.length} assinaturas de _enqueue_engagement_welcome`);
    assert.equal(data[0].is_secdef, true, 'a funcao perdeu SECURITY DEFINER no replace (#2418)');

    assert.deepEqual(violacoes(data[0].prosrc), [],
      'o corpo VIVO em producao voltou a descrever errado o que o externo pode fazer');
  });

test('#2418 mutacao — o detector reprova cada defeito, pela MESMA funcao', () => {
  const SAUDAVEL = `
  CASE v_eng.kind
    WHEN 'volunteer' THEN
      v_body := 'participant blah';
    WHEN 'observer' THEN
      IF v_eng.role = 'participant' THEN
        v_subject := 'Convite';
        v_body := 'Voce pode contribuir no quadro desta iniciativa.';
      ELSE
        v_subject := 'Observer';
        v_body := 'Voce tem acesso de leitura aos materiais.';
      END IF;
    WHEN 'speaker' THEN
      v_body := 'outro';
    ELSE
      RETURN;
  END CASE;`;
  assert.deepEqual(violacoes(SAUDAVEL), [], 'controle sem mutacao: o corpo correto nao pode produzir violacao');

  // Mutacao 1 — o estado EXATO de antes do conserto: ramo sem IF por role.
  const semRole = SAUDAVEL.replace(
    /IF v_eng\.role[\s\S]*?END IF;/,
    `v_subject := 'Observer';\n        v_body := 'Voce tem acesso de leitura aos materiais.';`);
  assert.notEqual(semRole, SAUDAVEL, 'a mutacao 1 precisa ter MUDADO o corpo');
  assert.match(violacoes(semRole).join(' | '), /nao ramifica por role/,
    'mutacao 1: o detector tem de achar o welcome que le so o kind');

  // Mutacao 2 — ramifica, mas o braco do participante continua prometendo leitura.
  const leituraNoParticipante = SAUDAVEL.replace(
    'Voce pode contribuir no quadro desta iniciativa.',
    'Voce tem acesso de leitura aos materiais.');
  assert.notEqual(leituraNoParticipante, SAUDAVEL, 'a mutacao 2 precisa ter MUDADO o corpo');
  const v2 = violacoes(leituraNoParticipante).join(' | ');
  assert.match(v2, /nao convida a CONTRIBUIR/, 'mutacao 2: falta o convite a contribuir');
  assert.match(v2, /continua dizendo "acesso de leitura"/, 'mutacao 2: sobra a promessa de leitura');

  // Mutacao 3 — o ramo observer inteiro desaparece.
  const semRamo = SAUDAVEL.replace(/WHEN 'observer' THEN[\s\S]*?END IF;/, "WHEN 'observer_x' THEN\n      NULL;");
  assert.notEqual(semRamo, SAUDAVEL, 'a mutacao 3 precisa ter MUDADO o corpo');
  assert.match(violacoes(semRamo).join(' | '), /sumiu de _enqueue_engagement_welcome/,
    'mutacao 3: ramo ausente nao pode ler como aprovado');

  // Mutacao 4 — o defeito escondido em COMENTARIO nao pode salvar o guard, e um comentario
  // que CITA o texto certo nao pode aprovar um corpo que nao o tem.
  const soNoComentario = SAUDAVEL.replace(
    'Voce pode contribuir no quadro desta iniciativa.',
    "'; -- Voce pode contribuir no quadro desta iniciativa.\n        v_body := 'x");
  assert.notEqual(soNoComentario, SAUDAVEL, 'a mutacao 4 precisa ter MUDADO o corpo');
  assert.match(violacoes(soNoComentario).join(' | '), /nao convida a CONTRIBUIR/,
    'mutacao 4: o guard esta casando o proprio comentario em vez do codigo');
});
