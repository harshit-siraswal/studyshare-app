#!/usr/bin/env node
// Runs migration 059 via Supabase's internal pg connection pooler
// Uses the postgres:// connection string with the service role key

const https = require('https');

const PROJECT_REF = 'iayuwsvguwfqjgjsvjiy';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlheXV3c3ZndXdmcWpnanN2aml5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NjA1MTkxMSwiZXhwIjoyMDgxNjI3OTExfQ.Zur3Mu-IeVOb3hkd1XkEn3IQRy_yXULqdJVs8zsVzZI';

// Supabase exposes a pg REST endpoint at /pg for management operations
// Try the management API SQL endpoint
const SQL_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS resource_ai_outputs (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id   UUID        NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    output_type   TEXT        NOT NULL CHECK (output_type IN ('summary', 'quiz', 'flashcards')),
    content       JSONB       NOT NULL,
    generated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (resource_id, output_type)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_resource_ai_outputs_resource ON resource_ai_outputs(resource_id)`,
  `ALTER TABLE resource_ai_outputs ENABLE ROW LEVEL SECURITY`,
];

function httpsReq(opts, bodyStr) {
  return new Promise((resolve, reject) => {
    const r = https.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
    r.on('error', reject);
    if (bodyStr) r.write(bodyStr);
    r.end();
  });
}

async function tryManagementAPI() {
  // Try Supabase's internal management SQL API (available when using management token)
  // This uses the DB API at api.supabase.com/v1/projects/{ref}/database/query
  // But we only have service_role, not management token. This will fail gracefully.
  const body = JSON.stringify({ query: SQL_STATEMENTS.join(';\n') + ';' });
  const result = await httpsReq({
    hostname: 'api.supabase.com',
    port: 443,
    path: `/v1/projects/${PROJECT_REF}/database/query`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + SERVICE_ROLE_KEY,
      'Content-Length': Buffer.byteLength(body)
    }
  }, body);
  return result;
}

async function main() {
  console.log('Attempting migration via Supabase Management API...');
  const r = await tryManagementAPI();
  console.log('Status:', r.status);
  console.log('Response:', r.body.substring(0, 400));

  if (r.status === 200 || r.status === 201) {
    console.log('\n✅ Migration 059 applied successfully!');
  } else {
    console.log('\n❌ Could not run SQL automatically (needs Management API token, not service_role key).');
    console.log('\n📋 MANUAL STEP REQUIRED:');
    console.log('Open: https://supabase.com/dashboard/project/iayuwsvguwfqjgjsvjiy/sql/new');
    console.log('Paste and run:\n');
    console.log('-- Migration 059: resource_ai_outputs');
    SQL_STATEMENTS.forEach(s => console.log(s + ';\n'));
    console.log('-- Done.');
  }
}

main().catch(console.error);
