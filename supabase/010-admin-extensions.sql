-- ============================================================================
-- SUPABASE: Admin Panel Extensions
-- Tables and RPCs required for the new admin dashboard sections
-- ============================================================================

-- ==========================================
-- STEP 1: Announcements table
-- ==========================================

CREATE TABLE IF NOT EXISTS public.announcements (
    id          SERIAL PRIMARY KEY,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    is_pinned   BOOLEAN DEFAULT false,
    created_by  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Only admins can view/create/delete
DROP POLICY IF EXISTS "Admins can manage announcements" ON public.announcements;
CREATE POLICY "Admins can manage announcements"
    ON public.announcements
    FOR ALL
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()))
    WITH CHECK (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()));

-- ==========================================
-- STEP 2: RPC — Admin: get all threads
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_get_all_threads() CASCADE;
CREATE OR REPLACE FUNCTION public.admin_get_all_threads()
RETURNS TABLE (
    id          INTEGER,
    title       TEXT,
    author_id   UUID,
    author_nickname TEXT,
    author_username TEXT,
    is_pinned   BOOLEAN,
    is_locked   BOOLEAN,
    is_deleted  BOOLEAN,
    posts_count INTEGER,
    created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT
        t.id,
        t.title,
        t.author_id,
        p.telegram_first_name || ' ' || COALESCE(p.telegram_last_name, '') AS author_nickname,
        p.telegram_username,
        t.is_pinned,
        t.is_locked,
        t.is_deleted,
        t.posts_count,
        t.created_at
    FROM public.forum_threads t
    LEFT JOIN public.profiles p ON t.author_id = p.user_id
    WHERE t.is_deleted = false
    ORDER BY t.created_at DESC
    LIMIT 100;
END;
$$;

-- ==========================================
-- STEP 3: RPC — Admin: get all bans (with user info)
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_get_bans() CASCADE;
CREATE OR REPLACE FUNCTION public.admin_get_bans()
RETURNS TABLE (
    user_id     UUID,
    telegram_username TEXT,
    reason      TEXT,
    created_at  TIMESTAMPTZ,
    expires_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT
        m.user_id,
        p.telegram_username,
        m.reason,
        m.created_at,
        m.expires_at
    FROM public.user_mod_actions m
    LEFT JOIN public.profiles p ON m.user_id = p.user_id
    WHERE m.action_type = 'ban'
      AND m.is_active = true
    ORDER BY m.created_at DESC;
END;
$$;

-- ==========================================
-- STEP 4: RPC — Admin: get announcements
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_get_announcements() CASCADE;
CREATE OR REPLACE FUNCTION public.admin_get_announcements()
RETURNS TABLE (
    id          INTEGER,
    title       TEXT,
    body        TEXT,
    is_pinned   BOOLEAN,
    created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT a.id, a.title, a.body, a.is_pinned, a.created_at
    FROM public.announcements a
    ORDER BY a.created_at DESC;
END;
$$;

-- ==========================================
-- STEP 5: RPC — Admin: create announcement
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_create_announcement(TEXT, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_create_announcement(
    p_title TEXT,
    p_body  TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN NULL;
    END IF;
    INSERT INTO public.announcements (title, body, created_by)
    VALUES (p_title, p_body, auth.uid())
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- ==========================================
-- STEP 6: RPC — Admin: delete announcement
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_delete_announcement(INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_delete_announcement(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    DELETE FROM public.announcements WHERE id = p_id;
    RETURN true;
END;
$$;

-- ==========================================
-- STEP 7: RPC — Admin: create achievement
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_create_achievement(JSONB) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_create_achievement(p_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN NULL;
    END IF;
    INSERT INTO public.achievements (id, title, description, icon_emoji, rarity, points)
    VALUES (
        p_data->>'id',
        p_data->>'title',
        COALESCE(p_data->>'description', ''),
        COALESCE(p_data->>'icon_emoji', '🏆'),
        COALESCE(p_data->>'rarity', 'common'),
        COALESCE((p_data->>'points')::INTEGER, 10)
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- ==========================================
-- STEP 8: Update API fallback to use RPCs
-- ==========================================

-- Grant execute permissions
DO $$
BEGIN
    IF to_regprocedure('public.admin_get_all_threads()') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION public.admin_get_all_threads() TO authenticated;
        GRANT EXECUTE ON FUNCTION public.admin_get_all_threads() TO service_role;
    END IF;
    IF to_regprocedure('public.admin_get_bans()') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION public.admin_get_bans() TO authenticated;
        GRANT EXECUTE ON FUNCTION public.admin_get_bans() TO service_role;
    END IF;
    IF to_regprocedure('public.admin_get_announcements()') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION public.admin_get_announcements() TO authenticated;
        GRANT EXECUTE ON FUNCTION public.admin_get_announcements() TO service_role;
    END IF;
    IF to_regprocedure('public.admin_create_announcement(TEXT,TEXT)') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION public.admin_create_announcement(TEXT, TEXT) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.admin_create_announcement(TEXT, TEXT) TO service_role;
    END IF;
    IF to_regprocedure('public.admin_delete_announcement(INTEGER)') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION public.admin_delete_announcement(INTEGER) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.admin_delete_announcement(INTEGER) TO service_role;
    END IF;
    IF to_regprocedure('public.admin_create_achievement(JSONB)') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION public.admin_create_achievement(JSONB) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.admin_create_achievement(JSONB) TO service_role;
    END IF;
END;
$$;
