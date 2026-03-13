// ===== ENTITY MANAGEMENT =====

void RemoveEntityByRef(int &entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity > 0 && IsValidEntity(entity))
        RemoveEdict(entity);
    entityRef = 0;
}

// ===== SCOREBOARD =====

enum
{
    BBALL_TIMER_MIN_TENS = 0,
    BBALL_TIMER_MIN_ONES,
    BBALL_TIMER_SEC_TENS,
    BBALL_TIMER_SEC_ONES
}

enum
{
    BBALL_SCORE_TEAM_RED = 0,
    BBALL_SCORE_TEAM_BLU
}

enum
{
    BBALL_SCORE_TENS = 0,
    BBALL_SCORE_ONES
}

void ResetBBallScoreboardCache(int arena_index)
{
    if (arena_index < 0 || arena_index > MAXARENAS)
        return;

    for (int i = 0; i < 4; i++)
        g_iBBallTimerEntRef[arena_index][i] = INVALID_ENT_REFERENCE;

    for (int team = 0; team < 2; team++)
    {
        for (int digit = 0; digit < 2; digit++)
            g_iBBallScoreEntRef[arena_index][team][digit] = INVALID_ENT_REFERENCE;
    }
}

void GetBBallScoreboardModeForArena(int arena_index, char[] mode, int modeSize)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount)
    {
        strcopy(mode, modeSize, "1v1");
        return;
    }

    strcopy(mode, modeSize, g_bFourPersonArena[arena_index] ? "2v2" : "1v1");
}

float GetArenaClosestSpawnDistSqr(int arena_index, float origin[3])
{
    float bestDistSqr = -1.0;

    if (g_bArenaUseTeamSpawns[arena_index])
    {
        for (int i = 1; i <= g_iArenaRedSpawns[arena_index]; i++)
        {
            float distSqr = GetVectorDistance(origin, g_fArenaRedSpawnOrigin[arena_index][i], true);
            if (bestDistSqr < 0.0 || distSqr < bestDistSqr)
                bestDistSqr = distSqr;
        }

        for (int i = 1; i <= g_iArenaBluSpawns[arena_index]; i++)
        {
            float distSqr = GetVectorDistance(origin, g_fArenaBluSpawnOrigin[arena_index][i], true);
            if (bestDistSqr < 0.0 || distSqr < bestDistSqr)
                bestDistSqr = distSqr;
        }
    }

    if (bestDistSqr < 0.0)
    {
        for (int i = 1; i <= g_iArenaSpawns[arena_index]; i++)
        {
            float distSqr = GetVectorDistance(origin, g_fArenaSpawnOrigin[arena_index][i], true);
            if (bestDistSqr < 0.0 || distSqr < bestDistSqr)
                bestDistSqr = distSqr;
        }
    }

    return bestDistSqr;
}

void GetBBallHoopGoalOrigin(int arena_index, int goalSlot, float origin[3])
{
    if (goalSlot == SLOT_ONE)
    {
        if (g_bArenaBBallHoopSpawnRedSet[arena_index])
        {
            origin[0] = g_fArenaBBallHoopSpawnRed[arena_index][0];
            origin[1] = g_fArenaBBallHoopSpawnRed[arena_index][1];
            origin[2] = g_fArenaBBallHoopSpawnRed[arena_index][2];
        }
        else if (g_bArenaBBallHoopSpawnSet[arena_index])
        {
            origin[0] = g_fArenaBBallHoopSpawn[arena_index][0];
            origin[1] = g_fArenaBBallHoopSpawn[arena_index][1];
            origin[2] = g_fArenaBBallHoopSpawn[arena_index][2];
        }
        else
        {
            int spawnIndex = g_iArenaSpawns[arena_index] - 1;
            origin[0] = g_fArenaSpawnOrigin[arena_index][spawnIndex][0];
            origin[1] = g_fArenaSpawnOrigin[arena_index][spawnIndex][1];
            origin[2] = g_fArenaSpawnOrigin[arena_index][spawnIndex][2];
        }
    }
    else
    {
        if (g_bArenaBBallHoopSpawnBluSet[arena_index])
        {
            origin[0] = g_fArenaBBallHoopSpawnBlu[arena_index][0];
            origin[1] = g_fArenaBBallHoopSpawnBlu[arena_index][1];
            origin[2] = g_fArenaBBallHoopSpawnBlu[arena_index][2];
        }
        else if (g_bArenaBBallHoopSpawnSet[arena_index])
        {
            origin[0] = g_fArenaBBallHoopSpawn[arena_index][0];
            origin[1] = g_fArenaBBallHoopSpawn[arena_index][1];
            origin[2] = g_fArenaBBallHoopSpawn[arena_index][2];
        }
        else
        {
            int spawnIndex = g_iArenaSpawns[arena_index];
            origin[0] = g_fArenaSpawnOrigin[arena_index][spawnIndex][0];
            origin[1] = g_fArenaSpawnOrigin[arena_index][spawnIndex][1];
            origin[2] = g_fArenaSpawnOrigin[arena_index][spawnIndex][2];
        }
    }
}

