ALTER TABLE public.users ADD COLUMN IF NOT EXISTS subject TEXT DEFAULT '' CONSTRAINT users_subject_length_check CHECK (char_length(subject) <= 200);

-- Backfill existing NULL values to the default
UPDATE public.users SET subject = '' WHERE subject IS NULL;

GRANT SELECT (
    id,
    display_name,
    photo_url,
    bio,
    role,
    semester,
    branch,
    subject,
    created_at,
    updated_at
) ON public.users TO authenticated;

GRANT UPDATE (
    display_name,
    photo_url,
    bio,
    semester,
    branch,
    subject
) ON public.users TO authenticated;

-- Ensure RLS is enabled and an UPDATE policy restricts users to their own rows
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'users' AND schemaname = 'public' AND policyname = 'users_update_own_row'
  ) THEN
    EXECUTE 'CREATE POLICY users_update_own_row ON public.users FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id)';
  END IF;
END
$$;
