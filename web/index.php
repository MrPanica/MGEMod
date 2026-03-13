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
require_once 'includes/i18n.php';

$MGE_LANG = mge_resolve_language();
$MGE_LOCALE = mge_locale_for_language($MGE_LANG);
$MGE_I18N = mge_load_translations($MGE_LANG);

// Initialize query counter and timer
$queryCount = 0;
$startTime = microtime(true);

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

// Function to execute a prepared statement and increment query counter
function executeQuery($db, $sql, $params = [], $types = '') {
    global $queryCount;
    $queryCount++;

    $stmt = $db->prepare($sql);
    if (!$stmt) {
        return false;
    }

    if (!empty($params) && !empty($types)) {
        $stmt->bind_param($types, ...$params);
    }

    $result = $stmt->execute();
    if (!$result) {
        $stmt->close();
        return false;
    }

    $result = $stmt->get_result();
    $data = $result ? $result->fetch_all(MYSQLI_ASSOC) : [];
    $stmt->close();

    return $data;
}

// Function to execute a prepared statement and get single result
function executeQuerySingle($db, $sql, $params = [], $types = '') {
    global $queryCount;
    $queryCount++;

    $stmt = $db->prepare($sql);
    if (!$stmt) {
        return false;
    }

    if (!empty($params) && !empty($types)) {
        $stmt->bind_param($types, ...$params);
    }

    $result = $stmt->execute();
    if (!$result) {
        $stmt->close();
        return false;
    }

    $result = $stmt->get_result();
    $data = $result ? $result->fetch_assoc() : false;
    $stmt->close();

    return $data;
}

// Function to execute a count query
function executeCountQuery($db, $sql, $params = [], $types = '') {
    global $queryCount;
    $queryCount++;

    $stmt = $db->prepare($sql);
    if (!$stmt) {
        return 0;
    }

    if (!empty($params) && !empty($types)) {
        $stmt->bind_param($types, ...$params);
    }

    $result = $stmt->execute();
    if (!$result) {
        $stmt->close();
        return 0;
    }

    $result = $stmt->get_result();
    $row = $result ? $result->fetch_assoc() : false;
    $stmt->close();

    return $row ? (int)$row['total'] : 0;
}

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
    $row = executeQuerySingle($db, "SELECT rating FROM mgemod_stats WHERE steamid = ?", [$steamId], 's');

    return $row ? $row['rating'] : null;
}

function getMGEDuels($db, $steamId, $limit = 10) {
    $stmt = $db->prepare("
        SELECT * FROM (
            SELECT
                '1v1' AS type,
                id,
                endtime,
                winner,
                NULL          AS winner2,
                loser,
                NULL          AS loser2,
                winnerscore,
                loserscore,
                winlimit,
                mapname,
                arenaname,
                winnerclass,
                NULL          AS winner2class,
                loserclass,
                NULL          AS loser2class,
                starttime
            FROM mgemod_duels
            WHERE (winner = ? OR loser = ?)
              AND winner IS NOT NULL
              AND loser  IS NOT NULL
              -- AND canceled = 0

            UNION ALL

            SELECT
                '2v2' AS type,
                id,
                endtime,
                winner,
                winner2,
                loser,
                loser2,
                winnerscore,
                loserscore,
                winlimit,
                mapname,
                arenaname,
                winnerclass,
                winner2class,
                loserclass,
                loser2class,
                starttime
            FROM mgemod_duels_2v2
            WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?)
              AND winner IS NOT NULL
              AND loser  IS NOT NULL
              -- AND canceled = 0
        ) AS combined
        ORDER BY endtime DESC
        LIMIT ?
    ");

    $stmt->bind_param('ssssssi', 
        $steamId, $steamId,     // 1v1: winner / loser
        $steamId, $steamId, $steamId, $steamId,  // 2v2: winner, winner2, loser, loser2
        $limit
    );

    $stmt->execute();
    $result = $stmt->get_result();
    $duels = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

// If processDuelWinners already exists in your build, keep it.
// Otherwise this is a minimal fallback that sets is_winner.

    $processedDuels = [];
    foreach ($duels as $duel) {
        $isWinner = false;

        if ($duel['type'] === '1v1') {
            if ($duel['winner'] === $steamId) {
                $isWinner = true;
            }
        } else { // 2v2
            if ($duel['winner'] === $steamId || $duel['winner2'] === $steamId) {
                $isWinner = true;
            }
        }

        $duel['is_winner'] = $isWinner;
        $processedDuels[] = $duel;
    }

    error_log("DEBUG: Fetched {$limit} duels for SteamID $steamId -> found: " . count($processedDuels));

    return $processedDuels;
}


