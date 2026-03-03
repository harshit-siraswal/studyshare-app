-- Consolidated SQL for StudyShare new features

-- 1. Feature: Profile Semester & Branch
ALTER TABLE users ADD COLUMN IF NOT EXISTS semester text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS branch text;

-- Add check constraints to ensure valid data is entered (idempotent)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'check_semester' AND conrelid = 'users'::regclass) THEN
    ALTER TABLE users ADD CONSTRAINT check_semester 
        CHECK (semester IS NULL OR semester IN ('1', '2', '3', '4', '5', '6', '7', '8'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'check_branch' AND conrelid = 'users'::regclass) THEN
    ALTER TABLE users ADD CONSTRAINT check_branch 
        CHECK (branch IS NULL OR branch IN ('CSE', 'IT', 'ECE', 'AI/ML', 'MECH', 'CIVIL', 'BCA', 'MCA'));
  END IF;
END $$;

-- 2. Feature: Teacher Account & Resource Moderation
ALTER TABLE users ADD COLUMN IF NOT EXISTS admin_key_hash text;

-- Ensure that if an admin_key is provided, it must be unique among teachers
-- (We use a partial index so NULLs or empty strings aren't forced to be unique)
CREATE UNIQUE INDEX IF NOT EXISTS unique_admin_key_hash 
ON users(admin_key_hash) 
WHERE admin_key_hash IS NOT NULL AND admin_key_hash != '';

-- Add Row Level Security (RLS) policies if they don't already exist
-- (Assuming RLS is enabled on the users table)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Allow users to update their own profile, including semester and branch
-- Note: users.id is stored as text, auth.uid() returns uuid — explicit ::text casts are intentional
DROP POLICY IF EXISTS "Users can update their own profile" ON users;
CREATE POLICY "Users can update their own profile"
    ON users FOR UPDATE
    USING (auth.uid()::text = id::text)
    WITH CHECK (auth.uid()::text = id::text);

-- Raw admin_key should not be stored. Only admin_key_hash is persisted and
-- comparisons should be done on the backend with a hashed incoming key.

-- Function to get unread notification count directly 
CREATE OR REPLACE FUNCTION get_unread_notification_count(user_uuid TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
BEGIN
  -- Only allow users to query their own notification count
  IF auth.uid()::text IS DISTINCT FROM user_uuid THEN
    RETURN 0;
  END IF;

  RETURN (
    SELECT count(*)::integer FROM notifications 
    WHERE user_id = user_uuid AND is_read = false
  );
END;
$$;

-- Restrict execution to authenticated users only
REVOKE EXECUTE ON FUNCTION get_unread_notification_count(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION get_unread_notification_count(TEXT) TO authenticated;


