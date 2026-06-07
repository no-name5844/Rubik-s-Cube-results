-- ============================================
-- 升级脚本 v4：添加层级项目和算法配置
-- 功能：
--   1. events 表添加 parent_event_id（自引用）
--   2. events 表添加 algorithm_config（算法配置）
--   3. 创建 event_algorithms 表（算法模板库）
--   4. 更新视图和函数
-- ============================================

-- 备份提示
SELECT '开始升级到 v4...' AS status;

-- ============================================
-- 1. 为 events 表添加新字段
-- ============================================

-- 添加父项目 ID（自引用）
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS parent_event_id UUID REFERENCES events(id) ON DELETE CASCADE;

-- 添加算法配置（JSONB）
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS algorithm_config JSONB DEFAULT '{}'::jsonb;

-- 添加是否为子项目标志（可选，可通过 parent_event_id 判断）
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS is_sub_event BOOLEAN DEFAULT FALSE;

-- 添加排序字段
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0;

-- 添加注释
COMMENT ON COLUMN events.parent_event_id IS '父项目 ID，NULL 表示顶级项目';
COMMENT ON COLUMN events.is_sub_event IS '是否为子项目（TRUE=子项目，FALSE=顶级项目）';
COMMENT ON COLUMN events.algorithm_config IS '算法配置（JSON 格式）：
{
  "algorithm_type": "average",     -- 算法类型：single, average, best_of, sub
  "window_size": 5,               -- 窗口大小（如 AO5 的 5）
  "trim_count": 1,                 -- 去掉头尾数量（average 类型）
  "is_lower_better": true,         -- 是否越小越好
  "threshold": null,               -- 阈值（sub 类型，如 10.000 表示 sub-10）
  "custom_formula": null,          -- 自定义公式（高级用法）
  "inherit_from_parent": true      -- 是否继承父项目配置
}';
COMMENT ON COLUMN events.sort_order IS '排序权重，越小越靠前';

-- 为 parent_event_id 创建索引
CREATE INDEX IF NOT EXISTS idx_events_parent ON events(parent_event_id);

-- ============================================
-- 2. 创建算法模板表
-- ============================================

CREATE TABLE IF NOT EXISTS event_algorithms (
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
-- 3. 更新现有项目：添加子项目
-- ============================================

-- 为现有项目添加子项目示例（三阶）
-- 先检查是否已有子项目，避免重复插入

-- 三阶 Single
INSERT INTO events (event_code, event_name, description, puzzle_type, parent_event_id, is_sub_event, algorithm_config, sort_order)
SELECT '3x3-single', '三阶 - 单次', '三阶速拧单次成绩', 'cube', id, TRUE, '{
  "algorithm_type": "single",
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, 1
FROM events 
WHERE event_code = '3x3' AND NOT EXISTS (
    SELECT 1 FROM events WHERE event_code = '3x3-single'
);

-- 三阶 Average (AO5)
INSERT INTO events (event_code, event_name, description, puzzle_type, parent_event_id, is_sub_event, algorithm_config, sort_order)
SELECT '3x3-ao5', '三阶 - AO5', '三阶速拧最近 5 次平均', 'cube', id, TRUE, '{
  "algorithm_type": "average",
  "window_size": 5,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, 2
FROM events 
WHERE event_code = '3x3' AND NOT EXISTS (
    SELECT 1 FROM events WHERE event_code = '3x3-ao5'
);

-- 三阶 AO12
INSERT INTO events (event_code, event_name, description, puzzle_type, parent_event_id, is_sub_event, algorithm_config, sort_order)
SELECT '3x3-ao12', '三阶 - AO12', '三阶速拧最近 12 次平均', 'cube', id, TRUE, '{
  "algorithm_type": "average",
  "window_size": 12,
  "trim_count": 1,
  "is_lower_better": true,
  "inherit_from_parent": false
}'::jsonb, 3
FROM events 
WHERE event_code = '3x3' AND NOT EXISTS (
    SELECT 1 FROM events WHERE event_code = '3x3-ao12'
);

-- ============================================
-- 4. 创建函数：获取项目的完整配置（继承父项目）
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
-- 5. 创建函数：计算成绩（根据算法配置）
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
-- 6. 更新视图
-- ============================================

DROP VIEW IF EXISTS event_config_view;

CREATE OR REPLACE VIEW event_config_view
WITH (security_invoker = true)
AS
SELECT 
    e.id,
    e.event_code,
    e.event_name,
    e.description,
    e.puzzle_type,
    e.event_config,
    e.algorithm_config,
    e.parent_event_id,
    e.is_sub_event,
    e.sort_order,
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
-- 7. 刷新 schema 缓存
-- ============================================
SELECT pg_notify('pgrst', 'reload schema');

-- 完成提示
SELECT '数据库升级到 v4 完成！
- events 表支持层级结构（父子项目）
- 添加 algorithm_config 字段（算法配置）
- 创建 event_algorithms 表（算法模板库）
- 自动为「三阶」创建 3 个子项目（Single, AO5, AO12）
- 提供 get_event_full_config() 函数（配置继承）
- 提供 calculate_statistic() 函数（动态计算统计）
- 更新 event_config_view 视图（显示层级关系）' AS status;
