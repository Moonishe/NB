-- UID system: sequential user IDs (1, 2, 3, ...)
-- Run this migration to add uid column to profiles and auto-assign on registration

-- 1. Create sequence
CREATE SEQUENCE IF NOT EXISTS user_uid_seq START 1;

-- 2. Add uid column
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS uid INTEGER UNIQUE;

-- 3. Backfill existing users (ordered by created_at)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT user_id FROM profiles ORDER BY created_at ASC
    LOOP
        UPDATE profiles SET uid = nextval('user_uid_seq') WHERE user_id = r.user_id AND uid IS NULL;
    END LOOP;
END;
$$;

-- 4. Set default for new users
ALTER TABLE profiles ALTER COLUMN uid SET DEFAULT nextval('user_uid_seq');

-- 5. Update trigger to include uid in INSERT (it will use the default)
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

    INSERT INTO profiles (user_id, email, is_verified, pending_invite_code, telegram_id)
    VALUES (
        NEW.id,
        NEW.email,
        (v_telegram_id IS NOT NULL),
        CASE WHEN v_telegram_id IS NULL THEN v_invite_code ELSE NULL END,
        v_telegram_id
    );
    RETURN NEW;
END;
$$;

-- 6. Update get_public_profile to return uid
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
        p.uid,
        p.telegram_first_name,
        p.telegram_last_name,
        p.telegram_username,
        p.telegram_photo_url,
        p.bio,
        (p.role IN ('moderator', 'stmoderator', 'admin')) AS is_moderator,
        p.is_verified,
        p.role,
        p.created_at,
        (SELECT COUNT(*) FROM forum_threads WHERE author_id = p.user_id AND is_deleted = false),
        (SELECT COUNT(*) FROM forum_posts WHERE author_id = p.user_id AND is_deleted = false)
    FROM profiles p
    WHERE p.user_id = p_user_id;
END;
$$;

