-- ============================================
-- BUNDLE 3: FORUM & SOCIAL — Posts, Reactions, Notifications
-- Run AFTER 01-core.sql
-- ============================================


-- --- migration_forum_and_social.sql ---

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
DROP POLICY IF EXISTS "public_read_forum_categories" ON forum_categories;
CREATE POLICY "public_read_forum_categories" ON forum_categories
    FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_forum_categories" ON forum_categories;
CREATE POLICY "admin_all_forum_categories" ON forum_categories
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- forum_threads: public read non-deleted, verified users create, author+mod update, mod delete
DROP POLICY IF EXISTS "public_read_forum_threads" ON forum_threads;
CREATE POLICY "public_read_forum_threads" ON forum_threads
    FOR SELECT USING (
        is_deleted = false
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
DROP POLICY IF EXISTS "verified_insert_forum_threads" ON forum_threads;
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
DROP POLICY IF EXISTS "author_mod_update_forum_threads" ON forum_threads;
CREATE POLICY "author_mod_update_forum_threads" ON forum_threads
    FOR UPDATE USING (
        author_id = auth.uid()
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
DROP POLICY IF EXISTS "mod_admin_delete_forum_threads" ON forum_threads;
CREATE POLICY "mod_admin_delete_forum_threads" ON forum_threads
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- forum_posts: similar pattern
DROP POLICY IF EXISTS "public_read_forum_posts" ON forum_posts;
CREATE POLICY "public_read_forum_posts" ON forum_posts
    FOR SELECT USING (
        is_deleted = false
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
DROP POLICY IF EXISTS "verified_insert_forum_posts" ON forum_posts;
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
DROP POLICY IF EXISTS "author_mod_update_forum_posts" ON forum_posts;
CREATE POLICY "author_mod_update_forum_posts" ON forum_posts
    FOR UPDATE USING (
        author_id = auth.uid()
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
DROP POLICY IF EXISTS "mod_admin_delete_forum_posts" ON forum_posts;
CREATE POLICY "mod_admin_delete_forum_posts" ON forum_posts
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- moderators: public read (for badges), admin manage
DROP POLICY IF EXISTS "public_read_moderators" ON moderators;
CREATE POLICY "public_read_moderators" ON moderators
    FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_manage_moderators" ON moderators;
CREATE POLICY "admin_manage_moderators" ON moderators
    FOR ALL USING (
        EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- user_mod_actions: users read own, mods/admins read all and insert/update
DROP POLICY IF EXISTS "user_read_own_mod_actions" ON user_mod_actions;
CREATE POLICY "user_read_own_mod_actions" ON user_mod_actions
    FOR SELECT USING (
        user_id = auth.uid()
        OR EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );
DROP POLICY IF EXISTS "mod_insert_mod_actions" ON user_mod_actions;
CREATE POLICY "mod_insert_mod_actions" ON user_mod_actions
    FOR INSERT WITH CHECK (
        created_by = auth.uid()
        AND (EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
             OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()))
    );
DROP POLICY IF EXISTS "mod_update_mod_actions" ON user_mod_actions;
CREATE POLICY "mod_update_mod_actions" ON user_mod_actions
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
        OR EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
    );

-- ==========================================
-- STEP 6: Indexes for performance
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_forum_threads_category ON forum_threads(category_id) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_forum_threads_author ON forum_threads(author_id);
CREATE INDEX IF NOT EXISTS idx_forum_threads_pinned_created ON forum_threads(is_pinned DESC, created_at DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_forum_threads_last_post ON forum_threads(last_post_at DESC NULLS LAST) WHERE is_deleted = false AND is_pinned = false;
CREATE INDEX IF NOT EXISTS idx_forum_posts_thread_created ON forum_posts(thread_id, created_at ASC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_forum_posts_author ON forum_posts(author_id);
CREATE INDEX IF NOT EXISTS idx_moderators_user ON moderators(user_id);
CREATE INDEX IF NOT EXISTS idx_moderators_telegram_id ON moderators(telegram_id);
CREATE INDEX IF NOT EXISTS idx_mod_actions_user_active ON user_mod_actions(user_id, action_type, is_active) WHERE is_active = true;

-- ==========================================
-- STEP 7: Default forum categories
-- ==========================================

INSERT INTO forum_categories (name, slug, description, sort_order) VALUES
    ('РћР±СЃСѓР¶РґРµРЅРёРµ', 'discussion', 'РћР±С‰РµРµ РѕР±СЃСѓР¶РґРµРЅРёРµ РїСЂРѕРµРєС‚Р° NeuroBench', 0),
    ('РР Рё РіРµРЅРµСЂР°С†РёСЏ', 'ai-generation', 'РћР±СЃСѓР¶РґРµРЅРёРµ РР РјРѕРґРµР»РµР№, РіРµРЅРµСЂР°С†РёРё Рё Р±РµРЅС‡РјР°СЂРєРѕРІ', 1),
    ('РћС„С„С‚РѕРї', 'offtopic', 'РћР±С‰РµРЅРёРµ РЅР° СЃРІРѕР±РѕРґРЅС‹Рµ С‚РµРјС‹', 2)
ON CONFLICT (slug) DO NOTHING;

-- ==========================================
-- STEP 8: Helper function вЂ” is user moderator
-- ==========================================

DROP FUNCTION IF EXISTS public.is_moderator(UUID);
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
-- STEP 9: Helper function вЂ” is user banned/muted
-- ==========================================

DROP FUNCTION IF EXISTS public.get_user_restriction(UUID);
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
-- STEP 10: RPC вЂ” Get forum threads (paginated, with author info)
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
-- STEP 11: RPC вЂ” Get forum threads count
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
-- STEP 12: RPC вЂ” Get thread posts (paginated, with author info)
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
-- STEP 13: RPC вЂ” Get thread posts count
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
-- STEP 14: RPC вЂ” Create forum thread
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
-- STEP 15: RPC вЂ” Create forum post (reply)
-- ==========================================

DROP FUNCTION IF EXISTS public.create_forum_post(INTEGER, TEXT);
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
-- STEP 16: RPC вЂ” Update own post
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
-- STEP 17: RPC вЂ” Update own thread (title/content only)
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
-- STEP 18: RPC вЂ” Update profile bio
-- ==========================================

DROP FUNCTION IF EXISTS public.update_profile_bio(TEXT);
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
-- STEP 19: RPC вЂ” Moderator: pin/unpin thread
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
-- STEP 20: RPC вЂ” Moderator: lock/unlock thread
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
-- STEP 21: RPC вЂ” Moderator: soft-delete thread
-- ==========================================

DROP FUNCTION IF EXISTS public.mod_delete_thread(INTEGER);
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
-- STEP 22: RPC вЂ” Moderator: soft-delete post
-- ==========================================

DROP FUNCTION IF EXISTS public.mod_delete_post(INTEGER);
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
-- STEP 23: RPC вЂ” Moderator: ban user
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
-- STEP 24: RPC вЂ” Moderator: mute user
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
-- STEP 25: RPC вЂ” Moderator: unban user
-- ==========================================

DROP FUNCTION IF EXISTS public.mod_unban_user(UUID);
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
-- STEP 26: RPC вЂ” Moderator: unmute user
-- ==========================================

DROP FUNCTION IF EXISTS public.mod_unmute_user(UUID);
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
-- STEP 27: RPC вЂ” Admin: assign moderator
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_assign_moderator(UUID);
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
-- STEP 28: RPC вЂ” Admin: remove moderator
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_remove_moderator(UUID);
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
-- STEP 29: RPC вЂ” Admin: get moderators list
-- ==========================================

DROP FUNCTION IF EXISTS public.admin_get_moderators();
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
-- STEP 30: RPC вЂ” Get public profile info (for viewing other users)
-- ==========================================

DROP FUNCTION IF EXISTS public.get_public_profile(UUID);
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
-- STEP 31: RPC вЂ” Get user mod actions history (for moderators)
-- ==========================================

DROP FUNCTION IF EXISTS public.get_user_mod_actions(UUID);
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

DROP FUNCTION IF EXISTS public.cleanup_expired_mod_actions();
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
-- STEP 34: Fix admin_get_profiles вЂ” reload schema cache so SETOF profiles includes telegram_id
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


-- --- migration_social_v2.sql ---

-- ============================================
-- NeuroBench: Social Features V2 вЂ” Reactions, Notifications, Activity, @Mentions
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

DROP FUNCTION IF EXISTS public.get_unread_count();
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

DROP FUNCTION IF EXISTS public.mark_notifications_read();
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

DROP FUNCTION IF EXISTS public.create_forum_post(INTEGER, TEXT);
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
-- STEP 8: RPC вЂ” Resolve usernames to user_ids (for @mentions)
-- ==========================================

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
BEGIN
    RETURN QUERY
    SELECT p.telegram_username, p.user_id
    FROM profiles p
    WHERE lower(p.telegram_username) = ANY(p_usernames)
      AND p.is_verified = true;
END;
$$;

-- ==========================================
-- STEP 9: RPC вЂ” Final public profile shape
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
-- STEP 10: RPC вЂ” Create mention notifications
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
-- STEP 11: RPC вЂ” Get user recent activity (for profile)
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
-- STEP 12: RPC вЂ” Get user threads (for profile tabs)
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


-- --- migration_admin_like_reaction.sql ---

-- ============================================
-- NeuroBench: Admin Like Reaction + Default Role
-- ============================================
-- 1. Add 'admin_like' emoji вЂ” only admin/stmoderator can place it
-- 2. Ensure new users get role = 'member' on registration
-- ==========================================

-- STEP 1: Update toggle_post_reaction to support admin_like
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

-- STEP 2: Update check_reaction_achievements to handle admin_like
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
    v_result JSONB;
    v_granted TEXT[] := '{}';
BEGIN
    SELECT author_id INTO v_post_author FROM forum_posts WHERE id = p_post_id;
    IF v_post_author IS NULL THEN RETURN jsonb_build_object('granted', '{}'); END IF;

    -- silent_wave: 20+ reactions on post, 0 dislikes
    SELECT COUNT(*) INTO v_total_reactions FROM post_reactions WHERE post_id = p_post_id;
    SELECT COUNT(*) INTO v_dislike_count FROM post_reactions WHERE post_id = p_post_id AND emoji = 'dislike';
    IF v_total_reactions >= 20 AND v_dislike_count = 0 THEN
        SELECT (grant_achievement(v_post_author, 'silent_wave')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'silent_wave'); END IF;
    END IF;

    -- puke_gradient: 20+ puke reactions on one post
    SELECT COUNT(*) INTO v_puke_count FROM post_reactions WHERE post_id = p_post_id AND emoji = 'puke';
    IF v_puke_count >= 20 THEN
        SELECT (grant_achievement(v_post_author, 'puke_gradient')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'puke_gradient'); END IF;
    END IF;

    -- models_remember: reaction from mod/admin
    SELECT COALESCE(role, 'member') INTO v_reactor_role FROM profiles WHERE user_id = p_reactor_id;
    IF v_reactor_role IN ('admin', 'stmoderator', 'moderator') THEN
        SELECT (grant_achievement(v_post_author, 'models_remember')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'models_remember'); END IF;
    END IF;

    -- admin_like: grant 'admin_endorsement' achievement to post author (if achievement exists)
    SELECT COUNT(*) INTO v_admin_like_count FROM post_reactions WHERE post_id = p_post_id AND emoji = 'admin_like';
    IF v_admin_like_count >= 1 THEN
        IF EXISTS (SELECT 1 FROM achievements WHERE id = 'admin_endorsement') THEN
            SELECT (grant_achievement(v_post_author, 'admin_endorsement')->>'granted')::BOOLEAN INTO v_result;
            IF v_result THEN v_granted := array_append(v_granted, 'admin_endorsement'); END IF;
        END IF;
    END IF;

    -- first_reaction: reactor places their first ever reaction
    PERFORM grant_achievement(p_reactor_id, 'first_reaction');

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

-- STEP 3: Add 'admin_endorsement' achievement to catalog
INSERT INTO achievements (id, title, description, category, rarity, points, icon_emoji, max_supply, is_secret, sort_order)
VALUES (
    'admin_endorsement', 'РћРґРѕР±СЂРµРЅРёРµ Р°РґРјРёРЅР°', 'РџРѕР»СѓС‡РёС‚СЊ admin_like РЅР° РїРѕСЃС‚Рµ',
    'unique', 'unique', 50, 'рџ‘‘', NULL, FALSE, 28
)
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    rarity = EXCLUDED.rarity,
    points = EXCLUDED.points,
    icon_emoji = EXCLUDED.icon_emoji,
    is_secret = EXCLUDED.is_secret,
    sort_order = EXCLUDED.sort_order;

-- STEP 4: Update handle_new_user to set role = 'member' on registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_telegram_id TEXT;
    v_invite_code TEXT;
BEGIN
    v_telegram_id := NEW.raw_user_meta_data->>'telegram_id';
    v_invite_code := NEW.raw_user_meta_data->>'invite_code';

    INSERT INTO profiles (user_id, email, is_verified, pending_invite_code, telegram_id, role)
    VALUES (
        NEW.id,
        NEW.email,
        (v_telegram_id IS NOT NULL),
        CASE WHEN v_telegram_id IS NULL THEN v_invite_code ELSE NULL END,
        v_telegram_id,
        'member'
    );
    RETURN NEW;
END;
$$;

-- Backfill: set role = 'member' for any existing profiles with NULL role
UPDATE profiles SET role = 'member' WHERE role IS NULL;

