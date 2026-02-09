package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

// DashboardData holds aggregated statistics for the dashboard
type DashboardData struct {
	TotalInstalls   int               `json:"total_installs"`
	SuccessCount    int               `json:"success_count"`
	FailedCount     int               `json:"failed_count"`
	InstallingCount int               `json:"installing_count"`
	SuccessRate     float64           `json:"success_rate"`
	TopApps         []AppCount        `json:"top_apps"`
	OsDistribution  []OsCount         `json:"os_distribution"`
	MethodStats     []MethodCount     `json:"method_stats"`
	RecentRecords   []TelemetryRecord `json:"recent_records"`
	DailyStats      []DailyStat       `json:"daily_stats"`
}

type AppCount struct {
	App   string `json:"app"`
	Count int    `json:"count"`
}

type OsCount struct {
	Os    string `json:"os"`
	Count int    `json:"count"`
}

type MethodCount struct {
	Method string `json:"method"`
	Count  int    `json:"count"`
}

type DailyStat struct {
	Date    string `json:"date"`
	Success int    `json:"success"`
	Failed  int    `json:"failed"`
}

// FetchDashboardData retrieves aggregated data from PocketBase
func (p *PBClient) FetchDashboardData(ctx context.Context, days int) (*DashboardData, error) {
	if err := p.ensureAuth(ctx); err != nil {
		return nil, err
	}

	data := &DashboardData{}

	// Calculate date filter
	since := time.Now().AddDate(0, 0, -days).Format("2006-01-02 00:00:00")
	filter := url.QueryEscape(fmt.Sprintf("created >= '%s'", since))

	// Fetch all records for the period
	records, err := p.fetchRecords(ctx, filter, 500)
	if err != nil {
		return nil, err
	}

	// Aggregate statistics
	appCounts := make(map[string]int)
	osCounts := make(map[string]int)
	methodCounts := make(map[string]int)
	dailySuccess := make(map[string]int)
	dailyFailed := make(map[string]int)

	for _, r := range records {
		data.TotalInstalls++

		switch r.Status {
		case "sucess":
			data.SuccessCount++
		case "failed":
			data.FailedCount++
		case "installing":
			data.InstallingCount++
		}

		// Count apps
		if r.NSAPP != "" {
			appCounts[r.NSAPP]++
		}

		// Count OS
		if r.OsType != "" {
			osCounts[r.OsType]++
		}

		// Count methods
		if r.Method != "" {
			methodCounts[r.Method]++
		}

		// Daily stats (use Created field if available)
		if r.Created != "" {
			date := r.Created[:10] // "2026-02-09"
			if r.Status == "sucess" {
				dailySuccess[date]++
			} else if r.Status == "failed" {
				dailyFailed[date]++
			}
		}
	}

	// Calculate success rate
	completed := data.SuccessCount + data.FailedCount
	if completed > 0 {
		data.SuccessRate = float64(data.SuccessCount) / float64(completed) * 100
	}

	// Convert maps to sorted slices (top 10)
	data.TopApps = topN(appCounts, 10)
	data.OsDistribution = topNOs(osCounts, 10)
	data.MethodStats = topNMethod(methodCounts, 10)

	// Daily stats for chart
	data.DailyStats = buildDailyStats(dailySuccess, dailyFailed, days)

	// Recent records (last 20)
	if len(records) > 20 {
		data.RecentRecords = records[:20]
	} else {
		data.RecentRecords = records
	}

	return data, nil
}

// TelemetryRecord includes Created timestamp
type TelemetryRecord struct {
	TelemetryOut
	Created string `json:"created"`
}