-- 7. Update get_user_display_name to return uid
CREATE OR REPLACE FUNCTION public.get_user_display_name(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    is_banned BOOLEAN,
    is_muted BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT,
    invite_use_count INTEGER,
    role TEXT
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
        (p.role IN ('moderator', 'stmoderator', 'admin')) AS is_moderator,
        p.is_verified,
        EXISTS (SELECT 1 FROM user_mod_actions WHERE user_id = p.user_id AND action_type = 'ban' AND is_active = true AND (expires_at IS NULL OR expires_at > now())) AS is_banned,
        EXISTS (SELECT 1 FROM user_mod_actions WHERE user_id = p.user_id AND action_type = 'mute' AND is_active = true AND (expires_at IS NULL OR expires_at > now())) AS is_muted,
        p.has_generated_invite,
        gen_ic.code AS generated_code,
        (SELECT COUNT(*)::int FROM invite_code_uses WHERE invite_code_id = p.generated_invite_code_id) AS invite_use_count,
        p.role
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = p_user_id;
END;
$$;

-- 8. Update get_forum_threads to return author_uid
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
    author_uid INTEGER
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
        p.uid
    FROM forum_threads ft
    LEFT JOIN profiles p ON p.user_id = ft.author_id
    LEFT JOIN forum_categories fc ON fc.id = ft.category_id
    WHERE ft.is_deleted = false
      AND (p_category_id IS NULL OR ft.category_id = p_category_id)
    ORDER BY ft.is_pinned DESC, ft.last_post_at DESC NULLS LAST, ft.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 9. Update get_forum_thread_posts to return author_uid
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
    author_uid INTEGER
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
        EXISTS (SELECT 1 FROM moderators m WHERE m.user_id = fp.author_id),
        p.uid
    FROM forum_posts fp
    LEFT JOIN profiles p ON p.user_id = fp.author_id
    WHERE fp.thread_id = p_thread_id
      AND fp.is_deleted = false
    ORDER BY fp.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 10. Index for fast UID lookups
CREATE INDEX IF NOT EXISTS idx_profiles_uid ON profiles(uid);

-- 11. Update bio limit to 120 chars
CREATE OR REPLACE FUNCTION public.update_profile_bio(p_bio TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF length(p_bio) > 44 THEN
        RAISE EXCEPTION 'Bio must be at most 44 characters';
    END IF;
    UPDATE profiles SET bio = p_bio WHERE user_id = auth.uid();
    RETURN FOUND;
END;
$$;

-- 12. Invite quota per role: member=1, beta=3, alpha=10, moderator+=unlimited
CREATE OR REPLACE FUNCTION public.get_invite_max(p_role TEXT)
RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN CASE p_role
        WHEN 'admin' THEN 999999
        WHEN 'stmoderator' THEN 999999
        WHEN 'moderator' THEN 999999
        WHEN 'alpha' THEN 10
        WHEN 'beta' THEN 3
        ELSE 1
    END;
END;
$$;

-- 13. Rewrite generate_user_invite_code: multiple invites, delete oldest unused if at limit
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

-- 14. Update get_user_display_name to return invite quota info
CREATE OR REPLACE FUNCTION public.get_user_display_name(p_user_id UUID)
RETURNS TABLE (
    user_id UUID,
    uid INTEGER,
    telegram_first_name TEXT,
    telegram_last_name TEXT,
    telegram_username TEXT,
    telegram_photo_url TEXT,
    is_moderator BOOLEAN,
    is_verified BOOLEAN,
    is_banned BOOLEAN,
    is_muted BOOLEAN,
    has_generated_invite BOOLEAN,
    generated_code TEXT,
    invite_use_count INTEGER,
    role TEXT,
    invite_max INTEGER,
    invite_active_count INTEGER,
    verified_by_name TEXT
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
        (p.role IN ('moderator', 'stmoderator', 'admin')) AS is_moderator,
        p.is_verified,
        EXISTS (SELECT 1 FROM user_mod_actions WHERE user_id = p.user_id AND action_type = 'ban' AND is_active = true AND (expires_at IS NULL OR expires_at > now())) AS is_banned,
        EXISTS (SELECT 1 FROM user_mod_actions WHERE user_id = p.user_id AND action_type = 'mute' AND is_active = true AND (expires_at IS NULL OR expires_at > now())) AS is_muted,
        p.has_generated_invite,
        gen_ic.code AS generated_code,
        (SELECT COUNT(*)::int FROM invite_code_uses WHERE invite_code_id = p.generated_invite_code_id) AS invite_use_count,
        p.role,
        get_invite_max(p.role) AS invite_max,
        (SELECT COUNT(*)::int FROM invite_codes WHERE created_by = p.user_id AND is_admin_code = false AND used_by IS NULL AND (expires_at IS NULL OR expires_at > now())) AS invite_active_count,
        (SELECT COALESCE(vp.telegram_username, vp.telegram_first_name, 'Админ')
         FROM profiles vp WHERE vp.user_id = p.verified_by) AS verified_by_name
    FROM profiles p
    LEFT JOIN invite_codes gen_ic ON gen_ic.id = p.generated_invite_code_id
    WHERE p.user_id = p_user_id;
END;
$$;

-- 15. Add verified_by column to profiles (tracks which admin verified)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- 16. Add expires_at column to invite_codes (5 minute TTL)
ALTER TABLE invite_codes ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- 17. Update generate_user_invite_code to set 5-minute TTL
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
    SELECT role INTO v_role FROM profiles WHERE user_id = v_user_id AND is_verified = true;
    IF v_role IS NULL THEN RETURN NULL; END IF;

    v_max := get_invite_max(v_role);

    SELECT COUNT(*) INTO v_active_count
    FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND used_by IS NULL
      AND (expires_at IS NULL OR expires_at > now());

    IF v_active_count >= v_max THEN
        SELECT id INTO v_oldest_id
        FROM invite_codes
        WHERE created_by = v_user_id
          AND is_admin_code = false
          AND used_by IS NULL
          AND (expires_at IS NULL OR expires_at > now())
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_oldest_id IS NOT NULL THEN
            DELETE FROM invite_codes WHERE id = v_oldest_id;
        END IF;
    END IF;

    -- Cleanup expired invites for this user
    DELETE FROM invite_codes
    WHERE created_by = v_user_id
      AND is_admin_code = false
      AND used_by IS NULL
      AND expires_at IS NOT NULL
      AND expires_at <= now();

    v_new_code := upper(substr(md5(random()::text), 1, 8));

    INSERT INTO invite_codes (code, created_by, is_admin_code, expires_at)
    VALUES (v_new_code, v_user_id, false, now() + interval '5 minutes')
    RETURNING id INTO v_invite_id;

    UPDATE profiles
    SET has_generated_invite = true, generated_invite_code_id = v_invite_id
    WHERE user_id = v_user_id;

    RETURN v_new_code;
END;
$$;

-- 18. Update claim_invite_code to check expiry
CREATE OR REPLACE FUNCTION public.claim_invite_code(p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite invite_codes%ROWTYPE;
    v_user_id UUID := auth.uid();
BEGIN
    SELECT * INTO v_invite FROM invite_codes
    WHERE code = p_code AND used_by IS NULL AND is_admin_code = false;

    IF v_invite IS NULL THEN RETURN false; END IF;

    IF v_invite.expires_at IS NOT NULL AND v_invite.expires_at <= now() THEN
        DELETE FROM invite_codes WHERE id = v_invite.id;
        RETURN false;
    END IF;

    IF v_invite.max_uses IS NOT NULL AND v_invite.use_count >= v_invite.max_uses THEN
        RETURN false;
    END IF;

    UPDATE invite_codes
    SET use_count = use_count + 1,
        used_by = CASE WHEN max_uses IS NULL OR max_uses = 1 THEN v_user_id ELSE used_by END,
        used_at = CASE WHEN max_uses IS NULL OR max_uses = 1 THEN now() ELSE used_at END
    WHERE id = v_invite.id;

    UPDATE profiles SET used_invite_code_id = v_invite.id WHERE user_id = v_user_id;

    INSERT INTO invite_code_uses (invite_code_id, user_id)
    VALUES (v_invite.id, v_user_id);

    RETURN true;
END;
$$;