int FindNearestBBallGoalTriggerForArena(int arena_index, const char[] targetName, int goalSlot)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount || targetName[0] == '\0')
        return INVALID_ENT_REFERENCE;

    int entity = -1;
    int bestEntity = -1;
    float bestDistSqr = -1.0;
    float goalOrigin[3];
    float origin[3];
    char nameBuf[64];

    GetBBallHoopGoalOrigin(arena_index, goalSlot, goalOrigin);

    while ((entity = FindEntityByClassname(entity, "trigger_capture_area")) != -1)
    {
        if (!IsValidEntity(entity))
            continue;

        GetEntPropString(entity, Prop_Data, "m_iName", nameBuf, sizeof(nameBuf));
        if (!StrEqual(nameBuf, targetName, false))
            continue;

        GetEntPropVector(entity, Prop_Data, "m_vecOrigin", origin);
        float distSqr = GetVectorDistance(goalOrigin, origin, true);
        if (bestEntity == -1 || distSqr < bestDistSqr)
        {
            bestEntity = entity;
            bestDistSqr = distSqr;
        }
    }

    if (bestEntity == -1)
        return INVALID_ENT_REFERENCE;

    return EntIndexToEntRef(bestEntity);
}

void UnhookBBallArenaGoalTriggers(int arena_index)
{
    if (arena_index <= 0 || arena_index > MAXARENAS)
        return;

    int redTrigger = EntRefToEntIndex(g_iBBallHoopTrigger[arena_index][SLOT_ONE]);
    int bluTrigger = EntRefToEntIndex(g_iBBallHoopTrigger[arena_index][SLOT_TWO]);

    if (redTrigger > MaxClients && IsValidEntity(redTrigger))
        SDKUnhook(redTrigger, SDKHook_StartTouch, OnTouchHoopTrigger);

    if (bluTrigger > MaxClients && bluTrigger != redTrigger && IsValidEntity(bluTrigger))
        SDKUnhook(bluTrigger, SDKHook_StartTouch, OnTouchHoopTrigger);

    g_iBBallHoopTrigger[arena_index][SLOT_ONE] = INVALID_ENT_REFERENCE;
    g_iBBallHoopTrigger[arena_index][SLOT_TWO] = INVALID_ENT_REFERENCE;
}

void RefreshBBallArenaGoalTriggers(int arena_index)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount || !g_bArenaBBall[arena_index])
        return;

    UnhookBBallArenaGoalTriggers(arena_index);

    int redTrigger = -1;
    int bluTrigger = -1;

    if (g_bArenaBBallHoopTriggerRedSet[arena_index] && g_sArenaBBallHoopTriggerRed[arena_index][0] != '\0')
    {
        g_iBBallHoopTrigger[arena_index][SLOT_ONE] = FindNearestBBallGoalTriggerForArena(arena_index, g_sArenaBBallHoopTriggerRed[arena_index], SLOT_ONE);
        redTrigger = EntRefToEntIndex(g_iBBallHoopTrigger[arena_index][SLOT_ONE]);
        if (redTrigger <= MaxClients || !IsValidEntity(redTrigger))
        {
            g_iBBallHoopTrigger[arena_index][SLOT_ONE] = INVALID_ENT_REFERENCE;
            LogError("[%s] Could not find trigger_capture_area '%s' for hooptrigger_red.", g_sArenaName[arena_index], g_sArenaBBallHoopTriggerRed[arena_index]);
            redTrigger = -1;
        }
    }

    if (g_bArenaBBallHoopTriggerBluSet[arena_index] && g_sArenaBBallHoopTriggerBlu[arena_index][0] != '\0')
    {
        g_iBBallHoopTrigger[arena_index][SLOT_TWO] = FindNearestBBallGoalTriggerForArena(arena_index, g_sArenaBBallHoopTriggerBlu[arena_index], SLOT_TWO);
        bluTrigger = EntRefToEntIndex(g_iBBallHoopTrigger[arena_index][SLOT_TWO]);
        if (bluTrigger <= MaxClients || !IsValidEntity(bluTrigger))
        {
            g_iBBallHoopTrigger[arena_index][SLOT_TWO] = INVALID_ENT_REFERENCE;
            LogError("[%s] Could not find trigger_capture_area '%s' for hooptrigger_blu.", g_sArenaName[arena_index], g_sArenaBBallHoopTriggerBlu[arena_index]);
            bluTrigger = -1;
        }
    }

    if (redTrigger > MaxClients && IsValidEntity(redTrigger))
        SDKHook(redTrigger, SDKHook_StartTouch, OnTouchHoopTrigger);

    if (bluTrigger > MaxClients && bluTrigger != redTrigger && IsValidEntity(bluTrigger))
        SDKHook(bluTrigger, SDKHook_StartTouch, OnTouchHoopTrigger);
}

int FindNearestBBallTextureToggleForArena(int arena_index, const char[] targetName)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount || targetName[0] == '\0')
        return INVALID_ENT_REFERENCE;

    int entity = -1;
    int bestEntity = -1;
    float bestDistSqr = -1.0;
    float origin[3];
    char nameBuf[64];

    while ((entity = FindEntityByClassname(entity, "env_texturetoggle")) != -1)
    {
        if (!IsValidEntity(entity))
            continue;

        GetEntPropString(entity, Prop_Data, "m_iName", nameBuf, sizeof(nameBuf));
        if (!StrEqual(nameBuf, targetName, false))
            continue;

        GetEntPropVector(entity, Prop_Data, "m_vecOrigin", origin);
        float distSqr = GetArenaClosestSpawnDistSqr(arena_index, origin);
        if (distSqr < 0.0)
            continue;

        if (bestEntity == -1 || distSqr < bestDistSqr)
        {
            bestEntity = entity;
            bestDistSqr = distSqr;
        }
    }

    if (bestEntity == -1)
        return INVALID_ENT_REFERENCE;

    return EntIndexToEntRef(bestEntity);
}

