-- Add semester and branch for context-aware syllabus widget and AI features
ALTER TABLE users ADD COLUMN IF NOT EXISTS semester text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS branch text;

-- Add admin_key_hash for Teacher accounts to securely authenticate API requests for resource moderation
ALTER TABLE users ADD COLUMN IF NOT EXISTS admin_key_hash text;

-- Drop old non-filtered index if it exists, then create the partial unique index
DROP INDEX IF EXISTS idx_users_admin_key_hash;
CREATE UNIQUE INDEX idx_users_admin_key_hash ON users(admin_key_hash) WHERE admin_key_hash IS NOT NULL;
