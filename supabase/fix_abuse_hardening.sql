-- DEPRECATED / DO NOT RUN.
-- This file was superseded by supabase/fix_security_audit_v2.sql.
-- It is intentionally stopped here because older logic can break achievement flows.
DO $$
BEGIN
    RAISE EXCEPTION 'Deprecated migration. Run supabase/fix_security_audit_v2.sql instead.';
END;
$$;

-- ============================================
-- NeuroBench: Security Hardening — Abuse Fixes
-- ============================================

-- ==========================================
-- FIX 1: grant_achievement() — restrict to self-only or internal calls
-- ABUSE: Any authenticated user can call grant_achievement(ANY_USER_ID, ANY_ACHIEVEMENT)
--        and give themselves (or anyone) any achievement.
-- FIX:   Only allow granting to auth.uid(), block arbitrary p_user_id.
--        Internal calls from other SECURITY DEFINER functions still work
--        because they run as the function owner, not as the user.
-- ==========================================

CREATE OR REPLACE FUNCTION public.grant_achievement(p_user_id UUID, p_achievement_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_max_supply INT;
    v_current_count INT;
    v_already BOOLEAN;
    v_caller_is_rpc BOOLEAN;
BEGIN
    -- Block direct RPC calls for other users:
    -- If called from another SECURITY DEFINER function, auth.uid() may differ
    -- but the call stack is trusted. We check: if auth.uid() != p_user_id,
    -- only allow if caller is admin.
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
            RETURN jsonb_build_object('granted', false, 'reason', 'forbidden');
        END IF;
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM user_achievements WHERE user_id = p_user_id AND achievement_id = p_achievement_id
    ) INTO v_already;

    IF v_already THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'already_unlocked');
    END IF;

    SELECT max_supply INTO v_max_supply FROM achievements WHERE id = p_achievement_id;
    IF v_max_supply IS NOT NULL THEN
        SELECT COUNT(*) INTO v_current_count FROM user_achievements WHERE achievement_id = p_achievement_id;
        IF v_current_count >= v_max_supply THEN
            RETURN jsonb_build_object('granted', false, 'reason', 'supply_exhausted');
        END IF;
    END IF;

    INSERT INTO user_achievements (user_id, achievement_id)
    VALUES (p_user_id, p_achievement_id);

    RETURN jsonb_build_object('granted', true, 'achievement_id', p_achievement_id);
END;
$$;

-- ==========================================
-- FIX 2: check_and_grant_achievements() — only allow for own user
-- ABUSE: Anyone can call check_and_grant_achievements(OTHER_USER_ID)
--        to trigger achievement checks for another user.
-- FIX:   Enforce p_user_id = auth.uid()
-- ==========================================

