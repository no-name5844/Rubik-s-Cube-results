/**
 * 统计计算 + Gamma MLE
 * 包含 loadStats, loadStatsFallback, fitGammaMLE, 绘图函数
 */

// 加载统计分析
async function loadStats() {
    var participantId = document.getElementById('mle-participant').value;
    var eventId = document.getElementById('mle-event').value;
    if (!participantId || !eventId) {
        document.getElementById('stats-display').innerHTML = '';
        document.getElementById('mle-prediction').innerHTML = '请选择选手和项目';
        return;
    }
    
    // 1. 调用数据库的 calculate_statistic() 函数
    var { data: statsData, error: statsError } = await dbClient
        .rpc('calculate_statistic', {
            participant_id: participantId,
            event_id: eventId,
            statistic_type: 'all'
        });
    
    if (statsError) {
        console.error('调用 calculate_statistic() 失败:', statsError);
        showAlert('数据库函数调用失败，使用浏览器端计算', 'info');
        return loadStatsFallback(participantId, eventId);
    }
    
    // 2. 显示统计卡片
    if (statsData && statsData.length > 0) {
        var stats = statsData[0];
        var cardsHtml = 
            '<div class="stat-card"><h3>单次最佳</h3><div class="value">' + (stats.single_best ? stats.single_best.toFixed(3) : '-') + '</div></div>' +
            '<div class="stat-card"><h3>平均最佳</h3><div class="value">' + (stats.average_best ? stats.average_best.toFixed(3) : '-') + '</div></div>' +
            '<div class="stat-card"><h3>AO5 最佳</h3><div class="value">' + (stats.ao5_best ? stats.ao5_best.toFixed(3) : '-') + '</div></div>' +
            '<div class="stat-card"><h3>AO12 最佳</h3><div class="value">' + (stats.ao12_best ? stats.ao12_best.toFixed(3) : '-') + '</div></div>' +
            '<div class="stat-card"><h3>总次数</h3><div class="value">' + (stats.total_attempts || 0) + '</div></div>';
        document.getElementById('stats-display').innerHTML = cardsHtml;
    }
    
    // 3. 获取成绩数据用于 Gamma 分布拟合
    var { data: attempts, error: attemptsError } = await dbClient
        .from('attempts')
        .select('*, competition_events!inner(*)')
        .eq('participant_id', participantId)
        .eq('competition_events.event_id', eventId)
        .eq('is_dnf', false)
        .not('solve_time', 'is', null)
        .order('created_at');
    
    if (attemptsError || !attempts || attempts.length === 0) {
        document.getElementById('mle-prediction').innerHTML = '暂无有效成绩';
        return;
    }
    
    var times = attempts.map(a => a.solve_time);
    
    // 4. Gamma 分布 MLE 拟合
    var mle = fitGammaMLE(times);
    if (!mle) {
        document.getElementById('mle-prediction').innerHTML = '成绩数据不足，无法拟合';
        return;
    }
    
    var alpha = mle.alpha;
    var beta = mle.beta;
    var mode = (alpha > 1) ? (alpha - 1) / beta : 0;
    var mean = alpha / beta;
    var variance = alpha / (beta * beta);
    
    // 5. 显示 MLE 预测
    var predictionHtml = 
        '<h4>📊 Gamma 分布参数（MLE 估计）</h4>' +
        '<p><strong>α（形状）</strong>：' + alpha.toFixed(3) + '</p>' +
        '<p><strong>β（尺度）</strong>：' + beta.toFixed(3) + '</p>' +
        '<p><strong>众数（真实水平）</strong>：' + mode.toFixed(3) + ' 秒</p>' +
        '<p><strong>均值</strong>：' + mean.toFixed(3) + ' 秒</p>' +
        '<p><strong>标准差</strong>：' + Math.sqrt(variance).toFixed(3) + ' 秒</p>' +
        '<h4>🎯 预测</h4>' +
        '<p>下次成绩 < 10 秒的概率：～ ' + (gammaCdf(10, alpha, beta) * 100).toFixed(1) + '%</p>' +
        '<p>下次成绩在 ' + mode.toFixed(1) + ' ± 2 秒内的概率：～ ' + ((gammaCdf(mode+2, alpha, beta) - gammaCdf(Math.max(0, mode-2), alpha, beta)) * 100).toFixed(1) + '%</p>';
    document.getElementById('mle-prediction').innerHTML = predictionHtml;
    
    // 6. 绘制 Gamma 分布图
    drawGammaChart(times, alpha, beta);
    
    // 7. 保存 MLE 预测结果到数据库
    await dbClient.from('mle_predictions').upsert({
        participant_id: participantId,
        event_id: eventId,
        alpha: alpha,
        beta: beta,
        mode_value: mode,
        mean_value: mean,
        variance_value: variance,
        sample_size: times.length,
        confidence_interval: JSON.stringify({ lower: mode - 2*Math.sqrt(variance), upper: mode + 2*Math.sqrt(variance) })
    }, { onConflict: 'participant_id,event_id' });
}

