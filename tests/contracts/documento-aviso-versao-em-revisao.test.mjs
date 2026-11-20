// Documento de governança (GP 19/11/2026): a página do documento abre a versão vigente e avisa quando existe uma versão
// mais nova, ainda não lacrada, que quem lê pode abrir. Origem: um revisor jurídico trabalhou sobre a vigente de setembro
// enquanto a v1 de 01/11 só aparecia por link direto.
//
// O guard afirma que (A) a RPC escolhe a versão não lacrada de número maior que a vigente, (B) a autorização é a da
// prévia (delega a get_governance_document_draft_preview, sem reescrever a regra) e só devolve id e rótulo, (C) anon não
// executa, (D) a página só procura o aviso fora do modo prévia e monta o link com ?version=, e (E) os rótulos existem nos
// 3 idiomas.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const maskSql = (s) => s.replace(/--[^\n]*/g, '');
const MIG = readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort()
  .filter((f) => /CREATE OR REPLACE FUNCTION public\.get_governance_document_newer_draft\(/.test(readFileSync(`supabase/migrations/${f}`, 'utf8'))).at(-1);
const SQL = MIG ? maskSql(readFileSync(`supabase/migrations/${MIG}`, 'utf8')) : '';
const PAGE = maskJsComments(readFileSync('src/pages/governance/document/[id].astro', 'utf8'));
const DICTS = ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts'].map((p) => [p, readFileSync(p, 'utf8')]);

describe('documento: aviso de versão mais nova em revisão', () => {
  it('A: a RPC escolhe a não lacrada de número maior que a vigente', () => {
    assert.ok(MIG, 'migration da RPC');
    assert.match(SQL, /AND dv\.locked_at IS NULL\s+AND dv\.version_number > COALESCE\(v_current_number, 0\)\s+ORDER BY dv\.version_number DESC\s+LIMIT 1;/);
    assert.match(SQL, /JOIN public\.document_versions dv ON dv\.id = gd\.current_version_id\s+WHERE gd\.id = p_document_id;/);
  });

  it('B: a autorização é a da prévia, e só id e rótulo saem', () => {
    assert.match(SQL, /v_preview := public\.get_governance_document_draft_preview\(p_document_id, v_newer\.id\);/);
    assert.match(SQL, /IF v_preview -> 'draft_version' IS NULL OR jsonb_typeof\(v_preview -> 'draft_version'\) = 'null' THEN\s+RETURN jsonb_build_object\('ok', true, 'newer', NULL\);/);
    assert.match(SQL, /EXCEPTION WHEN insufficient_privilege THEN\s+RETURN jsonb_build_object\('ok', true, 'newer', NULL\);/);
    const out = SQL.slice(SQL.lastIndexOf("RETURN jsonb_build_object('ok', true, 'newer', jsonb_build_object("));
    assert.doesNotMatch(out.slice(0, out.indexOf('END;')), /content_html/);
  });

  it('C: SECURITY DEFINER, e anon não executa', () => {
    assert.match(SQL, /RETURNS jsonb\s+LANGUAGE plpgsql\s+STABLE\s+SECURITY DEFINER\s+SET search_path TO 'public', 'pg_temp'/);
    assert.match(SQL, /REVOKE ALL ON FUNCTION public\.get_governance_document_newer_draft\(uuid\) FROM PUBLIC, anon;\s+GRANT EXECUTE ON FUNCTION public\.get_governance_document_newer_draft\(uuid\) TO authenticated, service_role;/);
  });

  it('D: a página procura o aviso só fora da prévia e liga o link à versão', () => {
    assert.match(PAGE, /if \(!isDraftPreview\) \{\s+try \{\s+var nd = await sb\.rpc\('get_governance_document_newer_draft', \{ p_document_id: DOC_ID \}\);/);
    assert.match(PAGE, /if \(newer && newer\.version_id\) \{[\s\S]*?u\.searchParams\.set\('version', newer\.version_id\);[\s\S]*?getElementById\('doc-newer-draft-banner'\)\.classList\.remove\('hidden'\);/);
    assert.match(PAGE, /<section id="doc-newer-draft-banner" class="hidden /);
  });

  it('E: rótulos nos 3 idiomas', () => {
    for (const [p, src] of DICTS) {
      for (const k of ['newerDraftTitle', 'newerDraftBody', 'newerDraftLink']) {
        assert.match(src, new RegExp(`'governance\\.document\\.${k}': '[^']+'`), `${p} ${k}`);
      }
    }
  });
});
