-- ============================================
-- BUNDLE 2: LEADERBOARD — Models, Results, Ratings
-- Run AFTER 01-core.sql
-- ============================================

-- ==========================================
-- STEP 1: Create tables
-- ==========================================

-- Prompts: test prompts catalog
CREATE TABLE IF NOT EXISTS prompts (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE prompts ENABLE ROW LEVEL SECURITY;

-- Models: global catalog
CREATE TABLE IF NOT EXISTS models (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE models ENABLE ROW LEVEL SECURITY;

-- Model spaces: platforms where the model is tested
CREATE TABLE IF NOT EXISTS model_spaces (
    id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL REFERENCES models(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(model_id, name)
);
ALTER TABLE model_spaces ENABLE ROW LEVEL SECURITY;

-- Model params: parameter definitions per model
CREATE TABLE IF NOT EXISTS model_params (
    id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL REFERENCES models(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(model_id, name)
);
ALTER TABLE model_params ENABLE ROW LEVEL SECURITY;

-- Model param values: possible values for each parameter
CREATE TABLE IF NOT EXISTS model_param_values (
    id SERIAL PRIMARY KEY,
    param_id INTEGER NOT NULL REFERENCES model_params(id) ON DELETE CASCADE,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(param_id, value)
);
ALTER TABLE model_param_values ENABLE ROW LEVEL SECURITY;

-- Results: test result = model + prompt + space + scores + SVG + author
CREATE TABLE IF NOT EXISTS results (
    id SERIAL PRIMARY KEY,
    model_id INTEGER NOT NULL REFERENCES models(id) ON DELETE CASCADE,
    prompt_id INTEGER NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
    model_space_id INTEGER REFERENCES model_spaces(id) ON DELETE SET NULL,
    test_date DATE,
    author TEXT,
    s_visual NUMERIC(3,1) NOT NULL DEFAULT 0,
    s_animation NUMERIC(3,1) NOT NULL DEFAULT 0,
    s_creative NUMERIC(3,1) NOT NULL DEFAULT 0,
    s_code NUMERIC(3,1) NOT NULL DEFAULT 0,
    s_detail NUMERIC(3,1) NOT NULL DEFAULT 0,
    overall NUMERIC(5,1) NOT NULL DEFAULT 0,
    svg_content TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE results ENABLE ROW LEVEL SECURITY;

-- Result param values: junction table
CREATE TABLE IF NOT EXISTS result_param_values (
    id SERIAL PRIMARY KEY,
    result_id INTEGER NOT NULL REFERENCES results(id) ON DELETE CASCADE,
    param_value_id INTEGER NOT NULL REFERENCES model_param_values(id) ON DELETE CASCADE,
    UNIQUE(result_id, param_value_id)
);
ALTER TABLE result_param_values ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- STEP 2: RLS policies
-- ==========================================

-- prompts: public read, admin write
DROP POLICY IF EXISTS "public_read_prompts" ON prompts;
CREATE POLICY "public_read_prompts" ON prompts FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_prompts" ON prompts;
CREATE POLICY "admin_all_prompts" ON prompts FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- models: public read, admin write
DROP POLICY IF EXISTS "public_read_models" ON models;
CREATE POLICY "public_read_models" ON models FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_models" ON models;
CREATE POLICY "admin_all_models" ON models FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- model_spaces: public read, admin write
DROP POLICY IF EXISTS "public_read_model_spaces" ON model_spaces;
CREATE POLICY "public_read_model_spaces" ON model_spaces FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_model_spaces" ON model_spaces;
CREATE POLICY "admin_all_model_spaces" ON model_spaces FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- model_params: public read, admin write
DROP POLICY IF EXISTS "public_read_model_params" ON model_params;
CREATE POLICY "public_read_model_params" ON model_params FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_model_params" ON model_params;
CREATE POLICY "admin_all_model_params" ON model_params FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- model_param_values: public read, admin write
DROP POLICY IF EXISTS "public_read_model_param_values" ON model_param_values;
CREATE POLICY "public_read_model_param_values" ON model_param_values FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_model_param_values" ON model_param_values;
CREATE POLICY "admin_all_model_param_values" ON model_param_values FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- results: public read, admin write
DROP POLICY IF EXISTS "public_read_results" ON results;
CREATE POLICY "public_read_results" ON results FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_results" ON results;
CREATE POLICY "admin_all_results" ON results FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- result_param_values: public read, admin write
DROP POLICY IF EXISTS "public_read_result_param_values" ON result_param_values;
CREATE POLICY "public_read_result_param_values" ON result_param_values FOR SELECT USING (true);
DROP POLICY IF EXISTS "admin_all_result_param_values" ON result_param_values;
CREATE POLICY "admin_all_result_param_values" ON result_param_values FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_users WHERE user_id = auth.uid())
);

-- ==========================================
-- STEP 3: Indexes
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_model_spaces_model_id ON model_spaces(model_id);
CREATE INDEX IF NOT EXISTS idx_model_params_model_id ON model_params(model_id);
CREATE INDEX IF NOT EXISTS idx_model_param_values_param_id ON model_param_values(param_id);
CREATE INDEX IF NOT EXISTS idx_results_model_id ON results(model_id);
CREATE INDEX IF NOT EXISTS idx_results_prompt_id ON results(prompt_id);
CREATE INDEX IF NOT EXISTS idx_results_model_space_id ON results(model_space_id);
CREATE INDEX IF NOT EXISTS idx_results_overall ON results(overall DESC);
CREATE INDEX IF NOT EXISTS idx_results_prompt_model ON results(prompt_id, model_id);
CREATE INDEX IF NOT EXISTS idx_result_param_values_result_id ON result_param_values(result_id);
CREATE INDEX IF NOT EXISTS idx_result_param_values_param_value_id ON result_param_values(param_value_id);

-- ==========================================
-- STEP 4: Result Ratings
-- ==========================================

CREATE TABLE IF NOT EXISTS result_ratings (
    id BIGSERIAL PRIMARY KEY,
    result_id INTEGER NOT NULL REFERENCES results(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    s_visual NUMERIC(3,1) NOT NULL DEFAULT 5 CHECK (s_visual >= 1 AND s_visual <= 10),
    s_animation NUMERIC(3,1) NOT NULL DEFAULT 5 CHECK (s_animation >= 1 AND s_animation <= 10),
    s_creative NUMERIC(3,1) NOT NULL DEFAULT 5 CHECK (s_creative >= 1 AND s_creative <= 10),
    s_code NUMERIC(3,1) NOT NULL DEFAULT 5 CHECK (s_code >= 1 AND s_code <= 10),
    s_detail NUMERIC(3,1) NOT NULL DEFAULT 5 CHECK (s_detail >= 1 AND s_detail <= 10),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(result_id, user_id)
);

ALTER TABLE result_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own_read_result_ratings" ON result_ratings;
CREATE POLICY "own_read_result_ratings" ON result_ratings
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "own_insert_result_ratings" ON result_ratings;
CREATE POLICY "own_insert_result_ratings" ON result_ratings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "own_update_result_ratings" ON result_ratings;
CREATE POLICY "own_update_result_ratings" ON result_ratings
    FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_result_ratings_result_id ON result_ratings(result_id);
CREATE INDEX IF NOT EXISTS idx_result_ratings_user_id ON result_ratings(user_id);
CREATE INDEX IF NOT EXISTS idx_result_ratings_result_created ON result_ratings(result_id, created_at);

CREATE OR REPLACE FUNCTION touch_result_rating_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_result_rating_updated_at ON result_ratings;
CREATE TRIGGER trg_touch_result_rating_updated_at
BEFORE UPDATE ON result_ratings
FOR EACH ROW
EXECUTE FUNCTION touch_result_rating_updated_at();

DROP FUNCTION IF EXISTS public.get_result_rating_stats(INTEGER[]);
CREATE OR REPLACE FUNCTION get_result_rating_stats(p_result_ids INTEGER[])
RETURNS TABLE (
    result_id INTEGER,
    avg_score NUMERIC,
    rating_count BIGINT,
    my_score NUMERIC,
    my_s_visual NUMERIC,
    my_s_animation NUMERIC,
    my_s_creative NUMERIC,
    my_s_code NUMERIC,
    my_s_detail NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        r.id AS result_id,
        ROUND(AVG((rr.s_visual + rr.s_animation + rr.s_creative + rr.s_code + rr.s_detail) * 1.8)::numeric, 1) AS avg_score,
        COUNT(rr.id)::bigint AS rating_count,
        ROUND(MAX((rr.s_visual + rr.s_animation + rr.s_creative + rr.s_code + rr.s_detail) * 1.8) FILTER (WHERE rr.user_id = auth.uid())::numeric, 1) AS my_score,
        MAX(rr.s_visual) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_visual,
        MAX(rr.s_animation) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_animation,
        MAX(rr.s_creative) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_creative,
        MAX(rr.s_code) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_code,
        MAX(rr.s_detail) FILTER (WHERE rr.user_id = auth.uid()) AS my_s_detail
    FROM results r
    LEFT JOIN result_ratings rr ON rr.result_id = r.id
    WHERE r.id = ANY(p_result_ids)
    GROUP BY r.id;
$$;

CREATE OR REPLACE FUNCTION rate_result(
    p_result_id INTEGER,
    p_s_visual NUMERIC,
    p_s_animation NUMERIC,
    p_s_creative NUMERIC,
    p_s_code NUMERIC,
    p_s_detail NUMERIC
)
RETURNS TABLE (
    result_id INTEGER,
    avg_score NUMERIC,
    rating_count BIGINT,
    my_score NUMERIC,
    my_s_visual NUMERIC,
    my_s_animation NUMERIC,
    my_s_creative NUMERIC,
    my_s_code NUMERIC,
    my_s_detail NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    INSERT INTO result_ratings (
        result_id, user_id,
        s_visual, s_animation, s_creative, s_code, s_detail
    )
    VALUES (
        p_result_id, v_user_id,
        LEAST(10, GREATEST(1, ROUND(p_s_visual::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_animation::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_creative::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_code::numeric, 1))),
        LEAST(10, GREATEST(1, ROUND(p_s_detail::numeric, 1)))
    )
    ON CONFLICT (result_id, user_id)
    DO UPDATE SET
        s_visual = EXCLUDED.s_visual,
        s_animation = EXCLUDED.s_animation,
        s_creative = EXCLUDED.s_creative,
        s_code = EXCLUDED.s_code,
        s_detail = EXCLUDED.s_detail;

    RETURN QUERY SELECT * FROM get_result_rating_stats(ARRAY[p_result_id]);
END;
$$;

DROP FUNCTION IF EXISTS public.get_result_rating_entries(INTEGER[], INTEGER) CASCADE;
CREATE OR REPLACE FUNCTION public.get_result_rating_entries(
    p_result_ids INTEGER[],
    p_limit_per_result INTEGER DEFAULT 8
)
RETURNS TABLE (
    result_id INTEGER,
    rating_id BIGINT,
    rating_rank INTEGER,
    rated_at TIMESTAMPTZ,
    rating_delay_seconds INTEGER,
    rater_uid INTEGER,
    rater_nickname TEXT,
    rater_role TEXT,
    total_score NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_result_ids IS NULL OR array_length(p_result_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    IF p_limit_per_result < 1 OR p_limit_per_result > 20 THEN
        RAISE EXCEPTION 'p_limit_per_result must be between 1 and 20'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH requested AS (
        SELECT req.id, req.ord
        FROM unnest(p_result_ids) WITH ORDINALITY AS req(id, ord)
    ),
    ranked AS (
        SELECT
            rr.result_id,
            rr.id AS rating_id,
            ROW_NUMBER() OVER (
                PARTITION BY rr.result_id
                ORDER BY
                    GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (
                        rr.created_at - COALESCE(r.created_at, r.test_date::timestamptz, rr.created_at)
                    )))::INTEGER) ASC,
                    rr.created_at ASC,
                    rr.id ASC
            )::INTEGER AS rating_rank,
            rr.created_at AS rated_at,
            GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (
                rr.created_at - COALESCE(r.created_at, r.test_date::timestamptz, rr.created_at)
            )))::INTEGER) AS rating_delay_seconds,
            p.uid AS rater_uid,
            COALESCE(
                '@' || NULLIF(p.telegram_username, ''),
                CASE WHEN p.uid IS NOT NULL THEN '@uid' || p.uid::TEXT ELSE '@unknown' END
            ) AS rater_nickname,
            COALESCE(p.role, 'member') AS rater_role,
            ROUND(((rr.s_visual + rr.s_animation + rr.s_creative + rr.s_code + rr.s_detail) * 1.8)::NUMERIC, 1) AS total_score,
            requested.ord
        FROM requested
        JOIN results r ON r.id = requested.id
        JOIN result_ratings rr ON rr.result_id = r.id
        LEFT JOIN profiles p ON p.user_id = rr.user_id
    )
    SELECT
        ranked.result_id,
        ranked.rating_id,
        ranked.rating_rank,
        ranked.rated_at,
        ranked.rating_delay_seconds,
        ranked.rater_uid,
        ranked.rater_nickname,
        ranked.rater_role,
        ranked.total_score
    FROM ranked
    WHERE ranked.rating_rank <= p_limit_per_result
    ORDER BY ranked.ord ASC, ranked.rating_rank ASC;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_result_rating_entries(INTEGER[], INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_result_rating_stats(INTEGER[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rate_result(INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_result_rating_entries(INTEGER[], INTEGER) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
