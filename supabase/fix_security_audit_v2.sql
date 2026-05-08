-- NeuroBench security audit fixes v2

CREATE TABLE IF NOT EXISTS public.user_action_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_action_events_user_action_created
ON public.user_action_events(user_id, action_type, created_at DESC);

ALTER TABLE public.user_action_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_user_action_events" ON public.user_action_events;
CREATE POLICY "deny_direct_user_action_events" ON public.user_action_events
    FOR ALL USING (false) WITH CHECK (false);

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
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM user_achievements WHERE user_id = p_user_id AND achievement_id = p_achievement_id
    ) INTO v_already;

    IF v_already THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'already_unlocked');
    END IF;

    SELECT max_supply INTO v_max_supply FROM achievements WHERE id = p_achievement_id;
    IF v_max_supply IS NULL AND NOT EXISTS (SELECT 1 FROM achievements WHERE id = p_achievement_id) THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'achievement_not_found');
    END IF;

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

REVOKE EXECUTE ON FUNCTION public.grant_achievement(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grant_achievement(UUID, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.grant_achievement(UUID, TEXT) FROM authenticated;

CREATE OR REPLACE FUNCTION public.check_and_grant_achievements(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_granted TEXT[] := '{}';
    v_result BOOLEAN;
    v_referral_count INT := 0;
    v_profile RECORD;
    v_has_posts BOOLEAN;
    v_days_since_reg INT;
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object('granted', '[]'::jsonb, 'error', 'forbidden');
    END IF;

    SELECT * INTO v_profile FROM profiles WHERE user_id = p_user_id;
    IF v_profile IS NULL THEN RETURN jsonb_build_object('granted', '[]'::jsonb); END IF;

    SELECT (grant_achievement(p_user_id, 'welcome')->>'granted')::BOOLEAN INTO v_result;
    IF v_result THEN v_granted := array_append(v_granted, 'welcome'); END IF;

    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 10 THEN
        SELECT (grant_achievement(p_user_id, 'first_among_equals')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_among_equals'); END IF;
    END IF;

    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 100 THEN
        SELECT (grant_achievement(p_user_id, 'the_first_hundred')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'the_first_hundred'); END IF;
    END IF;

    IF v_profile.created_at IS NOT NULL AND v_profile.created_at < TIMESTAMPTZ '2026-02-19 00:00:00+00' THEN
        SELECT (grant_achievement(p_user_id, 'before_public_launch')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'before_public_launch'); END IF;
    END IF;

    IF v_profile.role = 'alpha' THEN
        SELECT (grant_achievement(p_user_id, 'alpha_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'alpha_user'); END IF;
    END IF;

    IF v_profile.role = 'beta' THEN
        SELECT (grant_achievement(p_user_id, 'beta_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'beta_user'); END IF;
    END IF;

    IF v_profile.role IN ('moderator', 'stmoderator', 'admin') THEN
        SELECT (grant_achievement(p_user_id, 'moderator_power')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'moderator_power'); END IF;
    END IF;

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

    IF (v_profile.bio IS NOT NULL AND v_profile.bio <> '')
       OR (v_profile.telegram_photo_url IS NOT NULL AND v_profile.telegram_photo_url <> '') THEN
        SELECT (grant_achievement(p_user_id, 'profile_tuned')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'profile_tuned'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM post_reactions WHERE user_id = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_reaction')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_reaction'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 3) THEN
        SELECT (grant_achievement(p_user_id, 'daily_login')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'daily_login'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM forum_threads WHERE author_id = p_user_id AND is_deleted = false LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_thread')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_thread'); END IF;
    END IF;

    IF EXISTS(
        SELECT 1 FROM forum_posts fp
        JOIN forum_threads ft ON ft.id = fp.thread_id
        WHERE fp.author_id = p_user_id AND fp.is_deleted = false AND ft.author_id != p_user_id
        LIMIT 1
    ) THEN
        SELECT (grant_achievement(p_user_id, 'first_comment')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_comment'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM results WHERE author = p_user_id::text LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_model_rate')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_model_rate'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND content LIKE '%@%' LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_mention')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_mention'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND updated_at IS NOT NULL AND updated_at != created_at LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_edit')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_edit'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 7) THEN
        SELECT (grant_achievement(p_user_id, 'seven_day_streak')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'seven_day_streak'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') >= 2 AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') < 5 LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'night_shift')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'night_shift'); END IF;
    END IF;

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

    IF (SELECT COUNT(*) FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false) >= 100 THEN
        SELECT (grant_achievement(p_user_id, 'overfitting')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'overfitting'); END IF;
    END IF;

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

CREATE OR REPLACE FUNCTION public.check_reaction_achievements(p_post_id INTEGER, p_reactor_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_post_author UUID;
    v_total_reactions INT;
    v_dislike_count INT;
    v_puke_count INT;
    v_admin_like_count INT;
    v_reactor_role TEXT;
    v_result BOOLEAN;
    v_granted TEXT[] := '{}';
BEGIN
    SELECT author_id INTO v_post_author FROM forum_posts WHERE id = p_post_id;
    IF v_post_author IS NULL THEN RETURN jsonb_build_object('granted', '[]'::jsonb); END IF;

    SELECT COUNT(*) INTO v_total_reactions FROM post_reactions WHERE post_id = p_post_id;
    SELECT COUNT(*) INTO v_dislike_count FROM post_reactions WHERE post_id = p_post_id AND emoji = 'dislike';
    IF v_total_reactions >= 20 AND v_dislike_count = 0 THEN
        SELECT (grant_achievement(v_post_author, 'silent_wave')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'silent_wave'); END IF;
    END IF;

    SELECT COUNT(*) INTO v_puke_count FROM post_reactions WHERE post_id = p_post_id AND emoji = 'puke';
    IF v_puke_count >= 20 THEN
        SELECT (grant_achievement(v_post_author, 'puke_gradient')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'puke_gradient'); END IF;
    END IF;

    SELECT COALESCE(role, 'member') INTO v_reactor_role FROM profiles WHERE user_id = p_reactor_id;
    IF v_reactor_role IN ('admin', 'stmoderator', 'moderator') THEN
        SELECT (grant_achievement(v_post_author, 'models_remember')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'models_remember'); END IF;
    END IF;

    SELECT COUNT(*) INTO v_admin_like_count FROM post_reactions WHERE post_id = p_post_id AND emoji = 'admin_like';
    IF v_admin_like_count >= 1 THEN
        IF EXISTS (SELECT 1 FROM achievements WHERE id = 'admin_endorsement') THEN
            SELECT (grant_achievement(v_post_author, 'admin_endorsement')->>'granted')::BOOLEAN INTO v_result;
            IF v_result THEN v_granted := array_append(v_granted, 'admin_endorsement'); END IF;
        END IF;
    END IF;

    PERFORM grant_achievement(p_reactor_id, 'first_reaction');

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

CREATE OR REPLACE FUNCTION public.check_pin_achievement(p_thread_id INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_author UUID;
    v_result BOOLEAN;
BEGIN
    SELECT author_id INTO v_author
    FROM forum_threads
    WHERE id = p_thread_id AND is_deleted = false AND is_pinned = true;

    IF v_author IS NULL THEN
        RETURN jsonb_build_object('granted', false);
    END IF;

    SELECT (grant_achievement(v_author, 'benchmark_oracle')->>'granted')::BOOLEAN INTO v_result;
    RETURN jsonb_build_object('granted', COALESCE(v_result, false), 'achievement_id', 'benchmark_oracle');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM authenticated;

DROP FUNCTION IF EXISTS public.mod_pin_thread(INTEGER, BOOLEAN);

CREATE OR REPLACE FUNCTION public.mod_pin_thread(p_thread_id INTEGER, p_pin BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated_count INTEGER;
    v_pin_achievement JSONB := NULL;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_moderator');
    END IF;

    UPDATE forum_threads
    SET is_pinned = p_pin, updated_at = now()
    WHERE id = p_thread_id AND is_deleted = false;
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'thread_not_found');
    END IF;

    IF p_pin THEN
        v_pin_achievement := check_pin_achievement(p_thread_id);
    END IF;

    RETURN jsonb_build_object('ok', true, 'pinned', p_pin, 'achievement', v_pin_achievement);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_mention_notifications(
    p_post_id INTEGER,
    p_thread_id INTEGER,
    p_mentioned_user_ids UUID[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER := 0;
    v_uid UUID;
    v_snippet TEXT;
    v_recent_mentions INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN RETURN 0; END IF;
    IF p_mentioned_user_ids IS NULL OR array_length(p_mentioned_user_ids, 1) IS NULL THEN RETURN 0; END IF;
    IF array_length(p_mentioned_user_ids, 1) > 10 THEN
        RAISE EXCEPTION 'Too many mentions';
    END IF;

    SELECT COUNT(*) INTO v_recent_mentions
    FROM notifications
    WHERE from_user_id = auth.uid()
      AND type = 'mention'
      AND created_at > now() - interval '5 minutes';
    IF v_recent_mentions >= 30 THEN
        RAISE EXCEPTION 'Too many mentions. Slow down.';
    END IF;

    SELECT left(content, 80) INTO v_snippet
    FROM forum_posts
    WHERE id = p_post_id
      AND thread_id = p_thread_id
      AND author_id = auth.uid()
      AND is_deleted = false;

    IF v_snippet IS NULL THEN RETURN 0; END IF;

    FOREACH v_uid IN ARRAY p_mentioned_user_ids LOOP
        IF v_uid != auth.uid()
           AND EXISTS (SELECT 1 FROM profiles WHERE user_id = v_uid)
           AND NOT EXISTS (
               SELECT 1 FROM notifications
               WHERE user_id = v_uid
                 AND type = 'mention'
                 AND from_user_id = auth.uid()
                 AND ref_post_id = p_post_id
           ) THEN
            INSERT INTO notifications (user_id, type, from_user_id, ref_thread_id, ref_post_id, snippet)
            VALUES (v_uid, 'mention', auth.uid(), p_thread_id, p_post_id, v_snippet);
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;

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

    SELECT COUNT(*) INTO v_recent_count
    FROM user_action_events
    WHERE user_id = v_uid
      AND action_type = 'reaction'
      AND created_at > now() - interval '3 seconds';
    IF v_recent_count >= 5 THEN
        RAISE EXCEPTION 'Too many reactions. Slow down.';
    END IF;

    INSERT INTO user_action_events (user_id, action_type) VALUES (v_uid, 'reaction');

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
            SELECT v_post_author, 'reaction', v_uid, v_thread_id, p_post_id, p_emoji,
                   (SELECT left(content, 80) FROM forum_posts WHERE id = p_post_id)
            WHERE NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE user_id = v_post_author
                  AND type = 'reaction'
                  AND from_user_id = v_uid
                  AND ref_post_id = p_post_id
                  AND emoji = p_emoji
            );
        END IF;

        PERFORM check_reaction_achievements(p_post_id, v_uid);
    END IF;

    RETURN jsonb_build_object('action', v_action, 'emoji', p_emoji);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_generate_invite_for_user(p_user_id UUID, p_max_uses INT DEFAULT 1)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code TEXT;
    v_invite_id UUID;
    v_max_uses INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = p_user_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    v_max_uses := LEAST(100, GREATEST(1, COALESCE(p_max_uses, 1)));
    v_code := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 8));

    INSERT INTO invite_codes (code, is_admin_code, max_uses, created_by)
    VALUES (v_code, true, v_max_uses, auth.uid())
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true,
        generated_invite_code_id = v_invite_id
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object('ok', true, 'code', v_code, 'invite_id', v_invite_id, 'max_uses', v_max_uses);
END;
$$;

NOTIFY pgrst, 'reload schema';
