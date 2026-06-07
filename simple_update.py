#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简化版：为 index-v3.html 添加层级项目支持
只做最必要的修改
"""

import sys
sys.stdout.reconfigure(encoding='utf-8')

# 读取原文件
with open('index-v3.html', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 找到需要修改的位置
output = []
i = 0
while i < len(lines):
    line = lines[i]
    
    # 1. 在"项目代码"前添加"父项目"选择器
    if '                            <label>项目代码</label>' in line and i > 0:
        # 检查上一行是否是 </div>
        if '</div>' in lines[i-1]:
            # 添加父项目选择器
            output.append('                        <div class="form-group">\n')
            output.append('                            <label>父项目（可选）</label>\n')
            output.append('                            <select id="event-parent">\n')
            output.append('                                <option value="">-- 顶级项目 --</option>\n')
            output.append('                            </select>\n')
            output.append('                        </div>\n')
    
    output.append(line)
    i += 1

# 保存
with open('index-v3.html', 'w', encoding='utf-8') as f:
    f.writelines(output)

print("OK: Added parent event selector")
print("TODO: Need to also update:")
print("  1. addEvent() to save parent_event_id")
print("  2. loadEvents() to display hierarchical structure")
print("  3. Add algorithm config field")
