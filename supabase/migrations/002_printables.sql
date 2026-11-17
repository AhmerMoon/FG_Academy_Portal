-- Additive migration: does not change existing attendance, awards or fees.
-- Run in Supabase SQL Editor before releasing the new app.
BEGIN;

CREATE TABLE IF NOT EXISTS public.printable_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL REFERENCES auth.users(id),
  teacher_name text NOT NULL,
  batch_id uuid NOT NULL REFERENCES public.batches(id),
  batch_name text NOT NULL,
  subject_code text NOT NULL CHECK (subject_code IN ('Phy','Chem','Math','Eng','Comp','Bio')),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  test_date date NOT NULL,
  copies integer NOT NULL CHECK (copies BETWEEN 1 AND 5000),
  notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 1000),
  file_name text NOT NULL CHECK (length(file_name) BETWEEN 1 AND 240),
  file_size integer NOT NULL CHECK (file_size BETWEEN 1 AND 20971520),
  file_path text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'uploading'
    CHECK (status IN ('uploading', 'pending', 'printed', 'deleting')),
  created_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  printed_at timestamptz,
  printed_by uuid REFERENCES auth.users(id),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS printable_requests_teacher_date_idx
  ON public.printable_requests (teacher_id, test_date);
CREATE INDEX IF NOT EXISTS printable_requests_expiry_idx
  ON public.printable_requests (expires_at);
CREATE INDEX IF NOT EXISTS printable_requests_status_created_idx
  ON public.printable_requests (status, created_at);

ALTER TABLE public.printable_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.printable_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.printable_requests TO authenticated;
GRANT ALL ON public.printable_requests TO service_role;

CREATE OR REPLACE FUNCTION public.printable_actor_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT role FROM public.user_profiles
  WHERE user_id = auth.uid() AND is_active = true AND role IN ('admin', 'teacher');
$$;
REVOKE ALL ON FUNCTION public.printable_actor_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.printable_actor_role() TO authenticated;

DROP POLICY IF EXISTS printable_requests_read ON public.printable_requests;
CREATE POLICY printable_requests_read ON public.printable_requests
  FOR SELECT TO authenticated USING (
    status IN ('pending', 'printed') AND expires_at > now()
    AND ((SELECT public.printable_actor_role()) = 'admin'
      OR ((SELECT public.printable_actor_role()) = 'teacher' AND teacher_id = (SELECT auth.uid())))
  );

