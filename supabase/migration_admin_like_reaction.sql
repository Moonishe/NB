-- ============================================
-- NeuroBench: Admin Like Reaction + Default Role
-- ============================================
-- 1. Add 'admin_like' emoji — only admin/stmoderator can place it
-- 2. Ensure new users get role = 'member' on registration
-- ==========================================

-- STEP 1: Update toggle_post_reaction to support admin_like
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
    'admin_endorsement', 'Одобрение админа', 'Получить admin_like на посте',
    'unique', 'unique', 50, '👑', NULL, FALSE, 28
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
