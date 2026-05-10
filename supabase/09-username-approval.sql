-- ============================================
-- BUNDLE 9: Username approval system
-- Run AFTER all previous bundles
-- ============================================

BEGIN;
SET LOCAL search_path = public;

-- ==========================================
-- STEP 1: Add username columns to profiles
-- ==========================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS username TEXT,
    ADD COLUMN IF NOT EXISTS pending_username TEXT,
    ADD COLUMN IF NOT EXISTS username_changed_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles (username)
    WHERE username IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_pending_username ON public.profiles (pending_username)
    WHERE pending_username IS NOT NULL;

-- ==========================================
-- STEP 2: Update get_public_profile
-- ==========================================

DROP FUNCTION IF EXISTS public.get_public_profile(UUID);
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    username TEXT,
    pending_username TEXT,
    bio TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    role TEXT,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT,
    reactions_given_count BIGINT,
    achievement_points BIGINT,
    achievements_count BIGINT,
    showcased_achievements JSONB,
    invited_users_count BIGINT,
    invited_users JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    SELECT
        p.user_id,
        p.uid::INTEGER,
        p.telegram_first_name::TEXT,
        p.telegram_last_name::TEXT,
        p.telegram_username::TEXT,
        p.telegram_photo_url::TEXT,
        p.username::TEXT,
        p.pending_username::TEXT,
        p.bio::TEXT,
        (COALESCE(p.role, 'member') IN ('moderator', 'stmoderator', 'admin'))::BOOLEAN,
        COALESCE(p.is_verified, false)::BOOLEAN,
        COALESCE(p.role, 'member')::TEXT,
        p.created_at
    INTO
        user_id,
        uid,
        telegram_first_name,
        telegram_last_name,
        telegram_username,
        telegram_photo_url,
        username,
        pending_username,
        bio,
        is_moderator,
        is_verified,
        role,
        created_at
    FROM profiles p
    WHERE p.user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT COUNT(*)::BIGINT INTO threads_count
    FROM forum_threads
    WHERE author_id = p_user_id AND is_deleted = false;

    SELECT COUNT(*)::BIGINT INTO posts_count
    FROM forum_posts
    WHERE author_id = p_user_id AND is_deleted = false;

    SELECT COUNT(*)::BIGINT INTO reactions_given_count
    FROM post_reactions
    WHERE post_reactions.user_id = p_user_id;

    SELECT COALESCE(SUM(a.points), 0)::BIGINT INTO achievement_points
    FROM user_achievements ua
    JOIN achievements a ON a.id = ua.achievement_id
    WHERE ua.user_id = p_user_id;

    SELECT COUNT(*)::BIGINT INTO achievements_count
    FROM user_achievements
    WHERE user_achievements.user_id = p_user_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', a.id,
        'title', a.title,
        'icon_emoji', a.icon_emoji,
        'rarity', a.rarity,
        'points', a.points
    ) ORDER BY a.sort_order), '[]'::jsonb) INTO showcased_achievements
    FROM user_achievements ua
    JOIN achievements a ON a.id = ua.achievement_id
    WHERE ua.user_id = p_user_id AND ua.is_showcased = TRUE;

    SELECT COUNT(DISTINCT icu.user_id)::BIGINT INTO invited_users_count
    FROM invite_codes ic
    JOIN invite_code_uses icu ON icu.invite_code_id = ic.id
    WHERE ic.created_by = p_user_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'user_id', invited.user_id,
        'uid', invited.uid,
        'telegram_first_name', invited.telegram_first_name,
        'telegram_last_name', invited.telegram_last_name,
        'telegram_username', invited.telegram_username,
        'username', invited.username,
        'telegram_photo_url', invited.telegram_photo_url
    ) ORDER BY invited.uid), '[]'::jsonb) INTO invited_users
    FROM (
        SELECT DISTINCT
            p.user_id,
            p.uid,
            p.telegram_first_name,
            p.telegram_last_name,
            p.telegram_username,
            p.username,
            p.telegram_photo_url
        FROM invite_codes ic
        JOIN invite_code_uses icu ON icu.invite_code_id = ic.id
        JOIN profiles p ON p.user_id = icu.user_id
        WHERE ic.created_by = p_user_id
        ORDER BY p.uid
        LIMIT 12
    ) invited;

    RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO service_role;

-- ==========================================
-- STEP 3: Update get_public_profile_by_uid
-- ==========================================

DROP FUNCTION IF EXISTS public.get_public_profile_by_uid(INTEGER);
CREATE OR REPLACE FUNCTION public.get_public_profile_by_uid(p_uid INTEGER)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    username TEXT,
    pending_username TEXT,
    bio TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    role TEXT,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT,
    reactions_given_count BIGINT,
    achievement_points BIGINT,
    achievements_count BIGINT,
    showcased_achievements JSONB,
    invited_users_count BIGINT,
    invited_users JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT profiles.user_id INTO v_user_id
    FROM profiles
    WHERE profiles.uid = p_uid;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        gp.user_id,
        gp.uid,
        gp.telegram_first_name,
        gp.telegram_last_name,
        gp.telegram_username,
        gp.telegram_photo_url,
        gp.username,
        gp.pending_username,
        gp.bio,
        gp.is_moderator,
        gp.is_verified,
        gp.role,
        gp.created_at,
        gp.threads_count,
        gp.posts_count,
        gp.reactions_given_count,
        gp.achievement_points,
        gp.achievements_count,
        gp.showcased_achievements,
        gp.invited_users_count,
        gp.invited_users
    FROM public.get_public_profile(v_user_id) gp;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO service_role;

