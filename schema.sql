-- 魔方比赛成绩数据库 Schema
-- 适用于 Supabase (PostgreSQL)
-- 创建时间: 2026-06-05

-- ============================================
-- 1. 比赛表 (competitions)
-- ============================================
CREATE TABLE IF NOT EXISTS competitions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    competition_number VARCHAR(50) UNIQUE NOT NULL,  -- 比赛唯一编号，如 "COMP-2026-001"
    name VARCHAR(255) NOT NULL,                      -- 比赛名称
    competition_date DATE NOT NULL,                   -- 比赛日期
    location VARCHAR(255),                           -- 比赛地点
    organizer VARCHAR(255),                          -- 主办方
    description TEXT,                                -- 比赛描述
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 创建索引
CREATE INDEX idx_competitions_number ON competitions(competition_number);
CREATE INDEX idx_competitions_date ON competitions(competition_date DESC);

-- ============================================
-- 2. 选手表 (participants) - 可选，用于管理选手信息
-- ============================================
CREATE TABLE IF NOT EXISTS participants (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(100) NOT NULL,                     -- 选手称呼/名称
    nickname VARCHAR(100),                          -- 昵称
    email VARCHAR(255),                             -- 邮箱（可选）
    notes TEXT,                                     -- 备注
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 创建索引
CREATE INDEX idx_participants_name ON participants(name);

-- ============================================
-- 3. 尝试记录表 (attempts) - 核心表
-- ============================================
CREATE TABLE IF NOT EXISTS attempts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    attempt_number VARCHAR(50) UNIQUE NOT NULL,     -- 唯一编号，如 "COMP-2026-001-ATT-001"
    
    -- 关联信息
    competition_id UUID REFERENCES competitions(id) ON DELETE CASCADE,
    participant_id UUID REFERENCES participants(id) ON DELETE SET NULL,
    participant_name VARCHAR(100) NOT NULL,         -- 冗余字段，方便查询
    
    -- 尝试序号（在某比赛中的第几次尝试）
    attempt_index INTEGER NOT NULL,                  -- 第几次尝试（1, 2, 3...）
    
    -- 魔方信息
    cube_type VARCHAR(20) NOT NULL CHECK (cube_type IN ('smart', 'non_smart')),  -- 智能/非智能
    cube_name VARCHAR(100),                         -- 魔方型号/名称（如 "魔域智能魔方"、"GAN12"）
    cube_category VARCHAR(50),                      -- 魔方类别（如 "3x3", "2x2", "Pyraminx"）
    
    -- 打乱与复原
    scramble TEXT NOT NULL,                         -- 打乱公式
    solve_time DECIMAL(10,3) NOT NULL,             -- 复原时间（秒，保留3位小数）
    is_dnf BOOLEAN DEFAULT FALSE,                   -- 是否 DNF (Did Not Finish)
    is_plus_two BOOLEAN DEFAULT FALSE,              -- 是否 +2 惩罚
    
    -- 智能魔方专属数据
    move_count INTEGER,                             -- 步数（仅智能魔方）
    tps DECIMAL(5,2),                             -- 每秒步数（仅智能魔方）
    solve_steps JSONB,                              -- 复原步骤详情（仅智能魔方，存储详细步骤）
    
    -- 非智能魔方可选数据
    video_url TEXT,                                 -- 录像链接（非智能魔方，用于复盘）
    
    -- 其他信息
    notes TEXT,                                     -- 备注
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- 约束：智能魔方必须有步数和TPS
    CONSTRAINT smart_cube_has_move_data CHECK (
        cube_type = 'non_smart' OR 
        (cube_type = 'smart' AND move_count IS NOT NULL AND tps IS NOT NULL)
    )
);

-- 创建索引
CREATE INDEX idx_attempts_competition ON attempts(competition_id);
CREATE INDEX idx_attempts_participant ON attempts(participant_id);
CREATE INDEX idx_attempts_attempt_number ON attempts(attempt_number);
CREATE INDEX idx_attempts_cube_type ON attempts(cube_type);
CREATE INDEX idx_attempts_solve_time ON attempts(solve_time);
CREATE INDEX idx_attempts_created_at ON attempts(created_at DESC);

