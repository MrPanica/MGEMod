StringMap g_migrationProgress;

// ===== MIGRATION SYSTEM CORE =====

// Initializes the migration tracking system by creating or resetting the progress map
void InitializeMigrationSystem()
{
    if (g_migrationProgress != null)
        delete g_migrationProgress;
    g_migrationProgress = new StringMap();
}

// Entry point for database schema migrations that orchestrates the entire migration process
void RunDatabaseMigrations()
{
    LogMessage("[Migrations] Starting database schema migrations");
    InitializeMigrationSystem();
    CreateMigrationsTable();
}

// Creates the migrations tracking table for both SQLite and MySQL databases
void CreateMigrationsTable()
{
    char query[512];
    GetCreateTableQuery_Migrations(query, sizeof(query));
    g_DB.Query(CreateMigrationsTableCallback, query);
}


// ===== MIGRATION EXECUTION ENGINE =====

// Checks if a migration has been executed and runs it if needed
void CheckAndRunMigration(const char[] migrationName)
{
    char query[256];
    GetSelectMigrationStatusQuery(query, sizeof(query), migrationName);
    
    DataPack pack = new DataPack();
    pack.WriteString(migrationName);
    
    g_DB.Query(CheckMigrationCallback, query, pack);
}

// Dispatches specific migration execution based on migration name
void RunMigration(const char[] migrationName)
{
    // NOTE: Migrations 001-004 are legacy migrations for SQLite/MySQL only
    // PostgreSQL gets modern schema immediately in CREATE TABLE statements
    // Future migrations (005+) should include PostgreSQL-specific queries using g_DatabaseType switch

    if (StrEqual(migrationName, "001_add_class_columns"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
        {
            g_migrationProgress.SetValue(migrationName, 1); // Just mark as complete for PostgreSQL
        }
        else
        {
            g_migrationProgress.SetValue(migrationName, 6);
        }
        Migration_001_AddClassColumns();
    }
    else if (StrEqual(migrationName, "002_duel_timing_columns"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
        {
            g_migrationProgress.SetValue(migrationName, 1); // Just mark as complete for PostgreSQL
        }
        else
        {
            g_migrationProgress.SetValue(migrationName, 6);
        }
        Migration_002_DuelTimingColumns();
    }
    else if (StrEqual(migrationName, "003_add_primary_keys"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
        {
            g_migrationProgress.SetValue(migrationName, 1); // Just mark as complete for PostgreSQL
        }
        else if (g_DatabaseType == DB_MYSQL)
        {
            g_migrationProgress.SetValue(migrationName, 4);
        }
        else
        {
            g_migrationProgress.SetValue(migrationName, 11);
        }
        Migration_003_AddPrimaryKeys();
    }
    else if (StrEqual(migrationName, "004_add_elo_tracking"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
        {
            g_migrationProgress.SetValue(migrationName, 1); // Just mark as complete for PostgreSQL
        }
        else
        {
            g_migrationProgress.SetValue(migrationName, 12);
        }
        Migration_004_AddEloTracking();
    }
    else if (StrEqual(migrationName, "005_add_cancel_fields"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
            g_migrationProgress.SetValue(migrationName, 1);
        else
            g_migrationProgress.SetValue(migrationName, 6);
        Migration_005_AddCancelFields();
    }
    else if (StrEqual(migrationName, "006_add_class_ratings"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
        {
            g_migrationProgress.SetValue(migrationName, 1); // Just mark as complete for PostgreSQL
        }
        else
        {
            g_migrationProgress.SetValue(migrationName, 9);
        }
        Migration_006_AddClassRatings();
    }
    else if (StrEqual(migrationName, "007_add_weapon_id_columns"))
    {
        if (g_DatabaseType == DB_POSTGRESQL)
            g_migrationProgress.SetValue(migrationName, 1);
        else
            g_migrationProgress.SetValue(migrationName, 6);
        Migration_007_AddWeaponIdColumns();
    }
    else if (StrEqual(migrationName, "008_add_round_logs"))
    {
        g_migrationProgress.SetValue(migrationName, 2);
        Migration_008_AddRoundLogs();
    }
    else if (StrEqual(migrationName, "009_add_server_id_to_duels"))
    {
        g_migrationProgress.SetValue(migrationName, 2);
        Migration_009_AddServerIdToDuels();
    }
    else if (StrEqual(migrationName, "010_ensure_duel_ids_autoincrement"))
    {
        if (g_DatabaseType == DB_MYSQL)
            g_migrationProgress.SetValue(migrationName, 6);
        else
            g_migrationProgress.SetValue(migrationName, 1);
        Migration_010_EnsureDuelIdsAutoincrement();
    }
    else if (StrEqual(migrationName, "011_round_slot_normalization"))
    {
        if (g_DatabaseType == DB_MYSQL)
            g_migrationProgress.SetValue(migrationName, 29);
        else
            g_migrationProgress.SetValue(migrationName, 10);
        Migration_011_RoundSlotNormalization();
    }
    else if (StrEqual(migrationName, "012_add_compact_round_json"))
    {
        g_migrationProgress.SetValue(migrationName, 2);
        Migration_012_AddCompactRoundJson();
    }
}

// Executes individual migration steps with progress tracking and error handling
void ExecuteMigrationStep(const char[] migrationName, const char[] query, int stepNumber)
{
    DataPack pack = new DataPack();
    pack.WriteString(migrationName);
    pack.WriteCell(stepNumber);
    g_DB.Query(GenericMigrationCallback, query, pack);
}

// Records successful migration completion in the migrations tracking table
void MarkMigrationComplete(const char[] migrationName)
{
    char query[256];
    GetInsertMigrationCompleteQuery(query, sizeof(query), migrationName, GetTime());
    g_DB.Query(MarkMigrationCallback, query);
}


// ===== DATABASE CALLBACK HANDLERS =====

// Handles migrations table creation result and initiates individual migration checks
void CreateMigrationsTableCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Migrations] Database connection lost while creating migrations table");
        return;
    }
    
    if (!StrEqual("", error))
    {
        LogError("[Migrations] Failed to create migrations table: %s", error);
        return;
    }
    
    LogMessage("[Migrations] Migration tracking table ready, checking individual migrations");
    
    // Run legacy migrations for SQLite and MySQL
    CheckAndRunMigration("001_add_class_columns");
    CheckAndRunMigration("002_duel_timing_columns");
    CheckAndRunMigration("003_add_primary_keys");
    CheckAndRunMigration("004_add_elo_tracking");
    CheckAndRunMigration("005_add_cancel_fields");
    CheckAndRunMigration("006_add_class_ratings");
    CheckAndRunMigration("007_add_weapon_id_columns");
    CheckAndRunMigration("008_add_round_logs");
    CheckAndRunMigration("009_add_server_id_to_duels");
    CheckAndRunMigration("010_ensure_duel_ids_autoincrement");
    CheckAndRunMigration("011_round_slot_normalization");
    CheckAndRunMigration("012_add_compact_round_json");
}

// Processes migration existence check results and triggers migration execution if needed
void CheckMigrationCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    char migrationName[64];
    pack.ReadString(migrationName, sizeof(migrationName));
    delete pack;
    
    if (db == null)
    {
        LogError("[Migrations] Database connection lost while checking migration: %s", migrationName);
        return;
    }
    
    if (!StrEqual("", error))
    {
        LogError("[Migrations] Failed to check migration %s: %s", migrationName, error);
        return;
    }
    
    if (results.FetchRow())
    {
        int migrationExists = results.FetchInt(0);
        if (migrationExists == 0)
        {
            LogMessage("[Migrations] Running migration: %s", migrationName);
            RunMigration(migrationName);
        }
        else
        {
            LogMessage("[Migrations] Migration %s already executed (skipping)", migrationName);
        }
    }
}

// Handles individual migration step results and tracks progress toward completion
void GenericMigrationCallback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
    pack.Reset();
    char migrationName[64];
    pack.ReadString(migrationName, sizeof(migrationName));
    int stepNumber = pack.ReadCell();
    delete pack;

    if (db == null)
    {
        LogError("[Migration %s] Database connection lost during step %d", migrationName, stepNumber);
        return;
    }

    // For migrations 002 and 003, ignore certain errors as they indicate partial application
    bool stepSkipped = false;
    if (!StrEqual("", error))
    {
        if ((StrEqual(migrationName, "002_duel_timing_columns") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "no such column") != -1 ||
              StrContains(error, "Unknown column") != -1)) ||
            (StrEqual(migrationName, "003_add_primary_keys") &&
             (StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "Duplicate key name") != -1 ||
              StrContains(error, "Multiple primary key") != -1)) ||
            (StrEqual(migrationName, "006_add_class_ratings") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "already exists") != -1 ||
              StrContains(error, "Unknown column") != -1)) ||
            (StrEqual(migrationName, "007_add_weapon_id_columns") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "already exists") != -1 ||
              StrContains(error, "Unknown column") != -1)) ||
            (StrEqual(migrationName, "009_add_server_id_to_duels") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "already exists") != -1 ||
              StrContains(error, "Duplicate key name") != -1 ||
              StrContains(error, "multiple primary key") != -1 ||
              StrContains(error, "Multiple primary key") != -1 ||
              StrContains(error, "Unknown column") != -1)) ||
            (StrEqual(migrationName, "010_ensure_duel_ids_autoincrement") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "already exists") != -1 ||
              StrContains(error, "Duplicate key name") != -1 ||
              StrContains(error, "multiple primary key") != -1 ||
              StrContains(error, "Multiple primary key") != -1 ||
              StrContains(error, "Unknown column") != -1)) ||
            (StrEqual(migrationName, "012_add_compact_round_json") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "already exists") != -1 ||
              StrContains(error, "Unknown column") != -1)) ||
            (StrEqual(migrationName, "011_round_slot_normalization") &&
             (StrContains(error, "duplicate column name") != -1 ||
              StrContains(error, "Duplicate column name") != -1 ||
              StrContains(error, "already exists") != -1 ||
              StrContains(error, "Unknown column") != -1 ||
              StrContains(error, "no such column") != -1 ||
              StrContains(error, "Can't DROP") != -1 ||
              StrContains(error, "check that column/key exists") != -1 ||
              StrContains(error, "Illegal mix of collations") != -1)))
        {
            LogMessage("[Migration %s] Step %d skipped (already applied): %s", migrationName, stepNumber, error);
            stepSkipped = true;
        }
        else if (StrContains(error, "duplicate column name") != -1 ||
                 StrContains(error, "Duplicate column name") != -1)
        {
            // Generic handling for duplicate column errors
            LogMessage("[Migration %s] Step %d skipped (column already exists): %s", migrationName, stepNumber, error);
            stepSkipped = true;
        }
        else
        {
            LogError("[Migration %s] Step %d failed: %s", migrationName, stepNumber, error);
            return;
        }
    }

    // Get expected total steps for this migration
    int totalSteps;
    if (!g_migrationProgress.GetValue(migrationName, totalSteps))
    {
        LogError("[Migration %s] No step count registered for migration", migrationName);
        return;
    }

    // Get current progress (completed steps)
    char progressKey[128];
    Format(progressKey, sizeof(progressKey), "%s_completed", migrationName);
    int completedSteps;
    g_migrationProgress.GetValue(progressKey, completedSteps);

    completedSteps++;
    g_migrationProgress.SetValue(progressKey, completedSteps);

    if (stepSkipped)
        LogMessage("[Migration %s] Step %d/%d skipped", migrationName, completedSteps, totalSteps);
    else
        LogMessage("[Migration %s] Step %d/%d completed", migrationName, completedSteps, totalSteps);

    // When all steps are complete, mark migration as done
    if (completedSteps >= totalSteps)
    {
        LogMessage("[Migration %s] All steps completed successfully", migrationName);
        MarkMigrationComplete(migrationName);

        // Clean up progress tracking for this migration
        g_migrationProgress.Remove(migrationName);
        g_migrationProgress.Remove(progressKey);
    }
}

