<?php
// Modern 2026 design for MGE statistics with Steam authentication
require_once 'auth/steam_handler.php';

/*
DATABASE INDEX RECOMMENDATIONS FOR PERFORMANCE:
Run these SQL commands to improve query performance:

-- Indexes for mgemod_duels table
CREATE INDEX idx_mgemod_duels_endtime ON mgemod_duels(endtime DESC);
CREATE INDEX idx_mgemod_duels_winner ON mgemod_duels(winner);
CREATE INDEX idx_mgemod_duels_loser ON mgemod_duels(loser);

-- Indexes for mgemod_duels_2v2 table
CREATE INDEX idx_mgemod_duels_2v2_endtime ON mgemod_duels_2v2(endtime DESC);
CREATE INDEX idx_mgemod_duels_2v2_winner ON mgemod_duels_2v2(winner);
CREATE INDEX idx_mgemod_duels_2v2_winner2 ON mgemod_duels_2v2(winner2);
CREATE INDEX idx_mgemod_duels_2v2_loser ON mgemod_duels_2v2(loser);
CREATE INDEX idx_mgemod_duels_2v2_loser2 ON mgemod_duels_2v2(loser2);

-- Indexes for mgemod_stats table
CREATE INDEX idx_mgemod_stats_rating ON mgemod_stats(rating DESC);

-- Indexes for player_playtime table
CREATE INDEX idx_player_playtime_steamid_server ON player_playtime(steamid, server_id);

*/

require_once 'includes/helpers.php';

// Database configuration for MGE tables
$config = include __DIR__ . '/config/secure_config_statstf2.php';
$dbHost = $config['db']['host'];
$dbUser = $config['db']['user'];
$dbPass = $config['db']['pass'];
$dbName = $config['db']['name'];

$db = new mysqli($dbHost, $dbUser, $dbPass, $dbName);
if ($db->connect_error) {
    die("Connection failed: " . $db->connect_error);
}
$db->set_charset('utf8mb4');

