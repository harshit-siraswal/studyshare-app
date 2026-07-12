-- Migration 059: Create resource_ai_outputs table
-- Purpose: Store AI-generated outputs (summary, quiz, flashcards) per resource
-- Triggered by: n8n PDF Processing Pipeline workflow on resources INSERT

CREATE TABLE IF NOT EXISTS resource_ai_outputs (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_id   TEXT        NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
  output_type   TEXT        NOT NULL CHECK (output_type IN ('summary', 'quiz', 'flashcards')),
  content       JSONB       NOT NULL,
  generated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (resource_id, output_type)
);

CREATE INDEX IF NOT EXISTS idx_resource_ai_outputs_resource
  ON resource_ai_outputs(resource_id);

-- RLS: Allow service-role full access, authenticated users can SELECT their own
ALTER TABLE resource_ai_outputs ENABLE ROW LEVEL SECURITY;

-- Service role bypasses RLS; authenticated users may read outputs for resources
-- they can already see (join via resources table)
CREATE POLICY "authenticated_select_resource_ai_outputs"
  ON resource_ai_outputs
  FOR SELECT
  TO authenticated
  USING (
    resource_id IN (
      SELECT id FROM resources
    )
  );

COMMENT ON TABLE resource_ai_outputs IS
  'Stores AI-generated content (summary, quiz, flashcards) produced by the n8n PDF Processing Pipeline for each uploaded PDF resource.';
