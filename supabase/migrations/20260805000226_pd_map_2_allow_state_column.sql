ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS allow_state_in_public_map boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.members.allow_state_in_public_map IS
  'LGPD Art. 7 I (consentimento) + privacy-by-design opt-out por padrao (DEFAULT false). Autorizacao explicita do membro para inclusao do seu estado (UF) em mapas de distribuicao geografica AGREGADOS exibidos publicamente (get_public_state_reach, supressao k>=5). Revogavel a qualquer tempo (Art. 18). Finalidade distinta da coleta original de members.state (verificacao de afiliacao) - base legal registrada no RoPA. Cycle4 heatmap PD-MAP-2.';
