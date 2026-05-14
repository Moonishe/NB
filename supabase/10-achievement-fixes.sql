-- ============================================
-- BUNDLE 10: ACHIEVEMENT FIXES (canonical)
-- Run AFTER 07-vulnerability-fixes.sql
-- Consolidates fixes from 04, 06a, 06b, 07, 08
-- ============================================

-- 1. Add missing 'verified' achievement to seed data
INSERT INTO achievements (id, title, description, category, rarity, points, icon_emoji, max_supply, is_secret, sort_order)
VALUES ('verified', 'Верифицирован', 'Аккаунт проверен администратором', 'starter', 'common', 15, '✅', NULL, FALSE, 29)
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    rarity = EXCLUDED.rarity,
    points = EXCLUDED.points,
    icon_emoji = EXCLUDED.icon_emoji,
    max_supply = EXCLUDED.max_supply,
    is_secret = EXCLUDED.is_secret,
    sort_order = EXCLUDED.sort_order;

-- 2. Canonical check_and_grant_achievements (single authoritative version)
DROP FUNCTION IF EXISTS public.check_and_grant_achievements(UUID) CASCADE;
CREATE OR REPLACE FUNCTION public.check_and_grant_achievements(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result BOOLEAN;
    v_granted TEXT[] := ARRAY[]::TEXT[];
    v_profile RECORD;
    v_referral_count INT := 0;
    v_has_posts BOOLEAN;
    v_days_since_reg INT;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object('granted', to_jsonb(v_granted));
    END IF;

    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object('granted', '[]'::jsonb, 'error', 'forbidden');
    END IF;

    SELECT * INTO v_profile FROM profiles WHERE user_id = p_user_id;
    IF v_profile IS NULL THEN
        RETURN jsonb_build_object('granted', '[]'::jsonb);
    END IF;

    -- === STARTER ACHIEVEMENTS ===

    -- welcome: always
    SELECT (grant_achievement(p_user_id, 'welcome')->>'granted')::BOOLEAN INTO v_result;
    IF v_result THEN v_granted := array_append(v_granted, 'welcome'); END IF;

    -- verified: is_verified = true
    IF v_profile.is_verified THEN
        SELECT (grant_achievement(p_user_id, 'verified')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'verified'); END IF;
    END IF;

    -- first_referral: 1+ referrals
    SELECT COUNT(*) INTO v_referral_count
    FROM invite_code_uses icu
    JOIN invite_codes ic ON ic.id = icu.invite_code_id
    WHERE ic.created_by = p_user_id;

    IF v_referral_count >= 1 THEN
        SELECT (grant_achievement(p_user_id, 'first_referral')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_referral'); END IF;
    END IF;

    -- first_thread: created a thread
    IF EXISTS(SELECT 1 FROM forum_threads WHERE author_id = p_user_id AND is_deleted = false LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_thread')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_thread'); END IF;
    END IF;

    -- first_reaction: placed a reaction
    IF EXISTS(SELECT 1 FROM post_reactions WHERE user_id = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_reaction')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_reaction'); END IF;
    END IF;

    -- profile_tuned: bio or photo filled
    IF (v_profile.bio IS NOT NULL AND v_profile.bio <> '')
       OR (v_profile.telegram_photo_url IS NOT NULL AND v_profile.telegram_photo_url <> '') THEN
        SELECT (grant_achievement(p_user_id, 'profile_tuned')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'profile_tuned'); END IF;
    END IF;

    -- daily_login: 3-day streak
    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 3) THEN
        SELECT (grant_achievement(p_user_id, 'daily_login')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'daily_login'); END IF;
    END IF;

    -- first_comment: replied in someone else's thread
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

    -- FIX: first_model_rate — check result_ratings (was: results.author = p_user_id::text — never matched)
    IF EXISTS(SELECT 1 FROM result_ratings WHERE user_id = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_model_rate')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_model_rate'); END IF;
    END IF;

    -- first_mention: used @mention
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND content LIKE '%@%' LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_mention')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_mention'); END IF;
    END IF;

    -- first_edit: edited a post
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND edited_at IS NOT NULL LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_edit')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_edit'); END IF;
    END IF;

    -- === RARE ACHIEVEMENTS ===

    -- binding_layer: 3+ referrals
    IF v_referral_count >= 3 THEN
        SELECT (grant_achievement(p_user_id, 'binding_layer')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'binding_layer'); END IF;
    END IF;

    -- before_public_launch: registered before 2026-02-19
    IF v_profile.created_at IS NOT NULL AND v_profile.created_at < TIMESTAMPTZ '2026-02-19 00:00:00+00' THEN
        SELECT (grant_achievement(p_user_id, 'before_public_launch')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'before_public_launch'); END IF;
    END IF;

    -- beta_user: role = beta
    IF v_profile.role = 'beta' THEN
        SELECT (grant_achievement(p_user_id, 'beta_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'beta_user'); END IF;
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

    -- overfitting: 100+ posts
    IF (SELECT COUNT(*) FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false) >= 100 THEN
        SELECT (grant_achievement(p_user_id, 'overfitting')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'overfitting'); END IF;
    END IF;

    -- seven_day_streak: 7-day streak
    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 7) THEN
        SELECT (grant_achievement(p_user_id, 'seven_day_streak')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'seven_day_streak'); END IF;
    END IF;

    -- FIX: night_shift — MSK night = UTC 21:00-01:59 (was: UTC 02:00-05:00 = MSK morning)
    IF EXISTS(
        SELECT 1 FROM forum_posts
        WHERE author_id = p_user_id AND is_deleted = false
          AND (EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') >= 21
               OR EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') < 2)
        LIMIT 1
    ) THEN
        SELECT (grant_achievement(p_user_id, 'night_shift')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'night_shift'); END IF;
    END IF;

    -- archaeologist: replied in thread > 90 days old
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

    -- === UNIQUE ACHIEVEMENTS ===

    -- cluster_formed: 10+ referrals
    IF v_referral_count >= 10 THEN
        SELECT (grant_achievement(p_user_id, 'cluster_formed')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'cluster_formed'); END IF;
    END IF;

    -- first_among_equals: uid <= 10
    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 10 THEN
        SELECT (grant_achievement(p_user_id, 'first_among_equals')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_among_equals'); END IF;
    END IF;

    -- alpha_user: role = alpha
    IF v_profile.role = 'alpha' THEN
        SELECT (grant_achievement(p_user_id, 'alpha_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'alpha_user'); END IF;
    END IF;

    -- moderator_power: role in (moderator, stmoderator, admin)
    IF v_profile.role IN ('moderator', 'stmoderator', 'admin') THEN
        SELECT (grant_achievement(p_user_id, 'moderator_power')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'moderator_power'); END IF;
    END IF;

    -- === LIMITED ACHIEVEMENTS ===

    -- the_first_hundred: uid <= 100 (max 100)
    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 100 THEN
        SELECT (grant_achievement(p_user_id, 'the_first_hundred')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'the_first_hundred'); END IF;
    END IF;

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) TO service_role;

NOTIFY pgrst, 'reload schema';