// 降级函数：浏览器端计算
async function loadStatsFallback(participantId, eventId) {
    var { data: attempts, error: attemptsError } = await dbClient
        .from('attempts')
        .select('*, competition_events!inner(*)')
        .eq('participant_id', participantId)
        .eq('competition_events.event_id', eventId)
        .eq('is_dnf', false)
        .not('solve_time', 'is', null)
        .order('created_at');
    
    if (attemptsError || !attempts || attempts.length === 0) {
        document.getElementById('stats-display').innerHTML = '';
        document.getElementById('mle-prediction').innerHTML = '暂无有效成绩';
        return;
    }
    
    var times = attempts.map(a => a.solve_time);
    
    // 计算单次最佳
    var singleBest = Math.min(...times);
    
    // 计算 AO5 最佳（滑动窗口）
    var ao5Best = null;
    for (var i = 4; i < times.length; i++) {
        var window = times.slice(i-4, i+1);
        var trimmed = window.sort((a,b) => a-b).slice(1, 4);
        var avg = trimmed.reduce((a,b) => a+b, 0) / 3;
        if (ao5Best === null || avg < ao5Best) ao5Best = avg;
    }
    
    // 计算 AO12 最佳
    var ao12Best = null;
    for (var i = 11; i < times.length; i++) {
        var window = times.slice(i-11, i+1);
        var trimmed = window.sort((a,b) => a-b).slice(1, 11);
        var avg = trimmed.reduce((a,b) => a+b, 0) / 10;
        if (ao12Best === null || avg < ao12Best) ao12Best = avg;
    }
    
    var cardsHtml = 
        '<div class="stat-card"><h3>单次最佳</h3><div class="value">' + singleBest.toFixed(3) + '</div></div>' +
        '<div class="stat-card"><h3>AO5 最佳</h3><div class="value">' + (ao5Best ? ao5Best.toFixed(3) : '-') + '</div></div>' +
        '<div class="stat-card"><h3>AO12 最佳</h3><div class="value">' + (ao12Best ? ao12Best.toFixed(3) : '-') + '</div></div>' +
        '<div class="stat-card"><h3>总次数</h3><div class="value">' + times.length + '</div></div>';
    document.getElementById('stats-display').innerHTML = cardsHtml;
    
    // Gamma MLE
    var mle = fitGammaMLE(times);
    if (!mle) {
        document.getElementById('mle-prediction').innerHTML = '成绩数据不足，无法拟合';
        return;
    }
    
    var alpha = mle.alpha;
    var beta = mle.beta;
    var mode = (alpha > 1) ? (alpha - 1) / beta : 0;
    var mean = alpha / beta;
    var variance = alpha / (beta * beta);
    
    var predictionHtml = 
        '<h4>📊 Gamma 分布参数（MLE 估计）</h4>' +
        '<p><strong>α（形状）</strong>：' + alpha.toFixed(3) + '</p>' +
        '<p><strong>β（尺度）</strong>：' + beta.toFixed(3) + '</p>' +
        '<p><strong>众数（真实水平）</strong>：' + mode.toFixed(3) + ' 秒</p>' +
        '<p><strong>均值</strong>：' + mean.toFixed(3) + ' 秒</p>' +
        '<p><strong>标准差</strong>：' + Math.sqrt(variance).toFixed(3) + ' 秒</p>';
    document.getElementById('mle-prediction').innerHTML = predictionHtml;
    
    drawGammaChart(times, alpha, beta);
}

// Gamma 分布 MLE 拟合
function fitGammaMLE(times) {
    if (!times || times.length < 3) return null;
    
    var n = times.length;
    var mean = times.reduce((a,b) => a+b, 0) / n;
    var logMean = Math.log(mean);
    var meanLog = meanOfLog(times);
    
    // 初始估计
    var s = logMean - meanLog;
    var alpha0 = (3 - s + Math.sqrt((s-3)*(s-3) + 24*s)) / (12*s);
    
    // 牛顿法迭代
    var alpha = alpha0;
    for (var iter = 0; iter < 100; iter++) {
        var d1 = n * (Math.log(alpha) - meanLog - digamma(alpha)) + n * Math.log(mean);
        var d2 = n / alpha - n * trigamma(alpha);
        var alphaNew = alpha - d1 / d2;
        if (alphaNew <= 0) break;
        if (Math.abs(alphaNew - alpha) < 1e-6) { alpha = alphaNew; break; }
        alpha = alphaNew;
    }
    
    var beta = alpha / mean;
    return { alpha: alpha, beta: beta };
}

