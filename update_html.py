#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
更新 index-v3.html 以支持层级项目和算法配置
"""

import re

# 读取文件
with open('index-v3.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. 在"项目代码"前添加"父项目"选择器
old1 = '''                        <div class="form-group">
                            <label>项目代码</label>'''
new1 = '''                        <div class="form-group">
                            <label>父项目（可选）</label>
                            <select id="event-parent" onchange="toggleSubEvent()">
                                <option value="">-- 顶级项目（无父项目）--</option>
                            </select>
                            <small style="color: #6c757d; margin-top: 5px; display: block;">
                                选择父项目会创建子项目（如：三阶 → 三阶-AO5）
                            </small>
                        </div>
                        <div class="form-group">
                            <label>项目代码</label>'''

if old1 in content:
    content = content.replace(old1, new1)
    print("✅ 添加了父项目选择器")
else:
    print("⚠️ 未找到'项目代码'位置")

# 2. 在"描述"字段后添加"算法配置"输入区域
old2 = '''                        <div class="form-group">
                            <label>描述</label>
                            <textarea id="event-desc" rows="3"></textarea>
                        </div>
                        <button class="btn" onclick="addEvent()">➕ 添加项目</button>'''
new2 = '''                        <div class="form-group">
                            <label>描述</label>
                            <textarea id="event-desc" rows="3"></textarea>
                        </div>
                        <div class="form-group" id="algo-config-form">
                            <label>算法配置 (JSON 格式）</label>
                            <textarea id="event-algo-config" rows="10" style="font-family: 'Courier New', monospace; font-size: 13px;" placeholder='{
  "algorithm_type": "single",
  "is_lower_better": true,
  "trim_count": 0,
  "window_size": null
}'></textarea>
                            <small style="color: #6c757d; margin-top: 5px; display: block;">
                                算法类型：single（单次）、average（平均）、mean（算术平均）、best_of（最佳N次）、sub（低于阈值比率）
                            </small>
                        </div>
                        <button class="btn" onclick="addEvent()">➕ 添加项目</button>
                        <button class="btn btn-success" onclick="loadAlgoTemplate()" style="margin-left: 10px;">📋 加载算法模板</button>'''

if old2 in content:
    content = content.replace(old2, new2)
    print("✅ 添加了算法配置表单")
else:
    print("⚠️ 未找到'描述'字段位置")

# 3. 更新"项目列表"表格，显示层级关系
# 这个需要在 JavaScript 中更新 loadEvents() 函数
# 先标记需要修改的位置
if 'loadEvents()' in content:
    print("📝 需要更新 loadEvents() 函数以显示层级关系")
    print("   - 需要修改 Tabulator 列定义")
    print("   - 需要缩进子项目")

# 4. 更新 addEvent() 函数以支持 parent_event_id
if 'async function addEvent()' in content:
    print("📝 需要更新 addEvent() 函数以保存 parent_event_id")
    print("   - 需要获取 event-parent 的值")
    print("   - 需要保存到数据库")

# 5. 添加新的 JavaScript 函数
new_functions = '''        
        // ========= 算法模板功能 =========
        
        // 加载算法模板
        async function loadAlgoTemplate() {
            var eventId = document.getElementById('config-event-select').value;
            if (!eventId) {
                showAlert('请先选择项目', 'error');
                return;
            }
            
            // 获取算法模板列表
            var { data, error } = await dbClient
                .from('event_algorithms')
                .select('*')
                .order('algorithm_code');
            
            if (error) {
                showAlert('加载算法模板失败：' + error.message, 'error');
                return;
            }
            
            // 简单实现：使用第一个模板
            if (data && data.length > 0) {
                document.getElementById('event-algo-config').value = 
                    JSON.stringify(data[0].config_template, null, 2);
                showAlert('已加载算法模板：' + data[0].algorithm_name, 'success');
            }
        }
        
        // 切换子项目表单
        function toggleSubEvent() {
            var parentId = document.getElementById('event-parent').value;
            var algoForm = document.getElementById('algo-config-form');
            
            if (parentId) {
                // 是子项目，可以继承父项目配置
                algoForm.style.opacity = '0.6';
                showAlert('已选择父项目，将自动继承父项目的配置', 'info');
            } else {
                algoForm.style.opacity = '1';
            }
        }
        
        // 更新 addEvent() 以支持父项目
        // （需要在原函数开始处添加）
'''

if '// ========= 动态加载比赛项目' in content:
    content = content.replace(
        '// ========= 动态加载比赛项目',
        new_functions + '\n        // ========= 动态加载比赛项目'
    )
    print("✅ 添加了算法相关 JavaScript 函数")
else:
    print("⚠️ 未找到插入 JavaScript 函数的位置")

# 保存文件
with open('index-v3.html', 'w', encoding='utf-8') as f:
    f.write(content)

print("\n✅ 文件已更新：index-v3.html")
print("\n⚠️ 注意事项：")
print("1. 需要手动更新 loadEvents() 函数以显示层级关系")
print("2. 需要手动更新 addEvent() 函数以保存 parent_event_id")
print("3. 需要更新 Tabulator 列定义以显示父项目信息")
