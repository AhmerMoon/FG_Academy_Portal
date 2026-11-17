# Printables setup and release

The Flutter implementation is ready in this repository. The live Supabase
project still needs the SQL and Edge Function below. Do these steps **before**
distributing the updated app. No existing attendance, award, student or fee
records are modified by the new migration.

Local verification: all 10 Flutter tests passed, Flutter analysis reported no
issues, and the web release build completed. PostgreSQL parsing passed for the
migration, its function bodies and the schedule script. SQL/Storage policies
and the Edge Function still require the real-account checks below after
deployment. Windows compilation could not run because this PC lacks the Visual
Studio C++ toolchain. Android compilation hit local Kotlin cross-drive cache
and memory failures; a successful Android build is still required before release.

## 1. Add the database and private bucket

1. Open your existing Academy Supabase project.
2. Open **SQL Editor → New query**.
3. Paste the entire contents of
   [`supabase/migrations/002_printables.sql`](../supabase/migrations/002_printables.sql)
   and run it. Run this new migration only; unrelated older cleanup scripts are
   not part of Printables setup.
4. Confirm that `public.printable_requests` exists and Storage has the **private**
   bucket `test-printables` with a 20 MB file limit.

Teacher class/subject choices come from existing `teacher_assignments` joined
to `batches.class_level`. Teachers without an active profile or assignment cannot
submit. No new teacher accounts or assignments need to be created if those are
already correct.

## 2. Set a cleanup secret

Generate a new random secret locally. In PowerShell:

```powershell
$printablesRandom = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$printablesSecretBytes = New-Object byte[] 32
$printablesRandom.GetBytes($printablesSecretBytes)
[Convert]::ToBase64String($printablesSecretBytes)
$printablesRandom.Dispose()
```

Keep that generated value private and use the **same value** in both places:

1. Supabase **Edge Functions → Secrets**: add
   `PRINTABLES_CLEANUP_SECRET` with the generated value.
2. Supabase **Vault** (find it through dashboard search / Integrations): add a
   secret named `printables_cleanup_secret` with that same generated value.

Do not put either secret in Flutter, `constants.dart`, committed SQL, or chat.
The function uses Supabase's automatically provided `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` on the server. Neither goes into the frontend.

## 3. Deploy the cleanup function

Using the Supabase dashboard:

1. Go to **Edge Functions → Deploy a new function → Via Editor**.
2. Name it exactly `cleanup-printables`.
3. Replace the example code with all of
   [`supabase/functions/cleanup-printables/index.ts`](../supabase/functions/cleanup-printables/index.ts).
4. Deploy it.
5. In this function's settings, turn **Verify JWT / Enforce JWT verification**
   **off**. It checks the separate `x-printables-secret` header instead.
   Leaving JWT verification on prevents this scheduled request from working.

If using the Supabase CLI instead, from `D:\academy_portal`:

```powershell
supabase login
supabase functions deploy cleanup-printables --project-ref acwpurtriixeweteipjl --no-verify-jwt
```

The dashboard route does not require installing the CLI.

## 4. Enable automatic cleanup

1. Open a new SQL Editor query.
2. Run all of
   [`docs/003_printables_cleanup_schedule.sql`](003_printables_cleanup_schedule.sql).
3. Its final result must show the job `academy-cleanup-printables` with
   `active = true` and schedule `*/15 * * * *`.
4. Test the function from its dashboard Test/Invoke panel: method **POST**, add
   the header `x-printables-secret` with your generated secret, body `{}`.
   Expect HTTP 200 and a JSON response such as
   `{"ok":true,"deleted":0,"orphan_files_removed":0}`.
5. After the first scheduled run (within 15 minutes), check the Edge Function's
   logs for a successful invocation. A successful cron SQL run only means the
   HTTP request was queued; verify the HTTP/function result too.

Retention example: a test on **5 December** stays accessible throughout
**6 December**. At **00:00 on 7 December, Pakistan time**, access stops. Physical
files and request rows are removed on the next cleanup run, normally within
15 minutes. Server cleanup works while all apps are closed. Printed requests
follow the same retention period. It also reaps abandoned uploads after one hour.

The worker removes actual objects through the Storage API before deleting
database rows, retains failed cleanup rows for retries, and sweeps old orphaned
objects. It processes up to 500 requests plus 100 orphaned files per invocation;
larger backlogs continue on following runs. During a Supabase outage, removal
resumes when the schedule can run successfully again.

