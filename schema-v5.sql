-- ============================================
-- 魔方比赛成绩管理系统 v5 - 完整数据库重构
-- 功能：层级项目结构、算法配置、Gamma MLE、高度可自定义统计
-- 重构：清理冗余字段，统一命名规范
-- ============================================

-- 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 1. 比赛表 (competitions)
-- ============================================
DROP TABLE IF EXISTS attempt_results CASCADE;
DROP TABLE IF EXISTS attempt_records CASCADE;
DROP TABLE IF EXISTS competition_events CASCADE;
DROP TABLE IF EXISTS competitions CASCADE;
DROP TABLE IF EXISTS participants CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS statistics_definitions CASCADE;
DROP TABLE IF EXISTS participant_statistics CASCADE;
DROP TABLE IF EXISTS mle_predictions CASCADE;
DROP TABLE IF EXISTS event_algorithms CASCADE;

CREATE TABLE competitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comp_number TEXT UNIQUE NOT NULL,
    comp_name TEXT NOT NULL,
    comp_date DATE NOT NULL,
    location TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE competitions IS '魔方比赛基本信息';
COMMENT ON COLUMN competitions.comp_number IS '比赛编号（如 WCA-2024-001）';
COMMENT ON COLUMN competitions.comp_name IS '比赛名称';

-- ============================================
-- 2. 项目表 (events)
-- 支持层级结构（父子项目）和算法配置
-- ============================================
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_code VARCHAR(20) UNIQUE NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    description TEXT,
    puzzle_type VARCHAR(50),
    parent_event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    is_sub_event BOOLEAN DEFAULT FALSE,
    sort_order INTEGER DEFAULT 0,
    event_config JSONB DEFAULT '{}'::jsonb,
    algorithm_config JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE events IS '魔方项目定义，支持层级结构';
COMMENT ON COLUMN events.parent_event_id IS '父项目 ID，NULL 表示顶级项目';
COMMENT ON COLUMN events.is_sub_event IS '是否为子项目（TRUE=子项目，FALSE=顶级项目）';
COMMENT ON COLUMN events.sort_order IS '排序权重，越小越靠前';
COMMENT ON COLUMN events.event_config IS '项目自定义配置（JSON格式）';
COMMENT ON COLUMN events.algorithm_config IS '算法配置（JSON格式）';

CREATE INDEX idx_events_parent ON events(parent_event_id);

-- 插入默认顶级项目
INSERT INTO events (event_code, event_name, description, puzzle_type, sort_order) VALUES
('3x3', '三阶魔方', '标准三阶速拧', 'cube', 1),
('2x2', '二阶魔方', '二阶速拧', 'cube', 2),
('4x4', '四阶魔方', '四阶速拧', 'cube', 3),
('5x5', '五阶魔方', '五阶速拧', 'cube', 4),
('pyraminx', '金字塔', '金字塔魔方', 'pyramid', 5),
('megaminx', '五魔方', '十二面体魔方', 'other', 6),
('skewb', '斜转魔方', 'Skewb', 'other', 7),
('oh', '单手', '三阶单手', 'cube', 8),
('bld', '盲拧', '三阶盲拧', 'cube', 9);

-- 为三阶添加子项目（Single, AO5, AO12）
INSERT INTO events (event_code, event_name, description, puzzle_type, parent_event_id, is_sub_event, algorithm_config, sort_order)
SELECT '3x3-single', '三阶 - 单次', '三阶速拧单次成绩', 'cube', e.id, TRUE, '{
  "algorithm_type": "single",
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, 1
FROM events e WHERE e.event_code = '3x3' AND NOT EXISTS (SELECT 1 FROM events WHERE event_code = '3x3-single');

INSERT INTO events (event_code, event_name, description, puzzle_type, parent_event_id, is_sub_event, algorithm_config, sort_order)
SELECT '3x3-ao5', '三阶 - AO5', '三阶速拧最近5次平均', 'cube', e.id, TRUE, '{
  "algorithm_type": "average",
  "window_size": 5,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, 2
FROM events e WHERE e.event_code = '3x3' AND NOT EXISTS (SELECT 1 FROM events WHERE event_code = '3x3-ao5');

