-- Fix race conditions in invite code system
-- Addresses: concurrent claim_invite_code, generate_user_invite_code, and telegram-auth invite claim

-- 1. Fix claim_invite_code: add FOR UPDATE lock to prevent double-use
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
    SET is_verified = true,
        used_invite_code_id = v_invite_id,
        pending_invite_code = NULL
    WHERE user_id = auth.uid();

    RETURN true;
END;
$$;

-- 2. Fix generate_user_invite_code: serialize with advisory lock per user
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