CREATE OR REPLACE FUNCTION public.printable_submission_choices()
RETURNS TABLE (batch_id uuid, batch_name text, subject_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT DISTINCT b.id, b.name, ta.subject_code
  FROM public.batches b
  JOIN public.teacher_assignments ta ON ta.class_level = b.class_level
  WHERE ta.teacher_id = auth.uid() AND public.printable_actor_role() = 'teacher'
    AND ta.subject_code IN ('Phy','Chem','Math','Eng','Comp','Bio')
  ORDER BY b.name, ta.subject_code;
$$;
REVOKE ALL ON FUNCTION public.printable_submission_choices() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.printable_submission_choices() TO authenticated;

CREATE OR REPLACE FUNCTION public.reserve_printable_request(
  p_batch_id uuid, p_subject_code text, p_title text, p_test_date date,
  p_copies integer, p_notes text, p_file_name text, p_file_size integer
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_teacher_name text;
  v_batch_name text;
  v_ext text;
  v_path text;
  v_today date := (now() AT TIME ZONE 'Asia/Karachi')::date;
BEGIN
  IF public.printable_actor_role() IS DISTINCT FROM 'teacher' THEN
    RAISE EXCEPTION 'An active teacher account is required.';
  END IF;
  -- Serialize reservations per teacher, including quota checks.
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 2));
  SELECT full_name INTO v_teacher_name FROM public.user_profiles WHERE user_id = auth.uid();
  SELECT b.name INTO v_batch_name FROM public.batches b
  WHERE b.id = p_batch_id AND EXISTS (
    SELECT 1 FROM public.teacher_assignments ta WHERE ta.teacher_id = auth.uid()
      AND ta.class_level = b.class_level AND ta.subject_code = p_subject_code
  );
  IF v_batch_name IS NULL THEN
    RAISE EXCEPTION 'You can only submit for your assigned class and subject.';
  END IF;
  IF p_test_date IS NULL OR p_test_date < v_today OR p_test_date > v_today + 366 THEN
    RAISE EXCEPTION 'Choose a test date from today through the next year (Pakistan time).';
  END IF;
  IF p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 1 AND 120
    OR p_copies IS NULL OR p_copies NOT BETWEEN 1 AND 5000
    OR length(coalesce(p_notes, '')) > 1000 THEN
    RAISE EXCEPTION 'Enter a title, 1 to 5000 copies and instructions up to 1000 characters.';
  END IF;
  IF p_file_name IS NULL OR length(p_file_name) NOT BETWEEN 1 AND 240
    OR p_file_name ~ '[/\\]' OR p_file_name ~ '[[:cntrl:]]'
    OR p_file_size IS NULL OR p_file_size NOT BETWEEN 1 AND 20971520 THEN
    RAISE EXCEPTION 'Choose a PDF or Word file up to 20 MB with a valid file name.';
  END IF;
  v_ext := lower(substring(p_file_name FROM '\.([^.]+)$'));
  IF v_ext IS NULL OR v_ext NOT IN ('pdf','doc','docx') THEN
    RAISE EXCEPTION 'Only PDF, DOC and DOCX files are supported.';
  END IF;
  IF (SELECT count(*) FROM public.printable_requests
      WHERE teacher_id = auth.uid() AND created_at > now() - interval '1 day') >= 50 THEN
    RAISE EXCEPTION 'Daily submission limit reached (50). Contact the administrator.';
  END IF;
  v_path := auth.uid()::text || '/' || v_id::text || '/document.' || v_ext;
  INSERT INTO public.printable_requests (
    id, teacher_id, teacher_name, batch_id, batch_name, subject_code,
    title, test_date, copies, notes, file_name, file_size, file_path, expires_at
  ) VALUES (
    v_id, auth.uid(), v_teacher_name, p_batch_id, v_batch_name, p_subject_code,
    btrim(p_title), p_test_date, p_copies, btrim(coalesce(p_notes, '')),
    p_file_name, p_file_size, v_path,
    ((p_test_date + 2)::timestamp AT TIME ZONE 'Asia/Karachi')
  );
  RETURN jsonb_build_object('id', v_id, 'file_path', v_path);
