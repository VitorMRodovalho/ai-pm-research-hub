-- #2699 — a contra-assinatura invalida o PDF congelado, e agora alguém volta a gerá-lo.
--
-- O DEFEITO. #2022 fez `counter_sign_certificate` zerar `pdf_url`, de propósito: o congelado
-- tinha sido renderizado ANTES da contra-assinatura e dizia "Pendente contra-assinatura". Mas o
-- único caminho que GERA o PDF é `trg_certificate_pdf_autogen`, que é AFTER INSERT. A
-- contra-assinatura é um UPDATE, então nada voltava a gerar. Medido em 14/10/2026: os 15 termos
-- contra-assinados de 02/09 a 14/10 estão com `pdf_url` nulo, e o download caía no print() do
-- navegador. O lote (`bulk_counter_sign_certificates`) delega à RPC individual e herda o mesmo.
--
-- A lacuna não é do Termo: o UPDATE da RPC não olha o tipo. Nenhum certificado de outro tipo foi
-- contra-assinado depois de #2022, por isso só o Termo apareceu.
--
-- O CONSERTO, em duas peças, porque a primeira sozinha falharia em silêncio de novo:
--
-- 1. Um gatilho AFTER UPDATE que, quando o congelado é invalidado num certificado emitido, chama
--    o MESMO endpoint de render (reaproveita `_trg_certificate_pdf_autogen`, que só lê NEW). O
--    pg_net despacha depois do COMMIT, então o endpoint lê o estado já contra-assinado.
--    O endpoint grava `pdf_url` de NULL para o caminho; esse UPDATE não satisfaz o WHEN (NEW.pdf_url
--    não é nulo), então não há laço.
--
-- 2. Uma varredura de 10 em 10 minutos para o que o gatilho não entregou. O render é melhor
--    esforço e tem rate limit: a #2022 mediu 429 com 12 renders simultâneos, e uma diretora
--    contra-assinou 10 termos de uma vez em 14/10. Sem a varredura, um 429 deixaria o termo sem
--    PDF até alguém notar. Ela também recupera os 15 de hoje, sem backfill à parte.
--    No máximo 5 por rodada (a #2022 mediu blocos de 8-10 passando limpos) e 3 tentativas por
--    certificado, contadas no `admin_audit_log`, para um certificado que nunca renderiza não
--    ocupar as vagas para sempre. Quando só sobra certificado esgotado, a varredura FALHA: o
--    `_alert_sweep_cron` lê falha de cron e avisa o GP. Esgotar em silêncio seria repetir o defeito.

DROP TRIGGER IF EXISTS trg_certificate_pdf_regen_on_invalidate ON public.certificates;
CREATE TRIGGER trg_certificate_pdf_regen_on_invalidate
AFTER UPDATE OF pdf_url, counter_signed_at ON public.certificates
FOR EACH ROW
WHEN (NEW.pdf_url IS NULL
      AND NEW.status = 'issued'
      AND (OLD.pdf_url IS NOT NULL OR OLD.counter_signed_at IS DISTINCT FROM NEW.counter_signed_at))
EXECUTE FUNCTION public._trg_certificate_pdf_autogen();

CREATE OR REPLACE FUNCTION public._certificate_pdf_regen_sweep_cron(p_limit integer DEFAULT 5)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_secret    text;
  v_rec       record;
  v_enviados  int := 0;
  v_esgotados int := 0;
BEGIN
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cert_pdf_internal_secret'
  LIMIT 1;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE EXCEPTION 'cert_pdf_regen_sweep: segredo cert_pdf_internal_secret ausente no Vault';
  END IF;

  FOR v_rec IN
    SELECT c.id, c.verification_code
    FROM public.certificates c
    WHERE c.pdf_url IS NULL
      AND c.status = 'issued'
      -- 10 minutos de folga para o gatilho, que já mandou o pedido dele, terminar primeiro.
      AND COALESCE(c.counter_signed_at, c.issued_at, '-infinity'::timestamptz) < now() - interval '10 minutes'
      AND (SELECT count(*) FROM public.admin_audit_log l
           WHERE l.action = 'certificate.pdf_regen_requested' AND l.target_id = c.id) < 3
    ORDER BY COALESCE(c.counter_signed_at, c.issued_at, '-infinity'::timestamptz)
    LIMIT GREATEST(LEAST(COALESCE(p_limit, 5), 10), 1)
  LOOP
    PERFORM net.http_post(
      url := 'https://nucleoia.vitormr.dev/api/internal/cert-pdf-render/' || v_rec.id::text,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_secret,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object('cert_id', v_rec.id, 'verification_code', v_rec.verification_code),
      timeout_milliseconds := 30000
    );

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (NULL, 'certificate.pdf_regen_requested', 'certificate', v_rec.id,
      jsonb_build_object('verification_code', v_rec.verification_code, 'source', 'regen_sweep_cron'));

    v_enviados := v_enviados + 1;
  END LOOP;

  SELECT count(*) INTO v_esgotados
  FROM public.certificates c
  WHERE c.pdf_url IS NULL
    AND c.status = 'issued'
    AND (SELECT count(*) FROM public.admin_audit_log l
         WHERE l.action = 'certificate.pdf_regen_requested' AND l.target_id = c.id) >= 3;

  -- Falha só quando não há mais nada a tentar: assim a rodada que ainda envia não perde os pedidos
  -- (o RAISE desfaria os INSERTs do log e as tentativas não contariam).
  IF v_enviados = 0 AND v_esgotados > 0 THEN
    RAISE EXCEPTION 'cert_pdf_regen_sweep: % certificado(s) emitido(s) sem PDF depois de 3 tentativas de render', v_esgotados;
  END IF;

  RETURN jsonb_build_object('enviados', v_enviados, 'esgotados', v_esgotados);
END;
$function$;

REVOKE ALL ON FUNCTION public._certificate_pdf_regen_sweep_cron(integer) FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('certificate-pdf-regen-sweep')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'certificate-pdf-regen-sweep');

SELECT cron.schedule(
  'certificate-pdf-regen-sweep',
  '*/10 * * * *',
  $cron$SELECT public._certificate_pdf_regen_sweep_cron(5);$cron$
);