-- ==========================================
-- STEP 4: RPC — Request username change
-- ==========================================

DROP FUNCTION IF EXISTS public.request_username_change(TEXT);
CREATE OR REPLACE FUNCTION public.request_username_change(p_username TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_clean TEXT;
    v_existing UUID;
    v_pending UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
    END IF;

    v_clean := lower(btrim(regexp_replace(COALESCE(p_username, ''), '^@+', '')));

    IF length(v_clean) < 2 OR length(v_clean) > 32 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'invalid_length');
    END IF;

    IF v_clean !~ '^[a-z0-9_]+$' THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'invalid_chars');
    END IF;

    -- Check if already owned by someone else (approved username)
    SELECT user_id INTO v_existing
    FROM public.profiles
    WHERE lower(username) = v_clean
      AND user_id IS DISTINCT FROM v_user_id;

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'taken');
    END IF;

    -- Check if already pending by someone else
    SELECT user_id INTO v_pending
    FROM public.profiles
    WHERE lower(pending_username) = v_clean
      AND user_id IS DISTINCT FROM v_user_id;

    IF v_pending IS NOT NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'pending_taken');
    END IF;

    -- If unchanged from current approved username, clear pending
    IF EXISTS (
        SELECT 1 FROM public.profiles
        WHERE user_id = v_user_id
          AND lower(COALESCE(username, '')) = v_clean
    ) THEN
        RETURN jsonb_build_object('ok', true, 'reason', 'no_change');
    END IF;

    UPDATE public.profiles
    SET pending_username = left(v_clean, 32)
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object('ok', true, 'pending_username', left(v_clean, 32));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_username_change(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.request_username_change(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_username_change(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_username_change(TEXT) TO service_role;

-- ==========================================
-- STEP 5: RPC — Admin approve/reject username
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_approve_username(UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION public.admin_approve_username(
    p_user_id UUID,
    p_approve BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pending TEXT;
    v_conflict UUID;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    SELECT pending_username INTO v_pending
    FROM public.profiles
    WHERE user_id = p_user_id;

    IF v_pending IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'no_pending');
    END IF;

    IF p_approve THEN
        -- Check conflict one more time
        SELECT user_id INTO v_conflict
        FROM public.profiles
        WHERE lower(username) = lower(v_pending)
          AND user_id IS DISTINCT FROM p_user_id;

        IF v_conflict IS NOT NULL THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'taken');
        END IF;

        UPDATE public.profiles
        SET
            username = left(v_pending, 32),
            pending_username = NULL,
            username_changed_at = now()
        WHERE user_id = p_user_id;
    ELSE
        UPDATE public.profiles
        SET pending_username = NULL
        WHERE user_id = p_user_id;
    END IF;

    RETURN jsonb_build_object('ok', true, 'approved', p_approve, 'username', CASE WHEN p_approve THEN left(v_pending, 32) ELSE NULL END);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_approve_username(UUID, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_approve_username(UUID, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_username(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_username(UUID, BOOLEAN) TO service_role;

-- ==========================================
-- STEP 6: Update admin_update_user_profile (add p_username)
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_update_user_profile(
    p_user_id UUID,
    p_is_verified BOOLEAN DEFAULT NULL,
    p_created_at TIMESTAMPTZ DEFAULT NULL,
    p_bio TEXT DEFAULT NULL,
    p_telegram_first_name TEXT DEFAULT NULL,
    p_telegram_last_name TEXT DEFAULT NULL,
    p_telegram_username TEXT DEFAULT NULL,
    p_telegram_photo_url TEXT DEFAULT NULL,
    p_username TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updates TEXT[] := ARRAY[]::TEXT[];
    v_photo_url TEXT;
    v_conflict UUID;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF p_is_verified IS NOT NULL THEN
        UPDATE public.profiles
        SET is_verified = p_is_verified,
            verified_by = CASE WHEN p_is_verified THEN auth.uid() ELSE NULL END
        WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'is_verified');
    END IF;

    IF p_created_at IS NOT NULL THEN
        UPDATE public.profiles SET created_at = p_created_at WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'created_at');
    END IF;

    IF p_bio IS NOT NULL THEN
        IF length(p_bio) > 400 THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'bio_too_long');
        END IF;
        UPDATE public.profiles SET bio = p_bio WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'bio');
    END IF;

    IF p_telegram_first_name IS NOT NULL THEN
        UPDATE public.profiles SET telegram_first_name = left(p_telegram_first_name, 64) WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_first_name');
    END IF;

    IF p_telegram_last_name IS NOT NULL THEN
        UPDATE public.profiles SET telegram_last_name = left(p_telegram_last_name, 64) WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_last_name');
    END IF;

    IF p_telegram_username IS NOT NULL THEN
        UPDATE public.profiles SET telegram_username = left(p_telegram_username, 64) WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_username');
    END IF;

    IF p_telegram_photo_url IS NOT NULL THEN
        v_photo_url := public.normalize_telegram_photo_url(p_telegram_photo_url);
        UPDATE public.profiles SET telegram_photo_url = v_photo_url WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_photo_url');
    END IF;

    IF p_username IS NOT NULL THEN
        IF length(p_username) > 32 THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'username_too_long');
        END IF;
        SELECT user_id INTO v_conflict
        FROM public.profiles
        WHERE lower(username) = lower(p_username)
          AND user_id IS DISTINCT FROM p_user_id;
        IF v_conflict IS NOT NULL THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'username_taken');
        END IF;
        UPDATE public.profiles
        SET username = left(p_username, 32), pending_username = NULL
        WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'username');
    END IF;

    RETURN jsonb_build_object('ok', true, 'updated_fields', to_jsonb(v_updates));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- ==========================================
