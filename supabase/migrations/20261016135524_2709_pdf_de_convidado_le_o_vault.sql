-- #2709: o gatilho de PDF do certificado de convidado passa a ler o segredo do vault.
--
-- `app.cert_pdf_internal_secret` nao pode ser definido no Postgres gerenciado (SEDIMENT-225.B), e
-- por isso o gatilho dos membros passou a ler do vault em 20260805000006. O de convidado nasceu no
-- mesmo dia (20260805000338, #1098) copiando a versao anterior: o GUC volta sempre vazio, o gatilho
-- cai no WARNING e nenhum certificado de convidado recebe PDF automatico.
--
-- Medido em 16/10/2026, em transacao desfeita: inserir um certificado de convidado punha 0 pedidos
-- em net.http_request_queue (controle: um net.http_post direto punha 1).
--
-- Unica mudanca: a leitura do segredo e o search_path, iguais aos de _trg_certificate_pdf_autogen.
-- O resto do corpo (URL, corpo com kind=event_guest, timeout, melhor-esforco) fica igual.

CREATE OR REPLACE FUNCTION public._trg_event_guest_cert_pdf_autogen()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
DECLARE
  v_secret text;
  v_url text;
BEGIN
  IF NEW.pdf_url IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets
  WHERE name = 'cert_pdf_internal_secret'
  LIMIT 1;

  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'event_guest_cert_pdf_autogen: vault secret "cert_pdf_internal_secret" not configured; skipping PDF gen for guest cert % (verification_code=%)', NEW.id, NEW.verification_code;
    RETURN NEW;
  END IF;

  v_url := 'https://nucleoia.vitormr.dev/api/internal/cert-pdf-render/' || NEW.id::text;

  PERFORM net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_secret,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('cert_id', NEW.id, 'verification_code', NEW.verification_code, 'kind', 'event_guest'),
    timeout_milliseconds := 30000
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'event_guest_cert_pdf_autogen exception for guest cert % (verification_code=%): % (continuing, best-effort)',
      NEW.id, NEW.verification_code, SQLERRM;
    RETURN NEW;
END;
$function$;
