-- ============================================
-- 魔方比赛成绩管理系统 v4 - 完整数据库
-- 功能：层级项目结构、算法配置、Gamma MLE、高度可自定义统计
-- ============================================

-- 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 1. 比赛表 (competitions)
-- ============================================
DROP TABLE IF EXISTS attempts CASCADE;
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
    competition_number TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    competition_date DATE NOT NULL,
    location TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 2. 项目/魔方类型表 (events)
-- 支持层级结构（父子项目）和算法配置
-- ============================================
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_code VARCHAR(20) UNIQUE NOT NULL,     -- 如 '3x3', '2x2', 'pyraminx'
    event_name VARCHAR(100) NOT NULL,            -- 如 '三阶魔方'
    description TEXT,
    puzzle_type VARCHAR(50),                     -- 'cube', 'pyramid', 'other'
    parent_event_id UUID REFERENCES events(id) ON DELETE CASCADE,  -- 父项目 ID
    is_sub_event BOOLEAN DEFAULT FALSE,         -- 是否为子项目
    sort_order INTEGER DEFAULT 0,                -- 排序权重
    event_config JSONB DEFAULT '{}'::jsonb,     -- 项目自定义配置
    algorithm_config JSONB DEFAULT '{}'::jsonb, -- 算法配置
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON COLUMN events.parent_event_id IS '父项目 ID，NULL 表示顶级项目';
COMMENT ON COLUMN events.is_sub_event IS '是否为子项目（TRUE=子项目，FALSE=顶级项目）';
COMMENT ON COLUMN events.sort_order IS '排序权重，越小越靠前';
COMMENT ON COLUMN events.event_config IS '项目自定义配置（JSON格式）';
COMMENT ON COLUMN events.algorithm_config IS '算法配置（JSON格式）';

-- 为 parent_event_id 创建索引
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
    algorithm_code VARCHAR(50) UNIQUE NOT NULL,  -- 算法代码
    algorithm_name VARCHAR(100) NOT NULL,          -- 算法名称
    description TEXT,                               -- 描述
    config_template JSONB NOT NULL,                -- 配置模板（JSON）
    is_builtin BOOLEAN DEFAULT TRUE,             -- 是否为内置算法
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

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
-- 每场比赛可以有不同的项目组合
-- ============================================
CREATE TABLE competition_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_id UUID REFERENCES competitions(id) ON DELETE CASCADE,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    event_number INTEGER NOT NULL,               -- 比赛中的项目编号（如第1个项目）
    UNIQUE(competition_id, event_id),
    UNIQUE(competition_id, event_number)
);

-- ============================================
-- 4. 选手表 (participants)
-- ============================================
CREATE TABLE participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    wca_id VARCHAR(20),                          -- WCA ID（如有）
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 5. 成绩记录表 (attempts)
-- 关联到 competition_events（具体比赛的具体项目）
-- attempt_number 为文本类型，支持灵活编号
-- ============================================
CREATE TABLE attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_event_id UUID REFERENCES competition_events(id) ON DELETE CASCADE,
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    attempt_number TEXT NOT NULL,                -- 尝试编号（文本类型，灵活标识）
    solve_time DECIMAL(10,3),                    -- 复原时间（秒），DNF时为NULL
    cube_type VARCHAR(20) NOT NULL CHECK (cube_type IN ('smart', 'non_smart')),
    scramble TEXT,                               -- 打乱公式
    move_count INTEGER,                          -- 步数（仅智能魔方）
    tps DECIMAL(10,3),                          -- TPS（仅智能魔方）
    solve_steps JSONB,                           -- 复原步骤 + C++ 注释
    step_comments TEXT,                          -- C++ 格式注释文本（如 // F2L, // OLL）
    is_dnf BOOLEAN DEFAULT FALSE,                -- 是否 DNF
    is_plus_two BOOLEAN DEFAULT FALSE,           -- 是否 +2 秒
    video_url TEXT,                              -- 录像链接（非智能魔方可填）
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(competition_event_id, participant_id, attempt_number)
);

