<?php

function mge_available_languages(): array {
    return ['ru', 'en'];
}

function mge_detect_browser_language(): string {
    $header = strtolower((string)($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? ''));
    if ($header === '') {
        return 'ru';
    }

    if (preg_match('/\b(ru|en)(?:[-_][a-z]{2})?\b/i', $header, $m)) {
        $lang = strtolower($m[1]);
        return in_array($lang, mge_available_languages(), true) ? $lang : 'ru';
    }

    return 'ru';
}

function mge_resolve_language(): string {
    $allowed = mge_available_languages();

    $fromGet = strtolower((string)($_GET['lang'] ?? ''));
    if (in_array($fromGet, $allowed, true)) {
        setcookie('mge_lang', $fromGet, [
            'expires' => time() + (60 * 60 * 24 * 365),
            'path' => '/',
            'samesite' => 'Lax'
        ]);
        $_COOKIE['mge_lang'] = $fromGet;
        return $fromGet;
    }

    $fromCookie = strtolower((string)($_COOKIE['mge_lang'] ?? ''));
    if (in_array($fromCookie, $allowed, true)) {
        return $fromCookie;
    }

    return mge_detect_browser_language();
}

function mge_locale_for_language(string $lang): string {
    return $lang === 'en' ? 'en-US' : 'ru-RU';
}

function mge_load_translations(string $lang): array {
    $lang = in_array($lang, mge_available_languages(), true) ? $lang : 'ru';
    $basePath = dirname(__DIR__) . '/lang/';

    $en = [];
    $enPath = $basePath . 'en.php';
    if (is_file($enPath)) {
        $en = require $enPath;
    }

    $current = [];
    $path = $basePath . $lang . '.php';
    if (is_file($path)) {
        $current = require $path;
    }

    if (!is_array($en)) {
        $en = [];
    }
    if (!is_array($current)) {
        $current = [];
    }

    return array_replace($en, $current);
}

function mge_t(string $key, array $params = []): string {
    global $MGE_I18N;

    $text = isset($MGE_I18N[$key]) ? (string)$MGE_I18N[$key] : $key;
    if (empty($params)) {
        return $text;
    }

    $replace = [];
    foreach ($params as $k => $value) {
        $replace['{' . $k . '}'] = (string)$value;
    }

    return strtr($text, $replace);
}

function t(string $key, array $params = []): string {
    return mge_t($key, $params);
}

function mge_url_with_lang(string $lang, array $extraParams = []): string {
    $allowed = mge_available_languages();
    $lang = in_array($lang, $allowed, true) ? $lang : 'ru';

    $params = $_GET;
    $params['lang'] = $lang;

    foreach ($extraParams as $k => $v) {
        if ($v === null) {
            unset($params[$k]);
        } else {
            $params[$k] = $v;
        }
    }

    return $_SERVER['PHP_SELF'] . '?' . http_build_query($params);
}
