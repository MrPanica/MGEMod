<?php
// Steam OpenID authentication functions

/**
 * Get Steam login URL for OpenID authentication
 * @return string Steam login URL
 */
function getSteamLoginUrl() {
    $openid = new LightOpenID('http://' . $_SERVER['HTTP_HOST']);
    $openid->identity = 'https://steamcommunity.com/openid';
    return $openid->authUrl();
}

/**
 * Validate Steam login and return SteamID
 * @return string|null SteamID if authenticated, null otherwise
 */
function validateSteamLogin() {
    if (isset($_GET['openid_identity'])) {
        $openid = new LightOpenID('http://' . $_SERVER['HTTP_HOST']);

        if ($openid->validate()) {
            $id = $openid->identity;
            $ptn = "/^https?:\/\/steamcommunity\.com\/openid\/id\/(7[0-9]{15,25}+)$/";
            preg_match($ptn, $id, $matches);

            if (isset($matches[1])) {
                $_SESSION['steamid64'] = $matches[1];

                // Convert SteamID64 to SteamID
                $steamId64 = $matches[1];
                $y = bcmod($steamId64, '2');
                $z = bcdiv(bcsub($steamId64, '76561197960265728'), '2');
                $steamId = "STEAM_0:{$y}:{$z}";

                $_SESSION['steamid'] = $steamId;
                return $steamId;
            }
        }
    }

    return isset($_SESSION['steamid']) ? $_SESSION['steamid'] : null;
}