CREATE OR REPLACE FUNCTION public.check_and_grant_achievements(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_granted TEXT[] := '{}';
    v_result JSONB;
    v_referral_count INT := 0;
    v_profile RECORD;
    v_uid_seq INT;
    v_has_posts BOOLEAN;
    v_days_since_reg INT;
BEGIN
    -- FIX: Only allow checking achievements for yourself
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object('granted', '{}', 'error', 'forbidden');
    END IF;

    SELECT * INTO v_profile FROM profiles WHERE user_id = p_user_id;
    IF v_profile IS NULL THEN RETURN jsonb_build_object('granted', '{}'); END IF;

    -- welcome
    SELECT (grant_achievement(p_user_id, 'welcome')->>'granted')::BOOLEAN INTO v_result;
    IF v_result THEN v_granted := array_append(v_granted, 'welcome'); END IF;

    -- first_among_equals: uid <= 10
    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 10 THEN
        SELECT (grant_achievement(p_user_id, 'first_among_equals')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_among_equals'); END IF;
    END IF;

    -- the_first_hundred: uid <= 100
    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 100 THEN
        SELECT (grant_achievement(p_user_id, 'the_first_hundred')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'the_first_hundred'); END IF;
    END IF;

    IF v_profile.created_at IS NOT NULL AND v_profile.created_at < TIMESTAMPTZ '2026-02-19 00:00:00+00' THEN
        SELECT (grant_achievement(p_user_id, 'before_public_launch')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'before_public_launch'); END IF;
    END IF;

    -- alpha_user
    IF v_profile.role = 'alpha' THEN
        SELECT (grant_achievement(p_user_id, 'alpha_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'alpha_user'); END IF;
    END IF;

    -- beta_user
    IF v_profile.role = 'beta' THEN
        SELECT (grant_achievement(p_user_id, 'beta_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'beta_user'); END IF;
    END IF;

    -- moderator_power
    IF v_profile.role IN ('moderator', 'stmoderator', 'admin') THEN
        SELECT (grant_achievement(p_user_id, 'moderator_power')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'moderator_power'); END IF;
    END IF;

    -- referral achievements
    SELECT COUNT(*) INTO v_referral_count
    FROM invite_code_uses icu
    JOIN invite_codes ic ON ic.id = icu.invite_code_id
    WHERE ic.created_by = p_user_id;

    IF v_referral_count >= 1 THEN
        SELECT (grant_achievement(p_user_id, 'first_referral')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_referral'); END IF;
    END IF;
    IF v_referral_count >= 3 THEN
        SELECT (grant_achievement(p_user_id, 'binding_layer')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'binding_layer'); END IF;
    END IF;
    IF v_referral_count >= 10 THEN
        SELECT (grant_achievement(p_user_id, 'cluster_formed')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'cluster_formed'); END IF;
    END IF;

    -- silent_observer: 30+ days, 0 posts
    IF v_profile.created_at IS NOT NULL THEN
        v_days_since_reg := EXTRACT(DAY FROM NOW() - v_profile.created_at);
        IF v_days_since_reg >= 30 THEN
            SELECT EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false) INTO v_has_posts;
            IF NOT v_has_posts THEN
                SELECT (grant_achievement(p_user_id, 'silent_observer')->>'granted')::BOOLEAN INTO v_result;
                IF v_result THEN v_granted := array_append(v_granted, 'silent_observer'); END IF;
            END IF;
        END IF;
    END IF;

    -- profile_tuned
    IF (v_profile.bio IS NOT NULL AND v_profile.bio <> '')
       OR (v_profile.telegram_photo_url IS NOT NULL AND v_profile.telegram_photo_url <> '') THEN
        SELECT (grant_achievement(p_user_id, 'profile_tuned')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'profile_tuned'); END IF;
    END IF;

    -- first_reaction
    IF EXISTS(SELECT 1 FROM post_reactions WHERE user_id = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_reaction')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_reaction'); END IF;
    END IF;

    -- daily_login: 3-day streak
    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 3) THEN
        SELECT (grant_achievement(p_user_id, 'daily_login')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'daily_login'); END IF;
    END IF;

    -- first_thread
    IF EXISTS(SELECT 1 FROM forum_threads WHERE author_id = p_user_id AND is_deleted = false LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_thread')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_thread'); END IF;
    END IF;

    -- first_comment
    IF EXISTS(
        SELECT 1 FROM forum_posts fp
        JOIN forum_threads ft ON ft.id = fp.thread_id
        WHERE fp.author_id = p_user_id AND fp.is_deleted = false
        AND ft.author_id != p_user_id
        LIMIT 1
    ) THEN
        SELECT (grant_achievement(p_user_id, 'first_comment')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_comment'); END IF;
    END IF;

    -- first_model_rate
    IF EXISTS(SELECT 1 FROM results WHERE author = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_model_rate')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_model_rate'); END IF;
    END IF;

    -- first_mention
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND content LIKE '%@%' LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_mention')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_mention'); END IF;
    END IF;

    -- first_edit
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND updated_at IS NOT NULL AND updated_at != created_at LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_edit')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_edit'); END IF;
    END IF;

    -- seven_day_streak
    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 7) THEN
        SELECT (grant_achievement(p_user_id, 'seven_day_streak')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'seven_day_streak'); END IF;
    END IF;

    -- night_shift: post between 02:00-05:00 UTC
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') >= 2 AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') < 5 LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'night_shift')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'night_shift'); END IF;
    END IF;

    -- archaeologist: reply in thread older than 90 days
    IF EXISTS(
        SELECT 1 FROM forum_posts fp
        JOIN forum_threads ft ON ft.id = fp.thread_id
        WHERE fp.author_id = p_user_id AND fp.is_deleted = false
        AND ft.created_at < fp.created_at - INTERVAL '90 days'
        LIMIT 1
    ) THEN
        SELECT (grant_achievement(p_user_id, 'archaeologist')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'archaeologist'); END IF;
    END IF;

    -- overfitting: 100+ posts
    IF (SELECT COUNT(*) FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false) >= 100 THEN
        SELECT (grant_achievement(p_user_id, 'overfitting')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'overfitting'); END IF;
    END IF;

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