// Processes migration completion marking results with error logging
void MarkMigrationCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Migrations] Database connection lost while marking migration complete");
        return;
    }
    
    if (!StrEqual("", error))
    {
        LogError("[Migrations] Failed to mark migration complete: %s", error);
        return;
    }
}


// ===== SPECIFIC MIGRATIONS =====

// Adds class tracking columns to duel tables for both 1v1 and 2v2 matches
void Migration_001_AddClassColumns()
{
    LogMessage("[Migration 001] Adding class tracking columns");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN winnerclass TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN loserclass TEXT DEFAULT NULL", 2);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winnerclass TEXT DEFAULT NULL", 3);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2class TEXT DEFAULT NULL", 4);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loserclass TEXT DEFAULT NULL", 5);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2class TEXT DEFAULT NULL", 6);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN winnerclass VARCHAR(64) DEFAULT NULL", 1);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels ADD COLUMN loserclass VARCHAR(64) DEFAULT NULL", 2);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winnerclass VARCHAR(64) DEFAULT NULL", 3);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2class VARCHAR(64) DEFAULT NULL", 4);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loserclass VARCHAR(64) DEFAULT NULL", 5);
            ExecuteMigrationStep("001_add_class_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2class VARCHAR(64) DEFAULT NULL", 6);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('001_add_class_columns', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Converts gametime to endtime and adds starttime column for better duel tracking
void Migration_002_DuelTimingColumns()
{
    LogMessage("[Migration 002] Converting gametime to endtime and adding starttime column");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels ADD COLUMN starttime INTEGER DEFAULT NULL", 1);
            ExecuteMigrationStep("002_duel_timing_columns", "UPDATE mgemod_duels SET starttime = gametime WHERE starttime IS NULL", 2);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels RENAME COLUMN gametime TO endtime", 3);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN starttime INTEGER DEFAULT NULL", 4);
            ExecuteMigrationStep("002_duel_timing_columns", "UPDATE mgemod_duels_2v2 SET starttime = gametime WHERE starttime IS NULL", 5);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 RENAME COLUMN gametime TO endtime", 6);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels ADD COLUMN starttime INT(11) DEFAULT NULL", 1);
            ExecuteMigrationStep("002_duel_timing_columns", "UPDATE mgemod_duels SET starttime = gametime WHERE starttime IS NULL", 2);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels CHANGE gametime endtime INT(11) NOT NULL", 3);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN starttime INT(11) DEFAULT NULL", 4);
            ExecuteMigrationStep("002_duel_timing_columns", "UPDATE mgemod_duels_2v2 SET starttime = gametime WHERE starttime IS NULL", 5);
            ExecuteMigrationStep("002_duel_timing_columns", "ALTER TABLE mgemod_duels_2v2 CHANGE gametime endtime INT(11) NOT NULL", 6);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('002_duel_timing_columns', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Adds primary keys to database tables and creates necessary indexes
void Migration_003_AddPrimaryKeys()
{
    LogMessage("[Migration 003] Adding primary keys to database tables");
    
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_backup AS SELECT * FROM mgemod_duels", 1);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_new (id INTEGER PRIMARY KEY, winner TEXT, loser TEXT, winnerscore INTEGER, loserscore INTEGER, winlimit INTEGER, endtime INTEGER, starttime INTEGER, mapname TEXT, arenaname TEXT, winnerclass TEXT, loserclass TEXT)", 2);
            ExecuteMigrationStep("003_add_primary_keys", "INSERT INTO mgemod_duels_new SELECT NULL, winner, loser, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, loserclass FROM mgemod_duels", 3);
            ExecuteMigrationStep("003_add_primary_keys", "DROP TABLE mgemod_duels", 4);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels_new RENAME TO mgemod_duels", 5);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_2v2_backup AS SELECT * FROM mgemod_duels_2v2", 6);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE TABLE mgemod_duels_2v2_new (id INTEGER PRIMARY KEY, winner TEXT, winner2 TEXT, loser TEXT, loser2 TEXT, winnerscore INTEGER, loserscore INTEGER, winlimit INTEGER, endtime INTEGER, starttime INTEGER, mapname TEXT, arenaname TEXT, winnerclass TEXT, winner2class TEXT, loserclass TEXT, loser2class TEXT)", 7);
            ExecuteMigrationStep("003_add_primary_keys", "INSERT INTO mgemod_duels_2v2_new SELECT NULL, winner, winner2, loser, loser2, winnerscore, loserscore, winlimit, endtime, starttime, mapname, arenaname, winnerclass, winner2class, loserclass, loser2class FROM mgemod_duels_2v2", 8);
            ExecuteMigrationStep("003_add_primary_keys", "DROP TABLE mgemod_duels_2v2", 9);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels_2v2_new RENAME TO mgemod_duels_2v2", 10);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE UNIQUE INDEX IF NOT EXISTS idx_stats_steamid ON mgemod_stats (steamid)", 11);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY FIRST", 1);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY FIRST", 2);
            ExecuteMigrationStep("003_add_primary_keys", "ALTER TABLE mgemod_stats ADD PRIMARY KEY (steamid(32))", 3);
            ExecuteMigrationStep("003_add_primary_keys", "CREATE UNIQUE INDEX idx_stats_steamid ON mgemod_stats (steamid(32))", 4);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('003_add_primary_keys', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Adds ELO tracking columns to record rating changes for each duel participant
void Migration_004_AddEloTracking()
{
    LogMessage("[Migration 004] Adding ELO tracking columns to duel tables");
    
    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_previous_elo INTEGER DEFAULT NULL", 1);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_new_elo INTEGER DEFAULT NULL", 2);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_previous_elo INTEGER DEFAULT NULL", 3);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_new_elo INTEGER DEFAULT NULL", 4);
            
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_previous_elo INTEGER DEFAULT NULL", 5);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_new_elo INTEGER DEFAULT NULL", 6);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_previous_elo INTEGER DEFAULT NULL", 7);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_new_elo INTEGER DEFAULT NULL", 8);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_previous_elo INTEGER DEFAULT NULL", 9);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_new_elo INTEGER DEFAULT NULL", 10);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_previous_elo INTEGER DEFAULT NULL", 11);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_new_elo INTEGER DEFAULT NULL", 12);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_previous_elo INT(4) DEFAULT NULL", 1);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN winner_new_elo INT(4) DEFAULT NULL", 2);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_previous_elo INT(4) DEFAULT NULL", 3);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels ADD COLUMN loser_new_elo INT(4) DEFAULT NULL", 4);
            
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_previous_elo INT(4) DEFAULT NULL", 5);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_new_elo INT(4) DEFAULT NULL", 6);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_previous_elo INT(4) DEFAULT NULL", 7);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_new_elo INT(4) DEFAULT NULL", 8);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_previous_elo INT(4) DEFAULT NULL", 9);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_new_elo INT(4) DEFAULT NULL", 10);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_previous_elo INT(4) DEFAULT NULL", 11);
            ExecuteMigrationStep("004_add_elo_tracking", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_new_elo INT(4) DEFAULT NULL", 12);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('004_add_elo_tracking', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Adds cancel fields to duel tables for duel cancellation functionality
void Migration_005_AddCancelFields()
{
    LogMessage("[Migration 005] Adding cancel fields to duel tables");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels ADD COLUMN canceled INTEGER DEFAULT 0", 1);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels ADD COLUMN canceled_reason TEXT DEFAULT NULL", 2);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels ADD COLUMN canceled_by TEXT DEFAULT NULL", 3);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN canceled INTEGER DEFAULT 0", 4);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN canceled_reason TEXT DEFAULT NULL", 5);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN canceled_by TEXT DEFAULT NULL", 6);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels ADD COLUMN canceled TINYINT(1) DEFAULT 0", 1);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels ADD COLUMN canceled_reason TEXT DEFAULT NULL", 2);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels ADD COLUMN canceled_by VARCHAR(32) DEFAULT NULL", 3);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN canceled TINYINT(1) DEFAULT 0", 4);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN canceled_reason TEXT DEFAULT NULL", 5);
            ExecuteMigrationStep("005_add_cancel_fields", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN canceled_by VARCHAR(32) DEFAULT NULL", 6);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('005_add_cancel_fields', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Adds class rating columns to player stats table
void Migration_006_AddClassRatings()
{
    LogMessage("[Migration 006] Adding class rating columns to mgemod_stats");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN scout_rating INTEGER DEFAULT 1600", 1);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN sniper_rating INTEGER DEFAULT 1600", 2);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN soldier_rating INTEGER DEFAULT 1600", 3);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN demoman_rating INTEGER DEFAULT 1600", 4);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN medic_rating INTEGER DEFAULT 1600", 5);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN heavy_rating INTEGER DEFAULT 1600", 6);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN pyro_rating INTEGER DEFAULT 1600", 7);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN spy_rating INTEGER DEFAULT 1600", 8);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN engineer_rating INTEGER DEFAULT 1600", 9);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN scout_rating INT(4) NOT NULL DEFAULT 1600", 1);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN sniper_rating INT(4) NOT NULL DEFAULT 1600", 2);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN soldier_rating INT(4) NOT NULL DEFAULT 1600", 3);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN demoman_rating INT(4) NOT NULL DEFAULT 1600", 4);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN medic_rating INT(4) NOT NULL DEFAULT 1600", 5);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN heavy_rating INT(4) NOT NULL DEFAULT 1600", 6);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN pyro_rating INT(4) NOT NULL DEFAULT 1600", 7);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN spy_rating INT(4) NOT NULL DEFAULT 1600", 8);
            ExecuteMigrationStep("006_add_class_ratings", "ALTER TABLE mgemod_stats ADD COLUMN engineer_rating INT(4) NOT NULL DEFAULT 1600", 9);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('006_add_class_ratings', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Adds weapon id tracking columns to duel tables (1v1 + 2v2)
void Migration_007_AddWeaponIdColumns()
{
    LogMessage("[Migration 007] Adding weapon id columns to duel tables");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels ADD COLUMN winnerweaponids TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels ADD COLUMN loserweaponids TEXT DEFAULT NULL", 2);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winnerweaponids TEXT DEFAULT NULL", 3);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2weaponids TEXT DEFAULT NULL", 4);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loserweaponids TEXT DEFAULT NULL", 5);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2weaponids TEXT DEFAULT NULL", 6);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels ADD COLUMN winnerweaponids TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels ADD COLUMN loserweaponids TEXT DEFAULT NULL", 2);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winnerweaponids TEXT DEFAULT NULL", 3);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2weaponids TEXT DEFAULT NULL", 4);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loserweaponids TEXT DEFAULT NULL", 5);
            ExecuteMigrationStep("007_add_weapon_id_columns", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2weaponids TEXT DEFAULT NULL", 6);
        }
        case DB_POSTGRESQL:
        {
            // PostgreSQL gets modern schema immediately in CREATE TABLE statements
            // But we still need to mark this migration as complete for consistency
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('007_add_weapon_id_columns', %d) ON CONFLICT (migration_name) DO NOTHING", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Adds dedicated round log tables linked to 1v1 and 2v2 duel rows
void Migration_008_AddRoundLogs()
{
    LogMessage("[Migration 008] Creating round log tables for 1v1 and 2v2");

    char query[4096];

    GetCreateTableQuery_DuelRounds1v1(query, sizeof(query));
    ExecuteMigrationStep("008_add_round_logs", query, 1);

    GetCreateTableQuery_DuelRounds2v2(query, sizeof(query));
    ExecuteMigrationStep("008_add_round_logs", query, 2);
}

// Adds server_id to duel tables so duel logs can be separated by server
void Migration_009_AddServerIdToDuels()
{
    LogMessage("[Migration 009] Adding server_id to duel tables");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("009_add_server_id_to_duels", "ALTER TABLE mgemod_duels ADD COLUMN server_id INTEGER NOT NULL DEFAULT 1", 1);
            ExecuteMigrationStep("009_add_server_id_to_duels", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN server_id INTEGER NOT NULL DEFAULT 1", 2);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("009_add_server_id_to_duels", "ALTER TABLE mgemod_duels ADD COLUMN server_id INT(11) NOT NULL DEFAULT 1", 1);
            ExecuteMigrationStep("009_add_server_id_to_duels", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN server_id INT(11) NOT NULL DEFAULT 1", 2);
        }
        case DB_POSTGRESQL:
        {
            ExecuteMigrationStep("009_add_server_id_to_duels", "ALTER TABLE mgemod_duels ADD COLUMN server_id INTEGER NOT NULL DEFAULT 1", 1);
            ExecuteMigrationStep("009_add_server_id_to_duels", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN server_id INTEGER NOT NULL DEFAULT 1", 2);
        }
    }
}

// Ensures duel id columns exist and are auto-increment in MySQL so dependent tables can reference duel_id reliably
void Migration_010_EnsureDuelIdsAutoincrement()
{
    LogMessage("[Migration 010] Ensuring duel id columns are auto-increment");

    switch (g_DatabaseType)
    {
        case DB_MYSQL:
        {
            ExecuteMigrationStep("010_ensure_duel_ids_autoincrement", "ALTER TABLE mgemod_duels ADD COLUMN id INT(11) NULL FIRST", 1);
            ExecuteMigrationStep("010_ensure_duel_ids_autoincrement", "ALTER TABLE mgemod_duels ADD UNIQUE KEY uq_mgemod_duels_id (id)", 2);
            ExecuteMigrationStep("010_ensure_duel_ids_autoincrement", "ALTER TABLE mgemod_duels MODIFY COLUMN id INT(11) NOT NULL AUTO_INCREMENT", 3);
            ExecuteMigrationStep("010_ensure_duel_ids_autoincrement", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN id INT(11) NULL FIRST", 4);
            ExecuteMigrationStep("010_ensure_duel_ids_autoincrement", "ALTER TABLE mgemod_duels_2v2 ADD UNIQUE KEY uq_mgemod_duels_2v2_id (id)", 5);
            ExecuteMigrationStep("010_ensure_duel_ids_autoincrement", "ALTER TABLE mgemod_duels_2v2 MODIFY COLUMN id INT(11) NOT NULL AUTO_INCREMENT", 6);
        }
        default:
        {
            // Not needed outside MySQL; mark as complete for migration consistency.
            int currentTime = GetTime();
            char migrationQuery[256];
            g_DB.Format(migrationQuery, sizeof(migrationQuery), "INSERT INTO mgemod_migrations (migration_name, executed_at) VALUES ('010_ensure_duel_ids_autoincrement', %d)", currentTime);
            g_DB.Query(MarkMigrationCallback, migrationQuery);
        }
    }
}

// Normalizes round logs by storing scorer/victim slots instead of repeating SteamIDs each round.
void Migration_011_RoundSlotNormalization()
{
    LogMessage("[Migration 011] Normalizing round logs to slot-based identity mapping");

    switch (g_DatabaseType)
    {
        case DB_MYSQL:
        {
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels ADD COLUMN winner_slot TINYINT NULL DEFAULT NULL", 1);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels ADD COLUMN loser_slot TINYINT NULL DEFAULT NULL", 2);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_slot TINYINT NULL DEFAULT NULL", 3);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_slot TINYINT NULL DEFAULT NULL", 4);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_slot TINYINT NULL DEFAULT NULL", 5);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_slot TINYINT NULL DEFAULT NULL", 6);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 ADD COLUMN scorer_slot TINYINT NULL DEFAULT NULL", 7);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 ADD COLUMN victim_slot TINYINT NULL DEFAULT NULL", 8);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 ADD COLUMN scorer_slot TINYINT NULL DEFAULT NULL", 9);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 ADD COLUMN victim_slot TINYINT NULL DEFAULT NULL", 10);

            // Backfill duel-level slot mapping from historical round snapshots.
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duels d INNER JOIN mgemod_duel_rounds_1v1 r ON r.duel_id = d.id SET d.winner_slot = 1 WHERE d.winner_slot IS NULL AND BINARY d.winner = BINARY r.slot1_steamid", 11);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duels d INNER JOIN mgemod_duel_rounds_1v1 r ON r.duel_id = d.id SET d.winner_slot = 2 WHERE d.winner_slot IS NULL AND BINARY d.winner = BINARY r.slot2_steamid", 12);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duels d INNER JOIN mgemod_duel_rounds_1v1 r ON r.duel_id = d.id SET d.loser_slot = 1 WHERE d.loser_slot IS NULL AND BINARY d.loser = BINARY r.slot1_steamid", 13);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duels d INNER JOIN mgemod_duel_rounds_1v1 r ON r.duel_id = d.id SET d.loser_slot = 2 WHERE d.loser_slot IS NULL AND BINARY d.loser = BINARY r.slot2_steamid", 14);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duels_2v2 d INNER JOIN mgemod_duel_rounds_2v2 r ON r.duel_id = d.id SET d.winner_slot = COALESCE(d.winner_slot, CASE WHEN BINARY d.winner = BINARY r.slot1_steamid THEN 1 WHEN BINARY d.winner = BINARY r.slot2_steamid THEN 2 WHEN BINARY d.winner = BINARY r.slot3_steamid THEN 3 WHEN BINARY d.winner = BINARY r.slot4_steamid THEN 4 ELSE NULL END), d.winner2_slot = COALESCE(d.winner2_slot, CASE WHEN BINARY d.winner2 = BINARY r.slot1_steamid THEN 1 WHEN BINARY d.winner2 = BINARY r.slot2_steamid THEN 2 WHEN BINARY d.winner2 = BINARY r.slot3_steamid THEN 3 WHEN BINARY d.winner2 = BINARY r.slot4_steamid THEN 4 ELSE NULL END), d.loser_slot = COALESCE(d.loser_slot, CASE WHEN BINARY d.loser = BINARY r.slot1_steamid THEN 1 WHEN BINARY d.loser = BINARY r.slot2_steamid THEN 2 WHEN BINARY d.loser = BINARY r.slot3_steamid THEN 3 WHEN BINARY d.loser = BINARY r.slot4_steamid THEN 4 ELSE NULL END), d.loser2_slot = COALESCE(d.loser2_slot, CASE WHEN BINARY d.loser2 = BINARY r.slot1_steamid THEN 1 WHEN BINARY d.loser2 = BINARY r.slot2_steamid THEN 2 WHEN BINARY d.loser2 = BINARY r.slot3_steamid THEN 3 WHEN BINARY d.loser2 = BINARY r.slot4_steamid THEN 4 ELSE NULL END) WHERE d.winner_slot IS NULL OR d.winner2_slot IS NULL OR d.loser_slot IS NULL OR d.loser2_slot IS NULL", 15);

            // Backfill round scorer/victim slots from old round SteamID data.
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duel_rounds_1v1 SET scorer_slot = CASE WHEN scorer_steamid = slot1_steamid THEN 1 WHEN scorer_steamid = slot2_steamid THEN 2 ELSE scorer_slot END WHERE scorer_slot IS NULL", 16);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duel_rounds_1v1 SET victim_slot = CASE WHEN victim_steamid = slot1_steamid THEN 1 WHEN victim_steamid = slot2_steamid THEN 2 ELSE victim_slot END WHERE victim_slot IS NULL", 17);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duel_rounds_2v2 SET scorer_slot = CASE WHEN scorer_steamid = slot1_steamid THEN 1 WHEN scorer_steamid = slot2_steamid THEN 2 WHEN scorer_steamid = slot3_steamid THEN 3 WHEN scorer_steamid = slot4_steamid THEN 4 ELSE scorer_slot END WHERE scorer_slot IS NULL", 18);
            ExecuteMigrationStep("011_round_slot_normalization", "UPDATE mgemod_duel_rounds_2v2 SET victim_slot = CASE WHEN victim_steamid = slot1_steamid THEN 1 WHEN victim_steamid = slot2_steamid THEN 2 WHEN victim_steamid = slot3_steamid THEN 3 WHEN victim_steamid = slot4_steamid THEN 4 ELSE victim_slot END WHERE victim_slot IS NULL", 19);

            // Drop old per-round SteamID columns to save storage.
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 DROP COLUMN scorer_steamid", 20);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 DROP COLUMN victim_steamid", 21);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 DROP COLUMN slot1_steamid", 22);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 DROP COLUMN slot2_steamid", 23);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 DROP COLUMN scorer_steamid", 24);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 DROP COLUMN victim_steamid", 25);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 DROP COLUMN slot1_steamid", 26);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 DROP COLUMN slot2_steamid", 27);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 DROP COLUMN slot3_steamid", 28);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 DROP COLUMN slot4_steamid", 29);
        }
        case DB_SQLITE:
        {
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels ADD COLUMN winner_slot INTEGER DEFAULT NULL", 1);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels ADD COLUMN loser_slot INTEGER DEFAULT NULL", 2);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_slot INTEGER DEFAULT NULL", 3);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_slot INTEGER DEFAULT NULL", 4);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_slot INTEGER DEFAULT NULL", 5);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_slot INTEGER DEFAULT NULL", 6);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 ADD COLUMN scorer_slot INTEGER DEFAULT NULL", 7);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 ADD COLUMN victim_slot INTEGER DEFAULT NULL", 8);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 ADD COLUMN scorer_slot INTEGER DEFAULT NULL", 9);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 ADD COLUMN victim_slot INTEGER DEFAULT NULL", 10);
        }
        case DB_POSTGRESQL:
        {
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels ADD COLUMN winner_slot INTEGER DEFAULT NULL", 1);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels ADD COLUMN loser_slot INTEGER DEFAULT NULL", 2);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner_slot INTEGER DEFAULT NULL", 3);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN winner2_slot INTEGER DEFAULT NULL", 4);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser_slot INTEGER DEFAULT NULL", 5);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN loser2_slot INTEGER DEFAULT NULL", 6);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 ADD COLUMN scorer_slot INTEGER DEFAULT NULL", 7);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_1v1 ADD COLUMN victim_slot INTEGER DEFAULT NULL", 8);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 ADD COLUMN scorer_slot INTEGER DEFAULT NULL", 9);
            ExecuteMigrationStep("011_round_slot_normalization", "ALTER TABLE mgemod_duel_rounds_2v2 ADD COLUMN victim_slot INTEGER DEFAULT NULL", 10);
        }
    }
}

// Adds compact per-duel round JSON column for reduced storage footprint.
void Migration_012_AddCompactRoundJson()
{
    LogMessage("[Migration 012] Adding compact round JSON columns to duel tables");

    switch (g_DatabaseType)
    {
        case DB_SQLITE:
        {
            ExecuteMigrationStep("012_add_compact_round_json", "ALTER TABLE mgemod_duels ADD COLUMN rounds_compact_json TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("012_add_compact_round_json", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN rounds_compact_json TEXT DEFAULT NULL", 2);
        }
        case DB_MYSQL:
        {
            ExecuteMigrationStep("012_add_compact_round_json", "ALTER TABLE mgemod_duels ADD COLUMN rounds_compact_json TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("012_add_compact_round_json", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN rounds_compact_json TEXT DEFAULT NULL", 2);
        }
        case DB_POSTGRESQL:
        {
            ExecuteMigrationStep("012_add_compact_round_json", "ALTER TABLE mgemod_duels ADD COLUMN rounds_compact_json TEXT DEFAULT NULL", 1);
            ExecuteMigrationStep("012_add_compact_round_json", "ALTER TABLE mgemod_duels_2v2 ADD COLUMN rounds_compact_json TEXT DEFAULT NULL", 2);
        }
    }
}
