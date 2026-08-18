-- Migration 061: CyberVidya Credentials Vault & Automated Sync Logging
--
-- Secure storage schema for CyberVidya student credentials, college mailbox OAuth tokens,
-- and automated synchronization logs with RLS policies and auditing.

-- Step 1: Create CyberVidya Credentials Vault Table
CREATE TABLE IF NOT EXISTS user_cybervidya_credentials (
    user_id TEXT PRIMARY KEY,
    college_id TEXT NOT NULL,
    registration_number TEXT NOT NULL,
    encrypted_password TEXT NOT NULL,
    encryption_iv TEXT NOT NULL,
    key_version INTEGER NOT NULL DEFAULT 1,
    auth_status TEXT NOT NULL DEFAULT 'active', -- 'active', 'invalid_credentials', 'otp_failed', 'reconnect_required', 'captcha_required'
    last_authenticated_at TIMESTAMPTZ,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick lookup during background worker batching
CREATE INDEX IF NOT EXISTS idx_cybervidya_creds_status_sync 
ON user_cybervidya_credentials (auth_status, last_sync_at);

-- Step 2: Create College Email OAuth Tokens Table
CREATE TABLE IF NOT EXISTS user_college_email_tokens (
    user_id TEXT PRIMARY KEY,
    email_address TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'google', -- 'google', 'microsoft'
    encrypted_refresh_token TEXT NOT NULL,
    encryption_iv TEXT NOT NULL,
    scope TEXT NOT NULL,
    token_status TEXT NOT NULL DEFAULT 'active', -- 'active', 'revoked', 'expired'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 3: Create Attendance Synchronization Audit Logs Table
CREATE TABLE IF NOT EXISTS attendance_sync_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    college_id TEXT NOT NULL,
    sync_type TEXT NOT NULL, -- 'manual', 'scheduled_background', 'initial_setup'
    status TEXT NOT NULL, -- 'success', 'failed', 'captcha_required', 'otp_retrieval_failed', 'invalid_credentials'
    error_code TEXT,
    duration_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_logs_user_date 
ON attendance_sync_logs (user_id, created_at DESC);

-- Step 4: Row Level Security (RLS) Configuration
ALTER TABLE user_cybervidya_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_college_email_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_sync_logs ENABLE ROW LEVEL SECURITY;

-- Service role bypasses RLS for background sync worker; authenticated users can manage their own records
DROP POLICY IF EXISTS "Users can read/write their own CyberVidya credentials" ON user_cybervidya_credentials;
CREATE POLICY "Users can read/write their own CyberVidya credentials"
ON user_cybervidya_credentials
FOR ALL
USING (auth.uid()::text = user_id)
WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can read/write their own College Email tokens" ON user_college_email_tokens;
CREATE POLICY "Users can read/write their own College Email tokens"
ON user_college_email_tokens
FOR ALL
USING (auth.uid()::text = user_id)
WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can read their own attendance sync logs" ON attendance_sync_logs;
CREATE POLICY "Users can read their own attendance sync logs"
ON attendance_sync_logs
FOR SELECT
USING (auth.uid()::text = user_id);

COMMENT ON TABLE user_cybervidya_credentials IS 'Envelope-encrypted storage for CyberVidya registration number and password.';
COMMENT ON TABLE user_college_email_tokens IS 'Encrypted OAuth refresh tokens for college mailbox OTP retrieval.';
COMMENT ON TABLE attendance_sync_logs IS 'Audit log of automated and manual attendance synchronization attempts.';
