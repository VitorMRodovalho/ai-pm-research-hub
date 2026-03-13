-- W116 pt2: Publication assist trigger + notification type for publications
-- When a public_publication is marked as published, notify comms team members

CREATE OR REPLACE FUNCTION notify_on_publication_published()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_comms_member RECORD;
BEGIN
  -- Only fire when is_published changes to true
  IF NEW.is_published = true AND (OLD.is_published IS DISTINCT FROM true) THEN
    -- Notify all comms team members so they can help promote
    FOR v_comms_member IN
      SELECT id FROM members
      WHERE is_active = true
        AND (
          designations && ARRAY['comms_leader', 'comms_member']
          OR operational_role = 'communicator'
        )
    LOOP
      PERFORM create_notification(
        v_comms_member.id,
        'publication',
        'Nova publicação disponível: ' || NEW.title,
        'A publicação "' || NEW.title || '" foi marcada como pública e pode ser promovida.',
        '/publications',
        'publication',
        NEW.id
      );
    END LOOP;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_notify_publication_published
  AFTER UPDATE OF is_published ON public_publications
  FOR EACH ROW
  WHEN (NEW.is_published = true)
  EXECUTE FUNCTION notify_on_publication_published();

-- Also fire on INSERT when is_published is already true (e.g. auto-publish from curation)
CREATE OR REPLACE FUNCTION notify_on_publication_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_comms_member RECORD;
BEGIN
  IF NEW.is_published = true THEN
    FOR v_comms_member IN
      SELECT id FROM members
      WHERE is_active = true
        AND (
          designations && ARRAY['comms_leader', 'comms_member']
          OR operational_role = 'communicator'
        )
    LOOP
      PERFORM create_notification(
        v_comms_member.id,
        'publication',
        'Nova publicação disponível: ' || NEW.title,
        'A publicação "' || NEW.title || '" foi marcada como pública e pode ser promovida.',
        '/publications',
        'publication',
        NEW.id
      );
    END LOOP;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_notify_publication_insert
  AFTER INSERT ON public_publications
  FOR EACH ROW
  WHEN (NEW.is_published = true)
  EXECUTE FUNCTION notify_on_publication_insert();
