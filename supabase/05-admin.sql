-- ============================================
-- BUNDLE 5: ADMIN TOOLS — Invite TTL, Profile Management
-- Run AFTER 01-core.sql
-- ============================================


-- --- migration_admin_invite_ttl.sql ---

DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER);
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.admin_generate_invite_code(
    p_max_uses INTEGER DEFAULT 10,
    p_ttl_minutes INTEGER DEFAULT 5
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_code TEXT;
    v_max_uses INTEGER;
    v_ttl_minutes INTEGER;
    v_attempt INTEGER := 0;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN NULL;
    END IF;

    v_max_uses := LEAST(100, GREATEST(1, COALESCE(p_max_uses, 10)));
    v_ttl_minutes := LEAST(10080, GREATEST(1, COALESCE(p_ttl_minutes, 5)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(6), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (code, created_by, is_admin_code, max_uses, use_count, expires_at)
            VALUES (v_code, auth.uid(), true, v_max_uses, 0, now() + make_interval(mins => v_ttl_minutes));
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


-- --- migration_admin_invite_ttl_seconds.sql ---

DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER, INTEGER);

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

    v_max_uses := LEAST(100, GREATEST(1, COALESCE(p_max_uses, 10)));
    v_ttl_seconds := LEAST(604800, GREATEST(1, COALESCE(p_ttl_seconds, 300)));

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


-- --- migration_admin_profile_tools.sql ---

-- ============================================
-- NeuroBench: Admin Profile Management Tools
-- ============================================
-- Run AFTER migration_roles.sql and migration_achievements.sql
-- ============================================

-- ==========================================
-- STEP 1: Admin revoke achievement
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_revoke_achievement(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.admin_revoke_achievement(p_user_id UUID, p_achievement_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    DELETE FROM user_achievements
    WHERE user_id = p_user_id AND achievement_id = p_achievement_id;

    RETURN jsonb_build_object('ok', true, 'revoked', true);
END;
$$;

-- ==========================================
-- STEP 2: Admin grant achievement (bypasses supply limits)
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_grant_achievement(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.admin_grant_achievement(p_user_id UUID, p_achievement_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_already BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM achievements WHERE id = p_achievement_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'achievement_not_found');
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM user_achievements WHERE user_id = p_user_id AND achievement_id = p_achievement_id
    ) INTO v_already;

    IF v_already THEN
        RETURN jsonb_build_object('ok', true, 'granted', false, 'reason', 'already_unlocked');
    END IF;

    INSERT INTO user_achievements (user_id, achievement_id)
    VALUES (p_user_id, p_achievement_id);

    RETURN jsonb_build_object('ok', true, 'granted', true, 'achievement_id', p_achievement_id);
END;
$$;

-- ==========================================
-- STEP 3: Admin update user profile
-- ==========================================

CREATE OR REPLACE FUNCTION public.admin_update_user_profile(
    p_user_id       UUID,
    p_is_verified   BOOLEAN DEFAULT NULL,
    p_created_at    TIMESTAMPTZ DEFAULT NULL,
    p_bio           TEXT DEFAULT NULL,
    p_telegram_first_name TEXT DEFAULT NULL,
    p_telegram_last_name  TEXT DEFAULT NULL,
    p_telegram_username   TEXT DEFAULT NULL,
    p_telegram_photo_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updates TEXT[] := '{}';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = p_user_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    IF p_is_verified IS NOT NULL THEN
        UPDATE profiles SET is_verified = p_is_verified WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'is_verified');
    END IF;

    IF p_created_at IS NOT NULL THEN
        UPDATE profiles SET created_at = p_created_at WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'created_at');
    END IF;

    IF p_bio IS NOT NULL THEN
        UPDATE profiles SET bio = p_bio WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'bio');
    END IF;

    IF p_telegram_first_name IS NOT NULL THEN
        UPDATE profiles SET telegram_first_name = p_telegram_first_name WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_first_name');
    END IF;

    IF p_telegram_last_name IS NOT NULL THEN
        UPDATE profiles SET telegram_last_name = p_telegram_last_name WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_last_name');
    END IF;

    IF p_telegram_username IS NOT NULL THEN
        UPDATE profiles SET telegram_username = p_telegram_username WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_username');
    END IF;

    IF p_telegram_photo_url IS NOT NULL THEN
        UPDATE profiles SET telegram_photo_url = p_telegram_photo_url WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_photo_url');
    END IF;

    RETURN jsonb_build_object('ok', true, 'updated_fields', to_jsonb(v_updates));
END;
$$;

-- ==========================================
-- STEP 4: Admin generate invite for specific user
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_generate_invite_for_user(UUID);
CREATE OR REPLACE FUNCTION public.admin_generate_invite_for_user(p_user_id UUID, p_max_uses INT DEFAULT 1)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code TEXT;
    v_invite_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    v_code := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 8));

    INSERT INTO invite_codes (code, is_admin_code, max_uses, created_by)
    VALUES (v_code, true, p_max_uses, auth.uid())
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true,
        generated_invite_code_id = v_invite_id
    WHERE user_id = p_user_id
      AND (has_generated_invite IS NULL OR has_generated_invite = false);

    RETURN jsonb_build_object('ok', true, 'code', v_code, 'invite_id', v_invite_id);
END;
$$;

-- ==========================================
-- STEP 5: Admin get user detail (full profile + achievements + stats)
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_get_user_detail(UUID);
CREATE OR REPLACE FUNCTION public.admin_get_user_detail(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile JSONB;
    v_achievements JSONB;
    v_stats JSONB;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    SELECT to_jsonb(p) INTO v_profile FROM profiles p WHERE p.user_id = p_user_id;
    IF v_profile IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'achievement_id', a.id,
        'title', a.title,
        'icon_emoji', a.icon_emoji,
        'rarity', a.rarity,
        'points', a.points,
        'unlocked_at', ua.unlocked_at,
        'is_showcased', ua.is_showcased
    ) ORDER BY a.sort_order), '[]'::jsonb) INTO v_achievements
    FROM user_achievements ua
    JOIN achievements a ON a.id = ua.achievement_id
    WHERE ua.user_id = p_user_id;

    SELECT jsonb_build_object(
        'threads_count', (SELECT COUNT(*) FROM forum_threads WHERE author_id = p_user_id AND is_deleted = false),
        'posts_count', (SELECT COUNT(*) FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false),
        'reactions_given', (SELECT COUNT(*) FROM post_reactions WHERE user_id = p_user_id),
        'reactions_received', (SELECT COUNT(*) FROM post_reactions pr JOIN forum_posts fp ON fp.id = pr.post_id WHERE fp.author_id = p_user_id),
        'achievement_points', (SELECT COALESCE(SUM(a.points), 0) FROM user_achievements ua JOIN achievements a ON a.id = ua.achievement_id WHERE ua.user_id = p_user_id),
        'login_streak', (SELECT current_streak FROM login_streaks WHERE user_id = p_user_id),
        'max_streak', (SELECT max_streak FROM login_streaks WHERE user_id = p_user_id),
        'is_banned', EXISTS(SELECT 1 FROM user_mod_actions WHERE user_id = p_user_id AND action_type = 'ban' AND is_active = true AND (expires_at IS NULL OR expires_at > now())),
        'is_muted', EXISTS(SELECT 1 FROM user_mod_actions WHERE user_id = p_user_id AND action_type = 'mute' AND is_active = true AND (expires_at IS NULL OR expires_at > now()))
    ) INTO v_stats;

    RETURN jsonb_build_object(
        'ok', true,
        'profile', v_profile,
        'achievements', v_achievements,
        'stats', v_stats
    );
END;
$$;

