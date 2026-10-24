-- ACADEMY PORTAL: FINAL CLEANUP (based on exported Supabase schema snapshot)
-- IMPORTANT: Run only after backing up the live DB and preparing updated clients.
-- Removes fee tables/views/functions + student fee fields, adds archive protection.
-- The transaction rolls back if a dependency prevents a safe DROP (NO CASCADE).
BEGIN;

-- 1) Archive metadata. Keep current status ('enrolled' / 'trial') independent.
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid,
  ADD COLUMN IF NOT EXISTS archive_reason text;

CREATE INDEX IF NOT EXISTS idx_students_active_batch
  ON public.students (batch_id, name) WHERE is_archived = false;
CREATE INDEX IF NOT EXISTS idx_students_archived
  ON public.students (archived_at DESC) WHERE is_archived = true;

-- Preserve both attendance and marks; hard DELETE of a student is forbidden.
CREATE OR REPLACE FUNCTION public.prevent_student_hard_delete()
RETURNS trigger LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Student deletion disabled. Archive the student instead.'
    USING ERRCODE = '23514';
END;
$$;
DROP TRIGGER IF EXISTS trg_prevent_student_hard_delete ON public.students;
CREATE TRIGGER trg_prevent_student_hard_delete
  BEFORE DELETE ON public.students FOR EACH ROW
  EXECUTE FUNCTION public.prevent_student_hard_delete();

-- Batch deletion can cascade to students/attendance/award tests: block too.
CREATE OR REPLACE FUNCTION public.prevent_batch_hard_delete()
RETURNS trigger LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Batch deletion disabled to preserve attendance and award history.'
    USING ERRCODE = '23514';
END;
$$;
DROP TRIGGER IF EXISTS trg_prevent_batch_hard_delete ON public.batches;
CREATE TRIGGER trg_prevent_batch_hard_delete
  BEFORE DELETE ON public.batches FOR EACH ROW
  EXECUTE FUNCTION public.prevent_batch_hard_delete();

