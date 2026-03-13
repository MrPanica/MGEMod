/**
 * Profile Page JavaScript
 * MGE Statistics
 */

const i18n = window.MGE_I18N || {};
const tJs = (key, fallback = '') => (typeof i18n[key] === 'string' ? i18n[key] : (fallback || key));
const currentLang = window.MGE_LANG || 'ru';

function buildAjaxUrl(params) {
    const url = new URL(window.location.pathname, window.location.origin);
    Object.entries(params).forEach(([key, value]) => {
        if (value !== undefined && value !== null && value !== '') {
            url.searchParams.set(key, String(value));
        }
    });

    if (!url.searchParams.has('lang') && currentLang) {
        url.searchParams.set('lang', currentLang);
    }

    return `${url.pathname}?${url.searchParams.toString()}`;
}

async function parseJsonResponseSafe(response, contextLabel) {
    const rawResponse = await response.text();
    let data = null;
    let normalizedResponse = rawResponse;

    if (normalizedResponse.charCodeAt(0) === 0xFEFF) {
        normalizedResponse = normalizedResponse.slice(1);
    }
    normalizedResponse = normalizedResponse.trim();

    try {
        data = JSON.parse(normalizedResponse);
    } catch (parseError) {
        const firstBrace = normalizedResponse.indexOf('{');
        const lastBrace = normalizedResponse.lastIndexOf('}');

        if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
            const maybeJson = normalizedResponse.slice(firstBrace, lastBrace + 1);
            try {
                data = JSON.parse(maybeJson);
            } catch (nestedParseError) {
                const preview = normalizedResponse.slice(0, 220).replace(/\s+/g, ' ');
                throw new Error(`Invalid JSON response in ${contextLabel} (${response.status}): ${preview}`);
            }
        } else {
            const preview = normalizedResponse.slice(0, 220).replace(/\s+/g, ' ');
            throw new Error(`Invalid JSON response in ${contextLabel} (${response.status}): ${preview}`);
        }
    }

    if (!response.ok) {
        throw new Error(data?.error || `HTTP error in ${contextLabel}: ${response.status}`);
    }

    if (data && data.error) {
        throw new Error(data.error);
    }

    return data;
}


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
        <div>${tJs('js_rating', 'Rating')}: ${rating}</div>
        <div>${tJs('js_duels', 'Duels')}: ${total}</div>
        <div>${tJs('js_wins', 'Wins')}: ${wins} (${winrate}%)</div>
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
                <div style="color: #888;">${tJs('js_rating', 'Rating')}:</div>
                <div style="color: #fff; font-weight: bold; font-size: 15px;">${rating}</div>
                <div style="color: #888;">${tJs('js_duels', 'Duels')}:</div>
                <div style="color: #fff;">${total}</div>
                <div style="color: #888;">${tJs('js_wins', 'Wins')}:</div>
                <div style="color: #4caf50;">${wins}</div>
                <div style="color: #888;">${tJs('js_losses', 'Losses')}:</div>
                <div style="color: #f44336;">${losses}</div>
                <div style="color: #888;">${tJs('js_winrate', 'Win rate')}:</div>
                <div style="color: #fff; font-weight: bold;">${winrate}%</div>
            </div>
        </div>
    `;
}

// ==================== ACTIVITY HEATMAP ====================
// AJAX function to change year without page reload
async function changeYearAjax(year) {
    document.querySelectorAll('.year-btn, .year-option').forEach(el => {
        el.classList.toggle('active', el.textContent.trim() == year);
    });

    const heatmapContainer = document.querySelector('.activity-heatmap-container-full-width');
    if (!heatmapContainer) return;

    const originalContent = heatmapContainer.innerHTML;
    heatmapContainer.innerHTML = '<div style="display: flex; justify-content: center; align-items: center; height: 130px;"><div class="loading-spinner"></div></div>';

    try {
        const steamId = window.PROFILE_STEAM_ID || document.querySelector('[data-player-steamid]')?.getAttribute('data-player-steamid');
        if (!steamId) throw new Error('Steam ID not found');

        const response = await fetch(buildAjaxUrl({
            ajax: 'get_activity_heatmap',
            steam_id: steamId,
            year: year
        }));

        const data = await parseJsonResponseSafe(response, 'activity heatmap');
        if (!data || typeof data.heatmap_html !== 'string') {
            throw new Error('Invalid activity heatmap payload');
        }

        heatmapContainer.innerHTML = data.heatmap_html;
    } catch (error) {
        console.error('Error loading heatmap data:', error);
        heatmapContainer.innerHTML = originalContent;
        const reason = error && error.message ? `: ${error.message}` : '';
        alert(`${tJs('js_error_loading_year', 'Failed to load data for selected year')}${reason}`);
    }
}

async function showDailyDuelsChart(date) {
    const chartContainer = document.getElementById('daily-duels-chart-container');
    const dateDisplay = document.getElementById('selected-date-display');
    const chartTitle = document.getElementById('daily-chart-title');

    if (!chartContainer) return;

    // Update the date display
    if (dateDisplay) dateDisplay.textContent = date;
    if (chartTitle) chartTitle.innerHTML = `${tJs('js_duels_for_date', 'Duels for')} <span id="selected-date-display">${date}</span>`;

    // Show the chart container
    chartContainer.style.display = 'block';

    // Scroll to the chart
    chartContainer.scrollIntoView({ behavior: 'smooth' });

    // Fetch duels data for the selected date
    try {
        chartContainer.querySelectorAll('.daily-chart-error').forEach((node) => node.remove());
        const duelsData = await fetchDailyDuelsData(date);
        createDailyDuelsChart(duelsData, date);
    } catch (error) {
        console.error('Error fetching daily duels data:', error);
        const errorNode = document.createElement('p');
        errorNode.className = 'daily-chart-error';
        errorNode.style.color = '#f85149';
        errorNode.style.padding = '10px';
        errorNode.textContent = `${tJs('js_error_loading_data', 'Failed to load data')}: ${error.message}`;
        chartContainer.appendChild(errorNode);
    }
}

// Function to fetch daily duels data via AJAX
async function fetchDailyDuelsData(date) {
    const steamId = window.PROFILE_STEAM_ID || document.querySelector('[data-player-steamid]')?.getAttribute('data-player-steamid');

    if (!steamId) {
        throw new Error('Unable to determine player Steam ID');
    }

    const response = await fetch(buildAjaxUrl({
        ajax: 'get_daily_duels',
        steam_id: steamId,
        date: date
    }));

    return parseJsonResponseSafe(response, 'daily duels');
}

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
                    text: `${tJs('js_duels_for_date', 'Duels for')} ${date}`
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