func (p *PBClient) fetchRecords(ctx context.Context, filter string, limit int) ([]TelemetryRecord, error) {
	var allRecords []TelemetryRecord
	page := 1
	perPage := 100

	for {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet,
			fmt.Sprintf("%s/api/collections/%s/records?filter=%s&sort=-created&page=%d&perPage=%d",
				p.baseURL, p.targetColl, filter, page, perPage),
			nil,
		)
		if err != nil {
			return nil, err
		}
		req.Header.Set("Authorization", "Bearer "+p.token)

		resp, err := p.http.Do(req)
		if err != nil {
			return nil, err
		}

		var result struct {
			Items      []TelemetryRecord `json:"items"`
			TotalItems int               `json:"totalItems"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
			resp.Body.Close()
			return nil, err
		}
		resp.Body.Close()

		allRecords = append(allRecords, result.Items...)

		if len(allRecords) >= limit || len(allRecords) >= result.TotalItems {
			break
		}
		page++
	}

	return allRecords, nil
}

func topN(m map[string]int, n int) []AppCount {
	result := make([]AppCount, 0, len(m))
	for k, v := range m {
		result = append(result, AppCount{App: k, Count: v})
	}
	// Simple bubble sort for small datasets
	for i := 0; i < len(result)-1; i++ {
		for j := i + 1; j < len(result); j++ {
			if result[j].Count > result[i].Count {
				result[i], result[j] = result[j], result[i]
			}
		}
	}
	if len(result) > n {
		return result[:n]
	}
	return result
}

func topNOs(m map[string]int, n int) []OsCount {
	result := make([]OsCount, 0, len(m))
	for k, v := range m {
		result = append(result, OsCount{Os: k, Count: v})
	}
	for i := 0; i < len(result)-1; i++ {
		for j := i + 1; j < len(result); j++ {
			if result[j].Count > result[i].Count {
				result[i], result[j] = result[j], result[i]
			}
		}
	}
	if len(result) > n {
		return result[:n]
	}
	return result
}

func topNMethod(m map[string]int, n int) []MethodCount {
	result := make([]MethodCount, 0, len(m))
	for k, v := range m {
		result = append(result, MethodCount{Method: k, Count: v})
	}
	for i := 0; i < len(result)-1; i++ {
		for j := i + 1; j < len(result); j++ {
			if result[j].Count > result[i].Count {
				result[i], result[j] = result[j], result[i]
			}
		}
	}
	if len(result) > n {
		return result[:n]
	}
	return result
}

func buildDailyStats(success, failed map[string]int, days int) []DailyStat {
	result := make([]DailyStat, 0, days)
	for i := days - 1; i >= 0; i-- {
		date := time.Now().AddDate(0, 0, -i).Format("2006-01-02")
		result = append(result, DailyStat{
			Date:    date,
			Success: success[date],
			Failed:  failed[date],
		})
	}
	return result
}

// DashboardHTML returns the embedded dashboard HTML
func DashboardHTML() string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Telemetry Dashboard - Community Scripts</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --border-color: #30363d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --accent-blue: #58a6ff;
            --accent-green: #3fb950;
            --accent-red: #f85149;
            --accent-yellow: #d29922;
            --accent-purple: #a371f7;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
            padding: 20px;
        }
        
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
            padding-bottom: 16px;
            border-bottom: 1px solid var(--border-color);
        }
        
        .header h1 {
            font-size: 24px;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .header h1 img {
            height: 40px;
        }
        
        .controls {
            display: flex;
            gap: 12px;
            align-items: center;
        }
        
        select, button {
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            color: var(--text-primary);
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 14px;
            cursor: pointer;
        }
        
        select:hover, button:hover {
            border-color: var(--accent-blue);
        }
        
        button {
            background: var(--accent-blue);
            border-color: var(--accent-blue);
            color: #fff;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }
        
        .stat-card {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 20px;
        }
        
        .stat-card .label {
            font-size: 12px;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }
        
        .stat-card .value {
            font-size: 32px;
            font-weight: 600;
        }
        
        .stat-card .value.success { color: var(--accent-green); }
        .stat-card .value.failed { color: var(--accent-red); }
        .stat-card .value.pending { color: var(--accent-yellow); }
        .stat-card .value.rate { color: var(--accent-blue); }
        
        .charts-grid {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 16px;
            margin-bottom: 24px;
        }
        
        @media (max-width: 1200px) {
            .charts-grid {
                grid-template-columns: 1fr;
            }
        }
        
        .chart-card {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 20px;
        }
        
        .chart-card h3 {
            font-size: 14px;
            font-weight: 600;
            margin-bottom: 16px;
            color: var(--text-secondary);
        }
        
        .chart-container {
            position: relative;
            height: 300px;
        }
        
        .small-charts {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }
        
        .table-card {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
        }
        
        .table-card h3 {
            font-size: 14px;
            font-weight: 600;
            padding: 16px 20px;
            border-bottom: 1px solid var(--border-color);
            color: var(--text-secondary);
        }
        
        .filters {
            padding: 12px 20px;
            background: var(--bg-tertiary);
            border-bottom: 1px solid var(--border-color);
            display: flex;
            gap: 12px;
            flex-wrap: wrap;
        }
        
        .filters input, .filters select {
            background: var(--bg-secondary);
            flex: 1;
            min-width: 150px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        th, td {
            padding: 12px 20px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }
        
        th {
            font-size: 12px;
            font-weight: 600;
            color: var(--text-secondary);
            text-transform: uppercase;
            background: var(--bg-tertiary);
        }
        
        td {
            font-size: 14px;
        }
        
        tr:hover {
            background: var(--bg-tertiary);
        }
        
        .status-badge {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: 500;
        }
        
        .status-badge.sucess { background: rgba(63, 185, 80, 0.2); color: var(--accent-green); }
        .status-badge.failed { background: rgba(248, 81, 73, 0.2); color: var(--accent-red); }
        .status-badge.installing { background: rgba(210, 153, 34, 0.2); color: var(--accent-yellow); }
        
        .loading {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 200px;
            color: var(--text-secondary);
        }
        
        .error {
            background: rgba(248, 81, 73, 0.1);
            border: 1px solid var(--accent-red);
            color: var(--accent-red);
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 24px;
        }
        
        .last-updated {
            font-size: 12px;
            color: var(--text-secondary);
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M3 3v18h18"/>
                <path d="M18.7 8l-5.1 5.2-2.8-2.7L7 14.3"/>
            </svg>
            Telemetry Dashboard
        </h1>
        <div class="controls">
            <select id="timeRange">
                <option value="7">Last 7 days</option>
                <option value="14">Last 14 days</option>
                <option value="30" selected>Last 30 days</option>
                <option value="90">Last 90 days</option>
            </select>
            <button onclick="refreshData()">Refresh</button>
            <span class="last-updated" id="lastUpdated"></span>
        </div>
    </div>
    
    <div id="error" class="error" style="display: none;"></div>
    
    <div class="stats-grid">
        <div class="stat-card">
            <div class="label">Total Installations</div>
            <div class="value" id="totalInstalls">-</div>
        </div>
        <div class="stat-card">
            <div class="label">Successful</div>
            <div class="value success" id="successCount">-</div>
        </div>
        <div class="stat-card">
            <div class="label">Failed</div>
            <div class="value failed" id="failedCount">-</div>
        </div>
        <div class="stat-card">
            <div class="label">In Progress</div>
            <div class="value pending" id="installingCount">-</div>
        </div>
        <div class="stat-card">
            <div class="label">Success Rate</div>
            <div class="value rate" id="successRate">-</div>
        </div>
    </div>
    
    <div class="charts-grid">
        <div class="chart-card">
            <h3>Installations Over Time</h3>
            <div class="chart-container">
                <canvas id="dailyChart"></canvas>
            </div>
        </div>
        <div class="chart-card">
            <h3>Status Distribution</h3>
            <div class="chart-container">
                <canvas id="statusChart"></canvas>
            </div>
        </div>
    </div>
    
    <div class="small-charts">
        <div class="chart-card">
            <h3>Top Applications</h3>
            <div class="chart-container">
                <canvas id="appsChart"></canvas>
            </div>
        </div>
        <div class="chart-card">
            <h3>OS Distribution</h3>
            <div class="chart-container">
                <canvas id="osChart"></canvas>
            </div>
        </div>
        <div class="chart-card">
            <h3>Installation Method</h3>
            <div class="chart-container">
                <canvas id="methodChart"></canvas>
            </div>
        </div>
    </div>
    
    <div class="table-card">
        <h3>Recent Installations</h3>
        <div class="filters">
            <input type="text" id="filterApp" placeholder="Filter by app..." oninput="filterTable()">
            <select id="filterStatus" onchange="filterTable()">
                <option value="">All Status</option>
                <option value="sucess">Success</option>
                <option value="failed">Failed</option>
                <option value="installing">Installing</option>
            </select>
            <select id="filterOs" onchange="filterTable()">
                <option value="">All OS</option>
            </select>
        </div>
        <table>
            <thead>
                <tr>
                    <th>App</th>
                    <th>Status</th>
                    <th>OS</th>
                    <th>Type</th>
                    <th>Method</th>
                    <th>Exit Code</th>
                    <th>Error</th>
                </tr>
            </thead>
            <tbody id="recordsTable">
                <tr><td colspan="7" class="loading">Loading...</td></tr>
            </tbody>
        </table>
    </div>
    
    <script>
        let charts = {};
        let allRecords = [];
        
        const chartColors = {
            blue: 'rgba(88, 166, 255, 0.8)',
            green: 'rgba(63, 185, 80, 0.8)',
            red: 'rgba(248, 81, 73, 0.8)',
            yellow: 'rgba(210, 153, 34, 0.8)',
            purple: 'rgba(163, 113, 247, 0.8)',
            gray: 'rgba(139, 148, 158, 0.8)'
        };
        
        const chartDefaults = {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    labels: { color: '#c9d1d9' }
                }
            },
            scales: {
                x: {
                    ticks: { color: '#8b949e' },
                    grid: { color: '#30363d' }
                },
                y: {
                    ticks: { color: '#8b949e' },
                    grid: { color: '#30363d' }
                }
            }
        };
        
        async function fetchData() {
            const days = document.getElementById('timeRange').value;
            try {
                const response = await fetch('/api/dashboard?days=' + days);
                if (!response.ok) throw new Error('Failed to fetch data');
                return await response.json();
            } catch (error) {
                document.getElementById('error').style.display = 'block';
                document.getElementById('error').textContent = 'Error: ' + error.message;
                throw error;
            }
        }
        
        function updateStats(data) {
            document.getElementById('totalInstalls').textContent = data.total_installs.toLocaleString();
            document.getElementById('successCount').textContent = data.success_count.toLocaleString();
            document.getElementById('failedCount').textContent = data.failed_count.toLocaleString();
            document.getElementById('installingCount').textContent = data.installing_count.toLocaleString();
            document.getElementById('successRate').textContent = data.success_rate.toFixed(1) + '%';
            document.getElementById('lastUpdated').textContent = 'Updated: ' + new Date().toLocaleTimeString();
            document.getElementById('error').style.display = 'none';
        }
        
        function updateCharts(data) {
            // Daily chart
            if (charts.daily) charts.daily.destroy();
            charts.daily = new Chart(document.getElementById('dailyChart'), {
                type: 'line',
                data: {
                    labels: data.daily_stats.map(d => d.date.slice(5)), // MM-DD
                    datasets: [
                        {
                            label: 'Success',
                            data: data.daily_stats.map(d => d.success),
                            borderColor: chartColors.green,
                            backgroundColor: 'rgba(63, 185, 80, 0.1)',
                            fill: true,
                            tension: 0.3
                        },
                        {
                            label: 'Failed',
                            data: data.daily_stats.map(d => d.failed),
                            borderColor: chartColors.red,
                            backgroundColor: 'rgba(248, 81, 73, 0.1)',
                            fill: true,
                            tension: 0.3
                        }
                    ]
                },
                options: chartDefaults
            });
            
            // Status pie chart
            if (charts.status) charts.status.destroy();
            charts.status = new Chart(document.getElementById('statusChart'), {
                type: 'doughnut',
                data: {
                    labels: ['Success', 'Failed', 'Installing'],
                    datasets: [{
                        data: [data.success_count, data.failed_count, data.installing_count],
                        backgroundColor: [chartColors.green, chartColors.red, chartColors.yellow]
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: { color: '#c9d1d9' }
                        }
                    }
                }
            });
            
            // Top apps chart
            if (charts.apps) charts.apps.destroy();
            charts.apps = new Chart(document.getElementById('appsChart'), {
                type: 'bar',
                data: {
                    labels: data.top_apps.map(a => a.app),
                    datasets: [{
                        label: 'Installations',
                        data: data.top_apps.map(a => a.count),
                        backgroundColor: chartColors.blue
                    }]
                },
                options: {
                    ...chartDefaults,
                    indexAxis: 'y',
                    plugins: { legend: { display: false } }
                }
            });
            
            // OS distribution chart
            if (charts.os) charts.os.destroy();
            charts.os = new Chart(document.getElementById('osChart'), {
                type: 'pie',
                data: {
                    labels: data.os_distribution.map(o => o.os),
                    datasets: [{
                        data: data.os_distribution.map(o => o.count),
                        backgroundColor: [
                            chartColors.blue, chartColors.green, chartColors.purple,
                            chartColors.yellow, chartColors.red, chartColors.gray
                        ]
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'right',
                            labels: { color: '#c9d1d9' }
                        }
                    }
                }
            });
            
            // Method chart
            if (charts.method) charts.method.destroy();
            charts.method = new Chart(document.getElementById('methodChart'), {
                type: 'bar',
                data: {
                    labels: data.method_stats.map(m => m.method || 'default'),
                    datasets: [{
                        label: 'Count',
                        data: data.method_stats.map(m => m.count),
                        backgroundColor: chartColors.purple
                    }]
                },
                options: {
                    ...chartDefaults,
                    plugins: { legend: { display: false } }
                }
            });
        }
        
        function updateTable(records) {
            allRecords = records || [];
            
            // Populate OS filter
            const osFilter = document.getElementById('filterOs');
            const uniqueOs = [...new Set(allRecords.map(r => r.os_type).filter(Boolean))];
            osFilter.innerHTML = '<option value="">All OS</option>' + 
                uniqueOs.map(os => '<option value="' + os + '">' + os + '</option>').join('');
            
            filterTable();
        }
        
        function filterTable() {
            const appFilter = document.getElementById('filterApp').value.toLowerCase();
            const statusFilter = document.getElementById('filterStatus').value;
            const osFilter = document.getElementById('filterOs').value;
            
            const filtered = allRecords.filter(r => {
                if (appFilter && !r.nsapp.toLowerCase().includes(appFilter)) return false;
                if (statusFilter && r.status !== statusFilter) return false;
                if (osFilter && r.os_type !== osFilter) return false;
                return true;
            });
            
            const tbody = document.getElementById('recordsTable');
            if (filtered.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" class="loading">No records found</td></tr>';
                return;
            }
            
            tbody.innerHTML = filtered.slice(0, 50).map(r => {
                const statusClass = r.status || 'unknown';
                return '<tr>' +
                    '<td><strong>' + (r.nsapp || '-') + '</strong></td>' +
                    '<td><span class="status-badge ' + statusClass + '">' + (r.status || '-') + '</span></td>' +
                    '<td>' + (r.os_type || '-') + ' ' + (r.os_version || '') + '</td>' +
                    '<td>' + (r.type || '-') + '</td>' +
                    '<td>' + (r.method || 'default') + '</td>' +
                    '<td>' + (r.exit_code || '-') + '</td>' +
                    '<td title="' + (r.error || '').replace(/"/g, '&quot;') + '">' + 
                        ((r.error || '').slice(0, 40) + (r.error && r.error.length > 40 ? '...' : '')) + '</td>' +
                '</tr>';
            }).join('');
        }
        
        async function refreshData() {
            try {
                const data = await fetchData();
                updateStats(data);
                updateCharts(data);
                updateTable(data.recent_records);
            } catch (e) {
                console.error(e);
            }
        }
        
        // Initial load
        refreshData();
        
        // Refresh on time range change
        document.getElementById('timeRange').addEventListener('change', refreshData);
        
        // Auto-refresh every 60 seconds
        setInterval(refreshData, 60000);
    </script>
</body>
</html>`
}
