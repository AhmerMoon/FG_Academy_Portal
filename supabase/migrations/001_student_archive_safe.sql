-- ============================================================================
-- MIGRATION: 001_student_archive_safe.sql
-- PURPOSE: Safe, non-destructive Student Archive & Restore System
--
-- GAPS ADDRESSED IN THIS REVISION:
-- 1. Attendance Read-Only Enforcement:
--    Blocks INSERT, UPDATE, and DELETE on public.attendance for archived
--    students via both RLS policies and row-level trigger. Admins retain full
--    SELECT access to historical attendance; teachers remain restricted to
--    active students only.
-- 2. Award Marks Immutability & Cascade Protection:
--    A BEFORE INSERT OR UPDATE OR DELETE trigger on public.award_marks
--    blocks any mutation or removal of marks belonging to an archived student.
--    This protects historical marks against save_award_marks(),
--    clear_award_mark(), delete_award_test(), and foreign key cascading deletes,
--    while preserving all standard active-student workflows.
-- 3. Hard Delete Prevention:
--    Blocks hard DELETE on public.students and public.batches.
-- 4. Admin-Only Archive & Restore RPCs:
--    Provides archive_student() and restore_student() with strict is_portal_admin()
--    checks, preserving original student UUIDs and all historical records.
--
-- SAFETY GUARANTEES:
-- - No tables, views, functions, or columns are dropped.
-- - No fee tables, fee columns, or fee RPCs are altered or removed.
-- - No existing student, attendance, or award mark records are altered.
-- - Transaction-wrapped and idempotent (safe to review and rerun).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. ADD ARCHIVE METADATA TO STUDENTS TABLE
-- ----------------------------------------------------------------------------
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid,
  ADD COLUMN IF NOT EXISTS archive_reason text;

-- Performance indexes for active vs archived student queries
CREATE INDEX IF NOT EXISTS idx_students_active_batch
  ON public.students (batch_id, name)
  WHERE is_archived = false;

CREATE INDEX IF NOT EXISTS idx_students_archived
  ON public.students (archived_at DESC)
  WHERE is_archived = true;

-- ----------------------------------------------------------------------------
-- 2. HARD DELETE PREVENTION (STUDENTS & BATCHES)
-- ----------------------------------------------------------------------------
-- Prevent hard delete of student records (preserves attendance & marks history)
CREATE OR REPLACE FUNCTION public.prevent_student_hard_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Student hard deletion is disabled. Archive the student instead.'
    USING ERRCODE = '23514';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_student_hard_delete ON public.students;
CREATE TRIGGER trg_prevent_student_hard_delete
  BEFORE DELETE ON public.students
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_student_hard_delete();

-- Prevent hard delete of batches (avoids cascade deletion of students/attendance)
CREATE OR REPLACE FUNCTION public.prevent_batch_hard_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Batch deletion is disabled to protect student, attendance, and award history.'
    USING ERRCODE = '23514';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_batch_hard_delete ON public.batches;
CREATE TRIGGER trg_prevent_batch_hard_delete
  BEFORE DELETE ON public.batches
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_batch_hard_delete();

