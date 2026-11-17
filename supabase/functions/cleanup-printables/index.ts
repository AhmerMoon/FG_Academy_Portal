import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

// Deploy with JWT verification disabled; authentication uses this dedicated
// server-only secret. Never put the secret or service-role key in Flutter.
Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const secret = Deno.env.get('PRINTABLES_CLEANUP_SECRET');
  if (!secret || request.headers.get('x-printables-secret') !== secret) {
    return new Response('Unauthorized', { status: 401 });
  }
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return new Response('Server configuration missing', { status: 500 });
  const client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let deleted = 0;
  try {
    // Bounded batches fit Edge Function execution limits. Remaining work is
    // retried by the next scheduled invocation; failures never lose row paths.
    for (let batch = 0; batch < 5; batch++) {
      const { data: rows, error } = await client.rpc('claim_printables_cleanup');
      if (error) throw error;
      if (!rows?.length) break;
      const { error: storageError } = await client.storage.from('test-printables')
        .remove(rows.map((row: { file_path: string }) => row.file_path));
      if (storageError) throw storageError;
      // Storage API first: SQL deletion alone would leave billable file bytes.
      const { error: deleteError } = await client.from('printable_requests').delete()
        .in('id', rows.map((row: { id: string }) => row.id)).eq('status', 'deleting');
      if (deleteError) throw deleteError;
      deleted += rows.length;
      if (rows.length < 100) break;
    }
    const { data: orphans, error: orphanError } = await client.rpc('orphan_printable_files');
    if (orphanError) throw orphanError;
    if (orphans?.length) {
      const { error } = await client.storage.from('test-printables')
        .remove(orphans.map((row: { file_path: string }) => row.file_path));
      if (error) throw error;
    }
    return Response.json({ ok: true, deleted, orphan_files_removed: orphans?.length ?? 0 });
  } catch (error) {
    console.error('Printables cleanup failed:', error);
    return Response.json({ ok: false, error: 'Cleanup failed; see function logs. The next run will retry.' }, { status: 500 });
  }
});