// CSRF protection
if (!isset($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

function validateCSRF($token) {
    return isset($_SESSION['csrf_token']) && hash_equals($_SESSION['csrf_token'], $token);
}

// Function to get player name and avatar from Steam API with caching
function getSteamUserInfo($steamId64, $apiKey) {
    $defaultAvatar = 'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg';

    // Check session cache first (faster than file cache)
    $cacheKey = 'steam_user_' . $steamId64;
    if (isset($_SESSION[$cacheKey]) && $_SESSION[$cacheKey]['expires'] > time()) {
        return $_SESSION[$cacheKey]['data'];
    }

    // Try file cache (persists across sessions)
    $cacheDir = sys_get_temp_dir() . '/steam_cache';
    if (!is_dir($cacheDir)) {
        @mkdir($cacheDir, 0755, true);
    }
    $cacheFile = $cacheDir . '/' . $steamId64 . '.json';

    if (file_exists($cacheFile) && (time() - filemtime($cacheFile)) < 3600) { // 1 hour cache
        $cached = json_decode(file_get_contents($cacheFile), true);
        if ($cached) {
            $_SESSION[$cacheKey] = ['data' => $cached, 'expires' => time() + 300];
            return $cached;
        }
    }

    // Fetch from Steam API
    $url = "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key={$apiKey}&steamids={$steamId64}";
    $context = stream_context_create(['http' => ['timeout' => 3]]); // 3 second timeout
    $response = @file_get_contents($url, false, $context);
    $data = json_decode($response, true);

    $result = [
        'name' => 'Unknown',
        'avatar' => $defaultAvatar
    ];

    if (isset($data['response']['players'][0])) {
        $player = $data['response']['players'][0];
        $result = [
            'name' => $player['personaname'] ?? 'Unknown',
            'avatar' => $player['avatarfull'] ?? $defaultAvatar
        ];
    }

    // Save to cache
    @file_put_contents($cacheFile, json_encode($result));
    $_SESSION[$cacheKey] = ['data' => $result, 'expires' => time() + 300];

    return $result;
}

// MGE-specific functions
function getMGERating($db, $steamId) {
    $stmt = $db->prepare("SELECT rating FROM mgemod_stats WHERE steamid = ?");
    $stmt->bind_param('s', $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();

    return $row ? $row['rating'] : null;
}

function getMGEDuels($db, $steamId, $limit = 10) {
    $stmt = $db->prepare("
        SELECT * FROM (
            SELECT
                '1v1' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels
            WHERE winner = ? OR loser = ?
            UNION ALL
            SELECT
                '2v2' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels_2v2
            WHERE winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?
        ) AS combined
        ORDER BY endtime DESC
        LIMIT ?
    ");

    $stmt->bind_param('ssssssi', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId, $limit);
    $stmt->execute();
    $result = $stmt->get_result();
    $duels = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    return $duels;
}

function getMGEStats($db, $steamId) {
    $stmt = $db->prepare("SELECT wins, losses FROM mgemod_stats WHERE steamid = ?");
    $stmt->bind_param('s', $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();

    $wins = $row['wins'] ?? 0;
    $losses = $row['losses'] ?? 0;
    $winrate = ($wins + $losses) > 0 ? round(($wins / ($wins + $losses)) * 100, 2) : 0;

    return [
        'wins' => $wins,
        'losses' => $losses,
        'winrate' => $winrate
    ];
}

// Function to get top players
function getTopPlayers($db, $limit = 10, $orderBy = 'rating', $orderDir = 'DESC') {
    static $cache = []; // Cache for top players
    $cacheKey = "top_players_{$limit}_{$orderBy}_{$orderDir}";

    if (isset($cache[$cacheKey])) {
        return $cache[$cacheKey];
    }

    // Validate order by field to prevent SQL injection
    $allowedFields = ['rating', 'wins', 'losses', 'winrate'];
    if (!in_array($orderBy, $allowedFields)) {
        $orderBy = 'rating';
    }

    // Validate order direction
    $orderDir = strtoupper($orderDir) === 'ASC' ? 'ASC' : 'DESC';

    $stmt = $db->prepare("
        SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
        FROM mgemod_stats ms
        WHERE ms.rating IS NOT NULL
        ORDER BY ms.{$orderBy} {$orderDir}
        LIMIT ?
    ");
    $stmt->bind_param('i', $limit);
    $stmt->execute();
    $result = $stmt->get_result();
    $players = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $cache[$cacheKey] = $players;
    return $players;
}

// Function to get recent duels with pagination
function getRecentDuels($db, $limit = 10, $offset = 0) {
    // Use a UNION query to get recent duels from both tables ordered by endtime
    // This is more efficient than combining results in PHP

    $sql = "
        (
            SELECT
                '1v1' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels
        )
        UNION ALL
        (
            SELECT
                '2v2' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels_2v2
        )
        ORDER BY endtime DESC
        LIMIT ? OFFSET ?
    ";

    $stmt = $db->prepare($sql);
    if (!$stmt) {
        error_log("Prepare failed for getRecentDuels: " . $db->error);
        return [];
    }

    $stmt->bind_param('ii', $limit, $offset);
    if (!$stmt->execute()) {
        error_log("Execute failed for getRecentDuels: " . $stmt->error);
        $stmt->close();
        return [];
    }

    $result = $stmt->get_result();
    $duels = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    return $duels;
}

// Function to get total duels count for pagination
function getTotalDuelsCount($db) {
    static $cache = []; // Cache for total duels count

    if (isset($cache['total_duels_count'])) {
        return $cache['total_duels_count'];
    }

    // Count duels from both tables in a single query for better performance
    $sql = "
        SELECT
            (SELECT COUNT(*) FROM mgemod_duels) +
            (SELECT COUNT(*) FROM mgemod_duels_2v2) as total_count
    ";

    $result = $db->query($sql);
    if (!$result) {
        error_log("Query failed for getTotalDuelsCount: " . $db->error);
        return 0;
    }

    $row = $result->fetch_assoc();
    $totalCount = $row['total_count'];
    $cache['total_duels_count'] = $totalCount;

    return $totalCount;
}

// Function to get duel details by ID
function getDuelDetails($db, $duelId, $type) {
    $table = $type === '1v1' ? 'mgemod_duels' : 'mgemod_duels_2v2';
    $stmt = $db->prepare("
        SELECT * FROM {$table} WHERE id = ?
    ");

    if (!$stmt) {
        error_log("Prepare failed for getDuelDetails: " . $db->error);
        return null;
    }

    $stmt->bind_param('i', $duelId);
    if (!$stmt->execute()) {
        error_log("Execute failed for getDuelDetails: " . $stmt->error);
        $stmt->close();
        return null;
    }

    $result = $stmt->get_result();
    $duel = $result->fetch_assoc();
    $stmt->close();

    return $duel;
}

// Function to get player nemesis (most duels with)
function getPlayerNemesis($db, $steamId) {
    $stmt = $db->prepare("
        SELECT
            CASE
                WHEN winner = ? THEN loser
                WHEN loser = ? THEN winner
            END as opponent,
            COUNT(*) as duels_count
        FROM mgemod_duels
        WHERE (winner = ? OR loser = ?) AND winner != loser
        GROUP BY opponent
        ORDER BY duels_count DESC
        LIMIT 1
    ");

    if (!$stmt) {
        error_log("Prepare failed for getPlayerNemesis: " . $db->error);
        return null;
    }

    $stmt->bind_param('ssss', $steamId, $steamId, $steamId, $steamId);
    if (!$stmt->execute()) {
        error_log("Execute failed for getPlayerNemesis: " . $stmt->error);
        $stmt->close();
        return null;
    }

    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();

    if ($row) {
        $opponentId = $row['opponent'];
        $opponentNick = getPlayerNickname($db, $opponentId);
        return [
            'steamid' => $opponentId,
            'nick' => $opponentNick,
            'duels_count' => $row['duels_count']
        ];
    }

    return null;
}

// Function to get MGE duels for a specific player with pagination
function getMGEDuelsPaginated($db, $steamId, $limit = 10, $offset = 0) {
    $stmt = $db->prepare("
        SELECT * FROM (
            SELECT
                '1v1' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels
            WHERE winner = ? OR loser = ?
            UNION ALL
            SELECT
                '2v2' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels_2v2
            WHERE winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?
        ) AS combined
        ORDER BY endtime DESC
        LIMIT ? OFFSET ?
    ");

    $stmt->bind_param('sssssiii', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId, $limit, $offset);
    $stmt->execute();
    $result = $stmt->get_result();
    $duels = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    return $duels;
}

// Function to get total count of MGE duels for a specific player
function getMGEDuelsCount($db, $steamId) {
    $stmt = $db->prepare("
        SELECT SUM(duel_count) as total FROM (
            SELECT COUNT(*) as duel_count
            FROM mgemod_duels
            WHERE winner = ? OR loser = ?
            UNION ALL
            SELECT COUNT(*)
            FROM mgemod_duels_2v2
            WHERE winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?
        ) AS counts
    ");

    $stmt->bind_param('ssssss', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();

    return $row ? $row['total'] : 0;
}

// Function to get rating history for the last month
function getRatingHistory($db, $steamId, $days = 30) {
    $endDate = time();
    $startDate = $endDate - ($days * 24 * 60 * 60);

    // Optimized query to get rating history with better performance
    $sql = "
        SELECT
            UNIX_TIMESTAMP(DATE(FROM_UNIXTIME(endtime))) as date_ts,
            CASE
                WHEN winner = ? THEN winner_new_elo
                WHEN loser = ? THEN loser_new_elo
                WHEN winner2 = ? THEN winner_new_elo
                WHEN loser2 = ? THEN loser_new_elo
            END as rating
        FROM (
            SELECT endtime, winner, loser, winner2, loser2, winner_new_elo, loser_new_elo
            FROM mgemod_duels
            WHERE (winner = ? OR loser = ?) AND endtime >= ?
            UNION ALL
            SELECT endtime, winner, loser, winner2, loser2, winner_new_elo, loser_new_elo
            FROM mgemod_duels_2v2
            WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?) AND endtime >= ?
        ) AS combined
        WHERE rating IS NOT NULL
        GROUP BY DATE(FROM_UNIXTIME(endtime))
        ORDER BY date_ts
    ";

    $stmt = $db->prepare($sql);
    if (!$stmt) {
        error_log("Prepare failed for getRatingHistory: " . $db->error);
        return [];
    }

    $stmt->bind_param('ssssiiisssii', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId, $startDate, $steamId, $steamId, $steamId, $steamId, $startDate);
    if (!$stmt->execute()) {
        error_log("Execute failed for getRatingHistory: " . $stmt->error);
        $stmt->close();
        return [];
    }

    $result = $stmt->get_result();
    $history = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    return $history;
}

// Function to get total statistics
function getTotalStats($db) {
    $stats = [];

    // Total duels
    $stmt = $db->prepare("SELECT COUNT(*) as total FROM mgemod_duels");
    if ($stmt) {
        $stmt->execute();
        $result = $stmt->get_result();
        $row = $result->fetch_assoc();
        $stats['total_duels'] = $row['total'] ?? 0;
        $stmt->close();
    } else {
        error_log("Prepare failed for total duels query: " . $db->error);
        $stats['total_duels'] = 0;
    }

    // Total 2v2 duels
    $stmt = $db->prepare("SELECT COUNT(*) as total FROM mgemod_duels_2v2");
    if ($stmt) {
        $stmt->execute();
        $result = $stmt->get_result();
        $row = $result->fetch_assoc();
        $stats['total_duels_2v2'] = $row['total'] ?? 0;
        $stmt->close();
    } else {
        error_log("Prepare failed for total 2v2 duels query: " . $db->error);
        $stats['total_duels_2v2'] = 0;
    }

    // Total players
    $stmt = $db->prepare("SELECT COUNT(*) as total FROM mgemod_stats");
    if ($stmt) {
        $stmt->execute();
        $result = $stmt->get_result();
        $row = $result->fetch_assoc();
        $stats['total_players'] = $row['total'] ?? 0;
        $stmt->close();
    } else {
        error_log("Prepare failed for total players query: " . $db->error);
        $stats['total_players'] = 0;
    }

    // Highest rating
    $stmt = $db->prepare("SELECT MAX(rating) as max_rating FROM mgemod_stats");
    if ($stmt) {
        $stmt->execute();
        $result = $stmt->get_result();
        $row = $result->fetch_assoc();
        $stats['highest_rating'] = $row['max_rating'] ?? 0;
        $stmt->close();
    } else {
        error_log("Prepare failed for highest rating query: " . $db->error);
        $stats['highest_rating'] = 0;
    }

    return $stats;
}

// Handle logout
if (isset($_GET['logout'])) {
    session_destroy();
    $redirectUrl = $_SERVER['PHP_SELF'];
    if (isset($_GET['profile']) || isset($_GET['duel'])) {
        $redirectUrl .= '?';
    }
    header('Location: ' . $redirectUrl);
    exit;
}

// Handle AJAX requests
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');

    if ($_GET['ajax'] === 'get_duels_page') {
        $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
        $limit = 10;
        $offset = ($page - 1) * $limit;

        $duels = getRecentDuels($db, $limit, $offset);
        $totalDuels = getTotalDuelsCount($db);
        $totalPages = ceil($totalDuels / $limit);

        foreach ($duels as &$duel) {
            $winnerNick = getPlayerNickname($db, $duel['winner']);
            $loserNick = getPlayerNickname($db, $duel['loser']);
            $duel['winner_nick'] = $winnerNick;
            $duel['loser_nick'] = $loserNick;

            if (isset($duel['winner2']) && $duel['winner2']) {
                $winner2Nick = getPlayerNickname($db, $duel['winner2']);
                $loser2Nick = getPlayerNickname($db, $duel['loser2']);
                $duel['winner2_nick'] = $winner2Nick;
                $duel['loser2_nick'] = $loser2Nick;
            }
        }

        echo json_encode([
            'duels' => $duels,
            'current_page' => $page,
            'total_pages' => $totalPages,
            'total_duels' => $totalDuels
        ]);
        exit;
    }

    if ($_GET['ajax'] === 'get_duel_details') {
        $duelId = (int)$_GET['duel_id'];
        $type = $_GET['type'];

        $duel = getDuelDetails($db, $duelId, $type);
        if ($duel) {
            $duel['winner_nick'] = getPlayerNickname($db, $duel['winner']);
            $duel['loser_nick'] = getPlayerNickname($db, $duel['loser']);

            if ($type === '2v2') {
                $duel['winner2_nick'] = getPlayerNickname($db, $duel['winner2']);
                $duel['loser2_nick'] = getPlayerNickname($db, $duel['loser2']);
            }
        }

        echo json_encode([
            'duel' => $duel
        ]);
        exit;
    }

    if ($_GET['ajax'] === 'search_players') {
        $query = sanitizeInput($_GET['q'] ?? '');
        $orderBy = $_GET['sort_by'] ?? 'rating';
        $orderDir = $_GET['sort_dir'] ?? 'DESC';

        // Validate sort parameters to prevent SQL injection
        list($orderBy, $orderDir) = validateSortParams($orderBy, $orderDir);

        // Debug: Check if debug mode is enabled
        if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
            echo "<h3>Отладка поиска игрока</h3>";
            echo "<p>Поисковый запрос: " . htmlspecialchars($query) . "</p>";

            // Check if the player exists in the database with exact match
            $checkStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE name = ?");
            $checkStmt->bind_param('s', $query);
            $checkStmt->execute();
            $checkResult = $checkStmt->get_result();
            $exactMatch = $checkResult->fetch_assoc();
            $checkStmt->close();

            if ($exactMatch) {
                echo "<p>Найдено точное совпадение: " . htmlspecialchars($exactMatch['name']) . " (" . htmlspecialchars($exactMatch['steamid']) . ")</p>";
            } else {
                echo "<p>Точное совпадение не найдено</p>";
            }

            // Check for partial match
            $partialSearch = "%{$query}%";
            $checkPartialStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE name LIKE ?");
            $checkPartialStmt->bind_param('s', $partialSearch);
            $checkPartialStmt->execute();
            $checkPartialResult = $checkPartialStmt->get_result();
            $partialMatches = $checkPartialResult->fetch_all(MYSQLI_ASSOC);
            $checkPartialStmt->close();

            if (!empty($partialMatches)) {
                echo "<p>Найдено частичных совпадений: " . count($partialMatches) . "</p>";
                foreach ($partialMatches as $match) {
                    echo "<p>- " . htmlspecialchars($match['name']) . " (" . htmlspecialchars($match['steamid']) . ")</p>";
                }
            } else {
                echo "<p>Частичные совпадения не найдены</p>";
            }

            // Check for case-insensitive match
            $checkCaseStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE LOWER(name) = LOWER(?)");
            $checkCaseStmt->bind_param('s', $query);
            $checkCaseStmt->execute();
            $checkCaseResult = $checkCaseStmt->get_result();
            $caseMatch = $checkCaseResult->fetch_assoc();
            $checkCaseStmt->close();

            if ($caseMatch) {
                echo "<p>Найдено совпадение без учета регистра: " . htmlspecialchars($caseMatch['name']) . " (" . htmlspecialchars($caseMatch['steamid']) . ")</p>";
            } else {
                echo "<p>Совпадение без учета регистра не найдено</p>";
            }
        }

        $stmt = $db->prepare("
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
                   CASE
                       WHEN (ms.wins + ms.losses) > 0 THEN ROUND((ms.wins / (ms.wins + ms.losses)) * 100, 2)
                       ELSE 0
                   END as winrate,
                   CASE
                       WHEN ms.name = ? THEN 1  -- Exact name match
                       WHEN ms.name LIKE ? THEN 2  -- Partial name match
                       WHEN ms.steamid = ? THEN 3  -- Exact SteamID match
                       WHEN ms.steamid LIKE ? THEN 4  -- Partial SteamID match
                       ELSE 5
                   END as relevance_order
            FROM mgemod_stats ms
            WHERE (ms.name IS NOT NULL AND ms.name LIKE ?) OR ms.steamid LIKE ?
            ORDER BY relevance_order ASC, ms.{$orderBy} {$orderDir}
            LIMIT 10
        ");

        if ($stmt) {
            $searchTerm = "%{$query}%";
            $exactSearch = $query;
            $stmt->bind_param('ssssss', $exactSearch, $searchTerm, $exactSearch, $searchTerm, $searchTerm, $searchTerm);
            $stmt->execute();
            $result = $stmt->get_result();
            $players = $result->fetch_all(MYSQLI_ASSOC);
            $stmt->close();

            foreach ($players as &$player) {
                $player['nick'] = $player['name'] ?: $player['steamid'];
            }

            echo json_encode([
                'players' => $players
            ]);
        } else {
            echo json_encode(['players' => []]);
        }
        exit;
    }

    if ($_GET['ajax'] === 'get_players_page') {
        $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
        $orderBy = $_GET['sort_by'] ?? 'rating';
        $orderDir = $_GET['sort_dir'] ?? 'DESC';
        $limit = 25;
        $offset = ($page - 1) * $limit;

        // Validate sort parameters to prevent SQL injection
        list($orderBy, $orderDir) = validateSortParams($orderBy, $orderDir);

        // Get total count for pagination
        $countStmt = $db->prepare("SELECT COUNT(*) as total FROM mgemod_stats ms WHERE ms.rating IS NOT NULL");
        $countStmt->execute();
        $countResult = $countStmt->get_result();
        $totalCount = $countResult->fetch_assoc()['total'];
        $countStmt->close();

        $stmt = $db->prepare("
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY ms.{$orderBy} {$orderDir}
            LIMIT ? OFFSET ?
        ");

        if ($stmt) {
            $stmt->bind_param('ii', $limit, $offset);
            $stmt->execute();
            $result = $stmt->get_result();
            $players = $result->fetch_all(MYSQLI_ASSOC);
            $stmt->close();

            $totalPages = ceil($totalCount / $limit);

            foreach ($players as &$player) {
                $player['nick'] = $player['name'] ?: $player['steamid'];
                $winrate = ($player['wins'] + $player['losses']) > 0 ?
                    round(($player['wins'] / ($player['wins'] + $player['losses'])) * 100, 2) : 0;
                $player['winrate'] = $winrate;
            }

            echo json_encode([
                'players' => $players,
                'current_page' => $page,
                'total_pages' => $totalPages,
                'total_players' => $totalCount
            ]);
        } else {
            echo json_encode(['players' => [], 'current_page' => 1, 'total_pages' => 1, 'total_players' => 0]);
        }
        exit;
    }

    if ($_GET['ajax'] === 'get_profile_duels_page') {
        $steamId = sanitizeInput($_GET['steam_id'] ?? '');
        $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
        $limit = 10;
        $offset = ($page - 1) * $limit;

        $duels = getMGEDuelsPaginated($db, $steamId, $limit, $offset);
        $totalDuels = getMGEDuelsCount($db, $steamId);
        $totalPages = ceil($totalDuels / $limit);

        foreach ($duels as &$duel) {
            $winnerNick = getPlayerNickname($db, $duel['winner']);
            $loserNick = getPlayerNickname($db, $duel['loser']);
            $duel['winner_nick'] = $winnerNick;
            $duel['loser_nick'] = $loserNick;

            if (isset($duel['winner2']) && $duel['winner2']) {
                $winner2Nick = getPlayerNickname($db, $duel['winner2']);
                $loser2Nick = getPlayerNickname($db, $duel['loser2']);
                $duel['winner2_nick'] = $winner2Nick;
                $duel['loser2_nick'] = $loser2Nick;
            }
        }

        // Process duels to determine if the current player is the winner
        $duels = processDuelWinners($duels, $steamId);

        echo json_encode([
            'duels' => $duels,
            'current_page' => $page,
            'total_pages' => $totalPages,
            'total_duels' => $totalDuels
        ]);
        exit;
    }

    if ($_GET['ajax'] === 'get_daily_duels') {
        $steamId = sanitizeInput($_GET['steam_id'] ?? '');
        $date = sanitizeInput($_GET['date'] ?? '');

        // Validate date format
        if (!strtotime($date)) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid date format']);
            exit;
        }

        // Get duels for the specific date
        $stmt = $db->prepare("
            SELECT
                HOUR(FROM_UNIXTIME(endtime)) as hour,
                COUNT(*) as duel_count
            FROM (
                SELECT endtime FROM mgemod_duels WHERE (winner = ? OR loser = ?) AND DATE(FROM_UNIXTIME(endtime)) = ?
                UNION ALL
                SELECT endtime FROM mgemod_duels_2v2 WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?) AND DATE(FROM_UNIXTIME(endtime)) = ?
            ) AS all_duels
            GROUP BY HOUR(FROM_UNIXTIME(endtime))
            ORDER BY hour
        ");

        $stmt->bind_param('ssssssss', $steamId, $steamId, $date, $steamId, $steamId, $steamId, $steamId, $date);
        $stmt->execute();
        $result = $stmt->get_result();
        $hourlyData = $result->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        // Format data for chart (ensure all 24 hours are represented)
        $hourlyCounts = array_fill(0, 24, 0); // Initialize all hours to 0

        foreach ($hourlyData as $data) {
            $hour = (int)$data['hour'];
            $hourlyCounts[$hour] = (int)$data['duel_count'];
        }

        // Create labels and dataset
        $labels = array_map(function($hour) {
            return sprintf('%02d:00', $hour);
        }, range(0, 23));

        $dataset = [
            'label' => 'Количество дуэлей',
            'data' => array_values($hourlyCounts),
            'borderColor' => 'rgb(74, 222, 128)',
            'backgroundColor' => 'rgba(74, 222, 128, 0.1)',
            'tension' => 0.4,
            'fill' => true
        ];

        echo json_encode([
            'labels' => $labels,
            'datasets' => [$dataset]
        ]);
        exit;
    }

    if ($_GET['ajax'] === 'get_activity_heatmap') {
        $steamId = sanitizeInput($_GET['steam_id'] ?? '');
        $year = (int)$_GET['year'];

        if (!$steamId || !$year) {
            http_response_code(400);
            echo json_encode(['error' => 'Missing steam_id or year']);
            exit;
        }

        // Get activity data for the specified year
        $stmt = $db->prepare("
            SELECT
                DATE(FROM_UNIXTIME(endtime)) as duel_date,
                COUNT(*) as duel_count
            FROM (
                SELECT endtime FROM mgemod_duels WHERE (winner = ? OR loser = ?) AND YEAR(FROM_UNIXTIME(endtime)) = ?
                UNION ALL
                SELECT endtime FROM mgemod_duels_2v2 WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?) AND YEAR(FROM_UNIXTIME(endtime)) = ?
            ) AS all_duels
            GROUP BY DATE(FROM_UNIXTIME(endtime))
            ORDER BY duel_date
        ");

        $stmt->bind_param('ssissssi', $steamId, $steamId, $year, $steamId, $steamId, $steamId, $steamId, $year);
        $stmt->execute();
        $result = $stmt->get_result();
        $activity = $result->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        // Get all years with activity
        $stmtYears = $db->prepare("
            SELECT DISTINCT YEAR(FROM_UNIXTIME(endtime)) as year
            FROM (
                SELECT endtime FROM mgemod_duels WHERE (winner = ? OR loser = ?)
                UNION ALL
                SELECT endtime FROM mgemod_duels_2v2 WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?)
            ) AS all_duels
            ORDER BY year DESC
        ");
        $stmtYears->bind_param('ssssss', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId);
        $stmtYears->execute();
        $yearsResult = $stmtYears->get_result();
        $availableYears = [];
        while ($row = $yearsResult->fetch_assoc()) {
            $availableYears[] = $row['year'];
        }
        $stmtYears->close();

        // Format the data
        $activityData = [];
        foreach ($activity as $item) {
            $activityData[$item['duel_date']] = (int)$item['duel_count'];
        }

        // Generate heatmap HTML
        ob_start();

        $selectedYear = $year;

        // GitHub-style heatmap: columns = weeks, rows = days of week
        // Cell size increased by 40% (10px -> 14px)
        $cellSize = 15;
        $cellWidth = 14;

        $start = new DateTime("$selectedYear-01-01");
        $end = new DateTime("$selectedYear-12-31");
        $interval = new DateInterval('P1D');

        // Find the first Sunday on or before Jan 1
        $firstSunday = clone $start;
        while ($firstSunday->format('w') != 0) {
            $firstSunday->sub($interval);
        }

        // Find the last Saturday on or after Dec 31
        $lastSaturday = clone $end;
        while ($lastSaturday->format('w') != 6) {
            $lastSaturday->add($interval);
        }

        // Calculate positions for all days
        $dayPositions = [];
        $tempCurrent = clone $firstSunday;
        $weekNumber = 0;

        while ($tempCurrent <= $lastSaturday) {
            $dateStr = $tempCurrent->format('Y-m-d');
            $dayOfWeek = (int)$tempCurrent->format('w');

            $dayPositions[] = [
                'date' => $dateStr,
                'x' => $weekNumber * $cellSize,
                'y' => $dayOfWeek * $cellSize,
                'month' => $tempCurrent->format('n'),
                'in_year' => $tempCurrent->format('Y') == $selectedYear
            ];

            $tempCurrent->add($interval);

            if ($tempCurrent->format('w') == 0) {
                $weekNumber++;
            }
        }

        $svgWidth = ($weekNumber + 1) * $cellSize + 40;
        $svgHeight = 7 * $cellSize + 25;

        // Month labels
        $months = [];
        $lastMonth = null;
        foreach ($dayPositions as $pos) {
            if (!$pos['in_year']) continue;
            $month = $pos['month'];
            if ($month !== $lastMonth) {
                $months[$month] = [
                    'x' => $pos['x'],
                    'name' => DateTime::createFromFormat('!m', $month)->format('M')
                ];
                $lastMonth = $month;
            }
        }
        ?>
        <div style="display: flex; gap: 16px; align-items: flex-start;">
            <div class="calendar-graph-full-width" style="flex: 1;">
                <svg width="<?= $svgWidth ?>" height="<?= $svgHeight ?>" class="js-calendar-graph-svg">
                    <!-- Month labels -->
                    <g transform="translate(36, 12)" font-size="11" fill="#7d8590">
                        <?php foreach ($months as $monthNum => $monthData): ?>
                            <text x="<?= $monthData['x'] ?>" y="0"><?= $monthData['name'] ?></text>
                        <?php endforeach; ?>
                    </g>

                    <!-- Day of week labels -->
                    <g transform="translate(0, 28)" font-size="10" fill="#7d8590">
                        <text x="0" y="26">Пн</text>
                        <text x="0" y="56">Ср</text>
                        <text x="0" y="86">Пт</text>
                    </g>

                    <!-- Heatmap days -->
                    <g transform="translate(36, 20)">
                        <?php
                        foreach ($dayPositions as $pos) {
                            $dateStr = $pos['date'];
                            $count = isset($activityData[$dateStr]) ? $activityData[$dateStr] : 0;

                            if (!$pos['in_year']) {
                                continue;
                            } elseif ($count == 0) {
                                $color = '#161b22';
                            } elseif ($count <= 2) {
                                $color = '#0e4429';
                            } elseif ($count <= 4) {
                                $color = '#006d32';
                            } elseif ($count <= 7) {
                                $color = '#26a641';
                            } else {
                                $color = '#39d353';
                            }

                            echo '<rect class="day" width="'.$cellWidth.'" height="'.$cellWidth.'" x="'.$pos['x'].'" y="'.$pos['y'].'" fill="'.$color.'" data-count="'.$count.'" data-date="'.$dateStr.'" rx="2" ry="2" onclick="showDailyDuelsChart(\''.$dateStr.'\')"><title>'.$dateStr.': '.$count.' дуэлей</title></rect>';
                        }
                        ?>
                    </g>
                </svg>
            </div>

            <?php if (count($availableYears) > 0): ?>
            <div class="year-selector-vertical">
                <?php foreach ($availableYears as $yr): ?>
                    <button class="year-btn <?= $yr == $selectedYear ? 'active' : '' ?>" onclick="changeYearAjax('<?= $yr ?>')"><?= $yr ?></button>
                <?php endforeach; ?>
            </div>
            <?php endif; ?>
        </div>

        <div style="margin-top: 12px; display: flex; justify-content: flex-start; align-items: center; gap: 4px; font-size: 11px; color: #7d8590;">
            <span>Меньше</span>
            <div style="width: 14px; height: 14px; background: #161b22; border-radius: 2px;"></div>
            <div style="width: 14px; height: 14px; background: #0e4429; border-radius: 2px;"></div>
            <div style="width: 14px; height: 14px; background: #006d32; border-radius: 2px;"></div>
            <div style="width: 14px; height: 14px; background: #26a641; border-radius: 2px;"></div>
            <div style="width: 14px; height: 14px; background: #39d353; border-radius: 2px;"></div>
            <span>Больше</span>
        </div>
        <?php
        $heatmapHtml = ob_get_clean();

        echo json_encode([
            'heatmap_html' => $heatmapHtml,
            'year' => $year,
            'available_years' => $availableYears
        ]);
        exit;
    }
}

// Function to get player matchups (practice duels)
function getPlayerMatchups($db, $steamId) {
    $stmt = $db->prepare("
        SELECT
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
        FROM mgemod_duels
        WHERE (winner = ? OR loser = ?)
        AND mapname = 'Регулировка'
        AND arenaname LIKE 'Матчап%'
        ORDER BY endtime DESC
        LIMIT 10
    ");

    $stmt->bind_param('ss', $steamId, $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $matchups = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    // Get opponent nicknames
    foreach ($matchups as &$matchup) {
        if ($matchup['winner'] === $steamId) {
            $matchup['opponent'] = getPlayerNickname($db, $matchup['loser']);
            $matchup['result'] = 'win';
        } else {
            $matchup['opponent'] = getPlayerNickname($db, $matchup['winner']);
            $matchup['result'] = 'loss';
        }
    }

    return $matchups;
}

// Function to get matchup ratings for heatmap
function getMatchupRatings($db, $steamId) {
    $stmt = $db->prepare("SELECT my_class, opponent_class, rating FROM mgemod_matchup_ratings WHERE steamid = ?");
    if (!$stmt) {
        return [];
    }

    $stmt->bind_param('s', $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $ratings = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    // Initialize all matchups with default rating of 1500
    $classOrder = ['scout', 'soldier', 'pyro', 'demoman', 'heavy', 'engineer', 'medic', 'sniper', 'spy'];
    $matchupRatings = [];

    foreach ($classOrder as $myClass) {
        foreach ($classOrder as $oppClass) {
            $matchupRatings[$myClass][$oppClass] = 1500;
        }
    }

    // Fill in actual ratings from database
    foreach ($ratings as $rating) {
        $myClassId = (int)$rating['my_class'];
        $oppClassId = (int)$rating['opponent_class'];
        $ratingValue = (int)$rating['rating'];

        // Map class IDs to class names
        $classIdMap = [
            1 => 'scout',
            2 => 'sniper',
            3 => 'soldier',
            4 => 'demoman',
            5 => 'medic',
            6 => 'heavy',
            7 => 'pyro',
            8 => 'spy',
            9 => 'engineer'
        ];

        $myClass = $classIdMap[$myClassId] ?? null;
        $oppClass = $classIdMap[$oppClassId] ?? null;

        if ($myClass && $oppClass && $ratingValue > 0) {
            $matchupRatings[$myClass][$oppClass] = $ratingValue;
        }
    }

    return $matchupRatings;
}

// Function to get matchup statistics
function getMatchupStats($db, $steamId) {
    $classOrder = ['scout', 'soldier', 'pyro', 'demoman', 'heavy', 'engineer', 'medic', 'sniper', 'spy'];
    $matchupStats = [];

    // Initialize all matchups with zero stats
    foreach ($classOrder as $myClass) {
        foreach ($classOrder as $oppClass) {
            $matchupStats[$myClass][$oppClass] = [
                'total' => 0,
                'wins' => 0
            ];
        }
    }

    // Parse class string (can contain multiple classes like "scout,pyro,sniper")
    $parseClasses = function($classString) use ($classOrder) {
        if (empty($classString)) return [];
        $classes = array_map('trim', explode(',', $classString));
        $result = [];
        foreach ($classes as $class) {
            $class = strtolower(trim($class));
            if (in_array($class, $classOrder)) {
                $result[] = $class;
            }
        }
        return $result;
    };

    // Get 1v1 duels - parse classes from winnerclass/loserclass fields
    $query1v1 = "SELECT
        id,
        winner,
        loser,
        winnerclass,
        loserclass
        FROM mgemod_duels
        WHERE (winner = ? OR loser = ?)
        AND (winnerclass IS NOT NULL AND winnerclass != '')
        AND (loserclass IS NOT NULL AND loserclass != '')";

    $stmt = $db->prepare($query1v1);
    if ($stmt) {
        $stmt->bind_param('ss', $steamId, $steamId);
        if ($stmt->execute()) {
            $result = $stmt->get_result();
            $processedDuels = [];
            while ($row = $result->fetch_assoc()) {
                $duelId = (int)$row['id'];
                $isWinner = ($row['winner'] === $steamId);

                $myClasses = $isWinner ? $parseClasses($row['winnerclass']) : $parseClasses($row['loserclass']);
                $oppClasses = $isWinner ? $parseClasses($row['loserclass']) : $parseClasses($row['winnerclass']);

                // Count all combinations of my classes vs opponent classes
                foreach ($myClasses as $myClass) {
                    foreach ($oppClasses as $oppClass) {
                        $key = $myClass . '_' . $oppClass;
                        $duelKey = $key . '_' . $duelId;

                        if (!isset($processedDuels[$duelKey])) {
                            $processedDuels[$duelKey] = true;
                            $matchupStats[$myClass][$oppClass]['total'] += 1;
                            if ($isWinner) {
                                $matchupStats[$myClass][$oppClass]['wins'] += 1;
                            }
                        }
                    }
                }
            }
        }
        $stmt->close();
    }

    // Get 2v2 duels - parse classes from all class fields
    $query2v2 = "SELECT
        id,
        winner,
        winner2,
        loser,
        loser2,
        winnerclass,
        winner2class,
        loserclass,
        loser2class
        FROM mgemod_duels_2v2
        WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?)
        AND ((winnerclass IS NOT NULL AND winnerclass != '') OR (winner2class IS NOT NULL AND winner2class != ''))
        AND ((loserclass IS NOT NULL AND loserclass != '') OR (loser2class IS NOT NULL AND loser2class != ''))";

    $stmt = $db->prepare($query2v2);
    if ($stmt) {
        $stmt->bind_param('ssss', $steamId, $steamId, $steamId, $steamId);
        if ($stmt->execute()) {
            $result = $stmt->get_result();
            $processedDuels = [];
            while ($row = $result->fetch_assoc()) {
                $duelId = (int)$row['id'];
                $isWinner = ($row['winner'] === $steamId || $row['winner2'] === $steamId);

                // Get all my classes (from winner or loser side)
                $myClasses = [];
                if ($row['winner'] === $steamId && !empty($row['winnerclass'])) {
                    $myClasses = array_merge($myClasses, $parseClasses($row['winnerclass']));
                }
                if ($row['winner2'] === $steamId && !empty($row['winner2class'])) {
                    $myClasses = array_merge($myClasses, $parseClasses($row['winner2class']));
                }
                if ($row['loser'] === $steamId && !empty($row['loserclass'])) {
                    $myClasses = array_merge($myClasses, $parseClasses($row['loserclass']));
                }
                if ($row['loser2'] === $steamId && !empty($row['loser2class'])) {
                    $myClasses = array_merge($myClasses, $parseClasses($row['loser2class']));
                }

                // Get all opponent classes
                $oppClasses = [];
                if ($row['winner'] !== $steamId && $row['winner2'] !== $steamId) {
                    if (!empty($row['winnerclass'])) {
                        $oppClasses = array_merge($oppClasses, $parseClasses($row['winnerclass']));
                    }
                    if (!empty($row['winner2class'])) {
                        $oppClasses = array_merge($oppClasses, $parseClasses($row['winner2class']));
                    }
                }
                if ($row['loser'] !== $steamId && $row['loser2'] !== $steamId) {
                    if (!empty($row['loserclass'])) {
                        $oppClasses = array_merge($oppClasses, $parseClasses($row['loserclass']));
                    }
                    if (!empty($row['loser2class'])) {
                        $oppClasses = array_merge($oppClasses, $parseClasses($row['loser2class']));
                    }
                }

                // Count all combinations
                foreach ($myClasses as $myClass) {
                    foreach ($oppClasses as $oppClass) {
                        $key = $myClass . '_' . $oppClass;
                        $duelKey = $key . '_' . $duelId;

                        if (!isset($processedDuels[$duelKey])) {
                            $processedDuels[$duelKey] = true;
                            $matchupStats[$myClass][$oppClass]['total'] += 1;
                            if ($isWinner) {
                                $matchupStats[$myClass][$oppClass]['wins'] += 1;
                            }
                        }
                    }
                }
            }
        }
        $stmt->close();
    }

    return $matchupStats;
}

// Function to get rating color based on value
function getRatingColor($rating) {
    if ($rating > 2000) return '#4caf50'; // Very high - green
    if ($rating > 1700) return '#8bc34a'; // High - light green
    if ($rating == 1500) return '#cddc39'; // Default rating - yellow-green
    if ($rating > 1300) return '#9ccc65'; // Medium - light green
    if ($rating > 1000) return '#ff9800'; // Low - orange
    return '#f44336'; // Very low - red
}

// Function to get class display name
function getClassDisplayName($className) {
    $names = [
        'scout' => 'Скаут',
        'soldier' => 'Солдат',
        'pyro' => 'Пироман',
        'demoman' => 'Демомен',
        'heavy' => 'Пулемётчик',
        'engineer' => 'Инженер',
        'medic' => 'Медик',
        'sniper' => 'Снайпер',
        'spy' => 'Шпион'
    ];
    return $names[strtolower($className)] ?? ucfirst($className);
}

// Function to get class icon path
function getClassIconPath($className) {
    $iconMap = [
        'scout' => 'Scout_emblem_RED_beta.png',
        'soldier' => 'Soldier_emblem_RED.png',
        'pyro' => 'Pyro_emblem_RED.png',
        'demoman' => 'Demoman_emblem_RED.png',
        'heavy' => '145px-Heavy_emblem_RED.png',
        'engineer' => 'Engineer_emblem_RED.png',
        'medic' => 'Medic_emblem_RED.png',
        'sniper' => 'Sniper_emblem_RED.png',
        'spy' => 'Spy_emblem_RED.png'
    ];
    return $iconMap[strtolower($className)] ?? '';
}


// Function to get player activity data for heatmap
function getPlayerActivity($db, $steamId) {
    // Get ALL activity data from duels (no date limit)
    $stmt = $db->prepare("
        SELECT
            DATE(FROM_UNIXTIME(endtime)) as duel_date,
            COUNT(*) as duel_count
        FROM (
            SELECT endtime FROM mgemod_duels WHERE (winner = ? OR loser = ?)
            UNION ALL
            SELECT endtime FROM mgemod_duels_2v2 WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?)
        ) AS all_duels
        GROUP BY DATE(FROM_UNIXTIME(endtime))
        ORDER BY duel_date
    ");

    $stmt->bind_param('ssssss', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $activity = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    // Format the data for the heatmap
    $heatmapData = [];
    foreach ($activity as $item) {
        $heatmapData[] = [
            'date' => $item['duel_date'],
            'count' => (int)$item['duel_count']
        ];
    }

    return $heatmapData;
}

// Handle duel view
$viewDuel = isset($_GET['duel']) ? (int)$_GET['duel'] : null;
$duelType = isset($_GET['type']) ? $_GET['type'] : '1v1';

// Get sorting parameters
$orderBy = $_GET['sort_by'] ?? 'rating';
$orderDir = $_GET['sort_dir'] ?? 'DESC';

// Validate sort parameters to prevent SQL injection
list($orderBy, $orderDir) = validateSortParams($orderBy, $orderDir);

// Handle profile view
$viewProfile = isset($_GET['profile']) ? $_GET['profile'] : null;

// Handle search
$searchQuery = isset($_GET['search']) ? sanitizeInput(trim($_GET['search'])) : '';
$searchResults = [];

if ($searchQuery) {
    // Debug: Check if debug mode is enabled
    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
        echo "<h3>Отладка обычного поиска игрока</h3>";
        echo "<p>Поисковый запрос: " . htmlspecialchars($searchQuery) . "</p>";

        // Check if the player exists in the database with exact match
        $checkStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE name = ?");
        $checkStmt->bind_param('s', $searchQuery);
        $checkStmt->execute();
        $checkResult = $checkStmt->get_result();
        $exactMatch = $checkResult->fetch_assoc();
        $checkStmt->close();

        if ($exactMatch) {
            echo "<p>Найдено точное совпадение: " . htmlspecialchars($exactMatch['name']) . " (" . htmlspecialchars($exactMatch['steamid']) . ")</p>";
        } else {
            echo "<p>Точное совпадение не найдено</p>";
        }

        // Check for partial match
        $partialSearch = "%{$searchQuery}%";
        $checkPartialStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE name LIKE ?");
        $checkPartialStmt->bind_param('s', $partialSearch);
        $checkPartialStmt->execute();
        $checkPartialResult = $checkPartialStmt->get_result();
        $partialMatches = $checkPartialResult->fetch_all(MYSQLI_ASSOC);
        $checkPartialStmt->close();

        if (!empty($partialMatches)) {
            echo "<p>Найдено частичных совпадений: " . count($partialMatches) . "</p>";
            foreach ($partialMatches as $match) {
                echo "<p>- " . htmlspecialchars($match['name']) . " (" . htmlspecialchars($match['steamid']) . ")</p>";
            }
        } else {
            echo "<p>Частичные совпадения не найдены</p>";
        }

        // Check for case-insensitive match
        $checkCaseStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE LOWER(name) = LOWER(?)");
        $checkCaseStmt->bind_param('s', $searchQuery);
        $checkCaseStmt->execute();
        $checkCaseResult = $checkCaseStmt->get_result();
        $caseMatch = $checkCaseResult->fetch_assoc();
        $checkCaseStmt->close();

        if ($caseMatch) {
            echo "<p>Найдено совпадение без учета регистра: " . htmlspecialchars($caseMatch['name']) . " (" . htmlspecialchars($caseMatch['steamid']) . ")</p>";
        } else {
            echo "<p>Совпадение без учета регистра не найдено</p>";
        }
    }

    // Debug: Show the actual search query being executed
    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
        echo "<!-- Executing main search query for: $searchQuery -->";
    }

    $stmt = $db->prepare("
        SELECT DISTINCT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
               CASE
                   WHEN (ms.wins + ms.losses) > 0 THEN ROUND((ms.wins / (ms.wins + ms.losses)) * 100, 2)
                   ELSE 0
               END as winrate,
               CASE
                   WHEN ms.name = ? THEN 1  -- Exact name match
                   WHEN ms.name LIKE ? THEN 2  -- Partial name match
                   WHEN ms.steamid = ? THEN 3  -- Exact SteamID match
                   WHEN ms.steamid LIKE ? THEN 4  -- Partial SteamID match
                   ELSE 5
               END as relevance_order
        FROM mgemod_stats ms
        WHERE (ms.name IS NOT NULL AND ms.name LIKE ?) OR ms.steamid LIKE ?
        ORDER BY relevance_order ASC, ms.{$orderBy} {$orderDir}
        LIMIT 50
    ");

    if ($stmt) {
        $searchTerm = "%{$searchQuery}%";
        $exactSearch = $searchQuery;
        $stmt->bind_param('ssssss', $exactSearch, $searchTerm, $exactSearch, $searchTerm, $searchTerm, $searchTerm);
        $stmt->execute();
        $result = $stmt->get_result();
        $searchResults = $result->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        // Update nick field for search results
        foreach ($searchResults as &$player) {
            $player['nick'] = $player['name'] ?: $player['steamid'];
            $winrate = ($player['wins'] + $player['losses']) > 0 ?
                round(($player['wins'] / ($player['wins'] + $player['losses'])) * 100, 2) : 0;
            $player['winrate'] = $winrate;
        }

        // Debug: Show results after processing
        if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
            echo "<!-- Main query results count: " . count($searchResults) . " -->";
            foreach ($searchResults as $idx => $player) {
                echo "<!-- Main result $idx: " . $player['name'] . " (" . $player['steamid'] . ") -->";
            }
        }

        // If no results found in main tables, search in duel tables
        if (empty($searchResults)) {
            // Search for players who participated in duels but may not be in mgemod_stats
            $duelSearchStmt = $db->prepare("
                SELECT DISTINCT
                    CASE
                        WHEN winner LIKE ? THEN winner
                        WHEN loser LIKE ? THEN loser
                        WHEN winner2 LIKE ? AND winner2 IS NOT NULL THEN winner2
                        WHEN loser2 LIKE ? AND loser2 IS NOT NULL THEN loser2
                    END as steamid
                FROM (
                    SELECT winner, loser, NULL as winner2, NULL as loser2 FROM mgemod_duels
                    UNION ALL
                    SELECT winner, loser, winner2, loser2 FROM mgemod_duels_2v2
                ) all_duels
                WHERE winner LIKE ? OR loser LIKE ? OR (winner2 LIKE ? AND winner2 IS NOT NULL) OR (loser2 LIKE ? AND loser2 IS NOT NULL)
                LIMIT 50
            ");

            if ($duelSearchStmt) {
                $duelSearchTerm = "%{$searchQuery}%";
                $duelSearchStmt->bind_param('ssssssss', $duelSearchTerm, $duelSearchTerm, $duelSearchTerm, $duelSearchTerm, $duelSearchTerm, $duelSearchTerm, $duelSearchTerm, $duelSearchTerm);
                $duelSearchStmt->execute();
                $duelResult = $duelSearchStmt->get_result();

                $duelSteamIds = [];
                while ($row = $duelResult->fetch_assoc()) {
                    if (!empty($row['steamid'])) {
                        $duelSteamIds[] = $row['steamid'];
                    }
                }
                $duelSearchStmt->close();

                // Now get full player info for these SteamIDs
                if (!empty($duelSteamIds)) {
                    $placeholders = str_repeat('?,', count($duelSteamIds) - 1) . '?';
                    $duelInfoStmt = $db->prepare("
                        SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
                        FROM mgemod_stats ms
                        WHERE ms.steamid IN ($placeholders)
                    ");

                    if ($duelInfoStmt) {
                        $types = str_repeat('s', count($duelSteamIds));
                        $duelInfoStmt->bind_param($types, ...$duelSteamIds);
                        $duelInfoStmt->execute();
                        $duelInfoResult = $duelInfoStmt->get_result();
                        $searchResults = $duelInfoResult->fetch_all(MYSQLI_ASSOC);
                        $duelInfoStmt->close();

                        // Update nick field for search results from duels
                        foreach ($searchResults as &$player) {
                            $player['nick'] = $player['name'] ?: $player['steamid'];
                            $winrate = ($player['wins'] + $player['losses']) > 0 ?
                                round(($player['wins'] / ($player['wins'] + $player['losses'])) * 100, 2) : 0;
                            $player['winrate'] = $winrate;
                        }

                        // Debug: Show results from duels after processing
                        if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
                            echo "<!-- Duel query results count: " . count($searchResults) . " -->";
                            foreach ($searchResults as $idx => $player) {
                                echo "<!-- Duel result $idx: " . $player['name'] . " (" . $player['steamid'] . ") -->";
                            }
                        }
                    }
                }
            }
        }
    }
}

// Debug: Check search results
if ($searchQuery && isset($_GET['debug']) && $_GET['debug'] === 'true') {
    echo "<!-- Search query: $searchQuery -->";
    echo "<!-- Search results count: " . count($searchResults) . " -->";
    if (!empty($searchResults)) {
        foreach ($searchResults as $idx => $player) {
            echo "<!-- Player $idx: " . $player['name'] . " (" . $player['steamid'] . ") -->";
        }
    }
}

// Get player data if authenticated
$playerData = null;
$steamUserInfo = null;
if ($isAuthenticated) {
    // Get SteamID64 from session
    $steamId64 = $_SESSION['steamid64'] ?? null;

    if ($steamId64) {
        // Get API key from config
        $apiKey = $config['steam_api_key'] ?? '';
        if ($apiKey) {
            $steamUserInfo = getSteamUserInfo($steamId64, $apiKey);
        }
    }

    $rating = getMGERating($db, $steamId);
    $stats = getMGEStats($db, $steamId);
    $duels = getMGEDuels($db, $steamId);

    $playerData = [
        'steamid' => $steamId,
        'steamid64' => $steamId64,
        'name' => $steamUserInfo['name'] ?? 'Unknown',
        'rating' => $rating,
        'stats' => $stats,
        'duels' => $duels
    ];
}

// Pagination for players
$page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
$limit = 25; // Using 25 players per page
$offset = ($page - 1) * $limit;

// Get top players with pagination
$stmt = $db->prepare("
    SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
    FROM mgemod_stats ms
    WHERE ms.rating IS NOT NULL
    ORDER BY ms.{$orderBy} {$orderDir}
    LIMIT ? OFFSET ?
");

if ($stmt) {
    $stmt->bind_param('ii', $limit, $offset);
    $stmt->execute();
    $result = $stmt->get_result();
    $topPlayers = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    foreach ($topPlayers as &$player) {
        $player['nick'] = $player['name'] ?: $player['steamid'];
        $winrate = ($player['wins'] + $player['losses']) > 0 ?
            round(($player['wins'] / ($player['wins'] + $player['losses'])) * 100, 2) : 0;
        $player['winrate'] = $winrate;
    }
} else {
    $topPlayers = [];
}

// Get total count for players pagination
$countStmt = $db->prepare("SELECT COUNT(*) as total FROM mgemod_stats ms WHERE ms.rating IS NOT NULL");
$countStmt->execute();
$countResult = $countStmt->get_result();
$totalPlayers = $countResult->fetch_assoc()['total'];
$countStmt->close();
$totalPagesPlayers = ceil($totalPlayers / $limit);

$totalStats = getTotalStats($db);

// Pagination for recent duels
$duelLimit = 10;
$duelOffset = ($page - 1) * $duelLimit;
$recentDuels = getRecentDuels($db, $duelLimit, $duelOffset);
$totalDuels = getTotalDuelsCount($db);
$totalPages = ceil($totalDuels / $duelLimit);

// Get profile data if viewing a specific profile
$profileData = null;
$profileUserInfo = null;
if ($viewProfile) {
    $profileRating = getMGERating($db, $viewProfile);
    $profileStats = getMGEStats($db, $viewProfile);

    // Get profile duels with pagination
    $profileDuelsPage = isset($_GET['duels_page']) ? max(1, (int)$_GET['duels_page']) : 1;
    $profileDuelsLimit = 10;
    $profileDuelsOffset = ($profileDuelsPage - 1) * $profileDuelsLimit;

    $profileDuels = getMGEDuelsPaginated($db, $viewProfile, $profileDuelsLimit, $profileDuelsOffset);
    $profileDuelsCount = getMGEDuelsCount($db, $viewProfile);
    $profileDuelsTotalPages = ceil($profileDuelsCount / $profileDuelsLimit);

    $profileNemesis = getPlayerNemesis($db, $viewProfile);
    $profileRatingHistory = getRatingHistory($db, $viewProfile);

    // Get player nickname
    $profileNickname = getPlayerNickname($db, $viewProfile);

    // Try to get SteamID64 from the profile
    if (preg_match('/STEAM_0:(\d+):(\d+)/', $viewProfile, $matches)) {
        $y = $matches[1];
        $z = $matches[2];
        $profileSteamId64 = bcadd(bcmul($z, '2'), bcadd('76561197960265728', $y));

        $apiKey = $config['steam_api_key'] ?? '';
        if ($apiKey) {
            $profileUserInfo = getSteamUserInfo($profileSteamId64, $apiKey);
        }
    }

    $profileData = [
        'steamid' => $viewProfile,
        'name' => $profileNickname,
        'rating' => $profileRating,
        'stats' => $profileStats,
        'duels' => $profileDuels,
        'duels_count' => $profileDuelsCount,
        'duels_total_pages' => $profileDuelsTotalPages,
        'duels_current_page' => $profileDuelsPage,
        'nemesis' => $profileNemesis,
        'rating_history' => $profileRatingHistory,
        'matchups' => getPlayerMatchups($db, $viewProfile),
        'activity' => getPlayerActivity($db, $viewProfile),
        'matchup_ratings' => getMatchupRatings($db, $viewProfile),
        'matchup_stats' => getMatchupStats($db, $viewProfile)
    ];
}

// Get duel data if viewing a specific duel
$duelData = null;
if ($viewDuel) {
    $duelData = getDuelDetails($db, $viewDuel, $duelType);
    if ($duelData) {
        $duelData['winner_nick'] = getPlayerNickname($db, $duelData['winner']);
        $duelData['loser_nick'] = getPlayerNickname($db, $duelData['loser']);

        if ($duelType === '2v2') {
            $duelData['winner2_nick'] = getPlayerNickname($db, $duelData['winner2']);
            $duelData['loser2_nick'] = getPlayerNickname($db, $duelData['loser2']);
        }
    }
}
?>

<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php
        if ($viewDuel) echo "Дуэль #{$viewDuel} - MGE Статистика";
        elseif ($viewProfile) echo "Профиль {$profileData['name']} - MGE Статистика";
        else echo "MGE Статистика - 2026";
    ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="css/styles.css">
    <link rel="stylesheet" href="css/profile.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="js/profile.js" defer></script>
</head>
<body>
    <div class="loading-overlay" id="loadingOverlay">
        <div class="loading-content">
            <div class="loading-spinner"></div>
            <p>Загрузка данных...</p>
        </div>
    </div>

    <div class="container">
        <div class="header">
            <h1><i class="fas fa-chart-line"></i> MGE Статистика</h1>
            <p>Дуэльная статистика для MGE серверов</p>

            <div class="auth-section">
                <?php if ($isAuthenticated): ?>
                    <span class="player-name">Добро пожаловать, <?= htmlspecialchars($playerData['name'] ?? 'Игрок') ?></span>
                    <a href="?logout=1" class="btn btn-secondary">
                        <i class="fas fa-sign-out-alt"></i> Выйти
                    </a>
                    <?php if (!$viewProfile && !$viewDuel): ?>
                        <a href="?profile=<?= urlencode($playerData['steamid']) ?>" class="btn btn-outline">
                            <i class="fas fa-user"></i> Мой профиль
                        </a>
                    <?php endif; ?>
                <?php else: ?>
                    <a href="<?= getSteamLoginUrl() ?>" class="btn btn-primary">
                        <i class="fab fa-steam"></i> Войти через Steam
                    </a>
                <?php endif; ?>

                <?php if ($viewProfile || $viewDuel): ?>
                    <a href="<?= $_SERVER['PHP_SELF'] ?>" class="btn btn-outline">
                        <i class="fas fa-arrow-left"></i> Назад к общей статистике
                    </a>
                <?php endif; ?>
            </div>
        </div>

        <?php if ($viewDuel && $duelData): ?>
            <?php
            // Helper function to convert Steam ID to 64-bit
            function steamIdTo64($steamId) {
                if (preg_match('/STEAM_0:(\d+):(\d+)/', $steamId, $matches)) {
                    $y = $matches[1];
                    $z = $matches[2];
                    return bcadd(bcmul($z, '2'), bcadd('76561197960265728', $y));
                }
                return null;
            }

            // Get avatars for players
            $apiKey = $config['steam_api_key'] ?? '';
            $defaultAvatar = 'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg';

            $winnerAvatar = $defaultAvatar;
            $loserAvatar = $defaultAvatar;
            $winner2Avatar = $defaultAvatar;
            $loser2Avatar = $defaultAvatar;

            if ($apiKey) {
                $winnerId64 = steamIdTo64($duelData['winner']);
                $loserId64 = steamIdTo64($duelData['loser']);

                if ($winnerId64) {
                    $winnerInfo = getSteamUserInfo($winnerId64, $apiKey);
                    $winnerAvatar = $winnerInfo['avatar'];
                }
                if ($loserId64) {
                    $loserInfo = getSteamUserInfo($loserId64, $apiKey);
                    $loserAvatar = $loserInfo['avatar'];
                }

                if ($duelType === '2v2') {
                    $winner2Id64 = steamIdTo64($duelData['winner2']);
                    $loser2Id64 = steamIdTo64($duelData['loser2']);
                    if ($winner2Id64) {
                        $winner2Info = getSteamUserInfo($winner2Id64, $apiKey);
                        $winner2Avatar = $winner2Info['avatar'];
                    }
                    if ($loser2Id64) {
                        $loser2Info = getSteamUserInfo($loser2Id64, $apiKey);
                        $loser2Avatar = $loser2Info['avatar'];
                    }
                }
            }

            // Get nicknames
            $winnerNick = getPlayerNickname($db, $duelData['winner']) ?: $duelData['winner'];
            $loserNick = getPlayerNickname($db, $duelData['loser']) ?: $duelData['loser'];
            $winner2Nick = $duelType === '2v2' ? (getPlayerNickname($db, $duelData['winner2']) ?: $duelData['winner2']) : '';
            $loser2Nick = $duelType === '2v2' ? (getPlayerNickname($db, $duelData['loser2']) ?: $duelData['loser2']) : '';

            // Back URL - return to profile if came from there
            $backUrl = isset($_GET['profile']) ? '?profile=' . urlencode($_GET['profile']) : $_SERVER['PHP_SELF'];
            $backText = isset($_GET['profile']) ? 'Назад к профилю' : 'Назад к общей статистике';

            // ELO changes
            $winnerEloDiff = ($duelData['winner_new_elo'] ?? 0) - ($duelData['winner_previous_elo'] ?? 0);
            $loserEloDiff = ($duelData['loser_new_elo'] ?? 0) - ($duelData['loser_previous_elo'] ?? 0);
            ?>
            <!-- Duel Page -->
            <div class="profile-back">
                <a href="<?= $backUrl ?>" class="btn btn-outline">
                    <i class="fas fa-arrow-left"></i> <?= $backText ?>
                </a>
            </div>

            <div class="card">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-fist-raised"></i> Дуэль #<?= $viewDuel ?></h2>
                    <span style="color: #7d8590; font-size: 14px;"><?= date('d.m.Y H:i', $duelData['endtime']) ?> • <?= htmlspecialchars($duelData['mapname']) ?> • <?= htmlspecialchars($duelData['arenaname']) ?></span>
                </div>

                <div class="duel-page-content">
                    <!-- Main Duel Display -->
                    <div class="duel-versus-container">
                        <!-- Winner Side -->
                        <div class="duel-player-card winner">
                            <div class="duel-player-status">ПОБЕДА</div>
                            <a href="?profile=<?= urlencode($duelData['winner']) ?>" class="duel-player-avatar">
                                <img src="<?= $winnerAvatar ?>" alt="Winner Avatar">
                            </a>
                            <a href="?profile=<?= urlencode($duelData['winner']) ?>" class="duel-player-name"><?= htmlspecialchars($winnerNick) ?></a>
                            <div class="duel-player-class"><?= htmlspecialchars($duelData['winnerclass'] ?? 'Unknown') ?></div>
                            <div class="duel-player-elo">
                                <span class="elo-value"><?= $duelData['winner_new_elo'] ?? 'N/A' ?></span>
                                <span class="elo-change positive">+<?= $winnerEloDiff ?></span>
                            </div>
                            <?php if ($duelType === '2v2'): ?>
                            <div class="duel-teammate">
                                <a href="?profile=<?= urlencode($duelData['winner2']) ?>" class="teammate-avatar">
                                    <img src="<?= $winner2Avatar ?>" alt="Winner 2 Avatar">
                                </a>
                                <div class="teammate-info">
                                    <a href="?profile=<?= urlencode($duelData['winner2']) ?>" class="teammate-name"><?= htmlspecialchars($winner2Nick) ?></a>
                                    <span class="teammate-class"><?= htmlspecialchars($duelData['winner2class'] ?? 'Unknown') ?></span>
                                </div>
                            </div>
                            <?php endif; ?>
                        </div>

                        <!-- Score -->
                        <div class="duel-score-display">
                            <div class="duel-score-value">
                                <span class="score-winner"><?= $duelData['winnerscore'] ?></span>
                                <span class="score-separator">:</span>
                                <span class="score-loser"><?= $duelData['loserscore'] ?></span>
                            </div>
                            <div class="duel-type-badge"><?= strtoupper($duelType) ?></div>
                        </div>

                        <!-- Loser Side -->
                        <div class="duel-player-card loser">
                            <div class="duel-player-status">ПОРАЖЕНИЕ</div>
                            <a href="?profile=<?= urlencode($duelData['loser']) ?>" class="duel-player-avatar">
                                <img src="<?= $loserAvatar ?>" alt="Loser Avatar">
                            </a>
                            <a href="?profile=<?= urlencode($duelData['loser']) ?>" class="duel-player-name"><?= htmlspecialchars($loserNick) ?></a>
                            <div class="duel-player-class"><?= htmlspecialchars($duelData['loserclass'] ?? 'Unknown') ?></div>
                            <div class="duel-player-elo">
                                <span class="elo-value"><?= $duelData['loser_new_elo'] ?? 'N/A' ?></span>
                                <span class="elo-change negative"><?= $loserEloDiff ?></span>
                            </div>
                            <?php if ($duelType === '2v2'): ?>
                            <div class="duel-teammate">
                                <a href="?profile=<?= urlencode($duelData['loser2']) ?>" class="teammate-avatar">
                                    <img src="<?= $loser2Avatar ?>" alt="Loser 2 Avatar">
                                </a>
                                <div class="teammate-info">
                                    <a href="?profile=<?= urlencode($duelData['loser2']) ?>" class="teammate-name"><?= htmlspecialchars($loser2Nick) ?></a>
                                    <span class="teammate-class"><?= htmlspecialchars($duelData['loser2class'] ?? 'Unknown') ?></span>
                                </div>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>

        <?php elseif ($viewProfile && $profileData): ?>
            <!-- Profile View -->
            <div class="profile-back">
                <a href="<?= $_SERVER['PHP_SELF'] ?>" class="btn btn-outline">
                    <i class="fas fa-arrow-left"></i> Назад к общей статистике
                </a>
            </div>

            <div class="profile-header" data-player-steamid="<?= $viewProfile ?? '' ?>">
                <div class="profile-avatar">
                    <img src="<?= $profileUserInfo['avatar'] ?? 'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/avatars/fe/fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb_full.jpg' ?>" alt="Steam Avatar">
                </div>

                <div class="profile-basic-info">
                    <h2><?= htmlspecialchars($profileData['name']) ?></h2>
                    <p class="steam-id"><?= $profileData['steamid'] ?></p>

                    <div class="profile-stats-grid" style="margin-top: 15px; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));">
                        <div class="profile-stat-card">
                            <div class="profile-stat-value" style="color: var(--accent);"><?= $profileData['rating'] !== null ? $profileData['rating'] : 'N/A' ?></div>
                            <div class="profile-stat-label">Рейтинг</div>
                        </div>

                        <div class="profile-stat-card">
                            <div class="profile-stat-value" style="color: var(--success);"><?= $profileData['stats']['wins'] ?></div>
                            <div class="profile-stat-label">Победы</div>
                        </div>

                        <div class="profile-stat-card">
                            <div class="profile-stat-value" style="color: var(--danger);"><?= $profileData['stats']['losses'] ?></div>
                            <div class="profile-stat-label">Поражения</div>
                        </div>

                        <div class="profile-stat-card">
                            <div class="profile-stat-value" style="color: var(--warning);"><?= $profileData['stats']['winrate'] ?>%</div>
                            <div class="profile-stat-label">Винрейт</div>
                        </div>
                    </div>
                </div>
            </div>

            <?php if ($profileData['nemesis']): ?>
                <div class="nemesis-info">
                    <h3><i class="fas fa-skull-crossbones"></i> Заклятый враг</h3>
                    <p>
                        <a href="?profile=<?= urlencode($profileData['nemesis']['steamid']) ?>" style="color: var(--danger); text-decoration: none;">
                            <?= htmlspecialchars($profileData['nemesis']['nick']) ?> (<?= $profileData['nemesis']['steamid'] ?>)
                        </a>
                        - <?= $profileData['nemesis']['duels_count'] ?> встреч
                    </p>
                </div>
            <?php endif; ?>

            <?php if (!empty($profileData['rating_history'])): ?>
                <div class="rating-chart-container">
                    <h3><i class="fas fa-chart-line"></i> Изменение рейтинга за месяц</h3>
                    <div class="chart-wrapper">
                        <canvas id="ratingChart"></canvas>
                    </div>
                </div>
            <?php endif; ?>

            <div class="card">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-fist-raised"></i> Последние дуэли</h2>
                </div>

                <?php if (!empty($profileData['duels'])): ?>
                    <div style="overflow-x: auto;">
                        <table class="duels-table" id="profile-duels-table">
                            <thead>
                                <tr>
                                    <th>ID</th>
                                    <th>Тип</th>
                                    <th>Дата</th>
                                    <th>Результат</th>
                                    <th>Карта</th>
                                    <th>Арена</th>
                                    <th>Счет</th>
                                    <th>Изменение ELO</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($profileData['duels'] as $duel):
                                    $isWinner = ($duel['winner'] === $profileData['steamid']);
                                    $eloChange = $isWinner ?
                                        ($duel['winner_new_elo'] - $duel['winner_previous_elo']) :
                                        ($duel['loser_new_elo'] - $duel['loser_previous_elo']);
                                ?>
                                    <tr>
                                        <td>
                                            <a href="?duel=<?= $duel['id'] ?>&type=<?= $duel['type'] ?>&profile=<?= urlencode($viewProfile) ?>" class="duel-id-link">
                                                <?= $duel['id'] ?>
                                            </a>
                                        </td>
                                        <td><?= $duel['type'] ?></td>
                                        <td><?= date('d.m.Y H:i', $duel['endtime']) ?></td>
                                        <td>
                                            <span class="duel-result <?= $isWinner ? 'win' : 'loss' ?>">
                                                <?= $isWinner ? 'ПОБЕДА' : 'ПОРАЖЕНИЕ' ?>
                                            </span>
                                        </td>
                                        <td><?= htmlspecialchars($duel['mapname']) ?></td>
                                        <td><?= htmlspecialchars($duel['arenaname']) ?></td>
                                        <td><?= $duel['winnerscore'] ?>:<?= $duel['loserscore'] ?></td>
                                        <td class="elo-change <?= $eloChange >= 0 ? 'positive' : 'negative' ?>">
                                            <?= $eloChange >= 0 ? '+' : '' ?><?= $eloChange ?>
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>

                    <!-- Pagination for profile duels -->
                    <?php if ($profileData['duels_total_pages'] > 1): ?>
                        <div class="pagination profile-duels-pagination">
                            <?php if ($profileData['duels_current_page'] > 1): ?>
                                <a href="?profile=<?= urlencode($viewProfile) ?>&duels_page=<?= $profileData['duels_current_page'] - 1 ?>"><i class="fas fa-chevron-left"></i> Назад</a>
                            <?php endif; ?>

                            <?php for ($i = max(1, $profileData['duels_current_page'] - 2); $i <= min($profileData['duels_total_pages'], $profileData['duels_current_page'] + 2); $i++): ?>
                                <?php if ($i == $profileData['duels_current_page']): ?>
                                    <span class="current"><?= $i ?></span>
                                <?php else: ?>
                                    <a href="?profile=<?= urlencode($viewProfile) ?>&duels_page=<?= $i ?>"><?= $i ?></a>
                                <?php endif; ?>
                            <?php endfor; ?>

                            <?php if ($profileData['duels_current_page'] < $profileData['duels_total_pages']): ?>
                                <a href="?profile=<?= urlencode($viewProfile) ?>&duels_page=<?= $profileData['duels_current_page'] + 1 ?>">Вперед <i class="fas fa-chevron-right"></i></a>
                            <?php endif; ?>
                        </div>
                    <?php endif; ?>
                <?php else: ?>
                    <p>Нет данных о дуэлях</p>
                <?php endif; ?>
            </div>


            <!-- Matchup Grid -->
            <?php if (!empty($profileData['matchup_ratings'])): ?>
            <?php
            $classOrder = ['scout', 'soldier', 'pyro', 'demoman', 'heavy', 'engineer', 'medic', 'sniper', 'spy'];
            $matchupRatings = $profileData['matchup_ratings'];
            $matchupStats = $profileData['matchup_stats'];

            // Find most frequent matchup
            $maxDuels = 0;
            $mostFrequentMatchup = null;
            foreach ($matchupStats as $myClass => $oppClasses) {
                foreach ($oppClasses as $oppClass => $stats) {
                    if ($stats['total'] > $maxDuels) {
                        $maxDuels = $stats['total'];
                        $mostFrequentMatchup = ['myClass' => $myClass, 'oppClass' => $oppClass];
                    }
                }
            }
            ?>
            <div class="card">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-chess-board"></i> Сетка матчапов</h2>
                </div>

                <div style="margin-top: 8px; display: flex; gap: 20px; align-items: stretch; max-width: 100%; overflow: hidden;">
                    <div style="flex: 1 1 85%; min-width: 0; overflow: hidden;">
                        <div style="overflow-x: auto; overflow-y: hidden; width: 100%; padding-right: 5px;">
                            <table id="matchupHeatmap" style="border-collapse: separate; border-spacing: 3px; background: #1a1a1a; width: 100%; height: 100%; table-layout: fixed;">
                                <thead>
                                    <tr>
                                        <th style="padding: 4px; background: transparent; width: 24px; height: 24px;"></th>
                                        <?php foreach ($classOrder as $oppClass): ?>
                                            <?php $iconPath = getClassIconPath($oppClass); ?>
                                            <th style="padding: 2px; background: transparent; height: 20px; text-align: center; vertical-align: middle;">
                                                <?php if ($iconPath): ?>
                                                    <img src="tf_logo/<?= htmlspecialchars($iconPath) ?>"
                                                         alt="<?= htmlspecialchars($oppClass) ?>"
                                                         style="width: 22px; height: 22px; display: block; margin: 0 auto;">
                                                <?php else: ?>
                                                    <span style="font-size: 10px; color: #ccc;"><?= htmlspecialchars(substr($oppClass, 0, 1)) ?></span>
                                                <?php endif; ?>
                                            </th>
                                        <?php endforeach; ?>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($classOrder as $myClass): ?>
                                        <?php $iconPath = getClassIconPath($myClass); ?>
                                        <tr>
                                            <td style="padding: 2px; background: transparent; width: 24px; height: 20px; text-align: center; vertical-align: middle;">
                                                <?php if ($iconPath): ?>
                                                    <img src="tf_logo/<?= htmlspecialchars($iconPath) ?>"
                                                         alt="<?= htmlspecialchars($myClass) ?>"
                                                         style="width: 24px; height: 24px; display: block; margin: 0 auto;">
                                                <?php else: ?>
                                                    <span style="font-size: 10px; color: #ccc;"><?= htmlspecialchars(substr($myClass, 0, 1)) ?></span>
                                                <?php endif; ?>
                                            </td>
                                            <?php foreach ($classOrder as $oppClass): ?>
                                                <?php
                                                $rating = $matchupRatings[$myClass][$oppClass];
                                                $color = getRatingColor($rating);
                                                $label = $rating > 2000 ? 'Очень высокий' :
                                                         ($rating > 1700 ? 'Высокий' :
                                                         ($rating >= 1500 ? 'Средний' :
                                                         ($rating > 1000 ? 'Низкий' : 'Очень низкий')));
                                                $myClassDisplay = getClassDisplayName($myClass);
                                                $oppClassDisplay = getClassDisplayName($oppClass);
                                                $stats = $matchupStats[$myClass][$oppClass];
                                                $isMostFrequent = ($mostFrequentMatchup && $mostFrequentMatchup['myClass'] === $myClass && $mostFrequentMatchup['oppClass'] === $oppClass);
                                                ?>
                                                <td class="matchup-cell"
                                                    data-my-class="<?= htmlspecialchars($myClass) ?>"
                                                    data-opp-class="<?= htmlspecialchars($oppClass) ?>"
                                                    data-rating="<?= $rating ?>"
                                                    data-label="<?= htmlspecialchars($label) ?>"
                                                    data-my-class-display="<?= htmlspecialchars($myClassDisplay) ?>"
                                                    data-opp-class-display="<?= htmlspecialchars($oppClassDisplay) ?>"
                                                    data-total="<?= $stats['total'] ?>"
                                                    data-wins="<?= $stats['wins'] ?>"
                                                    style="height: 20px; background: <?= $color ?>; border-radius: 2px; cursor: pointer; position: relative; transition: all 0.2s; opacity: 0.7; border: 1px solid rgba(255,255,255,0.1); color: #333; font-size: 10px; font-weight: bold; text-align: center; line-height: 18px;"
                                                    onmouseenter="showMatchupTooltip(event, this)"
                                                    onmouseleave="hideMatchupTooltip()"
                                                    onclick="showMatchupDetails(this)">
                                                    <?php if ($isMostFrequent && $stats['total'] > 0): ?>
                                                        <svg style="position: absolute; top: 2px; right: 2px; width: 12px; height: 12px; pointer-events: none; filter: drop-shadow(0 0 2px rgba(0,0,0,0.8)) drop-shadow(0 0 4px rgba(255,215,0,0.6));" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                                                            <path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2Z" fill="#FFD700" stroke="#FFA500" stroke-width="0.5"/>
                                                        </svg>
                                                    <?php endif; ?>
                                                    <?= $rating ?>
                                                </td>
                                            <?php endforeach; ?>
                                        </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                    </div>
                    <div id="matchupDetailsPanel" style="flex: 0 0 220px; padding: 12px; background: #2a2a2a; border-radius: 8px; border: 1px solid #444; display: flex; flex-direction: column;">
                        <div style="color: #fff; font-weight: bold; font-size: 14px; margin-bottom: 10px; text-align: center;">Детали матчапа</div>
                        <div id="matchupDetailsContent" style="color: #ccc; font-size: 13px; line-height: 1.4; flex: 1;">
                            <div style="background: #1a1a1a; padding: 14px; border-radius: 6px; height: 100%; display: flex; align-items: center; justify-content: center;">
                                <div style="font-size: 12px; color: #666; text-align: center;">
                                    Выберите ячейку для просмотра статистики
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                <div id="matchupTooltip" style="position: absolute; background: #2a2a2a; color: #fff; padding: 8px 12px; border-radius: 4px; border: 1px solid #444; font-size: 12px; pointer-events: none; z-index: 10000; display: none; box-shadow: 0 4px 6px rgba(0,0,0,0.3);">
                </div>
                <div style="margin-top: 8px; display: flex; gap: 12px; flex-wrap: wrap; font-size: 12px;">
                    <div style="display: flex; align-items: center; gap: 4px;">
                        <div style="width: 16px; height: 16px; background: #4caf50; border: 1px solid #333;"></div>
                        <span style="color: #ccc;">Очень высокий (>2000)</span>
                    </div>
                    <div style="display: flex; align-items: center; gap: 4px;">
                        <div style="width: 16px; height: 16px; background: #8bc34a; border: 1px solid #333;"></div>
                        <span style="color: #ccc;">Высокий (1700-2000)</span>
                    </div>
                    <div style="display: flex; align-items: center; gap: 4px;">
                        <div style="width: 16px; height: 16px; background: #9ccc65; border: 1px solid #333;"></div>
                        <span style="color: #ccc;">Средний (1500-1700)</span>
                    </div>
                    <div style="display: flex; align-items: center; gap: 4px;">
                        <div style="width: 16px; height: 16px; background: #ff9800; border: 1px solid #333;"></div>
                        <span style="color: #ccc;">Низкий (1000-1500)</span>
                    </div>
                    <div style="display: flex; align-items: center; gap: 4px;">
                        <div style="width: 16px; height: 16px; background: #f44336; border: 1px solid #333;"></div>
                        <span style="color: #ccc;">Очень низкий (<1000)</span>
                    </div>
                </div>
            </div>

            <?php endif; ?>

            <!-- Activity Heatmap -->
            <?php if (!empty($profileData['activity'])): ?>
            <?php
            // Prepare heatmap data by year
            $years = [];
            foreach ($profileData['activity'] as $day) {
                $year = date('Y', strtotime($day['date']));
                if (!isset($years[$year])) {
                    $years[$year] = [];
                }
                $years[$year][$day['date']] = $day['count'];
            }

            // Get years with activity data (sorted descending)
            $availableYears = array_keys($years);
            rsort($availableYears);

            // Get current year to show by default
            $currentYear = date('Y');
            $selectedYear = !empty($availableYears) ? $availableYears[0] : $currentYear;
            if (isset($_GET['year']) && in_array($_GET['year'], $availableYears)) {
                $selectedYear = $_GET['year'];
            }
            ?>
            <div class="card">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-fire"></i> Активность</h2>
                </div>

                <div class="activity-heatmap-container-full-width">
                    <div style="display: flex; gap: 16px; align-items: flex-start;">
                        <div class="calendar-graph-full-width" style="flex: 1;">
                        <?php
                        // GitHub-style heatmap: columns = weeks, rows = days of week
                        // Cell size increased by 40% (10px -> 14px)
                        $cellSize = 15; // 14px cell + 1px gap
                        $cellWidth = 14;

                        // Generate calendar for selected year
                        $start = new DateTime("$selectedYear-01-01");
                        $end = new DateTime("$selectedYear-12-31");
                        $interval = new DateInterval('P1D');

                        // Find the first Sunday on or before Jan 1 (GitHub starts weeks on Sunday)
                        $firstSunday = clone $start;
                        while ($firstSunday->format('w') != 0) {
                            $firstSunday->sub($interval);
                        }

                        // Find the last Saturday on or after Dec 31
                        $lastSaturday = clone $end;
                        while ($lastSaturday->format('w') != 6) {
                            $lastSaturday->add($interval);
                        }

                        // Calculate positions for all days
                        $dayPositions = [];
                        $tempCurrent = clone $firstSunday;
                        $weekNumber = 0;

                        while ($tempCurrent <= $lastSaturday) {
                            $dateStr = $tempCurrent->format('Y-m-d');
                            $dayOfWeek = (int)$tempCurrent->format('w');

                            $dayPositions[] = [
                                'date' => $dateStr,
                                'x' => $weekNumber * $cellSize,
                                'y' => $dayOfWeek * $cellSize,
                                'month' => $tempCurrent->format('n'),
                                'in_year' => $tempCurrent->format('Y') == $selectedYear
                            ];

                            $tempCurrent->add($interval);

                            if ($tempCurrent->format('w') == 0) {
                                $weekNumber++;
                            }
                        }

                        // SVG dimensions (40% larger)
                        $svgWidth = ($weekNumber + 1) * $cellSize + 40;
                        $svgHeight = 7 * $cellSize + 25;

                        // Month labels
                        $months = [];
                        $lastMonth = null;
                        foreach ($dayPositions as $pos) {
                            if (!$pos['in_year']) continue;
                            $month = $pos['month'];
                            if ($month !== $lastMonth) {
                                $months[$month] = [
                                    'x' => $pos['x'],
                                    'name' => DateTime::createFromFormat('!m', $month)->format('M')
                                ];
                                $lastMonth = $month;
                            }
                        }
                        ?>
                        <svg width="<?= $svgWidth ?>" height="<?= $svgHeight ?>" class="js-calendar-graph-svg">
                            <!-- Month labels -->
                            <g transform="translate(36, 12)" font-size="11" fill="#7d8590">
                                <?php foreach ($months as $monthNum => $monthData): ?>
                                    <text x="<?= $monthData['x'] ?>" y="0"><?= $monthData['name'] ?></text>
                                <?php endforeach; ?>
                            </g>

                            <!-- Day of week labels -->
                            <g transform="translate(0, 28)" font-size="10" fill="#7d8590">
                                <text x="0" y="26">Пн</text>
                                <text x="0" y="56">Ср</text>
                                <text x="0" y="86">Пт</text>
                            </g>

                            <!-- Heatmap days -->
                            <g transform="translate(36, 20)">
                                <?php
                                foreach ($dayPositions as $pos) {
                                    $dateStr = $pos['date'];
                                    $count = isset($years[$selectedYear][$dateStr]) ? $years[$selectedYear][$dateStr] : 0;

                                    if (!$pos['in_year']) {
                                        continue;
                                    } elseif ($count == 0) {
                                        $color = '#161b22';
                                    } elseif ($count <= 2) {
                                        $color = '#0e4429';
                                    } elseif ($count <= 4) {
                                        $color = '#006d32';
                                    } elseif ($count <= 7) {
                                        $color = '#26a641';
                                    } else {
                                        $color = '#39d353';
                                    }

                                    echo '<rect class="day" width="'.$cellWidth.'" height="'.$cellWidth.'" x="'.$pos['x'].'" y="'.$pos['y'].'" fill="'.$color.'" data-count="'.$count.'" data-date="'.$dateStr.'" rx="2" ry="2" onclick="showDailyDuelsChart(\''.$dateStr.'\')"><title>'.$dateStr.': '.$count.' дуэлей</title></rect>';
                                }
                                ?>
                            </g>
                        </svg>
                    </div>

                        <!-- Year selector (GitHub style - right side) -->
                        <?php if (count($availableYears) > 0): ?>
                        <div class="year-selector-vertical">
                            <?php foreach ($availableYears as $yr): ?>
                                <button class="year-btn <?= $yr == $selectedYear ? 'active' : '' ?>" onclick="changeYearAjax('<?= $yr ?>')"><?= $yr ?></button>
                            <?php endforeach; ?>
                        </div>
                        <?php endif; ?>
                    </div>

                    <div style="margin-top: 12px; display: flex; justify-content: flex-start; align-items: center; gap: 4px; font-size: 11px; color: #7d8590;">
                        <span>Меньше</span>
                        <div style="width: 14px; height: 14px; background: #161b22; border-radius: 2px;"></div>
                        <div style="width: 14px; height: 14px; background: #0e4429; border-radius: 2px;"></div>
                        <div style="width: 14px; height: 14px; background: #006d32; border-radius: 2px;"></div>
                        <div style="width: 14px; height: 14px; background: #26a641; border-radius: 2px;"></div>
                        <div style="width: 14px; height: 14px; background: #39d353; border-radius: 2px;"></div>
                        <span>Больше</span>
                    </div>

                </div>

                <!-- Daily Duels Chart Container (outside of heatmap container for AJAX) -->
                <div id="daily-duels-chart-container" style="margin-top: 20px; display: none; padding: 16px; background: #1a1a1a; border-radius: 8px;">
                    <h3 id="daily-chart-title" style="margin: 0 0 12px 0; color: #e6edf3;">Дуэли за <span id="selected-date-display"></span></h3>
                    <div class="chart-wrapper" style="height: 200px;">
                        <canvas id="dailyDuelsChart"></canvas>
                    </div>
                    <button onclick="hideDailyDuelsChart()" style="margin-top: 12px; padding: 6px 12px; background: #21262d; border: 1px solid #30363d; border-radius: 6px; color: #c9d1d9; cursor: pointer; font-size: 12px;">Скрыть график</button>
                </div>
            </div>

            <script>
                // Initialize profile Steam ID for JS functions
                window.PROFILE_STEAM_ID = '<?= $viewProfile ?>';
            </script>
            <?php endif; ?>
        <?php else: ?>
            <!-- Main Statistics View -->
            <div class="search-container">
                <form method="GET" class="search-form" style="display: flex; width: 100%;">
                    <?php if (isset($_GET['profile'])): ?>
                        <input type="hidden" name="profile" value="<?= htmlspecialchars($_GET['profile']) ?>">
                    <?php endif; ?>
                    <input type="text" name="search" placeholder="Поиск игрока..." class="search-input" value="<?= htmlspecialchars($searchQuery) ?>">
                    <button type="submit" class="search-btn">Найти</button>
                    <?php if ($searchQuery): ?>
                        <a href="?" class="btn btn-secondary" style="margin-left: 10px;">Очистить</a>
                    <?php endif; ?>
                </form>
            </div>

            <?php if ($searchQuery && !empty($searchResults)): ?>
                <div class="search-results">
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-search"></i> Результаты поиска</h2>
                        </div>
                        <div style="overflow-x: auto;">
                            <table class="top-players-table">
                                <thead>
                                    <tr>
                                        <th>Место</th>
                                        <th>Игрок</th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=rating&sort_dir=<?= $orderBy === 'rating' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                Рейтинг
                                                <?php if ($orderBy === 'rating'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=wins&sort_dir=<?= $orderBy === 'wins' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                Победы
                                                <?php if ($orderBy === 'wins'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=losses&sort_dir=<?= $orderBy === 'losses' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                Поражения
                                                <?php if ($orderBy === 'losses'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=winrate&sort_dir=<?= $orderBy === 'winrate' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                Винрейт
                                                <?php if ($orderBy === 'winrate'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($searchResults as $index => $player): ?>
                                        <tr>
                                            <td>
                                                <span class="rank-badge"><?= $index + 1 ?></span>
                                            </td>
                                            <td>
                                                <a href="?profile=<?= urlencode($player['steamid']) ?>" style="color: var(--accent); text-decoration: none;">
                                                    <?= htmlspecialchars($player['nick'] ?: $player['steamid']) ?>
                                                </a>
                                            </td>
                                            <td><?= $player['rating'] ?></td>
                                            <td><?= $player['wins'] ?></td>
                                            <td><?= $player['losses'] ?></td>
                                            <td><?= $player['winrate'] ?>%</td>
                                        </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            <?php elseif ($searchQuery): ?>
                <div class="card">
                    <p>Игроки не найдены по запросу: <?= htmlspecialchars($searchQuery) ?></p>
                </div>
            <?php else: ?>
                <div class="stats-overview">
                    <div class="stat-item">
                        <div class="stat-label">Всего дуэлей</div>
                        <div class="stat-value" style="color: var(--accent);"><?= $totalStats['total_duels'] + $totalStats['total_duels_2v2'] ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label">Всего игроков</div>
                        <div class="stat-value" style="color: var(--success);"><?= $totalStats['total_players'] ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label">Рекордный рейтинг</div>
                        <div class="stat-value" style="color: var(--warning);"><?= $totalStats['highest_rating'] ?: 'N/A' ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label">Дуэлей 1v1</div>
                        <div class="stat-value" style="color: var(--danger);"><?= $totalStats['total_duels'] ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label">Дуэлей 2v2</div>
                        <div class="stat-value" style="color: var(--primary);"><?= $totalStats['total_duels_2v2'] ?></div>
                    </div>
                </div>

                <div class="tabs">
                    <button class="tab active" data-tab="overview">Список игроков</button>
                    <button class="tab" data-tab="recent-duels">Последние дуэли</button>
                </div>

                <div class="tab-content active" id="overview-tab">
                    <div class="main-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-users"></i> Список игроков</h2>
                            </div>

                            <div id="players-container" class="refreshable-content">
                                <div class="refresh-indicator" id="players-refresh-indicator">
                                    <div class="refresh-spinner"></div>
                                </div>
                                <?php if (!empty($topPlayers)): ?>
                                    <div style="overflow-x: auto;">
                                        <table class="top-players-table">
                                            <thead>
                                                <tr>
                                                    <th>Место</th>
                                                    <th>Игрок</th>
                                                    <th>
                                                        <a href="?sort_by=rating&sort_dir=<?= $orderBy === 'rating' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                            Рейтинг
                                                            <?php if ($orderBy === 'rating'): ?>
                                                                <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                            <?php endif; ?>
                                                        </a>
                                                    </th>
                                                    <th>
                                                        <a href="?sort_by=wins&sort_dir=<?= $orderBy === 'wins' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                            Победы
                                                            <?php if ($orderBy === 'wins'): ?>
                                                                <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                            <?php endif; ?>
                                                        </a>
                                                    </th>
                                                    <th>
                                                        <a href="?sort_by=losses&sort_dir=<?= $orderBy === 'losses' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                            Поражения
                                                            <?php if ($orderBy === 'losses'): ?>
                                                                <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                            <?php endif; ?>
                                                        </a>
                                                    </th>
                                                    <th>
                                                        <a href="?sort_by=winrate&sort_dir=<?= $orderBy === 'winrate' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                            Винрейт
                                                            <?php if ($orderBy === 'winrate'): ?>
                                                                <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                            <?php endif; ?>
                                                        </a>
                                                    </th>
                                                </tr>
                                            </thead>
                                            <tbody id="players-tbody">
                                                <?php foreach ($topPlayers as $index => $player):
                                                    $winrate = ($player['wins'] + $player['losses']) > 0 ?
                                                        round(($player['wins'] / ($player['wins'] + $player['losses'])) * 100, 2) : 0;
                                                ?>
                                                    <tr class="rank-<?= $index + 1 ?>">
                                                        <td>
                                                            <span class="rank-badge"><?= $index + 1 ?></span>
                                                        </td>
                                                        <td>
                                                            <a href="?profile=<?= urlencode($player['steamid']) ?>" style="color: var(--accent); text-decoration: none;">
                                                                <?= htmlspecialchars($player['nick'] ?: $player['steamid']) ?>
                                                            </a>
                                                        </td>
                                                        <td><?= $player['rating'] ?></td>
                                                        <td><?= $player['wins'] ?></td>
                                                        <td><?= $player['losses'] ?></td>
                                                        <td><?= $winrate ?>%</td>
                                                    </tr>
                                                <?php endforeach; ?>
                                            </tbody>
                                        </table>
                                    </div>
                                <?php else: ?>
                                    <p>Нет данных о топ игроках</p>
                                <?php endif; ?>

                                <!-- Players Pagination -->
                                <div class="pagination" id="players-pagination">
                                    <?php if ($totalPagesPlayers > 1): ?>
                                        <?php if ($page > 1): ?>
                                            <a href="?page=<?= $page - 1 ?>"><i class="fas fa-chevron-left"></i> Назад</a>
                                        <?php endif; ?>

                                        <?php for ($i = max(1, $page - 2); $i <= min($totalPagesPlayers, $page + 2); $i++): ?>
                                            <?php if ($i == $page): ?>
                                                <span class="current"><?= $i ?></span>
                                            <?php else: ?>
                                                <a href="?page=<?= $i ?>"><?= $i ?></a>
                                            <?php endif; ?>
                                        <?php endfor; ?>

                                        <?php if ($page < $totalPagesPlayers): ?>
                                            <a href="?page=<?= $page + 1 ?>">Вперед <i class="fas fa-chevron-right"></i></a>
                                        <?php endif; ?>
                                    <?php endif; ?>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>


                <div class="tab-content" id="recent-duels-tab">
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-history"></i> Последние дуэли</h2>
                        </div>

                        <div id="duels-container-2" class="refreshable-content">
                            <div class="refresh-indicator" id="duels-refresh-indicator-2">
                                <div class="refresh-spinner"></div>
                            </div>
                            <div style="overflow-x: auto;">
                                <table class="duels-table">
                                    <thead>
                                        <tr>
                                            <th>ID</th>
                                            <th>Тип</th>
                                            <th>Дата</th>
                                            <th>Победитель</th>
                                            <th>Проигравший</th>
                                            <th>Карта</th>
                                            <th>Арена</th>
                                            <th>Счет</th>
                                        </tr>
                                    </thead>
                                    <tbody id="duels-tbody-2">
                                        <?php foreach ($recentDuels as $duel):
                                            $winnerNick = getPlayerNickname($db, $duel['winner']);
                                            $loserNick = getPlayerNickname($db, $duel['loser']);
                                        ?>
                                            <tr>
                                                <td>
                                                    <a href="?duel=<?= $duel['id'] ?>&type=<?= $duel['type'] ?>" class="duel-id-link">
                                                        <?= $duel['id'] ?>
                                                    </a>
                                                </td>
                                                <td><?= $duel['type'] ?></td>
                                                <td><?= date('d.m.Y H:i', $duel['endtime']) ?></td>
                                                <td>
                                                    <a href="?profile=<?= urlencode($duel['winner']) ?>" style="color: var(--success); text-decoration: none;">
                                                        <?= htmlspecialchars($winnerNick) ?>
                                                    </a>
                                                </td>
                                                <td>
                                                    <a href="?profile=<?= urlencode($duel['loser']) ?>" style="color: var(--danger); text-decoration: none;">
                                                        <?= htmlspecialchars($loserNick) ?>
                                                    </a>
                                                </td>
                                                <td><?= htmlspecialchars($duel['mapname']) ?></td>
                                                <td><?= htmlspecialchars($duel['arenaname']) ?></td>
                                                <td><?= $duel['winnerscore'] ?>:<?= $duel['loserscore'] ?></td>
                                            </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>

                            <!-- Pagination -->
                            <div class="pagination" id="pagination-2">
                                <?php if ($totalPages > 1 || ($totalPages == 1 && $totalDuels > 0)): ?>
                                    <?php if ($page > 1): ?>
                                        <a href="?page=<?= $page - 1 ?>"><i class="fas fa-chevron-left"></i> Назад</a>
                                    <?php endif; ?>

                                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                                        <?php if ($i == $page): ?>
                                            <span class="current"><?= $i ?></span>
                                        <?php else: ?>
                                            <a href="?page=<?= $i ?>"><?= $i ?></a>
                                        <?php endif; ?>
                                    <?php endfor; ?>

                                    <?php if ($page < $totalPages): ?>
                                        <a href="?page=<?= $page + 1 ?>">Вперед <i class="fas fa-chevron-right"></i></a>
                                    <?php endif; ?>
                                <?php elseif ($totalPages == 1 && $totalDuels > 0): ?>
                                    <!-- Show single page indicator -->
                                    <span class="current">1</span>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                </div>
            <?php endif; ?>
        <?php endif; ?>
    </div>

    <script src="js/script.js"></script>
    <script>
        // Initialize rating chart if on profile page
        <?php if ($viewProfile && !empty($profileData['rating_history'])): ?>
        const ratingCtx = document.getElementById('ratingChart').getContext('2d');
        const ratingData = {
            labels: [
                <?php
                $labels = [];
                $datasets = [];
                foreach ($profileData['rating_history'] as $entry) {
                    $labels[] = date('d.m', $entry['date_ts']);
                    $datasets[] = $entry['rating'];
                }
                echo '"' . implode('", "', $labels) . '"';
                ?>
            ],
            datasets: [{
                label: 'Рейтинг',
                data: [<?php echo implode(', ', $datasets); ?>],
                borderColor: 'rgb(74, 222, 128)',
                backgroundColor: 'rgba(74, 222, 128, 0.1)',
                tension: 0.4,
                fill: true
            }]
        };

        const ratingChart = new Chart(ratingCtx, {
            type: 'line',
            data: ratingData,
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: false
                    }
                },
                scales: {
                    y: {
                        beginAtZero: false,
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
        <?php endif; ?>

        // Auto-refresh duels periodically if authenticated
        <?php if ($isAuthenticated): ?>
        setInterval(function() {
            // In a real app, you would fetch updated data here
            console.log('Checking for new duel data...');
        }, 30000); // Every 30 seconds
        <?php endif; ?>

        // Function to change year for activity heatmap
        function changeYear(year) {
            const urlParams = new URLSearchParams(window.location.search);
            urlParams.set('year', year);
            window.location.search = urlParams.toString();
        }
    </script>
</body>
</html>