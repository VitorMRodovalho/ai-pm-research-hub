import { describe, it, expect } from 'vitest';
import { perfilVeioNestaImportacao, upsertSelectionApplication } from './db';

/**
 * #3019 — on re-import, the PMI profile fields are rewritten only when the profile came in this import, or to clear
 * a private one (Decision 5). Before, an import that could not fetch the profile wrote NULL over the good data already
 * in the row. Each case reads the PATCH body as PostgREST receives it (JSON): a key that is absent leaves the column
 * as it is.
 */

const PERFIL = [
  'pmi_memberships', 'profile_location', 'profile_state', 'profile_city', 'profile_country', 'profile_industry',
  'profile_company', 'profile_designation', 'profile_certifications', 'profile_volunteer_interest',
  'profile_specialties', 'profile_linkedin_url', 'profile_about_me', 'service_history_count',
  'service_history_chapters', 'service_first_start_date', 'service_latest_end_date', 'is_open_to_volunteer',
  'community_profile_private', 'pmi_data_fetched_at', 'certifications',
];
const SEM_PERFIL = Object.fromEntries(PERFIL.map((k) => [k, null]));

function bancoFalso(existente: Record<string, unknown>) {
  const corpos: Record<string, unknown>[] = [];
  const db: any = {
    from: () => ({
      select: () => ({ eq: () => ({ eq: () => ({ maybeSingle: async () => ({ data: existente, error: null }) }) }) }),
      update: (obj: Record<string, unknown>) => {
        corpos.push(JSON.parse(JSON.stringify(obj)));
        return { eq: async () => ({ error: null }) };
      },
      insert: async () => ({ error: null }),
    }),
  };
  return { db, corpos };
}

async function corpoDoPatch(payload: Record<string, unknown>, mesmoCiclo = false) {
  const existente = { id: 'linha', cycle_id: mesmoCiclo ? 'ciclo-novo' : 'ciclo-velho', email: 'e@x.com', status: 'submitted', vep_reconciled_at: null };
  const { db, corpos } = bancoFalso(existente);
  await upsertSelectionApplication(db, {
    vep_application_id: '1', vep_opportunity_id: 'o', cycle_id: 'ciclo-novo', email: 'e@x.com', applicant_name: 'N',
    status: 'submitted', chapter: 'PMI-GO', vep_last_seen_at: '2026-11-06T00:00:00Z', linkedin_url: null, applicant_city: null,
    ...SEM_PERFIL, ...payload,
  } as any);
  expect(corpos).toHaveLength(1);
  return corpos[0]!;
}

describe('#3019 perfilVeioNestaImportacao', () => {
  it.each([
    [{ pmi_data_fetched_at: '2026-11-06T00:00:00Z', community_profile_private: false }, true],
    [{ pmi_data_fetched_at: null, community_profile_private: true }, true],
    [{ pmi_data_fetched_at: null, community_profile_private: false }, false],
    [{ pmi_data_fetched_at: null, community_profile_private: null }, false],
  ])('%o -> %s', (p, esperado) => {
    expect(perfilVeioNestaImportacao(p as any)).toBe(esperado);
  });
});

describe('#3019 the re-import PATCH keeps or rewrites the PMI profile', () => {
  it('profile NOT fetched in this import: no profile key in the body, so the row keeps what it had', async () => {
    for (const mesmoCiclo of [false, true]) {
      const corpo = await corpoDoPatch({}, mesmoCiclo);
      for (const k of PERFIL) expect(corpo, `${k} (mesmo ciclo: ${mesmoCiclo})`).not.toHaveProperty(k);
      expect(corpo).not.toHaveProperty('linkedin_url');
      expect(corpo).not.toHaveProperty('applicant_city');
      // Controle: o que não é do perfil continua sendo gravado.
      expect(corpo).toMatchObject({ chapter: 'PMI-GO', vep_last_seen_at: '2026-11-06T00:00:00Z' });
    }
  });

  it('profile fetched and empty: the profile keys are written, NULL included (a membership that ended)', async () => {
    const corpo = await corpoDoPatch({ pmi_data_fetched_at: '2026-11-06T00:00:00Z', community_profile_private: false, profile_location: 'Goiânia' });
    expect(corpo).toMatchObject({ pmi_data_fetched_at: '2026-11-06T00:00:00Z', community_profile_private: false, profile_location: 'Goiânia' });
    expect(corpo).toHaveProperty('pmi_memberships', null);
    expect(corpo).toHaveProperty('linkedin_url', null);
    expect(corpo).toHaveProperty('applicant_city', null);
  });

  it('private profile (Decision 5): the profile keys are written as NULL, and the flag as true', async () => {
    const corpo = await corpoDoPatch({ community_profile_private: true });
    expect(corpo).toHaveProperty('community_profile_private', true);
    for (const k of PERFIL.filter((x) => x !== 'community_profile_private')) expect(corpo, k).toHaveProperty(k, null);
  });

  it('a value that comes from the application itself is written even without the profile', async () => {
    const corpo = await corpoDoPatch({ linkedin_url: 'https://www.linkedin.com/in/exemplo', applicant_city: 'Anápolis' });
    expect(corpo).toMatchObject({ linkedin_url: 'https://www.linkedin.com/in/exemplo', applicant_city: 'Anápolis' });
    expect(corpo).not.toHaveProperty('pmi_memberships');
  });
});
