// ===== ROUND LOG TRACKING =====

enum RoundEndReason
{
    RoundEndReason_Kill = 1,
    RoundEndReason_ClassChange,
    RoundEndReason_KothCap,
    RoundEndReason_BBallGoal
}

enum struct RoundLogEntry
{
    int roundNumber;
    int startTime;
    int endTime;
    int duration;
    int winnerTeamSlot;
    int endReason;
    int scoreRedBefore;
    int scoreBluBefore;
    int scoreRedAfter;
    int scoreBluAfter;
    int scoringWeaponDefIndex;
    int scorerSlot;
    int victimSlot;

    char slot1Class[16];
    char slot2Class[16];
    char slot3Class[16];
    char slot4Class[16];

    int slot1Hp;
    int slot2Hp;
    int slot3Hp;
    int slot4Hp;

    char slot1WeaponIds[256];
    char slot2WeaponIds[256];
    char slot3WeaponIds[256];
    char slot4WeaponIds[256];
}

bool IsRoundLogArenaValid(int arena_index)
{
    return (arena_index > 0 && arena_index <= g_iArenaCount);
}

void EnsureArenaRoundLogList(int arena_index)
{
    if (!IsRoundLogArenaValid(arena_index))
        return;

    if (g_alArenaRoundLogs[arena_index] == null)
        g_alArenaRoundLogs[arena_index] = new ArrayList(sizeof(RoundLogEntry));
}

void ResetArenaRoundLogging(int arena_index)
{
    if (!IsRoundLogArenaValid(arena_index))
        return;

    EnsureArenaRoundLogList(arena_index);
    g_alArenaRoundLogs[arena_index].Clear();
    g_iArenaRoundNumber[arena_index] = 0;
    g_iArenaRoundStartTime[arena_index] = 0;
    g_fArenaRoundStartGameTime[arena_index] = 0.0;
    g_bArenaRoundInProgress[arena_index] = false;
}

void StartArenaRoundLogging(int arena_index)
{
    if (!IsRoundLogArenaValid(arena_index))
        return;
    if (g_iArenaStatus[arena_index] < AS_FIGHT || g_iArenaStatus[arena_index] >= AS_REPORTED)
        return;

    EnsureArenaRoundLogList(arena_index);
    g_iArenaRoundNumber[arena_index]++;
    g_iArenaRoundStartTime[arena_index] = GetTime();
    g_fArenaRoundStartGameTime[arena_index] = GetGameTime();
    g_bArenaRoundInProgress[arena_index] = true;
}

bool AreArenaRoundParticipantsAlive(int arena_index)
{
    if (!IsRoundLogArenaValid(arena_index))
        return false;

    int max_active_slot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    for (int slot = SLOT_ONE; slot <= max_active_slot; slot++)
    {
        int client = g_iArenaQueue[arena_index][slot];
        if (!IsValidClient(client))
            return false;
        if (!IsPlayerAlive(client))
            return false;
    }

    return true;
}

void TryStartArenaRoundLoggingOnSpawn(int arena_index)
{
    if (!IsRoundLogArenaValid(arena_index))
        return;
    if (g_bArenaRoundInProgress[arena_index])
        return;
    if (g_iArenaStatus[arena_index] != AS_FIGHT)
        return;
    if (!AreArenaRoundParticipantsAlive(arena_index))
        return;

    StartArenaRoundLogging(arena_index);
}

int GetClientScoringWeaponDefIndex(int client)
{
    if (!IsValidClient(client))
        return 0;

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEntity(weapon))
        return 0;
    if (!HasEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"))
        return 0;

    return GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
}

void GetClientClassNameForRound(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (!IsValidClient(client))
        return;

    TFClassType classType = g_tfctPlayerClass[client];
    if (classType == TFClass_Unknown)
        classType = TF2_GetPlayerClass(client);

    switch (classType)
    {
        case TFClass_Scout: strcopy(buffer, maxlen, "scout");
        case TFClass_Sniper: strcopy(buffer, maxlen, "sniper");
        case TFClass_Soldier: strcopy(buffer, maxlen, "soldier");
        case TFClass_DemoMan: strcopy(buffer, maxlen, "demoman");
        case TFClass_Medic: strcopy(buffer, maxlen, "medic");
        case TFClass_Heavy: strcopy(buffer, maxlen, "heavy");
        case TFClass_Pyro: strcopy(buffer, maxlen, "pyro");
        case TFClass_Spy: strcopy(buffer, maxlen, "spy");
        case TFClass_Engineer: strcopy(buffer, maxlen, "engineer");
        default: strcopy(buffer, maxlen, "unknown");
    }
}

void InitRoundLogEntry(RoundLogEntry entry)
{
    entry.roundNumber = 0;
    entry.startTime = 0;
    entry.endTime = 0;
    entry.duration = 0;
    entry.winnerTeamSlot = 0;
    entry.endReason = 0;
    entry.scoreRedBefore = 0;
    entry.scoreBluBefore = 0;
    entry.scoreRedAfter = 0;
    entry.scoreBluAfter = 0;
    entry.scoringWeaponDefIndex = 0;
    entry.scorerSlot = 0;
    entry.victimSlot = 0;

    entry.slot1Class[0] = '\0';
    entry.slot2Class[0] = '\0';
    entry.slot3Class[0] = '\0';
    entry.slot4Class[0] = '\0';

    entry.slot1Hp = 0;
    entry.slot2Hp = 0;
    entry.slot3Hp = 0;
    entry.slot4Hp = 0;

    entry.slot1WeaponIds[0] = '\0';
    entry.slot2WeaponIds[0] = '\0';
    entry.slot3WeaponIds[0] = '\0';
    entry.slot4WeaponIds[0] = '\0';
}

