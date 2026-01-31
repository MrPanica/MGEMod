# MGE Statistics - Полная структура проекта

## Список всех файлов и папок:

### Папки:
- auth/ - аутентификация Steam
- config/ - конфигурационные файлы
- css/ - файлы стилей
- images/ - изображения
- includes/ - вспомогательные функции
- js/ - JavaScript файлы

### Файлы:

#### Основные файлы:
- stats_mge.php - главная страница статистики
- LightOpenID.php - библиотека OpenID
- .htaccess - настройки безопасности

#### В папке auth/:
- steam_auth.php - функции аутентификации Steam
- steam_handler.php - обработчик сессий Steam

#### В папке config/:
- secure_config_statstf2.php - конфигурация БД и API
- .htaccess - защита конфигурационных файлов

#### В папке css/:
- styles.css - основные стили

#### В папке includes/:
- helpers.php - вспомогательные функции

#### Дополнительные файлы:
- README.md - документация