void CacheBBallScoreboardEntities()
{
    for (int arena = 0; arena <= MAXARENAS; arena++)
    {
        ResetBBallScoreboardCache(arena);

        if (arena <= 0 || arena > g_iArenaCount || !g_bArenaBBall[arena])
            continue;

        char mode[4];
        GetBBallScoreboardModeForArena(arena, mode, sizeof(mode));

        char targetName[64];

        Format(targetName, sizeof(targetName), "skin_bball_count_%s_1000", mode);
        g_iBBallTimerEntRef[arena][BBALL_TIMER_MIN_TENS] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_bball_count_%s_100", mode);
        g_iBBallTimerEntRef[arena][BBALL_TIMER_MIN_ONES] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_bball_count_%s_10", mode);
        g_iBBallTimerEntRef[arena][BBALL_TIMER_SEC_TENS] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_bball_count_%s_1", mode);
        g_iBBallTimerEntRef[arena][BBALL_TIMER_SEC_ONES] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_count_bball_%s_red_10", mode);
        g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_RED][BBALL_SCORE_TENS] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_count_bball_%s_red_1", mode);
        g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_RED][BBALL_SCORE_ONES] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_count_bball_%s_blue_10", mode);
        g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_BLU][BBALL_SCORE_TENS] = FindNearestBBallTextureToggleForArena(arena, targetName);

        Format(targetName, sizeof(targetName), "skin_count_bball_%s_blue_1", mode);
        g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_BLU][BBALL_SCORE_ONES] = FindNearestBBallTextureToggleForArena(arena, targetName);
    }
}

void ApplyTextureToggleDigit(int entRef, int digit)
{
    int entity = EntRefToEntIndex(entRef);
    if (entity <= MaxClients || !IsValidEntity(entity))
        return;

    if (digit < 0)
        digit = 0;
    else if (digit > 9)
        digit = 9;

    SetVariantInt(digit);
    AcceptEntityInput(entity, "SetTextureIndex");
}

void UpdateBBallScoreboardForArena(int arena_index)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount || !g_bArenaBBall[arena_index])
        return;

    int elapsed = 0;
    int redScore = 0;
    int bluScore = 0;
    if (g_iArenaStatus[arena_index] == AS_FIGHT && g_iArenaDuelStartTime[arena_index] > 0)
    {
        elapsed = GetTime() - g_iArenaDuelStartTime[arena_index];
        if (elapsed < 0)
            elapsed = 0;
        else if (elapsed > 5999)
            elapsed = 5999;

        redScore = g_iArenaScore[arena_index][SLOT_ONE];
        bluScore = g_iArenaScore[arena_index][SLOT_TWO];
        if (redScore < 0)
            redScore = 0;
        else if (redScore > 99)
            redScore = 99;
        if (bluScore < 0)
            bluScore = 0;
        else if (bluScore > 99)
            bluScore = 99;
    }

    int minutes = elapsed / 60;
    int seconds = elapsed % 60;
    int minuteTens = (minutes / 10) % 10;
    int minuteOnes = minutes % 10;
    int secondTens = (seconds / 10) % 10;
    int secondOnes = seconds % 10;
    int redTens = (redScore / 10) % 10;
    int redOnes = redScore % 10;
    int bluTens = (bluScore / 10) % 10;
    int bluOnes = bluScore % 10;

    ApplyTextureToggleDigit(g_iBBallTimerEntRef[arena_index][BBALL_TIMER_MIN_TENS], minuteTens);
    ApplyTextureToggleDigit(g_iBBallTimerEntRef[arena_index][BBALL_TIMER_MIN_ONES], minuteOnes);
    ApplyTextureToggleDigit(g_iBBallTimerEntRef[arena_index][BBALL_TIMER_SEC_TENS], secondTens);
    ApplyTextureToggleDigit(g_iBBallTimerEntRef[arena_index][BBALL_TIMER_SEC_ONES], secondOnes);

    ApplyTextureToggleDigit(g_iBBallScoreEntRef[arena_index][BBALL_SCORE_TEAM_RED][BBALL_SCORE_TENS], redTens);
    ApplyTextureToggleDigit(g_iBBallScoreEntRef[arena_index][BBALL_SCORE_TEAM_RED][BBALL_SCORE_ONES], redOnes);
    ApplyTextureToggleDigit(g_iBBallScoreEntRef[arena_index][BBALL_SCORE_TEAM_BLU][BBALL_SCORE_TENS], bluTens);
    ApplyTextureToggleDigit(g_iBBallScoreEntRef[arena_index][BBALL_SCORE_TEAM_BLU][BBALL_SCORE_ONES], bluOnes);
}

void UpdateBBallScoreboards()
{
    for (int arena = 1; arena <= g_iArenaCount; arena++)
    {
        if (!g_bArenaBBall[arena])
            continue;

        UpdateBBallScoreboardForArena(arena);
    }
}

Action Timer_UpdateBBallScoreboards(Handle timer)
{
    if (g_hBBallScoreboardTimer != timer)
        return Plugin_Stop;

    UpdateBBallScoreboards();
    return Plugin_Continue;
}