// Digamma 函数
function digamma(x) {
    if (x < 1e-6) return -1e10;
    var result = 0;
    while (x < 6) { result -= 1/x; x++; }
    var xx = 1/x;
    var xx2 = xx*xx;
    result += Math.log(x) - 0.5*xx - xx2*(1/12 - xx2*(1/120 - xx2*(1/252 - xx2*(1/240 - xx2*(1/132 + xx2/32760))));
    return result;
}

// Trigamma 函数
function trigamma(x) {
    if (x < 1e-6) return 1e10;
    var result = 0;
    while (x < 6) { result += 1/(x*x); x++; }
    return result + 0.5/(x*x) + (1 + 1.5/x)/x/x/x;
}

// 计算 log 的均值
function meanOfLog(times) {
    return times.reduce((sum, t) => sum + Math.log(t), 0) / times.length;
}

// Gamma 累积分布函数
function gammaCdf(x, alpha, beta) {
    return lowerIncompleteGamma(alpha, x * beta);
}

// 不完全 Gamma 函数（下侧）
function lowerIncompleteGamma(s, x) {
    if (x <= 0) return 0;
    var maxIter = 200;
    var eps = 1e-10;
    var ap = s;
    var s0 = 1/s;
    var ak = 1/s;
    var delta = ak;
    for (var n = 1; n <= maxIter; n++) {
        ap += 1;
        delta *= x * n / (ap * s);
        if (Math.abs(delta) < Math.abs(ak) * eps) break;
        ak += delta;
    }
    return ak * Math.exp(-x + s * Math.log(x) - logGamma(s));
}

// Log-Gamma 函数
function logGamma(x) {
    var coef = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5];
    var y = x;
    var tmp = x + 5.5;
    tmp -= (x + 0.5) * Math.log(tmp);
    var ser = 1.000000000190015;
    for (var j = 0; j <= 5; j++) { ser += coef[j] / ++y; }
    return -tmp + Math.log(2.5066282746310005 * ser / x);
}

// 绘制 Gamma 分布图
function drawGammaChart(times, alpha, beta) {
    var canvas = document.getElementById('gamma-chart');
    if (!canvas) return;
    
    if (window.gammaChartInstance) window.gammaChartInstance.destroy();
    
    var ctx = canvas.getContext('2d');
    
    // 准备直方图数据
    var min = Math.min(...times);
    var max = Math.max(...times);
    var binCount = Math.min(20, Math.ceil(Math.sqrt(times.length)));
    var binWidth = (max - min) / binCount;
    var bins = [];
    for (var i = 0; i < binCount; i++) {
        bins.push({ start: min + i*binWidth, count: 0 });
    }
    times.forEach(t => {
        var idx = Math.min(Math.floor((t - min) / binWidth), binCount-1);
        bins[idx].count++;
    });
    
    // Gamma PDF
    var pdfX = [];
    var pdfY = [];
    for (var x = min; x <= max + 2; x += 0.1) {
        pdfX.push(x);
        pdfY.push(Math.pow(beta, alpha) * Math.pow(x, alpha-1) * Math.exp(-beta*x) / Math.exp(logGamma(alpha)));
    }
    
    window.gammaChartInstance = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: bins.map(b => b.start.toFixed(1)),
            datasets: [{
                label: '成绩分布',
                data: bins.map(b => b.count),
                backgroundColor: 'rgba(102, 126, 234, 0.6)',
                borderColor: 'rgba(102, 126, 234, 1)',
                borderWidth: 1,
                yAxisID: 'y'
            }, {
                label: 'Gamma PDF',
                data: pdfY,
                type: 'line',
                borderColor: 'rgba(255, 99, 132, 1)',
                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                fill: false,
                yAxisID: 'y1'
            }]
        },
        options: {
            scales: {
                y: { type: 'linear', position: 'left', title: { display: true, text: '频数' } },
                y1: { type: 'linear', position: 'right', title: { display: true, text: '密度' }, grid: { drawOnChartArea: false } }
            }
        }
    });
}
