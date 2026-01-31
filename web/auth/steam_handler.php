<?php
// Steam authentication handler

require_once '../LightOpenID.php';
require_once 'steam_auth.php';

session_start();

// Initialize Steam authentication
$steamId = validateSteamLogin();
$isAuthenticated = !empty($steamId);

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