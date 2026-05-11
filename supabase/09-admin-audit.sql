-- ==========================================
-- Admin audit log table
-- ==========================================
CREATE TABLE IF NOT EXISTS public.admin_actions (
    id          BIGSERIAL PRIMARY KEY,
    actor_id    UUID NOT NULL,
    action      TEXT NOT NULL,
    target_id   UUID,
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.admin_actions FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.admin_actions FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.admin_actions FROM authenticated;
GRANT SELECT ON TABLE public.admin_actions TO authenticated;
GRANT SELECT, INSERT ON TABLE public.admin_actions TO service_role;

DROP POLICY IF EXISTS "admin_read_actions" ON public.admin_actions;
CREATE POLICY "admin_read_actions" ON public.admin_actions
    FOR SELECT USING (EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "service_insert_actions" ON public.admin_actions;
CREATE POLICY "service_insert_actions" ON public.admin_actions
    FOR INSERT TO service_role WITH CHECK (true);