-- ==========================================
-- FIX 3: Rate-limit create_forum_post — max 1 post per 10 seconds
-- ABUSE: Bot/script can spam hundreds of posts per minute
-- ==========================================

CREATE OR REPLACE FUNCTION public.create_forum_post(
    p_thread_id INTEGER,
    p_content TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id INTEGER;
    v_thread_author UUID;
    v_last_post TIMESTAMPTZ;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND is_verified = true) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;
    IF EXISTS (
        SELECT 1 FROM user_mod_actions
        WHERE user_id = auth.uid() AND action_type IN ('ban', 'mute')
        AND is_active = true AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'User is restricted';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM forum_threads WHERE id = p_thread_id AND is_locked = false AND is_deleted = false) THEN
        RAISE EXCEPTION 'Thread is locked or deleted';
    END IF;
    IF length(p_content) < 1 OR length(p_content) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;

    -- Rate limit: 1 post per 10 seconds
    SELECT MAX(created_at) INTO v_last_post
    FROM forum_posts WHERE author_id = auth.uid();
    IF v_last_post IS NOT NULL AND (now() - v_last_post) < interval '10 seconds' THEN
        RAISE EXCEPTION 'Too fast. Wait a few seconds.';
    END IF;

    INSERT INTO forum_posts (thread_id, author_id, content)
    VALUES (p_thread_id, auth.uid(), p_content)
    RETURNING id INTO v_id;

    UPDATE forum_threads
    SET posts_count = posts_count + 1,
        last_post_at = now(),
        last_post_by = auth.uid(),
        updated_at = now()
    WHERE id = p_thread_id;

    -- Notify thread author about the reply
    SELECT author_id INTO v_thread_author FROM forum_threads WHERE id = p_thread_id;
    IF v_thread_author IS NOT NULL AND v_thread_author != auth.uid() THEN
        INSERT INTO notifications (user_id, type, from_user_id, ref_thread_id, ref_post_id, snippet)
        VALUES (
            v_thread_author, 'reply', auth.uid(), p_thread_id, v_id,
            left(p_content, 80)
        );
    END IF;

    RETURN v_id;
END;
$$;

-- ==========================================
-- FIX 4: Rate-limit create_forum_thread — max 1 thread per 30 seconds
-- ==========================================