-- ----------------------------------------------------------------------------
-- 3. ADMIN-ONLY ARCHIVE AND RESTORE RPCs
-- ----------------------------------------------------------------------------
-- Archive student RPC: marks student as archived and preserves student UUID & history
CREATE OR REPLACE FUNCTION public.archive_student(
  p_student_id uuid,
  p_reason text DEFAULT 'Left academy'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_portal_admin() THEN
    RAISE EXCEPTION 'Only an active administrator can archive students.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.students
     SET is_archived = true,
         archived_at = now(),
         archived_by = auth.uid(),
         archive_reason = COALESCE(left(nullif(btrim(p_reason), ''), 500), 'Left academy')
   WHERE id = p_student_id
     AND is_archived = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Student not found or already archived.';
  END IF;
END;
$$;

-- Restore student RPC: clears archive status while preserving exact UUID & history
CREATE OR REPLACE FUNCTION public.restore_student(
  p_student_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_portal_admin() THEN
    RAISE EXCEPTION 'Only an active administrator can restore students.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.students
     SET is_archived = false,
         archived_at = null,
         archived_by = null,
         archive_reason = null
   WHERE id = p_student_id
     AND is_archived = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Student not found or not currently archived.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.archive_student(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_student(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.archive_student(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_student(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. RLS & ACCESS CONTROL ON STUDENTS TABLE
-- ----------------------------------------------------------------------------
-- Restrict archived students from teacher-facing SELECT while allowing admin full view
DROP POLICY IF EXISTS students_select_portal ON public.students;
CREATE POLICY students_select_portal ON public.students
  FOR SELECT TO authenticated
  USING (
    public.is_portal_admin()
    OR (is_archived = false AND public.can_access_batch(batch_id))
  );

-- Remove direct DELETE permission from client queries on students table
DROP POLICY IF EXISTS students_delete_admin ON public.students;
REVOKE DELETE ON public.students FROM anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. ATTENDANCE PROTECTION (READ-ONLY HISTORICAL ACCESS FOR ARCHIVED STUDENTS)
-- ----------------------------------------------------------------------------
-- Helper function: ensures non-admins can only manage attendance for active students
CREATE OR REPLACE FUNCTION public.can_manage_attendance(
  p_student_id uuid,
  p_batch_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
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

-- Update Attendance RLS policies to prohibit mutation of archived student rows,
-- even for admins, while preserving admin SELECT access to historical records.
DROP POLICY IF EXISTS attendance_insert_portal ON public.attendance;
CREATE POLICY attendance_insert_portal ON public.attendance
  FOR INSERT TO authenticated
  WITH CHECK (
    (public.is_portal_admin() OR public.can_manage_attendance(student_id, batch_id))
    AND NOT EXISTS (
      SELECT 1 FROM public.students s
      WHERE s.id = attendance.student_id AND s.is_archived = true
    )
  );

DROP POLICY IF EXISTS attendance_update_portal ON public.attendance;
CREATE POLICY attendance_update_portal ON public.attendance
  FOR UPDATE TO authenticated
  USING (
    (public.is_portal_admin() OR public.can_manage_attendance(student_id, batch_id))
    AND NOT EXISTS (
      SELECT 1 FROM public.students s
      WHERE s.id = attendance.student_id AND s.is_archived = true
    )
  )
  WITH CHECK (
    (public.is_portal_admin() OR public.can_manage_attendance(student_id, batch_id))
    AND NOT EXISTS (
      SELECT 1 FROM public.students s
      WHERE s.id = attendance.student_id AND s.is_archived = true
    )
  );

DROP POLICY IF EXISTS attendance_delete_admin ON public.attendance;
CREATE POLICY attendance_delete_admin ON public.attendance
  FOR DELETE TO authenticated
  USING (
    public.is_portal_admin()
    AND NOT EXISTS (
      SELECT 1 FROM public.students s
      WHERE s.id = attendance.student_id AND s.is_archived = true
    )
  );

-- Row-level trigger on public.attendance:
-- Enforces that no attendance row belonging to an archived student can be
-- inserted, modified, or deleted by any user or SECURITY DEFINER function.
CREATE OR REPLACE FUNCTION public.prevent_archived_student_attendance_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_student_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_student_id := OLD.student_id;
  ELSE
    v_student_id := NEW.student_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.students s
    WHERE s.id = v_student_id
      AND s.is_archived = true
  ) THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Cannot delete historical attendance records of an archived student.'
        USING ERRCODE = '23514';
    ELSE
      RAISE EXCEPTION 'Cannot record or modify attendance for an archived student. Restore the student first.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_archived_student_attendance ON public.attendance;
CREATE TRIGGER trg_protect_archived_student_attendance
  BEFORE INSERT OR UPDATE OR DELETE ON public.attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_archived_student_attendance_change();

-- ----------------------------------------------------------------------------
-- 6. AWARD MARKS PROTECTION (IMMUTABILITY & CASCADE PROTECTION)
-- ----------------------------------------------------------------------------
-- Row-level trigger on public.award_marks:
-- Blocks INSERT, UPDATE, or DELETE of marks belonging to an archived student.
-- This protects archived marks against:
-- - save_award_marks()
-- - clear_award_mark()
-- - delete_award_test() (which runs DELETE FROM award_marks WHERE test_id = ...)
-- - Foreign key cascading deletes (ON DELETE CASCADE from award_tests or students)
-- Normal active-student workflows are unaffected because active students have is_archived = false.
CREATE OR REPLACE FUNCTION public.prevent_archived_student_award_mark_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_student_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_student_id := OLD.student_id;
  ELSE
    v_student_id := NEW.student_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.students s
    WHERE s.id = v_student_id
      AND s.is_archived = true
  ) THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Cannot delete or alter historical award marks of an archived student.'
        USING ERRCODE = '23514';
    ELSE
      RAISE EXCEPTION 'Cannot record or modify award marks for an archived student. Restore the student first.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_archived_student_award_marks ON public.award_marks;
CREATE TRIGGER trg_protect_archived_student_award_marks
  BEFORE INSERT OR UPDATE OR DELETE ON public.award_marks
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_archived_student_award_mark_change();

-- ----------------------------------------------------------------------------
-- 7. SIMPLIFIED STUDENT CREATION RPC (STREAM-BASED)
-- ----------------------------------------------------------------------------
-- Creates student with mandatory stream code, setting default fees automatically:
-- - Rs 5,500 for Classes 9/10
-- - Rs 6,000 for Classes 11/12
-- Converts stream code into full subjects array:
--   Classes 9 & 10:
--     'Comp' -> Phy, Chem, Math, Eng, Comp
--     'Bio'  -> Phy, Chem, Math, Eng, Bio
--   Classes 11 & 12:
--     'Comp' -> Phy, Math, Eng, Comp (FCS)
--     'Chem' -> Phy, Chem, Math, Eng (Pre-Engineering)
--     'Bio'  -> Phy, Chem, Eng, Bio (Pre-Medical)
-- Preserves existing new-student attendance behavior (marks today as Present).
-- Prevents re-creating an archived student with the same name.
CREATE OR REPLACE FUNCTION public.portal_add_student_simple(
  p_name text,
  p_batch_id uuid,
  p_group_code text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_class_level integer;
  v_student_id uuid;
  v_trimmed_name text := btrim(COALESCE(p_name, ''));
  v_code text := btrim(COALESCE(p_group_code, ''));
  v_subjects text[];
  v_default_fee numeric;
  v_today date := current_date;
BEGIN
  -- Permission check
  IF NOT (public.is_portal_admin() OR public.can_access_batch(p_batch_id)) THEN
    RAISE EXCEPTION 'You do not have permission to add students to this batch.'
      USING ERRCODE = '42501';
  END IF;

  IF v_trimmed_name = '' THEN
    RAISE EXCEPTION 'Student name is required.'
      USING ERRCODE = '23514';
  END IF;

  -- Get class level
  SELECT class_level INTO v_class_level
  FROM public.batches
  WHERE id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Batch not found.'
      USING ERRCODE = '23503';
  END IF;

  -- Check active student duplicate
  IF EXISTS (
    SELECT 1 FROM public.students
    WHERE batch_id = p_batch_id
      AND lower(btrim(name)) = lower(v_trimmed_name)
      AND is_archived = false
  ) THEN
    RAISE EXCEPTION 'A student with this name already exists in this batch.'
      USING ERRCODE = '23505';
  END IF;

  -- Check archived student duplicate
  IF EXISTS (
    SELECT 1 FROM public.students
    WHERE batch_id = p_batch_id
      AND lower(btrim(name)) = lower(v_trimmed_name)
      AND is_archived = true
  ) THEN
    RAISE EXCEPTION 'An archived student with this name already exists in this batch. Restore the student instead.'
      USING ERRCODE = '23505';
  END IF;

  -- Stream mapping & fee assignment
  IF v_class_level IN (9, 10) THEN
    v_default_fee := 5500;
    IF v_code = 'Comp' THEN
      v_subjects := ARRAY['Phy', 'Chem', 'Math', 'Eng', 'Comp'];
    ELSIF v_code = 'Bio' THEN
      v_subjects := ARRAY['Phy', 'Chem', 'Math', 'Eng', 'Bio'];
    ELSE
      RAISE EXCEPTION 'Invalid stream for class %: %. Expected Comp or Bio.', v_class_level, v_code
        USING ERRCODE = '23514';
    END IF;
  ELSIF v_class_level IN (11, 12) THEN
    v_default_fee := 6000;
    IF v_code = 'Comp' THEN
      v_subjects := ARRAY['Phy', 'Math', 'Eng', 'Comp'];
    ELSIF v_code = 'Chem' THEN
      v_subjects := ARRAY['Phy', 'Chem', 'Math', 'Eng'];
    ELSIF v_code = 'Bio' THEN
      v_subjects := ARRAY['Phy', 'Chem', 'Eng', 'Bio'];
    ELSE
      RAISE EXCEPTION 'Invalid stream for class %: %. Expected Comp, Chem, or Bio.', v_class_level, v_code
        USING ERRCODE = '23514';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported class level %.', v_class_level
      USING ERRCODE = '23514';
  END IF;

  -- Insert student
  INSERT INTO public.students (
    name,
    batch_id,
    stream,
    default_fee,
    status,
    is_archived
  ) VALUES (
    v_trimmed_name,
    p_batch_id,
    v_subjects,
    v_default_fee,
    'enrolled',
    false
  ) RETURNING id INTO v_student_id;

  -- Mark today's attendance as Present
  INSERT INTO public.attendance (
    student_id,
    batch_id,
    date,
    status
  ) VALUES (
    v_student_id,
    p_batch_id,
    v_today,
    'present'
  ) ON CONFLICT (student_id, date) DO NOTHING;

  RETURN v_student_id;
END;
$$;

REVOKE ALL ON FUNCTION public.portal_add_student_simple(text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.portal_add_student_simple(text, uuid, text) TO authenticated;

COMMIT;