-- ============================================
-- 4. 创建更新时间触发器
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_competitions_updated_at BEFORE UPDATE ON competitions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_attempts_updated_at BEFORE UPDATE ON attempts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 5. 启用 Row Level Security (RLS)
-- ============================================
ALTER TABLE competitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempts ENABLE ROW LEVEL SECURITY;

-- 创建开放策略（允许所有人读写，你可以根据需要修改）
CREATE POLICY "Allow public read access on competitions" ON competitions
    FOR SELECT USING (true);

CREATE POLICY "Allow public insert access on competitions" ON competitions
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow public update access on competitions" ON competitions
    FOR UPDATE USING (true);

CREATE POLICY "Allow public read access on participants" ON participants
    FOR SELECT USING (true);

CREATE POLICY "Allow public insert access on participants" ON participants
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow public read access on attempts" ON attempts
    FOR SELECT USING (true);

CREATE POLICY "Allow public insert access on attempts" ON attempts
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow public update access on attempts" ON attempts
    FOR UPDATE USING (true);

-- ============================================
-- 6. 创建视图 - 方便查询统计数据
-- 使用 SECURITY INVOKER 确保遵循 RLS 策略
-- ============================================

-- 比赛统计视图
CREATE OR REPLACE VIEW competition_stats
WITH (security_invoker = true) AS
SELECT 
    c.id AS competition_id,
    c.competition_number,
    c.name AS competition_name,
    c.competition_date,
    COUNT(DISTINCT a.participant_id) AS total_participants,
    COUNT(a.id) AS total_attempts,
    AVG(CASE WHEN a.is_dnf = FALSE AND a.is_plus_two = FALSE THEN a.solve_time END) AS avg_time,
    MIN(CASE WHEN a.is_dnf = FALSE THEN a.solve_time END) AS best_time,
    COUNT(CASE WHEN a.cube_type = 'smart' THEN 1 END) AS smart_cube_attempts,
    COUNT(CASE WHEN a.cube_type = 'non_smart' THEN 1 END) AS non_smart_cube_attempts
FROM competitions c
LEFT JOIN attempts a ON c.id = a.competition_id
GROUP BY c.id, c.competition_number, c.name, c.competition_date;

-- 选手统计视图
CREATE OR REPLACE VIEW participant_stats
WITH (security_invoker = true) AS
SELECT 
    p.id AS participant_id,
    p.name AS participant_name,
    COUNT(DISTINCT a.competition_id) AS total_competitions,
    COUNT(a.id) AS total_attempts,
    AVG(CASE WHEN a.is_dnf = FALSE AND a.is_plus_two = FALSE THEN a.solve_time END) AS avg_time,
    MIN(CASE WHEN a.is_dnf = FALSE THEN a.solve_time END) AS best_time,
    AVG(CASE WHEN a.cube_type = 'smart' THEN a.tps END) AS avg_tps_smart,
    AVG(CASE WHEN a.cube_type = 'smart' THEN a.move_count END) AS avg_moves_smart
FROM participants p
LEFT JOIN attempts a ON p.id = a.participant_id
GROUP BY p.id, p.name;

-- ============================================
-- 7. 插入示例数据（可选，用于测试）
-- ============================================

-- 插入示例比赛
INSERT INTO competitions (competition_number, name, competition_date, location, organizer)
VALUES 
    ('COMP-2026-001', '2026春季魔方赛', '2026-06-15', '北京', '中国魔方协会'),
    ('COMP-2026-002', '线上智能魔方挑战赛', '2026-06-20', '线上', 'SmartCube组委会')
ON CONFLICT (competition_number) DO NOTHING;

-- 插入示例选手
INSERT INTO participants (name, nickname)
VALUES 
    ('张三', 'SpeedCubeMaster'),
    ('李四', 'CubeWizard')
ON CONFLICT DO NOTHING;

-- ============================================
-- 完成提示
-- ============================================
COMMENT ON TABLE competitions IS '比赛信息表';
COMMENT ON TABLE participants IS '选手信息表';
COMMENT ON TABLE attempts IS '尝试记录表 - 核心数据表';

SELECT '数据库 schema 创建成功！' AS status;