function getMGEStats($db, $steamId) {
    $row = executeQuerySingle($db, "SELECT wins, losses FROM mgemod_stats WHERE steamid = ?", [$steamId], 's');

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
    $allowedFields = ['rating', 'wins', 'losses', 'winrate', 'last_duel'];
    if (!in_array($orderBy, $allowedFields)) {
        $orderBy = 'rating';
    }

    // Validate order direction
    $orderDir = strtoupper($orderDir) === 'ASC' ? 'ASC' : 'DESC';

    // Special handling for 'last_duel' sort
    if ($orderBy === 'last_duel') {
        $sql = "
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
                   COALESCE(
                       GREATEST(
                           (SELECT MAX(endtime) FROM mgemod_duels WHERE winner = ms.steamid OR loser = ms.steamid),
                           (SELECT MAX(endtime) FROM mgemod_duels_2v2 WHERE winner = ms.steamid OR winner2 = ms.steamid OR loser = ms.steamid OR loser2 = ms.steamid)
                       ), 0
                   ) as last_duel_time_val
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY last_duel_time_val {$orderDir}
            LIMIT ?
        ";
        
        $stmt = $db->prepare($sql);
        $stmt->bind_param('i', $limit);
        $stmt->execute();
        $result = $stmt->get_result();
        $players = $result->fetch_all(MYSQLI_ASSOC);
        $stmt->close();
    } else if ($orderBy === 'winrate') {
        // For winrate sorting, calculate winrate in the query
        $players = executeQuery($db, "
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
                   CASE
                       WHEN (ms.wins + ms.losses) > 0 THEN ROUND((ms.wins / (ms.wins + ms.losses)) * 100, 2)
                       ELSE 0
                   END as winrate_calc
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY winrate_calc {$orderDir}
            LIMIT ?
        ", [$limit], 'i');
    } else {
        $players = executeQuery($db, "
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY ms.{$orderBy} {$orderDir}
            LIMIT ?
        ", [$limit], 'i');
    }

    $cache[$cacheKey] = $players;
    return $players;
}

// Function to get recent duels with pagination
// Function to get recent duels with pagination (OPTIMIZED VERSION)
function getRecentDuels($db, $limit = 10, $offset = 0, $orderBy = 'endtime', $orderDir = 'DESC') {
    // Validate order by field to prevent SQL injection
    $allowedFields = ['endtime', 'id', 'winnerscore', 'loserscore'];
    if (!in_array($orderBy, $allowedFields)) {
        $orderBy = 'endtime';
    }

    // Validate order direction
    $orderDir = strtoupper($orderDir) === 'ASC' ? 'ASC' : 'DESC';
    
    // Calculate how many records to fetch from each table
    // We fetch more than needed to account for data distribution
    $fetchLimit = $limit + $offset + 10; // Add buffer
    
    // First, try to get from 1v1 table
    $sql1v1 = "
        SELECT
            '1v1' as type,
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo,
            NULL as winner2, NULL as winner2class, NULL as loser2, NULL as loser2class
        FROM mgemod_duels
        ORDER BY {$orderBy} {$orderDir}
        LIMIT ?
    ";
    
    $duels1v1 = executeQuery($db, $sql1v1, [$fetchLimit], 'i');
    
    // Then get from 2v2 table
    $sql2v2 = "
        SELECT
            '2v2' as type,
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo,
            winner2, winner2class, loser2, loser2class
        FROM mgemod_duels_2v2
        ORDER BY {$orderBy} {$orderDir}
        LIMIT ?
    ";
    
    $duels2v2 = executeQuery($db, $sql2v2, [$fetchLimit], 'i');
    
    // Merge and sort all results in PHP
    $allDuels = array_merge($duels1v1, $duels2v2);
    
    // Sort the combined array
    usort($allDuels, function($a, $b) use ($orderBy, $orderDir) {
        $valA = $a[$orderBy];
        $valB = $b[$orderBy];
        
        if ($orderDir === 'ASC') {
            return $valA <=> $valB;
        } else {
            return $valB <=> $valA;
        }
    });
    
    // Apply offset and limit
    $result = array_slice($allDuels, $offset, $limit);
    
    return $result;
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

    $row = executeQuerySingle($db, $sql);
    $totalCount = $row ? $row['total_count'] : 0;
    $cache['total_duels_count'] = $totalCount;

    return $totalCount;
}

// Function to get duel details by ID
function getDuelDetails($db, $duelId, $type) {
    $table = $type === '1v1' ? 'mgemod_duels' : 'mgemod_duels_2v2';
    $duel = executeQuerySingle($db, "
        SELECT * FROM {$table} WHERE id = ?
    ", [$duelId], 'i');

    return $duel;
}

function normalizeMgeSlotValue($value, $defaultSlot) {
    $slot = (int)$value;
    return $slot > 0 ? $slot : (int)$defaultSlot;
}

function getMgeClassNameById($classId) {
    static $classMap = [
        0 => 'unknown',
        1 => 'scout',
        2 => 'sniper',
        3 => 'soldier',
        4 => 'demoman',
        5 => 'medic',
        6 => 'heavy',
        7 => 'pyro',
        8 => 'spy',
        9 => 'engineer',
        10 => 'civilian'
    ];

    return $classMap[(int)$classId] ?? 'unknown';
}

function getMgeSlotSteamIdFromDuel(array $duel, string $duelType, int $slot): ?string {
    if ($slot <= 0) {
        return null;
    }

    if ($duelType === '2v2') {
        $winnerSlot = normalizeMgeSlotValue($duel['winner_slot'] ?? 0, 1);
        $winner2Slot = normalizeMgeSlotValue($duel['winner2_slot'] ?? 0, 3);
        $loserSlot = normalizeMgeSlotValue($duel['loser_slot'] ?? 0, 2);
        $loser2Slot = normalizeMgeSlotValue($duel['loser2_slot'] ?? 0, 4);

        if ($slot === $winnerSlot) return isset($duel['winner']) ? trim((string)$duel['winner']) : null;
        if ($slot === $winner2Slot) return isset($duel['winner2']) ? trim((string)$duel['winner2']) : null;
        if ($slot === $loserSlot) return isset($duel['loser']) ? trim((string)$duel['loser']) : null;
        if ($slot === $loser2Slot) return isset($duel['loser2']) ? trim((string)$duel['loser2']) : null;

        return null;
    }

    $winnerSlot = normalizeMgeSlotValue($duel['winner_slot'] ?? 0, 1);
    $loserSlot = normalizeMgeSlotValue($duel['loser_slot'] ?? 0, 2);

    if ($slot === $winnerSlot) return isset($duel['winner']) ? trim((string)$duel['winner']) : null;
    if ($slot === $loserSlot) return isset($duel['loser']) ? trim((string)$duel['loser']) : null;

    return null;
}

function getMgeRoundTeamSlotByPlayerSlot($slot, $duelType, $duel = []) {
    $slot = (int)$slot;
    if ($slot <= 0) {
        return 0;
    }

    if ($duelType === '2v2') {
        $winnerSlot = normalizeMgeSlotValue($duel['winner_slot'] ?? 0, 1);
        $winner2Slot = normalizeMgeSlotValue($duel['winner2_slot'] ?? 0, 3);
        $loserSlot = normalizeMgeSlotValue($duel['loser_slot'] ?? 0, 2);
        $loser2Slot = normalizeMgeSlotValue($duel['loser2_slot'] ?? 0, 4);

        if ($slot === $winnerSlot || $slot === $winner2Slot) {
            return 1;
        }
        if ($slot === $loserSlot || $slot === $loser2Slot) {
            return 2;
        }

        if ($slot === 1 || $slot === 3) {
            return 1;
        }
        if ($slot === 2 || $slot === 4) {
            return 2;
        }

        return 0;
    }

    $winnerSlot = normalizeMgeSlotValue($duel['winner_slot'] ?? 0, 1);
    $loserSlot = normalizeMgeSlotValue($duel['loser_slot'] ?? 0, 2);

    if ($slot === $winnerSlot) {
        return 1;
    }
    if ($slot === $loserSlot) {
        return 2;
    }

    if ($slot === 1 || $slot === 2) {
        return $slot;
    }

    return 0;
}

function buildMgeRoundsFromCompactJson(array $duel, string $duelType): array {
    $compactRaw = trim((string)($duel['rounds_compact_json'] ?? ''));
    if ($compactRaw === '') {
        return [];
    }

    $decoded = json_decode($compactRaw, true);
    if (!is_array($decoded) || !isset($decoded['r']) || !is_array($decoded['r'])) {
        return [];
    }

    $is2v2 = ($duelType === '2v2');
    $slots = $is2v2 ? [1, 2, 3, 4] : [1, 2];
    $version = (int)($decoded['v'] ?? 1);
    $rows = [];
    $scoreRed = 0;
    $scoreBlu = 0;

    foreach ($decoded['r'] as $index => $roundData) {
        if (!is_array($roundData)) {
            continue;
        }

        $isV2Shape = $version >= 2;
        if (!$isV2Shape) {
            $roundLen = count($roundData);
            $isV2Shape = (!$is2v2 && $roundLen >= 7) || ($is2v2 && $roundLen >= 11);
        }

        $scoringWeaponDefindex = $isV2Shape ? (int)($roundData[2] ?? 0) : 0;
        $classOffset = $isV2Shape ? 3 : 2;
        $weaponOffset = $isV2Shape ? ($is2v2 ? 7 : 5) : ($is2v2 ? 6 : 4);

        $scorerSlot = (int)($roundData[0] ?? 0);
        $duration = max(0, (int)($roundData[1] ?? 0));
        $winnerTeamSlot = 0;
        if ($scorerSlot > 0) {
            $winnerTeamSlot = (int)getMgeRoundTeamSlotByPlayerSlot($scorerSlot, $duelType, $duel);
            if ($winnerTeamSlot !== 1 && $winnerTeamSlot !== 2) {
                $winnerTeamSlot = 0;
            }
        }

        $row = [
            'round_number' => ((int)$index + 1),
            'duration' => $duration,
            'winner_team_slot' => $winnerTeamSlot,
            'score_red_before' => $scoreRed,
            'score_blu_before' => $scoreBlu,
            'score_red_after' => $scoreRed,
            'score_blu_after' => $scoreBlu,
            'scorer_slot' => $scorerSlot,
            'scoring_weapon_defindex' => $scoringWeaponDefindex
        ];

        foreach ($slots as $slot) {
            $classId = (int)($roundData[$classOffset + ($slot - 1)] ?? 0);
            $weaponValue = $roundData[$weaponOffset + ($slot - 1)] ?? '';
            $weaponIds = is_string($weaponValue) ? trim($weaponValue) : trim((string)$weaponValue);

            $row["slot{$slot}_steamid"] = (string)(getMgeSlotSteamIdFromDuel($duel, $duelType, $slot) ?? '');
            $row["slot{$slot}_class_id"] = $classId;
            $row["slot{$slot}_class"] = getMgeClassNameById($classId);
            $row["slot{$slot}_weaponids"] = $weaponIds;
        }

        if ($winnerTeamSlot === 1) {
            $scoreRed++;
        } elseif ($winnerTeamSlot === 2) {
            $scoreBlu++;
        }

        $row['score_red_after'] = $scoreRed;
        $row['score_blu_after'] = $scoreBlu;
        $rows[] = $row;
    }

    return $rows;
}

function buildMgeRoundsHtmlSimple(array $duel, string $duelType): string {
    $rounds = buildMgeRoundsFromCompactJson($duel, $duelType);
    if (empty($rounds)) {
        return '<div class="duel-rounds-wrap"><div class="duel-rounds-empty">' . htmlspecialchars(t('rounds_not_found'), ENT_QUOTES, 'UTF-8') . '</div></div>';
    }

    $is2v2 = ($duelType === '2v2');
    $slots = $is2v2 ? [1, 2, 3, 4] : [1, 2];
    $topSlots = $is2v2 ? [1, 3] : [1];
    $bottomSlots = $is2v2 ? [2, 4] : [2];
    $slotNickMap = [];

    foreach ($slots as $slot) {
        $steamid = trim((string)(getMgeSlotSteamIdFromDuel($duel, $duelType, $slot) ?? ''));
        if ($steamid === '') {
            continue;
        }

        $nick = $steamid;
        if ($is2v2) {
            $winnerSlot = normalizeMgeSlotValue($duel['winner_slot'] ?? 0, 1);
            $winner2Slot = normalizeMgeSlotValue($duel['winner2_slot'] ?? 0, 3);
            $loserSlot = normalizeMgeSlotValue($duel['loser_slot'] ?? 0, 2);
            $loser2Slot = normalizeMgeSlotValue($duel['loser2_slot'] ?? 0, 4);

            if ($slot === $winnerSlot) $nick = (string)($duel['winner_nick'] ?? $duel['winner'] ?? $steamid);
            if ($slot === $winner2Slot) $nick = (string)($duel['winner2_nick'] ?? $duel['winner2'] ?? $steamid);
            if ($slot === $loserSlot) $nick = (string)($duel['loser_nick'] ?? $duel['loser'] ?? $steamid);
            if ($slot === $loser2Slot) $nick = (string)($duel['loser2_nick'] ?? $duel['loser2'] ?? $steamid);
        } else {
            $winnerSlot = normalizeMgeSlotValue($duel['winner_slot'] ?? 0, 1);
            $loserSlot = normalizeMgeSlotValue($duel['loser_slot'] ?? 0, 2);
            if ($slot === $winnerSlot) $nick = (string)($duel['winner_nick'] ?? $duel['winner'] ?? $steamid);
            if ($slot === $loserSlot) $nick = (string)($duel['loser_nick'] ?? $duel['loser'] ?? $steamid);
        }

        $slotNickMap[$slot] = $nick;
    }

    $renderSlotCard = static function (int $slot, array $round, int $winnerTeamSlot, int $scorerSlot) use ($duelType, $duel, $slotNickMap): string {
        $slotTeam = (int)getMgeRoundTeamSlotByPlayerSlot($slot, $duelType, $duel);
        $sideText = $slotTeam === 1 ? t('team_red') : ($slotTeam === 2 ? t('team_blu') : t('team_unknown'));
        $steamid = trim((string)($round["slot{$slot}_steamid"] ?? ''));
        $nick = (string)($slotNickMap[$slot] ?? (t('slot_label') . ' ' . $slot));
        $className = trim((string)($round["slot{$slot}_class"] ?? t('unknown')));

        $isWinner = ($winnerTeamSlot > 0 && $slotTeam === $winnerTeamSlot);
        $cardClass = $isWinner ? ' duel-round-card-win' : ' duel-round-card-loss';

        $nickEsc = htmlspecialchars($nick, ENT_QUOTES, 'UTF-8');
        if ($steamid !== '') {
            $nickEsc = '<a href="?profile=' . urlencode($steamid) . '&lang=' . urlencode($GLOBALS['MGE_LANG']) . '" class="duel-round-player-link">' . $nickEsc . '</a>';
        }

        $slotTitle = htmlspecialchars(t('slot_label') . ' ' . $slot . ' (' . $sideText . ')', ENT_QUOTES, 'UTF-8');
        $classEsc = htmlspecialchars($className, ENT_QUOTES, 'UTF-8');

        $badge = '';
        if ($scorerSlot === $slot) {
            $badge = '<span class="duel-round-badge duel-round-badge-scorer">' . htmlspecialchars(t('point_plus'), ENT_QUOTES, 'UTF-8') . '</span>';
        }

        $html = '<div class="duel-round-card' . $cardClass . '">';
        $html .= '<div class="duel-round-card-head">' . $slotTitle . $badge . '</div>';
        $html .= '<div class="duel-round-card-player">' . $nickEsc . '</div>';
        $html .= '<div class="duel-round-card-meta">' . htmlspecialchars(t('class_label'), ENT_QUOTES, 'UTF-8') . ': ' . $classEsc . '</div>';
        $html .= '</div>';

        return $html;
    };

    $html = '<div class="duel-rounds-wrap duel-rounds-wrap-timeline">';
    $html .= '<h3 class="duel-rounds-title">' . htmlspecialchars(t('rounds_title', ['count' => count($rounds)]), ENT_QUOTES, 'UTF-8') . '</h3>';
    $html .= '<div class="duel-rounds-timeline" data-rounds-timeline="1">';

    foreach ($rounds as $round) {
        $roundNumber = (int)($round['round_number'] ?? 0);
        $duration = max(0, (int)($round['duration'] ?? 0));
        $winnerTeamSlot = (int)($round['winner_team_slot'] ?? 0);
        $scoreAfter = (int)($round['score_red_after'] ?? 0) . ':' . (int)($round['score_blu_after'] ?? 0);
        $scorerSlot = (int)($round['scorer_slot'] ?? 0);

        $winnerClass = '';
        if ($winnerTeamSlot === 1) {
            $winnerClass = ' duel-round-center-red';
        } elseif ($winnerTeamSlot === 2) {
            $winnerClass = ' duel-round-center-blu';
        }

        $html .= '<div class="duel-round-timeline-item">';
        $html .= '<div class="duel-round-side duel-round-side-top">';
        foreach ($topSlots as $slot) {
            $html .= $renderSlotCard($slot, $round, $winnerTeamSlot, $scorerSlot);
        }
        $html .= '</div>';

        $html .= '<div class="duel-round-center">';
        $html .= '<div class="duel-round-center-pill' . $winnerClass . '">';
        $html .= '<div class="duel-round-center-line1">' . htmlspecialchars(t('round_label') . ' #' . $roundNumber . ' - ' . t('score_label') . ': ' . $scoreAfter, ENT_QUOTES, 'UTF-8') . '</div>'; 
        $html .= '<div class="duel-round-center-line2">' . htmlspecialchars(t('duration_label') . ': ' . $duration . 's', ENT_QUOTES, 'UTF-8') . '</div>'; 



        $html .= '</div>';
        $html .= '</div>';

        $html .= '<div class="duel-round-side duel-round-side-bottom">';
        foreach ($bottomSlots as $slot) {
            $html .= $renderSlotCard($slot, $round, $winnerTeamSlot, $scorerSlot);
        }
        $html .= '</div>';
        $html .= '</div>';
    }

    $html .= '</div>';
    $html .= '</div>';

    static $timelineScriptInjected = false;
    if (!$timelineScriptInjected) {
        $timelineScriptInjected = true;
        $html .= '<script>(function(){function initTimelineDrag(tl){if(!tl||tl.dataset.dragInit==="1"){return;}tl.dataset.dragInit="1";let isDown=false,startX=0,startScroll=0,pid=null;tl.addEventListener("pointerdown",function(e){isDown=true;pid=e.pointerId;startX=e.clientX;startScroll=tl.scrollLeft;tl.classList.add("duel-rounds-timeline-dragging");if(tl.setPointerCapture){try{tl.setPointerCapture(pid);}catch(_){}}});tl.addEventListener("pointermove",function(e){if(!isDown||e.pointerId!==pid){return;}tl.scrollLeft=startScroll-(e.clientX-startX);});function stopDrag(){isDown=false;tl.classList.remove("duel-rounds-timeline-dragging");if(pid!==null&&tl.releasePointerCapture){try{tl.releasePointerCapture(pid);}catch(_){}}pid=null;}tl.addEventListener("pointerup",stopDrag);tl.addEventListener("pointercancel",stopDrag);tl.addEventListener("dragstart",function(e){e.preventDefault();});}function boot(){document.querySelectorAll("[data-rounds-timeline=\"1\"]").forEach(initTimelineDrag);}if(document.readyState==="loading"){document.addEventListener("DOMContentLoaded",boot);}else{boot();}})();</script>';
    }

    return $html;
}

// Function to get player nemesis (most duels with)
function getPlayerNemesis($db, $steamId) {
    $row = executeQuerySingle($db, "
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
    ", [$steamId, $steamId, $steamId, $steamId], 'ssss');

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
    // Debug: Log the SQL query being used
    error_log("DEBUG SQL: SELECT * FROM (
        SELECT
            '1v1' as type,
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
        FROM mgemod_duels
        WHERE (winner = '$steamId' OR loser = '$steamId') AND winner IS NOT NULL AND loser IS NOT NULL
        UNION ALL
        SELECT
            '2v2' as type,
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
        FROM mgemod_duels_2v2
        WHERE (winner = '$steamId' OR (winner2 IS NOT NULL AND winner2 = '$steamId') OR loser = '$steamId' OR (loser2 IS NOT NULL AND loser2 = '$steamId'))
          AND winner IS NOT NULL AND loser IS NOT NULL
    ) AS combined
    ORDER BY endtime DESC
    LIMIT $limit OFFSET $offset");

    $duels = executeQuery($db, "
        SELECT * FROM (
            SELECT
                '1v1' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels
            WHERE (winner = ? OR loser = ?) AND winner IS NOT NULL AND loser IS NOT NULL
            UNION ALL
            SELECT
                '2v2' as type,
                id, endtime, winner, loser, winnerclass, loserclass,
                winnerscore, loserscore, mapname, arenaname,
                winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
            FROM mgemod_duels_2v2
            WHERE (winner = ? OR (winner2 IS NOT NULL AND winner2 = ?) OR loser = ? OR (loser2 IS NOT NULL AND loser2 = ?))
              AND winner IS NOT NULL AND loser IS NOT NULL
        ) AS combined
        ORDER BY endtime DESC
        LIMIT ? OFFSET ?
    ", [$steamId, $steamId, $steamId, $steamId, $steamId, $steamId, $limit, $offset], 'ssssssii');

    // Debug: Log the raw results
    error_log("DEBUG: Raw duels count for $steamId: " . count($duels));
    foreach ($duels as $index => $duel) {
        error_log("DEBUG: Duel $index - Type: {$duel['type']}, ID: {$duel['id']}, Winner: {$duel['winner']}, Loser: {$duel['loser']}");
        if ($duel['type'] === '2v2') {
            error_log("DEBUG: 2v2 Duel $index - Winner2: {$duel['winner2']}, Loser2: {$duel['loser2']}");
        }
    }

    // Process duels to determine if the current player is the winner
    $processedDuels = processDuelWinners($duels, $steamId);

    // Debug: Log the processed results
    error_log("DEBUG: Processed duels count for $steamId: " . count($processedDuels));
    foreach ($processedDuels as $index => $duel) {
        error_log("DEBUG: Processed Duel $index - Type: {$duel['type']}, ID: {$duel['id']}, Is Winner: " . ($duel['is_winner'] ? 'YES' : 'NO'));
    }

    return $processedDuels;
}

// Function to get total count of MGE duels for a specific player
function getMGEDuelsCount($db, $steamId) {
    $row = executeQuerySingle($db, "
        SELECT SUM(duel_count) as total FROM (
            SELECT COUNT(*) as duel_count
            FROM mgemod_duels
            WHERE winner = ? OR loser = ?
            UNION ALL
            SELECT COUNT(*)
            FROM mgemod_duels_2v2
            WHERE winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?
        ) AS counts
    ", [$steamId, $steamId, $steamId, $steamId, $steamId, $steamId], 'ssssss');

    return $row ? $row['total'] : 0;
}

// Function to get the most recent duel for a player
function getLastDuelForPlayer($db, $steamId) {
    // Optimized: Get max endtime from both tables separately, then get the duel
    // This is faster than UNION with subquery and ORDER BY
    
    // Get most recent duel from 1v1
    $duel1v1 = executeQuerySingle($db, "
        SELECT
            '1v1' as type,
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
        FROM mgemod_duels
        WHERE (winner = ? OR loser = ?) AND winner IS NOT NULL AND loser IS NOT NULL
        ORDER BY endtime DESC
        LIMIT 1
    ", [$steamId, $steamId], 'ss');
    
    // Get most recent duel from 2v2
    $duel2v2 = executeQuerySingle($db, "
        SELECT
            '2v2' as type,
            id, endtime, winner, loser, winnerclass, loserclass,
            winnerscore, loserscore, mapname, arenaname,
            winner_new_elo, winner_previous_elo, loser_new_elo, loser_previous_elo
        FROM mgemod_duels_2v2
        WHERE (winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?)
          AND winner IS NOT NULL AND loser IS NOT NULL
        ORDER BY endtime DESC
        LIMIT 1
    ", [$steamId, $steamId, $steamId, $steamId], 'ssss');
    
    // Return the more recent duel
    if (!$duel1v1) return $duel2v2;
    if (!$duel2v2) return $duel1v1;
    
    return ($duel1v1['endtime'] >= $duel2v2['endtime']) ? $duel1v1 : $duel2v2;
}

function getClassIcon($className) {
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

    if (strpos($className, ',') !== false) {
        $classes = explode(',', $className);
        $icons = [];

        foreach ($classes as $class) {
            $class = strtolower(trim($class));
            if (isset($iconMap[$class])) {
                $icons[] = $iconMap[$class];
            }
        }

        return $icons;
    } else {
        $className = strtolower(trim($className));

        return isset($iconMap[$className]) ? $iconMap[$className] : 'default.png';
    }
}

// Function to get class icons for multiple classes
function getClassIconsHtml($classNamesStr, $size = "32") {
    $icons = getClassIcon($classNamesStr);

    if (is_array($icons)) {
        $html = '';
        foreach ($icons as $icon) {
            $html .= '<img src="tf_logo/' . $icon . '" class="class-icon" width="' . $size . '" height="' . $size . '" style="margin-right: 2px;">';
        }
        error_log("DEBUG getClassIconsHtml: Input: $classNamesStr, Output: $html");
        return $html;
    } else {
        $html = '<img src="tf_logo/' . $icons . '" class="class-icon" width="' . $size . '" height="' . $size . '">';
        error_log("DEBUG getClassIconsHtml: Input: $classNamesStr, Output: $html");
        return $html;
    }
}

// Function to get rating history for the last month
function getRatingHistory($db, $steamId, $days = 30) {
    $endDate = time();
    $startDate = $endDate - ($days * 24 * 60 * 60);

    $history = [];

    // Use COALESCE(new, previous) so old/partial rows are not dropped.
    $queries = [
        ['sql' => "SELECT endtime, COALESCE(winner_new_elo, winner_previous_elo) AS rating FROM mgemod_duels WHERE winner = ? AND endtime >= ? AND (winner_new_elo IS NOT NULL OR winner_previous_elo IS NOT NULL)", 'types' => 'si', 'params' => [$steamId, $startDate], 'label' => '1v1 wins'],
        ['sql' => "SELECT endtime, COALESCE(loser_new_elo, loser_previous_elo) AS rating FROM mgemod_duels WHERE loser = ? AND endtime >= ? AND (loser_new_elo IS NOT NULL OR loser_previous_elo IS NOT NULL)", 'types' => 'si', 'params' => [$steamId, $startDate], 'label' => '1v1 losses'],
        ['sql' => "SELECT endtime, COALESCE(winner_new_elo, winner_previous_elo) AS rating FROM mgemod_duels_2v2 WHERE winner = ? AND endtime >= ? AND (winner_new_elo IS NOT NULL OR winner_previous_elo IS NOT NULL)", 'types' => 'si', 'params' => [$steamId, $startDate], 'label' => '2v2 wins'],
        ['sql' => "SELECT endtime, COALESCE(winner2_new_elo, winner2_previous_elo) AS rating FROM mgemod_duels_2v2 WHERE winner2 = ? AND endtime >= ? AND (winner2_new_elo IS NOT NULL OR winner2_previous_elo IS NOT NULL)", 'types' => 'si', 'params' => [$steamId, $startDate], 'label' => '2v2 wins2'],
        ['sql' => "SELECT endtime, COALESCE(loser_new_elo, loser_previous_elo) AS rating FROM mgemod_duels_2v2 WHERE loser = ? AND endtime >= ? AND (loser_new_elo IS NOT NULL OR loser_previous_elo IS NOT NULL)", 'types' => 'si', 'params' => [$steamId, $startDate], 'label' => '2v2 losses'],
        ['sql' => "SELECT endtime, COALESCE(loser2_new_elo, loser2_previous_elo) AS rating FROM mgemod_duels_2v2 WHERE loser2 = ? AND endtime >= ? AND (loser2_new_elo IS NOT NULL OR loser2_previous_elo IS NOT NULL)", 'types' => 'si', 'params' => [$steamId, $startDate], 'label' => '2v2 losses2'],
    ];

    foreach ($queries as $q) {
        $rows = executeQuery($db, $q['sql'], $q['params'], $q['types']);
        $count = 0;

        foreach ((array)$rows as $row) {
            if (!isset($row['rating']) || $row['rating'] === null) {
                continue;
            }

            $row['rating'] = (int)$row['rating'];
            $row['endtime'] = (int)$row['endtime'];
            $row['date_ts'] = strtotime(date('Y-m-d', $row['endtime']));
            $history[] = $row;
            $count++;
        }

        error_log($q['label'] . " query for $steamId: $count records");
    }

    // If no valid ELO rows exist in duels for this period, keep chart alive with current rating.
    if (empty($history)) {
        $current = executeQuerySingle($db, "SELECT rating FROM mgemod_stats WHERE steamid = ? AND rating IS NOT NULL LIMIT 1", [$steamId], 's');
        if ($current && isset($current['rating']) && $current['rating'] !== null) {
            $history[] = [
                'endtime' => $endDate,
                'rating' => (int)$current['rating'],
                'date_ts' => strtotime(date('Y-m-d', $endDate)),
                'synthetic' => 1
            ];
            error_log("Rating history fallback for $steamId: synthetic point added");
        }
    }

    error_log("Total rating history records for $steamId: " . count($history));

    usort($history, function($a, $b) {
        return ((int)$a['endtime']) - ((int)$b['endtime']);
    });

    return $history;
}

// Function to get total statistics
function getTotalStats($db) {
    $stats = [];

    // Total duels
    $row = executeQuerySingle($db, "SELECT COUNT(*) as total FROM mgemod_duels");
    $stats['total_duels'] = $row ? ($row['total'] ?? 0) : 0;

    // Total 2v2 duels
    $row = executeQuerySingle($db, "SELECT COUNT(*) as total FROM mgemod_duels_2v2");
    $stats['total_duels_2v2'] = $row ? ($row['total'] ?? 0) : 0;

    // Total players
    $row = executeQuerySingle($db, "SELECT COUNT(*) as total FROM mgemod_stats");
    $stats['total_players'] = $row ? ($row['total'] ?? 0) : 0;

    // Highest rating
    $row = executeQuerySingle($db, "SELECT MAX(rating) as max_rating FROM mgemod_stats");
    $stats['highest_rating'] = $row ? ($row['max_rating'] ?? 0) : 0;

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

        // Get sort parameters
        $duelOrderBy = trim(strtolower($_GET['duel_sort_by'] ?? 'endtime'));
        $duelOrderDir = trim(strtoupper($_GET['duel_sort_dir'] ?? 'DESC'));

        // Validate duel sort parameters
        $allowedDuelFields = ['endtime', 'id', 'winnerscore', 'loserscore'];
        if (!in_array($duelOrderBy, $allowedDuelFields)) {
            $duelOrderBy = 'endtime';
        }
        $duelOrderDir = $duelOrderDir === 'ASC' ? 'ASC' : 'DESC';

        $duels = getRecentDuels($db, $limit, $offset, $duelOrderBy, $duelOrderDir);
        $totalDuels = getTotalDuelsCount($db);
        $totalPages = ceil($totalDuels / $limit);

        foreach ($duels as &$duel) {
            $winnerNick = getPlayerNickname($db, $duel['winner']);
            $loserNick = getPlayerNickname($db, $duel['loser']);
            $duel['winner_nick'] = $winnerNick;
            $duel['loser_nick'] = $loserNick;

            $duel['winner_class_html'] = !empty($duel['winnerclass']) ? getClassIconsHtml($duel['winnerclass'], "38") : '<span class="no-class">-</span>';
            $duel['loser_class_html'] = !empty($duel['loserclass']) ? getClassIconsHtml($duel['loserclass'], "38") : '<span class="no-class">-</span>';

            if (isset($duel['winner2']) && $duel['winner2']) {
                $winner2Nick = getPlayerNickname($db, $duel['winner2']);
                $loser2Nick = getPlayerNickname($db, $duel['loser2']);
                $duel['winner2_nick'] = $winner2Nick;
                $duel['loser2_nick'] = $loser2Nick;

                $duel['winner2_class_html'] = !empty($duel['winner2class']) ? getClassIconsHtml($duel['winner2class'], "38") : '<span class="no-class">-</span>';
                $duel['loser2_class_html'] = !empty($duel['loser2class']) ? getClassIconsHtml($duel['loser2class'], "38") : '<span class="no-class">-</span>';
            }
        }

        error_log("DEBUG AJAX: Sending duels data: " . json_encode(array_slice($duels, 0, 2)));

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
        $orderBy = trim(strtolower($_GET['sort_by'] ?? 'rating'));
        $orderDir = trim(strtoupper($_GET['sort_dir'] ?? 'DESC'));

        // Validate sort parameters to prevent SQL injection
        list($orderBy, $orderDir) = validateSortParams($orderBy, $orderDir);

        // Debug: Check if debug mode is enabled
        if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
            echo "<h3>" . htmlspecialchars(t('debug_search_title'), ENT_QUOTES, "UTF-8") . "</h3>";
            echo "<p>" . htmlspecialchars(t('debug_search_query'), ENT_QUOTES, "UTF-8") . ": " . htmlspecialchars($query) . "</p>";

            // Check if the player exists in the database with exact match
            $checkStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE name = ?");
            $checkStmt->bind_param('s', $query);
            $checkStmt->execute();
            $checkResult = $checkStmt->get_result();
            $exactMatch = $checkResult->fetch_assoc();
            $checkStmt->close();

            if ($exactMatch) {
                echo "<p>" . htmlspecialchars(t('debug_exact_match_found'), ENT_QUOTES, "UTF-8") . ": " . htmlspecialchars($exactMatch['name']) . " (" . htmlspecialchars($exactMatch['steamid']) . ")</p>";
            } else {
                echo "<p>" . htmlspecialchars(t('debug_exact_match_not_found'), ENT_QUOTES, "UTF-8") . "</p>";
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
                echo "<p>" . htmlspecialchars(t('debug_partial_matches_found'), ENT_QUOTES, "UTF-8") . ": " . count($partialMatches) . "</p>";
                foreach ($partialMatches as $match) {
                    echo "<p>- " . htmlspecialchars($match['name']) . " (" . htmlspecialchars($match['steamid']) . ")</p>";
                }
            } else {
                echo "<p>" . htmlspecialchars(t('debug_partial_matches_not_found'), ENT_QUOTES, "UTF-8") . "</p>";
            }

            // Check for case-insensitive match
            $checkCaseStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE LOWER(name) = LOWER(?)");
            $checkCaseStmt->bind_param('s', $query);
            $checkCaseStmt->execute();
            $checkCaseResult = $checkCaseStmt->get_result();
            $caseMatch = $checkCaseResult->fetch_assoc();
            $checkCaseStmt->close();

            if ($caseMatch) {
                echo "<p>" . htmlspecialchars(t('debug_case_match_found'), ENT_QUOTES, "UTF-8") . ": " . htmlspecialchars($caseMatch['name']) . " (" . htmlspecialchars($caseMatch['steamid']) . ")</p>";
            } else {
                echo "<p>" . htmlspecialchars(t('debug_case_match_not_found'), ENT_QUOTES, "UTF-8") . "</p>";
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
    $orderBy = trim(strtolower($_GET['sort_by'] ?? 'rating'));
    $orderDir = trim(strtoupper($_GET['sort_dir'] ?? 'DESC'));
    $limit = 25;
    $offset = ($page - 1) * $limit;

    // Validate sort parameters to prevent SQL injection
    list($orderBy, $orderDir) = validateSortParams($orderBy, $orderDir);

    // Get total count for pagination
    $totalCount = executeCountQuery($db, "SELECT COUNT(*) as total FROM mgemod_stats ms WHERE ms.rating IS NOT NULL");

    // Special handling for 'last_duel' sort
    if ($orderBy === 'last_duel') {
        $sql = "
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
                   COALESCE(
                       GREATEST(
                           (SELECT MAX(endtime) FROM mgemod_duels WHERE winner = ms.steamid OR loser = ms.steamid),
                           (SELECT MAX(endtime) FROM mgemod_duels_2v2 WHERE winner = ms.steamid OR winner2 = ms.steamid OR loser = ms.steamid OR loser2 = ms.steamid)
                       ), 0
                   ) as last_duel_time_val
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY last_duel_time_val {$orderDir}
            LIMIT ? OFFSET ?
        ";
        
        $stmt = $db->prepare($sql);
        $stmt->bind_param('ii', $limit, $offset);
        $stmt->execute();
        $result = $stmt->get_result();
        $players = $result->fetch_all(MYSQLI_ASSOC);
        $stmt->close();
    }
    // Special handling for 'winrate' sort
    else if ($orderBy === 'winrate') {
        // For winrate sorting, we need to calculate winrate in the query
        $stmt = $db->prepare("
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
                   CASE
                       WHEN (ms.wins + ms.losses) > 0 THEN ROUND((ms.wins / (ms.wins + ms.losses)) * 100, 2)
                       ELSE 0
                   END as winrate_calc
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY winrate_calc {$orderDir}
            LIMIT ? OFFSET ?
        ");
    } else {
        $stmt = $db->prepare("
            SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
            FROM mgemod_stats ms
            WHERE ms.rating IS NOT NULL
            ORDER BY ms.{$orderBy} {$orderDir}
            LIMIT ? OFFSET ?
        ");
    }

    $players = [];
    if ($orderBy !== 'last_duel') {
        if ($stmt) {
            $stmt->bind_param('ii', $limit, $offset);
            $stmt->execute();
            $result = $stmt->get_result();
            $players = $result->fetch_all(MYSQLI_ASSOC);
            $stmt->close();
        }
    }

    $totalPages = ceil($totalCount / $limit);

    foreach ($players as &$player) {
        $player['nick'] = $player['name'] ?: $player['steamid'];

        // If we're sorting by winrate, use the calculated value from the query
        if ($orderBy === 'winrate' && isset($player['winrate_calc'])) {
            $player['winrate'] = $player['winrate_calc'];
        } else {
            // Otherwise calculate winrate as before
            $winrate = ($player['wins'] + $player['losses']) > 0 ?
                round(($player['wins'] / ($player['wins'] + $player['losses'])) * 100, 2) : 0;
            $player['winrate'] = $winrate;
        }

        // Get the most recent duel for this player
        $lastDuel = getLastDuelForPlayer($db, $player['steamid']);
        $player['last_duel_time'] = $lastDuel ? date('d.m.Y H:i', $lastDuel['endtime']) : t('no_data');

        // Add last duel time value for sorting if needed
        if ($orderBy === 'last_duel') {
            $player['last_duel_time_val'] = $player['last_duel_time_val'] ?? 0;
        }
    }

    echo json_encode([
        'players' => $players,
        'current_page' => $page,
        'total_pages' => $totalPages,
        'total_players' => $totalCount
    ]);
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

        // Debug: Log the duels before adding nicknames
        error_log("DEBUG AJAX: Before adding nicknames, duels count: " . count($duels));
        foreach ($duels as $index => $duel) {
            error_log("DEBUG AJAX: Pre-nickname duel $index - Type: {$duel['type']}, ID: {$duel['id']}, Winner: {$duel['winner']}, Loser: {$duel['loser']}, Is Winner: " . ($duel['is_winner'] ? 'YES' : 'NO'));
        }

        foreach ($duels as &$duel) {
            $winnerNick = getPlayerNickname($db, $duel['winner']);
            $loserNick = getPlayerNickname($db, $duel['loser']);
            $duel['winner_nick'] = $winnerNick;
            $duel['loser_nick'] = $loserNick;

            $duel['winnerclass_html'] = !empty($duel['winnerclass']) ? getClassIconsHtml($duel['winnerclass'], "32") : '<span class="no-class">-</span>';
            $duel['loserclass_html'] = !empty($duel['loserclass']) ? getClassIconsHtml($duel['loserclass'], "32") : '<span class="no-class">-</span>';

            if (isset($duel['winner2']) && $duel['winner2']) {
                $winner2Nick = getPlayerNickname($db, $duel['winner2']);
                $loser2Nick = getPlayerNickname($db, $duel['loser2']);
                $duel['winner2_nick'] = $winner2Nick;
                $duel['loser2_nick'] = $loser2Nick;

                $duel['winner2class_html'] = !empty($duel['winner2class']) ? getClassIconsHtml($duel['winner2class'], "32") : '<span class="no-class">-</span>';
                $duel['loser2class_html'] = !empty($duel['loser2class']) ? getClassIconsHtml($duel['loser2class'], "32") : '<span class="no-class">-</span>';
            }
        }

        // Debug: Log the duels after adding nicknames (this is what gets sent to browser)
        error_log("DEBUG AJAX: After adding nicknames, duels count: " . count($duels));
        foreach ($duels as $index => $duel) {
            error_log("DEBUG AJAX: Final duel $index - Type: {$duel['type']}, ID: {$duel['id']}, Winner: {$duel['winner_nick']}, Loser: {$duel['loser_nick']}, Is Winner: " . ($duel['is_winner'] ? 'YES' : 'NO'));
        }

        echo json_encode([
            'duels' => $duels,
            'current_page' => $page,
            'total_pages' => $totalPages,
            'total_duels' => $totalDuels
        ]);
        exit;
    }

    if ($_GET['ajax'] === 'get_player_nickname') {
        $steamId = sanitizeInput($_GET['steam_id'] ?? '');

        if (empty($steamId)) {
            http_response_code(400);
            echo htmlspecialchars(t('error_invalid_steamid'), ENT_QUOTES, "UTF-8");
            exit;
        }

        $nickname = getPlayerNickname($db, $steamId);
        echo htmlspecialchars($nickname, ENT_QUOTES, 'UTF-8');
        exit;
    }

    if ($_GET['ajax'] === 'get_daily_duels') {
        header('Content-Type: application/json; charset=utf-8');
        $steamId = sanitizeInput($_GET['steam_id'] ?? '');
        $date = sanitizeInput($_GET['date'] ?? '');

        if (empty($steamId)) {
            http_response_code(400);
            echo json_encode(['error' => t('error_invalid_steamid')]);
            exit;
        }

        // Validate date format
        if (!strtotime($date)) {
            http_response_code(400);
            echo json_encode(['error' => t('error_invalid_date_format')]);
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

        if (!$stmt) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to prepare daily duels query']);
            exit;
        }

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
            'label' => t('js_duels'),
            'data' => array_values($hourlyCounts),
            'borderColor' => 'rgb(74, 222, 128)',
            'backgroundColor' => 'rgba(74, 222, 128, 0.1)',
            'tension' => 0.4,
            'fill' => true
        ];

        $payload = json_encode([
            'labels' => $labels,
            'datasets' => [$dataset]
        ], JSON_UNESCAPED_UNICODE);

        if ($payload === false) {
            http_response_code(500);
            echo json_encode(['error' => 'JSON encode failed: ' . json_last_error_msg()], JSON_UNESCAPED_UNICODE);
            exit;
        }

        if (ob_get_length()) {
            ob_clean();
        }

        echo $payload;
        exit;
    }

    if ($_GET['ajax'] === 'get_activity_heatmap') {
        header('Content-Type: application/json; charset=utf-8');
        $steamId = sanitizeInput($_GET['steam_id'] ?? '');
        $year = (int)$_GET['year'];

        if (!$steamId || !$year) {
            http_response_code(400);
            echo json_encode(['error' => t('error_missing_steam_year')]);
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

        if (!$stmt) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to prepare activity query'], JSON_UNESCAPED_UNICODE);
            exit;
        }

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
        if (!$stmtYears) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to prepare activity years query'], JSON_UNESCAPED_UNICODE);
            exit;
        }

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
        <div class="flex-gap-16">
            <div class="calendar-graph-full-width">
                <svg width="<?= $svgWidth ?>" height="<?= $svgHeight ?>" class="js-calendar-graph-svg">
                    <!-- Month labels -->
                    <g transform="translate(36, 12)" font-size="11" fill="#7d8590">
                        <?php foreach ($months as $monthNum => $monthData): ?>
                            <text x="<?= $monthData['x'] ?>" y="0"><?= $monthData['name'] ?></text>
                        <?php endforeach; ?>
                    </g>

                    <!-- Day of week labels -->
                    <g transform="translate(0, 28)" font-size="10" fill="#7d8590">
                        <text x="0" y="26"><?= htmlspecialchars(t('weekday_mon_short'), ENT_QUOTES, 'UTF-8') ?></text>
                        <text x="0" y="56"><?= htmlspecialchars(t('weekday_wed_short'), ENT_QUOTES, 'UTF-8') ?></text>
                        <text x="0" y="86"><?= htmlspecialchars(t('weekday_fri_short'), ENT_QUOTES, 'UTF-8') ?></text>
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

                            echo '<rect class="day" width="'.$cellWidth.'" height="'.$cellWidth.'" x="'.$pos['x'].'" y="'.$pos['y'].'" fill="'.$color.'" data-count="'.$count.'" data-date="'.$dateStr.'" rx="2" ry="2" onclick="showDailyDuelsChart(\''.$dateStr.'\')"><title>'.$dateStr.': '.htmlspecialchars(t('duels_count_short', ['count' => $count]), ENT_QUOTES, 'UTF-8').'</title></rect>'; 
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

        <div class="margin-top-12-flex">
            <span><?= htmlspecialchars(t('less_label'), ENT_QUOTES, 'UTF-8') ?></span>
            <div class="color-box-14x14 bg-dark-calendar"></div>
            <div class="color-box-14x14 bg-green-light"></div>
            <div class="color-box-14x14 bg-green-medium"></div>
            <div class="color-box-14x14 bg-green-bright"></div>
            <div class="color-box-14x14 bg-green-highlight"></div>
            <span><?= htmlspecialchars(t('more_label'), ENT_QUOTES, 'UTF-8') ?></span>
        </div>
        <?php
        $heatmapHtml = ob_get_clean();

        $payload = json_encode([
            'heatmap_html' => $heatmapHtml,
            'year' => $year,
            'available_years' => $availableYears
        ], JSON_UNESCAPED_UNICODE);

        if ($payload === false) {
            http_response_code(500);
            echo json_encode(['error' => 'JSON encode failed: ' . json_last_error_msg()], JSON_UNESCAPED_UNICODE);
            exit;
        }

        if (ob_get_length()) {
            ob_clean();
        }

        echo $payload;
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
        AND mapname = '???????????'
        AND arenaname LIKE '??????%'
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
    $classKey = 'class_' . strtolower((string)$className);
    $translated = t($classKey);
    if ($translated !== $classKey) {
        return $translated;
    }

    return ucfirst((string)$className);
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
$orderBy = trim(strtolower($_GET['sort_by'] ?? 'rating'));
$orderDir = trim(strtoupper($_GET['sort_dir'] ?? 'DESC'));

// DEBUG: Show raw values in HTML
echo "<!-- DEBUG PHP RAW: orderBy=$orderBy, orderDir=$orderDir, REQUEST_URI=" . $_SERVER['REQUEST_URI'] . " -->\n";

// Validate sort parameters to prevent SQL injection
$allowedFields = ['rating', 'wins', 'losses', 'winrate', 'last_duel'];
if (!in_array($orderBy, $allowedFields)) {
    $orderBy = 'rating';
}
$orderDir = strtoupper($orderDir) === 'ASC' ? 'ASC' : 'DESC';

// Handle profile view
$viewProfile = isset($_GET['profile']) ? $_GET['profile'] : null;

// Handle search
$searchQuery = isset($_GET['search']) ? sanitizeInput(trim($_GET['search'])) : '';
$searchResults = [];

if ($searchQuery) {
    // Debug: Check if debug mode is enabled
    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
        echo "<h3>" . htmlspecialchars(t('debug_regular_search_title'), ENT_QUOTES, "UTF-8") . "</h3>";
        echo "<p>" . htmlspecialchars(t('debug_search_query'), ENT_QUOTES, "UTF-8") . ": " . htmlspecialchars($searchQuery) . "</p>";

        // Check if the player exists in the database with exact match
        $checkStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE name = ?");
        $checkStmt->bind_param('s', $searchQuery);
        $checkStmt->execute();
        $checkResult = $checkStmt->get_result();
        $exactMatch = $checkResult->fetch_assoc();
        $checkStmt->close();

        if ($exactMatch) {
            echo "<p>" . htmlspecialchars(t('debug_exact_match_found'), ENT_QUOTES, "UTF-8") . ": " . htmlspecialchars($exactMatch['name']) . " (" . htmlspecialchars($exactMatch['steamid']) . ")</p>";
        } else {
            echo "<p>" . htmlspecialchars(t('debug_exact_match_not_found'), ENT_QUOTES, "UTF-8") . "</p>";
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
            echo "<p>" . htmlspecialchars(t('debug_partial_matches_found'), ENT_QUOTES, "UTF-8") . ": " . count($partialMatches) . "</p>";
            foreach ($partialMatches as $match) {
                echo "<p>- " . htmlspecialchars($match['name']) . " (" . htmlspecialchars($match['steamid']) . ")</p>";
            }
        } else {
            echo "<p>" . htmlspecialchars(t('debug_partial_matches_not_found'), ENT_QUOTES, "UTF-8") . "</p>";
        }

        // Check for case-insensitive match
        $checkCaseStmt = $db->prepare("SELECT name, steamid FROM mgemod_stats WHERE LOWER(name) = LOWER(?)");
        $checkCaseStmt->bind_param('s', $searchQuery);
        $checkCaseStmt->execute();
        $checkCaseResult = $checkCaseStmt->get_result();
        $caseMatch = $checkCaseResult->fetch_assoc();
        $checkCaseStmt->close();

        if ($caseMatch) {
            echo "<p>" . htmlspecialchars(t('debug_case_match_found'), ENT_QUOTES, "UTF-8") . ": " . htmlspecialchars($caseMatch['name']) . " (" . htmlspecialchars($caseMatch['steamid']) . ")</p>";
        } else {
            echo "<p>" . htmlspecialchars(t('debug_case_match_not_found'), ENT_QUOTES, "UTF-8") . "</p>";
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
// Special handling for 'last_duel' sort
if ($orderBy === 'last_duel') {
    $sql = "
        SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name
        FROM mgemod_stats ms
        WHERE ms.rating IS NOT NULL
        ORDER BY ms.rating {$orderDir}
        LIMIT ? OFFSET ?
    ";
    
    $stmt = $db->prepare($sql);
    $stmt->bind_param('ii', $limit, $offset);
    $stmt->execute();
    $result = $stmt->get_result();
    $topPlayers = $result->fetch_all(MYSQLI_ASSOC);
    $stmt->close();
    
    foreach ($topPlayers as &$player) {
        $steamId = $player['steamid'];
        
        $lastDuelSql = "
            SELECT MAX(endtime) as last_duel_time FROM (
                SELECT MAX(endtime) as endtime FROM mgemod_duels WHERE winner = ? OR loser = ?
                UNION ALL
                SELECT MAX(endtime) FROM mgemod_duels_2v2 WHERE winner = ? OR winner2 = ? OR loser = ? OR loser2 = ?
            ) as t
        ";
        
        $stmt2 = $db->prepare($lastDuelSql);
        $stmt2->bind_param('ssssss', $steamId, $steamId, $steamId, $steamId, $steamId, $steamId);
        $stmt2->execute();
        $result2 = $stmt2->get_result();
        $row = $result2->fetch_assoc();
        $player['last_duel_time_val'] = $row['last_duel_time'] ?? 0;
        $stmt2->close();
    }
    
    usort($topPlayers, function($a, $b) use ($orderDir) {
        $aTime = $a['last_duel_time_val'] ?? 0;
        $bTime = $b['last_duel_time_val'] ?? 0;
        
        if ($orderDir === 'ASC') {
            return $aTime <=> $bTime;
        } else {
            return $bTime <=> $aTime;
        }
    });
}
// Special handling for 'winrate' sort
else if ($orderBy === 'winrate') {
    // For winrate sorting, we need to calculate winrate in the query
    $stmt = $db->prepare("
        SELECT ms.steamid, ms.rating, ms.wins, ms.losses, ms.name,
               CASE
                   WHEN (ms.wins + ms.losses) > 0 THEN ROUND((ms.wins / (ms.wins + ms.losses)) * 100, 2)
                   ELSE 0
               END as winrate_calc
        FROM mgemod_stats ms
        WHERE ms.rating IS NOT NULL
        ORDER BY winrate_calc {$orderDir}
        LIMIT ? OFFSET ?
    ");
    
    if ($stmt) {
        $stmt->bind_param('ii', $limit, $offset);
        $stmt->execute();
        $result = $stmt->get_result();
        $topPlayers = $result->fetch_all(MYSQLI_ASSOC);
        $stmt->close();
    } else {
        $topPlayers = [];
    }
} else {
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
    } else {
        $topPlayers = [];
    }
}

// Get total count for players pagination
$totalPlayers = executeCountQuery($db, "SELECT COUNT(*) as total FROM mgemod_stats ms WHERE ms.rating IS NOT NULL");
$totalPagesPlayers = ceil($totalPlayers / $limit);

$totalStats = getTotalStats($db);

// Pagination for recent duels
$duelLimit = 10;
$duelOffset = ($page - 1) * $duelLimit;

// Get sorting parameters for duels
$duelOrderBy = trim(strtolower($_GET['duel_sort_by'] ?? 'endtime'));
$duelOrderDir = trim(strtoupper($_GET['duel_sort_dir'] ?? 'DESC'));

// Validate duel sort parameters
$allowedDuelFields = ['endtime', 'id', 'winnerscore', 'loserscore'];
if (!in_array($duelOrderBy, $allowedDuelFields)) {
    $duelOrderBy = 'endtime';
}
$duelOrderDir = $duelOrderDir === 'ASC' ? 'ASC' : 'DESC';

$recentDuels = getRecentDuels($db, $duelLimit, $duelOffset, $duelOrderBy, $duelOrderDir);
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
    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
        echo "<!-- Raw rating history data: ";
        var_dump($profileRatingHistory);
        echo " -->";
    }

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

    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
        echo "<!-- Profile data rating_history: ";
        var_dump($profileData['rating_history']);
        echo " -->";
    }
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
<html lang="<?= htmlspecialchars($MGE_LANG, ENT_QUOTES, 'UTF-8') ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php
        if ($viewDuel) echo t('site_title_duel', ['id' => $viewDuel]);
        elseif ($viewProfile) echo t('site_title_profile', ['name' => (string)($profileData['name'] ?? '')]);
        else echo t('site_title_main');
    ?></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="css/styles.css">
    <link rel="stylesheet" href="css/profile.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-zoom@latest/dist/chartjs-plugin-zoom.min.js"></script>
    <script src="js/profile.js" defer></script>
</head>
<body>
    <div class="loading-overlay" id="loadingOverlay">
        <div class="loading-content">
            <div class="loading-spinner"></div>
            <p><?= htmlspecialchars(t('loading_data'), ENT_QUOTES, 'UTF-8') ?></p>
        </div>
    </div>

    <div class="container">
        <div class="header">
            <h1><i class="fas fa-chart-line"></i> <?= htmlspecialchars(t('header_title'), ENT_QUOTES, 'UTF-8') ?></h1>
            <p><?= htmlspecialchars(t('header_subtitle'), ENT_QUOTES, 'UTF-8') ?></p>

            <details class="lang-menu" role="group" aria-label="<?= htmlspecialchars(t('lang_switch_aria'), ENT_QUOTES, 'UTF-8') ?>">
                <summary>
                    <img class="flag-img" src="<?= $MGE_LANG === 'ru' ? 'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/svg/1f1f7-1f1fa.svg' : 'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/svg/1f1fa-1f1f8.svg' ?>" alt="" aria-hidden="true" style="width:16px;height:12px;display:inline-block;border-radius:2px;border:1px solid rgba(255,255,255,.35);vertical-align:middle;object-fit:cover;">
                    <span class="lang-menu-code"><?= strtoupper($MGE_LANG) ?></span>
                    <i class="fas fa-chevron-down lang-menu-caret" aria-hidden="true"></i>
                </summary>
                <div class="lang-menu-list">
                    <a href="<?= htmlspecialchars(mge_url_with_lang('ru'), ENT_QUOTES, 'UTF-8') ?>" class="lang-menu-item <?= $MGE_LANG === 'ru' ? 'active' : '' ?>">
                        <img class="flag-img" src="https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/svg/1f1f7-1f1fa.svg" alt="" aria-hidden="true" style="width:16px;height:12px;display:inline-block;border-radius:2px;border:1px solid rgba(255,255,255,.35);vertical-align:middle;object-fit:cover;">
                        <span>RU</span>
                    </a>
                    <a href="<?= htmlspecialchars(mge_url_with_lang('en'), ENT_QUOTES, 'UTF-8') ?>" class="lang-menu-item <?= $MGE_LANG === 'en' ? 'active' : '' ?>">
                        <img class="flag-img" src="https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/svg/1f1fa-1f1f8.svg" alt="" aria-hidden="true" style="width:16px;height:12px;display:inline-block;border-radius:2px;border:1px solid rgba(255,255,255,.35);vertical-align:middle;object-fit:cover;">
                        <span>EN</span>
                    </a>
                </div>
            </details>

            <div class="auth-section">
                <?php if ($isAuthenticated): ?>
                    <span class="player-name"><?= htmlspecialchars(t('welcome_player', ['name' => (string)($playerData['name'] ?? t('player_default_name'))]), ENT_QUOTES, 'UTF-8') ?></span>
                    <a href="?logout=1" class="btn btn-secondary">
                        <i class="fas fa-sign-out-alt"></i> <?= htmlspecialchars(t('btn_logout'), ENT_QUOTES, 'UTF-8') ?>
                    </a>
                    <?php if (!$viewProfile && !$viewDuel): ?>
                        <a href="?profile=<?= urlencode($playerData['steamid']) ?>" class="btn btn-outline">
                            <i class="fas fa-user"></i> <?= htmlspecialchars(t('btn_my_profile'), ENT_QUOTES, 'UTF-8') ?>
                        </a>
                    <?php endif; ?>
                <?php else: ?>
                    <a href="<?= getSteamLoginUrl() ?>" class="btn btn-primary">
                        <i class="fab fa-steam"></i> <?= htmlspecialchars(t('btn_login_steam'), ENT_QUOTES, 'UTF-8') ?>
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
            $backText = isset($_GET['profile']) ? t('btn_back_profile') : t('btn_back_stats');

            // ELO changes
            $winnerEloDiff = ($duelData['winner_new_elo'] ?? 0) - ($duelData['winner_previous_elo'] ?? 0);
            $loserEloDiff = ($duelData['loser_new_elo'] ?? 0) - ($duelData['loser_previous_elo'] ?? 0);
            $duelRoundsHtml = buildMgeRoundsHtmlSimple($duelData, $duelType);
            ?>
            <!-- Duel Page -->
            <div class="profile-back">
                <a href="<?= $backUrl ?>" class="btn btn-outline">
                    <i class="fas fa-arrow-left"></i> <?= htmlspecialchars($backText, ENT_QUOTES, 'UTF-8') ?>
                </a>
            </div>

            <div class="card">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-fist-raised"></i> <?= htmlspecialchars(t('duel_title', ['id' => $viewDuel]), ENT_QUOTES, 'UTF-8') ?></h2>
                    <span class="duel-timestamp"><?= date('d.m.Y H:i', $duelData['endtime']) ?> | <?= htmlspecialchars($duelData['mapname']) ?> | <?= htmlspecialchars($duelData['arenaname']) ?></span>
                </div>

                <div class="duel-page-content">
                    <!-- Main Duel Display -->
                    <div class="duel-versus-container">
                        <!-- Winner Side -->
                        <div class="duel-player-card winner">
                            <div class="duel-player-status"><?= htmlspecialchars(t('duel_status_win'), ENT_QUOTES, 'UTF-8') ?></div>
                            <a href="?profile=<?= urlencode($duelData['winner']) ?>" class="duel-player-avatar">
                                <img src="<?= $winnerAvatar ?>" alt="Winner Avatar">
                            </a>
                            <a href="?profile=<?= urlencode($duelData['winner']) ?>" class="duel-player-name"><?= htmlspecialchars($winnerNick) ?></a>
                            <div class="duel-player-class"><?= htmlspecialchars($duelData['winnerclass'] ?? t('unknown')) ?></div>
                            <div class="duel-player-elo">
                                <span class="elo-value"><?= $duelData['winner_new_elo'] ?? t('na') ?></span>
                                <span class="elo-change positive">+<?= $winnerEloDiff ?></span>
                            </div>
                            <?php if ($duelType === '2v2'): ?>
                            <div class="duel-teammate">
                                <a href="?profile=<?= urlencode($duelData['winner2']) ?>" class="teammate-avatar">
                                    <img src="<?= $winner2Avatar ?>" alt="Winner 2 Avatar">
                                </a>
                                <div class="teammate-info">
                                    <a href="?profile=<?= urlencode($duelData['winner2']) ?>" class="teammate-name"><?= htmlspecialchars($winner2Nick) ?></a>
                                    <span class="teammate-class"><?= htmlspecialchars($duelData['winner2class'] ?? t('unknown')) ?></span>
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
                            <div class="duel-player-status"><?= htmlspecialchars(t('duel_status_loss'), ENT_QUOTES, 'UTF-8') ?></div>
                            <a href="?profile=<?= urlencode($duelData['loser']) ?>" class="duel-player-avatar">
                                <img src="<?= $loserAvatar ?>" alt="Loser Avatar">
                            </a>
                            <a href="?profile=<?= urlencode($duelData['loser']) ?>" class="duel-player-name"><?= htmlspecialchars($loserNick) ?></a>
                            <div class="duel-player-class"><?= htmlspecialchars($duelData['loserclass'] ?? t('unknown')) ?></div>
                            <div class="duel-player-elo">
                                <span class="elo-value"><?= $duelData['loser_new_elo'] ?? t('na') ?></span>
                                <span class="elo-change negative"><?= $loserEloDiff ?></span>
                            </div>
                            <?php if ($duelType === '2v2'): ?>
                            <div class="duel-teammate">
                                <a href="?profile=<?= urlencode($duelData['loser2']) ?>" class="teammate-avatar">
                                    <img src="<?= $loser2Avatar ?>" alt="Loser 2 Avatar">
                                </a>
                                <div class="teammate-info">
                                    <a href="?profile=<?= urlencode($duelData['loser2']) ?>" class="teammate-name"><?= htmlspecialchars($loser2Nick) ?></a>
                                    <span class="teammate-class"><?= htmlspecialchars($duelData['loser2class'] ?? t('unknown')) ?></span>
                                </div>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
                <?= $duelRoundsHtml ?>
            </div>

        <?php elseif ($viewProfile && $profileData): ?>
            <!-- Profile View -->
            <div class="profile-back">
                <a href="<?= $_SERVER['PHP_SELF'] ?>" class="btn btn-outline">
                    <i class="fas fa-arrow-left"></i> <?= htmlspecialchars(t('btn_back_stats'), ENT_QUOTES, 'UTF-8') ?>
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
                            <div class="profile-stat-value profile-stat-value-colored"><?= $profileData['rating'] !== null ? $profileData['rating'] : t('na') ?></div>
                            <div class="profile-stat-label"><?= htmlspecialchars(t('profile_rating'), ENT_QUOTES, 'UTF-8') ?></div>
                        </div>

                        <div class="profile-stat-card">
                            <div class="profile-stat-value profile-stat-value-success"><?= $profileData['stats']['wins'] ?></div>
                            <div class="profile-stat-label"><?= htmlspecialchars(t('profile_wins'), ENT_QUOTES, 'UTF-8') ?></div>
                        </div>

                        <div class="profile-stat-card">
                            <div class="profile-stat-value profile-stat-value-danger"><?= $profileData['stats']['losses'] ?></div>
                            <div class="profile-stat-label"><?= htmlspecialchars(t('profile_losses'), ENT_QUOTES, 'UTF-8') ?></div>
                        </div>

                        <div class="profile-stat-card">
                            <div class="profile-stat-value profile-stat-value-warning"><?= $profileData['stats']['winrate'] ?>%</div>
                            <div class="profile-stat-label"><?= htmlspecialchars(t('profile_winrate'), ENT_QUOTES, 'UTF-8') ?></div>
                        </div>
                    </div>
                </div>
            </div>

            <?php if ($profileData['nemesis']): ?>
                <div class="nemesis-info">
                    <h3><i class="fas fa-skull-crossbones"></i> <?= htmlspecialchars(t('nemesis_title'), ENT_QUOTES, 'UTF-8') ?></h3>
                    <p>
                        <a href="?profile=<?= urlencode($profileData['nemesis']['steamid']) ?>" class="nemesis-link">
                            <?= htmlspecialchars($profileData['nemesis']['nick']) ?> (<?= $profileData['nemesis']['steamid'] ?>)
                        </a>
                        - <?= htmlspecialchars(t('nemesis_meetings', ['count' => (int)$profileData['nemesis']['duels_count']]), ENT_QUOTES, 'UTF-8') ?>
                    </p>
                </div>
            <?php endif; ?>

            <?php
            // Debug output to see what rating history data we have
            if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
                echo "<!-- Rating history data: ";
                var_dump($profileData['rating_history']);
                echo " -->";
            }
            ?>
            <!-- DEBUG: Checking rating history -->
            <?php
            $hasRatingHistory = !empty($profileData['rating_history']);
            if (isset($_GET['debug']) && $_GET['debug'] === 'true'):
            ?>
                <p class="debug-cyan">DEBUG: Has rating history: <?php echo $hasRatingHistory ? 'YES' : 'NO'; ?></p>
                <p class="debug-cyan">DEBUG: Rating history count: <?php echo count($profileData['rating_history'] ?? []); ?></p>
            <?php endif; ?>

            <?php if ($hasRatingHistory): ?>
                <div class="margin-top-20-div">
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-chart-line"></i> <?= htmlspecialchars(t('rating_history_title'), ENT_QUOTES, 'UTF-8') ?></h2>
                        </div>
                        <div class="chart-container chart-container-height">
                            <canvas id="ratingChart"></canvas>
                        </div>
                    </div>
                </div>
            <?php else: ?>
                <!-- Rating history is empty, showing message for debugging -->
                <?php if (isset($_GET['debug']) && $_GET['debug'] === 'true'): ?>
                    <p style="color: orange; margin-top: 20px;">DEBUG: No rating history data available for this player</p>
                <?php endif; ?>
            <?php endif; ?>

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
            <div class="card card-margin-top-20">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-chess-board"></i> <?= htmlspecialchars(t('matchup_title'), ENT_QUOTES, 'UTF-8') ?></h2>
                </div>

                <div class="flex-stretch-gap-20">
                    <div class="flex-1-min-width">
                        <div class="overflow-hidden-width">
                            <table id="matchupHeatmap" class="table-fixed-layout">
                                <thead>
                                    <tr>
                                        <th class="th-transparent"></th>
                                        <?php foreach ($classOrder as $oppClass): ?>
                                            <?php $iconPath = getClassIconPath($oppClass); ?>
                                            <th class="th-middle-align">
                                                <?php if ($iconPath): ?>
                                                    <img src="tf_logo/<?= htmlspecialchars($iconPath) ?>"
                                                         alt="<?= htmlspecialchars($oppClass) ?>"
                                                         class="img-center-block">
                                                <?php else: ?>
                                                    <span class="small-font-gray"><?= htmlspecialchars(substr($oppClass, 0, 1)) ?></span>
                                                <?php endif; ?>
                                            </th>
                                        <?php endforeach; ?>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($classOrder as $myClass): ?>
                                        <?php $iconPath = getClassIconPath($myClass); ?>
                                        <tr>
                                            <td class="td-middle-align">
                                                <?php if ($iconPath): ?>
                                                    <img src="tf_logo/<?= htmlspecialchars($iconPath) ?>"
                                                         alt="<?= htmlspecialchars($myClass) ?>"
                                                         class="img-center-block-24">
                                                <?php else: ?>
                                                    <span class="small-font-gray"><?= htmlspecialchars(substr($myClass, 0, 1)) ?></span>
                                                <?php endif; ?>
                                            </td>
                                            <?php foreach ($classOrder as $oppClass): ?>
                                                <?php
                                                $rating = $matchupRatings[$myClass][$oppClass];
                                                $color = getRatingColor($rating);
                                                $label = $rating > 2000 ? t('rating_highest') : ($rating > 1700 ? t('rating_high') : ($rating >= 1500 ? t('rating_medium') : ($rating > 1000 ? t('rating_low') : t('rating_lowest'))));



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
                    <div id="matchupDetailsPanel" class="matchup-details-panel">
                        <div class="matchup-details-header"><?= htmlspecialchars(t('matchup_details_title'), ENT_QUOTES, 'UTF-8') ?></div>
                        <div id="matchupDetailsContent" class="matchup-details-content">
                            <div class="matchup-details-placeholder">
                                <div class="matchup-details-placeholder-text">
                                    <?= htmlspecialchars(t('matchup_details_empty'), ENT_QUOTES, 'UTF-8') ?>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                <div id="matchupTooltip" class="matchup-tooltip">
                </div>
                <div class="legend-flex-wrap">
                    <div class="legend-item-flex">
                        <div class="legend-color-box legend-very-high"></div>
                        <span class="text-color-ccc"><?= htmlspecialchars(t('rating_highest'), ENT_QUOTES, 'UTF-8') ?> (&gt;2000)</span>
                    </div>
                    <div class="legend-item-flex">
                        <div class="legend-color-box legend-high"></div>
                        <span class="text-color-ccc"><?= htmlspecialchars(t('rating_high'), ENT_QUOTES, 'UTF-8') ?> (1700-2000)</span>
                    </div>
                    <div class="legend-item-flex">
                        <div class="legend-color-box legend-medium"></div>
                        <span class="text-color-ccc"><?= htmlspecialchars(t('rating_medium'), ENT_QUOTES, 'UTF-8') ?> (1500-1700)</span>
                    </div>
                    <div class="legend-item-flex">
                        <div class="legend-color-box legend-low"></div>
                        <span class="text-color-ccc"><?= htmlspecialchars(t('rating_low'), ENT_QUOTES, 'UTF-8') ?> (1000-1500)</span>
                    </div>
                    <div class="legend-item-flex">
                        <div class="legend-color-box legend-very-low"></div>
                        <span class="text-color-ccc"><?= htmlspecialchars(t('rating_lowest'), ENT_QUOTES, 'UTF-8') ?> (&lt;1000)</span>
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
            <div class="card card-margin-top-20">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-fire"></i> <?= htmlspecialchars(t('activity_title'), ENT_QUOTES, 'UTF-8') ?></h2>
                </div>

                <div class="activity-heatmap-container-full-width">
                    <div class="flex-start-align">
                        <div class="calendar-full-width-alt">
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
                                <text x="0" y="26"><?= htmlspecialchars(t('weekday_mon_short'), ENT_QUOTES, 'UTF-8') ?></text>
                                <text x="0" y="56"><?= htmlspecialchars(t('weekday_wed_short'), ENT_QUOTES, 'UTF-8') ?></text>
                                <text x="0" y="86"><?= htmlspecialchars(t('weekday_fri_short'), ENT_QUOTES, 'UTF-8') ?></text>
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

                                    echo '<rect class="day" width="'.$cellWidth.'" height="'.$cellWidth.'" x="'.$pos['x'].'" y="'.$pos['y'].'" fill="'.$color.'" data-count="'.$count.'" data-date="'.$dateStr.'" rx="2" ry="2" onclick="showDailyDuelsChart(\''.$dateStr.'\')"><title>'.$dateStr.': '.t('duels_count_short', ['count' => $count]).'</title></rect>';
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

                    <div class="margin-top-12-flex-alt">
                        <span><?= htmlspecialchars(t('less_label'), ENT_QUOTES, 'UTF-8') ?></span>
                        <div class="color-box-14x14 bg-dark-calendar"></div>
                        <div class="color-box-14x14 bg-green-light"></div>
                        <div class="color-box-14x14 bg-green-medium"></div>
                        <div class="color-box-14x14 bg-green-bright"></div>
                        <div class="color-box-14x14 bg-green-highlight"></div>
                        <span><?= htmlspecialchars(t('more_label'), ENT_QUOTES, 'UTF-8') ?></span>
                    </div>

                </div>

                <!-- Daily Duels Chart Container (outside of heatmap container for AJAX) -->
                <div id="daily-duels-chart-container" class="daily-chart-container">
                    <h3 id="daily-chart-title" class="daily-chart-title"><?= htmlspecialchars(t('duels_for_date', ['date' => '']), ENT_QUOTES, 'UTF-8') ?> <span id="selected-date-display"></span></h3>
                    <div class="chart-wrapper" style="height: 200px;">
                        <canvas id="dailyDuelsChart"></canvas>
                    </div>
                    <button onclick="hideDailyDuelsChart()" class="hide-chart-button"><?= htmlspecialchars(t('hide_chart'), ENT_QUOTES, 'UTF-8') ?></button>
                </div>
            </div>

            <script>
                // Initialize profile Steam ID for JS functions
                window.PROFILE_STEAM_ID = '<?= $viewProfile ?>';
            </script>
            <?php endif; ?>

            <div class="card card-margin-top-20">
                <div class="card-header">
                    <h2 class="card-title"><i class="fas fa-fist-raised"></i> <?= htmlspecialchars(t('recent_duels_title'), ENT_QUOTES, 'UTF-8') ?></h2>
                </div>

                <?php if (!empty($profileData['duels'])): ?>
                    <div class="overflow-auto-div">
                        <table class="duels-table" id="profile-duels-table">
                            <thead>
                                <tr>
                                    <th>ID</th>
                                    <th><?= htmlspecialchars(t('table_type'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_date'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_result'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_class'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_opponent'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_opponent_class'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_arena'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_score'), ENT_QUOTES, 'UTF-8') ?></th>
                                    <th><?= htmlspecialchars(t('table_elo_change'), ENT_QUOTES, 'UTF-8') ?></th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($profileData['duels'] as $duel):
                                    $isWinner = $duel['is_winner'] ?? false;

                                    // Calculate ELO change based on whether the player won or lost
                                    $eloChange = null;
                                    if ($duel['type'] === '1v1') {
                                        if ($duel['winner'] === $profileData['steamid']) {
                                            if (isset($duel['winner_new_elo']) && isset($duel['winner_previous_elo'])) {
                                                $eloChange = $duel['winner_new_elo'] - $duel['winner_previous_elo'];
                                            }
                                        } else {
                                            if (isset($duel['loser_new_elo']) && isset($duel['loser_previous_elo'])) {
                                                $eloChange = $duel['loser_new_elo'] - $duel['loser_previous_elo'];
                                            }
                                        }
                                    } else { // 2v2
                                        if ($duel['winner'] === $profileData['steamid'] || $duel['winner2'] === $profileData['steamid']) {
                                            if (isset($duel['winner_new_elo']) && isset($duel['winner_previous_elo'])) {
                                                $eloChange = $duel['winner_new_elo'] - $duel['winner_previous_elo'];
                                            }
                                        } else {
                                            if (isset($duel['loser_new_elo']) && isset($duel['loser_previous_elo'])) {
                                                $eloChange = $duel['loser_new_elo'] - $duel['loser_previous_elo'];
                                            }
                                        }
                                    }

                                    // Debug: Output the duel data to HTML for inspection
                                    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
                                        echo "<!-- DEBUG DUEL DATA: ID={$duel['id']}, Type={$duel['type']}, Winner={$duel['winner']}, Winner2={$duel['winner2']}, Loser={$duel['loser']}, Loser2={$duel['loser2']}, ProfileID={$profileData['steamid']}, IsWinner=" . ($isWinner ? 'YES' : 'NO') . " -->";
                                    }
                                ?>
                                    <?php if (isset($_GET['debug']) && $_GET['debug'] === 'true'): ?>
                                    <tr>
                                        <td colspan="8" style="background-color: #333; color: #0f0; font-family: monospace; font-size: 12px; padding: 5px;">
                                            DEBUG: ID=<?= $duel['id'] ?>, Type=<?= $duel['type'] ?>, Winner=<?= $duel['winner'] ?>, Winner2=<?= $duel['winner2'] ?? 'NULL' ?>, Loser=<?= $duel['loser'] ?>, Loser2=<?= $duel['loser2'] ?? 'NULL' ?>, ProfileID=<?= $profileData['steamid'] ?>, IsWinner=<?= $isWinner ? 'YES' : 'NO' ?>
                                        </td>
                                    </tr>
                                    <?php endif; ?>
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
                                                <?= $isWinner ? htmlspecialchars(t('result_win'), ENT_QUOTES, 'UTF-8') : htmlspecialchars(t('result_loss'), ENT_QUOTES, 'UTF-8') ?>
                                            </span>
                                        </td>
                                        <td>
                                            <?php if ($isWinner): ?>
                                                <?php if (!empty($duel['winnerclass'])): ?>
                                                    <?= getClassIconsHtml($duel['winnerclass'], "38") ?>
                                                <?php else: ?>
                                                    <span class="no-class">-</span>
                                                <?php endif; ?>
                                            <?php else: ?>
                                                <?php if (!empty($duel['loserclass'])): ?>
                                                    <?= getClassIconsHtml($duel['loserclass'], "38") ?>
                                                <?php else: ?>
                                                    <span class="no-class">-</span>
                                                <?php endif; ?>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <?php
                                                if ($isWinner) {
                                                    if ($duel['type'] === '1v1') {
                                                        $opponentId = $duel['loser'];
                                                    } else {
                                                        if ($duel['loser'] === $profileData['steamid']) {
                                                            $opponentId = $duel['loser2'];
                                                        } else {
                                                            $opponentId = $duel['loser'];
                                                        }
                                                    }
                                                } else {
                                                    if ($duel['type'] === '1v1') {
                                                        $opponentId = $duel['winner'];
                                                    } else {
                                                        if ($duel['winner'] === $profileData['steamid']) {
                                                            $opponentId = $duel['winner2'];
                                                        } else {
                                                            $opponentId = $duel['winner'];
                                                        }
                                                    }
                                                }
                                                $opponentNick = getPlayerNickname($db, $opponentId);
                                            ?>
                                            <a href="?profile=<?= urlencode($opponentId) ?>" class="opponent-link">
                                                <?= htmlspecialchars($opponentNick) ?>
                                            </a>
                                        </td>
                                        <td>
                                            <?php if ($isWinner): ?>
                                                <?php if (!empty($duel['loserclass'])): ?>
                                                    <?= getClassIconsHtml($duel['loserclass'], "38") ?>
                                                <?php else: ?>
                                                    <span class="no-class">-</span>
                                                <?php endif; ?>
                                            <?php else: ?>
                                                <?php if (!empty($duel['winnerclass'])): ?>
                                                    <?= getClassIconsHtml($duel['winnerclass'], "38") ?>
                                                <?php else: ?>
                                                    <span class="no-class">-</span>
                                                <?php endif; ?>
                                            <?php endif; ?>
                                        </td>
                                        <td><?= htmlspecialchars($duel['arenaname']) ?></td>
                                        <td><?= $duel['winnerscore'] ?>:<?= $duel['loserscore'] ?></td>
                                        <td class="elo-change <?= $eloChange !== null ? ($eloChange > 0 ? 'positive' : ($eloChange < 0 ? 'negative' : 'neutral')) : 'neutral' ?>">
                                            <?= $eloChange !== null ? ($eloChange > 0 ? '+' : '') . $eloChange : '-' ?>
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
                                <a href="?profile=<?= urlencode($viewProfile) ?>&duels_page=<?= $profileData['duels_current_page'] - 1 ?>"><i class="fas fa-chevron-left"></i> <?= htmlspecialchars(t('js_back'), ENT_QUOTES, 'UTF-8') ?></a>
                            <?php endif; ?>

                            <?php for ($i = max(1, $profileData['duels_current_page'] - 2); $i <= min($profileData['duels_total_pages'], $profileData['duels_current_page'] + 2); $i++): ?>
                                <?php if ($i == $profileData['duels_current_page']): ?>
                                    <span class="current"><?= $i ?></span>
                                <?php else: ?>
                                    <a href="?profile=<?= urlencode($viewProfile) ?>&duels_page=<?= $i ?>"><?= $i ?></a>
                                <?php endif; ?>
                            <?php endfor; ?>

                            <?php if ($profileData['duels_current_page'] < $profileData['duels_total_pages']): ?>
                                <a href="?profile=<?= urlencode($viewProfile) ?>&duels_page=<?= $profileData['duels_current_page'] + 1 ?>"><?= htmlspecialchars(t('js_forward'), ENT_QUOTES, 'UTF-8') ?> <i class="fas fa-chevron-right"></i></a>
                            <?php endif; ?>
                        </div>
                    <?php endif; ?>
                <?php else: ?>
                    <p><?= htmlspecialchars(t('no_duels_data'), ENT_QUOTES, 'UTF-8') ?></p>
                <?php endif; ?>
            </div>



        <?php else: ?>
            <!-- Main Statistics View -->
            <div class="search-container">
                <form method="GET" class="search-form search-form-full">
                    <?php if (isset($_GET['profile'])): ?>
                        <input type="hidden" name="profile" value="<?= htmlspecialchars($_GET['profile']) ?>">
                    <?php endif; ?>
                    <input type="text" name="search" placeholder="<?= htmlspecialchars(t('search_placeholder'), ENT_QUOTES, 'UTF-8') ?>" class="search-input" value="<?= htmlspecialchars($searchQuery) ?>">
                    <button type="submit" class="search-btn"><?= htmlspecialchars(t('search_btn'), ENT_QUOTES, 'UTF-8') ?></button>
                    <?php if ($searchQuery): ?>
                        <a href="?" class="btn btn-secondary btn-secondary-margin"><?= htmlspecialchars(t('clear_btn'), ENT_QUOTES, 'UTF-8') ?></a>
                    <?php endif; ?>
                </form>
            </div>

            <?php if ($searchQuery && !empty($searchResults)): ?>
                <div class="search-results">
                    <div class="card">
                        <div class="card-header">
                            <h2 class="card-title"><i class="fas fa-search"></i> <?= htmlspecialchars(t('search_results_title'), ENT_QUOTES, 'UTF-8') ?></h2>
                        </div>
                        <div class="overflow-x-auto-alt">
                            <table class="top-players-table">
                                <thead>
                                    <tr>
                                        <th><?= htmlspecialchars(t('table_place'), ENT_QUOTES, 'UTF-8') ?></th>
                                        <th><?= htmlspecialchars(t('table_player'), ENT_QUOTES, 'UTF-8') ?></th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=rating&sort_dir=<?= $orderBy === 'rating' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" class="inherit-color-no-decoration">
                                                <?= htmlspecialchars(t('profile_rating'), ENT_QUOTES, 'UTF-8') ?>
                                                <?php if ($orderBy === 'rating'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=wins&sort_dir=<?= $orderBy === 'wins' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                <?= htmlspecialchars(t('profile_wins'), ENT_QUOTES, 'UTF-8') ?>
                                                <?php if ($orderBy === 'wins'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=losses&sort_dir=<?= $orderBy === 'losses' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                <?= htmlspecialchars(t('profile_losses'), ENT_QUOTES, 'UTF-8') ?>
                                                <?php if ($orderBy === 'losses'): ?>
                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                <?php endif; ?>
                                            </a>
                                        </th>
                                        <th>
                                            <a href="?search=<?= urlencode($searchQuery) ?>&sort_by=winrate&sort_dir=<?= $orderBy === 'winrate' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?>" style="color: inherit; text-decoration: none;">
                                                <?= htmlspecialchars(t('profile_winrate'), ENT_QUOTES, 'UTF-8') ?>
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
                                                    <?= htmlspecialchars($player['name'] ?: $player['steamid']) ?>
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
                    <p><?= htmlspecialchars(t('players_not_found', ['query' => $searchQuery]), ENT_QUOTES, 'UTF-8') ?></p>
                </div>
            <?php else: ?>
                <div class="stats-overview">
                    <div class="stat-item">
                        <div class="stat-label"><?= htmlspecialchars(t('total_duels'), ENT_QUOTES, 'UTF-8') ?></div>
                        <div class="stat-value stat-value-accent"><?= $totalStats['total_duels'] + $totalStats['total_duels_2v2'] ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label"><?= htmlspecialchars(t('total_players'), ENT_QUOTES, 'UTF-8') ?></div>
                        <div class="stat-value stat-value-success-alt"><?= $totalStats['total_players'] ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label"><?= htmlspecialchars(t('highest_rating'), ENT_QUOTES, 'UTF-8') ?></div>
                        <div class="stat-value stat-value-warning"><?= $totalStats['highest_rating'] ?: t('na') ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label"><?= htmlspecialchars(t('duels_1v1'), ENT_QUOTES, 'UTF-8') ?></div>
                        <div class="stat-value stat-value-danger-alt"><?= $totalStats['total_duels'] ?></div>
                    </div>

                    <div class="stat-item">
                        <div class="stat-label"><?= htmlspecialchars(t('duels_2v2'), ENT_QUOTES, 'UTF-8') ?></div>
                        <div class="stat-value stat-value-primary"><?= $totalStats['total_duels_2v2'] ?></div>
                    </div>
                </div>

                <div class="tabs">
                    <button class="tab active" data-tab="overview"><?= htmlspecialchars(t('players_list_title'), ENT_QUOTES, 'UTF-8') ?></button>
                    <button class="tab" data-tab="recent-duels"><?= htmlspecialchars(t('recent_duels_title'), ENT_QUOTES, 'UTF-8') ?></button>
                </div>

                <div class="tab-content active" id="overview-tab">
                    <div class="main-content">
                        <div class="card">
                            <div class="card-header">
                                <h2 class="card-title"><i class="fas fa-users"></i> <?= htmlspecialchars(t('players_list_title'), ENT_QUOTES, 'UTF-8') ?></h2>
                            </div>

                            <div id="players-container" class="refreshable-content">
                                <div class="refresh-indicator" id="players-refresh-indicator">
                                    <div class="refresh-spinner"></div>
                                </div>
                                <?php if (!empty($topPlayers)): ?>
                                    <div class="overflow-x-auto-alt">
                                        <table class="top-players-table">
                                                <thead>
                                                    <tr>
                                                        <th><?= htmlspecialchars(t('table_place'), ENT_QUOTES, 'UTF-8') ?></th>
                                                        <th><?= htmlspecialchars(t('table_player'), ENT_QUOTES, 'UTF-8') ?></th>
                                                        <th>
                                                            <a href="?sort_by=rating&sort_dir=<?= $orderBy === 'rating' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                                <?= htmlspecialchars(t('profile_rating'), ENT_QUOTES, 'UTF-8') ?>
                                                                <?php if ($orderBy === 'rating'): ?>
                                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                                <?php endif; ?>
                                                            </a>
                                                        </th>
                                                        <th>
                                                            <a href="?sort_by=wins&sort_dir=<?= $orderBy === 'wins' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                                <?= htmlspecialchars(t('profile_wins'), ENT_QUOTES, 'UTF-8') ?>
                                                                <?php if ($orderBy === 'wins'): ?>
                                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                                <?php endif; ?>
                                                            </a>
                                                        </th>
                                                        <th>
                                                            <a href="?sort_by=losses&sort_dir=<?= $orderBy === 'losses' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                                <?= htmlspecialchars(t('profile_losses'), ENT_QUOTES, 'UTF-8') ?>
                                                                <?php if ($orderBy === 'losses'): ?>
                                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                                <?php endif; ?>
                                                            </a>
                                                        </th>
                                                        <th>
                                                            <a href="?sort_by=winrate&sort_dir=<?= $orderBy === 'winrate' && $orderDir === 'DESC' ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                                <?= htmlspecialchars(t('profile_winrate'), ENT_QUOTES, 'UTF-8') ?>
                                                                <?php if ($orderBy === 'winrate'): ?>
                                                                    <i class="fas fa-sort-<?= $orderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                                                <?php endif; ?>
                                                            </a>
                                                        </th>
                                                        <th>
                                                            <a href="?sort_by=last_duel&sort_dir=<?= ($orderBy === 'last_duel' && $orderDir === 'DESC') ? 'ASC' : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                                                <?= htmlspecialchars(t('table_last_duel'), ENT_QUOTES, 'UTF-8') ?>
                                                                <?php if ($orderBy === 'last_duel'): ?>
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

                                                    // Get the most recent duel for this player
                                                    $lastDuel = getLastDuelForPlayer($db, $player['steamid']);
                                                    
                                                    // Get player name - use name from mgemod_stats or fallback to steamid
                                                    $playerName = !empty($player['name']) ? $player['name'] : $player['steamid'];
                                                ?>
                                                    <tr class="rank-<?= $index + 1 ?>">
                                                        <td>
                                                            <span class="rank-badge"><?= $index + 1 ?></span>
                                                        </td>
                                                        <td>
                                                            <a href="?profile=<?= urlencode($player['steamid']) ?>" style="color: var(--accent); text-decoration: none;">
                                                                <?= htmlspecialchars($playerName) ?>
                                                            </a>
                                                        </td>
                                                        <td><?= $player['rating'] ?></td>
                                                        <td><?= $player['wins'] ?></td>
                                                        <td><?= $player['losses'] ?></td>
                                                        <td><?= $winrate ?>%</td>
                                                        <td>
                                                            <?php if ($lastDuel): ?>
                                                                <?= date('d.m.Y H:i', $lastDuel['endtime']) ?>
                                                            <?php else: ?>
                                                                <?= htmlspecialchars(t('no_data'), ENT_QUOTES, 'UTF-8') ?>
                                                            <?php endif; ?>
                                                        </td>
                                                    </tr>
                                                <?php endforeach; ?>
                                            </tbody>
                                        </table>
                                    </div>
                                <?php else: ?>
                                    <p><?= htmlspecialchars(t('no_top_players_data'), ENT_QUOTES, 'UTF-8') ?></p>
                                <?php endif; ?>

                                <!-- Players Pagination -->
                                <div class="pagination" id="players-pagination">
                                    <?php if ($totalPagesPlayers > 1): ?>
                                        <?php if ($page > 1): ?>
                                            <a href="?page=<?= $page - 1 ?>"><i class="fas fa-chevron-left"></i> <?= htmlspecialchars(t('js_back'), ENT_QUOTES, 'UTF-8') ?></a>
                                        <?php endif; ?>

                                        <?php for ($i = max(1, $page - 2); $i <= min($totalPagesPlayers, $page + 2); $i++): ?>
                                            <?php if ($i == $page): ?>
                                                <span class="current"><?= $i ?></span>
                                            <?php else: ?>
                                                <a href="?page=<?= $i ?>"><?= $i ?></a>
                                            <?php endif; ?>
                                        <?php endfor; ?>

                                        <?php if ($page < $totalPagesPlayers): ?>
                                            <a href="?page=<?= $page + 1 ?>"><?= htmlspecialchars(t('js_forward'), ENT_QUOTES, 'UTF-8') ?> <i class="fas fa-chevron-right"></i></a>
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
            <h2 class="card-title"><i class="fas fa-history"></i> <?= htmlspecialchars(t('recent_duels_title'), ENT_QUOTES, 'UTF-8') ?></h2>
        </div>

        <div id="duels-container-2" class="refreshable-content">
            <div class="refresh-indicator" id="duels-refresh-indicator-2">
                <div class="refresh-spinner"></div>
            </div>
            <div class="overflow-x-auto-alt">
                <table class="duels-table">
                    <thead>
                        <tr>
                            <th>
                                <a href="?duel_sort_by=id&duel_sort_dir=<?= $duelOrderBy === 'id' ? ($duelOrderDir === 'DESC' ? 'ASC' : 'DESC') : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                    ID
                                    <?php if ($duelOrderBy === 'id'): ?>
                                        <i class="fas fa-sort-<?= $duelOrderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                    <?php endif; ?>
                                </a>
                            </th>
                            <th><?= htmlspecialchars(t('table_type'), ENT_QUOTES, 'UTF-8') ?></th>
                            <th>
                                <a href="?duel_sort_by=endtime&duel_sort_dir=<?= $duelOrderBy === 'endtime' ? ($duelOrderDir === 'DESC' ? 'ASC' : 'DESC') : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                    <?= htmlspecialchars(t('table_date'), ENT_QUOTES, 'UTF-8') ?>
                                    <?php if ($duelOrderBy === 'endtime'): ?>
                                        <i class="fas fa-sort-<?= $duelOrderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                    <?php endif; ?>
                                </a>
                            </th>
                            <th><?= htmlspecialchars(t('table_winner'), ENT_QUOTES, 'UTF-8') ?></th>
                            <th><?= htmlspecialchars(t('table_class'), ENT_QUOTES, 'UTF-8') ?></th>
                            <th><?= htmlspecialchars(t('table_loser'), ENT_QUOTES, 'UTF-8') ?></th>
                            <th><?= htmlspecialchars(t('table_class'), ENT_QUOTES, 'UTF-8') ?></th>
                            <th>ELO</th>
                            <th><?= htmlspecialchars(t('table_arena'), ENT_QUOTES, 'UTF-8') ?></th>
                            <th>
                                <a href="?duel_sort_by=winnerscore&duel_sort_dir=<?= $duelOrderBy === 'winnerscore' ? ($duelOrderDir === 'DESC' ? 'ASC' : 'DESC') : 'DESC' ?><?php if (isset($_GET['page'])) echo '&page=' . $_GET['page']; ?><?php if (isset($_GET['search'])) echo '&search=' . urlencode($_GET['search']); ?>" style="color: inherit; text-decoration: none;">
                                    <?= htmlspecialchars(t('table_score'), ENT_QUOTES, 'UTF-8') ?>
                                    <?php if ($duelOrderBy === 'winnerscore'): ?>
                                        <i class="fas fa-sort-<?= $duelOrderDir === 'ASC' ? 'up' : 'down' ?>"></i>
                                    <?php endif; ?>
                                </a>
                            </th>
                        </tr>
                    </thead>
                    <tbody id="duels-tbody-2">
                        <?php 

                        
                        foreach ($recentDuels as $duel):
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
                                    <?php if (!empty($duel['winnerclass'])): ?>
                                        <?= getClassIconsHtml($duel['winnerclass'], "32") ?>
                                    <?php else: ?>
                                        <span class="no-class">-</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <a href="?profile=<?= urlencode($duel['loser']) ?>" style="color: var(--danger); text-decoration: none;">
                                        <?= htmlspecialchars($loserNick) ?>
                                    </a>
                                </td>
                                <td>
                                    <?php if (!empty($duel['loserclass'])): ?>
                                        <?= getClassIconsHtml($duel['loserclass'], "32") ?>
                                    <?php else: ?>
                                        <span class="no-class">-</span>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <?php
                                        $eloChange = null;
                                        if (isset($duel['winner_new_elo']) && isset($duel['winner_previous_elo'])) {
                                            $eloChange = $duel['winner_new_elo'] - $duel['winner_previous_elo'];
                                        }

                                        if ($eloChange !== null) {
                                            $eloChangeClass = $eloChange > 0 ? 'positive' : ($eloChange < 0 ? 'negative' : 'neutral');
                                            echo '<span class="elo-change ' . $eloChangeClass . '">' . ($eloChange > 0 ? '+' : '') . $eloChange . '</span>';
                                        } else {
                                            echo '<span class="elo-change neutral">-</span>';
                                        }
                                    ?>
                                </td>
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
                        <a href="?page=<?= $page - 1 ?>&duel_sort_by=<?= $duelOrderBy ?>&duel_sort_dir=<?= $duelOrderDir ?>"><i class="fas fa-chevron-left"></i> <?= htmlspecialchars(t('js_back'), ENT_QUOTES, 'UTF-8') ?></a>
                    <?php endif; ?>

                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                        <?php if ($i == $page): ?>
                            <span class="current"><?= $i ?></span>
                        <?php else: ?>
                            <a href="?page=<?= $i ?>&duel_sort_by=<?= $duelOrderBy ?>&duel_sort_dir=<?= $duelOrderDir ?>"><?= $i ?></a>
                        <?php endif; ?>
                    <?php endfor; ?>

                    <?php if ($page < $totalPages): ?>
                        <a href="?page=<?= $page + 1 ?>&duel_sort_by=<?= $duelOrderBy ?>&duel_sort_dir=<?= $duelOrderDir ?>"><?= htmlspecialchars(t('js_forward'), ENT_QUOTES, 'UTF-8') ?> <i class="fas fa-chevron-right"></i></a>
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

    <script>
        window.MGE_LANG = <?= json_encode($MGE_LANG, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?>;
        window.MGE_LOCALE = <?= json_encode($MGE_LOCALE, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?>;
        window.MGE_I18N = <?= json_encode($MGE_I18N, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?>;
        window.tJs = window.tJs || function(key, fallback) {
            if (window.MGE_I18N && typeof window.MGE_I18N[key] === 'string') {
                return window.MGE_I18N[key];
            }
            return typeof fallback === 'string' && fallback.length ? fallback : key;
        };
    </script>
    <script src="js/script.js"></script>
    <script>
        // Initialize rating chart if on profile page
        console.log('Profile view:', <?php echo json_encode($viewProfile ?? false); ?>);
        console.log('Rating history exists:', <?php echo json_encode(!empty($profileData['rating_history']) ? true : false); ?>);
        console.log('Both conditions:', <?php echo json_encode(($viewProfile && !empty($profileData['rating_history'])) ? true : false); ?>);
        <?php if ($viewProfile && !empty($profileData['rating_history'])): ?>
        // Declare variables in outer scope to ensure they're accessible in callbacks
        let labels = [];
        let ratings = [];
        let dateLabels = [];
        let datasets = [];

        try {
            console.log('Initializing rating chart...');
            const ratingCtx = document.getElementById('ratingChart');
            console.log('Canvas element found:', !!ratingCtx);
            if (!ratingCtx) {
                console.error('Rating chart canvas element not found');
            }
            ctx = ratingCtx.getContext('2d');
            console.log('Canvas context obtained:', !!ctx);

            // Configure Chart defaults to match stats.php appearance
            Chart.defaults.color = '#cfd5e0';
            Chart.defaults.font.family = "'Inter', 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif";
            Chart.defaults.font.size = 12;
            Chart.defaults.plugins.legend.labels.color = '#cfd5e0';
            Chart.defaults.plugins.legend.labels.usePointStyle = true;
            Chart.defaults.plugins.legend.labels.boxWidth = 8;
            Chart.defaults.plugins.legend.labels.boxHeight = 8;
            Chart.defaults.plugins.title.color = '#e3e7ef';
            Chart.defaults.plugins.tooltip.backgroundColor = '#2f3440';
            Chart.defaults.plugins.tooltip.titleColor = '#f5f7fb';
            Chart.defaults.plugins.tooltip.bodyColor = '#d6dbe6';
            Chart.defaults.plugins.tooltip.borderColor = 'rgba(255, 255, 255, 0.08)';
            Chart.defaults.plugins.tooltip.borderWidth = 1;
            Chart.defaults.plugins.tooltip.padding = 10;
            Chart.defaults.plugins.tooltip.cornerRadius = 6;
            Chart.defaults.scale.grid.color = 'rgba(255, 255, 255, 0.08)';
            Chart.defaults.scale.grid.tickColor = 'rgba(255, 255, 255, 0.08)';
            Chart.defaults.scale.ticks.color = '#bfc6d4';
            Chart.defaults.elements.line.borderWidth = 2;
            Chart.defaults.elements.line.tension = 0.35;
            Chart.defaults.elements.point.radius = 2;
            Chart.defaults.elements.point.hoverRadius = 4;

            // Prepare data for segmented chart (similar to stats.php)
            const ratingHistory = <?php echo json_encode($profileData['rating_history'] ?? []); ?>;
            console.log('Rating history data:', ratingHistory); // Debug log
            console.log('Rating history length:', ratingHistory.length);

            if (!ratingHistory || ratingHistory.length === 0) {
                console.warn('No rating history data available');
            }

            // Clear and populate arrays (they were declared in outer scope)
            labels = [];
            ratings = [];
            dateLabels = [];
            let prevRating = null;
            let currentSegment = { start: 0, color: 'rgba(76, 175, 80, 0.15)', borderColor: 'rgba(76, 175, 80, 1)' };
            const segments = [];

            ratingHistory.forEach((point, index) => {
                // Use the exact duel timestamp for precise timing
                const date = new Date(point.endtime * 1000);
                const dateString = date.toLocaleString(window.MGE_LOCALE || 'ru-RU', {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit'
                });

                // Create labels with dates and times for each duel
                labels.push(dateString);
                dateLabels.push(dateString);
                ratings.push(point.rating);

                if (prevRating !== null) {
                    let color, borderColor;
                    if (point.rating > prevRating) {
                        color = 'rgba(76, 175, 80, 0.15)'; // green
                        borderColor = 'rgba(76, 175, 80, 1)';
                    } else if (point.rating < prevRating) {
                        color = 'rgba(244, 67, 54, 0.15)'; // red
                        borderColor = 'rgba(244, 67, 54, 1)';
                    } else {
                        color = 'rgba(255, 193, 7, 0.15)'; // yellow
                        borderColor = 'rgba(255, 193, 7, 1)';
                    }

                    if (color !== currentSegment.color) {
                        // End previous segment
                        currentSegment.end = index - 1;
                        if (currentSegment.start <= currentSegment.end) {
                            segments.push({...currentSegment});
                        }

                        // Start new segment
                        currentSegment = { start: index, color: color, borderColor: borderColor };
                    }
                }
                prevRating = point.rating;
            });

            // Add the last segment
            if (currentSegment.start <= ratingHistory.length - 1) {
                currentSegment.end = ratingHistory.length - 1;
                segments.push(currentSegment);
            }

            // Create multiple datasets for each line segment with different colors based on rating changes (like in stats.php)
            datasets = [];

            // Create a dataset for each line segment between points
            for (let i = 0; i < ratings.length - 1; i++) {
                let color, borderColor, bgColor;
                if (ratings[i+1] > ratings[i]) {
                    color = 'rgba(76, 175, 80, 1)'; // green for increase
                    borderColor = 'rgba(76, 175, 80, 1)';
                    bgColor = 'rgba(76, 175, 80, 0.15)'; // light green for fill
                } else if (ratings[i+1] < ratings[i]) {
                    color = 'rgba(244, 67, 54, 1)'; // red for decrease
                    borderColor = 'rgba(244, 67, 54, 1)';
                    bgColor = 'rgba(244, 67, 54, 0.15)'; // light red for fill
                } else {
                    color = 'rgba(255, 193, 7, 1)'; // yellow for no change
                    borderColor = 'rgba(255, 193, 7, 1)';
                    bgColor = 'rgba(255, 193, 7, 0.15)'; // light yellow for fill
                }

                // Create data array with current and next point, with nulls for others
                const segmentData = [];
                for (let j = 0; j < ratings.length; j++) {
                    if (j === i || j === i + 1) {
                        segmentData.push(ratings[j]);
                    } else {
                        segmentData.push(null);
                    }
                }

                datasets.push({
                    data: segmentData,
                    borderColor: borderColor,
                    backgroundColor: bgColor,
                    borderWidth: 2,
                    fill: true,
                    pointBackgroundColor: function(context) {
                        // Color the points based on the rating change
                        const index = context.dataIndex;
                        if (index === i) {
                            // Point color based on change from this to next
                            if (ratings[i+1] > ratings[i]) return 'rgba(76, 175, 80, 1)'; // green
                            else if (ratings[i+1] < ratings[i]) return 'rgba(244, 67, 54, 1)'; // red
                            else return 'rgba(255, 193, 7, 1)'; // yellow
                        } else if (index === i + 1) {
                            // Point color based on change from previous to this
                            if (ratings[i+1] > ratings[i]) return 'rgba(76, 175, 80, 1)'; // green
                            else if (ratings[i+1] < ratings[i]) return 'rgba(244, 67, 54, 1)'; // red
                            else return 'rgba(255, 193, 7, 1)'; // yellow
                        }
                        return 'rgba(76, 175, 80, 1)'; // default
                    },
                    pointBorderColor: borderColor,
                    pointRadius: 3,
                    tension: 0.35,
                    spanGaps: false
                });
            }

            // Add a dataset for isolated points (if any exist)
            if (ratings.length === 1) {
                datasets.push({
                    data: ratings,
                    borderColor: 'rgba(76, 175, 80, 1)',
                    backgroundColor: 'rgba(76, 175, 80, 0.15)',
                    borderWidth: 2,
                    fill: true,
                    pointBackgroundColor: 'rgba(76, 175, 80, 1)',
                    pointBorderColor: 'rgba(76, 175, 80, 1)',
                    pointRadius: 3,
                    tension: 0.35,
                    spanGaps: false
                });
            }

        } catch (error) {
            console.error('Error initializing rating chart:', error);
        }

        console.log('Creating chart with labels:', labels);
        console.log('Creating chart with datasets:', datasets);
        console.log('Labels length:', labels.length);
        console.log('Datasets length:', datasets.length);
        if (datasets.length > 0) {
            console.log('First dataset length:', datasets[0].data.length);
        }

        console.log('Canvas element exists in DOM:', document.getElementById('ratingChart') !== null);

        const ratingChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: datasets
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'nearest', intersect: false },
                plugins: {
                    title: {
                        display: false  // Title is now in the card header
                    },
                    legend: {
                        display: false  // Hide legend
                    },
                    tooltip: {
                        mode: 'nearest',
                        intersect: false,
                        callbacks: {
                            title: function(context) {
                                // Show date from dateLabels
                                return dateLabels[context[0].dataIndex];
                            },
                            label: function(context) {
                                const dataIndex = context.dataIndex;
                                const rating = context.parsed.y;
                                let change = '';
                                if (dataIndex > 0) {
                                    const prevRating = ratings[dataIndex - 1];
                                    const diff = rating - prevRating;
                                    change = diff > 0 ? ` (+${diff})` : diff < 0 ? ` (${diff})` : ' (+/-0)';
                                }
                                return `${tJs('js_rating', 'Rating')}: ${rating}${change}`;
                            }
                        }
                    },
                    zoom: {
                        zoom: {
                            wheel: { enabled: false },
                            mode: 'x'
                        },
                        pan: {
                            enabled: true,
                            mode: 'x'
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: false,
                        title: { display: true, text: tJs('js_rating', 'Rating') },
                        grid: {
                            color: function(context) {
                                if (context.tick.value === 0) return 'rgba(255, 255, 255, 0.1)';
                                return 'rgba(255, 255, 255, 0.05)';
                            }
                        }
                    },
                    x: {
                        title: { display: true, text: tJs('js_date', 'Date') },
                        grid: {
                            color: 'rgba(255, 255, 255, 0.05)'
                        },
                        ticks: {
                            maxRotation: 0,
                            minRotation: 0,
                            callback: function(value, index, values) {
                                // Show only first, middle and last date labels
                                const isStart = index === 0;
                                const isMiddle = index === Math.floor(labels.length / 2);
                                const isEnd = index === labels.length - 1;

                                if (isStart || isMiddle || isEnd) {
                                    // Shorten the label to show only date and hour
                                    const fullLabel = labels[index];
                                    const datePart = fullLabel.split(',')[0]; // Get date part
                                    const timePart = fullLabel.split(',')[1]?.trim().split(':')[0]; // Get hour part
                                    if (timePart) {
                                        return `${datePart} ${timePart}:00`;
                                    }
                                    return datePart;
                                }
                                return '';
                            }
                        }
                    }
                }
            }
        });
        console.log('Chart created successfully:', ratingChart);
        <?php endif; ?> // Close rating chart initialization

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

    </script>

    <!-- Loading statistics -->
    <div style="margin-top: 20px; padding: 10px; font-size: 12px; color: #666; text-align: center; border-top: 1px solid #eee;">
        <span><?= htmlspecialchars(t('load_time_label'), ENT_QUOTES, 'UTF-8') ?>: <?php echo round((microtime(true) - $startTime) * 1000, 2); ?> <?= htmlspecialchars(t('ms_label'), ENT_QUOTES, 'UTF-8') ?></span> |
        <span><?= htmlspecialchars(t('queries_label'), ENT_QUOTES, 'UTF-8') ?>: <?php echo $queryCount; ?></span>
    </div>

    <!-- GitHub link -->
    <div class="github-link">
        <span><?= htmlspecialchars(t('developed_with_ai'), ENT_QUOTES, 'UTF-8') ?> | </span>
        <a href="https://github.com/MrPanica/MGEMod" target="_blank">GitHub</a>
    </div>
</body>