-- ============================================
-- 6. 统计定义表 (statistics_definitions)
-- 高度可自定义的统计类型
-- ============================================
CREATE TABLE statistics_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stat_code VARCHAR(50) UNIQUE NOT NULL,       -- 标识符
    stat_name VARCHAR(100) NOT NULL,              -- 显示名称
    calculation_type VARCHAR(20) NOT NULL,        -- 'single', 'average', 'best_average', 'sub'
    window_size INTEGER,                          -- 计算窗口（5 for AO5, NULL for all-time）
    is_lower_better BOOLEAN DEFAULT TRUE,         -- 是否越小越好（时间类 true，得分类 false）
    threshold_value DECIMAL(10,3),                -- 用于 'sub' 类型（如 10.000 表示 sub-10）
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

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
-- 7. 选手统计数据表 (participant_statistics)
-- 自动计算并存储统计结果
-- ============================================
CREATE TABLE participant_statistics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    stat_definition_id UUID REFERENCES statistics_definitions(id) ON DELETE CASCADE,
    stat_value DECIMAL(10,3),                    -- 计算出的统计值
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(participant_id, event_id, stat_definition_id)
);

-- ============================================
-- 8. MLE 预测结果表 (mle_predictions)
-- 存储 Gamma 分布参数和预测结果
-- ============================================
CREATE TABLE mle_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    alpha DECIMAL(10,3) NOT NULL,               -- Gamma 形状参数
    beta DECIMAL(10,3) NOT NULL,                -- Gamma 尺度参数
    mode_value DECIMAL(10,3) NOT NULL,           -- 众数（真实水平 = (alpha-1)/beta）
    mean_value DECIMAL(10,3) NOT NULL,           -- 均值 = alpha/beta
    variance_value DECIMAL(10,3) NOT NULL,       -- 方差 = alpha/beta^2
    sample_size INTEGER NOT NULL,                  -- 用于拟合的样本量
    confidence_interval JSONB,                     -- 置信区间 [lower, upper]
    predicted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 9. 创建函数：获取项目的完整配置（继承父项目）
-- ============================================
CREATE OR REPLACE FUNCTION get_event_full_config(event_id UUID)
RETURNS JSONB AS $$
DECLARE
    config JSONB;
    parent_id UUID;
    parent_config JSONB;
