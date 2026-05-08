-- ============================================
-- NeuroBench: Social Features V2 — Reactions, Notifications, Activity, @Mentions
-- ============================================
-- Run AFTER all previous migrations (migration_uid_system.sql, migration_roles.sql, etc.)
-- ============================================

-- ==========================================
-- STEP 1: Post reactions table
-- ==========================================

CREATE TABLE IF NOT EXISTS post_reactions (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL REFERENCES forum_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    emoji TEXT NOT NULL CHECK (emoji IN ('like','dislike','fire','puke','brain','emotion')),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(post_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_post_reactions_post ON post_reactions(post_id);
CREATE INDEX IF NOT EXISTS idx_post_reactions_user ON post_reactions(user_id);

ALTER TABLE post_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_post_reactions" ON post_reactions;
CREATE POLICY "public_read_post_reactions" ON post_reactions
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "user_manage_own_reactions" ON post_reactions;
CREATE POLICY "user_manage_own_reactions" ON post_reactions
    FOR ALL USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('mention','reaction','reply')),
    from_user_id UUID REFERENCES profiles(user_id) ON DELETE SET NULL,
    ref_thread_id INTEGER,
    ref_post_id INTEGER,
    emoji TEXT,
    snippet TEXT,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- STEP 2: Toggle reaction RPC
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
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE user_id = v_uid AND is_verified = true) THEN
        RAISE EXCEPTION 'Not verified';
    END IF;
    IF p_emoji NOT IN ('like','dislike','fire','puke','brain','emotion') THEN
        RAISE EXCEPTION 'Invalid emoji';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM forum_posts WHERE id = p_post_id AND is_deleted = false) THEN
        RAISE EXCEPTION 'Post not found';
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM post_reactions WHERE post_id = p_post_id AND user_id = v_uid AND emoji = p_emoji
    ) INTO v_exists;

    IF v_exists THEN
        DELETE FROM post_reactions WHERE post_id = p_post_id AND user_id = v_uid AND emoji = p_emoji;
        RETURN jsonb_build_object('action', 'removed', 'emoji', p_emoji);
    ELSE
        INSERT INTO post_reactions (post_id, user_id, emoji) VALUES (p_post_id, v_uid, p_emoji);
        -- Create notification for post author
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
        RETURN jsonb_build_object('action', 'added', 'emoji', p_emoji);
    END IF;
END;
$$;

-- ==========================================
-- STEP 3: Update get_forum_thread_posts to include reactions
-- ==========================================

DROP FUNCTION IF EXISTS public.get_forum_thread_posts(INTEGER, INTEGER, INTEGER);

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
    author_role TEXT,
    reactions JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
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
        p.role,
        (
            SELECT jsonb_object_agg(e.emoji, jsonb_build_object(
                'count', e.cnt,
                'me', COALESCE((SELECT true FROM post_reactions pr2 WHERE pr2.post_id = fp.id AND pr2.user_id = v_uid AND pr2.emoji = e.emoji), false)
            ))
            FROM (
                SELECT pr.emoji, COUNT(*) AS cnt
                FROM post_reactions pr
                WHERE pr.post_id = fp.id
                GROUP BY pr.emoji
            ) e
        )
    FROM forum_posts fp
    LEFT JOIN profiles p ON p.user_id = fp.author_id
    WHERE fp.thread_id = p_thread_id
      AND fp.is_deleted = false
    ORDER BY fp.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ==========================================
-- STEP 4: Update get_forum_threads to include author_role
-- ==========================================

DROP FUNCTION IF EXISTS public.get_forum_threads(INTEGER, INTEGER, INTEGER);

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
        p.role
    FROM forum_threads ft
    LEFT JOIN profiles p ON p.user_id = ft.author_id
    LEFT JOIN forum_categories fc ON fc.id = ft.category_id
    WHERE ft.is_deleted = false
      AND (p_category_id IS NULL OR ft.category_id = p_category_id)
    ORDER BY ft.is_pinned DESC, ft.last_post_at DESC NULLS LAST, ft.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_read_own_notifications" ON notifications;
CREATE POLICY "user_read_own_notifications" ON notifications
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user_update_own_notifications" ON notifications;
CREATE POLICY "user_update_own_notifications" ON notifications
    FOR UPDATE USING (user_id = auth.uid());

