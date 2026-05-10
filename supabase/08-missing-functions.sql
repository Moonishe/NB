-- ============================================
-- BUNDLE 8: MISSING FUNCTIONS & BUG FIXES
-- Run AFTER all previous bundles
-- ============================================

-- ==========================================
-- FIX 1: get_public_profile_by_uid
-- Called by profile.js when opening /profile/<uid>
-- Was missing entirely — caused profile page to always fail
-- ==========================================

DROP FUNCTION IF EXISTS public.get_public_profile_by_uid(INTEGER);
DROP FUNCTION IF EXISTS public.get_public_profile(UUID);
CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
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
    showcased_achievements JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.user_id,
        p.uid::INTEGER,
        p.telegram_first_name::TEXT,
        p.telegram_last_name::TEXT,
        p.telegram_username::TEXT,
        p.telegram_photo_url::TEXT,
        p.bio::TEXT,
        (COALESCE(p.role, 'member') IN ('moderator', 'stmoderator', 'admin'))::BOOLEAN,
        COALESCE(p.is_verified, false)::BOOLEAN,
        COALESCE(p.role, 'member')::TEXT,
        p.created_at,
        (SELECT COUNT(*)::BIGINT FROM forum_threads WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*)::BIGINT FROM forum_posts WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*)::BIGINT FROM post_reactions WHERE user_id = p.user_id),
        (SELECT COALESCE(SUM(a.points), 0)::BIGINT FROM user_achievements ua JOIN achievements a ON a.id = ua.achievement_id WHERE ua.user_id = p.user_id),
        (SELECT COUNT(*)::BIGINT FROM user_achievements WHERE user_id = p.user_id),
        (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', a.id,
                'title', a.title,
                'icon_emoji', a.icon_emoji,
                'rarity', a.rarity,
                'points', a.points
            ) ORDER BY a.sort_order), '[]'::jsonb)
            FROM user_achievements ua
            JOIN achievements a ON a.id = ua.achievement_id
            WHERE ua.user_id = p.user_id AND ua.is_showcased = TRUE
        )
    FROM profiles p
    WHERE p.user_id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO service_role;

DROP FUNCTION IF EXISTS public.resolve_user_id_by_uid(INTEGER);
CREATE OR REPLACE FUNCTION public.resolve_user_id_by_uid(p_uid INTEGER)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT user_id
    FROM profiles
    WHERE uid = p_uid
    LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.resolve_user_id_by_uid(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_user_id_by_uid(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.resolve_user_id_by_uid(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_user_id_by_uid(INTEGER) TO service_role;

CREATE OR REPLACE FUNCTION public.get_public_profile_by_uid(p_uid INTEGER)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
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
    showcased_achievements JSONB
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
        gp.showcased_achievements
    FROM public.get_public_profile(v_user_id) gp;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile_by_uid(INTEGER) TO service_role;

-- ==========================================
-- FIX 2: update_profile_bio — унифицировать лимит
-- В 01-core.sql было 44, в 03-forum.sql было 500, в profile.js textarea maxlength=400
-- Устанавливаем единый лимит 400 символов
-- ==========================================

DROP FUNCTION IF EXISTS public.update_profile_bio(TEXT);
CREATE OR REPLACE FUNCTION public.update_profile_bio(p_bio TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF length(p_bio) > 400 THEN
        RAISE EXCEPTION 'Bio must be at most 400 characters';
    END IF;
    UPDATE profiles SET bio = p_bio WHERE user_id = auth.uid();
    RETURN FOUND;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_profile_bio(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_profile_bio(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_profile_bio(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_profile_bio(TEXT) TO service_role;

-- ==========================================
-- FIX 3: check_and_grant_achievements — first_model_rate
-- Было: results.author = p_user_id::text (никогда не срабатывало)
-- Теперь: проверяем result_ratings — пользователь оценил хотя бы один результат
-- ==========================================

-- Обновляем только эту часть через отдельную функцию-обёртку
-- Полная функция check_and_grant_achievements уже переопределена в 06b,
-- поэтому добавляем отдельный RPC для проверки first_model_rate

DROP FUNCTION IF EXISTS public.check_first_model_rate_achievement(UUID);
CREATE OR REPLACE FUNCTION public.check_first_model_rate_achievement(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'forbidden');
    END IF;

    IF EXISTS(SELECT 1 FROM result_ratings WHERE user_id = p_user_id LIMIT 1) THEN
        RETURN grant_achievement(p_user_id, 'first_model_rate');
    END IF;

    RETURN jsonb_build_object('granted', false, 'reason', 'no_ratings');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_first_model_rate_achievement(UUID) TO service_role;

-- ==========================================
-- FIX 4: admin_generate_invite_code — поднять TTL лимит
-- Было: LEAST(604800, ...) = макс 7 дней
-- Теперь: LEAST(35996400, ...) = совпадает с INVITE_INFINITE_TTL_SECONDS в JS
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.admin_generate_invite_code(
    p_max_uses INTEGER DEFAULT 10,
    p_ttl_seconds INTEGER DEFAULT 300
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_code TEXT;
    v_max_uses INTEGER;
    v_ttl_seconds INTEGER;
    v_attempt INTEGER := 0;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN NULL;
    END IF;

    v_max_uses := LEAST(10000, GREATEST(1, COALESCE(p_max_uses, 10)));
    -- Поднимаем лимит до INVITE_INFINITE_TTL_SECONDS (35996400 сек ≈ 416 дней)
    v_ttl_seconds := LEAST(35996400, GREATEST(1, COALESCE(p_ttl_seconds, 300)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(6), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (code, created_by, is_admin_code, max_uses, use_count, expires_at)
            VALUES (v_code, auth.uid(), true, v_max_uses, 0, now() + make_interval(secs => v_ttl_seconds));
            EXIT;
        EXCEPTION
            WHEN unique_violation THEN
                IF v_attempt >= 8 THEN
                    RAISE EXCEPTION 'failed to generate a unique invite code after % attempts', v_attempt;
                END IF;
        END;
    END LOOP;

    RETURN v_code;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) TO service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- ==========================================
-- FIX 5: get_forum_threads — добавить author_role и author_uid
-- В оригинале не возвращался author_role, поэтому бейджи BETA/ALPHA/ADMIN
-- не показывались в карточках тредов и в detail view
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
        p.telegram_username,
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

-- ==========================================
-- FIX 6: get_forum_thread_posts — добавить author_role
-- ==========================================

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
        p.telegram_username,
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

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
