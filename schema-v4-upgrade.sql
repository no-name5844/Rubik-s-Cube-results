-- ============================================
-- 升级脚本：添加项目自定义配置支持
-- 功能：1. 添加 event_config 字段  2. 修改尝试编号为文本类型
-- ============================================

-- 备份提示
SELECT '开始升级数据库...' AS status;

-- ============================================
-- 1. 为 events 表添加 event_config 字段
-- ============================================

-- 添加新列，存储项目的自定义配置（JSON 格式）
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS event_config JSONB DEFAULT '{}'::jsonb;

-- 添加注释
COMMENT ON COLUMN events.event_config IS '项目自定义配置（JSON格式）：
{
  "supports_smart_cube": true,     -- 是否支持智能魔方
  "record_steps": true,             -- 是否记录步数
  "record_tps": true,              -- 是否记录 TPS
  "record_video": false,            -- 是否记录视频链接
  "penalty_types": ["none", "+2", "DNF"],  -- 支持的惩罚类型
  "attempt_id_type": "number",      -- 尝试编号类型："number" | "text" | "custom"
  "attempt_id_label": "尝试编号",  -- 尝试编号的显示标签
  "max_attempts": 5,               -- 最大尝试次数（可选）
  "best_of": 1,                    -- 取最佳 N 次（如：三局两胜）
  "custom_fields": []                -- 自定义字段列表（高级用法）
}';

-- 为现有项目添加默认配置
UPDATE events SET event_config = '{
  "supports_smart_cube": true,
  "record_steps": true,
  "record_tps": true,
  "record_video": true,
  "penalty_types": ["none", "+2", "DNF"],
  "attempt_id_type": "number",
  "attempt_id_label": "尝试编号",
  "max_attempts": 5
}'::jsonb WHERE event_config = '{}'::jsonb;

-- ============================================
-- 2. 修改 attempts 表的 attempt_number 字段
-- ============================================

-- 首先删除依赖此字段的唯一约束
ALTER TABLE attempts DROP CONSTRAINT IF EXISTS attempts_competition_event_id_participant_id_attempt_number_key;

-- 修改字段类型为 TEXT（支持更灵活的编号）
ALTER TABLE attempts 
ALTER COLUMN attempt_number TYPE TEXT USING attempt_number::TEXT;

-- 重命名字段（可选，但更语义化）
-- 注意：为了保持代码兼容性，这里不重命名，只是修改类型和注释

-- 更新注释
COMMENT ON COLUMN attempts.attempt_number IS '尝试编号（文本类型，支持灵活编号）';

-- 添加新的唯一约束
ALTER TABLE attempts 
ADD CONSTRAINT attempts_unique_attempt 
UNIQUE(competition_event_id, participant_id, attempt_number);

-- ============================================
-- 3. 创建一个视图：方便查询项目的自定义配置
-- ============================================

CREATE OR REPLACE VIEW event_config_view
WITH (security_invoker = true)
AS
SELECT 
    id,
    event_code,
    event_name,
    event_config,
    event_config->>'attempt_id_label' AS attempt_id_label,
    event_config->>'attempt_id_type' AS attempt_id_type,
    (event_config->>'supports_smart_cube')::boolean AS supports_smart_cube,
    (event_config->>'record_steps')::boolean AS record_steps,
    (event_config->>'record_tps')::boolean AS record_tps
FROM events;

-- ============================================
-- 4. 创建函数：根据项目配置动态生成表单
-- ============================================

CREATE OR REPLACE FUNCTION get_event_form_config(event_id UUID)
RETURNS JSONB AS $$
DECLARE
    config JSONB;
BEGIN
    SELECT event_config INTO config
    FROM events
    WHERE id = event_id;
    
    RETURN COALESCE(config, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. 刷新 schema 缓存
-- ============================================
SELECT pg_notify('pgrst', 'reload schema');

-- 完成提示
SELECT '数据库升级完成！
- events 表现在有 event_config 字段（JSONB）
- attempts 表的 attempt_number 改为 TEXT 类型
- 可以使用 event_config_view 视图查询配置
- 可以使用 get_event_form_config() 函数获取表单配置' AS status;