void SetRoundLogSlotDataBySlot(int slot, RoundLogEntry entry, const char[] className, int hp, const char[] weaponIds)
{
    switch (slot)
    {
        case SLOT_ONE:
        {
            strcopy(entry.slot1Class, sizeof(entry.slot1Class), className);
            strcopy(entry.slot1WeaponIds, sizeof(entry.slot1WeaponIds), weaponIds);
            entry.slot1Hp = hp;
        }
        case SLOT_TWO:
        {
            strcopy(entry.slot2Class, sizeof(entry.slot2Class), className);
            strcopy(entry.slot2WeaponIds, sizeof(entry.slot2WeaponIds), weaponIds);
            entry.slot2Hp = hp;
        }
        case SLOT_THREE:
        {
            strcopy(entry.slot3Class, sizeof(entry.slot3Class), className);
            strcopy(entry.slot3WeaponIds, sizeof(entry.slot3WeaponIds), weaponIds);
            entry.slot3Hp = hp;
        }
        case SLOT_FOUR:
        {
            strcopy(entry.slot4Class, sizeof(entry.slot4Class), className);
            strcopy(entry.slot4WeaponIds, sizeof(entry.slot4WeaponIds), weaponIds);
            entry.slot4Hp = hp;
        }
    }
}

void FillRoundLogSlotSnapshot(int arena_index, int slot, RoundLogEntry entry)
{
    int client = g_iArenaQueue[arena_index][slot];
    if (!IsValidClient(client))
        return;

    char className[16];
    GetClientClassNameForRound(client, className, sizeof(className));

    char weaponIds[256];
    GetPlayerCurrentWeaponIdsString(client, weaponIds, sizeof(weaponIds));

    int hp = 0;
    if (IsPlayerAlive(client))
        hp = GetClientHealth(client);
    else if (g_iPlayerHP[client] > 0)
        hp = g_iPlayerHP[client];

    SetRoundLogSlotDataBySlot(slot, entry, className, hp, weaponIds);
}

void RecordArenaRoundEnd(int arena_index, int winner_team_slot, RoundEndReason end_reason, int scorer, int victim, int scoring_weapon_defindex, int score_red_before, int score_blu_before, int score_red_after, int score_blu_after)
{
    if (!IsRoundLogArenaValid(arena_index))
        return;

    EnsureArenaRoundLogList(arena_index);

    if (!g_bArenaRoundInProgress[arena_index])
    {
        g_iArenaRoundNumber[arena_index]++;
        g_iArenaRoundStartTime[arena_index] = GetTime();
        g_fArenaRoundStartGameTime[arena_index] = GetGameTime();
        g_bArenaRoundInProgress[arena_index] = true;
    }

    RoundLogEntry entry;
    InitRoundLogEntry(entry);

    entry.roundNumber = g_iArenaRoundNumber[arena_index];
    entry.startTime = g_iArenaRoundStartTime[arena_index];
    entry.endTime = GetTime();
    float durationSeconds = GetGameTime() - g_fArenaRoundStartGameTime[arena_index];
    entry.duration = RoundToCeil(durationSeconds);
    if (entry.duration < 0)
        entry.duration = 0;

    entry.winnerTeamSlot = winner_team_slot;
    entry.endReason = view_as<int>(end_reason);
    entry.scoreRedBefore = score_red_before;
    entry.scoreBluBefore = score_blu_before;
    entry.scoreRedAfter = score_red_after;
    entry.scoreBluAfter = score_blu_after;
    entry.scoringWeaponDefIndex = scoring_weapon_defindex;
    if (IsValidClient(scorer))
        entry.scorerSlot = g_iPlayerSlot[scorer];
    if (IsValidClient(victim))
        entry.victimSlot = g_iPlayerSlot[victim];

    int max_active_slot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    for (int slot = SLOT_ONE; slot <= max_active_slot; slot++)
    {
        FillRoundLogSlotSnapshot(arena_index, slot, entry);
    }

    g_alArenaRoundLogs[arena_index].PushArray(entry, sizeof(entry));
    g_bArenaRoundInProgress[arena_index] = false;
    g_iArenaRoundStartTime[arena_index] = 0;
    g_fArenaRoundStartGameTime[arena_index] = 0.0;
}

ArrayList DetachArenaRoundEntriesForPersist(int arena_index)
{
    if (!IsRoundLogArenaValid(arena_index))
        return null;

    EnsureArenaRoundLogList(arena_index);

    if (g_alArenaRoundLogs[arena_index].Length == 0)
    {
        g_iArenaRoundNumber[arena_index] = 0;
        g_iArenaRoundStartTime[arena_index] = 0;
        g_fArenaRoundStartGameTime[arena_index] = 0.0;
        g_bArenaRoundInProgress[arena_index] = false;
        return null;
    }

    ArrayList detached = new ArrayList(sizeof(RoundLogEntry));
    RoundLogEntry entry;
    for (int i = 0; i < g_alArenaRoundLogs[arena_index].Length; i++)
    {
        g_alArenaRoundLogs[arena_index].GetArray(i, entry, sizeof(entry));
        detached.PushArray(entry, sizeof(entry));
    }

    g_alArenaRoundLogs[arena_index].Clear();
    g_iArenaRoundNumber[arena_index] = 0;
    g_iArenaRoundStartTime[arena_index] = 0;
    g_fArenaRoundStartGameTime[arena_index] = 0.0;
    g_bArenaRoundInProgress[arena_index] = false;
    return detached;
}