Downloads explicitly saved by a user are their own copies; server cleanup does
not delete files from their Downloads folder. Word preview temporary files are
reaped by this feature when the viewer is opened again after a day.

## 5. Check with real accounts before release

Use a small, non-confidential sample PDF and DOCX first:

| Check | Expected result |
| --- | --- |
| Teacher A opens Printables and taps + | Only assigned classes/subjects appear |
| Submit title, date, copies, optional instructions, PDF | Appears in Teacher A's list and admin list |
| Teacher B opens Printables | Teacher A's request is absent; direct Storage access is denied |
| Admin opens request | Teacher, class, subject, test date, copies and attachment appear |
| Admin marks Printed, then Pending | Status updates; teacher sees it on refresh / within one minute |
| Download PDF / DOCX on Windows, Android and web | Correct original file saves through OS/browser download flow |
| Preview / Print PDF on Windows, Android and web | PDF preview and system/browser print dialog work with configured printer |
| Word action on Windows/Android | Compatible installed app opens; print from that app |
| Word action on web | Downloads document; open in Word or a compatible app to print |
| Empty/unsupported file or >20 MB file | Submission rejected |
| Inactive teacher / signed-out user | Cannot read or submit files |
| Expired request | Hidden and file access denied; cleanup removes object and row |

For an immediate cleanup test, submit a disposable sample, copy its exact
request UUID from Table Editor, and run in SQL Editor (replace the placeholder):

```sql
UPDATE public.printable_requests
SET expires_at = now() - interval '1 minute'
WHERE id = 'PASTE-DISPOSABLE-SAMPLE-REQUEST-UUID-HERE'::uuid;
```

Invoke the cleanup function as described above. Confirm **both** the request row
and its object disappear. This test permanently removes that sample attachment.

## 6. Release the app

From `D:\academy_portal`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build apk --release
flutter build web --release
```

Android release signing uses the project's existing keystore and environment
configuration; the existing GitHub Android release workflow supplies these.
No release-signing credentials were changed by this feature. Local debug builds
can be checked with `flutter build apk --debug` instead.

Build artifacts:

- Windows: distribute the complete `build\windows\x64\runner\Release` folder,
  preserving the existing backend packaging if using WhatsApp automation.
- Android: `build\app\outputs\flutter-apk\app-release.apk`.
- Web: deploy `build\web` through the existing hosting flow.

The teacher and admin mobile bottom bars now include **Printables**. Admins can also open
**Menu → Printables** on mobile and **Printables** in the sidebar/rail on larger
screens. Teachers tap **+**, attach their paper, fill the request, and submit.
Admins download/print and then mark **Printed**. Status is manual because an OS
print dialog cannot confirm that physical copies came out of the printer.

PDF printing is in-app on all three target platforms. PDF preview may need
internet access to load the printing package's web PDF renderer. Word layout
and printing require a compatible external app; no documents are sent to an
external conversion service. Teachers should submit PDF whenever possible.
Set the requested copy count in the system/browser print dialog; it is not
automatically applied by Flutter's PDF printing API.

## Troubleshooting

- **Setup is not available yet**: run `002_printables.sql` in the correct project.
- **No assigned classes/subjects**: confirm teacher's `user_profiles.is_active`,
  teacher assignments and the target batch's `class_level`.
- **Upload rejected**: check 20 MB size limit, extension, active session and
  bucket policies. At most 50 upload reservations per teacher per rolling day.
- **Network interrupted during Submit**: close the form and refresh your list
  before submitting again; the first request may already have completed.
- **Cleanup returns 401**: match the Vault and Edge secret values and disable
  the function's JWT verification setting.
- **Files stay in Storage after expiry**: check Edge Function logs and cron
  HTTP results. Hiding expired rows alone does not free Storage space.
- **Nothing prints**: first test the OS/browser printer configuration with a
  local PDF, then try Preview / Print. Word needs an installed viewer.

For operational rollback, release the previous app version. Keep the new bucket,
table and cleanup function running until their remaining files expire; there is
no need to drop tables or change existing data.

References: [Supabase Storage deletion](https://supabase.com/docs/guides/storage/management/delete-objects),
[scheduled Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions),
[file picker](https://pub.dev/packages/file_picker).
