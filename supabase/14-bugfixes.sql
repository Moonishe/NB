-- ============================================
-- BUNDLE 14: CRITICAL BUGFIXES — Idempotent
-- Run AFTER all previous bundles (01-13)
-- ============================================
-- All statements are idempotent: safe to re-run.
-- No existing migration files are modified.
-- ============================================

BEGIN;
SET LOCAL search_path = public;

-- ==========================================
-- FIX 1 [CRITICAL]: admin_users RLS self-check policy
-- ==========================================
-- BUG: admin_users has RLS enabled (01-core.sql line 61) but NO policy.
-- This means SELECT FROM admin_users returns 0 rows for authenticated users,
-- so Api.isAdmin() (js/api.js line 431) ALWAYS returns false.
-- Additionally, all RLS policies on OTHER tables that check
--   EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
-- also always evaluate to false — breaking admin access everywhere.
--
-- FIX: Add a self-check SELECT policy so a user can see their own admin row.
-- This makes the EXISTS subqueries in other policies work correctly.

GRANT SELECT ON public.admin_users TO authenticated;

DROP POLICY IF EXISTS "self_check_admin" ON public.admin_users;
CREATE POLICY "self_check_admin" ON public.admin_users
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());


-- ==========================================
-- FIX 2 [HIGH]: forum_threads / forum_posts — remove direct UPDATE policy
-- ==========================================
-- BUG: The "author_mod_update_forum_threads" and "author_mod_update_forum_posts"
-- policies (03-forum.sql) allowed authors to UPDATE their rows directly.
-- RLS does not restrict WHICH columns can be changed, so an author could
-- set is_pinned, is_locked, is_deleted, or posts_count via a direct UPDATE
-- — bypassing the moderator-only RPC functions.
--
-- Note: 06b-security-hardening.sql already dropped these policies and
-- REVOKE'd UPDATE from authenticated. This DROP is a no-op safety net
-- for databases where 06b may not have been fully applied.
-- All updates now flow through SECURITY DEFINER RPCs (update_forum_thread,
-- update_forum_post) which only change title/content.

DROP POLICY IF EXISTS "author_mod_update_forum_threads" ON public.forum_threads;
DROP POLICY IF EXISTS "author_mod_update_forum_posts" ON public.forum_posts;


-- ==========================================
-- FIX 3 [HIGH]: post_reactions — block direct INSERT of admin_like
-- ==========================================
-- BUG: The "user_manage_own_reactions" policy (03-forum.sql) had no WITH CHECK,
-- so a user could directly INSERT a row with emoji='admin_like' — an emoji
-- that should only be set by moderators/admins via RPC.
--
-- FIX: Recreate the policy with WITH CHECK that rejects admin_like.
-- Note: 06b already dropped this policy and REVOKE'd INSERT from authenticated.
-- This policy is defense-in-depth: if INSERT is ever re-granted, admin_like
-- is still blocked at the RLS level.

DROP POLICY IF EXISTS "user_manage_own_reactions" ON public.post_reactions;
CREATE POLICY "user_manage_own_reactions" ON public.post_reactions
    FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid() AND emoji <> 'admin_like');


-- ==========================================
-- FIX 4 [HIGH]: admin_set_user_role — prevent self-demotion & last-admin removal
-- ==========================================
-- BUG: The original function (01-core.sql) had no guard against:
--   a) An admin demoting themselves (locking themselves out of admin).
--   b) Demoting the last remaining admin (no one left to manage the system).
--
-- FIX: Add guards — cannot change own role; cannot demote last admin.

CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id UUID, p_role TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_role TEXT;
    v_admin_count INTEGER;
BEGIN
    -- Only admins can set roles
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;

    -- Validate role
    IF p_role NOT IN ('admin', 'stmoderator', 'moderator', 'beta', 'alpha', 'member') THEN
        RETURN false;
    END IF;

    -- Prevent changing your own role (self-demotion or self-promotion abuse)
    IF p_user_id = auth.uid() THEN
        RETURN false;
    END IF;

    -- Prevent demoting the last admin: if target is currently admin and
    -- new role is not admin, ensure at least one other admin remains.
    SELECT role INTO v_current_role FROM profiles WHERE user_id = p_user_id;
    IF v_current_role = 'admin' AND p_role <> 'admin' THEN
        SELECT COUNT(*) INTO v_admin_count FROM admin_users;
        IF v_admin_count <= 1 THEN
            RETURN false;
        END IF;
    END IF;

    -- Update profile role
    UPDATE profiles SET role = p_role WHERE user_id = p_user_id;

    -- Sync st_moderators table
    DELETE FROM st_moderators WHERE user_id = p_user_id;
    IF p_role = 'stmoderator' THEN
        INSERT INTO st_moderators (user_id, telegram_id, telegram_username, assigned_by)
        SELECT p_user_id, telegram_id, telegram_username, auth.uid()
        FROM profiles WHERE user_id = p_user_id;
    END IF;

    -- Sync moderators table
    DELETE FROM moderators WHERE user_id = p_user_id;
    IF p_role IN ('moderator', 'stmoderator') THEN
        INSERT INTO moderators (user_id, telegram_id, telegram_username, assigned_by)
        SELECT p_user_id, telegram_id, telegram_username, auth.uid()
        FROM profiles WHERE user_id = p_user_id;
    END IF;

    -- Sync admin_users table
    DELETE FROM admin_users WHERE user_id = p_user_id;
    IF p_role = 'admin' THEN
        INSERT INTO admin_users (user_id) VALUES (p_user_id);
    END IF;

    RETURN true;
