-- ============================================
-- BUNDLE 4: ACHIEVEMENTS
-- Run AFTER 01-core.sql
-- ============================================


-- --- migration_achievements.sql ---

-- ============================================
-- NeuroBench: Achievements System
-- ============================================
-- Run AFTER migration_social_v2.sql
-- ============================================

-- ==========================================
-- STEP 1: Achievements catalog table
-- ==========================================

CREATE TABLE IF NOT EXISTS achievements (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    description     TEXT NOT NULL,
    category        TEXT NOT NULL CHECK (category IN ('starter', 'rare', 'unique', 'secret_limited')),
    rarity          TEXT NOT NULL CHECK (rarity IN ('common', 'rare', 'unique', 'limited')),
    points          INT NOT NULL DEFAULT 0,
    icon_emoji      TEXT,
    max_supply      INT,
    is_secret       BOOLEAN DEFAULT FALSE,
    sort_order      INT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ==========================================
-- STEP 1b: Migrate rarity for existing databases
-- ==========================================

DO $$
BEGIN
    -- Update existing data to new rarity values
    UPDATE achievements SET rarity = 'unique' WHERE rarity IN ('epic', 'legendary');
    UPDATE achievements SET rarity = 'limited' WHERE rarity = 'mythic';

    -- Drop old CHECK constraint and add new one
    ALTER TABLE achievements DROP CONSTRAINT IF EXISTS achievements_rarity_check;
    ALTER TABLE achievements ADD CONSTRAINT achievements_rarity_check
        CHECK (rarity IN ('common', 'rare', 'unique', 'limited'));
END $$;

-- ==========================================
-- STEP 2: User achievements junction table
-- ==========================================

CREATE TABLE IF NOT EXISTS user_achievements (
    id              SERIAL PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    achievement_id  TEXT NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    unlocked_at     TIMESTAMPTZ DEFAULT NOW(),
    is_showcased    BOOLEAN DEFAULT FALSE,
    UNIQUE(user_id, achievement_id)
);

CREATE INDEX IF NOT EXISTS idx_user_achievements_user ON user_achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_achievements_showcased ON user_achievements(user_id) WHERE is_showcased = TRUE;
CREATE INDEX IF NOT EXISTS idx_user_achievements_achievement ON user_achievements(achievement_id);

ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_user_achievements" ON user_achievements;
CREATE POLICY "public_read_user_achievements" ON user_achievements
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "user_manage_own_achievements" ON user_achievements;
CREATE POLICY "user_manage_own_achievements" ON user_achievements
    FOR ALL USING (user_id = auth.uid());

-- ==========================================
-- STEP 3: Seed achievements catalog
-- ==========================================

DELETE FROM user_achievements WHERE achievement_id = 'first_post';
DELETE FROM achievements WHERE id = 'first_post';

INSERT INTO achievements (id, title, description, category, rarity, points, icon_emoji, max_supply, is_secret, sort_order) VALUES
    ('welcome',            'Р”РѕР±СЂРѕ РїРѕР¶Р°Р»РѕРІР°С‚СЊ',       'Р—Р°СЂРµРіРёСЃС‚СЂРёСЂРѕРІР°С‚СЊСЃСЏ РЅР° СЃР°Р№С‚Рµ',                                   'starter',       'common',    5,   'рџ‘‹', NULL,  FALSE, 1),
    ('first_referral',     'РџРµСЂРІС‹Р№ РїСЂРёРіР»Р°С€С‘РЅРЅС‹Р№',    'РџСЂРёРіР»Р°СЃРёС‚СЊ 1 РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ',                                        'starter',       'common',    10,  'рџ¤ќ', NULL,  FALSE, 2),
    ('first_thread',       'РџРµСЂРІС‹Р№ С‚СЂРµРґ',            'РЎРѕР·РґР°С‚СЊ РїРµСЂРІС‹Р№ С‚СЂРµРґ',                                           'starter',       'common',    10,  'рџ“Ў', NULL,  FALSE, 3),
    ('first_reaction',     'РџРµСЂРІР°СЏ СЂРµР°РєС†РёСЏ',         'РџРѕСЃС‚Р°РІРёС‚СЊ РїРµСЂРІСѓСЋ СЂРµР°РєС†РёСЋ',                                      'starter',       'common',    5,   'вњЁ', NULL,  FALSE, 4),
    ('profile_tuned',      'РџСЂРѕС„РёР»СЊ Р·Р°РїРѕР»РЅРµРЅ',       'Р—Р°РїРѕР»РЅРёС‚СЊ РїСЂРѕС„РёР»СЊ',                                             'starter',       'common',    10,  'вљ™пёЏ', NULL,  FALSE, 5),
    ('daily_login',        '3 РґРЅСЏ РїРѕРґСЂСЏРґ',           'Р—Р°Р№С‚Рё РЅР° СЃР°Р№С‚ 3 РґРЅСЏ РїРѕРґСЂСЏРґ',                                    'starter',       'common',    15,  'рџ”‹', NULL,  FALSE, 6),
    ('first_comment',      'РџРµСЂРІС‹Р№ РєРѕРјРјРµРЅС‚Р°СЂРёР№',     'РќР°РїРёСЃР°С‚СЊ РїРµСЂРІС‹Р№ РєРѕРјРјРµРЅС‚Р°СЂРёР№',                                   'starter',       'common',    5,   'пїЅ', NULL,  FALSE, 7),
    ('first_model_rate',   'РџРµСЂРІР°СЏ РѕС†РµРЅРєР° РјРѕРґРµР»Рё',   'РћС†РµРЅРёС‚СЊ РјРѕРґРµР»СЊ РїРµСЂРІС‹Р№ СЂР°Р·',                                     'starter',       'common',    10,  'в­ђ', NULL,  FALSE, 8),
    ('first_mention',      'РЈРїРѕРјРёРЅР°РЅРёРµ',             'РЈРїРѕРјСЏРЅСѓС‚СЊ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ С‡РµСЂРµР· @',                                'starter',       'common',    5,   'рџ“Ј', NULL,  FALSE, 9),
    ('first_edit',         'Р РµРґР°РєС‚РѕСЂ',               'РћС‚СЂРµРґР°РєС‚РёСЂРѕРІР°С‚СЊ СЃРІРѕР№ РїРѕСЃС‚ РёР»Рё РєРѕРјРјРµРЅС‚Р°СЂРёР№',                      'starter',       'common',    5,   'вњЏпёЏ', NULL,  FALSE, 10),
    ('silent_wave',        'Р‘РµР· РЅРµРіР°С‚РёРІР°',           'РџРѕР»СѓС‡РёС‚СЊ 20 СЂРµР°РєС†РёР№ РЅР° РїРѕСЃС‚Рµ Р±РµР· dislike',                      'rare',          'rare',      25,  'рџЊЉ', NULL,  FALSE, 11),
    ('puke_gradient',      'РќРµСЃРІР°СЂРµРЅРёРµ Р¶РµР»СѓРґРєР°',     'РџРѕР»СѓС‡РёС‚СЊ 20 puke-СЂРµР°РєС†РёР№ РЅР° РѕРґРЅРѕРј РїРѕСЃС‚Рµ',                      'rare',          'rare',      30,  'рџ¤®', NULL,  FALSE, 12),
    ('binding_layer',      'РўСЂРё РїСЂРёРіР»Р°С€РµРЅРёСЏ',        'РџСЂРёРіР»Р°СЃРёС‚СЊ 3 РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№',                                   'rare',          'rare',      20,  'пїЅ', NULL,  FALSE, 13),
    ('models_remember',    'Р РµР°РєС†РёСЏ РјРѕРґРµСЂР°С‚РѕСЂР°',     'РџРѕР»СѓС‡РёС‚СЊ СЂРµР°РєС†РёСЋ РѕС‚ РјРѕРґРµСЂР°С‚РѕСЂР° РёР»Рё Р°РґРјРёРЅР°',                     'rare',          'rare',      35,  'рџ¤–', NULL,  FALSE, 14),
    ('before_public_launch','Р”Рѕ Р·Р°РїСѓСЃРєР°',            'РЎРѕР·РґР°С‚СЊ Р°РєРєР°СѓРЅС‚ РґРѕ РїСѓР±Р»РёС‡РЅРѕРіРѕ Р·Р°РїСѓСЃРєР°',                        'rare',          'rare',      25,  'рџ•°пёЏ', NULL,  FALSE, 15),
    ('beta_user',          'Р‘РµС‚Р°-РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ',      'РџРѕР»СѓС‡РёС‚СЊ beta-СЂРѕР»СЊ',                                           'rare',          'rare',      30,  'рџ§Є', NULL,  FALSE, 16),
    ('silent_observer',    '30 РґРЅРµР№ С‚РёС€РёРЅС‹',         'РќРµ РїРёСЃР°С‚СЊ РїРѕСЃС‚С‹ 30 РґРЅРµР№ РїРѕСЃР»Рµ СЂРµРіРёСЃС‚СЂР°С†РёРё',                   'rare',          'rare',      20,  'рџ‘ЃпёЏ', NULL,  FALSE, 17),
    ('overfitting',        '100 РїРѕСЃС‚РѕРІ',             'РќР°РїРёСЃР°С‚СЊ 100 РїРѕСЃС‚РѕРІ РЅР° С„РѕСЂСѓРјРµ',                                'rare',          'rare',      45,  'рџ§ ', NULL,  FALSE, 18),
    ('seven_day_streak',   'РЎРµРјРёРґРЅРµРІРєР°',             'Р—Р°Р№С‚Рё РЅР° СЃР°Р№С‚ 7 РґРЅРµР№ РїРѕРґСЂСЏРґ',                                  'rare',          'rare',      25,  'пїЅ', NULL,  FALSE, 19),
    ('night_shift',        'РќРѕС‡РЅР°СЏ СЃРјРµРЅР°',           'РћРїСѓР±Р»РёРєРѕРІР°С‚СЊ РїРѕСЃС‚ РјРµР¶РґСѓ 02:00 Рё 05:00',                        'rare',          'rare',      20,  'рџЊ™', NULL,  FALSE, 20),
    ('archaeologist',      'РђСЂС…РµРѕР»РѕРі',               'РћС‚РІРµС‚РёС‚СЊ РІ С‚СЂРµРґ СЃС‚Р°СЂС€Рµ 90 РґРЅРµР№',                               'rare',          'rare',      25,  'рџ¦ґ', NULL,  FALSE, 21),
    ('cluster_formed',     'Р”РµСЃСЏС‚СЊ РїСЂРёРіР»Р°С€РµРЅРёР№',     'РџСЂРёРіР»Р°СЃРёС‚СЊ 10 РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№',                                  'unique',        'unique',    50,  'рџ§¬', NULL,  FALSE, 22),
    ('benchmark_oracle',   'РџРѕР»СѓС‡РµРЅРёРµ РїСЂРёР·РЅР°РЅРёРµ',    'РџРѕР»СѓС‡РёС‚СЊ Р·Р°РєСЂРµРї С‚СЂРµРґР° РѕС‚ Р°РґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂР°',                       'unique',        'unique',    40,  'пїЅ', NULL,  FALSE, 23),
    ('first_among_equals', 'РџРµСЂРІС‹Рµ 10 РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№','Р’РѕР№С‚Рё РІ РїРµСЂРІС‹Рµ 10 Р·Р°СЂРµРіРёСЃС‚СЂРёСЂРѕРІР°РЅРЅС‹С…',                         'unique',        'unique',    75,  'рџ‘‘', NULL,  FALSE, 24),
    ('alpha_user',         'РђР»СЊС„Р°-РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ',     'РџРѕР»СѓС‡РёС‚СЊ alpha-СЂРѕР»СЊ',                                          'unique',        'unique',    60,  'вљЎ', NULL,  FALSE, 25),
    ('moderator_power',    'РњРѕРґРµСЂР°С‚РѕСЂ',              'РџРѕР»СѓС‡РёС‚СЊ СЂРѕР»СЊ РјРѕРґРµСЂР°С‚РѕСЂР°',                                      'unique',        'unique',    80,  'рџ—ЎпёЏ', NULL,  FALSE, 26),
    ('the_first_hundred',  'РџРµСЂРІС‹Рµ 100 РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№','Р’РѕР№С‚Рё РІ РїРµСЂРІС‹Рµ 100 Р·Р°СЂРµРіРёСЃС‚СЂРёСЂРѕРІР°РЅРЅС‹С… Р°РєРєР°СѓРЅС‚РѕРІ',             'secret_limited','limited',   150, 'рџ’Ћ', 100,   TRUE,  27)
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    rarity = EXCLUDED.rarity,
    points = EXCLUDED.points,
    icon_emoji = EXCLUDED.icon_emoji,
    max_supply = EXCLUDED.max_supply,
    is_secret = EXCLUDED.is_secret,
    sort_order = EXCLUDED.sort_order;

INSERT INTO achievements (id, title, description, category, rarity, points, icon_emoji, max_supply, is_secret, sort_order)
VALUES (
    'admin_endorsement', 'Admin endorsement', 'Received an admin_like reaction from an admin or senior moderator',
    'unique', 'unique', 50, 'A+', NULL, FALSE, 28
)
ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    rarity = EXCLUDED.rarity,
    points = EXCLUDED.points,
    icon_emoji = EXCLUDED.icon_emoji,
    max_supply = EXCLUDED.max_supply,
    is_secret = EXCLUDED.is_secret,
    sort_order = EXCLUDED.sort_order;

-- ==========================================
-- STEP 4: RPC вЂ” Grant achievement (idempotent)
-- ==========================================

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
    SELECT EXISTS(
        SELECT 1 FROM user_achievements WHERE user_id = p_user_id AND achievement_id = p_achievement_id
    ) INTO v_already;

    IF v_already THEN
        RETURN jsonb_build_object('granted', false, 'reason', 'already_unlocked');
    END IF;

    SELECT max_supply INTO v_max_supply FROM achievements WHERE id = p_achievement_id;
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

-- ==========================================
-- STEP 5: RPC вЂ” Check and grant all eligible achievements
-- ==========================================

DROP FUNCTION IF EXISTS public.check_and_grant_achievements(UUID);
CREATE OR REPLACE FUNCTION public.check_and_grant_achievements(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_granted TEXT[] := '{}';
    v_result JSONB;
    v_referral_count INT := 0;
    v_profile RECORD;
    v_uid_seq INT;
    v_has_posts BOOLEAN;
    v_days_since_reg INT;
BEGIN
    SELECT * INTO v_profile FROM profiles WHERE user_id = p_user_id;
    IF v_profile IS NULL THEN RETURN jsonb_build_object('granted', '{}'); END IF;

    -- welcome: always granted for existing users
    SELECT (grant_achievement(p_user_id, 'welcome')->>'granted')::BOOLEAN INTO v_result;
    IF v_result THEN v_granted := array_append(v_granted, 'welcome'); END IF;

    -- first_among_equals: uid <= 10
    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 10 THEN
        SELECT (grant_achievement(p_user_id, 'first_among_equals')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_among_equals'); END IF;
    END IF;

    -- the_first_hundred: uid <= 100
    IF v_profile.uid IS NOT NULL AND v_profile.uid <= 100 THEN
        SELECT (grant_achievement(p_user_id, 'the_first_hundred')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'the_first_hundred'); END IF;
    END IF;

    IF v_profile.created_at IS NOT NULL AND v_profile.created_at < TIMESTAMPTZ '2026-02-19 00:00:00+00' THEN
        SELECT (grant_achievement(p_user_id, 'before_public_launch')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'before_public_launch'); END IF;
    END IF;

    -- alpha_user: role = alpha
    IF v_profile.role = 'alpha' THEN
        SELECT (grant_achievement(p_user_id, 'alpha_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'alpha_user'); END IF;
    END IF;

    -- beta_user: role = beta
    IF v_profile.role = 'beta' THEN
        SELECT (grant_achievement(p_user_id, 'beta_user')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'beta_user'); END IF;
    END IF;

    -- moderator_power: role in (moderator, stmoderator, admin)
    IF v_profile.role IN ('moderator', 'stmoderator', 'admin') THEN
        SELECT (grant_achievement(p_user_id, 'moderator_power')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'moderator_power'); END IF;
    END IF;

    -- Referral-based: count users who used this user's invite code
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

    -- silent_observer: 30+ days since registration, 0 posts
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

    -- profile_tuned: bio or avatar filled
    IF (v_profile.bio IS NOT NULL AND v_profile.bio <> '')
       OR (v_profile.telegram_photo_url IS NOT NULL AND v_profile.telegram_photo_url <> '') THEN
        SELECT (grant_achievement(p_user_id, 'profile_tuned')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'profile_tuned'); END IF;
    END IF;

    -- first_reaction: user has placed at least 1 reaction
    IF EXISTS(SELECT 1 FROM post_reactions WHERE user_id = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_reaction')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_reaction'); END IF;
    END IF;

    -- daily_login: 3-day streak
    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 3) THEN
        SELECT (grant_achievement(p_user_id, 'daily_login')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'daily_login'); END IF;
    END IF;

    -- first_thread: created at least 1 thread
    IF EXISTS(SELECT 1 FROM forum_threads WHERE author_id = p_user_id AND is_deleted = false LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_thread')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_thread'); END IF;
    END IF;

    -- first_comment: wrote at least 1 reply (post in thread not authored by user)
    IF EXISTS(
        SELECT 1 FROM forum_posts fp
        JOIN forum_threads ft ON ft.id = fp.thread_id
        WHERE fp.author_id = p_user_id AND fp.is_deleted = false
        AND ft.author_id != p_user_id
        LIMIT 1
    ) THEN
        SELECT (grant_achievement(p_user_id, 'first_comment')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_comment'); END IF;
    END IF;

    -- first_model_rate: at least 1 result submitted
    IF EXISTS(SELECT 1 FROM results WHERE author = p_user_id LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_model_rate')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_model_rate'); END IF;
    END IF;

    -- first_mention: mentioned another user via @
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND content LIKE '%@%' LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_mention')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_mention'); END IF;
    END IF;

    -- first_edit: edited a post or comment
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND updated_at IS NOT NULL AND updated_at != created_at LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'first_edit')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'first_edit'); END IF;
    END IF;

    -- seven_day_streak: 7-day login streak
    IF EXISTS(SELECT 1 FROM login_streaks WHERE user_id = p_user_id AND current_streak >= 7) THEN
        SELECT (grant_achievement(p_user_id, 'seven_day_streak')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'seven_day_streak'); END IF;
    END IF;

    -- night_shift: post published between 02:00 and 05:00
    IF EXISTS(SELECT 1 FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') >= 2 AND EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC') < 5 LIMIT 1) THEN
        SELECT (grant_achievement(p_user_id, 'night_shift')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'night_shift'); END IF;
    END IF;

    -- archaeologist: reply in thread older than 90 days
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

    -- overfitting: 100+ posts
    IF (SELECT COUNT(*) FROM forum_posts WHERE author_id = p_user_id AND is_deleted = false) >= 100 THEN
        SELECT (grant_achievement(p_user_id, 'overfitting')->>'granted')::BOOLEAN INTO v_result;
        IF v_result THEN v_granted := array_append(v_granted, 'overfitting'); END IF;
    END IF;

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

-- ==========================================
-- STEP 6: RPC вЂ” Check reaction-based achievements
-- ==========================================

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

    -- first_reaction: reactor places their first ever reaction
    PERFORM grant_achievement(p_reactor_id, 'first_reaction');

    RETURN jsonb_build_object('granted', to_jsonb(v_granted));
END;
$$;

-- ==========================================
-- STEP 7: RPC вЂ” Check pin-based achievement
-- ==========================================

DROP FUNCTION IF EXISTS public.check_pin_achievement(INTEGER);
CREATE OR REPLACE FUNCTION public.check_pin_achievement(p_thread_id INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_author UUID;
    v_result JSONB;
BEGIN
    SELECT author_id INTO v_author FROM forum_threads WHERE id = p_thread_id;
    IF v_author IS NULL THEN RETURN jsonb_build_object('granted', false); END IF;
    SELECT (grant_achievement(v_author, 'benchmark_oracle')->>'granted')::BOOLEAN INTO v_result;
    RETURN jsonb_build_object('granted', v_result, 'achievement_id', 'benchmark_oracle');
END;
$$;

-- ==========================================
-- STEP 8: RPC вЂ” Set showcased achievements (max 3)
-- ==========================================

DROP FUNCTION IF EXISTS public.set_showcased_achievements(TEXT);
CREATE OR REPLACE FUNCTION public.set_showcased_achievements(p_achievement_ids TEXT[])
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_count INT;
    v_id TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF array_length(p_achievement_ids, 1) > 3 THEN
        RAISE EXCEPTION 'Maximum 3 showcased achievements allowed';
    END IF;

    IF p_achievement_ids IS NOT NULL AND array_length(p_achievement_ids, 1) > 0 THEN
        FOREACH v_id IN ARRAY p_achievement_ids LOOP
            IF NOT EXISTS(SELECT 1 FROM user_achievements WHERE user_id = v_uid AND achievement_id = v_id) THEN
                RAISE EXCEPTION 'Achievement % not owned by user', v_id;
            END IF;
        END LOOP;
    END IF;

    UPDATE user_achievements SET is_showcased = FALSE WHERE user_id = v_uid;

    IF p_achievement_ids IS NOT NULL AND array_length(p_achievement_ids, 1) > 0 THEN
        FOREACH v_id IN ARRAY p_achievement_ids LOOP
            UPDATE user_achievements SET is_showcased = TRUE
            WHERE user_id = v_uid AND achievement_id = v_id;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('ok', true, 'showcased', to_jsonb(p_achievement_ids));
END;
$$;

-- ==========================================
-- STEP 9: RPC вЂ” Get user achievements
-- ==========================================

DROP FUNCTION IF EXISTS public.get_user_achievements(UUID);
CREATE OR REPLACE FUNCTION public.get_user_achievements(p_user_id UUID)
RETURNS TABLE(
    achievement_id TEXT,
    title TEXT,
    description TEXT,
    category TEXT,
    rarity TEXT,
    points INT,
    icon_emoji TEXT,
    is_secret BOOLEAN,
    unlocked_at TIMESTAMPTZ,
    is_showcased BOOLEAN,
    total_points BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.id AS achievement_id,
        a.title,
        a.description,
        a.category,
        a.rarity,
        a.points,
        a.icon_emoji,
        a.is_secret,
        ua.unlocked_at,
        ua.is_showcased,
        (SELECT COALESCE(SUM(a2.points), 0)
         FROM user_achievements ua2
         JOIN achievements a2 ON a2.id = ua2.achievement_id
         WHERE ua2.user_id = p_user_id) AS total_points
    FROM user_achievements ua
    JOIN achievements a ON a.id = ua.achievement_id
    WHERE ua.user_id = p_user_id
    ORDER BY a.sort_order;
END;
$$;

-- ==========================================
-- STEP 10: RPC вЂ” Get achievements catalog
-- ==========================================

DROP FUNCTION IF EXISTS public.get_achievements_catalog();
CREATE OR REPLACE FUNCTION public.get_achievements_catalog()
RETURNS TABLE(
    id TEXT,
    title TEXT,
    description TEXT,
    category TEXT,
    rarity TEXT,
    points INT,
    icon_emoji TEXT,
    max_supply INT,
    is_secret BOOLEAN,
    sort_order INT,
    total_unlocked BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.id,
        a.title,
        a.description,
        a.category,
        a.rarity,
        a.points,
        a.icon_emoji,
        a.max_supply,
        a.is_secret,
        a.sort_order,
        (SELECT COUNT(*) FROM user_achievements ua WHERE ua.achievement_id = a.id) AS total_unlocked
    FROM achievements a
    ORDER BY a.sort_order;
END;
$$;

-- ==========================================
-- STEP 11: Update get_public_profile to include showcased achievements
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
    reactions_given_count BIGINT,
    achievement_points BIGINT,
    achievements_count BIGINT,
    showcased_achievements JSONB
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
        (SELECT COUNT(*) FROM post_reactions WHERE user_id = p.user_id),
        (SELECT COALESCE(SUM(a.points), 0) FROM user_achievements ua JOIN achievements a ON a.id = ua.achievement_id WHERE ua.user_id = p.user_id),
        (SELECT COUNT(*) FROM user_achievements WHERE user_id = p.user_id),
        (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', a.id,
                'title', a.title,
                'icon_emoji', a.icon_emoji,
                'rarity', a.rarity,
                'points', a.points
            ) ORDER BY a.sort_order), '[]'::jsonb)
            FROM user_achievements ua
            JOIN achievements a ON a.id = ua.achievement_id
            WHERE ua.user_id = p.user_id AND ua.is_showcased = TRUE
        )
    FROM profiles p
    WHERE p.user_id = p_user_id;
END;
$$;

-- ==========================================
-- STEP 12: Update toggle_post_reaction to trigger achievement checks
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
    v_action TEXT;
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

-- ==========================================
-- STEP 13: Update mod_pin_thread to trigger achievement
-- ==========================================

DROP FUNCTION IF EXISTS public.mod_pin_thread(INTEGER, BOOLEAN);
CREATE OR REPLACE FUNCTION public.mod_pin_thread(p_thread_id INTEGER, p_pin BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM st_moderators WHERE user_id = auth.uid())
       AND NOT EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Not a moderator';
    END IF;

    UPDATE forum_threads SET is_pinned = p_pin, updated_at = now() WHERE id = p_thread_id;

    IF p_pin THEN
        PERFORM check_pin_achievement(p_thread_id);
    END IF;

    RETURN jsonb_build_object('pinned', p_pin);
END;
$$;

-- ==========================================
-- STEP 14: Login streaks table for daily_login achievement
-- ==========================================

CREATE TABLE IF NOT EXISTS login_streaks (
    user_id         UUID PRIMARY KEY REFERENCES profiles(user_id) ON DELETE CASCADE,
    last_login_date DATE NOT NULL DEFAULT CURRENT_DATE,
    current_streak  INT NOT NULL DEFAULT 1,
    max_streak      INT NOT NULL DEFAULT 1
);

ALTER TABLE login_streaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_streak" ON login_streaks;
CREATE POLICY "users_read_own_streak" ON login_streaks
    FOR SELECT USING (user_id = auth.uid());

-- ==========================================
-- STEP 15: RPC вЂ” Record login (upsert streak)
-- ==========================================

DROP FUNCTION IF EXISTS public.record_login();
CREATE OR REPLACE FUNCTION public.record_login()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_row login_streaks%ROWTYPE;
    v_new_streak INT;
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
    END IF;

    SELECT * INTO v_row FROM login_streaks WHERE user_id = v_uid;

    IF v_row IS NULL THEN
        INSERT INTO login_streaks (user_id, last_login_date, current_streak, max_streak)
        VALUES (v_uid, v_today, 1, 1);
        RETURN jsonb_build_object('ok', true, 'streak', 1);
    END IF;

    IF v_row.last_login_date = v_today THEN
        RETURN jsonb_build_object('ok', true, 'streak', v_row.current_streak);
    END IF;

    IF v_row.last_login_date = v_today - 1 THEN
        v_new_streak := v_row.current_streak + 1;
    ELSE
        v_new_streak := 1;
    END IF;

    UPDATE login_streaks
    SET last_login_date = v_today,
        current_streak = v_new_streak,
        max_streak = GREATEST(v_row.max_streak, v_new_streak)
    WHERE user_id = v_uid;

    IF v_new_streak >= 3 THEN
        PERFORM grant_achievement(v_uid, 'daily_login');
    END IF;

    RETURN jsonb_build_object('ok', true, 'streak', v_new_streak);
END;
$$;

-- ==========================================
-- STEP 16: Reload PostgREST schema cache
-- ==========================================

NOTIFY pgrst, 'reload schema';