void StartBBallScoreboardTimer()
{
    delete g_hBBallScoreboardTimer;

    bool hasBballArena = false;
    for (int arena = 1; arena <= g_iArenaCount; arena++)
    {
        if (g_bArenaBBall[arena])
        {
            hasBballArena = true;
            break;
        }
    }

    if (!hasBballArena)
        return;

    g_hBBallScoreboardTimer = CreateTimer(1.0, Timer_UpdateBBallScoreboards, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    UpdateBBallScoreboards();
}

int ResolveCarryAttachment(int client)
{
    static const char attachments[][] = { "flag", "backpack", "back_lower", "spine_2", "weapon_bone", "head" };
    for (int i = 0; i < sizeof(attachments); i++)
    {
        if (LookupEntityAttachment(client, attachments[i]) > 0)
            return i;
    }
    return -1;
}

void RemoveBBallBackModel(int client)
{
    RemoveEntityByRef(g_iBBallBackModel[client]);
}

void ClearBBallCarryState(int client, bool removeParticle = true)
{
    if (client <= 0 || client > MaxClients)
        return;

    g_bPlayerHasIntel[client] = false;
    RemoveBBallBackModel(client);

    if (removeParticle)
        RemoveClientParticle(client);
}

void AttachBBallBackModel(int client)
{
    RemoveBBallBackModel(client);

    if (!IsValidClient(client))
        return;

    int attachIdx = ResolveCarryAttachment(client);
    if (attachIdx == -1)
        return;

    static const char attachments[][] = { "flag", "backpack", "back_lower", "spine_2", "weapon_bone", "head" };
    int model = CreateEntityByName("prop_dynamic_override");
    if (model == -1)
        return;

    DispatchKeyValue(model, "model", MODEL_BRIEFCASE);
    DispatchKeyValue(model, "solid", "0");
    DispatchSpawn(model);
    SetEntPropFloat(model, Prop_Send, "m_flModelScale", 0.9);
    SetEntPropEnt(model, Prop_Send, "m_hOwnerEntity", client);

    SetVariantString("!activator");
    AcceptEntityInput(model, "SetParent", client, model);
    SetVariantString(attachments[attachIdx]);
    AcceptEntityInput(model, "SetParentAttachment", client, model);
    SDKHook(model, SDKHook_SetTransmit, Hook_BBallBackModelSetTransmit);
    g_iBBallBackModel[client] = EntIndexToEntRef(model);
}

void RemoveBBallIntelWorldFx(int arena_index)
{
    RemoveEntityByRef(g_iBBallIntelWorldParticle[arena_index]);
    delete g_hBBallIntelSpinTimer[arena_index];
}

void ApplyBBallIntelVisuals(int arena_index)
{
    int intel = g_iBBallIntel[arena_index];
    if (intel <= 0 || !IsValidEntity(intel))
        return;

    SetEntProp(intel, Prop_Send, "m_nSkin", g_iBBallIntelSkinTeam[arena_index]);
    RemoveBBallIntelWorldFx(arena_index);

    int particle = CreateEntityByName("info_particle_system");
    if (particle != -1)
    {
        float pos[3];
        GetEntPropVector(intel, Prop_Send, "m_vecOrigin", pos);
        TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
        DispatchKeyValue(particle, "effect_name", g_iBBallIntelSkinTeam[arena_index] == 0 ? "mannpower_imbalance_red_beam" : "mannpower_imbalance_blue_beam");
        DispatchSpawn(particle);
        SetVariantString("!activator");
        AcceptEntityInput(particle, "SetParent", intel, particle);
        ActivateEntity(particle);
        AcceptEntityInput(particle, "Start");
        g_iBBallIntelWorldParticle[arena_index] = EntIndexToEntRef(particle);
    }

    delete g_hBBallIntelSpinTimer[arena_index];
    g_hBBallIntelSpinTimer[arena_index] = CreateTimer(g_fBBallSpinInterval, Timer_SpinBBallIntel, arena_index, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Hook_BBallBackModelSetTransmit(int entity, int client)
{
    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (owner == client)
        return Plugin_Handled;
    return Plugin_Continue;
}

void ConfigureAndSpawnBBallIntelEntity(int arena_index, float pos[3])
{
    DispatchKeyValue(g_iBBallIntel[arena_index], "powerup_model", MODEL_BRIEFCASE);
    DispatchSpawn(g_iBBallIntel[arena_index]);
    TeleportEntity(g_iBBallIntel[arena_index], pos, NULL_VECTOR, NULL_VECTOR);
    SetEntProp(g_iBBallIntel[arena_index], Prop_Send, "m_iTeamNum", 1, 4);
    SetEntPropFloat(g_iBBallIntel[arena_index], Prop_Send, "m_flModelScale", 1.15);
    SDKHook(g_iBBallIntel[arena_index], SDKHook_StartTouch, OnTouchIntel);
    AcceptEntityInput(g_iBBallIntel[arena_index], "Enable");
    ApplyBBallIntelVisuals(arena_index);
}

void RemoveBBallArenaEntities(int arena_index)
{
    if (arena_index <= 0 || arena_index > MAXARENAS)
        return;

    UnhookBBallArenaGoalTriggers(arena_index);

    if (IsValidEdict(g_iBBallHoop[arena_index][SLOT_ONE]) && g_iBBallHoop[arena_index][SLOT_ONE] > 0)
        RemoveEdict(g_iBBallHoop[arena_index][SLOT_ONE]);
    g_iBBallHoop[arena_index][SLOT_ONE] = -1;

    if (IsValidEdict(g_iBBallHoop[arena_index][SLOT_TWO]) && g_iBBallHoop[arena_index][SLOT_TWO] > 0)
        RemoveEdict(g_iBBallHoop[arena_index][SLOT_TWO]);
    g_iBBallHoop[arena_index][SLOT_TWO] = -1;

    if (IsValidEdict(g_iBBallIntel[arena_index]) && g_iBBallIntel[arena_index] > 0)
        RemoveEdict(g_iBBallIntel[arena_index]);
    g_iBBallIntel[arena_index] = -1;

    RemoveBBallIntelWorldFx(arena_index);
    g_iBBallIntelSkinTeam[arena_index] = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || g_iPlayerArena[client] != arena_index)
            continue;

        ClearBBallCarryState(client, true);
    }
}

void RebuildBBallArenaHoops(int arena_index)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount || !g_bArenaBBall[arena_index])
        return;

    float hoop_2_loc[3];
    GetBBallHoopGoalOrigin(arena_index, SLOT_TWO, hoop_2_loc);

    float hoop_1_loc[3];
    GetBBallHoopGoalOrigin(arena_index, SLOT_ONE, hoop_1_loc);

    if (IsValidEdict(g_iBBallHoop[arena_index][SLOT_ONE]) && g_iBBallHoop[arena_index][SLOT_ONE] > 0)
        RemoveEdict(g_iBBallHoop[arena_index][SLOT_ONE]);
    g_iBBallHoop[arena_index][SLOT_ONE] = -1;

    if (IsValidEdict(g_iBBallHoop[arena_index][SLOT_TWO]) && g_iBBallHoop[arena_index][SLOT_TWO] > 0)
        RemoveEdict(g_iBBallHoop[arena_index][SLOT_TWO]);
    g_iBBallHoop[arena_index][SLOT_TWO] = -1;

    g_iBBallHoop[arena_index][SLOT_ONE] = CreateEntityByName("item_ammopack_small");
    if (g_iBBallHoop[arena_index][SLOT_ONE] != -1)
    {
        TeleportEntity(g_iBBallHoop[arena_index][SLOT_ONE], hoop_1_loc, NULL_VECTOR, NULL_VECTOR);
        DispatchSpawn(g_iBBallHoop[arena_index][SLOT_ONE]);
        SetEntProp(g_iBBallHoop[arena_index][SLOT_ONE], Prop_Send, "m_iTeamNum", 1, 4);
        SDKHook(g_iBBallHoop[arena_index][SLOT_ONE], SDKHook_StartTouch, OnTouchHoop);
    }

    g_iBBallHoop[arena_index][SLOT_TWO] = CreateEntityByName("item_ammopack_small");
    if (g_iBBallHoop[arena_index][SLOT_TWO] != -1)
    {
        TeleportEntity(g_iBBallHoop[arena_index][SLOT_TWO], hoop_2_loc, NULL_VECTOR, NULL_VECTOR);
        DispatchSpawn(g_iBBallHoop[arena_index][SLOT_TWO]);
        SetEntProp(g_iBBallHoop[arena_index][SLOT_TWO], Prop_Send, "m_iTeamNum", 1, 4);
        SDKHook(g_iBBallHoop[arena_index][SLOT_TWO], SDKHook_StartTouch, OnTouchHoop);
    }

    if (g_bVisibleHoops[arena_index] == false)
    {
        if (IsValidEdict(g_iBBallHoop[arena_index][SLOT_ONE]) && g_iBBallHoop[arena_index][SLOT_ONE] > 0)
            AcceptEntityInput(g_iBBallHoop[arena_index][SLOT_ONE], "Disable");
        if (IsValidEdict(g_iBBallHoop[arena_index][SLOT_TWO]) && g_iBBallHoop[arena_index][SLOT_TWO] > 0)
            AcceptEntityInput(g_iBBallHoop[arena_index][SLOT_TWO], "Disable");
    }

    RefreshBBallArenaGoalTriggers(arena_index);
}