CREATE OR REPLACE FUNCTION public.create_forum_thread(
    p_category_id INTEGER,
    p_title TEXT,
    p_content TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id INTEGER;
    v_last_thread TIMESTAMPTZ;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND is_verified = true) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;
    IF EXISTS (
        SELECT 1 FROM user_mod_actions
        WHERE user_id = auth.uid() AND action_type IN ('ban', 'mute')
        AND is_active = true AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'User is restricted';
    END IF;
    IF length(p_title) < 3 OR length(p_title) > 200 THEN
        RAISE EXCEPTION 'Title must be 3-200 characters';
    END IF;
    IF length(p_content) < 1 OR length(p_content) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;

    -- Rate limit: 1 thread per 30 seconds
    SELECT MAX(created_at) INTO v_last_thread
    FROM forum_threads WHERE author_id = auth.uid();
    IF v_last_thread IS NOT NULL AND (now() - v_last_thread) < interval '30 seconds' THEN
        RAISE EXCEPTION 'Too fast. Wait before creating another thread.';
    END IF;

    INSERT INTO forum_threads (category_id, author_id, title, content, last_post_at)
    VALUES (p_category_id, auth.uid(), p_title, p_content, now())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ==========================================
-- FIX 5: Rate-limit toggle_post_reaction — max 5 reactions per 3 seconds
-- Also fixes notification spam by only notifying on first reaction per emoji
-- ==========================================

CREATE OR REPLACE FUNCTION public.toggle_post_reaction(p_post_id INTEGER, p_emoji TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_exists BOOLEAN;
    v_post_author UUID;
    v_thread_id INTEGER;
    v_action TEXT;
    v_user_role TEXT;
    v_recent_count INTEGER;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = v_uid AND is_verified = true) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;

    -- admin_like: only admin/stmoderator can use it
    IF p_emoji = 'admin_like' THEN
        SELECT COALESCE(role, 'member') INTO v_user_role FROM profiles WHERE user_id = v_uid;
        IF v_user_role NOT IN ('admin', 'stmoderator') THEN
            RAISE EXCEPTION 'Admin like is only available to admins';
        END IF;
    END IF;

    IF p_emoji NOT IN ('like','dislike','fire','puke','brain','emotion','admin_like') THEN
        RAISE EXCEPTION 'Invalid emoji';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM forum_posts WHERE id = p_post_id AND is_deleted = false) THEN
        RAISE EXCEPTION 'Post not found';
    END IF;

    -- Rate limit: max 5 reaction toggles per 3 seconds
    SELECT COUNT(*) INTO v_recent_count
    FROM post_reactions
    WHERE user_id = v_uid AND created_at > now() - interval '3 seconds';
    IF v_recent_count >= 5 THEN
        RAISE EXCEPTION 'Too many reactions. Slow down.';
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM post_reactions WHERE post_id = p_post_id AND user_id = v_uid AND emoji = p_emoji
    ) INTO v_exists;

    IF v_exists THEN
        DELETE FROM post_reactions WHERE post_id = p_post_id AND user_id = v_uid AND emoji = p_emoji;
        v_action := 'removed';
    ELSE
        INSERT INTO post_reactions (post_id, user_id, emoji) VALUES (p_post_id, v_uid, p_emoji);
        v_action := 'added';

        SELECT author_id, thread_id INTO v_post_author, v_thread_id
        FROM forum_posts WHERE id = p_post_id;
        IF v_post_author IS NOT NULL AND v_post_author != v_uid THEN
            INSERT INTO notifications (user_id, type, from_user_id, ref_thread_id, ref_post_id, emoji, snippet)
            VALUES (
                v_post_author, 'reaction', v_uid, v_thread_id, p_post_id, p_emoji,
                (SELECT left(content, 80) FROM forum_posts WHERE id = p_post_id)
            )
            ON CONFLICT DO NOTHING;
        END IF;

        PERFORM check_reaction_achievements(p_post_id, v_uid);
    END IF;

    RETURN jsonb_build_object('action', v_action, 'emoji', p_emoji);
END;
$$;

-- ==========================================
-- FIX 6: admin_set_user_role — prevent admin from removing their own admin role
-- ==========================================

CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id UUID, p_role TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;

    IF p_role NOT IN ('admin', 'stmoderator', 'moderator', 'beta', 'alpha', 'member') THEN
        RETURN false;
    END IF;

    -- Prevent admin from demoting themselves
    IF p_user_id = auth.uid() AND p_role != 'admin' THEN
        RETURN false;
    END IF;

    UPDATE profiles SET role = p_role WHERE user_id = p_user_id;

    -- Sync role tables
    DELETE FROM st_moderators WHERE user_id = p_user_id;
    IF p_role = 'stmoderator' THEN
        INSERT INTO st_moderators (user_id, telegram_id, telegram_username, assigned_by)
        SELECT p_user_id, telegram_id, telegram_username, auth.uid()
        FROM profiles WHERE user_id = p_user_id;
    END IF;

    DELETE FROM moderators WHERE user_id = p_user_id;
    IF p_role IN ('moderator', 'stmoderator') THEN
        INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
        SELECT p_user_id, telegram_id, telegram_username, auth.uid()
        FROM profiles WHERE user_id = p_user_id;
    END IF;

    DELETE FROM admin_users WHERE user_id = p_user_id;
    IF p_role = 'admin' THEN
        INSERT INTO admin_users (user_id) VALUES (p_user_id);
    END IF;

    RETURN true;
END;
$$;
