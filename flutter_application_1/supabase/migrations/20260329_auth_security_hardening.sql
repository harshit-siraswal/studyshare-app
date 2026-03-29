DO $$
DECLARE
  insert_columns text;
BEGIN
  IF to_regclass('public.users') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
  DROP POLICY IF EXISTS users_update_own_row ON public.users;
  DROP POLICY IF EXISTS users_insert_own_row ON public.users;
  DROP POLICY IF EXISTS users_select_public_profile ON public.users;

  CREATE POLICY users_select_public_profile
    ON public.users
    FOR SELECT
    TO authenticated
    USING (true);

  CREATE POLICY users_insert_own_row
    ON public.users
    FOR INSERT
    TO authenticated
    WITH CHECK (
      auth.uid()::text = id::text
      AND lower(coalesce(email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
    );

  CREATE POLICY users_update_own_row
    ON public.users
    FOR UPDATE
    TO authenticated
    USING (auth.uid()::text = id::text)
    WITH CHECK (
      auth.uid()::text = id::text
      AND lower(coalesce(email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
    );

  SELECT string_agg(format('%I', column_name), ', ')
    INTO insert_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'users'
    AND column_name IN (
      'id',
      'email',
      'display_name',
      'profile_photo_url',
      'photo_url',
      'created_at',
      'updated_at'
    );

  IF insert_columns IS NOT NULL THEN
    EXECUTE format(
      'GRANT INSERT (%s) ON public.users TO authenticated',
      insert_columns
    );
  END IF;
END
$$;

DO $$
DECLARE
  has_user_id boolean;
  has_user_email boolean;
  using_clause text;
BEGIN
  IF to_regclass('public.saved_posts') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.saved_posts ENABLE ROW LEVEL SECURITY;
  GRANT SELECT, INSERT, DELETE ON public.saved_posts TO authenticated;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'saved_posts'
      AND column_name = 'user_id'
  ) INTO has_user_id;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'saved_posts'
      AND column_name = 'user_email'
  ) INTO has_user_email;

  using_clause := '';
  IF has_user_id THEN
    using_clause := 'user_id::text = auth.uid()::text';
  END IF;
  IF has_user_email THEN
    using_clause := using_clause ||
      CASE WHEN using_clause <> '' THEN ' OR ' ELSE '' END ||
      'lower(coalesce(user_email, '''')) = lower(coalesce(auth.jwt() ->> ''email'', ''''))';
  END IF;

  IF using_clause = '' THEN
    RETURN;
  END IF;

  DROP POLICY IF EXISTS saved_posts_select_own ON public.saved_posts;
  DROP POLICY IF EXISTS saved_posts_insert_own ON public.saved_posts;
  DROP POLICY IF EXISTS saved_posts_delete_own ON public.saved_posts;

  EXECUTE format(
    'CREATE POLICY saved_posts_select_own ON public.saved_posts FOR SELECT TO authenticated USING (%s)',
    using_clause
  );
  EXECUTE format(
    'CREATE POLICY saved_posts_insert_own ON public.saved_posts FOR INSERT TO authenticated WITH CHECK (%s)',
    using_clause
  );
  EXECUTE format(
    'CREATE POLICY saved_posts_delete_own ON public.saved_posts FOR DELETE TO authenticated USING (%s)',
    using_clause
  );
END
$$;

DO $$
DECLARE
  has_user_id boolean;
  has_follower_id boolean;
  has_user_email boolean;
  has_follower_email boolean;
  using_clause text;
BEGIN
  IF to_regclass('public.department_followers') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE public.department_followers ENABLE ROW LEVEL SECURITY;
  GRANT SELECT, INSERT, DELETE ON public.department_followers TO authenticated;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'department_followers'
      AND column_name = 'user_id'
  ) INTO has_user_id;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'department_followers'
      AND column_name = 'follower_id'
  ) INTO has_follower_id;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'department_followers'
      AND column_name = 'user_email'
  ) INTO has_user_email;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'department_followers'
      AND column_name = 'follower_email'
  ) INTO has_follower_email;

  using_clause := '';
  IF has_user_id THEN
    using_clause := 'user_id::text = auth.uid()::text';
  END IF;
  IF has_follower_id THEN
    using_clause := using_clause ||
      CASE WHEN using_clause <> '' THEN ' OR ' ELSE '' END ||
      'follower_id::text = auth.uid()::text';
  END IF;
  IF has_user_email THEN
    using_clause := using_clause ||
      CASE WHEN using_clause <> '' THEN ' OR ' ELSE '' END ||
      'lower(coalesce(user_email, '''')) = lower(coalesce(auth.jwt() ->> ''email'', ''''))';
  END IF;
  IF has_follower_email THEN
    using_clause := using_clause ||
      CASE WHEN using_clause <> '' THEN ' OR ' ELSE '' END ||
      'lower(coalesce(follower_email, '''')) = lower(coalesce(auth.jwt() ->> ''email'', ''''))';
  END IF;

  IF using_clause = '' THEN
    RETURN;
  END IF;

  DROP POLICY IF EXISTS department_followers_select_own ON public.department_followers;
  DROP POLICY IF EXISTS department_followers_insert_own ON public.department_followers;
  DROP POLICY IF EXISTS department_followers_delete_own ON public.department_followers;

  EXECUTE format(
    'CREATE POLICY department_followers_select_own ON public.department_followers FOR SELECT TO authenticated USING (%s)',
    using_clause
  );
  EXECUTE format(
    'CREATE POLICY department_followers_insert_own ON public.department_followers FOR INSERT TO authenticated WITH CHECK (%s)',
    using_clause
  );
  EXECUTE format(
    'CREATE POLICY department_followers_delete_own ON public.department_followers FOR DELETE TO authenticated USING (%s)',
    using_clause
  );
END
$$;

CREATE OR REPLACE FUNCTION public.get_my_ban_status(target_college_id text DEFAULT NULL)
RETURNS TABLE (
  is_banned boolean,
  reason text,
  is_global boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  current_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  has_email boolean;
  has_user_email boolean;
  sql text;
BEGIN
  IF current_email = '' OR to_regclass('public.banned_users') IS NULL THEN
    RETURN QUERY SELECT false, NULL::text, false;
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'banned_users'
      AND column_name = 'email'
  ) INTO has_email;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'banned_users'
      AND column_name = 'user_email'
  ) INTO has_user_email;

  IF NOT has_email AND NOT has_user_email THEN
    RETURN QUERY SELECT false, NULL::text, false;
    RETURN;
  END IF;

  sql := '
    SELECT true AS is_banned,
           coalesce(reason, ''Your account has been restricted by an administrator.'') AS reason,
           (college_id IS NULL) AS is_global
    FROM public.banned_users
    WHERE (';

  IF has_email THEN
    sql := sql || 'lower(coalesce(email, '''')) = $1';
  END IF;
  IF has_user_email THEN
    sql := sql ||
      CASE WHEN has_email THEN ' OR ' ELSE '' END ||
      'lower(coalesce(user_email, '''')) = $1';
  END IF;

  sql := sql || ')
      AND (
        college_id IS NULL OR
        ($2 IS NOT NULL AND college_id = $2)
      )
    ORDER BY CASE WHEN college_id IS NULL THEN 0 ELSE 1 END
    LIMIT 1';

  RETURN QUERY EXECUTE sql USING current_email, target_college_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, false;
  END IF;
END
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_ban_status(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_my_ban_status(text) TO authenticated;
