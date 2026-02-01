<?php
// Common helper functions for MGE statistics

/**
 * Get player nickname by SteamID with caching
 * @param mysqli $db Database connection
 * @param string $steamId SteamID of the player
 * @return string Player nickname or SteamID if not found
 */
function getPlayerNickname($db, $steamId) {
    static $cache = []; // Simple in-memory cache

    if (isset($cache[$steamId])) {
        return $cache[$steamId];
    }

    $stmt = $db->prepare("SELECT name FROM mgemod_stats WHERE steamid = ? LIMIT 1");
    $stmt->bind_param('s', $steamId);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result->fetch_assoc();
    $stmt->close();

    $name = $row ? $row['name'] : $steamId;
    $cache[$steamId] = $name;

    // Debug: Show debug info if debug parameter is present
    if (isset($_GET['debug']) && $_GET['debug'] === 'true') {
        echo "<!-- getPlayerNickname called for steamId: $steamId, found name: $name -->";
    }

    return $name;
}

/**
 * Process duels to determine if the current player is the winner
 * @param array $duels Array of duel data
 * @param string $steamId Current player's SteamID
 * @return array Processed duels with is_winner flag
 */
function processDuelWinners($duels, $steamId) {
    foreach ($duels as &$duel) {
        // Determine if the current player is the winner
        $duel['is_winner'] = ($duel['winner'] === $steamId ||
                             (isset($duel['winner2']) && $duel['winner2'] === $steamId));
    }
    
    return $duels;
}

/**
 * Get player's ELO change for a duel
 * @param array $duel Duel data
 * @param bool $isWinner Whether the player won the duel
 * @return int ELO change
 */
function getPlayerEloChange($duel, $isWinner) {
    if ($isWinner) {
        if (isset($duel['type']) && $duel['type'] === '2v2') {
            return $duel['winner_new_elo'] - $duel['winner_previous_elo'];
        } else {
            return $duel['winner_new_elo'] - $duel['winner_previous_elo'];
        }
    } else {
        if (isset($duel['type']) && $duel['type'] === '2v2') {
            return $duel['loser_new_elo'] - $duel['loser_previous_elo'];
        } else {
            return $duel['loser_new_elo'] - $duel['loser_previous_elo'];
        }
    }
}

/**
 * Validate sort parameters to prevent SQL injection
 * @param string $orderBy Field to order by
 * @param string $orderDir Direction of ordering
 * @return array Validated and sanitized sort parameters
 */
function validateSortParams($orderBy, $orderDir) {
    // Validate order by field to prevent SQL injection
    $allowedFields = ['rating', 'wins', 'losses', 'winrate', 'last_duel'];
    if (!in_array($orderBy, $allowedFields)) {
        $orderBy = 'rating';
    }

    // Validate order direction
    $orderDir = strtoupper($orderDir) === 'ASC' ? 'ASC' : 'DESC';

    return [$orderBy, $orderDir];
}

/**
 * Sanitize user input to prevent XSS attacks
 * @param string $input User input
 * @return string Sanitized input
 */
function sanitizeInput($input) {
    return htmlspecialchars(strip_tags(trim($input)), ENT_QUOTES, 'UTF-8');
}