// Setup BBall hoops for all BBall arenas during round start
void SetupBBallHoops()
{
    PrecacheModel(MODEL_BRIEFCASE, true);
    PrecacheModel(MODEL_AMMOPACK, true);

    for (int i = 0; i <= g_iArenaCount; i++)
    {
        if (g_bArenaBBall[i])
            RebuildBBallArenaHoops(i);
    }
}

// Reset and recreate the intel entity at appropriate spawn locations for bball gameplay
void ResetIntel(int arena_index, any client = -1)
{
    if (g_bArenaBBall[arena_index])
    {
        if (IsValidEdict(g_iBBallIntel[arena_index]) && g_iBBallIntel[arena_index] > 0)
        {
            RemoveEdict(g_iBBallIntel[arena_index]);
            g_iBBallIntel[arena_index] = -1;
        }

        if (g_iBBallIntel[arena_index] == -1)
            g_iBBallIntel[arena_index] = CreateEntityByName("item_ammopack_small");
        else
            LogError("[%s] Intel [%i] already exists.", g_sArenaName[arena_index], g_iBBallIntel[arena_index]);


        float intel_loc[3];

        if (client != -1)
        {
            int client_slot = g_iPlayerSlot[client];
            ClearBBallCarryState(client, true);

            if (client_slot == SLOT_ONE || client_slot == SLOT_THREE)
            {
                if (g_bArenaBBallIntelSpawnRedSet[arena_index])
                {
                    intel_loc[0] = g_fArenaBBallIntelSpawnRed[arena_index][0];
                    intel_loc[1] = g_fArenaBBallIntelSpawnRed[arena_index][1];
                    intel_loc[2] = g_fArenaBBallIntelSpawnRed[arena_index][2];
                }
                else if (g_bArenaBBallIntelSpawnSet[arena_index])
                {
                    intel_loc[0] = g_fArenaBBallIntelSpawn[arena_index][0];
                    intel_loc[1] = g_fArenaBBallIntelSpawn[arena_index][1];
                    intel_loc[2] = g_fArenaBBallIntelSpawn[arena_index][2];
                }
                else
                {
                    intel_loc[0] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 3][0];
                    intel_loc[1] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 3][1];
                    intel_loc[2] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 3][2];
                }
            } else if (client_slot == SLOT_TWO || client_slot == SLOT_FOUR) {
                if (g_bArenaBBallIntelSpawnBluSet[arena_index])
                {
                    intel_loc[0] = g_fArenaBBallIntelSpawnBlu[arena_index][0];
                    intel_loc[1] = g_fArenaBBallIntelSpawnBlu[arena_index][1];
                    intel_loc[2] = g_fArenaBBallIntelSpawnBlu[arena_index][2];
                }
                else if (g_bArenaBBallIntelSpawnSet[arena_index])
                {
                    intel_loc[0] = g_fArenaBBallIntelSpawn[arena_index][0];
                    intel_loc[1] = g_fArenaBBallIntelSpawn[arena_index][1];
                    intel_loc[2] = g_fArenaBBallIntelSpawn[arena_index][2];
                }
                else
                {
                    intel_loc[0] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 2][0];
                    intel_loc[1] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 2][1];
                    intel_loc[2] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 2][2];
                }
            }
        } else {
            if (g_bArenaBBallIntelSpawnSet[arena_index])
            {
                intel_loc[0] = g_fArenaBBallIntelSpawn[arena_index][0];
                intel_loc[1] = g_fArenaBBallIntelSpawn[arena_index][1];
                intel_loc[2] = g_fArenaBBallIntelSpawn[arena_index][2];
            }
            else
            {
                intel_loc[0] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 4][0];
                intel_loc[1] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 4][1];
                intel_loc[2] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 4][2];
            }
        }

        // Should fix the intel being an ammopack
        ConfigureAndSpawnBBallIntelEntity(arena_index, intel_loc);
    }
}


