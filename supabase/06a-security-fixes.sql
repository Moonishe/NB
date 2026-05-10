-- ============================================
-- BUNDLE 6A: SECURITY FIXES (small patches)
-- Run AFTER bundles 01-05
-- ============================================


-- --- fix_telegram_auth_hardening.sql ---

-- Telegram auth hardening: DB-backed rate limit for the Edge Function.
-- Run this before deploying supabase/functions/telegram-auth/index.ts.

CREATE TABLE IF NOT EXISTS public.telegram_auth_rate_limits (
    identifier TEXT PRIMARY KEY,
    attempts INTEGER NOT NULL DEFAULT 0,
    window_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.telegram_auth_rate_limits ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.telegram_auth_rate_limits FROM PUBLIC;
REVOKE ALL ON TABLE public.telegram_auth_rate_limits FROM anon;
REVOKE ALL ON TABLE public.telegram_auth_rate_limits FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.telegram_auth_rate_limits TO service_role;

CREATE INDEX IF NOT EXISTS idx_telegram_auth_rate_limits_updated_at
    ON public.telegram_auth_rate_limits (updated_at);

DROP FUNCTION IF EXISTS public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.check_telegram_auth_rate_limit(
    p_identifier TEXT,
    p_max_attempts INTEGER DEFAULT 20,
    p_window_seconds INTEGER DEFAULT 300
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := now();
    v_window INTERVAL := make_interval(secs => GREATEST(1, COALESCE(p_window_seconds, 300)));
    v_attempts INTEGER;
BEGIN
    IF COALESCE(btrim(p_identifier), '') = '' THEN
        RETURN false;
    END IF;

    IF COALESCE(p_max_attempts, 0) <= 0 THEN
        RETURN false;
    END IF;

    INSERT INTO public.telegram_auth_rate_limits AS rl (
        identifier,
        attempts,
        window_started_at,
        updated_at
    )
    VALUES (
        p_identifier,
        1,
        v_now,
        v_now
    )
    ON CONFLICT (identifier) DO UPDATE
    SET attempts = CASE
            WHEN rl.window_started_at <= v_now - v_window THEN 1
            ELSE rl.attempts + 1
        END,
        window_started_at = CASE
            WHEN rl.window_started_at <= v_now - v_window THEN v_now
            ELSE rl.window_started_at
        END,
        updated_at = v_now
    RETURNING attempts INTO v_attempts;

    DELETE FROM public.telegram_auth_rate_limits
    WHERE updated_at < v_now - interval '1 day';

    RETURN v_attempts <= p_max_attempts;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_telegram_auth_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;

DROP FUNCTION IF EXISTS public.get_auth_user_id_by_email(TEXT);
CREATE OR REPLACE FUNCTION public.get_auth_user_id_by_email(p_email TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.id
    FROM auth.users AS u
    WHERE lower(u.email) = lower(btrim(p_email))
    LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_id_by_email(TEXT) TO service_role;

NOTIFY pgrst, 'reload schema';


-- --- fix_invite_race_conditions.sql ---

-- Fix race conditions in invite code system
-- Addresses: concurrent claim_invite_code, generate_user_invite_code, and telegram-auth invite claim

-- 1. Fix claim_invite_code: add FOR UPDATE lock to prevent double-use
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT);
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_code TEXT;
    v_invite_id UUID;
    v_max_uses INTEGER;
    v_current_uses INTEGER;
BEGIN
    IF p_code IS NOT NULL THEN
        v_code := p_code;
    ELSE
        SELECT pending_invite_code INTO v_code
        FROM profiles WHERE user_id = auth.uid();
    END IF;

    IF v_code IS NULL THEN
        RETURN false;
    END IF;

    SELECT id, max_uses, use_count INTO v_invite_id, v_max_uses, v_current_uses
    FROM invite_codes
    WHERE code = v_code AND (max_uses IS NULL OR use_count < max_uses)
    FOR UPDATE SKIP LOCKED;

    IF v_invite_id IS NULL THEN
        RETURN false;
    END IF;

    IF EXISTS (SELECT 1 FROM invite_code_uses WHERE invite_code_id = v_invite_id AND user_id = auth.uid()) THEN
        RETURN false;
    END IF;

    UPDATE invite_codes
    SET use_count = use_count + 1,
        used_by = auth.uid(),
        used_at = now()
    WHERE id = v_invite_id;

    INSERT INTO invite_code_uses (invite_code_id, user_id)
    VALUES (v_invite_id, auth.uid());

    UPDATE profiles
    SET used_invite_code_id = v_invite_id,
        pending_invite_code = NULL
    WHERE user_id = auth.uid();

    RETURN true;
END;
$$;

-- 2. Fix generate_user_invite_code: serialize with advisory lock per user
DROP FUNCTION IF EXISTS public.generate_user_invite_code();
CREATE OR REPLACE FUNCTION public.generate_user_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_role TEXT;
    v_max INTEGER;
    v_active_count INTEGER;
    v_oldest_id UUID;
    v_new_code TEXT;
    v_invite_id UUID;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

    SELECT role INTO v_role FROM profiles WHERE user_id = v_user_id AND is_verified = true;
    IF v_role IS NULL THEN RETURN NULL; END IF;

    v_max := get_invite_max(v_role);

    SELECT COUNT(*) INTO v_active_count
    FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND (used_by IS NULL);

    IF v_active_count >= v_max THEN
        SELECT id INTO v_oldest_id
        FROM invite_codes
        WHERE created_by = v_user_id
          AND is_admin_code = false
          AND used_by IS NULL
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_oldest_id IS NOT NULL THEN
            DELETE FROM invite_codes WHERE id = v_oldest_id;
        END IF;
    END IF;

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code)
    VALUES (v_new_code, v_user_id, false)
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true, generated_invite_code_id = v_invite_id
    WHERE user_id = v_user_id;

    RETURN v_new_code;
END;
$$;

-- 3. Admin RPC for atomic invite claim (used by telegram-auth edge function)
DROP FUNCTION IF EXISTS public.admin_claim_invite_for_user(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.admin_claim_invite_for_user(p_code TEXT, p_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite_id UUID;
    v_max_uses INTEGER;
BEGIN
    SELECT id, max_uses INTO v_invite_id, v_max_uses
    FROM invite_codes
    WHERE code = upper(p_code)
      AND (max_uses IS NULL OR use_count < max_uses)
    FOR UPDATE SKIP LOCKED;

    IF v_invite_id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE invite_codes
    SET use_count = use_count + 1,
        used_by = p_user_id,
        used_at = now()
    WHERE id = v_invite_id;

    INSERT INTO invite_code_uses (invite_code_id, user_id)
    VALUES (v_invite_id, p_user_id);

    RETURN v_invite_id;
END;
$$;


-- --- fix_display_name_role.sql ---

-- Fix: get_user_display_name missing 'role' field
-- Without this, forum.js can't determine admin_like visibility

DROP FUNCTION IF EXISTS public.get_user_display_name();

CREATE OR REPLACE FUNCTION public.get_user_display_name()
RETURNS TABLE(
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    display_name TEXT,
    is_verified BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT,
    invite_use_count INTEGER,
    bio TEXT,
    role TEXT,
    uid INTEGER,
    is_moderator BOOLEAN,
    is_banned BOOLEAN,
    is_muted BOOLEAN,
    ban_reason TEXT,
    mute_reason TEXT,
    ban_expires TIMESTAMPTZ,
    mute_expires TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_username,
        p.telegram_photo_url,
        COALESCE(NULLIF(regexp_replace(p.telegram_first_name, '[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]', '', 'g'), ''), NULLIF(regexp_replace(p.telegram_username, '[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF]', '', 'g'), ''), split_part(p.email, '@', 1)) AS display_name,
        p.is_verified,
        p.has_generated_invite,
        ic.code AS generated_code,
        ic.use_count AS invite_use_count,
        p.bio,
        COALESCE(p.role, 'member') AS role,
        p.uid,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = p.user_id) AS is_moderator,
        EXISTS (
            SELECT 1 FROM user_mod_actions uma
            WHERE uma.user_id = p.user_id AND uma.action_type = 'ban'
            AND uma.is_active = true AND (uma.expires_at IS NULL OR uma.expires_at > now())
        ) AS is_banned,
        EXISTS (
            SELECT 1 FROM user_mod_actions uma
            WHERE uma.user_id = p.user_id AND uma.action_type = 'mute'
            AND uma.is_active = true AND (uma.expires_at IS NULL OR uma.expires_at > now())
        ) AS is_muted,
        (SELECT uma_b.reason FROM user_mod_actions uma_b
         WHERE uma_b.user_id = p.user_id AND uma_b.action_type = 'ban'
         AND uma_b.is_active = true AND (uma_b.expires_at IS NULL OR uma_b.expires_at > now())
         ORDER BY uma_b.created_at DESC LIMIT 1) AS ban_reason,
        (SELECT uma_m.reason FROM user_mod_actions uma_m
         WHERE uma_m.user_id = p.user_id AND uma_m.action_type = 'mute'
         AND uma_m.is_active = true AND (uma_m.expires_at IS NULL OR uma_m.expires_at > now())
         ORDER BY uma_m.created_at DESC LIMIT 1) AS mute_reason,
        (SELECT uma_b2.expires_at FROM user_mod_actions uma_b2
         WHERE uma_b2.user_id = p.user_id AND uma_b2.action_type = 'ban'
         AND uma_b2.is_active = true AND (uma_b2.expires_at IS NULL OR uma_b2.expires_at > now())
         ORDER BY uma_b2.created_at DESC LIMIT 1) AS ban_expires,
        (SELECT uma_m2.expires_at FROM user_mod_actions uma_m2
         WHERE uma_m2.user_id = p.user_id AND uma_m2.action_type = 'mute'
         AND uma_m2.is_active = true AND (uma_m2.expires_at IS NULL OR uma_m2.expires_at > now())
         ORDER BY uma_m2.created_at DESC LIMIT 1) AS mute_expires
    FROM profiles p
    LEFT JOIN invite_codes ic ON p.generated_invite_code_id = ic.id
    WHERE p.user_id = auth.uid();
END;
$$;


-- --- fix_is_moderator.sql ---

-- Fix is_moderator() to check profiles.role in addition to moderators table
DROP FUNCTION IF EXISTS public.is_moderator();
CREATE OR REPLACE FUNCTION public.is_moderator()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role FROM profiles WHERE user_id = auth.uid();
    IF v_role IN ('admin', 'stmoderator', 'moderator') THEN
        RETURN true;
    END IF;
    RETURN EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid());
END;
$$;


-- --- fix_moderator_role_sync.sql ---

-- Fix admin_assign_moderator and admin_remove_moderator to sync profiles.role

DROP FUNCTION IF EXISTS public.admin_assign_moderator(UUID);
DROP FUNCTION IF EXISTS public.admin_assign_moderator(UUID, BIGINT, TEXT);
CREATE OR REPLACE FUNCTION public.admin_assign_moderator(p_user_id UUID, p_telegram_id BIGINT DEFAULT NULL, p_telegram_username TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
    VALUES (p_user_id, p_telegram_id, p_telegram_username, auth.uid())
    ON CONFLICT (user_id) DO UPDATE SET
        telegram_id = EXCLUDED.telegram_id,
        telegram_username = EXCLUDED.telegram_username,
        assigned_by = EXCLUDED.assigned_by;

    UPDATE profiles SET role = 'moderator' WHERE user_id = p_user_id AND role = 'member';
    RETURN FOUND;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_remove_moderator(UUID);
CREATE OR REPLACE FUNCTION public.admin_remove_moderator(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM moderators WHERE user_id = p_user_id;
    IF FOUND THEN
        UPDATE profiles SET role = 'member' WHERE user_id = p_user_id AND role = 'moderator';
        RETURN true;
    END IF;
    RETURN false;
END;
$$;


-- --- fix_moderator_telegram_nullable.sql ---

-- Fix: allow moderators without telegram_id + fix RETURN FOUND issue
-- Run this in Supabase SQL Editor

ALTER TABLE moderators ALTER COLUMN telegram_id DROP NOT NULL;

DROP FUNCTION IF EXISTS public.admin_assign_moderator(UUID);
DROP FUNCTION IF EXISTS public.admin_assign_moderator(UUID, BIGINT, TEXT);
CREATE OR REPLACE FUNCTION public.admin_assign_moderator(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tg_id TEXT;
    v_tg_username TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = p_user_id) THEN
        RETURN false;
    END IF;
    SELECT telegram_id, telegram_username INTO v_tg_id, v_tg_username FROM profiles WHERE user_id = p_user_id;
    INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
    VALUES (p_user_id, v_tg_id, v_tg_username, auth.uid())
    ON CONFLICT (user_id) DO NOTHING;
    RETURN EXISTS (SELECT 1 FROM moderators WHERE user_id = p_user_id);
END;
$$;

NOTIFY pgrst, 'reload schema';


-- --- migration_invite_delete_used_error.sql ---

DROP FUNCTION IF EXISTS public.admin_delete_invite_code(UUID);
CREATE OR REPLACE FUNCTION public.admin_delete_invite_code(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite public.invite_codes%ROWTYPE;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN false;
    END IF;

    IF p_id IS NULL THEN
        RETURN false;
    END IF;

    SELECT * INTO v_invite
    FROM public.invite_codes
    WHERE id = p_id
    FOR UPDATE;

    IF v_invite.id IS NULL THEN
        RETURN false;
    END IF;

    IF COALESCE(v_invite.use_count, 0) > 0 OR v_invite.used_by IS NOT NULL THEN
        RAISE EXCEPTION 'Нельзя удалить использованный инвайт';
    END IF;

    UPDATE public.profiles
    SET has_generated_invite = false,
        generated_invite_code_id = NULL
    WHERE generated_invite_code_id = p_id;

    DELETE FROM public.invite_codes
    WHERE id = p_id;

    RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) TO service_role;


-- --- fix_security_audit_v2.sql ---

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

DROP FUNCTION IF EXISTS public.grant_achievement(UUID, TEXT);
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
    IF p_user_id IS NULL OR p_achievement_id IS NULL THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'invalid_input');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('public.grant_achievement'), hashtext(p_achievement_id));

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

DROP FUNCTION IF EXISTS public.check_and_grant_achievements(UUID);
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

    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND edited_at IS NOT NULL LIMIT 1) THEN
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

DROP FUNCTION IF EXISTS public.check_reaction_achievements(INTEGER, UUID);
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

DROP FUNCTION IF EXISTS public.check_pin_achievement(INTEGER);
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

DROP FUNCTION IF EXISTS public.mod_pin_thread(INTEGER, BOOLEAN) CASCADE;

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

DROP FUNCTION IF EXISTS public.create_mention_notifications(INTEGER, INTEGER, UUID[]) CASCADE;
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

DROP FUNCTION IF EXISTS public.toggle_post_reaction(INTEGER, TEXT);
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

DROP FUNCTION IF EXISTS public.admin_generate_invite_for_user(UUID);
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

