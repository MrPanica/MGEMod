/**
 * Profile Page JavaScript
 * MGE Statistics
 */

// ==================== MATCHUP GRID ====================
function showMatchupTooltip(event, element) {
    const tooltip = document.getElementById('matchupTooltip');
    if (!tooltip) return;

    const rating = element.getAttribute('data-rating');
    const myClass = element.getAttribute('data-my-class-display');
    const oppClass = element.getAttribute('data-opp-class-display');
    const total = element.getAttribute('data-total');
    const wins = element.getAttribute('data-wins');
    const winrate = total > 0 ? Math.round((wins / total) * 100) : 0;

    tooltip.innerHTML = `
        <div><strong>${myClass} vs ${oppClass}</strong></div>
        <div>Рейтинг: ${rating}</div>
        <div>Дуэлей: ${total}</div>
        <div>Побед: ${wins} (${winrate}%)</div>
    `;

    tooltip.style.left = event.pageX + 10 + 'px';
    tooltip.style.top = event.pageY - 10 + 'px';
    tooltip.style.display = 'block';
}

function hideMatchupTooltip() {
    const tooltip = document.getElementById('matchupTooltip');
    if (tooltip) {
        tooltip.style.display = 'none';
    }
}

function showMatchupDetails(element) {
    const myClass = element.getAttribute('data-my-class-display');
    const oppClass = element.getAttribute('data-opp-class-display');
    const rating = element.getAttribute('data-rating');
    const total = element.getAttribute('data-total');
    const wins = element.getAttribute('data-wins');
    const losses = total - wins;
    const winrate = total > 0 ? Math.round((wins / total) * 100) : 0;

    const detailsContent = document.getElementById('matchupDetailsContent');
    if (!detailsContent) return;

    detailsContent.innerHTML = `
        <div style="background: #1a1a1a; padding: 14px; border-radius: 6px; height: 100%;">
            <div style="font-weight: bold; color: #fff; font-size: 14px; margin-bottom: 10px; padding-bottom: 8px; border-bottom: 1px solid #333;">${myClass} vs ${oppClass}</div>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px 14px; font-size: 13px;">
                <div style="color: #888;">Рейтинг:</div>
                <div style="color: #fff; font-weight: bold; font-size: 15px;">${rating}</div>
                <div style="color: #888;">Дуэлей:</div>
                <div style="color: #fff;">${total}</div>
                <div style="color: #888;">Побед:</div>
                <div style="color: #4caf50;">${wins}</div>
                <div style="color: #888;">Поражений:</div>
                <div style="color: #f44336;">${losses}</div>
                <div style="color: #888;">Винрейт:</div>
                <div style="color: #fff; font-weight: bold;">${winrate}%</div>
            </div>
        </div>
    `;
}

// ==================== ACTIVITY HEATMAP ====================
// AJAX function to change year without page reload
async function changeYearAjax(year) {
    // Update active state in year selector (works for both .year-btn and .year-option)
    document.querySelectorAll('.year-btn, .year-option').forEach(el => {
        el.classList.toggle('active', el.textContent.trim() == year);
    });

    // Show loading indicator
    const heatmapContainer = document.querySelector('.activity-heatmap-container-full-width');
    if (!heatmapContainer) return;

    const originalContent = heatmapContainer.innerHTML;
    heatmapContainer.innerHTML = '<div style="display: flex; justify-content: center; align-items: center; height: 130px;"><div class="loading-spinner"></div></div>';

    try {
        // Get steam ID from page data
        const steamId = window.PROFILE_STEAM_ID || document.querySelector('[data-player-steamid]')?.getAttribute('data-player-steamid');
        if (!steamId) throw new Error('Steam ID not found');

        const response = await fetch(`?ajax=get_activity_heatmap&steam_id=${encodeURIComponent(steamId)}&year=${year}`);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();

        // Update the heatmap with new data
        heatmapContainer.innerHTML = data.heatmap_html;

    } catch (error) {
        console.error('Error loading heatmap data:', error);
        // Restore original content if there's an error
        heatmapContainer.innerHTML = originalContent;
        alert('Ошибка загрузки данных за указанный год');
    }
}

// Function to show daily duels chart when clicking on a heatmap cell
async function showDailyDuelsChart(date) {
    const chartContainer = document.getElementById('daily-duels-chart-container');
    const dateDisplay = document.getElementById('selected-date-display');
    const chartTitle = document.getElementById('daily-chart-title');

    if (!chartContainer) return;

    // Update the date display
    if (dateDisplay) dateDisplay.textContent = date;
    if (chartTitle) chartTitle.innerHTML = 'Дуэли за <span id="selected-date-display">' + date + '</span>';

    // Show the chart container
    chartContainer.style.display = 'block';

    // Scroll to the chart
    chartContainer.scrollIntoView({ behavior: 'smooth' });

    // Fetch duels data for the selected date
    try {
        const duelsData = await fetchDailyDuelsData(date);
        createDailyDuelsChart(duelsData, date);
    } catch (error) {
        console.error('Error fetching daily duels data:', error);
        chartContainer.innerHTML += '<p style="color: #f85149; padding: 10px;">Ошибка загрузки данных</p>';
    }
}

// Function to fetch daily duels data via AJAX
async function fetchDailyDuelsData(date) {
    const steamId = window.PROFILE_STEAM_ID || document.querySelector('[data-player-steamid]')?.getAttribute('data-player-steamid');

    if (!steamId) {
        throw new Error('Unable to determine player Steam ID');
    }

    const response = await fetch(`?ajax=get_daily_duels&steam_id=${encodeURIComponent(steamId)}&date=${encodeURIComponent(date)}`);

    if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
    }

    const data = await response.json();

    if (data.error) {
        throw new Error(data.error);
    }

    return data;
}

// Function to create the daily duels chart
function createDailyDuelsChart(chartData, date) {
    const canvas = document.getElementById('dailyDuelsChart');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');

    // Destroy existing chart if it exists
    if (window.dailyDuelsChartInstance) {
        window.dailyDuelsChartInstance.destroy();
    }

    // Create new chart
    window.dailyDuelsChartInstance = new Chart(ctx, {
        type: 'line',
        data: chartData,
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: true,
                    position: 'top',
                },
                title: {
                    display: true,
                    text: `Дуэли за ${date}`
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: {
                        color: 'rgba(255, 255, 255, 0.1)'
                    },
                    ticks: {
                        color: '#888'
                    }
                },
                x: {
                    grid: {
                        color: 'rgba(255, 255, 255, 0.1)'
                    },
                    ticks: {
                        color: '#888'
                    }
                }
            }
        }
    });
}

// Function to hide the daily duels chart
function hideDailyDuelsChart() {
    const container = document.getElementById('daily-duels-chart-container');
    if (container) {
        container.style.display = 'none';
    }
}
