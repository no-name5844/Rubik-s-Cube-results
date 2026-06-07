#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
重构 events tab 布局
"""
import sys
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')

with open(r'C:\Users\cheng\WorkBuddy\2026-06-05-22-07-38\index-v3.html', 'r', encoding='utf-8') as f:
    html = f.read()

# --------------------------------------------------------------------------
# 1. 重组 events tab 的 grid：配置面板从左列移到右列下方 → 改为配置在左列
#    实际上用户要求：配置在左边，列表在右边撑满
#    当前结构：
#      <div class="grid">
#        <div> 添加项目表单 </div>
#        <div> 项目列表 + 配置面板 </div>
#      </div>
#    目标结构：
#      <div class="grid">
#        <div> 添加项目表单 + 配置面板 </div>
#        <div> 项目列表（撑满） </div>
#      </div>
# --------------------------------------------------------------------------

# 找到 events tab 的 grid 区域
grid_start = html.index('<div id="tab-events" class="tab-content">')
grid_end_marker = '<!-- 选手管理 -->'
grid_end = html.index(grid_end_marker, grid_start)

tab_html = html[grid_start:grid_end]

# 找左列（添加表单）的开闭标签
left_start = tab_html.index('<div>\n                        <h3>添加项目</h3>')
# 左列结束位置：第一个 </div>\n                    <div> 之前
left_end = tab_html.index('                    </div>\n                    <div>', left_start)

# 找右列中配置面板开始位置（在 hr 之后）
config_start = tab_html.index('<h3>⚙️ 配置项目参数</h3>', left_end)
# 配置面板结束位置：两个按钮之后 </div>\n                    </div>
# 找 config-form-wrapper 的结束 </div>
config_section_start = config_start
# 从 config_start 找到 </details> 之后的按钮，再找到 </div>
temp = tab_html[config_start:]
# 找最后一个 </div> 属于配置面板区域
# 简单方法：找到 </details> 之后的 saveConfigFromForm 按钮，再找它后面的 </div>
btn_area = tab_html.index('<button class="btn" onclick="saveConfigFromForm()">', config_start)
config_end = tab_html.index('                    </div>\n                    </div>', btn_area) + len('                    </div>\n                    </div>')

# 提取各部分
left_col_raw = tab_html[left_start:left_end]          # 左列原始（添加表单）
config_panel = tab_html[config_start:config_end]       # 配置面板 HTML
right_col_raw = tab_html[left_end:config_start]        # 右列原始（项目列表 + hr，不含配置）

# 构建新左列 = 添加表单 + hr + 配置面板 + 关闭 div
new_left = left_col_raw + '\n' + '                    <hr style="margin: 20px 0; border: none; border-top: 1px solid #e9ecef;">\n                    ' + config_panel.strip() + '\n                    '

# 构建新右列 = 项目列表（去掉 hr 和配置）
# right_col_raw 以 <hr> 开头，以项目列表结束
# 取 right_col_raw 中从开头到 <hr> 之前的部分... 实际上 right_col_raw 是：
#   <div>\n  <h3>项目列表</h3>\n  <div class="table-responsive">...\n  <hr>...\n  (配置面板)
# 我们要的只是：<div>\n  <h3>项目列表</h3>\n  <div class="table-responsive">...</div>\n</div>
# 即去掉 <hr> 及之后的所有内容

hr_pos = right_col_raw.index('<hr style="margin: 24px 0;')
right_col_clean = right_col_raw[:hr_pos].rstrip() + '\n                    </div>'

# 组装新 grid 内容
new_grid_inner = new_left + '\n\n' + right_col_clean + '\n                '

# 替换原 tab_html 中的 grid 内容
# tab_html 从 <div id="tab-events"...> 到 <!-- 选手管理 -->
# 我们需要替换的是 <div class="grid"> ... </div>  （grid 的两个子 div）
old_grid_content = tab_html[left_start:]  # 从第一个 <div>（左列）到 tab_html 结束

# 更精确：重建整个 tab_html
new_tab_html = (
    tab_html[:left_start]
    + new_grid_inner
    + tab_html[grid_end - grid_start:]
)

# 但这样不对... 直接用字符串替换
# 简单粗暴：找到 <div class="grid"> ... </div>  （整个 grid）
# 实际上 tab_html 的结构是：
#   <div id="tab-events" class="tab-content">
#   <h2>...</h2>
#   <div class="grid"> ... </div>   <- 这是我们要替换的
#   </div>  <- tab-content 的关闭

# 重新找：grid 开标签位置
gtag_start = tab_html.index('<div class="grid">')
# grid 闭标签位置
gtag_end = tab_html.index('                </div>\n            </div>\n            \n            <!-- 选手管理 -->', gtag_start)
gtag_end += len('                </div>')

new_grid = '<div class="grid">\n' + new_grid_inner + '                </div>'

tab_html_new = tab_html[:gtag_start] + new_grid + tab_html[gtag_end:]

# 替换原 html 中的 events tab 部分
html_new = html[:grid_start] + tab_html_new + html[grid_end:]

# --------------------------------------------------------------------------
# 2. 加 CSS：#tab-events .grid 右列撑满，左列定宽
# --------------------------------------------------------------------------
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
html_new = html_new.replace(css_target, css_insert + css_target)

# --------------------------------------------------------------------------
# 3. JS：eventsTable 加 maxHeight，去掉 fitColumns
# --------------------------------------------------------------------------
# loadEvents() 中
old1 = (
    "            eventsTable = new Tabulator('#events-table', {\n"
    "                data: data,\n"
    "                layout: 'fitColumns',"
)
new1 = (
    "            eventsTable = new Tabulator('#events-table', {\n"
    "                data: data,\n"
    "                layout: 'fitDataFill',\n"
    "                maxHeight: 160,\n"
    "                rowHeight: 26,\n"
    "                headerHeight: 28,"
)
html_new = html_new.replace(old1, new1)

# loadEventsHierarchical() 中
old2 = (
    "            eventsTable = new Tabulator('#events-table', {\n"
    "                data: result,\n"
    "                layout: 'fitColumns',"
)
new2 = (
    "            eventsTable = new Tabulator('#events-table', {\n"
    "                data: result,\n"
    "                layout: 'fitDataFill',\n"
    "                maxHeight: 160,\n"
    "                rowHeight: 26,\n"
    "                headerHeight: 28,"
)
html_new = html_new.replace(old2, new2)

# --------------------------------------------------------------------------
# 4. 给 events table 列加固定宽度（支持左右滚动）
# --------------------------------------------------------------------------
# loadEvents() columns 中 event_name 加 width
old3 = (
    '                    { title: \'项目名称\', field: \'event_name\', formatter: function(cell) {'
)
new3 = (
    '                    { title: \'项目名称\', field: \'event_name\', width: 180, formatter: function(cell) {'
)
html_new = html_new.replace(old3, new3)

# loadEventsHierarchical() columns 中 event_name 加 width
old4 = '                    { title: \'项目名称\', field: \'event_name\' },'
new4 = '                    { title: \'项目名称\', field: \'event_name\', width: 180 },'
html_new = html_new.replace(old4, new4)

with open(r'C:\Users\cheng\WorkBuddy\2026-06-05-22-07-38\index-v3.html', 'w', encoding='utf-8') as f:
    f.write(html_new)

print("[OK] events tab 布局重组完成")
print("  - 配置面板已移到左列（添加表单下方）")
print("  - 项目列表在右列，grid 460px 1fr")
print("  - 列表 maxHeight:160px（约5行），支持左右滚动")
