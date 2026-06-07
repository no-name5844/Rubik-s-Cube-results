#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复 events tab 剩余问题：JS 拼写 + CSS + maxHeight 确认"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

with open(r'C:\Users\cheng\WorkBuddy\2026-06-05-22-07-38\index-v3.html', 'r', encoding='utf-8') as f:
    html = f.read()

count = 0

# 1. 修 JS 拼写错误：afterrend → afterend（两处）
old = "btn.insertAdjacentElement('afterrend', hr);"
new = "btn.insertAdjacentElement('afterend', hr);"
if old in html:
    html = html.replace(old, new)
    count += 1
    print('[OK] 修复 btn.insertAdjacentElement afterrend -> afterend')

old2 = "hr.insertAdjacentElement('afterend', panel);"
new2 = "hr.insertAdjacentElement('afterend', panel);"
# 这行其实是对的，但第一处错了
# 重新检查
if "btn.insertAdjacentElement('afterrend'" in html:
    html = html.replace("btn.insertAdjacentElement('afterrend'", "btn.insertAdjacentElement('afterend'")
    count += 1
    print('[OK] 修复 btn.insertAdjacentElement afterrend -> afterend (二次)')

# 2. 加 CSS：#tab-events .grid 右列撑满
css_target = '        /* Tabulator 紧凑样式（桌面端） */'
css_insert = (
    '        /* 项目管理：左列定宽，右列撑满 */\n'
    '        #tab-events .grid {\n'
    '            grid-template-columns: 460px 1fr;\n'
    '        }\n'
    '        #tab-events .table-responsive {\n'
    '            max-height: 160px;\n'
    '            overflow-y: auto;\n'
    '        }\n'
    '        \n'
)
if css_target in html and '/* 项目管理' not in html:
    html = html.replace(css_target, css_insert + css_target)
    count += 1
    print('[OK] 添加 #tab-events .grid CSS（460px 1fr）')

# 3. 确认 eventsTable 有 maxHeight（两处 init）
for marker in [
    "            eventsTable = new Tabulator('#events-table', {\n                data: data,\n                layout: 'fitDataFill',",
    "            eventsTable = new Tabulator('#events-table', {\n                data: result,\n                layout: 'fitDataFill',",
]:
    if marker in html and 'maxHeight: 160' not in html[html.index(marker):html.index(marker)+500]:
        # 在 layout 行后插入 maxHeight
        insert_pos = html.index(marker) + len(marker)
        html = html[:insert_pos] + '\n                maxHeight: 160,' + html[insert_pos:]
        count += 1
        print(f'[OK] 添加 maxHeight:160 到 eventsTable')

# 4. 确认列有固定宽度（支持左右滚动）
# loadEvents() 的 event_name 列
old_col = "                        title: '项目名称',\n                        field: 'event_name',\n                        formatter: function(cell) {"
new_col = "                        title: '项目名称',\n                        field: 'event_name',\n                        width: 180,\n                        formatter: function(cell) {"
if old_col in html:
    html = html.replace(old_col, new_col)
    count += 1
    print('[OK] event_name 列加 width:180（loadEvents）')

# loadEventsHierarchical() 的 event_name 列
old_col2 = "                    { title: '项目名称', field: 'event_name' },"
new_col2 = "                    { title: '项目名称', field: 'event_name', width: 180 },"
if old_col2 in html:
    html = html.replace(old_col2, new_col2)
    count += 1
    print('[OK] event_name 列加 width:180（loadEventsHierarchical）')

if count == 0:
    print('[INFO] 没有需要修改的内容，或已全部修复')

with open(r'C:\Users\cheng\WorkBuddy\2026-06-05-22-07-38\index-v3.html', 'w', encoding='utf-8') as f:
    f.write(html)

print(f'\n完成：共修改 {count} 处')
