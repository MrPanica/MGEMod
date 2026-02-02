-- Создание индексов для ускорения сортировки по последней дуэли
-- ВНИМАНИЕ: Эти индексы КРИТИЧЕСКИ необходимы для производительности!
-- Используем префиксную индексацию для VARCHAR колонок

-- Индексы для таблицы mgemod_duels (1v1 дуэли)
CREATE INDEX idx_mgemod_duels_winner ON mgemod_duels(winner(64), endtime);
CREATE INDEX idx_mgemod_duels_loser ON mgemod_duels(loser(64), endtime);

-- Индексы для таблицы mgemod_duels_2v2 (2v2 дуэли)
CREATE INDEX idx_mgemod_duels_2v2_winner ON mgemod_duels_2v2(winner(64), endtime);
CREATE INDEX idx_mgemod_duels_2v2_winner2 ON mgemod_duels_2v2(winner2(64), endtime);
CREATE INDEX idx_mgemod_duels_2v2_loser ON mgemod_duels_2v2(loser(64), endtime);
CREATE INDEX idx_mgemod_duels_2v2_loser2 ON mgemod_duels_2v2(loser2(64), endtime);

-- Дополнительные полезные индексы
CREATE INDEX idx_mgemod_stats_rating ON mgemod_stats(rating DESC);
CREATE INDEX idx_player_playtime_steamid_server ON player_playtime(steamid, server_id);

-- Если индексы уже существуют, сначала удалите старые:
-- DROP INDEX idx_mgemod_duels_winner ON mgemod_duels;
-- DROP INDEX idx_mgemod_duels_loser ON mgemod_duels;
-- DROP INDEX idx_mgemod_duels_2v2_winner ON mgemod_duels_2v2;
-- DROP INDEX idx_mgemod_duels_2v2_winner2 ON mgemod_duels_2v2;
-- DROP INDEX idx_mgemod_duels_2v2_loser ON mgemod_duels_2v2;
-- DROP INDEX idx_mgemod_duels_2v2_loser2 ON mgemod_duels_2v2;