END;
$$;


-- ==========================================
-- FIX 5 [HIGH]: admin_update_user_profile — username format validation
-- ==========================================
-- BUG: The function (09-username-approval.sql) only checked length > 32
-- but did not validate the character set or minimum length. An admin could
-- set a username with invalid characters (spaces, unicode, special chars)
-- or a too-short username (1-2 chars).
--
-- FIX: Validate username matches ^[a-z0-9_]{3,30}$ (lowercase alphanumeric
-- and underscore, 3-30 characters).

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
        -- Validate username format: lowercase alphanumeric + underscore, 3-30 chars
        IF p_username !~ '^[a-z0-9_]{3,30}$' THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'username_invalid_format');
        END IF;
        SELECT user_id INTO v_conflict
        FROM public.profiles
        WHERE lower(username) = lower(p_username)
          AND user_id IS DISTINCT FROM p_user_id;
        IF v_conflict IS NOT NULL THEN
            RETURN jsonb_build_object('ok', false, 'reason', 'username_taken');
        END IF;
        UPDATE public.profiles
        SET username = p_username, pending_username = NULL
        WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'username');
    END IF;

    RETURN jsonb_build_object('ok', true, 'updated_fields', to_jsonb(v_updates));
END;
$$;


-- ==========================================
-- FIX 6 [HIGH]: admin_approve_username — FOR UPDATE lock to prevent TOCTOU
-- ==========================================
-- BUG: The function (09-username-approval.sql) reads pending_username and
-- checks for conflicts in two separate non-locked SELECTs. Between the check
-- and the UPDATE, a concurrent transaction could approve the same username
-- for a different user — causing a duplicate or race condition.
--
-- FIX: Use SELECT ... FOR UPDATE to lock the target row and conflict rows
-- so concurrent approvals serialize correctly.

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

    -- Lock the target row to prevent concurrent modifications
    SELECT pending_username INTO v_pending
    FROM public.profiles
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_pending IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'no_pending');
    END IF;

    IF p_approve THEN
        -- Lock conflict rows to prevent TOCTOU race
        SELECT p.user_id INTO v_conflict
        FROM public.profiles p
        WHERE lower(p.username) = lower(v_pending)
          AND p.user_id IS DISTINCT FROM p_user_id
        FOR UPDATE;

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

    RETURN jsonb_build_object(
        'ok', true,
        'approved', p_approve,
        'username', CASE WHEN p_approve THEN left(v_pending, 32) ELSE NULL END
    );
END;
$$;


-- ==========================================
-- FIX 7 [HIGH]: claim_invite_code — add rate limiting via user_action_events
-- ==========================================
-- BUG: The function (06b-security-hardening.sql) had no rate limiting.
-- A user could spam claim attempts to brute-force invite codes.
--
-- FIX: Limit to 1 claim attempt per minute using the user_action_events
-- table (same pattern as create_forum_post in 06b).

CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_result UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    -- Rate limiting: max 1 claim attempt per minute (check BEFORE attempt)
    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'invite_claim'
          AND created_at > now() - interval '1 minute'
    ) THEN
        RAISE EXCEPTION 'Rate limit: please wait before claiming another invite code';
    END IF;

    -- Record attempt BEFORE calling claim — prevents brute-force even on failures
    INSERT INTO public.user_action_events (user_id, action_type)
    VALUES (v_user_id, 'invite_claim');

    v_result := public._claim_invite_code_for_user(p_code, v_user_id);

    IF v_result IS NOT NULL THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;


-- ==========================================
-- FIX 8 [MEDIUM]: admin_create_achievement — validate rarity and points
-- ==========================================
-- BUG: The function (010-admin-extensions.sql) accepted any string for
-- rarity and any integer for points, including negative values and
-- invalid rarity strings that don't match the achievements table CHECK.
--
-- FIX: Validate rarity IN ('common','rare','unique','limited') and points >= 0.

CREATE OR REPLACE FUNCTION public.admin_create_achievement(p_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id TEXT;
    v_rarity TEXT;
    v_points INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()) THEN
        RETURN NULL;
    END IF;

    v_rarity := COALESCE(p_data->>'rarity', 'common');
    v_points := COALESCE((p_data->>'points')::INTEGER, 10);

    -- Validate rarity
    IF v_rarity NOT IN ('common', 'rare', 'unique', 'limited') THEN
        RETURN NULL;
    END IF;

    -- Validate points (non-negative)
    IF v_points < 0 THEN
        RETURN NULL;
    END IF;

    INSERT INTO public.achievements (id, title, description, icon_emoji, rarity, points)
    VALUES (
        p_data->>'id',
        p_data->>'title',
        COALESCE(p_data->>'description', ''),
        COALESCE(p_data->>'icon_emoji', '🏆'),
        v_rarity,
        v_points
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;


-- ==========================================
-- FIX 9 [MEDIUM]: admin_create_announcement — validate title length
-- ==========================================
-- BUG: The function (010-admin-extensions.sql) did not validate the title
-- length. An admin could create an announcement with an empty title or
-- an excessively long one.
--
-- FIX: Validate length(p_title) is between 1 and 200 characters.

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

    -- Validate title length: 1-200 characters
    IF length(COALESCE(p_title, '')) < 1 OR length(COALESCE(p_title, '')) > 200 THEN
        RETURN NULL;
    END IF;

    INSERT INTO public.announcements (title, body, created_by)
    VALUES (p_title, p_body, auth.uid())
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;


-- Reload PostgREST schema cache so new function signatures are picked up
NOTIFY pgrst, 'reload schema';

COMMIT;
