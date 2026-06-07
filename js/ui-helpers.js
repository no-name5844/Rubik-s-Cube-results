/**
 * UI 辅助函数
 * showAlert, switchTab, toggleSmartFields, checkDB
 */

function showAlert(message, type) {
    var alertBox = document.getElementById('alertBox');
    alertBox.className = 'alert alert-' + type;
    alertBox.textContent = message;
    alertBox.style.display = 'block';
    setTimeout(function() { alertBox.style.display = 'none'; }, 5000);
}

// 切换标签页
function switchTab(tabName) {
    var tabs = document.querySelectorAll('.tab');
    tabs.forEach(function(t) { t.classList.remove('active'); });
    event.target.classList.add('active');
    var contents = document.querySelectorAll('.tab-content');
    contents.forEach(function(c) { c.classList.remove('active'); });
    document.getElementById('tab-' + tabName).classList.add('active');
}

// 切换智能/非智能魔方字段
function toggleSmartFields() {
    var type = document.getElementById('attempt-cube-type').value;
    document.getElementById('smart-fields').style.display = type === 'smart' ? 'block' : 'none';
    document.getElementById('non-smart-fields').style.display = type === 'non_smart' ? 'block' : 'none';
}

// 检查数据库是否已连接
function checkDB() {
    if (!supabaseClient) {
        showAlert('⚠️ 请先连接数据库', 'error');
        return false;
    }
    return true;
}
