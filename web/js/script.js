// Add smooth animations and interactions
document.addEventListener('DOMContentLoaded', function() {
    // Add hover effects to cards
    const cards = document.querySelectorAll('.stat-item, .card');
    cards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-2px)';
            this.style.boxShadow = '0 10px 30px rgba(0,0,0,0.3)';
        });

        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
            this.style.boxShadow = 'none';
        });
    });

    // Tab functionality
    const tabs = document.querySelectorAll('.tab');
    const tabContents = document.querySelectorAll('.tab-content');

    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            const tabId = this.getAttribute('data-tab');

            // Remove active class from all tabs and contents
            tabs.forEach(t => t.classList.remove('active'));
            tabContents.forEach(c => c.classList.remove('active'));

            // Add active class to clicked tab and corresponding content
            this.classList.add('active');
            const targetTab = document.getElementById(`${tabId}-tab`);
            if (targetTab) {
                targetTab.classList.add('active');

                // If switching to recent duels tab, ensure pagination is updated
                if (tabId === 'recent-duels') {
                    // Update pagination links to use correct IDs for the second container
                    const paginationLinks = targetTab.querySelectorAll('#pagination-2 a');
                    paginationLinks.forEach(link => {
                        if (!link.classList.contains('pagination-link')) {
                            link.classList.add('pagination-link');
                        }
                    });
                }

                // If switching to overview tab, ensure players pagination is updated
                if (tabId === 'overview') {
                    const playersPaginationLinks = targetTab.querySelectorAll('#players-pagination a');
                    playersPaginationLinks.forEach(link => {
                        if (!link.classList.contains('pagination-link')) {
                            link.classList.add('pagination-link');
                        }
                    });
                }
            }
        });
    });

    // Show loading overlay when navigating to new pages (only for non-AJAX navigation)
    function showLoading() {
        document.getElementById('loadingOverlay').style.display = 'flex';
    }

    function hideLoading() {
        document.getElementById('loadingOverlay').style.display = 'none';
    }

    // Add loading effect to specific navigation links (not AJAX pagination)
    const duelIdLinks = document.querySelectorAll('a.duel-id-link:not(#duels-container a, #duels-container-2 a)');
    duelIdLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            showLoading();
        });
    });

    const profileLinks = document.querySelectorAll('a[href*="profile="]:not(#duels-container a, #duels-container-2 a, .profile-duels-pagination a)');
    profileLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            showLoading();
        });
    });

    const backLinks = document.querySelectorAll('a[href="?"]:not(#duels-container a, #duels-container-2 a, .profile-duels-pagination a), a[href*="stats_mge.php"]:not(#duels-container a, #duels-container-2 a, .profile-duels-pagination a)');
    backLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            showLoading();
        });
    });

    // Add loading effect to search form submission
    const searchForm = document.querySelector('.search-form');
    if (searchForm) {
        searchForm.addEventListener('submit', function(e) {
            showLoading();
        });
    }

    // Hide loading after page loads
    window.addEventListener('load', function() {
        hideLoading();
    });

    // AJAX pagination for recent duels
    function loadDuelsPage(page, containerId, tbodyId, paginationId) {
        const container = document.getElementById(containerId);
        const refreshIndicator = container.querySelector('.refresh-indicator');

        // Show refresh indicator (local to the table, not global)
        refreshIndicator.classList.add('active');
        container.classList.add('refreshing');

        fetch(`?ajax=get_duels_page&page=${page}`)
            .then(response => response.json())
            .then(data => {
                const tbody = document.getElementById(tbodyId);
                tbody.innerHTML = '';

                data.duels.forEach(duel => {
                    const row = document.createElement('tr');
                    row.innerHTML = `
                        <td><a href="?duel=${duel.id}&type=${duel.type}" class="duel-id-link">${duel.id}</a></td>
                        <td>${duel.type}</td>
                        <td>${new Date(duel.endtime * 1000).toLocaleString('ru-RU')}</td>
                        <td><a href="?profile=${encodeURIComponent(duel.winner)}" style="color: var(--success); text-decoration: none;">${duel.winner_nick}</a></td>
                        <td><a href="?profile=${encodeURIComponent(duel.loser)}" style="color: var(--danger); text-decoration: none;">${duel.loser_nick}</a></td>
                        <td>${duel.mapname}</td>
                        <td>${duel.arenaname}</td>
                        <td>${duel.winnerscore}:${duel.loserscore}</td>
                    `;
                    tbody.appendChild(row);
                });

                // Update pagination
                const pagination = document.getElementById(paginationId);
                pagination.innerHTML = '';

                if (data.current_page > 1) {
                    const prevLink = document.createElement('a');
                    prevLink.href = `?page=${data.current_page - 1}`;
                    prevLink.innerHTML = '<i class="fas fa-chevron-left"></i> Назад';
                    prevLink.addEventListener('click', function(e) {
                        e.preventDefault();
                        loadDuelsPage(data.current_page - 1, containerId, tbodyId, paginationId);
                    });
                    pagination.appendChild(prevLink);
                }

                for (let i = Math.max(1, data.current_page - 2); i <= Math.min(data.total_pages, data.current_page + 2); i++) {
                    const pageLink = document.createElement('span');
                    if (i === data.current_page) {
                        pageLink.className = 'current';
                        pageLink.textContent = i;
                    } else {
                        pageLink.className = 'pagination-link';
                        pageLink.textContent = i;
                        pageLink.addEventListener('click', function() {
                            loadDuelsPage(i, containerId, tbodyId, paginationId);
                        });
                    }
                    pagination.appendChild(pageLink);
                }

                if (data.current_page < data.total_pages) {
                    const nextLink = document.createElement('a');
                    nextLink.href = `?page=${data.current_page + 1}`;
                    nextLink.innerHTML = 'Вперед <i class="fas fa-chevron-right"></i>';
                    nextLink.addEventListener('click', function(e) {
                        e.preventDefault();
                        loadDuelsPage(data.current_page + 1, containerId, tbodyId, paginationId);
                    });
                    pagination.appendChild(nextLink);
                }

                // Hide refresh indicator after a short delay to show the animation
                setTimeout(() => {
                    refreshIndicator.classList.remove('active');
                    container.classList.remove('refreshing');
                }, 500);
            })
            .catch(error => {
                console.error('Error loading duels:', error);
                // Hide refresh indicator even if there's an error
                refreshIndicator.classList.remove('active');
                container.classList.remove('refreshing');
            });
    }

    // Add event listeners to pagination links - prevent global loading overlay
    document.querySelectorAll('.pagination a').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const href = this.getAttribute('href');
            const match = href.match(/page=(\d+)/);
            if (match) {
                const page = parseInt(match[1]);
                // Determine which container this pagination link belongs to
                const container = this.closest('.card').querySelector('.refreshable-content');
                if (container) {
                    const containerId = container.id;
                    const tbodyId = container.querySelector('tbody').id;
                    const paginationId = this.closest('.pagination').id;

                    if (containerId === 'duels-container') {
                        loadDuelsPage(page, 'duels-container', 'duels-tbody', 'pagination');
                    } else if (containerId === 'duels-container-2') {
                        loadDuelsPage(page, 'duels-container-2', 'duels-tbody-2', 'pagination-2');
                    } else if (containerId === 'players-container') {
                        loadPlayersPage(page, 'players-container', 'players-tbody', 'players-pagination');
                    }
                }
            }
        });
    });

    // Function to load players page with pagination
    function loadPlayersPage(page, containerId, tbodyId, paginationId) {
        const container = document.getElementById(containerId);
        const refreshIndicator = container.querySelector('.refresh-indicator');

        // Show refresh indicator
        if (refreshIndicator) {
            refreshIndicator.classList.add('active');
            container.classList.add('refreshing');
        }

        // Prepare sort parameters
        const urlParams = new URLSearchParams(window.location.search);
        const orderBy = urlParams.get('sort_by') || 'rating';
        const orderDir = urlParams.get('sort_dir') || 'DESC';

        fetch(`?ajax=get_players_page&page=${page}&sort_by=${orderBy}&sort_dir=${orderDir}`)
            .then(response => response.json())
            .then(data => {
                const tbody = document.getElementById(tbodyId);
                if (tbody) {
                    tbody.innerHTML = '';

                    data.players.forEach((player, index) => {
                        const winrate = player.wins + player.losses > 0 ?
                            ((player.wins / (player.wins + player.losses)) * 100).toFixed(2) : 0;

                        const row = document.createElement('tr');
                        row.className = `rank-${(data.current_page - 1) * 25 + index + 1}`;
                        row.innerHTML = `
                            <td><span class="rank-badge">${(data.current_page - 1) * 25 + index + 1}</span></td>
                            <td><a href="?profile=${encodeURIComponent(player.steamid)}" style="color: var(--accent); text-decoration: none;">${player.nick}</a></td>
                            <td>${player.rating}</td>
                            <td>${player.wins}</td>
                            <td>${player.losses}</td>
                            <td>${winrate}%</td>
                        `;
                        tbody.appendChild(row);
                    });
                }

                // Update pagination
                const pagination = document.getElementById(paginationId);
                if (pagination) {
                    pagination.innerHTML = '';

                    if (data.current_page > 1) {
                        const prevLink = document.createElement('a');
                        prevLink.href = '#';
                        prevLink.innerHTML = '<i class="fas fa-chevron-left"></i> Назад';
                        prevLink.addEventListener('click', function(e) {
                            e.preventDefault();
                            loadPlayersPage(data.current_page - 1, containerId, tbodyId, paginationId);
                        });
                        pagination.appendChild(prevLink);
                    }

                    for (let i = Math.max(1, data.current_page - 2); i <= Math.min(data.total_pages, data.current_page + 2); i++) {
                        const pageLink = document.createElement('span');
                        if (i === data.current_page) {
                            pageLink.className = 'current';
                            pageLink.textContent = i;
                        } else {
                            pageLink.className = 'pagination-link';
                            pageLink.textContent = i;
                            pageLink.addEventListener('click', function() {
                                loadPlayersPage(i, containerId, tbodyId, paginationId);
                            });
                        }
                        pagination.appendChild(pageLink);
                    }

                    if (data.current_page < data.total_pages) {
                        const nextLink = document.createElement('a');
                        nextLink.href = '#';
                        nextLink.innerHTML = 'Вперед <i class="fas fa-chevron-right"></i>';
                        nextLink.addEventListener('click', function(e) {
                            e.preventDefault();
                            loadPlayersPage(data.current_page + 1, containerId, tbodyId, paginationId);
                        });
                        pagination.appendChild(nextLink);
                    }
                }

                // Hide refresh indicator after a short delay
                setTimeout(() => {
                    if (refreshIndicator) {
                        refreshIndicator.classList.remove('active');
                        container.classList.remove('refreshing');
                    }
                }, 500);
            })
            .catch(error => {
                console.error('Error loading players:', error);
                if (refreshIndicator) {
                    refreshIndicator.classList.remove('active');
                    container.classList.remove('refreshing');
                }
            });
    }

    // Add click event to pagination links in both tabs
    document.querySelectorAll('.pagination-link').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault(); // Prevent default navigation
            const page = parseInt(this.textContent);
            const containerId = this.closest('.card')?.querySelector('.refreshable-content')?.id;

            if (containerId) {
                const tbodyId = this.closest('.card').querySelector('tbody').id;
                const paginationId = this.closest('.pagination').id;

                if (containerId === 'duels-container') {
                    loadDuelsPage(page, 'duels-container', 'duels-tbody', 'pagination');
                } else if (containerId === 'duels-container-2') {
                    loadDuelsPage(page, 'duels-container-2', 'duels-tbody-2', 'pagination-2');
                } else if (containerId === 'players-container') {
                    loadPlayersPage(page, 'players-container', 'players-tbody', 'players-pagination');
                }
            }
        });
    });

    // Also handle pagination links in the first tab for players
    document.querySelectorAll('#players-pagination a').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const href = this.getAttribute('href');
            const match = href.match(/page=(\d+)/);
            if (match) {
                const page = parseInt(match[1]);
                loadPlayersPage(page, 'players-container', 'players-tbody', 'players-pagination');
            }
        });
    });

    // Function to load profile duels page with pagination
    function loadProfileDuelsPage(page, steamId) {
        const tbody = document.querySelector('#profile-duels-table tbody');
        const pagination = document.querySelector('.profile-duels-pagination');
        const container = document.querySelector('#profile-duels-table'); // Container for refresh indicator

        if (!tbody || !pagination) {
            // If we're not on a profile page, skip
            return;
        }

        // Show refresh indicator similar to loadPlayersPage
        if (container) {
            // Add a refresh indicator if it doesn't exist
            let refreshIndicator = container.querySelector('.refresh-indicator');
            if (!refreshIndicator) {
                refreshIndicator = document.createElement('div');
                refreshIndicator.className = 'refresh-indicator';
                refreshIndicator.innerHTML = '<div class="refresh-spinner"></div><span>Загрузка...</span>';
                container.style.position = 'relative'; // Ensure container has position relative
                container.insertBefore(refreshIndicator, container.firstChild);
            }

            refreshIndicator.classList.add('active');
            container.classList.add('refreshing');
        }

        fetch(`?ajax=get_profile_duels_page&steam_id=${encodeURIComponent(steamId)}&page=${page}`)
            .then(response => response.json())
            .then(data => {
                // Hide refresh indicator
                if (container) {
                    const refreshIndicator = container.querySelector('.refresh-indicator');
                    if (refreshIndicator) {
                        refreshIndicator.classList.remove('active');
                        container.classList.remove('refreshing');
                    }
                }

                // Clear tbody and populate with new data
                tbody.innerHTML = '';

                if (data.duels.length === 0) {
                    const emptyRow = document.createElement('tr');
                    emptyRow.innerHTML = '<td colspan="8" style="text-align: center;">Нет данных о дуэлях</td>';
                    tbody.appendChild(emptyRow);
                } else {
                    data.duels.forEach(duel => {
                        const row = document.createElement('tr');
                        const resultClass = duel.is_winner ? 'win' : 'loss';
                        const resultText = duel.is_winner ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ';

                        // Calculate ELO change
                        let eloChange = 0;
                        if (duel.is_winner) {
                            if (duel.type === '1v1') {
                                eloChange = duel.winner_new_elo - duel.winner_previous_elo;
                            } else {
                                // For 2v2, use the first winner's ELO change
                                eloChange = duel.winner_new_elo - duel.winner_previous_elo;
                            }
                        } else {
                            if (duel.type === '1v1') {
                                eloChange = duel.loser_new_elo - duel.loser_previous_elo;
                            } else {
                                // For 2v2, use the first loser's ELO change
                                eloChange = duel.loser_new_elo - duel.loser_previous_elo;
                            }
                        }

                        const eloChangeClass = eloChange >= 0 ? 'positive' : 'negative';
                        const eloChangeDisplay = eloChange >= 0 ? `+${eloChange}` : `${eloChange}`;

                        row.innerHTML = `
                            <td><a href="?duel=${duel.id}&type=${duel.type}&profile=${encodeURIComponent(steamId)}" class="duel-id-link">${duel.id}</a></td>
                            <td>${duel.type}</td>
                            <td>${new Date(duel.endtime * 1000).toLocaleString('ru-RU')}</td>
                            <td><span class="duel-result ${resultClass}">${resultText}</span></td>
                            <td>${duel.mapname}</td>
                            <td>${duel.arenaname}</td>
                            <td>${duel.winnerscore}:${duel.loserscore}</td>
                            <td class="elo-change ${eloChangeClass}">${eloChangeDisplay}</td>
                        `;
                        tbody.appendChild(row);
                    });
                }

                // Update pagination
                pagination.innerHTML = '';

                if (data.current_page > 1) {
                    const prevLink = document.createElement('a');
                    prevLink.href = `?profile=${encodeURIComponent(steamId)}&duels_page=${data.current_page - 1}`;
                    prevLink.innerHTML = '<i class="fas fa-chevron-left"></i> Назад';
                    prevLink.addEventListener('click', function(e) {
                        e.preventDefault();
                        loadProfileDuelsPage(data.current_page - 1, steamId);
                    });
                    pagination.appendChild(prevLink);
                }

                for (let i = Math.max(1, data.current_page - 2); i <= Math.min(data.total_pages, data.current_page + 2); i++) {
                    const pageLink = document.createElement('span');
                    if (i === data.current_page) {
                        pageLink.className = 'current';
                        pageLink.textContent = i;
                    } else {
                        pageLink.className = 'pagination-link';
                        pageLink.textContent = i;
                        pageLink.addEventListener('click', function() {
                            loadProfileDuelsPage(i, steamId);
                        });
                    }
                    pagination.appendChild(pageLink);
                }

                if (data.current_page < data.total_pages) {
                    const nextLink = document.createElement('a');
                    nextLink.href = `?profile=${encodeURIComponent(steamId)}&duels_page=${data.current_page + 1}`;
                    nextLink.innerHTML = 'Вперед <i class="fas fa-chevron-right"></i>';
                    nextLink.addEventListener('click', function(e) {
                        e.preventDefault();
                        loadProfileDuelsPage(data.current_page + 1, steamId);
                    });
                    pagination.appendChild(nextLink);
                }
            })
            .catch(error => {
                console.error('Error loading profile duels:', error);

                // Hide refresh indicator even on error
                if (container) {
                    const refreshIndicator = container.querySelector('.refresh-indicator');
                    if (refreshIndicator) {
                        refreshIndicator.classList.remove('active');
                        container.classList.remove('refreshing');
                    }
                }

                tbody.innerHTML = '';
                const errorRow = document.createElement('tr');
                errorRow.innerHTML = '<td colspan="8" style="text-align: center; color: red;">Ошибка загрузки данных</td>';
                tbody.appendChild(errorRow);
            });
    }
    // Add click handlers for profile duels pagination if on profile page
    if (document.querySelector('#profile-duels-table')) {
        const profileSteamId = new URLSearchParams(window.location.search).get('profile');
        if (profileSteamId) {
            // Add event listeners to profile duels pagination links
            document.querySelectorAll('.profile-duels-pagination a').forEach(link => {
                link.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation(); // Prevent other event handlers from firing

                    // Extract page number from href attribute
                    const href = this.getAttribute('href');
                    const url = new URL(href, window.location.origin + window.location.pathname);
                    const pageParam = url.searchParams.get('duels_page');

                    if (pageParam) {
                        const page = parseInt(pageParam);
                        if (!isNaN(page)) {
                            loadProfileDuelsPage(page, profileSteamId);
                        }
                    }
                });
            });
        }
    }

    // Auto-refresh duels periodically if authenticated
    // Note: The PHP condition for this would need to be handled in the HTML template
    // setInterval(function() {
    //     // In a real app, you would fetch updated data here
    //     console.log('Checking for new duel data...');
    // }, 30000); // Every 30 seconds
});