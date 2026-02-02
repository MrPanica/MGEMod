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

        // Get sort parameters from URL
        const urlParams = new URLSearchParams(window.location.search);
        const duelOrderBy = urlParams.get('duel_sort_by') || 'endtime';
        const duelOrderDir = urlParams.get('duel_sort_dir') || 'DESC';

        fetch(`?ajax=get_duels_page&page=${page}&duel_sort_by=${duelOrderBy}&duel_sort_dir=${duelOrderDir}`)
            .then(response => response.json())
            .then(data => {
                console.log('AJAX Response Data:', data); // Отладка
                
                const tbody = document.getElementById(tbodyId);
                tbody.innerHTML = '';

                data.duels.forEach(duel => {
                    console.log('Processing duel:', duel); // Отладка
                    
                    const row = document.createElement('tr');
                    
                    // Create all cells first
                    const idCell = document.createElement('td');
                    idCell.innerHTML = `<a href="?duel=${duel.id}&type=${duel.type}" class="duel-id-link">${duel.id}</a>`;
                    
                    const typeCell = document.createElement('td');
                    typeCell.textContent = duel.type;
                    
                    const dateCell = document.createElement('td');
                    dateCell.textContent = new Date(duel.endtime * 1000).toLocaleString('ru-RU');
                    
                    const winnerCell = document.createElement('td');
                    winnerCell.innerHTML = `<a href="?profile=${encodeURIComponent(duel.winner)}" style="color: var(--success); text-decoration: none;">${duel.winner_nick}</a>`;
                    
                    const winnerClassCell = document.createElement('td');
                    console.log('Raw winner_class_html:', duel.winner_class_html); // Отладка
                    // Удаляем лишние экранирования, если они есть
                    const processedWinnerClassHtml = duel.winner_class_html.replace(/\\"/g, '"');
                    console.log('Processed winner_class_html:', processedWinnerClassHtml); // Отладка
                    winnerClassCell.innerHTML = processedWinnerClassHtml;
                    
                    const loserCell = document.createElement('td');
                    loserCell.innerHTML = `<a href="?profile=${encodeURIComponent(duel.loser)}" style="color: var(--danger); text-decoration: none;">${duel.loser_nick}</a>`;
                    
                    const loserClassCell = document.createElement('td');
                    console.log('Raw loser_class_html:', duel.loser_class_html); // Отладка
                    // Удаляем лишние экранирования, если они есть
                    const processedLoserClassHtml = duel.loser_class_html.replace(/\\"/g, '"');
                    console.log('Processed loser_class_html:', processedLoserClassHtml); // Отладка
                    loserClassCell.innerHTML = processedLoserClassHtml;
                    
                    // Calculate ELO change for winner
                    let eloChange = null;
                    if (duel.winner_new_elo !== undefined && duel.winner_previous_elo !== undefined) {
                        eloChange = duel.winner_new_elo - duel.winner_previous_elo;
                    }

                    const eloChangeCell = document.createElement('td');
                    if (eloChange !== null) {
                        const eloChangeClass = eloChange > 0 ? 'positive' : (eloChange < 0 ? 'negative' : 'neutral');
                        eloChangeCell.innerHTML = `<span class="elo-change ${eloChangeClass}">${eloChange > 0 ? '+' : ''}${eloChange}</span>`;
                    } else {
                        eloChangeCell.innerHTML = '<span class="elo-change neutral">-</span>';
                    }

                    const arenaCell = document.createElement('td');
                    arenaCell.textContent = duel.arenaname;

                    const scoreCell = document.createElement('td');
                    scoreCell.textContent = `${duel.winnerscore}:${duel.loserscore}`;

                    // Append all cells to the row
                    row.appendChild(idCell);
                    row.appendChild(typeCell);
                    row.appendChild(dateCell);
                    row.appendChild(winnerCell);
                    row.appendChild(winnerClassCell);
                    row.appendChild(loserCell);
                    row.appendChild(loserClassCell);
                    row.appendChild(eloChangeCell);
                    row.appendChild(arenaCell);
                    row.appendChild(scoreCell);
                    
                    tbody.appendChild(row);
                });

                // Update pagination
                const pagination = document.getElementById(paginationId);
                pagination.innerHTML = '';

                // Get sort parameters from URL
                const urlParams = new URLSearchParams(window.location.search);
                const duelOrderBy = urlParams.get('duel_sort_by') || 'endtime';
                const duelOrderDir = urlParams.get('duel_sort_dir') || 'DESC';

                if (data.current_page > 1) {
                    const prevLink = document.createElement('a');
                    prevLink.href = `?page=${data.current_page - 1}&duel_sort_by=${duelOrderBy}&duel_sort_dir=${duelOrderDir}`;
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
                    nextLink.href = `?page=${data.current_page + 1}&duel_sort_by=${duelOrderBy}&duel_sort_dir=${duelOrderDir}`;
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

    // Handle sort links in table headers - allow them to navigate normally
    document.querySelectorAll('.duels-table thead th a').forEach(link => {
        link.addEventListener('click', function(e) {
            // Allow default navigation for sort links
            // They will reload the page with new sort parameters
            showLoading();
        });
    });

    // Handle sort links in players table headers - allow them to navigate normally
    document.querySelectorAll('.top-players-table thead th a').forEach(link => {
        link.addEventListener('click', function(e) {
            // Allow default navigation for sort links - show loading overlay
            showLoading();
        });
    });

    // Use event delegation for dynamically added sort links
    document.addEventListener('click', function(e) {
        const link = e.target.closest('.top-players-table thead th a');
        if (link) {
            // This is a sort link - let it navigate normally
            showLoading();
        }
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

    // Use event delegation for profile duels pagination links
    document.addEventListener('click', function(e) {
        const target = e.target.closest('.profile-duels-pagination a');
        if (target) {
            e.preventDefault();
            
            const href = target.getAttribute('href');
            const profileMatch = href.match(/profile=([^&]*)/);
            const pageMatch = href.match(/duels_page=(\d+)/);
            
            if (profileMatch && pageMatch) {
                const profileId = decodeURIComponent(profileMatch[1]);
                const page = parseInt(pageMatch[1]);
                
                // Load profile duels page via AJAX
                loadProfileDuelsPage(page, profileId);
            }
        }
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
                    emptyRow.innerHTML = '<td colspan="10" style="text-align: center;">Нет данных о дуэлях</td>';
                    tbody.appendChild(emptyRow);
                } else {
                    data.duels.forEach(duel => {
                        const row = document.createElement('tr');
                        const resultClass = duel.is_winner ? 'win' : 'loss';
                        const resultText = duel.is_winner ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ';

                        // Calculate ELO change
                        let eloChange = null;
                        if (duel.is_winner) {
                            if (duel.type === '1v1') {
                                if (duel.winner_new_elo !== undefined && duel.winner_previous_elo !== undefined) {
                                    eloChange = duel.winner_new_elo - duel.winner_previous_elo;
                                }
                            } else {
                                // For 2v2, use the first winner's ELO change
                                if (duel.winner_new_elo !== undefined && duel.winner_previous_elo !== undefined) {
                                    eloChange = duel.winner_new_elo - duel.winner_previous_elo;
                                }
                            }
                        } else {
                            if (duel.type === '1v1') {
                                if (duel.loser_new_elo !== undefined && duel.loser_previous_elo !== undefined) {
                                    eloChange = duel.loser_new_elo - duel.loser_previous_elo;
                                }
                            } else {
                                // For 2v2, use the first loser's ELO change
                                if (duel.loser_new_elo !== undefined && duel.loser_previous_elo !== undefined) {
                                    eloChange = duel.loser_new_elo - duel.loser_previous_elo;
                                }
                            }
                        }

                        const eloChangeClass = eloChange !== null ? (eloChange > 0 ? 'positive' : (eloChange < 0 ? 'negative' : 'neutral')) : 'neutral';
                        const eloChangeDisplay = eloChange !== null ? (eloChange > 0 ? `+${eloChange}` : `${eloChange}`) : '-';

                        // Determine opponent ID based on whether the current player won or lost
                        let opponentId, opponentNick, playerClass, opponentClass;
                        
                        if (duel.is_winner) {
                            // Player won, so opponent is the loser
                            if (duel.type === '1v1') {
                                opponentId = duel.loser;
                            } else {
                                // In 2v2, determine who was the second loser
                                if (duel.loser === steamId) {
                                    opponentId = duel.loser2;
                                } else {
                                    opponentId = duel.loser;
                                }
                            }
                            
                            // Player's class is winner's class, opponent's class is loser's class
                            playerClass = duel.winnerclass ? duel.winnerclass : '';
                            opponentClass = duel.loserclass ? duel.loserclass : '';
                        } else {
                            // Player lost, so opponent is the winner
                            if (duel.type === '1v1') {
                                opponentId = duel.winner;
                            } else {
                                // In 2v2, determine who was the second winner
                                if (duel.winner === steamId) {
                                    opponentId = duel.winner2;
                                } else {
                                    opponentId = duel.winner;
                                }
                            }
                            
                            // Player's class is loser's class, opponent's class is winner's class
                            playerClass = duel.loserclass ? duel.loserclass : '';
                            opponentClass = duel.winnerclass ? duel.winnerclass : '';
                        }
                        
                        // Get opponent nickname
                        fetch(`?ajax=get_player_nickname&steam_id=${encodeURIComponent(opponentId)}`)
                            .then(response => response.text())
                            .then(nick => {
                                opponentNick = nick;
                                
                                row.innerHTML = `
                                    <td><a href="?duel=${duel.id}&type=${duel.type}&profile=${encodeURIComponent(steamId)}" class="duel-id-link">${duel.id}</a></td>
                                    <td>${duel.type}</td>
                                    <td>${new Date(duel.endtime * 1000).toLocaleString('ru-RU')}</td>
                                    <td><span class="duel-result ${resultClass}">${resultText}</span></td>
                                    <td>${duel.is_winner ? duel.winnerclass_html : duel.loserclass_html}</td>
                                    <td><a href="?profile=${encodeURIComponent(opponentId)}" style="color: var(--accent); text-decoration: none;">${opponentNick}</a></td>
                                    <td>${duel.is_winner ? duel.loserclass_html : duel.winnerclass_html}</td>
                                    <td>${duel.arenaname}</td>
                                    <td>${duel.winnerscore}:${duel.loserscore}</td>
                                    <td class="elo-change ${eloChangeClass}">${eloChangeDisplay}</td>
                                `;
                                tbody.appendChild(row);
                            })
                            .catch(error => {
                                console.error('Error getting opponent nickname:', error);
                                
                                row.innerHTML = `
                                    <td><a href="?duel=${duel.id}&type=${duel.type}&profile=${encodeURIComponent(steamId)}" class="duel-id-link">${duel.id}</a></td>
                                    <td>${duel.type}</td>
                                    <td>${new Date(duel.endtime * 1000).toLocaleString('ru-RU')}</td>
                                    <td><span class="duel-result ${resultClass}">${resultText}</span></td>
                                    <td>${duel.is_winner ? duel.winnerclass_html : duel.loserclass_html}</td>
                                    <td><a href="?profile=${encodeURIComponent(opponentId)}" style="color: var(--accent); text-decoration: none;">${opponentId}</a></td>
                                    <td>${duel.is_winner ? duel.loserclass_html : duel.winnerclass_html}</td>
                                    <td>${duel.arenaname}</td>
                                    <td>${duel.winnerscore}:${duel.loserscore}</td>
                                    <td class="elo-change ${eloChangeClass}">${eloChangeDisplay}</td>
                                `;
                                tbody.appendChild(row);
                            });
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
            });
    }

    // Helper function to escape HTML
    function htmlspecialchars(text) {
        if (typeof text !== 'string') {
            text = String(text);
        }
        return text
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
    }

    // Removed AJAX pagination for sort links to allow normal navigation

});