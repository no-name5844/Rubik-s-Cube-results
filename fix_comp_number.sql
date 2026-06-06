-- ============================================
-- 修复：将 competition_number 从 INTEGER 改为 TEXT
-- 用于已存在的数据库（已在 Supabase 中运行的项目）
-- ============================================

-- 1. 先删除依赖这个字段的外键/索引/视图（如果有的话）
-- 注意：如果 competitions 表已有数据，需要先备份

-- 2. 修改字段类型（PostgreSQL 需要特殊处理）
-- 方法：添加新 TEXT 列 → 迁移数据 → 删除旧列 → 重命名
ALTER TABLE competitions ADD COLUMN competition_number_new TEXT;
UPDATE competitions SET competition_number_new = competition_number::TEXT;
ALTER TABLE competitions DROP COLUMN competition_number;
ALTER TABLE competitions RENAME COLUMN competition_number_new TO competition_number;

-- 3. 添加唯一约束
ALTER TABLE competitions ADD CONSTRAINT competitions_competition_number_key UNIQUE (competition_number);

-- 4. 刷新 schema 缓存
SELECT pg_notify('pgrst', 'reload schema');

SELECT 'competition_number 字段类型已改为 TEXT' AS status;