-- ==========================================
-- STEP 6: Notification RPCs
-- ==========================================

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
BEGIN
    RETURN QUERY
    SELECT
        n.id, n.type, n.from_user_id,
        p.telegram_username,
        p.telegram_first_name,
        p.telegram_photo_url,
        n.ref_thread_id, n.ref_post_id,
        n.emoji, n.snippet, n.is_read, n.created_at
    FROM notifications n
    LEFT JOIN profiles p ON p.user_id = n.from_user_id
    WHERE n.user_id = auth.uid()
    ORDER BY n.created_at DESC
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unread_count()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM notifications
    WHERE user_id = auth.uid() AND is_read = false;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notifications_read()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INTEGER;
BEGIN
    UPDATE notifications SET is_read = true
    WHERE user_id = auth.uid() AND is_read = false;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ==========================================
-- STEP 7: Update create_forum_post to send reply notifications
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
-- STEP 8: RPC — Resolve usernames to user_ids (for @mentions)
-- ==========================================

CREATE OR REPLACE FUNCTION public.resolve_usernames(p_usernames TEXT[])
RETURNS TABLE(
    username TEXT,
    user_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT p.telegram_username, p.user_id
    FROM profiles p
    WHERE lower(p.telegram_username) = ANY(p_usernames)
      AND p.is_verified = true;
END;
$$;

-- ==========================================
-- STEP 9: RPC — Final public profile shape
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
    bio TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    role TEXT,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT,
    reactions_given_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.user_id,
        p.uid,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_username,
        p.telegram_photo_url,
        p.bio,
        (COALESCE(p.role, 'member') IN ('moderator', 'stmoderator', 'admin')) AS is_moderator,
        p.is_verified,
        COALESCE(p.role, 'member') AS role,
        p.created_at,
        (SELECT COUNT(*) FROM forum_threads WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*) FROM forum_posts WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*) FROM post_reactions WHERE user_id = p.user_id)
    FROM profiles p
    WHERE p.user_id = p_user_id;
END;
$$;

-- ==========================================
-- STEP 10: RPC — Create mention notifications
-- ==========================================

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
BEGIN
    IF auth.uid() IS NULL THEN RETURN 0; END IF;

    SELECT left(content, 80) INTO v_snippet FROM forum_posts WHERE id = p_post_id;

    FOREACH v_uid IN ARRAY p_mentioned_user_ids LOOP
        IF v_uid != auth.uid() THEN
            INSERT INTO notifications (user_id, type, from_user_id, ref_thread_id, ref_post_id, snippet)
            VALUES (v_uid, 'mention', auth.uid(), p_thread_id, p_post_id, v_snippet)
            ON CONFLICT DO NOTHING;
            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;

-- ==========================================
-- STEP 11: RPC — Get user recent activity (for profile)
-- ==========================================

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
BEGIN
    RETURN QUERY
    (
        SELECT
            'thread'::TEXT AS activity_type,
            ft.id AS thread_id,
            ft.title AS thread_title,
            NULL::INTEGER AS post_id,
            left(ft.content, 120) AS preview,
            NULL::TEXT AS emoji,
            ft.created_at
        FROM forum_threads ft
        WHERE ft.author_id = p_user_id AND ft.is_deleted = false
    )
    UNION ALL
    (
        SELECT
            'post'::TEXT AS activity_type,
            fp.thread_id,
            ft2.title AS thread_title,
            fp.id AS post_id,
            left(fp.content, 120) AS preview,
            NULL::TEXT AS emoji,
            fp.created_at
        FROM forum_posts fp
        LEFT JOIN forum_threads ft2 ON ft2.id = fp.thread_id
        WHERE fp.author_id = p_user_id AND fp.is_deleted = false
    )
    UNION ALL
    (
        SELECT
            'reaction'::TEXT AS activity_type,
            fp3.thread_id,
            ft3.title AS thread_title,
            pr.post_id,
            left(fp3.content, 120) AS preview,
            pr.emoji AS emoji,
            pr.created_at
        FROM post_reactions pr
        LEFT JOIN forum_posts fp3 ON fp3.id = pr.post_id AND fp3.is_deleted = false
        LEFT JOIN forum_threads ft3 ON ft3.id = fp3.thread_id
        WHERE pr.user_id = p_user_id
    )
    ORDER BY created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ==========================================
-- STEP 12: RPC — Get user threads (for profile tabs)
-- ==========================================

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
BEGIN
    RETURN QUERY
    SELECT
        ft.id, ft.title, ft.posts_count, ft.created_at,
        fc.name
    FROM forum_threads ft
    LEFT JOIN forum_categories fc ON fc.id = ft.category_id
    WHERE ft.author_id = p_user_id AND ft.is_deleted = false
    ORDER BY ft.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ==========================================
-- STEP 13: Reload PostgREST schema cache
-- ==========================================

NOTIFY pgrst, 'reload schema';
