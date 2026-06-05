-- ============================================
-- 魔方比赛成绩管理系统 v3 - 完整数据库
-- 功能：项目管理、Gamma MLE、自动统计、可视化
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

CREATE TABLE competitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_number INTEGER UNIQUE NOT NULL,
    name TEXT NOT NULL,
    competition_date DATE NOT NULL,
    location TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 2. 项目/魔方类型表 (events)
-- 高度可自定义，用户可添加任意项目
-- ============================================
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_code VARCHAR(20) UNIQUE NOT NULL,     -- 如 '3x3', '2x2', 'pyraminx'
    event_name VARCHAR(100) NOT NULL,            -- 如 '三阶魔方'
    description TEXT,
    puzzle_type VARCHAR(50),                     -- 'cube', 'pyramid', 'other'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 插入默认项目
INSERT INTO events (event_code, event_name, description, puzzle_type) VALUES
('3x3', '三阶魔方', '标准三阶速拧', 'cube'),
('2x2', '二阶魔方', '二阶速拧', 'cube'),
('4x4', '四阶魔方', '四阶速拧', 'cube'),
('5x5', '五阶魔方', '五阶速拧', 'cube'),
('6x6', '六阶魔方', '六阶速拧', 'cube'),
('7x7', '七阶魔方', '七阶速拧', 'cube'),
('pyraminx', '金字塔', '金字塔魔方', 'pyramid'),
('megaminx', '五魔方', '十二面体魔方', 'other'),
('skewb', '斜转魔方', 'Skewb', 'other'),
('sq1', 'Square-1', 'SQ1', 'other'),
('oh', '单手', '三阶单手', 'cube'),
('bld', '盲拧', '三阶盲拧', 'cube'),
('fmc', '最少步', 'Fewest Moves Challenge', 'cube');

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
-- ============================================
CREATE TABLE attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_event_id UUID REFERENCES competition_events(id) ON DELETE CASCADE,
    participant_id UUID REFERENCES participants(id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,             -- 第几次尝试
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
    PRIMARY KEY (participant_id, event_id, stat_definition_id)
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
-- 9. 启用行级安全 (RLS)
-- ============================================
ALTER TABLE competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE statistics_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE participant_statistics ENABLE ROW LEVEL SECURITY;
ALTER TABLE mle_predictions ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 10. 创建宽松的 RLS 策略（允许匿名访问）
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

-- 授予匿名用户权限
GRANT ALL ON competitions TO anon;
GRANT ALL ON events TO anon;
GRANT ALL ON competition_events TO anon;
GRANT ALL ON participants TO anon;
GRANT ALL ON attempts TO anon;
GRANT ALL ON statistics_definitions TO anon;
GRANT ALL ON participant_statistics TO anon;
GRANT ALL ON mle_predictions TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;

-- ============================================
-- 11. 创建视图 - 方便查询（使用 SECURITY INVOKER）
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

-- ============================================
-- 12. 创建索引以提升查询性能
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
-- 完成提示
-- ============================================
SELECT 'schema-v3 数据库初始化完成！' AS status;
SELECT '包含：比赛、项目、成绩、统计定义、MLE预测等表' AS details;
