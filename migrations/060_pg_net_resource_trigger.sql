-- Migration 060: pg_net trigger — free alternative to Supabase Database Webhooks
--
-- What this does: replicates the "Database Webhooks" paid feature using pg_net,
-- which is available FREE on all Supabase plans (Free tier included).
--
-- NOTE: resource_ai_outputs.resource_id is TEXT (not UUID) because resources.id is TEXT.
--
-- PREREQUISITES:
--   1. pg_net extension must be enabled (free, enabled by default on Supabase)
--   2. n8n must be publicly reachable (use ngrok or deploy to a VPS)
--   3. Run migration 059 first (resource_ai_outputs table)
--
-- Usage:
--   Update N8N_WEBHOOK_URL below to match your public n8n URL.
--   Run this in Supabase SQL Editor.

-- Step 1: Enable pg_net (safe to run even if already enabled)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Step 2: Create the trigger function
CREATE OR REPLACE FUNCTION notify_n8n_on_resource_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n8n_webhook_url TEXT := 'http://YOUR_NGROK_OR_PUBLIC_HOST/webhook/supabase-resource-insert';
  -- ⚠️  Replace above with your actual n8n public URL before running.
  -- For local dev with ngrok:
  --   1. Run: ngrok http 5678
  --   2. Copy the https URL, e.g. https://abcd1234.ngrok-free.app
  --   3. Set: 'https://abcd1234.ngrok-free.app/webhook/supabase-resource-insert'
  -- For production (n8n on a server):
  --   Set: 'https://n8n.yourdomain.com/webhook/supabase-resource-insert'
  -- Supabase project: iayuwsvguwfqjgjsvjiy.supabase.co
  payload JSONB;
BEGIN
  -- Only fire for PDF resources (same filter as the n8n workflow)
  IF NEW.file_type = 'pdf' THEN
    payload := jsonb_build_object(
      'type',   'INSERT',
      'table',  'resources',
      'schema', 'public',
      'record', row_to_json(NEW)::jsonb,
      'old_record', NULL
    );

    PERFORM net.http_post(
      url     := n8n_webhook_url,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body    := payload::text
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Step 3: Create the trigger on resources table
DROP TRIGGER IF EXISTS resources_notify_n8n ON resources;

CREATE TRIGGER resources_notify_n8n
  AFTER INSERT ON resources
  FOR EACH ROW
  EXECUTE FUNCTION notify_n8n_on_resource_insert();

-- Step 4 (optional): verify pg_net is working
-- SELECT net.http_get('https://httpbin.org/get');
-- Then check: SELECT * FROM net._http_response ORDER BY created DESC LIMIT 5;

COMMENT ON FUNCTION notify_n8n_on_resource_insert() IS
  'Free alternative to Supabase Database Webhooks (paid). Uses pg_net to POST '
  'an INSERT event to n8n whenever a PDF resource is created. '
  'Update the n8n_webhook_url variable to your public n8n endpoint.';
