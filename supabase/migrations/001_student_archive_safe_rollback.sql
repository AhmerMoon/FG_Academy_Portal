-- ============================================================================
-- ROLLBACK SCRIPT: 001_student_archive_safe_rollback.sql
-- PURPOSE: Restores original schema state prior to 001_student_archive_safe.sql
--
-- SAFETY GUARANTEES:
-- - Restores original RLS policies, trigger states, and helper functions.
-- - Restores original DELETE permissions.
-- - Preserves archive metadata columns (is_archived, archived_at, archived_by,
--   archive_reason) by default to prevent casual data loss.
-- - Wrapped in a single transaction block.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. DROP ADDED ROW-LEVEL PROTECTION TRIGGERS & FUNCTIONS
-- ----------------------------------------------------------------------------
-- Remove award marks protection trigger
DROP TRIGGER IF EXISTS trg_protect_archived_student_award_marks ON public.award_marks;
DROP FUNCTION IF EXISTS public.prevent_archived_student_award_mark_change();

-- Remove attendance protection trigger
DROP TRIGGER IF EXISTS trg_protect_archived_student_attendance ON public.attendance;
DROP FUNCTION IF EXISTS public.prevent_archived_student_attendance_change();

-- Remove hard delete blockers
DROP TRIGGER IF EXISTS trg_prevent_batch_hard_delete ON public.batches;
DROP FUNCTION IF EXISTS public.prevent_batch_hard_delete();

DROP TRIGGER IF EXISTS trg_prevent_student_hard_delete ON public.students;
DROP FUNCTION IF EXISTS public.prevent_student_hard_delete();

-- ----------------------------------------------------------------------------
-- 2. DROP ARCHIVE, RESTORE & ADD RPCs
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.archive_student(uuid, text);
DROP FUNCTION IF EXISTS public.restore_student(uuid);
DROP FUNCTION IF EXISTS public.portal_add_student_simple(text, uuid, text);

-- ----------------------------------------------------------------------------
-- 3. RESTORE ORIGINAL STUDENTS RLS POLICIES & DELETE PERMISSIONS
-- ----------------------------------------------------------------------------
-- Restore original students_select_portal policy
DROP POLICY IF EXISTS students_select_portal ON public.students;
CREATE POLICY students_select_portal ON public.students
  FOR SELECT TO authenticated
  USING (
    public.is_portal_admin()
    OR public.can_access_batch(batch_id)
  );

-- Restore original students_delete_admin policy & grants
DROP POLICY IF EXISTS students_delete_admin ON public.students;
CREATE POLICY students_delete_admin ON public.students
  FOR DELETE TO authenticated
  USING (
    public.is_portal_admin()
  );

GRANT DELETE ON public.students TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. RESTORE ORIGINAL ATTENDANCE RLS POLICIES & HELPER FUNCTION
-- ----------------------------------------------------------------------------
-- Restore original can_manage_attendance function definition
CREATE OR REPLACE FUNCTION public.can_manage_attendance(
  p_student_id uuid,
  p_batch_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.students s
    WHERE s.id = p_student_id
      AND s.batch_id = p_batch_id
      AND public.can_access_batch(p_batch_id)
  );
$$;

-- Restore original attendance RLS policies
DROP POLICY IF EXISTS attendance_insert_portal ON public.attendance;
CREATE POLICY attendance_insert_portal ON public.attendance
  FOR INSERT TO authenticated
  WITH CHECK (
    (public.is_portal_admin() OR public.can_manage_attendance(student_id, batch_id))
  );

DROP POLICY IF EXISTS attendance_update_portal ON public.attendance;
CREATE POLICY attendance_update_portal ON public.attendance
  FOR UPDATE TO authenticated
  USING (
    (public.is_portal_admin() OR public.can_manage_attendance(student_id, batch_id))
  )
  WITH CHECK (
    (public.is_portal_admin() OR public.can_manage_attendance(student_id, batch_id))
  );

DROP POLICY IF EXISTS attendance_delete_admin ON public.attendance;
CREATE POLICY attendance_delete_admin ON public.attendance
  FOR DELETE TO authenticated
  USING (
    public.is_portal_admin()
  );

-- ----------------------------------------------------------------------------
-- 5. DROP ADDED INDEXES
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_students_active_batch;
DROP INDEX IF EXISTS public.idx_students_archived;

-- ----------------------------------------------------------------------------
-- 6. ARCHIVE METADATA COLUMNS (PRESERVED BY DEFAULT)
-- ----------------------------------------------------------------------------
-- NOTE: The archive columns (is_archived, archived_at, archived_by, archive_reason)
-- are NOT dropped by default to prevent irreversible loss of archive history.
-- If you explicitly wish to drop the columns as well, uncomment the following line:
--
-- ALTER TABLE public.students
--   DROP COLUMN IF EXISTS is_archived,
--   DROP COLUMN IF EXISTS archived_at,
--   DROP COLUMN IF EXISTS archived_by,
--   DROP COLUMN IF EXISTS archive_reason;

COMMIT;