-- 2) Admin-only archive/restore RPCs. No historical row or student UUID changes.
CREATE OR REPLACE FUNCTION public.archive_student(
  p_student_id uuid, p_reason text DEFAULT 'Left academy'
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_portal_admin() THEN
    RAISE EXCEPTION 'Only an active admin can archive students.'
      USING ERRCODE = '42501';
  END IF;
  UPDATE public.students
     SET is_archived = true,
         archived_at = now(),
         archived_by = auth.uid(),
         archive_reason = left(nullif(btrim(p_reason), ''), 500)
   WHERE id = p_student_id AND is_archived = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Student not found or already archived.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_student(
  p_student_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_portal_admin() THEN
    RAISE EXCEPTION 'Only an active admin can restore students.'
      USING ERRCODE = '42501';
  END IF;
  UPDATE public.students
     SET is_archived = false,
         archived_at = null,
         archived_by = null,
         archive_reason = null
   WHERE id = p_student_id AND is_archived = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Student not found or not archived.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.archive_student(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_student(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.archive_student(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_student(uuid) TO authenticated;

-- Teacher cannot fetch archived students through normal student SELECT.
DROP POLICY IF EXISTS students_select_portal ON public.students;
CREATE POLICY students_select_portal ON public.students
  FOR SELECT TO authenticated
  USING (
    public.is_portal_admin()
    OR (is_archived = false AND public.can_access_batch(batch_id))
  );

DROP POLICY IF EXISTS students_delete_admin ON public.students;
REVOKE DELETE ON public.students FROM anon, authenticated;

-- Teachers cannot mark NEW attendance for archived students.
-- The existing admin override still permits looking up historic records.
CREATE OR REPLACE FUNCTION public.can_manage_attendance(
  p_student_id uuid, p_batch_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.students s
    WHERE s.id = p_student_id
      AND s.batch_id = p_batch_id
      AND s.is_archived = false
      AND public.can_access_batch(p_batch_id)
  );
$$;

-- 3) Fee-free student creation; subject/stream selection MUST be non-empty.
-- Preserves existing behavior: new student receives today's Present attendance.
CREATE OR REPLACE FUNCTION public.portal_add_student(
  p_name text, p_batch_id uuid, p_subjects text[]
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text := btrim(coalesce(p_name, ''));
  v_class_level smallint;
  v_student_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Please log in first.' USING ERRCODE = '42501';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Student name is required.';
  END IF;
  IF p_subjects IS NULL OR cardinality(p_subjects) < 1 THEN
    RAISE EXCEPTION 'Select at least one subject/stream.';
  END IF;
  SELECT b.class_level INTO v_class_level
    FROM public.batches b WHERE b.id = p_batch_id;
  IF v_class_level IS NULL THEN
    RAISE EXCEPTION 'Invalid batch.';
  END IF;
  IF NOT (public.is_portal_admin() OR public.can_access_batch(p_batch_id)) THEN
    RAISE EXCEPTION 'Not allowed to add a student to this batch.'
      USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_portal_admin() AND NOT EXISTS (
    SELECT 1 FROM public.teacher_assignments ta
    WHERE ta.teacher_id = auth.uid()
      AND ta.class_level = v_class_level
      AND ta.subject_code = ANY(p_subjects)
  ) THEN
    RAISE EXCEPTION 'Include your assigned subject in the selected stream.'
      USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.students s
    WHERE s.batch_id = p_batch_id
      AND lower(btrim(s.name)) = lower(v_name)
  ) THEN
    RAISE EXCEPTION 'Name exists in this batch (check Archive for a restore).';
  END IF;
  INSERT INTO public.students (name,batch_id,stream,status)
  VALUES (v_name,p_batch_id,p_subjects,'enrolled')
  RETURNING id INTO v_student_id;
  INSERT INTO public.attendance (student_id,batch_id,date,status)
  VALUES (v_student_id,p_batch_id,(now() AT TIME ZONE 'Asia/Karachi')::date,'present')
  ON CONFLICT (student_id,date)
  DO UPDATE SET batch_id = EXCLUDED.batch_id, status = 'present';
  RETURN v_student_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_add_student(text,uuid,text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.portal_add_student(text,uuid,text[]) TO authenticated;

-- Backward-compatible teacher attendance-add RPC, now with NO fee action.
CREATE OR REPLACE FUNCTION public.portal_add_student_from_attendance_v2(
  p_name text, p_batch_id uuid, p_subjects text[]
) RETURNS uuid LANGUAGE sql SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.portal_add_student(p_name,p_batch_id,p_subjects);
$$;
REVOKE ALL ON FUNCTION public.portal_add_student_from_attendance_v2(text,uuid,text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.portal_add_student_from_attendance_v2(text,uuid,text[]) TO authenticated;

-- 4) Remove ALL known fee reporting views in dependency order, without CASCADE.
DROP VIEW IF EXISTS public.fee_audit_ecc_balance;
DROP VIEW IF EXISTS public.fee_audit_staff_summary;
DROP VIEW IF EXISTS public.fee_audit_final_summary;
DROP VIEW IF EXISTS public.fee_audit_ssc_subject_summary;
DROP VIEW IF EXISTS public.fee_audit_hssc_subject_summary;
DROP VIEW IF EXISTS public.fee_audit_class_totals;
DROP VIEW IF EXISTS public.fee_audit_class_student_rows;
DROP VIEW IF EXISTS public.fee_summary_totals;
DROP VIEW IF EXISTS public.fee_financial_reports;

-- Only user-facing trigger on students which writes to fee_payments.
DROP TRIGGER IF EXISTS trg_sync_unpaid_fee_subject_stream ON public.students;

-- Remove fee tables (financial data is PERMANENTLY deleted; keep a backup).
-- DROP is intentionally without CASCADE: unexpected dependencies force rollback.
DROP TABLE IF EXISTS public.fee_payments;
DROP TABLE IF EXISTS public.fee_staff_payment_overrides;
DROP TABLE IF EXISTS public.fee_staff_allocations;
DROP TABLE IF EXISTS public.fee_month_teacher_assignments;
DROP TABLE IF EXISTS public.fee_month_distribution_settings;
DROP TABLE IF EXISTS public.fee_teacher_assignments;
DROP TABLE IF EXISTS public.fee_distribution_settings;
DROP TABLE IF EXISTS public.fee_audit_month_settings;

-- Remove fee-only stored procedures/functions (exact exported signatures).
DROP FUNCTION IF EXISTS public.admin_add_fee_student(text,uuid,numeric,text[],text);
DROP FUNCTION IF EXISTS public.add_fee_student(text,uuid,numeric,text[],text);
DROP FUNCTION IF EXISTS public.admin_initialize_fee_month(text);
DROP FUNCTION IF EXISTS public.initialize_fee_month(text);
DROP FUNCTION IF EXISTS public.admin_set_fee_payment_status(uuid,text,text,numeric);
DROP FUNCTION IF EXISTS public.set_fee_payment_status(uuid,text,text,numeric);
DROP FUNCTION IF EXISTS public.admin_reset_fee_staff_payment(text,text);
DROP FUNCTION IF EXISTS public.admin_set_student_fee_remarks(uuid,text);
DROP FUNCTION IF EXISTS public.admin_set_fee_staff_payment(text,text,numeric);
DROP FUNCTION IF EXISTS public.admin_update_fee_distribution(text,numeric,numeric,numeric,numeric,numeric,numeric);
DROP FUNCTION IF EXISTS public.admin_update_fee_teacher_name(text,text,text);
DROP FUNCTION IF EXISTS public.admin_ensure_fee_month_setup(text);
DROP FUNCTION IF EXISTS public.admin_update_fee_month_distribution(text,text,numeric,numeric,numeric,numeric,numeric,numeric);
DROP FUNCTION IF EXISTS public.admin_update_fee_month_teacher_name(text,text,text,text);
DROP FUNCTION IF EXISTS public.fee_report_class_code(smallint,text);
DROP FUNCTION IF EXISTS public.fee_report_group_label(smallint,text[]);
DROP FUNCTION IF EXISTS public.fee_report_group_order(smallint,text[]);
DROP FUNCTION IF EXISTS public.set_fee_payment_updated_at();
DROP FUNCTION IF EXISTS public.sync_fee_payment_batch();
DROP FUNCTION IF EXISTS public.snapshot_fee_payment_subject_stream();
DROP FUNCTION IF EXISTS public.sync_unpaid_fee_subject_stream();

-- Student identity, attendance, marks, subjects and batch are preserved.
ALTER TABLE public.students
  DROP COLUMN IF EXISTS default_fee,
  DROP COLUMN IF EXISTS fee_remarks;

-- Defensive: if schema drift introduced unknown fee objects, fail and ROLLBACK.
DO $$
DECLARE v_left text;
BEGIN
  SELECT string_agg(s, ', ') INTO v_left FROM (
    SELECT 'table/view:' || c.relname AS s
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname LIKE 'fee\_%' ESCAPE '\'
       AND c.relkind IN ('r','v','m','p','f')
    UNION ALL
    SELECT 'function:' || p.proname AS s
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname LIKE '%fee%'
  ) d;
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'Unrecognized fee objects remain: %. Transaction rolled back.', v_left;
  END IF;
END;
$$;

COMMIT;

-- Read-only check. Previously deleted student rows are NOT restored by this migration.
SELECT is_archived, count(*) AS students
  FROM public.students GROUP BY is_archived ORDER BY is_archived;
