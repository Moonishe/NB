-- ============================================
-- BUNDLE 6B: CANONICAL SECURITY HARDENING
-- Run LAST, after 06a
-- ============================================


-- --- fix_live_security_hardening.sql ---

-- Canonical backend hardening for invite codes, profile writes, and achievements.
-- This file is intended to replace older overlapping SQL definitions with one
-- auditable migration. Review before applying in any live environment.

BEGIN;

-- pgcrypto is required for gen_random_bytes().
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
SET LOCAL search_path = public, extensions;

-- Keep core tables on RLS even if older migrations were applied out of order.
ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS bio TEXT,
    ADD COLUMN IF NOT EXISTS pending_invite_code TEXT,
    ADD COLUMN IF NOT EXISTS used_invite_code_id UUID REFERENCES public.invite_codes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS has_generated_invite BOOLEAN,
    ADD COLUMN IF NOT EXISTS generated_invite_code_id UUID REFERENCES public.invite_codes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS telegram_id TEXT,
    ADD COLUMN IF NOT EXISTS telegram_username TEXT,
    ADD COLUMN IF NOT EXISTS telegram_first_name TEXT,
    ADD COLUMN IF NOT EXISTS telegram_last_name TEXT,
    ADD COLUMN IF NOT EXISTS telegram_photo_url TEXT,
    ADD COLUMN IF NOT EXISTS role TEXT,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.profiles
    ALTER COLUMN role SET DEFAULT 'member',
    ALTER COLUMN has_generated_invite SET DEFAULT false;

UPDATE public.profiles
SET role = 'member'
WHERE role IS NULL;

UPDATE public.profiles
SET has_generated_invite = false
WHERE has_generated_invite IS NULL;

-- Ensure invite tables have the columns needed by the hardened functions.
ALTER TABLE public.invite_codes
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS is_admin_code BOOLEAN,
    ADD COLUMN IF NOT EXISTS used_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS used_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS max_uses INTEGER,
    ADD COLUMN IF NOT EXISTS use_count INTEGER,
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

ALTER TABLE public.invite_codes
    ALTER COLUMN is_admin_code SET DEFAULT false,
    ALTER COLUMN created_at SET DEFAULT now(),
    ALTER COLUMN max_uses SET DEFAULT 1,
    ALTER COLUMN use_count SET DEFAULT 0;

UPDATE public.invite_codes
SET use_count = 0
WHERE use_count IS NULL;

UPDATE public.invite_codes
SET max_uses = 1
WHERE is_admin_code = false
  AND max_uses IS NULL;

UPDATE public.invite_codes
SET use_count = 1
WHERE used_by IS NOT NULL
  AND COALESCE(use_count, 0) = 0;

-- The invite claim/generation functions expect code lookups to resolve to a
-- single row. Older local states can contain duplicates if partial migrations
-- were run, so rewrite duplicate historical codes before enforcing uniqueness.
DO $$
DECLARE
    v_row RECORD;
    v_new_code TEXT;
BEGIN
    FOR v_row IN
        SELECT id
        FROM (
            SELECT
                id,
                ROW_NUMBER() OVER (
                    PARTITION BY code
                    ORDER BY
                        CASE WHEN COALESCE(use_count, 0) > 0 THEN 1 ELSE 0 END DESC,
                        created_at DESC NULLS LAST,
                        id DESC
                ) AS row_num
            FROM public.invite_codes
            WHERE code IS NOT NULL
        ) AS ranked_codes
        WHERE row_num > 1
    LOOP
        LOOP
            v_new_code := upper(encode(gen_random_bytes(6), 'hex'));

            EXIT WHEN NOT EXISTS (
                SELECT 1
                FROM public.invite_codes
                WHERE code = v_new_code
            );
        END LOOP;

        UPDATE public.invite_codes
        SET code = v_new_code
        WHERE id = v_row.id;
    END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_codes_code_unique
    ON public.invite_codes(code);

-- Ensure each user/code pair is tracked once so claim operations stay idempotent.
CREATE TABLE IF NOT EXISTS public.invite_code_uses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    invite_code_id UUID REFERENCES public.invite_codes(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    used_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.invite_code_uses ENABLE ROW LEVEL SECURITY;

WITH ranked_uses AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY invite_code_id, user_id
            ORDER BY used_at ASC, id ASC
        ) AS row_num
    FROM public.invite_code_uses
    WHERE invite_code_id IS NOT NULL
      AND user_id IS NOT NULL
)
DELETE FROM public.invite_code_uses AS icu
USING ranked_uses AS ru
WHERE icu.id = ru.id
  AND ru.row_num > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_code_uses_invite_user_unique
    ON public.invite_code_uses(invite_code_id, user_id);

-- ============================================================
-- Table grants and policies
-- ============================================================

-- invite_codes must not be directly readable or mutable by anon/authenticated.
REVOKE ALL ON TABLE public.invite_codes FROM PUBLIC;
REVOKE ALL ON TABLE public.invite_codes FROM anon;
REVOKE ALL ON TABLE public.invite_codes FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.invite_codes TO service_role;

DROP POLICY IF EXISTS "read_unused_codes" ON public.invite_codes;
DROP POLICY IF EXISTS "read_own_codes" ON public.invite_codes;
DROP POLICY IF EXISTS "admin_read_codes" ON public.invite_codes;
DROP POLICY IF EXISTS "admin_insert_codes" ON public.invite_codes;
DROP POLICY IF EXISTS "user_insert_own_invite" ON public.invite_codes;
DROP POLICY IF EXISTS "admin_update_codes" ON public.invite_codes;
DROP POLICY IF EXISTS "admin_delete_codes" ON public.invite_codes;
DROP POLICY IF EXISTS "service_manage_invite_codes" ON public.invite_codes;

CREATE POLICY "service_manage_invite_codes" ON public.invite_codes
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- user_achievements remain readable, but direct client writes are removed.
-- The current live project may not have the achievements schema yet, so keep
-- this block conditional while still hardening databases where it exists.
DO $$
BEGIN
    IF to_regclass('public.user_achievements') IS NOT NULL THEN
        ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.user_achievements FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.user_achievements FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.user_achievements FROM authenticated;
        GRANT SELECT ON TABLE public.user_achievements TO anon;
        GRANT SELECT ON TABLE public.user_achievements TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_achievements TO service_role;

        DROP POLICY IF EXISTS "user_manage_own_achievements" ON public.user_achievements;
        DROP POLICY IF EXISTS "public_read_user_achievements" ON public.user_achievements;
        DROP POLICY IF EXISTS "service_manage_user_achievements" ON public.user_achievements;

        CREATE POLICY "public_read_user_achievements" ON public.user_achievements
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_user_achievements" ON public.user_achievements;
        CREATE POLICY "service_manage_user_achievements" ON public.user_achievements
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END;
$$;

