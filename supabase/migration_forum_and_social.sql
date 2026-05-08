-- ============================================
-- NeuroBench: Forum & Social Features Migration
-- ============================================
-- Run this in Supabase SQL Editor AFTER previous migrations
--
-- Adds: User profiles (bio), forum (categories, threads, posts),
--       moderators (telegram-bound, assigned by admin),
--       moderation actions (bans, mutes)
-- ============================================

-- ==========================================
-- STEP 1: Extend profiles table
-- ==========================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio TEXT;

-- ==========================================
-- STEP 2: Create forum tables
-- ==========================================

CREATE TABLE IF NOT EXISTS forum_categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    description TEXT,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE forum_categories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS forum_threads (
    id SERIAL PRIMARY KEY,
    category_id INTEGER REFERENCES forum_categories(id) ON DELETE SET NULL,
    author_id UUID REFERENCES profiles(user_id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    is_pinned BOOLEAN DEFAULT false,
    is_locked BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    deleted_by UUID,
    posts_count INTEGER DEFAULT 0,
    last_post_at TIMESTAMPTZ,
    last_post_by UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE forum_threads ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS forum_posts (
    id SERIAL PRIMARY KEY,
    thread_id INTEGER NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
    author_id UUID REFERENCES profiles(user_id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    is_deleted BOOLEAN DEFAULT false,
    deleted_by UUID,
    edited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE forum_posts ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- STEP 3: Create moderators table
-- ==========================================

CREATE TABLE IF NOT EXISTS moderators (
    id SERIAL PRIMARY KEY,
    user_id UUID UNIQUE NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    telegram_id TEXT,
    telegram_username TEXT,
    assigned_by UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE moderators ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- STEP 4: Create moderation actions table
-- ==========================================

CREATE TABLE IF NOT EXISTS user_mod_actions (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('ban', 'mute')),
    reason TEXT,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE user_mod_actions ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- STEP 5: RLS policies
-- ==========================================

-- forum_categories: public read, admin write
CREATE POLICY "public_read_forum_categories" ON forum_categories
    FOR SELECT USING (true);
CREATE POLICY "admin_all_forum_categories" ON forum_categories
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- forum_threads: public read non-deleted, verified users create, author+mod update, mod delete
CREATE POLICY "public_read_forum_threads" ON forum_threads
    FOR SELECT USING (
        is_deleted = false
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
CREATE POLICY "verified_insert_forum_threads" ON forum_threads
    FOR INSERT WITH CHECK (
        author_id = auth.uid()
        AND EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND is_verified = true)
        AND NOT EXISTS (
            SELECT 1 FROM user_mod_actions
            WHERE user_id = auth.uid()
            AND action_type IN ('ban', 'mute')
            AND is_active = true
            AND (expires_at IS NULL OR expires_at > now())
        )
    );
CREATE POLICY "author_mod_update_forum_threads" ON forum_threads
    FOR UPDATE USING (
        author_id = auth.uid()
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
CREATE POLICY "mod_admin_delete_forum_threads" ON forum_threads
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- forum_posts: similar pattern
CREATE POLICY "public_read_forum_posts" ON forum_posts
    FOR SELECT USING (
        is_deleted = false
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
CREATE POLICY "verified_insert_forum_posts" ON forum_posts
    FOR INSERT WITH CHECK (
        author_id = auth.uid()
        AND EXISTS (SELECT 1 FROM profiles WHERE user_id = auth.uid() AND is_verified = true)
        AND NOT EXISTS (
            SELECT 1 FROM user_mod_actions
            WHERE user_id = auth.uid()
            AND action_type IN ('ban', 'mute')
            AND is_active = true
            AND (expires_at IS NULL OR expires_at > now())
        )
        AND EXISTS (
            SELECT 1 FROM forum_threads
            WHERE id = thread_id AND is_locked = false AND is_deleted = false
        )
    );
CREATE POLICY "author_mod_update_forum_posts" ON forum_posts
    FOR UPDATE USING (
        author_id = auth.uid()
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
CREATE POLICY "mod_admin_delete_forum_posts" ON forum_posts
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- moderators: public read (for badges), admin manage
CREATE POLICY "public_read_moderators" ON moderators
    FOR SELECT USING (true);
CREATE POLICY "admin_manage_moderators" ON moderators
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- user_mod_actions: users read own, mods/admins read all and insert/update
CREATE POLICY "user_read_own_mod_actions" ON user_mod_actions
    FOR SELECT USING (
        user_id = auth.uid()
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
CREATE POLICY "mod_insert_mod_actions" ON user_mod_actions
    FOR INSERT WITH CHECK (
        created_by = auth.uid()
        AND (EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
             OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()))
    );
CREATE POLICY "mod_update_mod_actions" ON user_mod_actions
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- ==========================================
-- STEP 6: Indexes for performance
-- ==========================================

CREATE INDEX idx_forum_threads_category ON forum_threads(category_id) WHERE is_deleted = false;
CREATE INDEX idx_forum_threads_author ON forum_threads(author_id);
CREATE INDEX idx_forum_threads_pinned_created ON forum_threads(is_pinned DESC, created_at DESC) WHERE is_deleted = false;
CREATE INDEX idx_forum_threads_last_post ON forum_threads(last_post_at DESC NULLS LAST) WHERE is_deleted = false AND is_pinned = false;
CREATE INDEX idx_forum_posts_thread_created ON forum_posts(thread_id, created_at ASC) WHERE is_deleted = false;
CREATE INDEX idx_forum_posts_author ON forum_posts(author_id);
CREATE INDEX idx_moderators_user ON moderators(user_id);
CREATE INDEX idx_moderators_telegram_id ON moderators(telegram_id);
CREATE INDEX idx_mod_actions_user_active ON user_mod_actions(user_id, action_type, is_active) WHERE is_active = true;

-- ==========================================
-- STEP 7: Default forum categories
-- ==========================================

INSERT INTO forum_categories (name, slug, description, sort_order) VALUES
    ('Обсуждение', 'discussion', 'Общее обсуждение проекта NeuroBench', 0),
    ('ИИ и генерация', 'ai-generation', 'Обсуждение ИИ моделей, генерации и бенчмарков', 1),
    ('Оффтоп', 'offtopic', 'Общение на свободные темы', 2)
ON CONFLICT (slug) DO NOTHING;

-- ==========================================
-- STEP 8: Helper function — is user moderator
-- ==========================================

CREATE OR REPLACE FUNCTION public.is_moderator(p_user_id UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM moderators
        WHERE user_id = COALESCE(p_user_id, auth.uid())
    );
END;
$$;

-- ==========================================
-- STEP 9: Helper function — is user banned/muted
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_user_restriction(p_user_id UUID DEFAULT NULL)
RETURNS TABLE(action_type TEXT, reason TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT uma.action_type, uma.reason, uma.expires_at
    FROM user_mod_actions uma
    WHERE uma.user_id = COALESCE(p_user_id, auth.uid())
      AND uma.is_active = true
      AND (uma.expires_at IS NULL OR uma.expires_at > now())
    ORDER BY uma.action_type;
END;
$$;

-- ==========================================
-- STEP 10: RPC — Get forum threads (paginated, with author info)
-- ==========================================

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
    category_slug TEXT
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
        fc.slug
    FROM forum_threads ft
    LEFT JOIN profiles p ON p.user_id = ft.author_id
    LEFT JOIN forum_categories fc ON fc.id = ft.category_id
    WHERE ft.is_deleted = false
      AND (p_category_id IS NULL OR ft.category_id = p_category_id)
    ORDER BY ft.is_pinned DESC, ft.last_post_at DESC NULLS LAST, ft.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ==========================================
-- STEP 11: RPC — Get forum threads count
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_forum_threads_count(
    p_category_id INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM forum_threads
    WHERE is_deleted = false
      AND (p_category_id IS NULL OR category_id = p_category_id);
    RETURN v_count;
END;
$$;

-- ==========================================
-- STEP 12: RPC — Get thread posts (paginated, with author info)
-- ==========================================

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
    is_author_moderator BOOLEAN
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
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = fp.author_id)
    FROM forum_posts fp
    LEFT JOIN profiles p ON p.user_id = fp.author_id
    WHERE fp.thread_id = p_thread_id
      AND fp.is_deleted = false
    ORDER BY fp.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ==========================================
-- STEP 13: RPC — Get thread posts count
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_forum_thread_posts_count(
    p_thread_id INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM forum_posts
    WHERE thread_id = p_thread_id AND is_deleted = false;
    RETURN v_count;
END;
$$;

-- ==========================================
-- STEP 14: RPC — Create forum thread
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
DECLARE v_id INTEGER;
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

    INSERT INTO forum_threads (category_id, author_id, title, content, last_post_at)
    VALUES (p_category_id, auth.uid(), p_title, p_content, now())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ==========================================
-- STEP 15: RPC — Create forum post (reply)
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
DECLARE v_id INTEGER;
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

    RETURN v_id;
END;
$$;

-- ==========================================
-- STEP 16: RPC — Update own post
-- ==========================================

CREATE OR REPLACE FUNCTION public.update_forum_post(
    p_post_id INTEGER,
    p_content TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF length(p_content) < 1 OR length(p_content) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;
    UPDATE forum_posts
    SET content = p_content, edited_at = now()
    WHERE id = p_post_id AND author_id = auth.uid() AND is_deleted = false;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 17: RPC — Update own thread (title/content only)
-- ==========================================

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
BEGIN
    IF length(p_title) < 3 OR length(p_title) > 200 THEN
        RAISE EXCEPTION 'Title must be 3-200 characters';
    END IF;
    IF length(p_content) < 1 OR length(p_content) > 10000 THEN
        RAISE EXCEPTION 'Content must be 1-10000 characters';
    END IF;
    UPDATE forum_threads
    SET title = p_title, content = p_content, updated_at = now()
    WHERE id = p_thread_id AND author_id = auth.uid() AND is_deleted = false;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 18: RPC — Update profile bio
-- ==========================================

CREATE OR REPLACE FUNCTION public.update_profile_bio(p_bio TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF length(p_bio) > 500 THEN
        RAISE EXCEPTION 'Bio must be at most 500 characters';
    END IF;
    UPDATE profiles SET bio = p_bio WHERE user_id = auth.uid();
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 19: RPC — Moderator: pin/unpin thread
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_pin_thread(
    p_thread_id INTEGER,
    p_pin BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE forum_threads SET is_pinned = p_pin, updated_at = now()
    WHERE id = p_thread_id AND is_deleted = false;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 20: RPC — Moderator: lock/unlock thread
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_lock_thread(
    p_thread_id INTEGER,
    p_lock BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE forum_threads SET is_locked = p_lock, updated_at = now()
    WHERE id = p_thread_id AND is_deleted = false;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 21: RPC — Moderator: soft-delete thread
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_delete_thread(p_thread_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE forum_threads SET is_deleted = true, deleted_by = auth.uid(), updated_at = now()
    WHERE id = p_thread_id AND is_deleted = false;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 22: RPC — Moderator: soft-delete post
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_delete_post(p_post_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_thread_id INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    SELECT thread_id INTO v_thread_id FROM forum_posts WHERE id = p_post_id AND is_deleted = false;
    IF v_thread_id IS NULL THEN RETURN false; END IF;
    UPDATE forum_posts SET is_deleted = true, deleted_by = auth.uid()
    WHERE id = p_post_id AND is_deleted = false;
    IF NOT FOUND THEN RETURN false; END IF;
    UPDATE forum_threads SET posts_count = greatest(posts_count - 1, 0), updated_at = now()
    WHERE id = v_thread_id;
    RETURN true;
END;
$$;

-- ==========================================
-- STEP 23: RPC — Moderator: ban user
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_ban_user(
    p_user_id UUID,
    p_reason TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    IF p_user_id = auth.uid() THEN RETURN false; END IF;
    IF EXISTS (SELECT 1 FROM moderators WHERE user_id = p_user_id) THEN RETURN false; END IF;
    IF EXISTS (SELECT 1 FROM admin_users WHERE user_id = p_user_id) THEN RETURN false; END IF;
    INSERT INTO user_mod_actions (user_id, action_type, reason, expires_at, created_by)
    VALUES (p_user_id, 'ban', p_reason, p_expires_at, auth.uid());
    RETURN true;
END;
$$;

-- ==========================================
-- STEP 24: RPC — Moderator: mute user
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_mute_user(
    p_user_id UUID,
    p_reason TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    IF p_user_id = auth.uid() THEN RETURN false; END IF;
    IF EXISTS (SELECT 1 FROM moderators WHERE user_id = p_user_id) THEN RETURN false; END IF;
    IF EXISTS (SELECT 1 FROM admin_users WHERE user_id = p_user_id) THEN RETURN false; END IF;
    INSERT INTO user_mod_actions (user_id, action_type, reason, expires_at, created_by)
    VALUES (p_user_id, 'mute', p_reason, p_expires_at, auth.uid());
    RETURN true;
END;
$$;

-- ==========================================
-- STEP 25: RPC — Moderator: unban user
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_unban_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE user_mod_actions SET is_active = false
    WHERE user_id = p_user_id AND action_type = 'ban' AND is_active = true;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 26: RPC — Moderator: unmute user
-- ==========================================

CREATE OR REPLACE FUNCTION public.mod_unmute_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    UPDATE user_mod_actions SET is_active = false
    WHERE user_id = p_user_id AND action_type = 'mute' AND is_active = true;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 27: RPC — Admin: assign moderator
-- ==========================================

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

-- ==========================================
-- STEP 28: RPC — Admin: remove moderator
-- ==========================================

CREATE OR REPLACE FUNCTION public.admin_remove_moderator(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN false;
    END IF;
    DELETE FROM moderators WHERE user_id = p_user_id;
    RETURN FOUND;
END;
$$;

-- ==========================================
-- STEP 29: RPC — Admin: get moderators list
-- ==========================================

CREATE OR REPLACE FUNCTION public.admin_get_moderators()
RETURNS TABLE(
    id INTEGER,
    user_id UUID,
    telegram_id TEXT,
    telegram_username TEXT,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    assigner_email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT m.id, m.user_id, m.telegram_id, m.telegram_username, m.assigned_by, m.created_at,
           COALESCE(p.email, '') AS assigner_email
    FROM moderators m
    LEFT JOIN profiles p ON p.user_id = m.assigned_by
    ORDER BY m.created_at DESC;
END;
$$;

-- ==========================================
-- STEP 30: RPC — Get public profile info (for viewing other users)
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS TABLE(
    user_id UUID,
    telegram_username TEXT,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_photo_url TEXT,
    bio TEXT,
    is_moderator BOOLEAN,
    created_at TIMESTAMPTZ,
    threads_count BIGINT,
    posts_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.user_id,
        p.telegram_username,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_photo_url,
        p.bio,
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = p.user_id),
        p.created_at,
        (SELECT COUNT(*) FROM forum_threads WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*) FROM forum_posts WHERE author_id = p.user_id AND is_deleted = false)
    FROM profiles p
    WHERE p.user_id = p_user_id AND p.is_verified = true;
END;
$$;

-- ==========================================
-- STEP 31: RPC — Get user mod actions history (for moderators)
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_user_mod_actions(p_user_id UUID)
RETURNS TABLE(
    id INTEGER,
    action_type TEXT,
    reason TEXT,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN,
    created_by UUID,
    created_at TIMESTAMPTZ,
    creator_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT uma.id, uma.action_type, uma.reason, uma.expires_at, uma.is_active,
           uma.created_by, uma.created_at,
           COALESCE(p2.telegram_username, p2.telegram_first_name, '') AS creator_name
    FROM user_mod_actions uma
    LEFT JOIN profiles p2 ON p2.user_id = uma.created_by
    WHERE uma.user_id = p_user_id
    ORDER BY uma.created_at DESC;
END;
$$;

-- ==========================================
-- STEP 32: Cleanup expired mod actions (call occasionally)
-- ==========================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_mod_actions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count INTEGER;
BEGIN
    UPDATE user_mod_actions
    SET is_active = false
    WHERE is_active = true AND expires_at IS NOT NULL AND expires_at <= now();
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ==========================================
-- STEP 33: Update get_user_display_name to include mod/ban status
-- ==========================================

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
        COALESCE(p.telegram_first_name, split_part(p.email, '@', 1)) AS display_name,
        p.is_verified,
        p.has_generated_invite,
        ic.code AS generated_code,
        ic.use_count AS invite_use_count,
        p.bio,
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

-- ==========================================
-- STEP 34: Fix admin_get_profiles — reload schema cache so SETOF profiles includes telegram_id
-- ==========================================

-- Restore original simple definition (SETOF profiles returns ALL columns automatically)
DROP FUNCTION IF EXISTS public.admin_get_profiles();

CREATE OR REPLACE FUNCTION public.admin_get_profiles()
RETURNS SETOF profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RETURN;
    END IF;
    RETURN QUERY SELECT * FROM profiles ORDER BY created_at DESC;
END;
$$;

-- ==========================================
-- STEP 35: Reload PostGREST schema cache
-- ==========================================

NOTIFY pgrst, 'reload schema';