BEGIN
    -- 获取当前项目的配置和父项目 ID
    SELECT algorithm_config, parent_event_id 
    INTO config, parent_id
    FROM events 
    WHERE id = event_id;
    
    -- 如果有父项目且配置中标记继承，则合并父项目配置
    IF parent_id IS NOT NULL THEN
        SELECT get_event_full_config(parent_id) INTO parent_config;
        
        -- 合并配置（子项目覆盖父项目的相同键）
        config = COALESCE(parent_config, '{}'::jsonb) || COALESCE(config, '{}'::jsonb);
    END IF;
    
    RETURN COALESCE(config, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 10. 创建函数：计算成绩（根据算法配置）
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
    -- 获取算法配置（如果未提供，则从数据库读取）
    IF p_algorithm_config IS NULL THEN
        SELECT get_event_full_config(p_event_id) INTO config;
    ELSE
        config = p_algorithm_config;
    END IF;
    
    -- 解析配置
    algo_type = config->>'algorithm_type';
    window_size = (config->>'window_size')::INT;
    trim_count = COALESCE((config->>'trim_count')::INT, 0);
    is_lower_better = COALESCE((config->>'is_lower_better')::BOOLEAN, TRUE);
    
    -- 获取成绩数据
    SELECT ARRAY_AGG(solve_time ORDER BY created_at)
    INTO times
    FROM attempts a
    JOIN competition_events ce ON a.competition_event_id = ce.id
    WHERE a.participant_id = p_participant_id
      AND ce.event_id = p_event_id
      AND a.is_dnf = FALSE
      AND a.is_plus_two = FALSE
      AND a.solve_time IS NOT NULL;
    
    -- 如果无数据，返回 NULL
    IF times IS NULL OR array_length(times, 1) = 0 THEN
        RETURN NULL;
    END IF;
    
    -- 根据算法类型计算
    IF algo_type = 'single' THEN
        -- 单次最佳
        SELECT MIN(unnest) INTO result FROM unnest(times);
        
    ELSIF algo_type = 'average' THEN
        -- 平均（可指定窗口大小）
        IF window_size IS NOT NULL AND array_length(times, 1) >= window_size THEN
            -- 取最近 window_size 次
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
            -- 全部平均
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
        -- 简单算术平均
        SELECT AVG(unnest) INTO result FROM unnest(times);
        
    ELSIF algo_type = 'best_of' THEN
        -- 最佳 N 次中的最佳（就是单次最佳）
        SELECT MIN(unnest) INTO result FROM unnest(times);
        
    ELSIF algo_type = 'sub' THEN
        -- SUB-X：返回低于阈值的比率（百分比）
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
-- 11. 启用行级安全 (RLS)
-- ============================================
ALTER TABLE competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE statistics_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE participant_statistics ENABLE ROW LEVEL SECURITY;
ALTER TABLE mle_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_algorithms ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 12. 创建宽松的 RLS 策略（允许匿名访问）
-- 生产环境请根据需要调整
-- ============================================
CREATE POLICY "Allow all access on competitions" ON competitions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on events" ON events FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on competition_events" ON competition_events FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on participants" ON participants FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on attempts" ON attempts FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on statistics_definitions" ON statistics_definitions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on participant_statistics" ON participant_statistics FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on mle_predictions" ON mle_predictions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all access on event_algorithms" ON event_algorithms FOR ALL USING (true) WITH CHECK (true);

-- 授予匿名用户权限
GRANT ALL ON competitions TO anon;
GRANT ALL ON events TO anon;
GRANT ALL ON competition_events TO anon;
GRANT ALL ON participants TO anon;
GRANT ALL ON attempts TO anon;
GRANT ALL ON statistics_definitions TO anon;
GRANT ALL ON participant_statistics TO anon;
GRANT ALL ON mle_predictions TO anon;
GRANT ALL ON event_algorithms TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;

-- ============================================
-- 13. 创建视图 - 方便查询（使用 SECURITY INVOKER）
-- ============================================

-- 比赛统计视图
CREATE OR REPLACE VIEW competition_stats
WITH (security_invoker = true) AS
SELECT 
    c.id AS competition_id,
    c.competition_number,
    c.name AS competition_name,
    c.competition_date,
    e.event_code,
    e.event_name,
    COUNT(DISTINCT a.participant_id) AS total_participants,
    COUNT(a.id) AS total_attempts,
    AVG(CASE WHEN a.is_dnf = FALSE AND a.is_plus_two = FALSE THEN a.solve_time END) AS avg_time,
    MIN(CASE WHEN a.is_dnf = FALSE THEN a.solve_time END) AS best_time,
    COUNT(CASE WHEN a.cube_type = 'smart' THEN 1 END) AS smart_cube_attempts,
    COUNT(CASE WHEN a.cube_type = 'non_smart' THEN 1 END) AS non_smart_cube_attempts
FROM competitions c
LEFT JOIN competition_events ce ON c.id = ce.competition_id
LEFT JOIN events e ON ce.event_id = e.id
LEFT JOIN attempts a ON ce.id = a.competition_event_id
GROUP BY c.id, c.competition_number, c.name, c.competition_date, e.event_code, e.event_name;

-- 选手统计视图
CREATE OR REPLACE VIEW participant_stats
WITH (security_invoker = true) AS
SELECT 
    p.id AS participant_id,
    p.name AS participant_name,
    e.event_code,
    e.event_name,
    COUNT(DISTINCT ce.competition_id) AS total_competitions,
    COUNT(a.id) AS total_attempts,
    AVG(CASE WHEN a.is_dnf = FALSE AND a.is_plus_two = FALSE THEN a.solve_time END) AS avg_time,
    MIN(CASE WHEN a.is_dnf = FALSE THEN a.solve_time END) AS best_time,
    AVG(CASE WHEN a.cube_type = 'smart' THEN a.tps END) AS avg_tps_smart,
    AVG(CASE WHEN a.cube_type = 'smart' THEN a.move_count END) AS avg_moves_smart
FROM participants p
LEFT JOIN attempts a ON p.id = a.participant_id
LEFT JOIN competition_events ce ON a.competition_event_id = ce.id
LEFT JOIN events e ON ce.event_id = e.id
GROUP BY p.id, p.name, e.event_code, e.event_name;

-- 项目配置视图（显示层级关系）
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
-- 14. 创建索引以提升查询性能
-- ============================================
CREATE INDEX idx_attempts_participant ON attempts(participant_id);
CREATE INDEX idx_attempts_competition_event ON attempts(competition_event_id);
CREATE INDEX idx_competition_events_competition ON competition_events(competition_id);
CREATE INDEX idx_competition_events_event ON competition_events(event_id);
CREATE INDEX idx_participant_statistics_participant ON participant_statistics(participant_id);
CREATE INDEX idx_participant_statistics_event ON participant_statistics(event_id);
CREATE INDEX idx_mle_predictions_participant ON mle_predictions(participant_id);
CREATE INDEX idx_mle_predictions_event ON mle_predictions(event_id);

-- ============================================
-- 15. 刷新 schema 缓存（重要！）
-- 否则 Supabase 客户端可能找不到新建的表
-- ============================================
SELECT pg_notify('pgrst', 'reload schema');
SELECT 'schema-v4 数据库初始化完成！' AS status;
