-- ============================================
-- 修复 Security Definer View 问题
-- ============================================

-- 方法：重新创建视图，并显式设置 SECURITY INVOKER

-- 1. 删除现有视图
DROP VIEW IF EXISTS public.competition_stats;
DROP VIEW IF EXISTS public.participant_stats;

-- 2. 重新创建 competition_stats 视图（添加 SECURITY INVOKER）
CREATE OR REPLACE VIEW public.competition_stats
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

-- 3. 重新创建 participant_stats 视图（添加 SECURITY INVOKER）
CREATE OR REPLACE VIEW public.participant_stats
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

-- 4. 设置视图权限（允许公钥读取）
GRANT SELECT ON public.competition_stats TO anon;
GRANT SELECT ON public.participant_stats TO anon;

-- 5. 添加注释
COMMENT ON VIEW public.competition_stats IS '比赛统计视图 - 使用 SECURITY INVOKER';
COMMENT ON VIEW public.participant_stats IS '选手统计视图 - 使用 SECURITY INVOKER';

-- 完成提示
SELECT 'Security Definer 问题已修复！视图现在使用 SECURITY INVOKER。' AS status;
