CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

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
        v_new_code := upper(encode(gen_random_bytes(4), 'hex'));

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

DROP FUNCTION IF EXISTS public.admin_generate_invite_code();
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER);
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.admin_generate_invite_code(
    p_max_uses INTEGER DEFAULT 10,
    p_ttl_seconds INTEGER DEFAULT 300
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_code TEXT;
    v_max_uses INTEGER;
    v_ttl_seconds INTEGER;
    v_attempt INTEGER := 0;
BEGIN
    IF COALESCE(auth.role(), '') <> 'service_role'
       AND NOT EXISTS (
           SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
       ) THEN
        RETURN NULL;
    END IF;

    v_max_uses := LEAST(10000, GREATEST(1, COALESCE(p_max_uses, 10)));
    v_ttl_seconds := LEAST(35996400, GREATEST(1, COALESCE(p_ttl_seconds, 300)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(4), 'hex'));

        BEGIN
            INSERT INTO public.invite_codes (code, created_by, is_admin_code, max_uses, use_count, expires_at)
            VALUES (v_code, auth.uid(), true, v_max_uses, 0, now() + make_interval(secs => v_ttl_seconds));
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

REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_code(INTEGER, INTEGER) TO service_role;

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
        v_code := upper(encode(gen_random_bytes(4), 'hex'));

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
    SET pending_invite_code = v_code
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object('ok', true, 'code', v_code, 'invite_id', v_invite_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_generate_invite_for_user(UUID, INTEGER) TO service_role;

DO $$
DECLARE
    v_row RECORD;
    v_new_code TEXT;
BEGIN
    PERFORM set_config('search_path', 'public, extensions', true);

    FOR v_row IN
        SELECT id
        FROM public.invite_codes
        WHERE code IS NOT NULL
          AND length(code) <> 8
          AND COALESCE(use_count, 0) = 0
    LOOP
        LOOP
            v_new_code := upper(encode(gen_random_bytes(4), 'hex'));
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

NOTIFY pgrst, 'reload schema';