-- Showcase updates stay possible only through a trusted RPC that verifies every
-- requested achievement belongs to the current user.
DROP FUNCTION IF EXISTS public.set_showcased_achievements(TEXT);
CREATE OR REPLACE FUNCTION public.set_showcased_achievements(p_achievement_ids TEXT[])
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ids TEXT[];
    v_requested_count INTEGER;
    v_owned_count INTEGER;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF to_regclass('public.user_achievements') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'achievements_unavailable');
    END IF;

    SELECT COALESCE(array_agg(DISTINCT requested.id), ARRAY[]::TEXT[])
    INTO v_ids
    FROM unnest(COALESCE(p_achievement_ids, ARRAY[]::TEXT[])) AS requested(id)
    WHERE btrim(requested.id) <> '';

    v_requested_count := COALESCE(array_length(v_ids, 1), 0);

    IF v_requested_count > 3 THEN
        RAISE EXCEPTION 'Maximum 3 showcased achievements allowed';
    END IF;

    IF v_requested_count > 0 THEN
        EXECUTE 'SELECT COUNT(*) FROM public.user_achievements WHERE user_id = $1 AND achievement_id = ANY($2)'
        INTO v_owned_count
        USING v_uid, v_ids;

        IF v_owned_count <> v_requested_count THEN
            RAISE EXCEPTION 'One or more achievements are not owned by user';
        END IF;
    END IF;

    EXECUTE 'UPDATE public.user_achievements SET is_showcased = false WHERE user_id = $1 AND is_showcased IS DISTINCT FROM false'
    USING v_uid;

    IF v_requested_count > 0 THEN
        EXECUTE 'UPDATE public.user_achievements SET is_showcased = true WHERE user_id = $1 AND achievement_id = ANY($2)'
        USING v_uid, v_ids;
    END IF;

    RETURN jsonb_build_object('ok', true, 'showcased', to_jsonb(v_ids));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_showcased_achievements(TEXT[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_showcased_achievements(TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_showcased_achievements(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_showcased_achievements(TEXT[]) TO service_role;

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

    SELECT *
    INTO v_profile
    FROM public.profiles
    WHERE user_id = p_user_id;

    IF v_profile IS NULL THEN
        RETURN jsonb_build_object('granted', '[]'::jsonb);
    END IF;

    SELECT (public.grant_achievement(p_user_id, 'welcome')->>'granted')::BOOLEAN INTO v_result;
    IF v_result THEN v_granted := array_append(v_granted, 'welcome'); END IF;

    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 10 THEN
        SELECT (public.grant_achievement(p_user_id, 'first_among_equals')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_among_equals'); END IF;
    END IF;

    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 100 THEN
        SELECT (public.grant_achievement(p_user_id, 'the_first_hundred')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'the_first_hundred'); END IF;
    END IF;

    IF v_profile.created_at IS NOT NULL AND v_profile.created_at < TIMESTAMPTZ '2026-02-19 00:00:00+00' THEN
        SELECT (public.grant_achievement(p_user_id, 'before_public_launch')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'before_public_launch'); END IF;
    END IF;

    IF v_profile.role = 'alpha' THEN
        SELECT (public.grant_achievement(p_user_id, 'alpha_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'alpha_user'); END IF;
    END IF;

    IF v_profile.role = 'beta' THEN
        SELECT (public.grant_achievement(p_user_id, 'beta_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'beta_user'); END IF;
    END IF;

    IF v_profile.role IN ('moderator', 'stmoderator', 'admin') THEN
        SELECT (public.grant_achievement(p_user_id, 'moderator_power')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'moderator_power'); END IF;
    END IF;

    SELECT COUNT(*)
    INTO v_referral_count
    FROM public.invite_code_uses AS icu
    JOIN public.invite_codes AS ic
      ON ic.id = icu.invite_code_id
    WHERE ic.created_by = p_user_id;

    IF v_referral_count >= 1 THEN
        SELECT (public.grant_achievement(p_user_id, 'first_referral')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_referral'); END IF;
    END IF;

    IF v_referral_count >= 3 THEN
        SELECT (public.grant_achievement(p_user_id, 'binding_layer')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'binding_layer'); END IF;
    END IF;

    IF v_referral_count >= 10 THEN
        SELECT (public.grant_achievement(p_user_id, 'cluster_formed')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'cluster_formed'); END IF;
    END IF;

    IF v_profile.created_at IS NOT NULL THEN
        v_days_since_reg := EXTRACT(DAY FROM now() - v_profile.created_at);
        IF v_days_since_reg >= 30 THEN
            SELECT EXISTS(
                SELECT 1
                FROM public.forum_posts
                WHERE author_id = p_user_id
                  AND is_deleted = false
            ) INTO v_has_posts;

            IF NOT v_has_posts THEN
                SELECT (public.grant_achievement(p_user_id, 'silent_observer')->>'granted')::BOOLEAN INTO v_result;
                IF v_result THEN v_granted := array_append(v_granted, 'silent_observer'); END IF;
            END IF;
        END IF;
    END IF;

    IF (v_profile.bio IS NOT NULL AND v_profile.bio <> '')
       OR (v_profile.telegram_photo_url IS NOT NULL AND v_profile.telegram_photo_url <> '') THEN
        SELECT (public.grant_achievement(p_user_id, 'profile_tuned')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'profile_tuned'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM public.post_reactions WHERE user_id = p_user_id LIMIT 1) THEN
        SELECT (public.grant_achievement(p_user_id, 'first_reaction')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_reaction'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM public.login_streaks WHERE user_id = p_user_id AND current_streak >= 3) THEN
        SELECT (public.grant_achievement(p_user_id, 'daily_login')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'daily_login'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM public.forum_threads WHERE author_id = p_user_id AND is_deleted = false LIMIT 1) THEN
        SELECT (public.grant_achievement(p_user_id, 'first_thread')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_thread'); END IF;
    END IF;

    IF EXISTS(
        SELECT 1
        FROM public.forum_posts AS fp
        JOIN public.forum_threads AS ft
          ON ft.id = fp.thread_id
        WHERE fp.author_id = p_user_id
          AND fp.is_deleted = false
          AND ft.author_id != p_user_id
        LIMIT 1
    ) THEN
        SELECT (public.grant_achievement(p_user_id, 'first_comment')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_comment'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM public.results WHERE author = p_user_id::text LIMIT 1) THEN
        SELECT (public.grant_achievement(p_user_id, 'first_model_rate')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_model_rate'); END IF;
    END IF;

    IF EXISTS(
        SELECT 1
        FROM public.forum_posts
        WHERE author_id = p_user_id
          AND is_deleted = false
          AND content LIKE '%@%'
        LIMIT 1
    ) THEN
        SELECT (public.grant_achievement(p_user_id, 'first_mention')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_mention'); END IF;
    END IF;

    IF EXISTS(
        SELECT 1
        FROM public.forum_posts
        WHERE author_id = p_user_id
          AND is_deleted = false
          AND edited_at IS NOT NULL
        LIMIT 1
    ) THEN
        SELECT (public.grant_achievement(p_user_id, 'first_edit')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_edit'); END IF;
    END IF;

    IF EXISTS(SELECT 1 FROM public.login_streaks WHERE user_id = p_user_id AND current_streak >= 7) THEN
        SELECT (public.grant_achievement(p_user_id, 'seven_day_streak')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'seven_day_streak'); END IF;
    END IF;

    IF EXISTS(
        SELECT 1
        FROM public.forum_posts
        WHERE author_id = p_user_id
          AND is_deleted = false
          AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') >= 2
          AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') < 5
        LIMIT 1
    ) THEN
        SELECT (public.grant_achievement(p_user_id, 'night_shift')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'night_shift'); END IF;
    END IF;

    IF EXISTS(
        SELECT 1
        FROM public.forum_posts AS fp
        JOIN public.forum_threads AS ft
          ON ft.id = fp.thread_id
        WHERE fp.author_id = p_user_id
          AND fp.is_deleted = false
          AND ft.created_at < fp.created_at - interval '90 days'
        LIMIT 1
    ) THEN
        SELECT (public.grant_achievement(p_user_id, 'archaeologist')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'archaeologist'); END IF;
    END IF;

    IF (SELECT COUNT(*) FROM public.forum_posts WHERE author_id = p_user_id AND is_deleted = false) >= 100 THEN
        SELECT (public.grant_achievement(p_user_id, 'overfitting')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'overfitting'); END IF;
    END IF;

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) TO service_role;

DO $$
BEGIN
    IF to_regprocedure('public.grant_achievement(uuid,text)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.grant_achievement(UUID, TEXT) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.grant_achievement(UUID, TEXT) FROM anon';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.grant_achievement(UUID, TEXT) FROM authenticated';
    END IF;

    IF to_regprocedure('public.check_reaction_achievements(integer,uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM anon';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM authenticated';
    END IF;

    IF to_regprocedure('public.check_pin_achievement(integer)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM anon';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM authenticated';
    END IF;

    IF to_regprocedure('public.check_and_grant_achievements(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) TO authenticated';
    END IF;
END;
$$;

-- Profiles stay readable through existing select policies, but all client
-- writes flow through trusted SQL functions or service/admin paths.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.profiles FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.profiles FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.profiles FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.profiles TO service_role;

DROP POLICY IF EXISTS "fn_manage_profiles" ON public.profiles;
DROP POLICY IF EXISTS "service_manage_profiles" ON public.profiles;
DROP POLICY IF EXISTS "user_update_own_profile_bio_only" ON public.profiles;

CREATE POLICY "service_manage_profiles" ON public.profiles
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);

-- Canonical role quota helper used by invite generation.
DROP FUNCTION IF EXISTS public.get_invite_max(TEXT);
CREATE OR REPLACE FUNCTION public.get_invite_max(p_role TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN CASE COALESCE(p_role, 'member')
        WHEN 'admin' THEN 999999
        WHEN 'stmoderator' THEN 999999
        WHEN 'moderator' THEN 999999
        WHEN 'alpha' THEN 10
        WHEN 'beta' THEN 3
        ELSE 1
    END;
END;
$$;

-- ============================================================
-- Canonical invite claim logic
-- ============================================================

-- Private helper used by both user-facing and admin/service claim flows.
-- It locks the target profile row to make same-user retries idempotent, checks
-- whether the user already used the same code, then claims the code with a row
-- lock so concurrent multi-use claims serialize instead of returning false.
DROP FUNCTION IF EXISTS public._claim_invite_code_for_user(TEXT, UUID) CASCADE;
CREATE OR REPLACE FUNCTION public._claim_invite_code_for_user(
    p_code TEXT,
    p_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile public.profiles%ROWTYPE;
    v_code TEXT;
    v_existing_invite_id UUID;
    v_invite public.invite_codes%ROWTYPE;
    v_claimed_at TIMESTAMPTZ := now();
BEGIN
    IF p_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT *
    INTO v_profile
    FROM public.profiles
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_code := upper(btrim(COALESCE(p_code, '')));
    IF v_code = '' THEN
        v_code := upper(btrim(COALESCE(v_profile.pending_invite_code, '')));
    END IF;

    IF v_code = '' THEN
        RETURN NULL;
    END IF;

    -- Idempotent success path: if this user already used this code, keep the
    -- profile in the verified state and do not increment use counters again.
    SELECT icu.invite_code_id
    INTO v_existing_invite_id
    FROM public.invite_code_uses AS icu
    JOIN public.invite_codes AS ic
      ON ic.id = icu.invite_code_id
    WHERE ic.code = v_code
      AND icu.user_id = p_user_id
    ORDER BY icu.used_at DESC, icu.id DESC
    LIMIT 1;

    IF v_existing_invite_id IS NOT NULL THEN
        UPDATE public.profiles
        SET is_verified = true,
            used_invite_code_id = v_existing_invite_id,
            pending_invite_code = NULL
        WHERE user_id = p_user_id
          AND (
              is_verified IS DISTINCT FROM true
              OR used_invite_code_id IS DISTINCT FROM v_existing_invite_id
              OR pending_invite_code IS NOT NULL
          );

        RETURN v_existing_invite_id;
    END IF;

    SELECT *
    INTO v_invite
    FROM public.invite_codes
    WHERE code = v_code
      AND (expires_at IS NULL OR expires_at > now())
      AND (max_uses IS NULL OR COALESCE(use_count, 0) < max_uses)
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Clean up expired unused rows for the same code so stale data does not
        -- keep accumulating even when callers retry old links.
        DELETE FROM public.invite_codes
        WHERE code = v_code
          AND expires_at IS NOT NULL
          AND expires_at <= now()
          AND COALESCE(use_count, 0) = 0;

        RETURN NULL;
    END IF;

    INSERT INTO public.invite_code_uses (invite_code_id, user_id, used_at)
    VALUES (v_invite.id, p_user_id, v_claimed_at)
    ON CONFLICT DO NOTHING;

    IF NOT FOUND THEN
        UPDATE public.profiles
        SET is_verified = true,
            used_invite_code_id = v_invite.id,
            pending_invite_code = NULL
        WHERE user_id = p_user_id
          AND (
              is_verified IS DISTINCT FROM true
              OR used_invite_code_id IS DISTINCT FROM v_invite.id
              OR pending_invite_code IS NOT NULL
          );

        RETURN v_invite.id;
    END IF;

    UPDATE public.invite_codes
    SET use_count = COALESCE(use_count, 0) + 1,
        used_by = CASE
            WHEN max_uses IS NOT NULL AND COALESCE(use_count, 0) + 1 >= max_uses
                THEN p_user_id
            ELSE used_by
        END,
        used_at = CASE
            WHEN max_uses IS NOT NULL AND COALESCE(use_count, 0) + 1 >= max_uses
                THEN v_claimed_at
            ELSE used_at
        END
    WHERE id = v_invite.id;

    UPDATE public.profiles
    SET is_verified = true,
        used_invite_code_id = v_invite.id,
        pending_invite_code = NULL
    WHERE user_id = p_user_id;

    RETURN v_invite.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._claim_invite_code_for_user(TEXT, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._claim_invite_code_for_user(TEXT, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public._claim_invite_code_for_user(TEXT, UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public._claim_invite_code_for_user(TEXT, UUID) FROM service_role;

DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT);
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN public._claim_invite_code_for_user(p_code, v_user_id) IS NOT NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_invite_code(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_invite_code(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.claim_invite_code(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_invite_code(TEXT) TO service_role;

-- Admin/service claim stays available for trusted server flows only.
DROP FUNCTION IF EXISTS public.admin_claim_invite_for_user(TEXT, UUID) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_claim_invite_for_user(
    p_code TEXT,
    p_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1
           FROM public.admin_users
           WHERE user_id = auth.uid()
       ) THEN
        RETURN NULL;
    END IF;

    RETURN public._claim_invite_code_for_user(p_code, p_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_claim_invite_for_user(TEXT, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_claim_invite_for_user(TEXT, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_claim_invite_for_user(TEXT, UUID) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_claim_invite_for_user(TEXT, UUID) TO service_role;

-- ============================================================
-- Canonical invite generation logic
-- ============================================================

DROP FUNCTION IF EXISTS public.generate_user_invite_code();
CREATE OR REPLACE FUNCTION public.generate_user_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_role TEXT;
    v_max INTEGER;
    v_active_count INTEGER;
    v_oldest_unused_id UUID;
    v_new_code TEXT;
    v_invite_id UUID;
    v_attempt INTEGER := 0;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Serialize invite generation per user so concurrent requests cannot race.
    PERFORM pg_advisory_xact_lock(
        hashtext('public.generate_user_invite_code'),
        hashtext(v_user_id::text)
    );

    SELECT p.role
    INTO v_role
    FROM public.profiles AS p
    WHERE p.user_id = v_user_id
      AND p.is_verified = true
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Remove stale unused invites first so quota checks only count live rows.
    DELETE FROM public.invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND expires_at IS NOT NULL
      AND expires_at <= now()
      AND COALESCE(use_count, 0) = 0;

    UPDATE public.profiles
    SET generated_invite_code_id = (
            SELECT ic.id
            FROM public.invite_codes AS ic
            WHERE ic.created_by = v_user_id
              AND ic.is_admin_code = false
              AND (ic.expires_at IS NULL OR ic.expires_at > now())
              AND (ic.max_uses IS NULL OR COALESCE(ic.use_count, 0) < ic.max_uses)
            ORDER BY ic.created_at DESC, ic.id DESC
            LIMIT 1
        ),
        has_generated_invite = EXISTS (
            SELECT 1
            FROM public.invite_codes AS ic
            WHERE ic.created_by = v_user_id
              AND ic.is_admin_code = false
              AND (ic.expires_at IS NULL OR ic.expires_at > now())
              AND (ic.max_uses IS NULL OR COALESCE(ic.use_count, 0) < ic.max_uses)
        )
    WHERE user_id = v_user_id;

    v_max := COALESCE(public.get_invite_max(v_role), 1);

    SELECT COUNT(*)
    INTO v_active_count
    FROM public.invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND (expires_at IS NULL OR expires_at > now())
      AND (max_uses IS NULL OR COALESCE(use_count, 0) < max_uses);

    IF v_active_count >= v_max THEN
        -- Preserve partially used codes; only rotate out an unused one.
        SELECT id
        INTO v_oldest_unused_id
        FROM public.invite_codes
        WHERE created_by = v_user_id
          AND is_admin_code = false
          AND COALESCE(use_count, 0) = 0
          AND (expires_at IS NULL OR expires_at > now())
        ORDER BY created_at ASC, id ASC
        LIMIT 1
        FOR UPDATE SKIP LOCKED;

        IF v_oldest_unused_id IS NULL THEN
            RETURN NULL;
        END IF;

        DELETE FROM public.invite_codes
        WHERE id = v_oldest_unused_id;
    END IF;

    LOOP
        v_attempt := v_attempt + 1;
        v_new_code := upper(encode(gen_random_bytes(6), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (
                code,
                created_by,
                is_admin_code,
                max_uses,
                use_count,
                expires_at
            )
            VALUES (
                v_new_code,
                v_user_id,
                false,
                1,
                0,
                now() + interval '5 minutes'
            )
            RETURNING id INTO v_invite_id;

            EXIT;
        EXCEPTION
            WHEN unique_violation THEN
                IF v_attempt >= 8 THEN
                    RAISE EXCEPTION 'failed to generate a unique invite code after % attempts', v_attempt;
                END IF;
        END;
    END LOOP;

    UPDATE public.profiles
    SET has_generated_invite = true,
        generated_invite_code_id = v_invite_id
    WHERE user_id = v_user_id;

    RETURN v_new_code;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.generate_user_invite_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.generate_user_invite_code() FROM anon;
GRANT EXECUTE ON FUNCTION public.generate_user_invite_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_user_invite_code() TO service_role;

DROP FUNCTION IF EXISTS public.admin_generate_invite_for_user(UUID, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_generate_invite_for_user(
    p_user_id UUID,
    p_max_uses INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_code TEXT;
    v_invite_id UUID;
    v_max_uses INT;
    v_attempt INTEGER := 0;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1
           FROM public.admin_users
           WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF p_user_id IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM public.profiles
           WHERE user_id = p_user_id
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    v_max_uses := LEAST(100, GREATEST(1, COALESCE(p_max_uses, 1)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(6), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (
                code,
                is_admin_code,
                max_uses,
                use_count,
                created_by
            )
            VALUES (
                v_code,
                true,
                v_max_uses,
                0,
                auth.uid()
            )
            RETURNING id INTO v_invite_id;

            EXIT;
        EXCEPTION
            WHEN unique_violation THEN
                IF v_attempt >= 8 THEN
                    RAISE EXCEPTION 'failed to generate a unique admin invite code after % attempts', v_attempt;
                END IF;
        END;
    END LOOP;

    UPDATE public.profiles
    SET has_generated_invite = true,
        generated_invite_code_id = v_invite_id
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object(
        'ok', true,
        'code', v_code,
        'invite_id', v_invite_id,
        'max_uses', v_max_uses
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INT) TO service_role;

-- Preserve bio updates through the sanctioned RPC instead of broad table writes.
DROP FUNCTION IF EXISTS public.update_profile_bio(TEXT);
CREATE OR REPLACE FUNCTION public.update_profile_bio(p_bio TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;

    IF length(COALESCE(p_bio, '')) > 500 THEN
        RAISE EXCEPTION 'Bio must be at most 500 characters';
    END IF;

    UPDATE public.profiles
    SET bio = COALESCE(p_bio, '')
    WHERE user_id = auth.uid();

    RETURN FOUND;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_profile_bio(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_profile_bio(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_profile_bio(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_profile_bio(TEXT) TO service_role;

-- ============================================================
-- DB-level profile photo hardening
-- ============================================================

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_telegram_photo_url_safe;

DROP FUNCTION IF EXISTS public.normalize_telegram_photo_url(TEXT);
CREATE OR REPLACE FUNCTION public.normalize_telegram_photo_url(p_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_value TEXT := NULLIF(btrim(COALESCE(p_value, '')), '');
BEGIN
    IF v_value IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_value ~ '^/i/userpic/[^[:space:]]+$' THEN
        RETURN v_value;
    END IF;

    IF v_value ~* '^https://([a-z0-9-]+\.)*t\.me(/[^[:space:]]*)?$'
       OR v_value ~* '^https://([a-z0-9-]+\.)*telegram\.org(/[^[:space:]]*)?$' THEN
        RETURN v_value;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_normalize_profiles_telegram_photo_url()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.telegram_photo_url := public.normalize_telegram_photo_url(NEW.telegram_photo_url);
    RETURN NEW;
END;
$$;

UPDATE public.profiles
SET telegram_photo_url = public.normalize_telegram_photo_url(telegram_photo_url)
WHERE telegram_photo_url IS DISTINCT FROM public.normalize_telegram_photo_url(telegram_photo_url);

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_telegram_photo_url_safe;

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_telegram_photo_url_safe
    CHECK (
        telegram_photo_url IS NULL
        OR telegram_photo_url = public.normalize_telegram_photo_url(telegram_photo_url)
    );

DROP TRIGGER IF EXISTS trg_normalize_profiles_telegram_photo_url ON public.profiles;
CREATE TRIGGER trg_normalize_profiles_telegram_photo_url
BEFORE INSERT OR UPDATE OF telegram_photo_url ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.trg_normalize_profiles_telegram_photo_url();

REVOKE EXECUTE ON FUNCTION public.normalize_telegram_photo_url(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.normalize_telegram_photo_url(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.normalize_telegram_photo_url(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.normalize_telegram_photo_url(TEXT) FROM service_role;

REVOKE EXECUTE ON FUNCTION public.trg_normalize_profiles_telegram_photo_url() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_normalize_profiles_telegram_photo_url() FROM anon;
REVOKE EXECUTE ON FUNCTION public.trg_normalize_profiles_telegram_photo_url() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_normalize_profiles_telegram_photo_url() FROM service_role;

-- ============================================================
-- Canonical forum and result abuse hardening
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_action_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    target_id INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.user_action_events
    ADD COLUMN IF NOT EXISTS target_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_user_action_events_user_action_created
    ON public.user_action_events(user_id, action_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_action_events_user_action_target_created
    ON public.user_action_events(user_id, action_type, target_id, created_at DESC);

ALTER TABLE public.user_action_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_user_action_events" ON public.user_action_events;
CREATE POLICY "deny_direct_user_action_events" ON public.user_action_events
    FOR ALL USING (false) WITH CHECK (false);

DO $$
BEGIN
    IF to_regclass('public.forum_threads') IS NOT NULL THEN
        ALTER TABLE public.forum_threads ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.forum_threads FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.forum_threads FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.forum_threads FROM authenticated;
        GRANT SELECT ON TABLE public.forum_threads TO anon;
        GRANT SELECT ON TABLE public.forum_threads TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.forum_threads TO service_role;

        DROP POLICY IF EXISTS "public_read_forum_threads" ON public.forum_threads;
        DROP POLICY IF EXISTS "verified_insert_forum_threads" ON public.forum_threads;
        DROP POLICY IF EXISTS "author_mod_update_forum_threads" ON public.forum_threads;
        DROP POLICY IF EXISTS "mod_admin_delete_forum_threads" ON public.forum_threads;
        DROP POLICY IF EXISTS "service_manage_forum_threads" ON public.forum_threads;

DROP POLICY IF EXISTS "public_read_forum_threads" ON public.forum_threads;
        CREATE POLICY "public_read_forum_threads" ON public.forum_threads
            FOR SELECT
            USING (
                is_deleted = false
                OR EXISTS (
                    SELECT 1
                    FROM public.moderators
                    WHERE user_id = auth.uid()
                )
                OR EXISTS (
                    SELECT 1
                    FROM public.admin_users
                    WHERE user_id = auth.uid()
                )
            );

DROP POLICY IF EXISTS "service_manage_forum_threads" ON public.forum_threads;
        CREATE POLICY "service_manage_forum_threads" ON public.forum_threads
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.forum_posts') IS NOT NULL THEN
        ALTER TABLE public.forum_posts ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.forum_posts FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.forum_posts FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.forum_posts FROM authenticated;
        GRANT SELECT ON TABLE public.forum_posts TO anon;
        GRANT SELECT ON TABLE public.forum_posts TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.forum_posts TO service_role;

        DROP POLICY IF EXISTS "public_read_forum_posts" ON public.forum_posts;
        DROP POLICY IF EXISTS "verified_insert_forum_posts" ON public.forum_posts;
        DROP POLICY IF EXISTS "author_mod_update_forum_posts" ON public.forum_posts;
        DROP POLICY IF EXISTS "mod_admin_delete_forum_posts" ON public.forum_posts;
        DROP POLICY IF EXISTS "service_manage_forum_posts" ON public.forum_posts;

DROP POLICY IF EXISTS "public_read_forum_posts" ON public.forum_posts;
        CREATE POLICY "public_read_forum_posts" ON public.forum_posts
            FOR SELECT
            USING (
                is_deleted = false
                OR EXISTS (
                    SELECT 1
                    FROM public.moderators
                    WHERE user_id = auth.uid()
                )
                OR EXISTS (
                    SELECT 1
                    FROM public.admin_users
                    WHERE user_id = auth.uid()
                )
            );

DROP POLICY IF EXISTS "service_manage_forum_posts" ON public.forum_posts;
        CREATE POLICY "service_manage_forum_posts" ON public.forum_posts
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.post_reactions') IS NOT NULL THEN
        ALTER TABLE public.post_reactions ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.post_reactions FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.post_reactions FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.post_reactions FROM authenticated;
        GRANT SELECT ON TABLE public.post_reactions TO anon;
        GRANT SELECT ON TABLE public.post_reactions TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.post_reactions TO service_role;

        ALTER TABLE public.post_reactions
            DROP CONSTRAINT IF EXISTS post_reactions_emoji_check;
        ALTER TABLE public.post_reactions
            DROP CONSTRAINT IF EXISTS post_reactions_emoji_safe;
        ALTER TABLE public.post_reactions
            ADD CONSTRAINT post_reactions_emoji_safe
            CHECK (emoji IN ('like', 'dislike', 'fire', 'puke', 'brain', 'emotion', 'admin_like'));

        DROP POLICY IF EXISTS "public_read_post_reactions" ON public.post_reactions;
        DROP POLICY IF EXISTS "user_manage_own_reactions" ON public.post_reactions;
        DROP POLICY IF EXISTS "service_manage_post_reactions" ON public.post_reactions;

DROP POLICY IF EXISTS "public_read_post_reactions" ON public.post_reactions;
        CREATE POLICY "public_read_post_reactions" ON public.post_reactions
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_post_reactions" ON public.post_reactions;
        CREATE POLICY "service_manage_post_reactions" ON public.post_reactions
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.create_forum_thread(INTEGER, TEXT, TEXT) CASCADE;
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
    v_user_id UUID := auth.uid();
    v_id INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE user_id = v_user_id
          AND is_verified = true
    ) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_mod_actions
        WHERE user_id = v_user_id
          AND action_type IN ('ban', 'mute')
          AND is_active = true
          AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'User is restricted';
    END IF;

    IF length(COALESCE(p_title, '')) < 3 OR length(COALESCE(p_title, '')) > 200 THEN
        RAISE EXCEPTION 'Title must be 3-200 characters';
    END IF;

    IF length(COALESCE(p_content, '')) < 1 OR length(COALESCE(p_content, '')) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext('public.create_forum_thread'),
        hashtext(v_user_id::text)
    );

    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_thread_create'
          AND created_at > now() - interval '30 seconds'
    ) THEN
        RAISE EXCEPTION 'Too fast. Wait before creating another thread.';
    END IF;

    INSERT INTO public.forum_threads (
        category_id,
        author_id,
        title,
        content,
        last_post_at
    )
    VALUES (
        p_category_id,
        v_user_id,
        p_title,
        p_content,
        now()
    )
    RETURNING id INTO v_id;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'forum_thread_create', v_id);

    RETURN v_id;
END;
$$;

DROP FUNCTION IF EXISTS public.create_forum_post(INTEGER, TEXT) CASCADE;
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
    v_user_id UUID := auth.uid();
    v_id INTEGER;
    v_thread_author UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE user_id = v_user_id
          AND is_verified = true
    ) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_mod_actions
        WHERE user_id = v_user_id
          AND action_type IN ('ban', 'mute')
          AND is_active = true
          AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'User is restricted';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.forum_threads
        WHERE id = p_thread_id
          AND is_locked = false
          AND is_deleted = false
    ) THEN
        RAISE EXCEPTION 'Thread is locked or deleted';
    END IF;

    IF length(COALESCE(p_content, '')) < 1 OR length(COALESCE(p_content, '')) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext('public.create_forum_post'),
        hashtext(v_user_id::text)
    );

    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_post_create'
          AND created_at > now() - interval '10 seconds'
    ) THEN
        RAISE EXCEPTION 'Too fast. Wait a few seconds.';
    END IF;

    INSERT INTO public.forum_posts (thread_id, author_id, content)
    VALUES (p_thread_id, v_user_id, p_content)
    RETURNING id INTO v_id;

    UPDATE public.forum_threads
    SET posts_count = posts_count + 1,
        last_post_at = now(),
        last_post_by = v_user_id,
        updated_at = now()
    WHERE id = p_thread_id;

    SELECT author_id
    INTO v_thread_author
    FROM public.forum_threads
    WHERE id = p_thread_id;

    IF v_thread_author IS NOT NULL AND v_thread_author != v_user_id THEN
        INSERT INTO public.notifications (
            user_id,
            type,
            from_user_id,
            ref_thread_id,
            ref_post_id,
            snippet
        )
        VALUES (
            v_thread_author,
            'reply',
            v_user_id,
            p_thread_id,
            v_id,
            left(p_content, 80)
        );
    END IF;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'forum_post_create', p_thread_id);

    RETURN v_id;
END;
$$;

DROP FUNCTION IF EXISTS public.update_forum_post(INTEGER, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION public.update_forum_post(
    p_post_id INTEGER,
    p_content TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_mod_actions
        WHERE user_id = v_user_id
          AND action_type IN ('ban', 'mute')
          AND is_active = true
          AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'User is restricted';
    END IF;

    IF length(COALESCE(p_content, '')) < 1 OR length(COALESCE(p_content, '')) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext('public.update_forum_post'),
        hashtext(v_user_id::text)
    );

    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_post_edit'
          AND target_id = p_post_id
          AND created_at > now() - interval '5 seconds'
    ) THEN
        RAISE EXCEPTION 'You can edit the same post only once every 5 seconds.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_post_edit'
          AND created_at > now() - interval '1 minute'
    ) >= 20 THEN
        RAISE EXCEPTION 'Too many post edits. Slow down.';
    END IF;

    UPDATE public.forum_posts
    SET content = p_content,
        edited_at = now()
    WHERE id = p_post_id
      AND author_id = v_user_id
      AND is_deleted = false;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'forum_post_edit', p_post_id);

    RETURN true;
END;
$$;

DROP FUNCTION IF EXISTS public.update_forum_thread(INTEGER, TEXT, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION public.update_forum_thread(
    p_thread_id INTEGER,
    p_title TEXT,
    p_content TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_mod_actions
        WHERE user_id = v_user_id
          AND action_type IN ('ban', 'mute')
          AND is_active = true
          AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'User is restricted';
    END IF;

    IF length(COALESCE(p_title, '')) < 3 OR length(COALESCE(p_title, '')) > 200 THEN
        RAISE EXCEPTION 'Title must be 3-200 characters';
    END IF;

    IF length(COALESCE(p_content, '')) < 1 OR length(COALESCE(p_content, '')) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext('public.update_forum_thread'),
        hashtext(v_user_id::text)
    );

    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_thread_edit'
          AND target_id = p_thread_id
          AND created_at > now() - interval '10 seconds'
    ) THEN
        RAISE EXCEPTION 'You can edit the same thread only once every 10 seconds.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_thread_edit'
          AND created_at > now() - interval '1 minute'
    ) >= 10 THEN
        RAISE EXCEPTION 'Too many thread edits. Slow down.';
    END IF;

    UPDATE public.forum_threads
    SET title = p_title,
        content = p_content,
        updated_at = now()
    WHERE id = p_thread_id
      AND author_id = v_user_id
      AND is_deleted = false;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'forum_thread_edit', p_thread_id);

    RETURN true;
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
    v_user_id UUID := auth.uid();
    v_count INTEGER := 0;
    v_mentioned_user_id UUID;
    v_snippet TEXT;
    v_recent_mentions INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN 0;
    END IF;

    IF p_mentioned_user_ids IS NULL OR array_length(p_mentioned_user_ids, 1) IS NULL THEN
        RETURN 0;
    END IF;

    IF array_length(p_mentioned_user_ids, 1) > 10 THEN
        RAISE EXCEPTION 'Too many mentions';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext('public.create_mention_notifications'),
        hashtext(v_user_id::text)
    );

    SELECT COUNT(*)
    INTO v_recent_mentions
    FROM public.user_action_events
    WHERE user_id = v_user_id
      AND action_type = 'forum_mention'
      AND created_at > now() - interval '5 minutes';

    IF v_recent_mentions >= 30 THEN
        RAISE EXCEPTION 'Too many mentions. Slow down.';
    END IF;

    SELECT left(content, 80)
    INTO v_snippet
    FROM public.forum_posts
    WHERE id = p_post_id
      AND thread_id = p_thread_id
      AND author_id = v_user_id
      AND is_deleted = false;

    IF v_snippet IS NULL THEN
        RETURN 0;
    END IF;

    FOREACH v_mentioned_user_id IN ARRAY p_mentioned_user_ids LOOP
        IF v_mentioned_user_id != v_user_id
           AND EXISTS (
               SELECT 1
               FROM public.profiles
               WHERE user_id = v_mentioned_user_id
           )
           AND NOT EXISTS (
               SELECT 1
               FROM public.notifications
               WHERE user_id = v_mentioned_user_id
                 AND type = 'mention'
                 AND from_user_id = v_user_id
                 AND ref_post_id = p_post_id
           ) THEN
            IF v_recent_mentions + v_count >= 30 THEN
                RAISE EXCEPTION 'Too many mentions. Slow down.';
            END IF;

            INSERT INTO public.notifications (
                user_id,
                type,
                from_user_id,
                ref_thread_id,
                ref_post_id,
                snippet
            )
           VALUES (
                v_mentioned_user_id,
                'mention',
                v_user_id,
                p_thread_id,
                p_post_id,
                v_snippet
            );

            INSERT INTO public.user_action_events (user_id, action_type, target_id)
            VALUES (v_user_id, 'forum_mention', p_post_id);

            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;

DROP FUNCTION IF EXISTS public.toggle_post_reaction(INTEGER, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION public.toggle_post_reaction(
    p_post_id INTEGER,
    p_emoji TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_exists BOOLEAN;
    v_post_author UUID;
    v_thread_id INTEGER;
    v_action TEXT;
    v_user_role TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE user_id = v_user_id
          AND is_verified = true
    ) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;

    IF p_emoji = 'admin_like' THEN
        SELECT COALESCE(role, 'member')
        INTO v_user_role
        FROM public.profiles
        WHERE user_id = v_user_id;

        IF v_user_role NOT IN ('admin', 'stmoderator') THEN
            RAISE EXCEPTION 'Admin like is only available to admins';
        END IF;
    END IF;

    IF p_emoji NOT IN ('like', 'dislike', 'fire', 'puke', 'brain', 'emotion', 'admin_like') THEN
        RAISE EXCEPTION 'Invalid emoji';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.forum_posts
        WHERE id = p_post_id
          AND is_deleted = false
    ) THEN
        RAISE EXCEPTION 'Post not found';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtext('public.toggle_post_reaction'),
        hashtext(v_user_id::text)
    );

    IF (
        SELECT COUNT(*)
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'forum_reaction'
          AND created_at > now() - interval '3 seconds'
    ) >= 5 THEN
        RAISE EXCEPTION 'Too many reactions. Slow down.';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.post_reactions
        WHERE post_id = p_post_id
          AND user_id = v_user_id
          AND emoji = p_emoji
    )
    INTO v_exists;

    IF v_exists THEN
        DELETE FROM public.post_reactions
        WHERE post_id = p_post_id
          AND user_id = v_user_id
          AND emoji = p_emoji;

        v_action := 'removed';
    ELSE
        INSERT INTO public.post_reactions (post_id, user_id, emoji)
        VALUES (p_post_id, v_user_id, p_emoji);

        v_action := 'added';

        SELECT author_id, thread_id
        INTO v_post_author, v_thread_id
        FROM public.forum_posts
        WHERE id = p_post_id;

        IF v_post_author IS NOT NULL AND v_post_author != v_user_id THEN
            INSERT INTO public.notifications (
                user_id,
                type,
                from_user_id,
                ref_thread_id,
                ref_post_id,
                emoji,
                snippet
            )
            SELECT
                v_post_author,
                'reaction',
                v_user_id,
                v_thread_id,
                p_post_id,
                p_emoji,
                (SELECT left(content, 80) FROM public.forum_posts WHERE id = p_post_id)
            WHERE NOT EXISTS (
                SELECT 1
                FROM public.notifications
                WHERE user_id = v_post_author
                  AND type = 'reaction'
                  AND from_user_id = v_user_id
                  AND ref_post_id = p_post_id
                  AND emoji = p_emoji
            );
        END IF;

        PERFORM public.check_reaction_achievements(p_post_id, v_user_id);
    END IF;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'forum_reaction', p_post_id);

    RETURN jsonb_build_object('action', v_action, 'emoji', p_emoji);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_forum_thread(INTEGER, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_forum_thread(INTEGER, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_forum_thread(INTEGER, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_forum_thread(INTEGER, TEXT, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.create_forum_post(INTEGER, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_forum_post(INTEGER, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_forum_post(INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_forum_post(INTEGER, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_forum_post(INTEGER, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_forum_post(INTEGER, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_forum_post(INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_forum_post(INTEGER, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.update_forum_thread(INTEGER, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_forum_thread(INTEGER, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_forum_thread(INTEGER, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_forum_thread(INTEGER, TEXT, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.create_mention_notifications(INTEGER, INTEGER, UUID[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_mention_notifications(INTEGER, INTEGER, UUID[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_mention_notifications(INTEGER, INTEGER, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_mention_notifications(INTEGER, INTEGER, UUID[]) TO service_role;

REVOKE EXECUTE ON FUNCTION public.toggle_post_reaction(INTEGER, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.toggle_post_reaction(INTEGER, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.toggle_post_reaction(INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_post_reaction(INTEGER, TEXT) TO service_role;

DO $$
BEGIN
    IF to_regprocedure('public.check_reaction_achievements(integer,uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM anon';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM authenticated';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_reaction_achievements(INTEGER, UUID) FROM service_role';
    END IF;

    IF to_regprocedure('public.check_pin_achievement(integer)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM anon';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM authenticated';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.check_pin_achievement(INTEGER) FROM service_role';
    END IF;

    IF to_regprocedure('public.mod_pin_thread(integer,boolean)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_pin_thread(INTEGER, BOOLEAN) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_pin_thread(INTEGER, BOOLEAN) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_pin_thread(INTEGER, BOOLEAN) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_pin_thread(INTEGER, BOOLEAN) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_lock_thread(integer,boolean)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_lock_thread(INTEGER, BOOLEAN) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_lock_thread(INTEGER, BOOLEAN) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_lock_thread(INTEGER, BOOLEAN) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_lock_thread(INTEGER, BOOLEAN) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_delete_thread(integer)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_delete_thread(INTEGER) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_delete_thread(INTEGER) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_delete_thread(INTEGER) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_delete_thread(INTEGER) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_delete_post(integer)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_delete_post(INTEGER) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_delete_post(INTEGER) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_delete_post(INTEGER) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_delete_post(INTEGER) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_ban_user(uuid,text,timestamp with time zone)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_ban_user(UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_ban_user(UUID, TEXT, TIMESTAMPTZ) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_ban_user(UUID, TEXT, TIMESTAMPTZ) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_ban_user(UUID, TEXT, TIMESTAMPTZ) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_mute_user(uuid,text,timestamp with time zone)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_mute_user(UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_mute_user(UUID, TEXT, TIMESTAMPTZ) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_mute_user(UUID, TEXT, TIMESTAMPTZ) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_mute_user(UUID, TEXT, TIMESTAMPTZ) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_unban_user(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_unban_user(UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_unban_user(UUID) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_unban_user(UUID) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_unban_user(UUID) TO service_role';
    END IF;

    IF to_regprocedure('public.mod_unmute_user(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_unmute_user(UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.mod_unmute_user(UUID) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_unmute_user(UUID) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.mod_unmute_user(UUID) TO service_role';
    END IF;
END;
$$;

-- Older fix files exposed moderator assignment as SECURITY DEFINER without an
-- admin/service-role gate. Keep the one frontend-used signature and replace it
-- with a canonical guarded implementation.
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
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1
           FROM public.admin_users
           WHERE user_id = auth.uid()
       ) THEN
        RETURN false;
    END IF;

    IF p_user_id IS NULL THEN
        RETURN false;
    END IF;

    SELECT telegram_id, telegram_username
    INTO v_tg_id, v_tg_username
    FROM public.profiles
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    INSERT INTO public.moderators (
        user_id,
        telegram_id,
        telegram_username,
        assigned_by
    )
    VALUES (
        p_user_id,
        v_tg_id,
        v_tg_username,
        auth.uid()
    )
    ON CONFLICT (user_id)
    DO UPDATE SET
        telegram_id = EXCLUDED.telegram_id,
        telegram_username = EXCLUDED.telegram_username,
        assigned_by = EXCLUDED.assigned_by;

    UPDATE public.profiles
    SET role = CASE
        WHEN COALESCE(role, 'member') = 'member' THEN 'moderator'
        ELSE role
    END
    WHERE user_id = p_user_id;

    RETURN EXISTS (
        SELECT 1
        FROM public.moderators
        WHERE user_id = p_user_id
    );
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
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1
           FROM public.admin_users
           WHERE user_id = auth.uid()
       ) THEN
        RETURN false;
    END IF;

    IF p_user_id IS NULL THEN
        RETURN false;
    END IF;

    DELETE FROM public.moderators
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE public.profiles
    SET role = 'member'
    WHERE user_id = p_user_id
      AND role = 'moderator';

    RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_assign_moderator(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_assign_moderator(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_assign_moderator(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assign_moderator(UUID) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_remove_moderator(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_remove_moderator(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_remove_moderator(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_moderator(UUID) TO service_role;

DO $$
BEGIN
    IF to_regclass('public.result_ratings') IS NOT NULL THEN
        ALTER TABLE public.result_ratings ENABLE ROW LEVEL SECURITY;

        REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_ratings FROM PUBLIC;
        REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_ratings FROM anon;
        REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_ratings FROM authenticated;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_ratings FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_ratings FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_ratings FROM authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.result_ratings TO service_role;

        DROP POLICY IF EXISTS "own_read_result_ratings" ON public.result_ratings;
        DROP POLICY IF EXISTS "own_insert_result_ratings" ON public.result_ratings;
        DROP POLICY IF EXISTS "own_update_result_ratings" ON public.result_ratings;
        DROP POLICY IF EXISTS "public_read_result_ratings" ON public.result_ratings;
        DROP POLICY IF EXISTS "service_manage_result_ratings" ON public.result_ratings;

        CREATE POLICY "service_manage_result_ratings" ON public.result_ratings
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.get_result_rating_stats(INTEGER[]);
CREATE OR REPLACE FUNCTION public.get_result_rating_stats(p_result_ids INTEGER[])
RETURNS TABLE (
    result_id INTEGER,
    avg_score NUMERIC,
    rating_count BIGINT,
    my_score NUMERIC,
    my_s_visual NUMERIC,
    my_s_animation NUMERIC,
    my_s_creative NUMERIC,
    my_s_code NUMERIC,
    my_s_detail NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH requested AS (
        SELECT DISTINCT req.id
        FROM unnest(COALESCE(p_result_ids, ARRAY[]::INTEGER[])) AS req(id)
        WHERE req.id IS NOT NULL
        LIMIT 100
    )
    SELECT
        r.id AS result_id,
        ROUND(AVG((rr.s_visual + rr.s_animation + rr.s_creative + rr.s_code + rr.s_detail) * 1.8)::NUMERIC, 1) AS avg_score,
        COUNT(rr.id)::BIGINT AS rating_count,
        ROUND(MAX((rr.s_visual + rr.s_animation + rr.s_creative + rr.s_code + rr.s_detail) * 1.8) FILTER (WHERE rr.user_id = auth.uid())::NUMERIC, 1) AS my_score,
        MAX(rr.s_visual) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_visual,
        MAX(rr.s_animation) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_animation,
        MAX(rr.s_creative) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_creative,
        MAX(rr.s_code) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_code,
        MAX(rr.s_detail) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_detail
    FROM requested
    JOIN public.results AS r ON r.id = requested.id
    LEFT JOIN public.result_ratings AS rr ON rr.result_id = r.id
    GROUP BY r.id;
$$;

DROP FUNCTION IF EXISTS public.get_result_rating_entries(INTEGER[], INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_result_rating_entries(
    p_result_ids INTEGER[],
    p_limit_per_result INTEGER DEFAULT 8
)
RETURNS TABLE (
    result_id INTEGER,
    rating_id BIGINT,
    rating_rank INTEGER,
    rated_at TIMESTAMPTZ,
    rating_delay_seconds INTEGER,
    rater_uid INTEGER,
    rater_nickname TEXT,
    rater_role TEXT,
    total_score NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INTEGER := LEAST(20, GREATEST(1, COALESCE(p_limit_per_result, 8)));
BEGIN
    IF p_result_ids IS NULL OR array_length(p_result_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH requested AS (
        SELECT DISTINCT ON (req.id) req.id, req.ord
        FROM unnest(p_result_ids) WITH ORDINALITY AS req(id, ord)
        WHERE req.id IS NOT NULL
        ORDER BY req.id, req.ord
        LIMIT 100
    ),
    ranked AS (
        SELECT
            rr.result_id,
            rr.id AS rating_id,
            ROW_NUMBER() OVER (
                PARTITION BY rr.result_id
                ORDER BY
                    GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (
                        rr.created_at - COALESCE(r.created_at, r.test_date::TIMESTAMPTZ, rr.created_at)
                    )))::INTEGER) ASC,
                    rr.created_at ASC,
                    rr.id ASC
            )::INTEGER AS rating_rank,
            rr.created_at AS rated_at,
            GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (
                rr.created_at - COALESCE(r.created_at, r.test_date::TIMESTAMPTZ, rr.created_at)
            )))::INTEGER) AS rating_delay_seconds,
            p.uid AS rater_uid,
            COALESCE(
                '@' || NULLIF(p.telegram_username, ''),
                CASE WHEN p.uid IS NOT NULL THEN '@uid' || p.uid::TEXT ELSE '@unknown' END
            ) AS rater_nickname,
            COALESCE(p.role, 'member') AS rater_role,
            ROUND(((rr.s_visual + rr.s_animation + rr.s_creative + rr.s_code + rr.s_detail) * 1.8)::NUMERIC, 1) AS total_score,
            requested.ord
        FROM requested
        JOIN public.results AS r ON r.id = requested.id
        JOIN public.result_ratings AS rr ON rr.result_id = r.id
        LEFT JOIN public.profiles AS p ON p.user_id = rr.user_id
    )
    SELECT
        ranked.result_id,
        ranked.rating_id,
        ranked.rating_rank,
        ranked.rated_at,
        ranked.rating_delay_seconds,
        ranked.rater_uid,
        ranked.rater_nickname,
        ranked.rater_role,
        ranked.total_score
    FROM ranked
    WHERE ranked.rating_rank <= v_limit
    ORDER BY ranked.ord ASC, ranked.rating_rank ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_result_rating_stats(INTEGER[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_result_rating_stats(INTEGER[]) TO anon;
GRANT EXECUTE ON FUNCTION public.get_result_rating_stats(INTEGER[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_result_rating_stats(INTEGER[]) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_result_rating_entries(INTEGER[], INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_result_rating_entries(INTEGER[], INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION public.get_result_rating_entries(INTEGER[], INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_result_rating_entries(INTEGER[], INTEGER) TO service_role;

DROP FUNCTION IF EXISTS public.rate_result(INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) CASCADE;
CREATE OR REPLACE FUNCTION public.rate_result(
    p_result_id INTEGER,
    p_s_visual NUMERIC,
    p_s_animation NUMERIC,
    p_s_creative NUMERIC,
    p_s_code NUMERIC,
    p_s_detail NUMERIC
)
RETURNS TABLE (
    result_id INTEGER,
    avg_score NUMERIC,
    rating_count BIGINT,
    my_score NUMERIC,
    my_s_visual NUMERIC,
    my_s_animation NUMERIC,
    my_s_creative NUMERIC,
    my_s_code NUMERIC,
    my_s_detail NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_recent_rating_count INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE user_id = v_user_id
          AND is_verified = true
    ) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;

    IF p_result_id IS NULL THEN
        RAISE EXCEPTION 'Result ID is required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.results
        WHERE id = p_result_id
    ) THEN
        RAISE EXCEPTION 'Result not found';
    END IF;

    -- Serialize rating writes per user so rate-limit checks remain effective
    -- under concurrent retries.
    PERFORM pg_advisory_xact_lock(
        hashtext('public.rate_result'),
        hashtext(v_user_id::text)
    );

    SELECT COUNT(*)
    INTO v_recent_rating_count
    FROM public.user_action_events
    WHERE user_id = v_user_id
      AND action_type = 'result_rating'
      AND created_at > now() - interval '1 minute';

    IF v_recent_rating_count >= 10 THEN
        RAISE EXCEPTION 'Too many rating actions. Try again in a minute.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'result_rating'
          AND target_id = p_result_id
          AND created_at > now() - interval '5 seconds'
    ) THEN
        RAISE EXCEPTION 'You can update the same result rating only once every 5 seconds.';
    END IF;

    INSERT INTO public.result_ratings (
        result_id,
        user_id,
        s_visual,
        s_animation,
        s_creative,
        s_code,
        s_detail
    )
    VALUES (
        p_result_id,
        v_user_id,
        LEAST(10, GREATEST(1, ROUND(p_s_visual::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_animation::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_creative::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_code::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_detail::numeric, 1)))
    )
    ON CONFLICT (result_id, user_id)
    DO UPDATE SET
        s_visual = EXCLUDED.s_visual,
        s_animation = EXCLUDED.s_animation,
        s_creative = EXCLUDED.s_creative,
        s_code = EXCLUDED.s_code,
        s_detail = EXCLUDED.s_detail;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'result_rating', p_result_id);

    RETURN QUERY
    SELECT *
    FROM public.get_result_rating_stats(ARRAY[p_result_id]);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rate_result(INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rate_result(INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) FROM anon;
GRANT EXECUTE ON FUNCTION public.rate_result(INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rate_result(INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO service_role;

-- ============================================================
-- Remaining legacy SECURITY DEFINER RPC hardening
-- ============================================================

DROP FUNCTION IF EXISTS public.admin_generate_invite_code();

CREATE OR REPLACE FUNCTION public.admin_generate_invite_code(p_max_uses INTEGER DEFAULT 10)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_code TEXT;
    v_max_uses INTEGER;
    v_attempt INTEGER := 0;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN NULL;
    END IF;

    v_max_uses := LEAST(100, GREATEST(1, COALESCE(p_max_uses, 10)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(6), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (code, created_by, is_admin_code, max_uses, use_count)
            VALUES (v_code, auth.uid(), true, v_max_uses, 0);
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

DROP FUNCTION IF EXISTS public.admin_delete_invite_code(UUID);
CREATE OR REPLACE FUNCTION public.admin_delete_invite_code(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

    UPDATE public.profiles
    SET has_generated_invite = false,
        generated_invite_code_id = NULL
    WHERE generated_invite_code_id = p_id;

    DELETE FROM public.invite_codes
    WHERE id = p_id
      AND COALESCE(use_count, 0) = 0;

    RETURN FOUND;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_get_invite_codes();
CREATE OR REPLACE FUNCTION public.admin_get_invite_codes()
RETURNS SETOF public.invite_codes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT *
    FROM public.invite_codes
    ORDER BY created_at DESC NULLS LAST, id DESC;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_update_user_profile(
    p_user_id UUID,
    p_is_verified BOOLEAN DEFAULT NULL,
    p_created_at TIMESTAMPTZ DEFAULT NULL,
    p_bio TEXT DEFAULT NULL,
    p_telegram_first_name TEXT DEFAULT NULL,
    p_telegram_last_name TEXT DEFAULT NULL,
    p_telegram_username TEXT DEFAULT NULL,
    p_telegram_photo_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updates TEXT[] := '{}';
    v_photo_url TEXT;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF p_user_id IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM public.profiles WHERE user_id = p_user_id
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    IF p_is_verified IS NOT NULL THEN
        UPDATE public.profiles SET is_verified = p_is_verified WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'is_verified');
    END IF;

    IF p_created_at IS NOT NULL THEN
        UPDATE public.profiles SET created_at = p_created_at WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'created_at');
    END IF;

    IF p_bio IS NOT NULL THEN
        UPDATE public.profiles SET bio = left(p_bio, 1000) WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'bio');
    END IF;

    IF p_telegram_first_name IS NOT NULL THEN
        UPDATE public.profiles SET telegram_first_name = left(p_telegram_first_name, 120) WHERE user_id = p_user_id;
        v_updates := array_append(v_updates, 'telegram_first_name');
    END IF;

    IF p_telegram_last_name IS NOT NULL THEN
        UPDATE public.profiles SET telegram_last_name = left(p_telegram_last_name, 120) WHERE user_id = p_user_id;
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

    RETURN jsonb_build_object('ok', true, 'updated_fields', to_jsonb(v_updates));
END;
$$;

DROP FUNCTION IF EXISTS public.admin_get_user_detail(UUID);
CREATE OR REPLACE FUNCTION public.admin_get_user_detail(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile JSONB;
    v_achievements JSONB := '[]'::jsonb;
    v_stats JSONB := jsonb_build_object(
        'threads_count', 0,
        'posts_count', 0,
        'reactions_given', 0,
        'reactions_received', 0,
        'achievement_points', 0,
        'login_streak', 0,
        'max_streak', 0,
        'is_banned', false,
        'is_muted', false
    );
    v_threads_count BIGINT := 0;
    v_posts_count BIGINT := 0;
    v_reactions_given BIGINT := 0;
    v_reactions_received BIGINT := 0;
    v_achievement_points BIGINT := 0;
    v_login_streak INTEGER := 0;
    v_max_streak INTEGER := 0;
    v_is_banned BOOLEAN := false;
    v_is_muted BOOLEAN := false;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    SELECT to_jsonb(p)
    INTO v_profile
    FROM public.profiles p
    WHERE p.user_id = p_user_id;

    IF v_profile IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    IF to_regclass('public.user_achievements') IS NOT NULL
       AND to_regclass('public.achievements') IS NOT NULL THEN
        EXECUTE $detail$
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'achievement_id', a.id,
                'title', a.title,
                'icon_emoji', a.icon_emoji,
                'rarity', a.rarity,
                'points', a.points,
                'unlocked_at', ua.unlocked_at,
                'is_showcased', ua.is_showcased
            ) ORDER BY a.sort_order), '[]'::jsonb)
            FROM public.user_achievements ua
            JOIN public.achievements a ON a.id = ua.achievement_id
            WHERE ua.user_id = $1
        $detail$
        INTO v_achievements
        USING p_user_id;

        EXECUTE $points$
            SELECT COALESCE(SUM(a.points), 0)
            FROM public.user_achievements ua
            JOIN public.achievements a ON a.id = ua.achievement_id
            WHERE ua.user_id = $1
        $points$
        INTO v_achievement_points
        USING p_user_id;
    END IF;

    IF to_regclass('public.forum_threads') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.forum_threads WHERE author_id = $1 AND is_deleted = false'
        INTO v_threads_count
        USING p_user_id;
    END IF;

    IF to_regclass('public.forum_posts') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.forum_posts WHERE author_id = $1 AND is_deleted = false'
        INTO v_posts_count
        USING p_user_id;
    END IF;

    IF to_regclass('public.post_reactions') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.post_reactions WHERE user_id = $1'
        INTO v_reactions_given
        USING p_user_id;
    END IF;

    IF to_regclass('public.post_reactions') IS NOT NULL
       AND to_regclass('public.forum_posts') IS NOT NULL THEN
        EXECUTE $reactions$
            SELECT COUNT(*)
            FROM public.post_reactions pr
            JOIN public.forum_posts fp ON fp.id = pr.post_id
            WHERE fp.author_id = $1
        $reactions$
        INTO v_reactions_received
        USING p_user_id;
    END IF;

    IF to_regclass('public.login_streaks') IS NOT NULL THEN
        EXECUTE 'SELECT COALESCE(current_streak, 0), COALESCE(max_streak, 0) FROM public.login_streaks WHERE user_id = $1'
        INTO v_login_streak, v_max_streak
        USING p_user_id;
    END IF;

    IF to_regclass('public.user_mod_actions') IS NOT NULL THEN
        EXECUTE $mods$
            SELECT
                EXISTS(SELECT 1 FROM public.user_mod_actions WHERE user_id = $1 AND action_type = 'ban' AND is_active = true AND (expires_at IS NULL OR expires_at > now())),
                EXISTS(SELECT 1 FROM public.user_mod_actions WHERE user_id = $1 AND action_type = 'mute' AND is_active = true AND (expires_at IS NULL OR expires_at > now()))
        $mods$
        INTO v_is_banned, v_is_muted
        USING p_user_id;
    END IF;

    v_stats := jsonb_build_object(
        'threads_count', v_threads_count,
        'posts_count', v_posts_count,
        'reactions_given', v_reactions_given,
        'reactions_received', v_reactions_received,
        'achievement_points', v_achievement_points,
        'login_streak', v_login_streak,
        'max_streak', v_max_streak,
        'is_banned', v_is_banned,
        'is_muted', v_is_muted
    );

    RETURN jsonb_build_object(
        'ok', true,
        'profile', v_profile,
        'achievements', v_achievements,
        'stats', v_stats
    );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_grant_achievement(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.admin_grant_achievement(p_user_id UUID, p_achievement_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF p_user_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = p_user_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'user_not_found');
    END IF;

    IF to_regclass('public.achievements') IS NULL
       OR to_regclass('public.user_achievements') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'achievements_not_installed');
    END IF;

    IF p_achievement_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.achievements WHERE id = p_achievement_id) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'achievement_not_found');
    END IF;

    INSERT INTO public.user_achievements (user_id, achievement_id)
    VALUES (p_user_id, p_achievement_id)
    ON CONFLICT (user_id, achievement_id) DO NOTHING;

    RETURN jsonb_build_object(
        'ok', true,
        'granted', FOUND,
        'achievement_id', p_achievement_id
    );
END;
$$;

DROP FUNCTION IF EXISTS public.admin_revoke_achievement(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.admin_revoke_achievement(p_user_id UUID, p_achievement_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_admin');
    END IF;

    IF to_regclass('public.user_achievements') IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'achievements_not_installed');
    END IF;

    DELETE FROM public.user_achievements
    WHERE user_id = p_user_id
      AND achievement_id = p_achievement_id;

    RETURN jsonb_build_object('ok', true, 'revoked', FOUND);
END;
$$;

DROP FUNCTION IF EXISTS public.get_my_notifications(INTEGER);
CREATE OR REPLACE FUNCTION public.get_my_notifications(p_limit INTEGER DEFAULT 20)
RETURNS TABLE(
    id INTEGER,
    type TEXT,
    from_user_id UUID,
    from_username TEXT,
    from_first_name TEXT,
    from_photo_url TEXT,
    ref_thread_id INTEGER,
    ref_post_id INTEGER,
    emoji TEXT,
    snippet TEXT,
    is_read BOOLEAN,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INTEGER := LEAST(100, GREATEST(1, COALESCE(p_limit, 20)));
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        n.id, n.type, n.from_user_id,
        p.telegram_username,
        p.telegram_first_name,
        p.telegram_photo_url,
        n.ref_thread_id, n.ref_post_id,
        n.emoji, n.snippet, n.is_read, n.created_at
    FROM public.notifications n
    LEFT JOIN public.profiles p ON p.user_id = n.from_user_id
    WHERE n.user_id = auth.uid()
    ORDER BY n.created_at DESC
    LIMIT v_limit;
END;
$$;

DROP FUNCTION IF EXISTS public.get_unread_count();
CREATE OR REPLACE FUNCTION public.get_unread_count()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM public.notifications
    WHERE user_id = auth.uid()
      AND is_read = false;

    RETURN v_count;
END;
$$;

DROP FUNCTION IF EXISTS public.mark_notifications_read();
CREATE OR REPLACE FUNCTION public.mark_notifications_read()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_count INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN 0;
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'notification_mark_read'
          AND created_at > now() - interval '1 minute'
    ) >= 30 THEN
        RAISE EXCEPTION 'Too many notification updates. Try again in a minute.';
    END IF;

    UPDATE public.notifications
    SET is_read = true
    WHERE user_id = v_user_id
      AND is_read = false;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    INSERT INTO public.user_action_events (user_id, action_type)
    VALUES (v_user_id, 'notification_mark_read');

    RETURN v_count;
END;
$$;

DROP FUNCTION IF EXISTS public.resolve_usernames(TEXT);
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
    SELECT p.telegram_username, p.user_id
    FROM public.profiles p
    WHERE lower(p.telegram_username) = ANY(v_usernames)
      AND p.is_verified = true;
END;
$$;

DROP FUNCTION IF EXISTS public.get_user_recent_activity(UUID, INTEGER, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_user_recent_activity(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 10,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    activity_type TEXT,
    thread_id INTEGER,
    thread_title TEXT,
    post_id INTEGER,
    preview TEXT,
    emoji TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INTEGER := LEAST(50, GREATEST(1, COALESCE(p_limit, 10)));
    v_offset INTEGER := LEAST(500, GREATEST(0, COALESCE(p_offset, 0)));
BEGIN
    IF p_user_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    (
        SELECT 'thread'::TEXT, ft.id, ft.title, NULL::INTEGER, left(ft.content, 120), NULL::TEXT, ft.created_at
        FROM public.forum_threads ft
        WHERE ft.author_id = p_user_id AND ft.is_deleted = false
    )
    UNION ALL
    (
        SELECT 'post'::TEXT, fp.thread_id, ft2.title, fp.id, left(fp.content, 120), NULL::TEXT, fp.created_at
        FROM public.forum_posts fp
        LEFT JOIN public.forum_threads ft2 ON ft2.id = fp.thread_id
        WHERE fp.author_id = p_user_id AND fp.is_deleted = false
    )
    UNION ALL
    (
        SELECT 'reaction'::TEXT, fp3.thread_id, ft3.title, pr.post_id, left(fp3.content, 120), pr.emoji, pr.created_at
        FROM public.post_reactions pr
        LEFT JOIN public.forum_posts fp3 ON fp3.id = pr.post_id AND fp3.is_deleted = false
        LEFT JOIN public.forum_threads ft3 ON ft3.id = fp3.thread_id
        WHERE pr.user_id = p_user_id
    )
    ORDER BY 7 DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$;

DROP FUNCTION IF EXISTS public.get_user_threads(UUID, INTEGER, INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_user_threads(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    id INTEGER,
    title TEXT,
    posts_count INTEGER,
    created_at TIMESTAMPTZ,
    category_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INTEGER := LEAST(50, GREATEST(1, COALESCE(p_limit, 20)));
    v_offset INTEGER := LEAST(500, GREATEST(0, COALESCE(p_offset, 0)));
BEGIN
    IF p_user_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT ft.id, ft.title, ft.posts_count, ft.created_at, fc.name
    FROM public.forum_threads ft
    LEFT JOIN public.forum_categories fc ON fc.id = ft.category_id
    WHERE ft.author_id = p_user_id
      AND ft.is_deleted = false
    ORDER BY ft.created_at DESC
    LIMIT v_limit OFFSET v_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_get_invite_codes() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_get_invite_codes() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_get_invite_codes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_invite_codes() TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_invite_code(UUID) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_profile(UUID, BOOLEAN, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_get_user_detail(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_get_user_detail(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_detail(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_user_detail(UUID) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_grant_achievement(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_grant_achievement(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_achievement(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_grant_achievement(UUID, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_revoke_achievement(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_revoke_achievement(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_revoke_achievement(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_achievement(UUID, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_my_notifications(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_notifications(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_notifications(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_unread_count() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_unread_count() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_unread_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_count() TO service_role;

REVOKE EXECUTE ON FUNCTION public.mark_notifications_read() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mark_notifications_read() FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read() TO service_role;

REVOKE EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_usernames(TEXT[]) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_user_recent_activity(UUID, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_recent_activity(UUID, INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_user_recent_activity(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_recent_activity(UUID, INTEGER, INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_user_threads(UUID, INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_threads(UUID, INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_user_threads(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_threads(UUID, INTEGER, INTEGER) TO service_role;

DO $$
BEGIN
    IF to_regprocedure('public.admin_get_profiles()') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_get_profiles() FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_get_profiles() FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_get_profiles() TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_get_profiles() TO service_role';
    END IF;

    IF to_regprocedure('public.admin_reset_user_invite_limit(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_reset_user_invite_limit(UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_reset_user_invite_limit(UUID) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_reset_user_invite_limit(UUID) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_reset_user_invite_limit(UUID) TO service_role';
    END IF;

    IF to_regprocedure('public.admin_reset_all_invite_limits()') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_reset_all_invite_limits() FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_reset_all_invite_limits() FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_reset_all_invite_limits() TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_reset_all_invite_limits() TO service_role';
    END IF;

    IF to_regprocedure('public.admin_set_user_role(uuid,text)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_set_user_role(UUID, TEXT) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_set_user_role(UUID, TEXT) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_set_user_role(UUID, TEXT) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_set_user_role(UUID, TEXT) TO service_role';
    END IF;

    IF to_regprocedure('public.admin_get_moderators()') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_get_moderators() FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_get_moderators() FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_get_moderators() TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_get_moderators() TO service_role';
    END IF;

    IF to_regprocedure('public.admin_get_invite_code_uses(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_get_invite_code_uses(UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.admin_get_invite_code_uses(UUID) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_get_invite_code_uses(UUID) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.admin_get_invite_code_uses(UUID) TO service_role';
    END IF;

    IF to_regprocedure('public.get_user_mod_actions(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.get_user_mod_actions(UUID) FROM PUBLIC';
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.get_user_mod_actions(UUID) FROM anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_user_mod_actions(UUID) TO authenticated';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_user_mod_actions(UUID) TO service_role';
    END IF;
END;
$$;

-- ============================================================
-- Admin content/catalog write hardening
-- ============================================================

DROP FUNCTION IF EXISTS public.is_admin();
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        COALESCE(auth.role(), '') = 'service_role'
        OR (
            auth.uid() IS NOT NULL
            AND EXISTS (
                SELECT 1
                FROM public.admin_users
                WHERE user_id = auth.uid()
            )
        );
$$;

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO service_role;

DROP FUNCTION IF EXISTS public.normalize_https_url(TEXT);
CREATE OR REPLACE FUNCTION public.normalize_https_url(p_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
    v_value TEXT := NULLIF(btrim(p_value), '');
BEGIN
    IF v_value IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_value !~* '^https://[^[:space:]]+$' THEN
        RAISE EXCEPTION 'URL must be null or start with https://';
    END IF;

    RETURN v_value;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.normalize_https_url(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.normalize_https_url(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.normalize_https_url(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.normalize_https_url(TEXT) FROM service_role;

ALTER TABLE public.results
    DROP CONSTRAINT IF EXISTS results_svg_content_safe;

DROP FUNCTION IF EXISTS public.is_safe_svg_content(TEXT);
CREATE OR REPLACE FUNCTION public.is_safe_svg_content(p_svg TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
    v_svg TEXT := COALESCE(p_svg, '');
BEGIN
    IF p_svg IS NULL OR btrim(p_svg) = '' THEN
        RETURN true;
    END IF;

    IF v_svg !~* '<[[:space:]]*svg([[:space:]>])' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '<[[:space:]]*script([[:space:]>])' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '<[[:space:]]*foreignObject([[:space:]>])' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '<[[:space:]]*(iframe|object|embed|link|meta|style)([[:space:]>])' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '[[:space:]]on[a-z0-9:_-]+[[:space:]]*=' THEN
        RETURN false;
    END IF;

    IF v_svg ~* 'style[[:space:]]*=' OR v_svg ~* 'url[[:space:]]*\(' OR v_svg ~* '@import' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '(href|src|xlink:href)[[:space:]]*=[[:space:]]*([''"]?)[[:space:]]*(javascript:|data:)' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '(href|src|xlink:href)[[:space:]]*=[[:space:]]*([''"]?)[[:space:]]*(https?:|//|/)' THEN
        RETURN false;
    END IF;

    IF v_svg ~* '<[[:space:]]*use([[:space:]>])[^>]*(href|xlink:href)[[:space:]]*=[[:space:]]*([''"]?)[[:space:]]*[^#''" >][^''" >]*' THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_safe_svg_content(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_safe_svg_content(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_safe_svg_content(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.is_safe_svg_content(TEXT) FROM service_role;

DROP FUNCTION IF EXISTS public.admin_content_target_table(TEXT);
CREATE OR REPLACE FUNCTION public.admin_content_target_table(p_table_name TEXT)
RETURNS REGCLASS
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
    CASE p_table_name
        WHEN 'prompts' THEN
            RETURN 'public.prompts'::regclass;
        WHEN 'models' THEN
            RETURN 'public.models'::regclass;
        WHEN 'model_spaces' THEN
            RETURN 'public.model_spaces'::regclass;
        WHEN 'model_params' THEN
            RETURN 'public.model_params'::regclass;
        WHEN 'model_param_values' THEN
            RETURN 'public.model_param_values'::regclass;
        WHEN 'results' THEN
            RETURN 'public.results'::regclass;
        WHEN 'result_param_values' THEN
            RETURN 'public.result_param_values'::regclass;
        ELSE
            RAISE EXCEPTION 'Unsupported admin content table: %', p_table_name;
    END CASE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_content_target_table(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_content_target_table(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_content_target_table(TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_content_target_table(TEXT) FROM service_role;

DROP FUNCTION IF EXISTS public.admin_prepare_content_payload(TEXT, JSONB);
CREATE OR REPLACE FUNCTION public.admin_prepare_content_payload(p_table_name TEXT, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_table REGCLASS;
    v_allowed_columns TEXT[];
    v_selected_columns TEXT[];
    v_invalid_columns TEXT[];
    v_payload JSONB := COALESCE(p_payload, '{}'::jsonb);
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;

    IF jsonb_typeof(v_payload) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'Payload must be a JSON object';
    END IF;

    IF v_payload = '{}'::jsonb THEN
        RAISE EXCEPTION 'Payload must include at least one writable column';
    END IF;

    IF v_payload ? 'id' OR v_payload ? 'created_at' THEN
        RAISE EXCEPTION 'id and created_at are server-managed columns';
    END IF;

    v_table := public.admin_content_target_table(p_table_name);

    SELECT COALESCE(array_agg(attname ORDER BY attnum), ARRAY[]::TEXT[])
    INTO v_allowed_columns
    FROM pg_attribute
    WHERE attrelid = v_table
      AND attnum > 0
      AND NOT attisdropped
      AND attname <> ALL (ARRAY['id', 'created_at']);

    SELECT COALESCE(array_agg(key ORDER BY key), ARRAY[]::TEXT[])
    INTO v_selected_columns
    FROM jsonb_object_keys(v_payload) AS key
    WHERE key = ANY (v_allowed_columns);

    SELECT COALESCE(array_agg(key ORDER BY key), ARRAY[]::TEXT[])
    INTO v_invalid_columns
    FROM jsonb_object_keys(v_payload) AS key
    WHERE key <> ALL (v_allowed_columns);

    IF cardinality(v_invalid_columns) > 0 THEN
        RAISE EXCEPTION 'Unsupported columns for %: %', p_table_name, array_to_string(v_invalid_columns, ', ');
    END IF;

    IF cardinality(v_selected_columns) = 0 THEN
        RAISE EXCEPTION 'Payload must include at least one writable column';
    END IF;

    IF p_table_name = 'model_spaces' AND v_payload ? 'url' THEN
        v_payload := jsonb_set(
            v_payload,
            '{url}',
            COALESCE(to_jsonb(public.normalize_https_url(v_payload ->> 'url')), 'null'::jsonb),
            true
        );
    END IF;

    IF p_table_name = 'results'
       AND v_payload ? 'svg_content'
       AND NOT public.is_safe_svg_content(v_payload ->> 'svg_content') THEN
        RAISE EXCEPTION 'Unsafe SVG content';
    END IF;

    RETURN v_payload;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_prepare_content_payload(TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_prepare_content_payload(TEXT, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_prepare_content_payload(TEXT, JSONB) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_prepare_content_payload(TEXT, JSONB) FROM service_role;

DROP FUNCTION IF EXISTS public.admin_validate_result_payload(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_validate_result_payload(p_result_id INTEGER, p_payload JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_model_id INTEGER;
    v_model_space_id INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;

    IF p_result_id IS NULL THEN
        v_model_id := NULLIF(p_payload ->> 'model_id', '')::INTEGER;
        v_model_space_id := NULLIF(p_payload ->> 'model_space_id', '')::INTEGER;
    ELSE
        SELECT model_id, model_space_id
        INTO v_model_id, v_model_space_id
        FROM public.results
        WHERE id = p_result_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Result % not found', p_result_id;
        END IF;

        IF p_payload ? 'model_id' THEN
            v_model_id := NULLIF(p_payload ->> 'model_id', '')::INTEGER;
        END IF;

        IF p_payload ? 'model_space_id' THEN
            v_model_space_id := NULLIF(p_payload ->> 'model_space_id', '')::INTEGER;
        END IF;
    END IF;

    IF v_model_id IS NULL THEN
        RAISE EXCEPTION 'results.model_id is required';
    END IF;

    IF v_model_space_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.model_spaces
            WHERE id = v_model_space_id
              AND model_id = v_model_id
       ) THEN
        RAISE EXCEPTION 'model_space_id % does not belong to model_id %', v_model_space_id, v_model_id;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_validate_result_payload(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_validate_result_payload(INTEGER, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_validate_result_payload(INTEGER, JSONB) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_validate_result_payload(INTEGER, JSONB) FROM service_role;

DROP FUNCTION IF EXISTS public.admin_insert_content_row(TEXT, JSONB);
CREATE OR REPLACE FUNCTION public.admin_insert_content_row(p_table_name TEXT, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_table REGCLASS;
    v_payload JSONB;
    v_columns TEXT[];
    v_insert_columns TEXT;
    v_insert_values TEXT;
    v_sql TEXT;
    v_row JSONB;
BEGIN
    v_payload := public.admin_prepare_content_payload(p_table_name, p_payload);
    v_table := public.admin_content_target_table(p_table_name);

    IF p_table_name = 'results' THEN
        PERFORM public.admin_validate_result_payload(NULL, v_payload);
    END IF;

    SELECT COALESCE(array_agg(key ORDER BY key), ARRAY[]::TEXT[])
    INTO v_columns
    FROM jsonb_object_keys(v_payload) AS key;

    v_insert_columns := array_to_string(
        ARRAY(SELECT format('%I', col) FROM unnest(v_columns) AS col),
        ', '
    );

    v_insert_values := array_to_string(
        ARRAY(SELECT format('payload_row.%I', col) FROM unnest(v_columns) AS col),
        ', '
    );

    v_sql := format(
        'WITH payload_row AS (
             SELECT * FROM jsonb_populate_record(NULL::%1$s, $1)
         )
         INSERT INTO %1$s AS t (%2$s)
         SELECT %3$s
         FROM payload_row
         RETURNING row_to_json(t)::jsonb',
        v_table,
        v_insert_columns,
        v_insert_values
    );

    EXECUTE v_sql USING v_payload INTO v_row;

    RETURN v_row;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_insert_content_row(TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_insert_content_row(TEXT, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_insert_content_row(TEXT, JSONB) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_insert_content_row(TEXT, JSONB) FROM service_role;

DROP FUNCTION IF EXISTS public.admin_update_content_row(TEXT, INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_content_row(p_table_name TEXT, p_id INTEGER, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_table REGCLASS;
    v_payload JSONB;
    v_columns TEXT[];
    v_update_assignments TEXT;
    v_sql TEXT;
    v_row JSONB;
BEGIN
    IF p_id IS NULL THEN
        RAISE EXCEPTION 'Row id is required';
    END IF;

    v_payload := public.admin_prepare_content_payload(p_table_name, p_payload);
    v_table := public.admin_content_target_table(p_table_name);

    IF p_table_name = 'results' THEN
        PERFORM public.admin_validate_result_payload(p_id, v_payload);
    END IF;

    SELECT COALESCE(array_agg(key ORDER BY key), ARRAY[]::TEXT[])
    INTO v_columns
    FROM jsonb_object_keys(v_payload) AS key;

    v_update_assignments := array_to_string(
        ARRAY(SELECT format('%1$I = payload_row.%1$I', col) FROM unnest(v_columns) AS col),
        ', '
    );

    v_sql := format(
        'WITH payload_row AS (
             SELECT * FROM jsonb_populate_record(NULL::%1$s, $1)
         )
         UPDATE %1$s AS t
         SET %2$s
         FROM payload_row
         WHERE t.id = $2
         RETURNING row_to_json(t)::jsonb',
        v_table,
        v_update_assignments
    );

    EXECUTE v_sql USING v_payload, p_id INTO v_row;

    IF v_row IS NULL THEN
        RAISE EXCEPTION '% row % not found', p_table_name, p_id;
    END IF;

    RETURN v_row;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_update_content_row(TEXT, INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_content_row(TEXT, INTEGER, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_content_row(TEXT, INTEGER, JSONB) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_content_row(TEXT, INTEGER, JSONB) FROM service_role;

DROP FUNCTION IF EXISTS public.admin_delete_content_row(TEXT, INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_content_row(p_table_name TEXT, p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_table REGCLASS;
    v_deleted BOOLEAN := false;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'Row id is required';
    END IF;

    v_table := public.admin_content_target_table(p_table_name);

    EXECUTE format(
        'DELETE FROM %s WHERE id = $1 RETURNING true',
        v_table
    )
    USING p_id
    INTO v_deleted;

    RETURN COALESCE(v_deleted, false);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_content_row(TEXT, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_content_row(TEXT, INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_delete_content_row(TEXT, INTEGER) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_content_row(TEXT, INTEGER) FROM service_role;

DO $$
BEGIN
    IF to_regclass('public.prompts') IS NOT NULL THEN
        ALTER TABLE public.prompts ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.prompts FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.prompts FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.prompts FROM authenticated;
        GRANT SELECT ON TABLE public.prompts TO anon;
        GRANT SELECT ON TABLE public.prompts TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.prompts TO service_role;

        DROP POLICY IF EXISTS "public_read_prompts" ON public.prompts;
        DROP POLICY IF EXISTS "admin_all_prompts" ON public.prompts;
        DROP POLICY IF EXISTS "admin_manage_prompts" ON public.prompts;
        DROP POLICY IF EXISTS "service_manage_prompts" ON public.prompts;

DROP POLICY IF EXISTS "public_read_prompts" ON public.prompts;
        CREATE POLICY "public_read_prompts" ON public.prompts
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_prompts" ON public.prompts;
        CREATE POLICY "service_manage_prompts" ON public.prompts
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.models') IS NOT NULL THEN
        ALTER TABLE public.models ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.models FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.models FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.models FROM authenticated;
        GRANT SELECT ON TABLE public.models TO anon;
        GRANT SELECT ON TABLE public.models TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.models TO service_role;

        DROP POLICY IF EXISTS "public_read_models" ON public.models;
        DROP POLICY IF EXISTS "public_read_models_new" ON public.models;
        DROP POLICY IF EXISTS "admin_all_models" ON public.models;
        DROP POLICY IF EXISTS "admin_all_models_new" ON public.models;
        DROP POLICY IF EXISTS "service_manage_models" ON public.models;

DROP POLICY IF EXISTS "public_read_models" ON public.models;
        CREATE POLICY "public_read_models" ON public.models
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_models" ON public.models;
        CREATE POLICY "service_manage_models" ON public.models
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.model_spaces') IS NOT NULL THEN
        ALTER TABLE public.model_spaces ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_spaces FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_spaces FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_spaces FROM authenticated;
        GRANT SELECT ON TABLE public.model_spaces TO anon;
        GRANT SELECT ON TABLE public.model_spaces TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_spaces TO service_role;

        ALTER TABLE public.model_spaces
            DROP CONSTRAINT IF EXISTS model_spaces_https_url_only;
        ALTER TABLE public.model_spaces
            ADD CONSTRAINT model_spaces_https_url_only
            CHECK (url IS NULL OR url ~* '^https://[^[:space:]]+$')
            NOT VALID;

        DROP POLICY IF EXISTS "public_read_model_spaces" ON public.model_spaces;
        DROP POLICY IF EXISTS "admin_all_model_spaces" ON public.model_spaces;
        DROP POLICY IF EXISTS "service_manage_model_spaces" ON public.model_spaces;

DROP POLICY IF EXISTS "public_read_model_spaces" ON public.model_spaces;
        CREATE POLICY "public_read_model_spaces" ON public.model_spaces
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_model_spaces" ON public.model_spaces;
        CREATE POLICY "service_manage_model_spaces" ON public.model_spaces
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.model_params') IS NOT NULL THEN
        ALTER TABLE public.model_params ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_params FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_params FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_params FROM authenticated;
        GRANT SELECT ON TABLE public.model_params TO anon;
        GRANT SELECT ON TABLE public.model_params TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_params TO service_role;

        DROP POLICY IF EXISTS "public_read_model_params" ON public.model_params;
        DROP POLICY IF EXISTS "admin_all_model_params" ON public.model_params;
        DROP POLICY IF EXISTS "service_manage_model_params" ON public.model_params;

DROP POLICY IF EXISTS "public_read_model_params" ON public.model_params;
        CREATE POLICY "public_read_model_params" ON public.model_params
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_model_params" ON public.model_params;
        CREATE POLICY "service_manage_model_params" ON public.model_params
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.model_param_values') IS NOT NULL THEN
        ALTER TABLE public.model_param_values ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_param_values FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_param_values FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_param_values FROM authenticated;
        GRANT SELECT ON TABLE public.model_param_values TO anon;
        GRANT SELECT ON TABLE public.model_param_values TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.model_param_values TO service_role;

        DROP POLICY IF EXISTS "public_read_model_param_values" ON public.model_param_values;
        DROP POLICY IF EXISTS "admin_all_model_param_values" ON public.model_param_values;
        DROP POLICY IF EXISTS "service_manage_model_param_values" ON public.model_param_values;

DROP POLICY IF EXISTS "public_read_model_param_values" ON public.model_param_values;
        CREATE POLICY "public_read_model_param_values" ON public.model_param_values
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_model_param_values" ON public.model_param_values;
        CREATE POLICY "service_manage_model_param_values" ON public.model_param_values
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.results') IS NOT NULL THEN
        ALTER TABLE public.results ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.results FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.results FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.results FROM authenticated;
        GRANT SELECT ON TABLE public.results TO anon;
        GRANT SELECT ON TABLE public.results TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.results TO service_role;

        ALTER TABLE public.results
            DROP CONSTRAINT IF EXISTS results_svg_content_safe;
        ALTER TABLE public.results
            ADD CONSTRAINT results_svg_content_safe
            CHECK (public.is_safe_svg_content(svg_content))
            NOT VALID;

        DROP POLICY IF EXISTS "public_read_results" ON public.results;
        DROP POLICY IF EXISTS "admin_all_results" ON public.results;
        DROP POLICY IF EXISTS "service_manage_results" ON public.results;

DROP POLICY IF EXISTS "public_read_results" ON public.results;
        CREATE POLICY "public_read_results" ON public.results
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_results" ON public.results;
        CREATE POLICY "service_manage_results" ON public.results
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;

    IF to_regclass('public.result_param_values') IS NOT NULL THEN
        ALTER TABLE public.result_param_values ENABLE ROW LEVEL SECURITY;

        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_param_values FROM PUBLIC;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_param_values FROM anon;
        REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_param_values FROM authenticated;
        GRANT SELECT ON TABLE public.result_param_values TO anon;
        GRANT SELECT ON TABLE public.result_param_values TO authenticated;
        GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.result_param_values TO service_role;

        DROP POLICY IF EXISTS "public_read_result_param_values" ON public.result_param_values;
        DROP POLICY IF EXISTS "admin_all_result_param_values" ON public.result_param_values;
        DROP POLICY IF EXISTS "service_manage_result_param_values" ON public.result_param_values;

DROP POLICY IF EXISTS "public_read_result_param_values" ON public.result_param_values;
        CREATE POLICY "public_read_result_param_values" ON public.result_param_values
            FOR SELECT
            USING (true);

DROP POLICY IF EXISTS "service_manage_result_param_values" ON public.result_param_values;
        CREATE POLICY "service_manage_result_param_values" ON public.result_param_values
            FOR ALL TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.admin_add_prompt(JSONB);
CREATE OR REPLACE FUNCTION public.admin_add_prompt(p_prompt JSONB)
RETURNS SETOF public.prompts
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.prompts, public.admin_insert_content_row('prompts', p_prompt))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_update_prompt(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_prompt(p_id INTEGER, p_prompt JSONB)
RETURNS SETOF public.prompts
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.prompts, public.admin_update_content_row('prompts', p_id, p_prompt))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_delete_prompt(INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_prompt(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.admin_delete_content_row('prompts', p_id);
$$;

DROP FUNCTION IF EXISTS public.admin_add_model(JSONB);
CREATE OR REPLACE FUNCTION public.admin_add_model(p_model JSONB)
RETURNS SETOF public.models
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.models, public.admin_insert_content_row('models', p_model))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_update_model(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_model(p_id INTEGER, p_model JSONB)
RETURNS SETOF public.models
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.models, public.admin_update_content_row('models', p_id, p_model))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_delete_model(INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_model(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.admin_delete_content_row('models', p_id);
$$;

DROP FUNCTION IF EXISTS public.admin_add_model_space(JSONB);
CREATE OR REPLACE FUNCTION public.admin_add_model_space(p_space JSONB)
RETURNS SETOF public.model_spaces
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.model_spaces, public.admin_insert_content_row('model_spaces', p_space))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_update_model_space(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_model_space(p_id INTEGER, p_space JSONB)
RETURNS SETOF public.model_spaces
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.model_spaces, public.admin_update_content_row('model_spaces', p_id, p_space))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_delete_model_space(INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_model_space(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.admin_delete_content_row('model_spaces', p_id);
$$;

DROP FUNCTION IF EXISTS public.admin_add_model_param(JSONB);
CREATE OR REPLACE FUNCTION public.admin_add_model_param(p_param JSONB)
RETURNS SETOF public.model_params
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.model_params, public.admin_insert_content_row('model_params', p_param))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_update_model_param(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_model_param(p_id INTEGER, p_param JSONB)
RETURNS SETOF public.model_params
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.model_params, public.admin_update_content_row('model_params', p_id, p_param))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_delete_model_param(INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_model_param(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.admin_delete_content_row('model_params', p_id);
$$;

DROP FUNCTION IF EXISTS public.admin_add_model_param_value(JSONB);
CREATE OR REPLACE FUNCTION public.admin_add_model_param_value(p_param_value JSONB)
RETURNS SETOF public.model_param_values
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.model_param_values, public.admin_insert_content_row('model_param_values', p_param_value))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_update_model_param_value(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_model_param_value(p_id INTEGER, p_param_value JSONB)
RETURNS SETOF public.model_param_values
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.model_param_values, public.admin_update_content_row('model_param_values', p_id, p_param_value))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_delete_model_param_value(INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_model_param_value(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.admin_delete_content_row('model_param_values', p_id);
$$;

DROP FUNCTION IF EXISTS public.admin_add_result(JSONB);
CREATE OR REPLACE FUNCTION public.admin_add_result(p_result JSONB)
RETURNS SETOF public.results
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.results, public.admin_insert_content_row('results', p_result))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_update_result(INTEGER, JSONB);
CREATE OR REPLACE FUNCTION public.admin_update_result(p_id INTEGER, p_result JSONB)
RETURNS SETOF public.results
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT (jsonb_populate_record(NULL::public.results, public.admin_update_content_row('results', p_id, p_result))).*;
$$;

DROP FUNCTION IF EXISTS public.admin_delete_result(INTEGER);
CREATE OR REPLACE FUNCTION public.admin_delete_result(p_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.admin_delete_content_row('results', p_id);
$$;

DROP FUNCTION IF EXISTS public.admin_set_result_param_values(INTEGER, INTEGER[]) CASCADE;
CREATE OR REPLACE FUNCTION public.admin_set_result_param_values(
    p_result_id INTEGER,
    p_param_value_ids INTEGER[]
)
RETURNS SETOF public.result_param_values
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result_model_id INTEGER;
    v_param_value_ids INTEGER[] := COALESCE(p_param_value_ids, ARRAY[]::INTEGER[]);
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Admin access required';
    END IF;

    IF p_result_id IS NULL THEN
        RAISE EXCEPTION 'Result ID is required';
    END IF;

    SELECT model_id
    INTO v_result_model_id
    FROM public.results
    WHERE id = p_result_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Result % not found', p_result_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(v_param_value_ids) AS item(param_value_id)
        LEFT JOIN public.model_param_values AS mpv
               ON mpv.id = item.param_value_id
        LEFT JOIN public.model_params AS mp
               ON mp.id = mpv.param_id
        WHERE item.param_value_id IS NULL
           OR mpv.id IS NULL
           OR mp.model_id <> v_result_model_id
    ) THEN
        RAISE EXCEPTION 'All result_param_values must belong to the result model';
    END IF;

    DELETE FROM public.result_param_values
    WHERE result_id = p_result_id;

    IF cardinality(v_param_value_ids) > 0 THEN
        INSERT INTO public.result_param_values (result_id, param_value_id)
        SELECT p_result_id, item.param_value_id
        FROM (
            SELECT DISTINCT unnest(v_param_value_ids) AS param_value_id
        ) AS item
        ORDER BY item.param_value_id;
    END IF;

    RETURN QUERY
    SELECT *
    FROM public.result_param_values
    WHERE result_id = p_result_id
    ORDER BY id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_add_prompt(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_add_prompt(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_prompt(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_prompt(JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_prompt(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_prompt(INTEGER, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_prompt(INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_prompt(INTEGER, JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_prompt(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_prompt(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_prompt(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_prompt(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_add_model(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_add_model(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_model(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_model(JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_model(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_model(INTEGER, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_model(INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_model(INTEGER, JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_model(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_model(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_model(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_model(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_add_model_space(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_add_model_space(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_model_space(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_model_space(JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_model_space(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_model_space(INTEGER, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_model_space(INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_model_space(INTEGER, JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_model_space(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_model_space(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_model_space(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_model_space(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_add_model_param(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_add_model_param(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_model_param(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_model_param(JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_model_param(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_model_param(INTEGER, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_model_param(INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_model_param(INTEGER, JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_model_param(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_model_param(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_model_param(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_model_param(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_add_model_param_value(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_add_model_param_value(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_model_param_value(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_model_param_value(JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_model_param_value(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_model_param_value(INTEGER, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_model_param_value(INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_model_param_value(INTEGER, JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_model_param_value(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_model_param_value(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_model_param_value(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_model_param_value(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_add_result(JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_add_result(JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_result(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_result(JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_update_result(INTEGER, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_update_result(INTEGER, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_result(INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_result(INTEGER, JSONB) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_delete_result(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_delete_result(INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_result(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_result(INTEGER) TO service_role;

REVOKE EXECUTE ON FUNCTION public.admin_set_result_param_values(INTEGER, INTEGER[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_set_result_param_values(INTEGER, INTEGER[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_result_param_values(INTEGER, INTEGER[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_result_param_values(INTEGER, INTEGER[]) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';

