-- ============================================
-- BUNDLE 15: BUGFIXES — Idempotent
-- Run AFTER all previous bundles (01-14)
-- ============================================
-- All statements are idempotent: safe to re-run.
-- ============================================

BEGIN;
SET LOCAL search_path = public;

-- ==========================================
-- FIX 1 [HIGH]: claim_invite_code — race condition in UPDATE
-- ==========================================
-- BUG: The claim_invite_code function (01-core.sql) performed a SELECT to
-- check use_count < max_uses, then a separate UPDATE that did not re-check.
-- Two concurrent transactions could both pass the SELECT and both increment
-- use_count, exceeding max_uses.
--
-- FIX: Add use_count < COALESCE(max_uses, use_count + 1) to the UPDATE WHERE
-- clause so the increment is atomic. Check IF NOT FOUND after UPDATE.
-- Rate limiting (from 14-bugfixes FIX 7) and expiry checking are preserved.

DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT);
DROP FUNCTION IF EXISTS public.claim_invite_code(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_code TEXT;
    v_invite_id UUID;
    v_max_uses INTEGER;
    v_current_uses INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.user_action_events
        WHERE user_id = v_user_id
          AND action_type = 'invite_claim'
          AND created_at > now() - interval '1 minute'
    ) THEN
        RAISE EXCEPTION 'Rate limit: please wait before claiming another invite code';
    END IF;

    INSERT INTO public.user_action_events (user_id, action_type)
    VALUES (v_user_id, 'invite_claim');

    IF p_code IS NOT NULL THEN
        v_code := p_code;
    ELSE
        SELECT pending_invite_code INTO v_code
        FROM profiles WHERE user_id = v_user_id;
    END IF;

    IF v_code IS NULL THEN
        RETURN false;
    END IF;

    SELECT id, max_uses, use_count INTO v_invite_id, v_max_uses, v_current_uses
    FROM invite_codes
    WHERE code = v_code
      AND (expires_at IS NULL OR expires_at > now())
      AND (max_uses IS NULL OR use_count < max_uses);

    IF v_invite_id IS NULL THEN
        RETURN false;
    END IF;

    IF EXISTS (SELECT 1 FROM invite_code_uses WHERE invite_code_id = v_invite_id AND user_id = v_user_id) THEN
        RETURN false;
    END IF;

    UPDATE invite_codes
    SET use_count = use_count + 1,
        used_by = v_user_id,
        used_at = now()
    WHERE id = v_invite_id
      AND use_count < COALESCE(max_uses, use_count + 1);

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    INSERT INTO invite_code_uses (invite_code_id, user_id)
    VALUES (v_invite_id, v_user_id);

    UPDATE profiles
    SET used_invite_code_id = v_invite_id,
        pending_invite_code = NULL
    WHERE user_id = v_user_id;

    RETURN true;
END;
$$;


-- ==========================================
-- FIX 2 [HIGH]: invite_code_uses — UNIQUE constraint on (invite_code_id, user_id)
-- ==========================================
-- BUG: Without a named UNIQUE constraint, a race could insert duplicate rows
-- for the same (invite_code_id, user_id) pair. 06b added a unique index; this
-- adds an explicit named constraint for schema clarity and integrity.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'invite_code_uses_unique'
          AND conrelid = 'public.invite_code_uses'::regclass
    ) THEN
        ALTER TABLE public.invite_code_uses
        ADD CONSTRAINT invite_code_uses_unique UNIQUE (invite_code_id, user_id);
    END IF;
END $$;


-- ==========================================
-- FIX 3 [HIGH]: telegram_id backfill — strip @neurobench.local suffix
-- ==========================================
-- BUG: The backfill in 01-core.sql:1534 used replace(email, 'telegram_', '')
-- which left '@neurobench.local' in telegram_id (e.g. '12345@neurobench.local').
--
-- FIX: Extract the part before '@' and strip 'telegram_' prefix.

UPDATE profiles
SET telegram_id = replace(split_part(email, '@', 1), 'telegram_', '')
WHERE email LIKE 'telegram_%@neurobench.local'
  AND telegram_id LIKE '%@neurobench.local';


-- ==========================================
-- FIX 4 [HIGH]: achievements table — enable RLS, block direct writes
-- ==========================================
-- BUG: The achievements catalog table had no RLS and no explicit revokes.
-- Any authenticated user could INSERT/UPDATE/DELETE achievement definitions.
--
-- FIX: Enable RLS, revoke write permissions from authenticated/anon, and add
-- a permissive SELECT policy so reads still work. Service role bypasses RLS.

ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE ON public.achievements FROM authenticated, anon;

DROP POLICY IF EXISTS "public_read_achievements" ON public.achievements;
CREATE POLICY "public_read_achievements" ON public.achievements
    FOR SELECT USING (true);


-- ==========================================
-- FIX 5 [HIGH]: user_mod_actions — block direct INSERT/UPDATE
-- ==========================================
-- BUG: authenticated users could directly INSERT/UPDATE user_mod_actions rows,
-- bypassing the SECURITY DEFINER moderator RPCs that enforce authorization.
--
-- FIX: Revoke INSERT and UPDATE from authenticated. All mod actions must go
-- through SECURITY DEFINER RPCs (ban_user, mute_user, etc.).

REVOKE INSERT, UPDATE ON public.user_mod_actions FROM authenticated;


-- ==========================================
-- FIX 6 [MEDIUM]: notifications — block direct UPDATE
-- ==========================================
-- BUG: authenticated users could directly UPDATE notifications, potentially
-- marking other users' notifications as read or modifying fields.
--
-- FIX: Revoke UPDATE from authenticated. Users mark notifications as read via
-- the mark_notifications_read RPC.

REVOKE UPDATE ON public.notifications FROM authenticated;


-- ==========================================
-- FIX 7 [MEDIUM]: toggle_post_reaction — decouple from achievements
-- ==========================================
-- BUG: toggle_post_reaction calls check_reaction_achievements directly. If the
-- achievements system has any error (missing achievement, constraint issue),
-- the entire reaction fails — users can't react at all.
--
-- FIX: Wrap the check_reaction_achievements call in a BEGIN...EXCEPTION block
-- so achievement system failures don't break reactions.

DROP FUNCTION IF EXISTS public.toggle_post_reaction(INTEGER, TEXT);
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

        BEGIN
            PERFORM public.check_reaction_achievements(p_post_id, v_user_id);
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;

    INSERT INTO public.user_action_events (user_id, action_type, target_id)
    VALUES (v_user_id, 'forum_reaction', p_post_id);

    RETURN jsonb_build_object('action', v_action, 'emoji', p_emoji);
END;
$$;


-- ==========================================
-- FIX 8 [MEDIUM]: resolve_usernames — case-insensitive matching
-- ==========================================
-- BUG: Earlier versions of resolve_usernames (03-forum.sql) lowercased the
-- profile column but not the input array, so 'John' in the input would not
-- match 'john' in the database.
--
-- FIX: Ensure both sides are lowercased. This re-creates the latest version
-- (09-username-approval.sql) which normalizes the input array to lowercase
-- and matches against lower(COALESCE(username, telegram_username)).

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


-- Reload PostgREST schema cache so new function signatures are picked up
NOTIFY pgrst, 'reload schema';

COMMIT;