// ===== EVENT HANDLERS =====

// Handle intel pickup events including particle effects, sound cues, and team notifications
Action OnTouchIntel(int entity, int other)
{
    int client = other;

    if (!IsValidClient(client))
        return Plugin_Continue;

    if (!g_bCanPlayerGetIntel[client])
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];
    g_bPlayerHasIntel[client] = true;
    AttachBBallBackModel(client);
    char msg[64];
    Format(msg, sizeof(msg), "%T", "YouHaveTheIntel", client);
    PrintCenterText(client, msg);

    if (entity == g_iBBallIntel[arena_index] && IsValidEdict(g_iBBallIntel[arena_index]) && g_iBBallIntel[arena_index] > 0)
    {
        // SDKUnhook(g_iBBallIntel[arena_index], SDKHook_StartTouch, OnTouchIntel);
        RemoveEdict(g_iBBallIntel[arena_index]);
        g_iBBallIntel[arena_index] = -1;
        RemoveBBallIntelWorldFx(arena_index);
    }

    int particle;
    TFTeam team = TF2_GetClientTeam(client);

    // Create a fancy lightning effect to make it abundantly clear that the intel has just been picked up.
    AttachParticle(client, team == TFTeam_Red ? "teleported_red" : "teleported_blue", particle);

    // Attach a team-colored particle to give a visual cue that a player is holding the intel, since we can't attach models.
    particle = EntRefToEntIndex(g_iClientParticle[client]);
    if (particle == 0 || !IsValidEntity(particle))
    {
        AttachParticle(client, team == TFTeam_Red ? g_sBBallParticleRed : g_sBBallParticleBlue, particle);
        g_iClientParticle[client] = EntIndexToEntRef(particle);
    }

    UpdateHud(client);
    EmitSoundToClient(client, "vo/intel_teamstolen.mp3");

    int foe = g_iArenaQueue[g_iPlayerArena[client]][(g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE) ? SLOT_TWO : SLOT_ONE];

    if (IsValidClient(foe))
    {
        EmitSoundToClient(foe, "vo/intel_enemystolen.mp3");
        UpdateHud(foe);
    }

    if (g_bFourPersonArena[g_iPlayerArena[client]])
    {
        int foe2 = g_iArenaQueue[g_iPlayerArena[client]][(g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE) ? SLOT_FOUR : SLOT_THREE];
        if (IsValidClient(foe2))
        {
            EmitSoundToClient(foe2, "vo/intel_enemystolen.mp3");
            UpdateHud(foe2);
        }
    }

    return Plugin_Continue;
}

