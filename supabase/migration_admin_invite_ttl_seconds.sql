DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.admin_generate_invite_code(INTEGER, INTEGER, INTEGER);

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

    v_max_uses := LEAST(100, GREATEST(1, COALESCE(p_max_uses, 10)));
    v_ttl_seconds := LEAST(604800, GREATEST(1, COALESCE(p_ttl_seconds, 300)));

    LOOP
        v_attempt := v_attempt + 1;
        v_code := upper(encode(gen_random_bytes(6), 'hex'));

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