-- STEP 7: Update resolve_usernames to prefer custom username
-- ==========================================

DROP FUNCTION IF EXISTS public.resolve_usernames(TEXT[]);
CREATE OR REPLACE FUNCTION public.resolve_usernames(p_usernames TEXT[])
RETURNS TABLE(
    username TEXT,
    user_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_usernames TEXT[];
BEGIN
    IF p_usernames IS NULL THEN
        RETURN;
    END IF;

    SELECT array_agg(DISTINCT lower(btrim(u)))
    INTO v_usernames
    FROM unnest(p_usernames[1:50]) AS u
    WHERE btrim(u) <> '';

    IF v_usernames IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT COALESCE(p.username, p.telegram_username), p.user_id
    FROM public.profiles p
    WHERE lower(COALESCE(p.username, p.telegram_username)) = ANY(v_usernames)
      AND p.is_verified = true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) TO service_role;

-- ==========================================
-- STEP 8: Update forum views to prefer custom username
-- ==========================================

DROP FUNCTION IF EXISTS public.get_forum_threads(INTEGER, INTEGER, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_forum_threads(
    p_category_id INTEGER DEFAULT NULL,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id INTEGER,
    category_id INTEGER,
    author_id UUID,
    title TEXT,
    content TEXT,
    is_pinned BOOLEAN,
    is_locked BOOLEAN,
    posts_count INTEGER,
    last_post_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    author_username TEXT,
    author_first_name TEXT,
    author_last_name TEXT,
    author_photo_url TEXT,
    is_author_moderator BOOLEAN,
    category_name TEXT,
    category_slug TEXT,
    author_uid INTEGER,
    author_role TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ft.id, ft.category_id, ft.author_id, ft.title, ft.content,
        ft.is_pinned, ft.is_locked, ft.posts_count,
        ft.last_post_at, ft.created_at, ft.updated_at,
        COALESCE(p.username, p.telegram_username),
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_photo_url,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = ft.author_id),
        fc.name,
        fc.slug,
        p.uid,
        COALESCE(p.role, 'member')
    FROM forum_threads ft
    LEFT JOIN profiles p ON p.user_id = ft.author_id
    LEFT JOIN forum_categories fc ON fc.id = ft.category_id
    WHERE ft.is_deleted = false
      AND (p_category_id IS NULL OR ft.category_id = p_category_id)
    ORDER BY ft.is_pinned DESC, ft.last_post_at DESC NULLS LAST, ft.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_forum_threads(INTEGER, INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_forum_threads(INTEGER, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_forum_threads(INTEGER, INTEGER, INTEGER) TO service_role;

DROP FUNCTION IF EXISTS public.get_forum_thread_posts(INTEGER, INTEGER, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_forum_thread_posts(
    p_thread_id INTEGER,
    p_limit INTEGER DEFAULT 25,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id INTEGER,
    thread_id INTEGER,
    author_id UUID,
    content TEXT,
    is_deleted BOOLEAN,
    edited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    author_username TEXT,
    author_first_name TEXT,
    author_last_name TEXT,
    author_photo_url TEXT,
    is_author_moderator BOOLEAN,
    author_uid INTEGER,
    author_role TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        fp.id, fp.thread_id, fp.author_id, fp.content,
        fp.is_deleted, fp.edited_at, fp.created_at,
        COALESCE(p.username, p.telegram_username),
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_photo_url,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = fp.author_id),
        p.uid,
        COALESCE(p.role, 'member')
    FROM forum_posts fp
    LEFT JOIN profiles p ON p.user_id = fp.author_id
    WHERE fp.thread_id = p_thread_id
      AND fp.is_deleted = false
    ORDER BY fp.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_forum_thread_posts(INTEGER, INTEGER, INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_forum_thread_posts(INTEGER, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_forum_thread_posts(INTEGER, INTEGER, INTEGER) TO service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
