-- Migration 062: Ensure college email tokens table is present and correct
-- This is a safe, idempotent migration. Run it even if 061 was already applied.
-- It adds the `updated_at` trigger, the service-role bypass policy, and verifies
-- the schema matches what `attendance_email_routes.ts` expects.

-- Re-create table if it somehow does not exist (migration 061 should have done this)
CREATE TABLE IF NOT EXISTS user_college_email_tokens (
    user_id         TEXT PRIMARY KEY,
    email_address   TEXT        NOT NULL,
    provider        TEXT        NOT NULL DEFAULT 'google',  -- 'google' | 'microsoft'
    encrypted_refresh_token TEXT NOT NULL,
    encryption_iv   TEXT        NOT NULL,
    scope           TEXT        NOT NULL DEFAULT 'https://www.googleapis.com/auth/gmail.readonly',
    token_status    TEXT        NOT NULL DEFAULT 'active',  -- 'active' | 'revoked' | 'expired'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS (safe to run even if already enabled)
ALTER TABLE user_college_email_tokens ENABLE ROW LEVEL SECURITY;

-- Policy: authenticated users can read/write their own row (Supabase JWT auth)
DROP POLICY IF EXISTS "Users can read/write their own College Email tokens" ON user_college_email_tokens;
CREATE POLICY "Users can read/write their own College Email tokens"
  ON user_college_email_tokens
  FOR ALL
  USING  (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- Policy: service-role key (used by the backend worker) bypasses RLS
-- Supabase grants service-role full access by default, but being explicit avoids surprises.
DROP POLICY IF EXISTS "Service role can manage all college email tokens" ON user_college_email_tokens;
CREATE POLICY "Service role can manage all college email tokens"
  ON user_college_email_tokens
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- Make the service-role policy only apply when using that role
ALTER POLICY "Service role can manage all college email tokens"
  ON user_college_email_tokens
  USING (current_setting('role', true) = 'service_role' OR current_setting('role', true) = 'supabase_admin');

-- Auto-update `updated_at` on every change
CREATE OR REPLACE FUNCTION update_college_email_tokens_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_college_email_tokens_updated_at ON user_college_email_tokens;
CREATE TRIGGER trg_college_email_tokens_updated_at
  BEFORE UPDATE ON user_college_email_tokens
  FOR EACH ROW EXECUTE FUNCTION update_college_email_tokens_updated_at();

-- Index for fast per-user lookups during attendance sync
CREATE UNIQUE INDEX IF NOT EXISTS idx_college_email_tokens_user
  ON user_college_email_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_college_email_tokens_status
  ON user_college_email_tokens (token_status, updated_at DESC);

COMMENT ON TABLE user_college_email_tokens IS
  'Encrypted OAuth refresh tokens for college mailbox OTP retrieval. '
  'Populated by POST /api/attendance/email/connect on the backend (AES-256-GCM via CyberVidyaVaultService). '
  'Read by CollegeEmailOtpService during CyberVidya attendance sync.';

COMMENT ON COLUMN user_college_email_tokens.encrypted_refresh_token IS
  'AES-256-GCM ciphertext of the Google/Microsoft OAuth refresh token. Format: hex(ciphertext):hex(authTag).';
COMMENT ON COLUMN user_college_email_tokens.encryption_iv IS
  'Hex-encoded 96-bit GCM initialization vector for the refresh token ciphertext.';
