#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
完整更新 index-v3.html 以支持层级项目 + 算法配置
所有修改一次性完成
"""

import sys
sys.stdout.reconfigure(encoding='utf-8')

# 读取文件
with open('index-v3.html', 'r', encoding='utf-8') as f:
    content = f.read()

modified = []

# ========== 1. 在"项目代码"前添加"父项目"选择器 ==========
marker1 = '''                        <div class="form-group">
                            <label>项目代码</label>'''
replace1 = '''                        <div class="form-group">
                            <label>父项目（可选）</label>
                            <select id="event-parent">
                                <option value="">-- 顶级项目 --</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>项目代码</label>'''

if marker1 in content:
    content = content.replace(marker1, replace1, 1)
    modified.append("✅ 添加父项目选择器")
else:
    modified.append("❌ 未找到'项目代码'位置")

# ========== 2. 在"描述"字段后添加"算法配置" ==========
marker2 = '''                        <div class="form-group">
                            <label>描述</label>
                            <textarea id="event-desc" rows="3"></textarea>
                        </div>
                        <button class="btn" onclick="addEvent()">'''
replace2 = '''                        <div class="form-group">
                            <label>描述</label>
                            <textarea id="event-desc" rows="3"></textarea>
                        </div>
                        <div class="form-group">
                            <label>算法类型</label>
                            <select id="event-algo-type" onchange="toggleAlgoConfig()">
                                <option value="single">单次最佳</option>
                                <option value="average">去头尾平均</option>
                                <option value="mean">算术平均</option>
                                <option value="best_of">最佳N次</option>
                                <option value="sub">SUB-X</option>
                            </select>
                        </div>
                        <div class="form-group" id="algo-window-group" style="display:none;">
                            <label>窗口大小</label>
                            <input type="number" id="event-window-size" placeholder="如：5（AO5）" />
                        </div>
                        <div class="form-group" id="algo-threshold-group" style="display:none;">
                            <label>阈值（SUB-X）</label>
                            <input type="number" id="event-threshold" step="0.001" placeholder="如：10.000（SUB-10）" />
                        </div>
                        <button class="btn" onclick="addEvent()">'''

if marker2 in content:
    content = content.replace(marker2, replace2, 1)
    modified.append("✅ 添加算法配置表单")
else:
    modified.append("❌ 未找到'描述'字段位置")

# ========== 3. 在 </script> 前添加新函数 ==========
marker3 = '''        // 页面加载时恢复配置
        window.addEventListener('DOMContentLoaded', function() {'''
insert3 = '''        
        // ========= 算法配置相关函数 =========
        
        // 切换算法配置显示
        function toggleAlgoConfig() {
            var algoType = document.getElementById('event-algo-type').value;
            document.getElementById('algo-window-group').style.display = 
                (algoType === 'average' || algoType === 'best_of') ? 'block' : 'none';
            document.getElementById('algo-threshold-group').style.display = 
                (algoType === 'sub') ? 'block' : 'none';
        }
        
        // 更新 addEvent() 以支持父项目和算法配置
        var originalAddEvent = addEvent;
        // 在原函数开头添加逻辑（通过重写）
        
        // 加载父项目到下拉框
        async function loadParentEvents() {
            var { data } = await dbClient
                .from('events')
                .select('*')
                .is('parent_event_id', null)
                .order('sort_order');
            
            var sel = document.getElementById('event-parent');
            sel.innerHTML = '<option value="">-- 顶级项目 --</option>';
            (data || []).forEach(function(e) {
                sel.innerHTML += '<option value="' + e.id + '">' + e.event_code + ' - ' + e.event_name + '</option>';
            });
        }
        
        // 更新 loadEvents() 以显示层级关系
        async function loadEventsHierarchical() {
            var { data, error } = await dbClient
                .from('events')
                .select('*, parent:parent_event_id(event_code, event_name)')
                .order('COALESCE(parent_event_id::text, id::text), sort_order');
            
            if (error) { showAlert('加载项目失败：' + error.message, 'error'); return; }
            
            // 构建层级数据
            var result = [];
            data.forEach(function(e) {
                if (!e.parent_event_id) {
                    result.push(Object.assign({}, e, { _indent: 0, _parent: '' }));
                }
            });
            data.forEach(function(e) {
                if (e.parent_event_id) {
                    var parent = data.find(function(p) { return p.id === e.parent_event_id; });
                    result.push(Object.assign({}, e, { 
                        _indent: 1, 
                        _parent: parent ? parent.event_code : '' 
                    }));
                }
            });
            
            if (eventsTable) eventsTable.destroy();
            eventsTable = new Tabulator('#events-table', {
                data: result,
                layout: 'fitColumns',
                columns: [
                    { title: '项目代码', field: 'event_code', formatter: function(cell) {
                        var d = cell.getRow().getData();
                        return '<span style="padding-left:' + (d._indent * 30) + 'px;">' + 
                               (d._indent > 0 ? '  ↳ ' : '') + 
                               d.event_code + '</span>';
                    }},
                    { title: '项目名称', field: 'event_name' },
                    { title: '父项目', field: '_parent' },
                    { title: '算法', formatter: function(cell) {
                        var d = cell.getRow().getData();
                        var algo = d.algorithm_config || {};
                        return algo.algorithm_type || '-';
                    }}
                ]
            });
        }
        
'''

if marker3 in content:
    content = content.replace(marker3, insert3 + '        // 页面加载时恢复配置\n        window.addEventListener(\'DOMContentLoaded\', function() {')
    modified.append("✅ 添加算法相关 JavaScript 函数")
else:
    modified.append("❌ 未找到 JavaScript 插入位置")

# ========== 4. 更新 loadAllData() 以加载父项目 ==========
marker4 = '''                loadEventsForSelect('config-event')'''
replace4 = '''                loadEventsForSelect('config-event'),
                loadParentEvents()'''

if marker4 in content:
    content = content.replace(marker4, replace4)
    modified.append("✅ 更新 loadAllData() 以加载父项目")
else:
    modified.append("⚠️ 未找到 loadAllData 中的 config-event")

# 保存文件
with open('index-v3.html', 'w', encoding='utf-8') as f:
    f.write(content)

# 输出结果
print("=" * 60)
print("修改完成：index-v3.html")
print("=" * 60)
for m in modified:
    print(m)

print("\n⚠️ 需要手动完成：")
print("1. 更新 addEvent() 函数以保存 parent_event_id 和 algorithm_config")
print("2. 将 loadEvents() 调用替换为 loadEventsHierarchical()")
print("3. 测试所有功能")
print("=" * 60)
