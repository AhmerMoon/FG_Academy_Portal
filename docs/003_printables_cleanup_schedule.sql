-- Run AFTER 002_printables.sql and deploying cleanup-printables.
-- First add a Vault secret named printables_cleanup_secret in the Supabase
-- dashboard. Its value must match the Edge secret PRINTABLES_CLEANUP_SECRET.
-- Generate a random value of at least 32 bytes; do not commit it to Git.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'printables_cleanup_secret') THEN
    RAISE EXCEPTION 'Create the Vault secret printables_cleanup_secret first. See docs/PRINTABLES_SETUP.md.';
  END IF;
END;
$$;

-- Re-running updates the existing named job, avoiding duplicate schedules.
-- Every 15 minutes, even when no teacher/admin has the app open.
SELECT cron.schedule('academy-cleanup-printables', '*/15 * * * *', $$
  SELECT net.http_post(
    url := 'https://acwpurtriixeweteipjl.supabase.co/functions/v1/cleanup-printables',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-printables-secret', (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'printables_cleanup_secret' LIMIT 1
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
$$);

-- Verification: the job should be active.
SELECT jobid, jobname, schedule, active FROM cron.job
WHERE jobname = 'academy-cleanup-printables';