bool TryHandleBBallGoalTouch(int client, int entity)
{
    if (!IsValidClient(client))
        return false;

    int arena_index = g_iPlayerArena[client];
    if (arena_index <= 0 || arena_index > g_iArenaCount || !g_bArenaBBall[arena_index] || !g_bPlayerHasIntel[client])
        return false;

    int fraglimit = g_iArenaFraglimit[arena_index];
    int client_slot = g_iPlayerSlot[client];
    int foe_slot = (client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
    int foe = g_iArenaQueue[arena_index][foe_slot];
    int client_teammate = 0;
    int foe_teammate = 0;
    int foe_team_slot = (foe_slot > 2) ? (foe_slot - 2) : foe_slot;
    int client_team_slot = (client_slot > 2) ? (client_slot - 2) : client_slot;
    int goalTrigger = EntRefToEntIndex(g_iBBallHoopTrigger[arena_index][foe_slot]);
    bool touchedGoal = (entity == g_iBBallHoop[arena_index][foe_slot]);

    if (g_bFourPersonArena[arena_index])
    {
        client_teammate = GetPlayerTeammate(client_slot, arena_index);
        foe_teammate = GetPlayerTeammate(foe_slot, arena_index);
    }

    if (!touchedGoal && goalTrigger > MaxClients && IsValidEntity(goalTrigger))
        touchedGoal = (entity == goalTrigger);

    if (!IsValidClient(foe) || !touchedGoal)
        return false;

    // Drop carry visuals immediately on dunk.
    ClearBBallCarryState(client, true);

    char foe_name[MAX_NAME_LENGTH];
    GetClientName(foe, foe_name, sizeof(foe_name));
    char client_name[MAX_NAME_LENGTH];
    GetClientName(client, client_name, sizeof(client_name));

    MC_PrintToChat(client, "%t", "bballdunk", foe_name);

    int score_red_before = g_iArenaScore[arena_index][SLOT_ONE];
    int score_blu_before = g_iArenaScore[arena_index][SLOT_TWO];
    g_iArenaScore[arena_index][client_team_slot] += 1;
    int score_red_after = g_iArenaScore[arena_index][SLOT_ONE];
    int score_blu_after = g_iArenaScore[arena_index][SLOT_TWO];
    g_iBBallIntelSkinTeam[arena_index] = (client_team_slot == SLOT_ONE) ? 0 : 1;
    UpdateBBallScoreboardForArena(arena_index);
    RecordArenaRoundEnd(arena_index, client_team_slot, RoundEndReason_BBallGoal, client, 0, GetClientScoringWeaponDefIndex(client), score_red_before, score_blu_before, score_red_after, score_blu_after);

    if (fraglimit > 0 && g_iArenaScore[arena_index][client_team_slot] >= fraglimit && g_iArenaStatus[arena_index] >= AS_FIGHT && g_iArenaStatus[arena_index] < AS_REPORTED)
    {
        g_iArenaStatus[arena_index] = AS_REPORTED;
        GetClientName(client, client_name, sizeof(client_name));

        if (g_bFourPersonArena[arena_index])
        {
            char client_teammate_name[128];
            char foe_teammate_name[128];

            GetClientName(client_teammate, client_teammate_name, sizeof(client_teammate_name));
            GetClientName(foe_teammate, foe_teammate_name, sizeof(foe_teammate_name));

            Format(client_name, sizeof(client_name), "%s and %s", client_name, client_teammate_name);
            Format(foe_name, sizeof(foe_name), "%s and %s", foe_name, foe_teammate_name);
        }

        char duel_time[32] = "";
        if (g_iArenaDuelStartTime[arena_index] > 0)
        {
            int currentTime = GetTime();
            int elapsedTime = currentTime - g_iArenaDuelStartTime[arena_index];
            int minutes = elapsedTime / 60;
            int seconds = elapsedTime % 60;
            Format(duel_time, sizeof(duel_time), "%02d:%02d", minutes, seconds);
        }

        MC_PrintToChatAll("%t", "XdefeatsY", client_name, g_iArenaScore[arena_index][client_team_slot], foe_name, g_iArenaScore[arena_index][foe_team_slot], fraglimit, g_sArenaName[arena_index], duel_time);

        if (!g_bNoStats && !g_bFourPersonArena[arena_index])
            CalcELO(client, foe);

        else if (!g_bNoStats)
            CalcELO2(client, client_teammate, foe, foe_teammate);

        g_iArenaDuelStartTime[arena_index] = 0;

        if (IsValidEdict(g_iBBallIntel[arena_index]) && g_iBBallIntel[arena_index] > -1)
        {
            // SDKUnhook(g_iBBallIntel[arena_index], SDKHook_StartTouch, OnTouchIntel);
            RemoveEdict(g_iBBallIntel[arena_index]);
            g_iBBallIntel[arena_index] = -1;
            RemoveBBallIntelWorldFx(arena_index);
        }
        if (g_bFourPersonArena[arena_index] && IsValidClient(g_iArenaQueue[arena_index][SLOT_FOUR + 1]))
        {
            RemoveFromQueue(foe, false);
            RemoveFromQueue(foe_teammate, false);
            AddInQueue(foe, arena_index, false, 0, false);
            AddInQueue(foe_teammate, arena_index, false, 0, false);
        }
        else if (IsValidClient(g_iArenaQueue[arena_index][SLOT_TWO + 1]))
        {
            RemoveFromQueue(foe, false);
            AddInQueue(foe, arena_index, false, 0, false);
        }
        else
        {
            if (!IsValidClient(g_iArenaQueue[arena_index][SLOT_TWO + 1]))
                g_iArenaQueue[arena_index][SLOT_TWO + 1] = 0;
            if (!IsValidClient(g_iArenaQueue[arena_index][SLOT_FOUR + 1]))
                g_iArenaQueue[arena_index][SLOT_FOUR + 1] = 0;
            CreateTimer(3.0, Timer_StartDuel, arena_index);
        }
    }
    else
    {
        ResetPlayer(client);
        ResetPlayer(foe);

        if (g_bFourPersonArena[arena_index])
        {
            ResetPlayer(client_teammate);
            ResetPlayer(foe_teammate);
        }

        CreateTimer(0.15, Timer_ResetIntel, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        StartArenaRoundLogging(arena_index);
    }

    UpdateBBallScoreboardForArena(arena_index);

    UpdateHud(client);
    UpdateHud(foe);

    if (g_bFourPersonArena[arena_index])
    {
        UpdateHud(client_teammate);
        UpdateHud(foe_teammate);
    }

    EmitSoundToClient(client, "vo/intel_teamcaptured.mp3");
    EmitSoundToClient(foe, "vo/intel_enemycaptured.mp3");

    if (g_bFourPersonArena[arena_index])
    {
        // This shouldn't be necessary but I'm getting invalid clients for some reason.
        if (IsValidClient(client_teammate))
            EmitSoundToClient(client_teammate, "vo/intel_teamcaptured.mp3");
        if (IsValidClient(foe_teammate))
            EmitSoundToClient(foe_teammate, "vo/intel_enemycaptured.mp3");
    }

    UpdateHudForArena(arena_index);
    return true;
}

// When a hoop is touched by a player in BBall.
Action OnTouchHoop(int entity, int other)
{
    TryHandleBBallGoalTouch(other, entity);
    return Plugin_Continue;
}

Action OnTouchHoopTrigger(int entity, int other)
{
    TryHandleBBallGoalTouch(other, entity);
    return Plugin_Continue;
}

// Handles intel dropping when a BBall player dies
void HandleBBallPlayerDeath(int victim, int killer, int arena_index)
{
    if (!g_bPlayerHasIntel[victim])
        return;
        
    ClearBBallCarryState(victim, true);
    float pos[3];
    GetClientAbsOrigin(victim, pos);
    float dist = DistanceAboveGround(victim);
    if (dist > -1)
        pos[2] = pos[2] - dist + 5;
    else
        pos[2] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 3][2];

    if (g_iBBallIntel[arena_index] == -1)
        g_iBBallIntel[arena_index] = CreateEntityByName("item_ammopack_small");
    else
        LogError("[%s] Player died with intel, but intel [%i] already exists.", g_sArenaName[arena_index], g_iBBallIntel[arena_index]);

    // Configure intel entity properties
    ConfigureAndSpawnBBallIntelEntity(arena_index, pos);

    // Play intel drop sounds
    EmitSoundToClient(victim, "vo/intel_teamdropped.mp3");
    if (IsValidClient(killer))
        EmitSoundToClient(killer, "vo/intel_enemydropped.mp3");
}


// ===== COMMANDS =====

// When a player drops the intel in BBall
Action Command_DropItem(int client, const char[] command, int argc)
{
    int arena_index = g_iPlayerArena[client];

    if (g_bArenaBBall[arena_index])
    {
        if (g_bPlayerHasIntel[client])
        {
            ClearBBallCarryState(client, true);
            float pos[3];
            GetClientAbsOrigin(client, pos);
            float dist = DistanceAboveGroundAroundPlayer(client);
            if (dist > -1)
                pos[2] = pos[2] - dist + 5;
            else
                pos[2] = g_fArenaSpawnOrigin[arena_index][g_iArenaSpawns[arena_index] - 3][2];

            if (g_iBBallIntel[arena_index] == -1)
                g_iBBallIntel[arena_index] = CreateEntityByName("item_ammopack_small");
            else
                LogError("[%s] Player dropped the intel, but intel [%i] already exists.", g_sArenaName[arena_index], g_iBBallIntel[arena_index]);

            // This should fix the ammopack not being turned into a briefcase
            ConfigureAndSpawnBBallIntelEntity(arena_index, pos);

            EmitSoundToClient(client, "vo/intel_teamdropped.mp3");

            g_bCanPlayerGetIntel[client] = false;
            CreateTimer(0.5, Timer_AllowPlayerCap, client);
        }
    }

    return Plugin_Continue;
}


// ===== TIMER CALLBACKS =====

// Restore intel to spawn location after scoring or timeout events
Action Timer_ResetIntel(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    int arena_index = g_iPlayerArena[client];

    ResetIntel(arena_index, client);

    return Plugin_Continue;
}

// Re-enable intel pickup capability after a brief cooldown period
Action Timer_AllowPlayerCap(Handle timer, int userid)
{
    g_bCanPlayerGetIntel[userid] = true;

    return Plugin_Continue;
}

Action Timer_SpinBBallIntel(Handle timer, any arena_index)
{
    if (arena_index <= 0 || arena_index > g_iArenaCount)
    {
        if (g_hBBallIntelSpinTimer[arena_index] == timer)
            g_hBBallIntelSpinTimer[arena_index] = null;
        return Plugin_Stop;
    }

    int intel = g_iBBallIntel[arena_index];
    if (intel <= 0 || !IsValidEntity(intel))
    {
        if (g_hBBallIntelSpinTimer[arena_index] == timer)
            g_hBBallIntelSpinTimer[arena_index] = null;
        return Plugin_Stop;
    }

    float ang[3];
    GetEntPropVector(intel, Prop_Data, "m_angRotation", ang);
    ang[1] += 2.75;
    if (ang[1] > 360.0)
        ang[1] -= 360.0;
    TeleportEntity(intel, NULL_VECTOR, ang, NULL_VECTOR);
    return Plugin_Continue;
}
