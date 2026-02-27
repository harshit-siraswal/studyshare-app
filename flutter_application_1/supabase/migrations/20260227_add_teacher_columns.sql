-- Migration file to add teacher-specific columns and profile details to the users table

-- Add semester column (nullable, expected values: 1-8)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS semester INTEGER;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_semester_check' AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users ADD CONSTRAINT users_semester_check CHECK (semester IS NULL OR (semester BETWEEN 1 AND 8));
    END IF;
END $$;

-- Add branch column (nullable, e.g. 'CSE', 'ECE', 'ME')
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS branch TEXT;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_branch_check' AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users ADD CONSTRAINT users_branch_check CHECK (branch IS NULL OR branch IN ('CSE', 'ECE', 'ME', 'CE', 'EE', 'IT', 'AI', 'DS'));
    END IF;
END $$;

-- Add admin_key_hash column to store hashed keys for users with the 'TEACHER' role
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS admin_key_hash TEXT;

-- Ensure partial unique index (drop old full index if it exists)
DROP INDEX IF EXISTS idx_users_admin_key_hash;
CREATE UNIQUE INDEX idx_users_admin_key_hash ON public.users(admin_key_hash) WHERE admin_key_hash IS NOT NULL;

-- Column-level security for admin_key_hash:
-- RLS works per-row, not per-column. Use column-level REVOKE for true column hiding.
-- Revoke SELECT on admin_key_hash from authenticated users (they cannot read other users' hashes).
-- Service role retains full access by default (it bypasses RLS and grants).
REVOKE ALL ON public.users FROM authenticated;
GRANT SELECT (id, email, display_name, photo_url, bio, role, semester, branch, created_at, updated_at)
    ON public.users TO authenticated;
GRANT UPDATE (display_name, photo_url, bio, semester, branch)
    ON public.users TO authenticated;

-- admin_key_hash can only be updated via service_role (backend API).
-- No explicit GRANT on admin_key_hash to authenticated — it stays invisible and immutable to them.