INSERT INTO events (event_code, event_name, description, puzzle_type, parent_event_id, is_sub_event, algorithm_config, sort_order)
SELECT '3x3-ao12', '三阶 - AO12', '三阶速拧最近12次平均', 'cube', e.id, TRUE, '{
  "algorithm_type": "average",
  "window_size": 12,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, 3
FROM events e WHERE e.event_code = '3x3' AND NOT EXISTS (SELECT 1 FROM events WHERE event_code = '3x3-ao12');

-- ============================================
-- 2.5 算法模板表 (event_algorithms)
-- 预定义常用算法模板
-- ============================================
CREATE TABLE event_algorithms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    algorithm_code VARCHAR(50) UNIQUE NOT NULL,
    algorithm_name VARCHAR(100) NOT NULL,
    description TEXT,
    config_template JSONB NOT NULL,
    is_builtin BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE event_algorithms IS '预定义的算法模板';

-- 插入内置算法模板
INSERT INTO event_algorithms (algorithm_code, algorithm_name, description, config_template, is_builtin) VALUES
('single', '单次最佳', '取最佳单次成绩', '{
  "algorithm_type": "single",
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('average_trim1', '去头尾平均', '去掉最高最低后平均（如 WCA 平均）', '{
  "algorithm_type": "average",
  "window_size": null,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('ao5', 'AO5', '最近 5 次平均（去头尾）', '{
  "algorithm_type": "average",
  "window_size": 5,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('ao12', 'AO12', '最近 12 次平均（去头尾）', '{
  "algorithm_type": "average",
  "window_size": 12,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('ao50', 'AO50', '最近 50 次平均', '{
  "algorithm_type": "average",
  "window_size": 50,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('ao100', 'AO100', '最近 100 次平均', '{
  "algorithm_type": "average",
  "window_size": 100,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('best_of_3', '三局两胜', '取最佳 3 次中的最佳', '{
  "algorithm_type": "best_of",
  "window_size": 3,
  "trim_count": 0,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('sub_x', 'SUB-X', '统计低于某时间的比率', '{
  "algorithm_type": "sub",
  "threshold": 10.000,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE),

('mean', '算术平均', '简单算术平均（不去头尾）', '{
  "algorithm_type": "mean",
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, TRUE)

ON CONFLICT (algorithm_code) DO UPDATE SET
    algorithm_name = EXCLUDED.algorithm_name,
    description = EXCLUDED.description,
    config_template = EXCLUDED.config_template;

-- ============================================
-- 3. 比赛-项目关联表 (competition_events)
-- ============================================
CREATE TABLE competition_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_id UUID REFERENCES competitions(id) ON DELETE CASCADE,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    event_number INTEGER NOT NULL,
    UNIQUE(competition_id, event_id),
    UNIQUE(competition_id, event_number)
);

COMMENT ON TABLE competition_events IS '比赛与项目的多对多关联';

-- ============================================
-- 4. 选手表 (participants)
-- ============================================
CREATE TABLE participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_name TEXT NOT NULL UNIQUE,
    wca_id VARCHAR(20),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE participants IS '参赛选手信息';

-- ============================================
-- 5. 成绩记录表 (attempt_records)
-- 记录每次尝试的原始数据
-- ============================================
CREATE TABLE attempt_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_event_id UUID REFERENCES competition_events(id) ON DELETE CASCADE,
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    attempt_id TEXT NOT NULL,
    raw_time DECIMAL(10,3),
    cube_type VARCHAR(20) NOT NULL CHECK (cube_type IN ('smart', 'non_smart')),
    scramble_text TEXT,
    move_count INTEGER,
    tps_value DECIMAL(10,3),
    solve_steps JSONB,
    step_comments TEXT,
    has_dnf BOOLEAN DEFAULT FALSE,
    has_plus_two BOOLEAN DEFAULT FALSE,
    video_link TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(competition_event_id, participant_id, attempt_id)
);

COMMENT ON TABLE attempt_records IS '每次尝试的原始记录';
COMMENT ON COLUMN attempt_records.attempt_id IS '尝试编号（文本类型，灵活标识）';
COMMENT ON COLUMN attempt_records.raw_time IS '复原时间（秒），DNF时为NULL';
COMMENT ON COLUMN attempt_records.has_dnf IS '是否 DNF';
COMMENT ON COLUMN attempt_records.has_plus_two IS '是否 +2 秒';

-- ============================================
-- 6. 成绩结果表 (attempt_results)
-- 存储计算后的成绩（支持多种算法）
-- ============================================
CREATE TABLE attempt_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_record_id UUID REFERENCES attempt_records(id) ON DELETE CASCADE,
    result_value DECIMAL(10,3),
    result_type VARCHAR(20) NOT NULL,
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE attempt_results IS '计算后的成绩结果';

-- ============================================
-- 7. 统计定义表 (statistics_definitions)
-- ============================================
CREATE TABLE statistics_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stat_code VARCHAR(50) UNIQUE NOT NULL,
    stat_name VARCHAR(100) NOT NULL,
    calculation_type VARCHAR(20) NOT NULL,
    window_size INTEGER,
    is_lower_better BOOLEAN DEFAULT TRUE,
    threshold_value DECIMAL(10,3),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE statistics_definitions IS '统计类型定义';

-- 插入默认统计定义
INSERT INTO statistics_definitions (stat_code, stat_name, calculation_type, window_size, is_lower_better, description) VALUES
('single', '单次最佳', 'single', NULL, TRUE, '历史最佳单次成绩'),
('ao5', 'AO5', 'average', 5, TRUE, '最近5次平均（去头尾）'),
('ao12', 'AO12', 'average', 12, TRUE, '最近12次平均（去头尾）'),
('ao50', 'AO50', 'average', 50, TRUE, '最近50次平均'),
('ao100', 'AO100', 'average', 100, TRUE, '最近100次平均'),
('bao5', '最佳AO5', 'best_average', 5, TRUE, '历史最佳AO5'),
('bao12', '最佳AO12', 'best_average', 12, TRUE, '历史最佳AO12'),
('current_avg', '当前平均', 'current_avg', NULL, TRUE, '所有有效成绩的平均');

-- ============================================
-- 8. 选手统计数据表 (participant_statistics)
-- ============================================
CREATE TABLE participant_statistics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    stat_definition_id UUID REFERENCES statistics_definitions(id) ON DELETE CASCADE,
    stat_value DECIMAL(10,3),
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(participant_id, event_id, stat_definition_id)
);

COMMENT ON TABLE participant_statistics IS '选手的统计数据';

-- ============================================
-- 9. MLE 预测结果表 (mle_predictions)
-- ============================================
CREATE TABLE mle_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    alpha DECIMAL(10,3) NOT NULL,
    beta DECIMAL(10,3) NOT NULL,
    mode_value DECIMAL(10,3) NOT NULL,
    mean_value DECIMAL(10,3) NOT NULL,
    variance_value DECIMAL(10,3) NOT NULL,
    sample_size INTEGER NOT NULL,
    confidence_interval JSONB,
    predicted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE mle_predictions IS 'Gamma 分布 MLE 预测结果';

-- ============================================
-- 10. 创建函数：获取项目的完整配置（继承父项目）
-- ============================================
CREATE OR REPLACE FUNCTION get_event_full_config(input_event_id UUID)
RETURNS JSONB AS $$
DECLARE
    config JSONB;
    parent_id UUID;
    parent_config JSONB;
BEGIN
    SELECT algorithm_config, parent_event_id 
    INTO config, parent_id
    FROM events
    WHERE id = input_event_id;
    
    IF parent_id IS NOT NULL THEN
        SELECT get_event_full_config(parent_id) INTO parent_config;
        config = COALESCE(parent_config, '{}'::jsonb) || COALESCE(config, '{}'::jsonb);
    END IF;
    
    RETURN COALESCE(config, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 11. 创建函数：计算成绩（根据算法配置）
-- ============================================
CREATE OR REPLACE FUNCTION calculate_statistic(
    p_participant_id UUID,
    p_event_id UUID,
    p_algorithm_config JSONB DEFAULT NULL
)
RETURNS DECIMAL(10,3) AS $$
DECLARE
    config JSONB;
    algo_type TEXT;
    window_size INT;
    trim_count INT;
    is_lower_better BOOLEAN;
    result DECIMAL(10,3);
    times DECIMAL(10,3)[];
BEGIN
    IF p_algorithm_config IS NULL THEN
        SELECT get_event_full_config(p_event_id) INTO config;
    ELSE
        config = p_algorithm_config;
    END IF;
    
    algo_type = config->>'algorithm_type';
    window_size = (config->>'window_size')::INT;
    trim_count = COALESCE((config->>'trim_count')::INT, 0);
    is_lower_better = COALESCE((config->>'is_lower_better')::BOOLEAN, TRUE);
    
    SELECT ARRAY_AGG(raw_time ORDER BY created_at)
    INTO times
    FROM attempt_records a
    JOIN competition_events ce ON a.competition_event_id = ce.id
    WHERE a.participant_id = p_participant_id
      AND ce.event_id = p_event_id
      AND a.has_dnf = FALSE
      AND a.has_plus_two = FALSE
      AND a.raw_time IS NOT NULL;
    
    IF times IS NULL OR array_length(times, 1) = 0 THEN
        RETURN NULL;
    END IF;
    
    IF algo_type = 'single' THEN
        SELECT MIN(unnest) INTO result FROM unnest(times);
        
    ELSIF algo_type = 'average' THEN
        IF window_size IS NOT NULL AND array_length(times, 1) >= window_size THEN
            WITH recent_times AS (
                SELECT unnest(times[array_length(times, 1) - window_size + 1 : array_length(times, 1)]) AS t
            )
            SELECT 
                CASE 
                    WHEN trim_count > 0 THEN 
                        (SUM(t) - MAX(t) - MIN(t)) / (COUNT(t) - 2 * trim_count)
                    ELSE 
                        AVG(t) 
                END
            INTO result
            FROM recent_times;
        ELSE
            SELECT 
                CASE 
                    WHEN trim_count > 0 AND COUNT(*) > 2 * trim_count THEN 
                        (SUM(t) - MAX(t) - MIN(t)) / (COUNT(t) - 2 * trim_count)
                    ELSE 
                        AVG(t) 
                END
            INTO result
            FROM unnest(times) AS t;
        END IF;
        
    ELSIF algo_type = 'mean' THEN
        SELECT AVG(unnest) INTO result FROM unnest(times);
        
    ELSIF algo_type = 'best_of' THEN
        SELECT MIN(unnest) INTO result FROM unnest(times);
        
    ELSIF algo_type = 'sub' THEN
        DECLARE
            threshold DECIMAL(10,3);
            sub_count INT;
            total_count INT;
        BEGIN
            threshold = (config->>'threshold')::DECIMAL;
            SELECT COUNT(*), array_length(times, 1)
            INTO sub_count, total_count
            FROM unnest(times) AS t
            WHERE t <= threshold;
            
            IF total_count > 0 THEN
                result = (sub_count::DECIMAL / total_count::DECIMAL) * 100;
            ELSE
                result = 0;
            END IF;
        END;
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 12. 启用行级安全 (RLS)
-- ============================================
ALTER TABLE competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempt_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempt_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE statistics_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE participant_statistics ENABLE ROW LEVEL SECURITY;
ALTER TABLE mle_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_algorithms ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 13. 创建宽松的 RLS 策略（允许匿名访问）
-- ============================================
CREATE POLICY "Allow all access on competitions" ON competitions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on events" ON events FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on competition_events" ON competition_events FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on participants" ON participants FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on attempt_records" ON attempt_records FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on attempt_results" ON attempt_results FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on statistics_definitions" ON statistics_definitions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on participant_statistics" ON participant_statistics FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on mle_predictions" ON mle_predictions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on event_algorithms" ON event_algorithms FOR ALL USING (true) WITH CHECK (true);

-- 授予匿名用户权限
GRANT ALL ON competitions TO anon;
GRANT ALL ON events TO anon;
GRANT ALL ON competition_events TO anon;
GRANT ALL ON participants TO anon;
GRANT ALL ON attempt_records TO anon;
GRANT ALL ON attempt_results TO anon;
GRANT ALL ON statistics_definitions TO anon;
GRANT ALL ON participant_statistics TO anon;
GRANT ALL ON mle_predictions TO anon;
GRANT ALL ON event_algorithms TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;

-- ============================================
-- 14. 创建视图
-- ============================================

-- 比赛统计视图
CREATE OR REPLACE VIEW competition_stats
WITH (security_invoker = true) AS
SELECT 
    c.id AS competition_id,
    c.comp_number,
    c.comp_name,
    c.comp_date,
    e.event_code,
    e.event_name,
    COUNT(DISTINCT a.participant_id) AS total_participants,
    COUNT(a.id) AS total_attempts,
    AVG(CASE WHEN a.has_dnf = FALSE AND a.has_plus_two = FALSE THEN a.raw_time END) AS avg_time,
    MIN(CASE WHEN a.has_dnf = FALSE THEN a.raw_time END) AS best_time,
    COUNT(CASE WHEN a.cube_type = 'smart' THEN 1 END) AS smart_cube_attempts,
    COUNT(CASE WHEN a.cube_type = 'non_smart' THEN 1 END) AS non_smart_cube_attempts
FROM competitions c
LEFT JOIN competition_events ce ON c.id = ce.competition_id
LEFT JOIN events e ON ce.event_id = e.id
LEFT JOIN attempt_records a ON ce.id = a.competition_event_id
GROUP BY c.id, c.comp_number, c.comp_name, c.comp_date, e.event_code, e.event_name;

-- 选手统计视图
CREATE OR REPLACE VIEW participant_stats
WITH (security_invoker = true) AS
SELECT 
    p.id AS participant_id,
    p.participant_name,
    e.event_code,
    e.event_name,
    COUNT(DISTINCT ce.competition_id) AS total_competitions,
    COUNT(a.id) AS total_attempts,
    AVG(CASE WHEN a.has_dnf = FALSE AND a.has_plus_two = FALSE THEN a.raw_time END) AS avg_time,
    MIN(CASE WHEN a.has_dnf = FALSE THEN a.raw_time END) AS best_time,
    AVG(CASE WHEN a.cube_type = 'smart' THEN a.tps_value END) AS avg_tps_smart,
    AVG(CASE WHEN a.cube_type = 'smart' THEN a.move_count END) AS avg_moves_smart
FROM participants p
LEFT JOIN attempt_records a ON p.id = a.participant_id
LEFT JOIN competition_events ce ON a.competition_event_id = ce.id
LEFT JOIN events e ON ce.event_id = e.id
GROUP BY p.id, p.participant_name, e.event_code, e.event_name;

-- 项目配置视图
CREATE OR REPLACE VIEW event_config_view
WITH (security_invoker = true) AS
SELECT 
    e.id,
    e.event_code,
    e.event_name,
    e.description,
    e.puzzle_type,
    e.parent_event_id,
    e.is_sub_event,
    e.sort_order,
    e.event_config,
    e.algorithm_config,
    p.event_code AS parent_code,
    p.event_name AS parent_name,
    e.event_config->>'attempt_id_label' AS attempt_id_label,
    e.event_config->>'attempt_id_type' AS attempt_id_type,
    (e.event_config->>'supports_smart_cube')::boolean AS supports_smart_cube,
    (e.event_config->>'record_steps')::boolean AS record_steps,
    (e.algorithm_config->>'algorithm_type') AS algorithm_type
FROM events e
LEFT JOIN events p ON e.parent_event_id = p.id
ORDER BY 
    COALESCE(e.parent_event_id::text, e.id::text), 
    e.sort_order, 
    e.event_code;

-- ============================================
-- 15. 创建索引
-- ============================================
CREATE INDEX idx_attempt_records_participant ON attempt_records(participant_id);
CREATE INDEX idx_attempt_records_competition_event ON attempt_records(competition_event_id);
CREATE INDEX idx_competition_events_competition ON competition_events(competition_id);
CREATE INDEX idx_competition_events_event ON competition_events(event_id);
CREATE INDEX idx_participant_statistics_participant ON participant_statistics(participant_id);
CREATE INDEX idx_participant_statistics_event ON participant_statistics(event_id);
CREATE INDEX idx_mle_predictions_participant ON mle_predictions(participant_id);
CREATE INDEX idx_mle_predictions_event ON mle_predictions(event_id);

-- ============================================
-- 16. 刷新 schema 缓存
-- ============================================
SELECT pg_notify('pgrst', 'reload schema');
SELECT 'schema-v5 数据库初始化完成！' AS status;
