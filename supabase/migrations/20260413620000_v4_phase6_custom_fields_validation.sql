-- ============================================================================
-- V4 Phase 6 — Migration 3/5: Custom Fields JSON Schema Validation
-- ADR: ADR-0009 (Config-Driven Initiative Kinds)
-- Depends on: 20260413610000_v4_phase6_kind_aware_engine.sql
-- Rollback: DROP FUNCTION IF EXISTS public.validate_initiative_metadata(text, jsonb);
--           DROP TRIGGER IF EXISTS trg_validate_initiative_metadata ON public.initiatives;
--           DROP FUNCTION IF EXISTS public.trg_validate_initiative_metadata_fn();
-- ============================================================================

-- Lightweight JSON schema validator for initiative metadata.
-- Checks required fields + basic type validation (string, number, boolean, array).
-- Full JSON Schema is overkill for Postgres — this covers the 80% case.

CREATE OR REPLACE FUNCTION public.validate_initiative_metadata(
  p_kind text,
  p_metadata jsonb
) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_schema jsonb;
  v_field text;
  v_field_def jsonb;
  v_field_type text;
  v_actual_type text;
BEGIN
  SELECT custom_fields_schema INTO v_schema
  FROM public.initiative_kinds WHERE slug = p_kind;

  -- No schema or empty schema = anything goes
  IF v_schema IS NULL OR v_schema = '{}'::jsonb THEN
    RETURN true;
  END IF;

  -- Check required fields exist
  IF v_schema ? 'required' THEN
    FOR v_field IN SELECT jsonb_array_elements_text(v_schema->'required')
    LOOP
      IF NOT (p_metadata ? v_field) THEN
        RAISE EXCEPTION 'Missing required metadata field: "%"', v_field
          USING ERRCODE = 'P0007';
      END IF;
    END LOOP;
  END IF;

  -- Check field types (properties.*.type)
  IF v_schema ? 'properties' THEN
    FOR v_field, v_field_def IN SELECT * FROM jsonb_each(v_schema->'properties')
    LOOP
      IF p_metadata ? v_field THEN
        v_actual_type := jsonb_typeof(p_metadata->v_field);
        -- Skip null values (null is always valid)
        IF v_actual_type = 'null' THEN
          CONTINUE;
        END IF;
        v_field_type := v_field_def->>'type';

        CASE v_field_type
          WHEN 'string' THEN
            IF v_actual_type != 'string' THEN
              RAISE EXCEPTION 'Metadata field "%" must be string, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          WHEN 'number', 'integer' THEN
            IF v_actual_type != 'number' THEN
              RAISE EXCEPTION 'Metadata field "%" must be number, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          WHEN 'boolean' THEN
            IF v_actual_type != 'boolean' THEN
              RAISE EXCEPTION 'Metadata field "%" must be boolean, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          WHEN 'array' THEN
            IF v_actual_type != 'array' THEN
              RAISE EXCEPTION 'Metadata field "%" must be array, got %', v_field, v_actual_type
                USING ERRCODE = 'P0008';
            END IF;
          ELSE
            NULL; -- unknown type = skip validation
        END CASE;
      END IF;
    END LOOP;
  END IF;

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.validate_initiative_metadata(text, jsonb) IS
  'V4 Phase 6: Validate initiative metadata against kind custom_fields_schema (ADR-0009)';

GRANT EXECUTE ON FUNCTION public.validate_initiative_metadata(text, jsonb) TO authenticated;

-- ── Trigger: auto-validate on INSERT/UPDATE ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.trg_validate_initiative_metadata_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.validate_initiative_metadata(NEW.kind, NEW.metadata);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_initiative_metadata
  BEFORE INSERT OR UPDATE OF metadata, kind ON public.initiatives
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_validate_initiative_metadata_fn();

-- ── Seed custom_fields_schema for study_group (CPMAI use case) ──────────────

UPDATE public.initiative_kinds SET
  custom_fields_schema = '{
    "properties": {
      "max_enrollment": {"type": "integer", "description": "Maximum number of participants"},
      "exam_date": {"type": "string", "description": "Target exam date (ISO 8601)"},
      "min_mock_score": {"type": "number", "description": "Minimum mock exam score to qualify (0-100)"},
      "min_attendance_pct": {"type": "number", "description": "Minimum attendance percentage required (0-100)"},
      "enrollment_deadline": {"type": "string", "description": "Enrollment deadline (ISO 8601)"},
      "start_date": {"type": "string", "description": "Course start date"},
      "end_date": {"type": "string", "description": "Course end date"},
      "domains": {"type": "array", "description": "Study domains with weights"}
    },
    "required": []
  }'::jsonb
WHERE slug = 'study_group';

-- Congress custom fields
UPDATE public.initiative_kinds SET
  custom_fields_schema = '{
    "properties": {
      "venue": {"type": "string", "description": "Venue name and location"},
      "start_date": {"type": "string", "description": "Event start date"},
      "end_date": {"type": "string", "description": "Event end date"},
      "expected_attendees": {"type": "integer", "description": "Expected number of attendees"},
      "tracks": {"type": "array", "description": "Event tracks/verticals"},
      "website_url": {"type": "string", "description": "Event website URL"}
    },
    "required": []
  }'::jsonb
WHERE slug = 'congress';

-- PostgREST reload
NOTIFY pgrst, 'reload schema';