END;
$$;
REVOKE ALL ON FUNCTION public.reserve_printable_request(uuid,text,text,date,integer,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_printable_request(uuid,text,text,date,integer,text,text,integer) TO authenticated;

-- Definer helper avoids dependence on table SELECT policies for invisible uploads.
CREATE OR REPLACE FUNCTION public.printable_storage_access(p_path text, p_upload boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.printable_requests r
    WHERE r.file_path = p_path AND r.expires_at > now()
      AND CASE WHEN p_upload THEN
        r.status = 'uploading' AND r.created_at > now() - interval '1 hour'
        AND r.teacher_id = auth.uid() AND public.printable_actor_role() = 'teacher'
      ELSE
        r.status IN ('pending','printed') AND (
          public.printable_actor_role() = 'admin'
          OR (public.printable_actor_role() = 'teacher' AND r.teacher_id = auth.uid())
        )
      END
  );
$$;
REVOKE ALL ON FUNCTION public.printable_storage_access(text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.printable_storage_access(text,boolean) TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('test-printables', 'test-printables', false, 20971520, ARRAY[
  'application/pdf', 'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]) ON CONFLICT (id) DO UPDATE SET public = false,
  file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS printable_files_insert ON storage.objects;
CREATE POLICY printable_files_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'test-printables' AND public.printable_storage_access(name, true));
DROP POLICY IF EXISTS printable_files_read ON storage.objects;
CREATE POLICY printable_files_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'test-printables' AND public.printable_storage_access(name, false));
-- No authenticated UPDATE / DELETE policy: prevents overwriting submitted tests.
-- Restrictive guards also protect this private bucket if the existing project
-- has a broad permissive policy for another feature. Other buckets are unchanged.
DROP POLICY IF EXISTS printable_files_guard_read ON storage.objects;
CREATE POLICY printable_files_guard_read ON storage.objects AS RESTRICTIVE
  FOR SELECT TO authenticated USING (
    bucket_id <> 'test-printables' OR public.printable_storage_access(name, false)
  );
DROP POLICY IF EXISTS printable_files_guard_insert ON storage.objects;
CREATE POLICY printable_files_guard_insert ON storage.objects AS RESTRICTIVE
  FOR INSERT TO authenticated WITH CHECK (
    bucket_id <> 'test-printables' OR public.printable_storage_access(name, true)
  );
DROP POLICY IF EXISTS printable_files_guard_update ON storage.objects;
CREATE POLICY printable_files_guard_update ON storage.objects AS RESTRICTIVE
  FOR UPDATE TO authenticated USING (bucket_id <> 'test-printables')
    WITH CHECK (bucket_id <> 'test-printables');
DROP POLICY IF EXISTS printable_files_guard_delete ON storage.objects;
CREATE POLICY printable_files_guard_delete ON storage.objects AS RESTRICTIVE
  FOR DELETE TO authenticated USING (bucket_id <> 'test-printables');
DROP POLICY IF EXISTS printable_files_guard_anon ON storage.objects;
CREATE POLICY printable_files_guard_anon ON storage.objects AS RESTRICTIVE
  FOR ALL TO anon USING (bucket_id <> 'test-printables')
    WITH CHECK (bucket_id <> 'test-printables');

CREATE OR REPLACE FUNCTION public.finalize_printable_request(p_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_request public.printable_requests;
BEGIN
  SELECT * INTO v_request FROM public.printable_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR v_request.teacher_id IS DISTINCT FROM auth.uid()
    OR public.printable_actor_role() IS DISTINCT FROM 'teacher' THEN
    RAISE EXCEPTION 'This upload is not available to your account.';
  END IF;
  -- Idempotent if the first successful response was lost in transit.
  IF v_request.status IN ('pending','printed') AND v_request.expires_at > now() THEN RETURN; END IF;
  IF v_request.status <> 'uploading' OR v_request.expires_at <= now()
    OR v_request.created_at <= now() - interval '1 hour' THEN
    RAISE EXCEPTION 'This upload has expired. Start a new submission.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'test-printables'
    AND o.name = v_request.file_path AND (o.metadata->>'size')::bigint = v_request.file_size) THEN
    RAISE EXCEPTION 'The file upload is incomplete. Submit the file again.';
  END IF;
  UPDATE public.printable_requests SET status = 'pending', submitted_at = now() WHERE id = p_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_printable_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_printable_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_printable_printed(p_request_id uuid, p_printed boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF public.printable_actor_role() IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'Administrator access is required.';
  END IF;
  IF p_printed IS NULL THEN RAISE EXCEPTION 'Choose a valid print status.'; END IF;
  UPDATE public.printable_requests SET
    status = CASE WHEN p_printed THEN 'printed' ELSE 'pending' END,
    printed_at = CASE WHEN p_printed THEN now() ELSE NULL END,
    printed_by = CASE WHEN p_printed THEN auth.uid() ELSE NULL END
  WHERE id = p_request_id AND status IN ('pending','printed') AND expires_at > now();
  IF NOT FOUND THEN RAISE EXCEPTION 'This printable has expired. Refresh the list.'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_printable_printed(uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_printable_printed(uuid,boolean) TO authenticated;

-- Only the cleanup function's service-role client can call this RPC.
-- Claim rows before removing objects so a late finalize cannot publish a deleted file.
CREATE OR REPLACE FUNCTION public.claim_printables_cleanup()
RETURNS TABLE (id uuid, file_path text)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  WITH candidates AS (
    SELECT r.id FROM public.printable_requests r
    WHERE r.expires_at <= now() OR r.status = 'deleting'
      OR (r.status = 'uploading' AND r.created_at <= now() - interval '1 hour')
    ORDER BY r.created_at LIMIT 100 FOR UPDATE SKIP LOCKED
  )
  UPDATE public.printable_requests r SET status = 'deleting'
  FROM candidates c WHERE r.id = c.id RETURNING r.id, r.file_path;
$$;
REVOKE ALL ON FUNCTION public.claim_printables_cleanup() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_printables_cleanup() TO service_role;

-- Sweep interrupted Storage uploads whose request row is already gone.
CREATE OR REPLACE FUNCTION public.orphan_printable_files()
RETURNS TABLE (file_path text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT o.name FROM storage.objects o
  WHERE o.bucket_id = 'test-printables' AND o.created_at < now() - interval '1 hour'
    AND NOT EXISTS (SELECT 1 FROM public.printable_requests r WHERE r.file_path = o.name)
  ORDER BY o.created_at LIMIT 100;
$$;
REVOKE ALL ON FUNCTION public.orphan_printable_files() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.orphan_printable_files() TO service_role;

COMMIT;
