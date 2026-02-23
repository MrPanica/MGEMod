// ===== PLAYER STATE MANAGEMENT =====

// Initialize basic client data when they connect (regardless of Steam status)
void HandleClientConnection(int client)
{
    if (IsFakeClient(client))
        return;
        
    // Initialize basic client state immediately (Steam-independent)
    ChangeClientTeam(client, TEAM_SPEC);
    g_bShowHud[client] = true;
    g_bPlayerRestoringAmmo[client] = false;
    g_bSkipNextSpawnTeleport[client] = false;
    g_bPlayerEloVerified[client] = false;
    g_bPlayerAddedViaWadd[client] = false;
    g_bScoreboardOpen[client] = false;
    g_bWaddMenu[client] = false;
    g_iPlayerRespawnroomTouchDepth[client] = 0;
    g_bSkipNextSpawnTeleport[client] = false;
    g_bSetSpawnAwaitInput[client] = false;
    g_iSetSpawnArena[client] = 0;
    g_iSetSpawnMode[client] = 0;
    g_iPlayerWaiting[client] = false;
    if (g_hPlayerWaitingSpecTimer[client] != null)
    {
        delete g_hPlayerWaitingSpecTimer[client];
        g_hPlayerWaitingSpecTimer[client] = null;
    }
    
    // Clear any inherited statistics data immediately (but preserve if already properly loaded)
    // This prevents stats from being inherited from previous client in the same slot
    if (g_iPlayerRating[client] == 0 || strlen(g_sPlayerSteamID[client]) == 0)
    {
        g_iPlayerRating[client] = 0;
        g_iPlayerWins[client] = 0;
        g_iPlayerLosses[client] = 0;
        g_bPlayerEloVerified[client] = false;
        for (int classId = 1; classId <= 9; classId++)
        {
            g_iPlayerClassPoints[client][classId] = 0;
            for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
            {
                g_iPlayerClassRating[client][classId][oppClassId] = 0;
                g_iPlayerMatchupCount[client][classId][oppClassId] = 0;
            }
        }
    }
    
    // Initialize class tracking ArrayList
    if (g_alPlayerDuelClasses[client] != null)
        delete g_alPlayerDuelClasses[client];
    g_alPlayerDuelClasses[client] = new ArrayList();
    
    // Try to load player stats (will retry in HandleClientAuthentication if Steam ID not ready)
    TryLoadPlayerStats(client, false);
    
    CreateTimer(5.0, Timer_ShowAdv, GetClientUserId(client));
    CreateTimer(15.0, Timer_WelcomePlayer, GetClientUserId(client));
    
    // Initialize spectator target detection for HUD display
    CreateTimer(0.5, Timer_ChangeSpecTarget, GetClientUserId(client));
    
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

// Handle Steam-authenticated connections and retry ELO loading if needed
void HandleClientAuthentication(int client)
{
    if (IsFakeClient(client))
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (g_bPlayerAskedForBot[i])
            {
                int arena_index = g_iPlayerArena[i];
                DataPack pack = new DataPack();
                CreateDataTimer(1.5, Timer_AddBotInQueue, pack);
                pack.WriteCell(GetClientUserId(client));
                pack.WriteCell(arena_index);
                g_iPlayerRating[client] = 1551;
                for (int classId = 1; classId <= 9; classId++)
                {
                    g_iPlayerClassPoints[client][classId] = 0;
                    for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
                    {
                        g_iPlayerClassRating[client][classId][oppClassId] = 1551;
                    }
                }
                g_bPlayerAskedForBot[i] = false;
                break;
            }
        }
    }
    else
    {
        // Steam authentication successful - retry stats loading if it failed before
        TryLoadPlayerStats(client, true);
    }
}

// Handle client disconnection and cleanup
void HandleClientDisconnection(int client)
{
    g_iPlayerRespawnroomTouchDepth[client] = 0;
    g_bSetSpawnAwaitInput[client] = false;
    g_iSetSpawnArena[client] = 0;
    g_iSetSpawnMode[client] = 0;

    g_iPlayerWaiting[client] = false;
    if (g_hPlayerWaitingSpecTimer[client] != null)
    {
        delete g_hPlayerWaitingSpecTimer[client];
        g_hPlayerWaitingSpecTimer[client] = null;
    }

    // Clear any invites before removing from queue
    ClearPlayerInvites(client);
    
    // Reset wadd flag
    g_bPlayerAddedViaWadd[client] = false;
    g_bScoreboardOpen[client] = false;
    g_bWaddMenu[client] = false;
    
    // Remove from waiting lists
    for (int i = 1; i <= g_iArenaCount; i++)
    {
        if (g_alArenaWaitingList[i] != null)
        {
            int index = g_alArenaWaitingList[i].FindValue(client);
            if (index != -1)
            {
                g_alArenaWaitingList[i].Erase(index);
            }
        }
    }

    // We ignore the kick queue check for this function only so that clients that get kicked still get their elo calculated
    if (IsValidClient(client, true) && g_iPlayerArena[client])
    {
        RemoveFromQueue(client, true);
    }
    else
    {
        int
            arena_index = g_iPlayerArena[client],
            player_slot = g_iPlayerSlot[client],
            foe_slot = (player_slot == SLOT_ONE || player_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE,
            foe = g_iArenaQueue[arena_index][foe_slot];

        // Turn all this logic into a helper method
        int player_teammate, foe2;

        if (g_bFourPersonArena[arena_index])
        {
            player_teammate = GetPlayerTeammate(player_slot, arena_index);
            foe2 = GetPlayerTeammate(foe_slot, arena_index);
        }

        g_iPlayerArena[client] = 0;
        g_iPlayerSlot[client] = 0;
        g_iArenaQueue[arena_index][player_slot] = 0;
        g_iPlayerHandicap[client] = 0;
        
        // Cleanup class tracking ArrayList
        if (g_alPlayerDuelClasses[client] != null)
        {
            delete g_alPlayerDuelClasses[client];
            g_alPlayerDuelClasses[client] = null;
        }
        
        // Clear 2v2 ready status
        g_bPlayer2v2Ready[client] = false;
        
        // Clear player statistics to prevent inheritance by new clients with same ID
        g_iPlayerRating[client] = 0;
        g_iPlayerWins[client] = 0;
        g_iPlayerLosses[client] = 0;
        for (int classId = 1; classId <= 9; classId++)
        {
            g_iPlayerClassPoints[client][classId] = 0;
            for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
            {
                g_iPlayerClassRating[client][classId][oppClassId] = 0;
                g_iPlayerMatchupCount[client][classId][oppClassId] = 0;
            }
        }
        
        // Clear hud text if arena was in ready state
        if (g_iArenaStatus[arena_index] == AS_WAITING_READY)
        {
            Clear2v2ReadyHud(arena_index);
        }

        // Bot cleanup logic (queue advancement is handled by RemoveFromQueue)
        if (IsValidClient(foe) && IsFakeClient(foe))
        {
            ConVar cvar = FindConVar("tf_bot_quota");
            int quota = cvar.IntValue;
            ServerCommand("tf_bot_quota %d", quota - 1);
        }

        if (IsValidClient(foe2) && IsFakeClient(foe2))
        {
            ConVar cvar = FindConVar("tf_bot_quota");
            int quota = cvar.IntValue;
            ServerCommand("tf_bot_quota %d", quota - 1);
        }

        if (IsValidClient(player_teammate) && IsFakeClient(player_teammate))
        {
            ConVar cvar = FindConVar("tf_bot_quota");
            int quota = cvar.IntValue;
            ServerCommand("tf_bot_quota %d", quota - 1);
        }

        // Ensure any 2v2 waiting/spec players are restored on disconnect
        if (g_bFourPersonArena[arena_index])
        {
            Restore2v2WaitingSpectators(arena_index);
            CreateTimer(3.0, Timer_Restart2v2Ready, arena_index);
        }

        g_iArenaStatus[arena_index] = AS_IDLE;
        // Reset duel start time since player disconnected and arena became idle
        g_iArenaDuelStartTime[arena_index] = 0;
        return;
    }
}

bool IsClientInRespawnroomByNetprop(int client)
{
    if (!IsValidClient(client))
        return false;

    if (!HasEntProp(client, Prop_Send, "m_bInUpgradeZone"))
        return false;

    return (GetEntProp(client, Prop_Send, "m_bInUpgradeZone") != 0);
}

void OnRespawnroomStartTouchOutput(const char[] output, int caller, int activator, float delay)
{
    #pragma unused output
    #pragma unused delay
    if (!IsValidClient(activator))
        return;

    g_iPlayerRespawnroomTouchDepth[activator]++;

    if (g_bDebugTeleport)
    {
        LogMessage("[MGE tele][debug] respawnroom starttouch client=%N caller=%d depth=%d",
            activator, caller, g_iPlayerRespawnroomTouchDepth[activator]);
    }
}

void OnRespawnroomEndTouchOutput(const char[] output, int caller, int activator, float delay)
{
    #pragma unused output
    #pragma unused delay
    if (!IsValidClient(activator))
        return;

    if (g_iPlayerRespawnroomTouchDepth[activator] > 0)
        g_iPlayerRespawnroomTouchDepth[activator]--;

    if (g_bDebugTeleport)
    {
        LogMessage("[MGE tele][debug] respawnroom endtouch client=%N caller=%d depth=%d",
            activator, caller, g_iPlayerRespawnroomTouchDepth[activator]);
    }
}

void QueueArenaTeleport(int client, float delay, const char[] reason)
{
    if (!IsValidClient(client))
        return;

    if (g_bDebugTeleport)
    {
        LogMessage("[MGE tele][debug] queue reason=%s client=%N delay=%.2f arena=%d slot=%d team=%d alive=%d",
            reason, client, delay, g_iPlayerArena[client], g_iPlayerSlot[client], GetClientTeam(client), IsPlayerAlive(client) ? 1 : 0);
    }

    DataPack pack = new DataPack();
    CreateDataTimer(delay, Timer_TeleWithDebug, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(reason);
}

Action Timer_TeleWithDebug(Handle timer, DataPack pack)
{
    pack.Reset();
    int userid = pack.ReadCell();
    char reason[64];
    pack.ReadString(reason, sizeof(reason));

    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
        return Plugin_Stop;

    if (g_bDebugTeleport)
    {
        int arena_index = g_iPlayerArena[client];
        int player_slot = g_iPlayerSlot[client];
        bool inRespawnNet = IsClientInRespawnroomByNetprop(client);
        LogMessage("[MGE tele][debug] fire reason=%s client=%N arena=%d slot=%d team=%d alive=%d in_upgrade_zone=%d rr_depth=%d",
            reason, client, arena_index, player_slot, GetClientTeam(client), IsPlayerAlive(client) ? 1 : 0, inRespawnNet ? 1 : 0, g_iPlayerRespawnroomTouchDepth[client]);
    }

    return Timer_Tele(timer, userid);
}

// Attempts to load player statistics from database with Steam ID validation
void TryLoadPlayerStats(int client, bool isRetry, bool forceReload = false)
{
    if (g_bNoStats || !IsValidClient(client))
        return;
    
    char steamid_dirty[31], steamid[64], query[256];
    
    // Get Steam ID and validate the operation succeeded
    if (!GetClientAuthId(client, AuthId_Steam2, steamid_dirty, sizeof(steamid_dirty))) {
        if (isRetry) {
            LogError("Failed to get Steam ID for client %d even after Steam auth - stats loading failed", client);
            g_bPlayerEloVerified[client] = false;
        }
        return;
    }
    
    g_DB.Escape(steamid_dirty, steamid, sizeof(steamid));
    
    // Skip if stats already loaded successfully for this specific Steam ID
    if (!forceReload && g_bPlayerEloVerified[client] && StrEqual(g_sPlayerSteamID[client], steamid)) {
        if (isRetry) {
            LogMessage("Stats already loaded for client %d (%s), skipping retry", client, steamid);
        }
        return;
    }
    
    strcopy(g_sPlayerSteamID[client], 32, steamid);
    
    GetSelectPlayerStatsQuery(query, sizeof(query), steamid);
    g_DB.Query(SQL_OnPlayerReceived, query, client);
}

// Validates if player's ELO is verified and safe for arena play
bool IsPlayerEloValid(int client, char[] reason, int reason_size)
{
    if (IsFakeClient(client))
        return true; // Bots are always valid
        
    if (g_bNoStats)
        return true; // Stats disabled, allow anyone
    
    if (!g_bPlayerEloVerified[client]) {
        if (g_bAllowUnverifiedPlayers) {
            return true; // Allow unverified players when convar enabled
        }
        Format(reason, reason_size, "%T", "EloNotVerified", client);
        return false;
    }
    
    if (strlen(g_sPlayerSteamID[client]) == 0) {
        Format(reason, reason_size, "%T", "InvalidSteamID", client);
        return false;
    }
    
    return true;
}

// Checks if player should be included in ELO calculations
bool IsPlayerEligibleForElo(int client)
{
    if (IsFakeClient(client))
        return false; // Bots never affect ELO
        
    if (g_bNoStats)
        return false; // Stats disabled globally
        
    return g_bPlayerEloVerified[client]; // Only verified players eligible for ELO
}

// Resets player state including health, class, team assignment, and teleports to spawn
int ResetPlayer(int client)
{
    int arena_index = g_iPlayerArena[client];
    int player_slot = g_iPlayerSlot[client];

    if (!arena_index || !player_slot)
    {
        return 0;
    }

    // Any pending "move to spec while waiting" timer is stale once we are resetting this player.
    if (g_hPlayerWaitingSpecTimer[client] != null)
    {
        delete g_hPlayerWaitingSpecTimer[client];
        g_hPlayerWaitingSpecTimer[client] = null;
    }
    g_iPlayerWaiting[client] = false;

    // Remove projectiles when resetting a player (keep player entities for round reset only)
    if (!g_bClearPlayerEntities && g_bClearProjectiles && g_iArenaStatus[arena_index] == AS_FIGHT && !g_bArenaBBall[arena_index])
        RemoveArenaProjectiles(arena_index);

    g_iPlayerSpecTarget[client] = 0;

    bool is_red_team = (player_slot == SLOT_ONE || player_slot == SLOT_THREE);
    if (g_bArenaNoFight[arena_index])
        is_red_team = ((player_slot % 2) == 1);

    if (is_red_team)
        ChangeClientTeam(client, TEAM_RED);
    else
        ChangeClientTeam(client, TEAM_BLU);


    TFClassType class;
    class = g_tfctPlayerClass[client] ? g_tfctPlayerClass[client] : TFClass_Soldier;

    if (!IsPlayerAlive(client) || g_bArenaBBall[arena_index])
    {
        if (class != TF2_GetPlayerClass(client))
            TF2_SetPlayerClass(client, class);

        g_bSkipNextSpawnTeleport[client] = true;
        TF2_RespawnPlayer(client);
        
        // Reset velocity immediately to prevent momentum carryover from death
        float vel[3] = { 0.0, 0.0, 0.0 };
        TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
    } else {
        TF2_RegeneratePlayer(client);
        ExtinguishEntity(client);
    }

    g_iPlayerMaxHP[client] = GetEntProp(client, Prop_Data, "m_iMaxHealth");

    if (g_bArenaMidair[arena_index])
        g_iPlayerHP[client] = g_iMidairHP;
    else
        g_iPlayerHP[client] = g_iPlayerHandicap[client] ? g_iPlayerHandicap[client] : GetArenaTargetHPForClient(client, arena_index, g_iPlayerMaxHP[client]);

    if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index])
        SetEntProp(client, Prop_Data, "m_iHealth", g_iPlayerHandicap[client] ? g_iPlayerHandicap[client] : GetArenaTargetHPForClient(client, arena_index, g_iPlayerMaxHP[client]));

    UpdateHud(client);
    ResetClientAmmoCounts(client);
    QueueArenaTeleport(client, 0.1, "ResetPlayer");
    QueueApplyWeaponRules(client, 0.15);
    QueueApplyWeaponRules(client, 0.45);

    return 1;
}

// Restores killer's health and regenerates them after scoring a frag
void ResetKiller(int killer, int arena_index)
{
    int reset_hp = g_iPlayerHandicap[killer] ? g_iPlayerHandicap[killer] : GetArenaTargetHPForClient(killer, arena_index, g_iPlayerMaxHP[killer]);
    g_iPlayerHP[killer] = reset_hp;
    SetEntProp(killer, Prop_Data, "m_iHealth", reset_hp);
    RequestFrame(RegenKiller, killer);
}

// Ensures player is using a class allowed in their current arena
void SetPlayerToAllowedClass(int client, int arena_index)
{
    // If a player's class isn't allowed, set it to one that is.
    if (g_tfctPlayerClass[client] == TFClass_Unknown || !g_tfctArenaAllowedClasses[arena_index][g_tfctPlayerClass[client]])
    {
        for (int i = 1; i <= 9; i++)
        {
            if (g_tfctArenaAllowedClasses[arena_index][i])
            {
                if (g_bArenaUltiduo[arena_index] && g_bFourPersonArena[arena_index] && g_iPlayerSlot[client] > SLOT_TWO)
                {
                    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
                    if (view_as<TFClassType>(i) == g_tfctPlayerClass[client_teammate])
                    {
                        // Tell the player what he did wrong
                        MC_PrintToChat(client, "%t", "TeamAlreadyHasClass");
                        // Change him classes and set his class to the only one available
                        if (g_tfctPlayerClass[client_teammate] == TFClass_Soldier)
                        {
                            g_tfctPlayerClass[client] = TFClass_Medic;
                        }
                        else
                        {
                            g_tfctPlayerClass[client] = TFClass_Soldier;
                        }
                    }
                }
                else
                    g_tfctPlayerClass[client] = view_as<TFClassType>(i);

                break;
            }
        }
    }
}

// Regenerates killer's health and ammo after successful elimination
void RegenKiller(any killer)
{
    TF2_RegeneratePlayer(killer);
}


// ===== ENTITY AND EFFECTS MANAGEMENT =====

// Destroys all engineer buildings belonging to a specific client
void RemoveEngineerBuildings(int client)
{
    if (!IsValidClient(client))
    {
        return;
    }

    int building = -1;
    while ((building = FindEntityByClassname(building, "obj_*")) != -1)
    {
      if (GetEntPropEnt(building, Prop_Send, "m_hBuilder") == client)
      {
          SetVariantInt(9999);
          AcceptEntityInput(building, "RemoveHealth");
      }
    }
}

// Creates and attaches particle effects to entities for visual feedback
void AttachParticle(int ent, char[] particleType, int &particle) 
{
    // Particle code borrowed from "The Amplifier" and "Presents!".
    particle = CreateEntityByName("info_particle_system");

    float pos[3];

    // Get position of entity
    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

    // Teleport, set up
    TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
    DispatchKeyValue(particle, "effect_name", particleType);

    SetVariantString("!activator");
    AcceptEntityInput(particle, "SetParent", ent, particle, 0);

    // All entities in presents are given a targetname to make clean up easier
    DispatchKeyValue(particle, "targetname", "tf2particle");

    // Spawn and start
    DispatchSpawn(particle);
    ActivateEntity(particle);
    AcceptEntityInput(particle, "Start");
}

// Removes particle effects attached to a specific client
void RemoveClientParticle(int client)
{
    int particle = EntRefToEntIndex(g_iClientParticle[client]);

    if (particle != 0 && IsValidEntity(particle))
        RemoveEdict(particle);

    g_iClientParticle[client] = 0;
}


// ===== UTILITY FUNCTIONS =====

// Converts player slot (1-4) to team slot (1-2) for scoring and team identification
int GetTeamSlotFromPlayerSlot(int player_slot)
{
    return (player_slot > 2) ? (player_slot - 2) : player_slot;
}

// Handles engineer building removal when player changes from engineer to another class
void HandleEngineerClassChange(int client, TFClassType old_class, TFClassType new_class)
{
    if (old_class == TFClass_Engineer && new_class != TFClass_Engineer)
    {
        RemoveEngineerBuildings(client);
    }
}

// Checks if class change would create conflict in Ultiduo 2v2 (same class on team)
bool IsUltiduo2v2ClassConflict(int client, TFClassType new_class, int arena_index)
{
    if (!g_bArenaUltiduo[arena_index] || !g_bFourPersonArena[arena_index])
        return false;
        
    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
    if (!IsValidClient(client_teammate))
        return false;
        
    return (new_class == g_tfctPlayerClass[client_teammate]);
}

// Formats player names for 2v2 team display (e.g., "Player1 and Player2")
void FormatTeamPlayerNames(int player1, int player2, char[] buffer, int maxlen)
{
    if (!IsValidClient(player1))
    {
        buffer[0] = '\0';
        return;
    }
    
    char player1_name[MAX_NAME_LENGTH];
    GetClientName(player1, player1_name, sizeof(player1_name));
    
    if (!IsValidClient(player2))
    {
        strcopy(buffer, maxlen, player1_name);
        return;
    }
    
    char player2_name[MAX_NAME_LENGTH];
    GetClientName(player2, player2_name, sizeof(player2_name));
    
    Format(buffer, maxlen, "%s and %s", player1_name, player2_name);
}

// Validates if a client index represents a valid, connected, non-bot player
bool IsValidClient(int iClient, bool bIgnoreKickQueue = false)
{
    if
    (
        // "client" is 0 (console) or lower - nope!
            0 >= iClient
        // "client" is higher than MaxClients - nope!
        || MaxClients < iClient
        // "client" isnt in game aka their entity hasn't been created - nope!
        || !IsClientInGame(iClient)
        // "client" is in the kick queue - nope!
        || (IsClientInKickQueue(iClient) && !bIgnoreKickQueue)
        // "client" is sourcetv - nope!
        || IsClientSourceTV(iClient)
        // "client" is the replay bot - nope!
        || IsClientReplay(iClient)
    )
    {
        return false;
    }
    return true;
}

// Determines if player is using rocket launcher or grenade launcher for physics calculations
bool ShootsRocketsOrPipes(int client)
{
    char weapon[64];
    GetClientWeapon(client, weapon, sizeof(weapon));
    return (StrContains(weapon, "tf_weapon_rocketlauncher") == 0) || StrEqual(weapon, "tf_weapon_grenadelauncher");
}

// Forces closure of any open menu for a specific client
void CloseClientMenu(int client)
{
    if (!IsValidClient(client))
        return;

    if (GetClientMenu(client, null) != MenuSource_None)
    {
        InternalShowMenu(client, "\10", 1);
        CancelClientMenu(client, true, null);
    }
}

// Handles class change requests for players not currently in any arena
Action HandleLobbyClassChange(int client, TFClassType new_class, int arena_index)
{
    if (!g_tfctClassAllowed[view_as<int>(new_class)])
    {
        MC_PrintToChat(client, "%t", "ClassIsNotAllowed");
        return Plugin_Handled;
    }
    
    if (IsUltiduo2v2ClassConflict(client, new_class, arena_index))
    {
        MC_PrintToChat(client, "%t", "TeamAlreadyHasClass");
        return Plugin_Handled;
    }
    
    HandleEngineerClassChange(client, g_tfctPlayerClass[client], new_class);
    TF2_SetPlayerClass(client, new_class);
    g_tfctPlayerClass[client] = new_class;
    
    ChangeClientTeam(client, TEAM_SPEC);
    UpdateHudForArena(g_iPlayerArena[client]);
    return Plugin_Handled;
}

// Validates if a player can change classes in their current arena
bool CanPlayerChangeClassInArena(int client, TFClassType new_class, int arena_index)
{
    if (!g_tfctArenaAllowedClasses[arena_index][new_class])
    {
        MC_PrintToChat(client, "%t", "ClassIsNotAllowed");
        return false;
    }
    
    if (IsUltiduo2v2ClassConflict(client, new_class, arena_index))
    {
        MC_PrintToChat(client, "%t", "TeamAlreadyHasClass");
        return false;
    }
    
    return true;
}

// Checks class change timing restrictions for 2v2 arenas
bool CanPlayerChangeClassInTeamArena(int client, int arena_index)
{
    if (!g_bArenaClassChange[arena_index])
    {
        // Class changes only allowed during waiting phase
        if (g_iArenaStatus[arena_index] != AS_WAITING_READY && g_iArenaStatus[arena_index] != AS_IDLE)
        {
            MC_PrintToChat(client, "%t", "ClassChangesOnlyWhileWaiting");
            return false;
        }
    }
    else if (g_iArenaStatus[arena_index] == AS_FIGHT)
    {
        // Class changes allowed during countdown, but slay during fight
        MC_PrintToChat(client, "%t", "ClassChangeDuringFightSlay");
        ForcePlayerSuicide(client);
        return true; // Allow but with penalty
    }
    
    return true;
}

// Checks class change restrictions for 1v1 arenas
bool CanPlayerChangeClassIn1v1Arena(int client, int arena_index)
{
    // Allow class changes if score is still 0-0, even during fight
    if (!g_bArenaClassChange[arena_index] && g_iArenaStatus[arena_index] == AS_FIGHT && 
        (g_iArenaScore[arena_index][SLOT_ONE] != 0 || g_iArenaScore[arena_index][SLOT_TWO] != 0))
    {
        MC_PrintToChat(client, "%t", "ClassChangesDisabledDuringFight");
        return false;
    }
    
    return true;
}

// Determines if player is in an active arena slot (participating in duels)
bool IsPlayerInActiveSlot(int client, int arena_index)
{
    int slot = g_iPlayerSlot[client];
    
    if (!g_bFourPersonArena[arena_index])
        return (slot == SLOT_ONE || slot == SLOT_TWO);
    else
        return (slot >= SLOT_ONE && slot <= SLOT_FOUR);
}

// Executes the class change and handles related game mechanics
Action ExecuteArenaClassChange(int client, TFClassType new_class, int arena_index)
{
    // Check if class changes are allowed in current arena state
    if (g_iArenaStatus[arena_index] == AS_FIGHT && !g_bArenaMGE[arena_index] && !g_bArenaEndif[arena_index] && !g_bArenaKoth[arena_index])
    {
        MC_PrintToChat(client, "%t", "NoClassChange");
        return Plugin_Handled;
    }
    
    HandleEngineerClassChange(client, g_tfctPlayerClass[client], new_class);
    TF2_SetPlayerClass(client, new_class);
    g_tfctPlayerClass[client] = new_class;
    
    // Add class to tracking list if class changes are allowed and duel is active
    if (g_bArenaClassChange[arena_index] && g_iArenaStatus[arena_index] != AS_IDLE && 
        g_alPlayerDuelClasses[client].FindValue(view_as<int>(new_class)) == -1)
    {
        g_alPlayerDuelClasses[client].Push(view_as<int>(new_class));
    }
    
    // Handle class change during active combat
    if (IsPlayerAlive(client))
    {
        HandleActivePlayerClassChange(client, arena_index);
    }
    
    // Reset handicap to prevent exploits
    g_iPlayerHandicap[client] = 0;
    UpdateHudForArena(g_iPlayerArena[client]);
    return Plugin_Continue;
}

// Records a scoring point for the player's current class during a duel and tracks matchup
void AddClassPointForPlayer(int client, int victim)
{
    if (!IsValidClient(client) || !IsValidClient(victim))
        return;

    TFClassType classType = g_tfctPlayerClass[client];
    int classId = view_as<int>(classType);
    if (classId < 1 || classId > 9)
    {
        classType = TF2_GetPlayerClass(client);
        classId = view_as<int>(classType);
    }

    TFClassType victimClassType = g_tfctPlayerClass[victim];
    int victimClassId = view_as<int>(victimClassType);
    if (victimClassId < 1 || victimClassId > 9)
    {
        victimClassType = TF2_GetPlayerClass(victim);
        victimClassId = view_as<int>(victimClassType);
    }

    if (classId >= 1 && classId <= 9)
    {
        g_iPlayerClassPoints[client][classId] += 1;
        // Track matchup interaction
        if (victimClassId >= 1 && victimClassId <= 9)
        {
            g_iPlayerMatchupCount[client][classId][victimClassId] += 1;
            // Initialize matchup rating if it doesn't exist
            if (g_iPlayerClassRating[client][classId][victimClassId] == 0)
            {
                g_iPlayerClassRating[client][classId][victimClassId] = 1500;
            }
        }
    }
}

// Handles class changes for players currently alive and fighting
void HandleActivePlayerClassChange(int client, int arena_index)
{
    if (!(g_iArenaStatus[arena_index] == AS_FIGHT && (g_bArenaMGE[arena_index] || g_bArenaEndif[arena_index])))
    {
        CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
        return;
    }
    
    // Handle scoring and match completion for MGE/Endif arenas
    int killer_slot = (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
    int fraglimit = g_iArenaFraglimit[arena_index];
    int killer = g_iArenaQueue[arena_index][killer_slot];
    int killer_teammate;
    int killer_team_slot = GetTeamSlotFromPlayerSlot(killer_slot);
    int client_team_slot = GetTeamSlotFromPlayerSlot(g_iPlayerSlot[client]);
    int client_teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
    
    if (g_bFourPersonArena[arena_index])
    {
        killer_teammate = GetPlayerTeammate(killer_slot, arena_index);
    }
    
    if (g_iArenaStatus[arena_index] == AS_FIGHT && killer)
    {
        // Award points and provide feedback
        if (g_bArenaClassChange[arena_index])
        {
            g_iArenaScore[arena_index][killer_team_slot] += 1;
            AddClassPointForPlayer(killer, client);
            MC_PrintToChat(killer, "%t", "ClassChangePointOpponent");
            MC_PrintToChat(client, "%t", "ClassChangePoint");
        }
        
        if (g_bFourPersonArena[arena_index] && killer_teammate)
        {
            CreateTimer(3.0, Timer_NewRound, arena_index);
        }
    }
    
    // Update HUDs for all players
    UpdateHud(client);
    if (IsValidClient(killer))
    {
        ResetKiller(killer, arena_index);
        UpdateHud(killer);
    }
    
    if (g_bFourPersonArena[arena_index])
    {
        if (IsValidClient(killer_teammate))
        {
            ResetKiller(killer_teammate, arena_index);
            UpdateHud(killer_teammate);
        }
        if (IsValidClient(client_teammate))
        {
            ResetKiller(client_teammate, arena_index);
            UpdateHud(client_teammate);
        }
    }
    
    // Check for match completion
    if (ValidateMatchCompletion(arena_index, killer_team_slot, fraglimit))
    {
        ProcessClassChangeMatchCompletion(arena_index, client, killer, killer_teammate, client_teammate, killer_team_slot, client_team_slot, fraglimit);
    }
    
    CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(client));
}


// ===== COMMAND HANDLERS =====

// Handles team join requests with special logic for spectating and 2v2 team switching
Action Command_JoinTeam(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    // Get the team argument
    char team[16];  
    GetCmdArg(1, team, sizeof(team));

    // Allow spectate command to pass through
    if (!strcmp(team, "spectate"))
    {
        // Handle spectating in arenas - treat as !remove for any arena type
        int arena_index = g_iPlayerArena[client];
        if (arena_index > 0)
        {
            // For any arena (1v1 or 2v2), going to spec means they want to leave
            MC_PrintToChat(client, "%t", "SpecRemove");
            RemoveFromQueue(client, true);
        }

        // Handle spectator HUD and target logic (moved from Event_PlayerTeam)
        HideHud(client);
        CreateTimer(0.3, Timer_ChangeSpecTarget, GetClientUserId(client));

        return Plugin_Handled;
    }
    else
    {
        // Check if player is in a 2v2 arena and trying to switch teams
        int arena_index = g_iPlayerArena[client];
        TFTeam currentTeam = TF2_GetClientTeam(client);

        if (arena_index > 0 && g_bFourPersonArena[arena_index] &&
            currentTeam != TFTeam_Spectator && currentTeam != TFTeam_Unassigned)
        {
            // Player is in a 2v2 arena - allow team switching
            int target_team = 0;
            if (!strcmp(team, "red"))
                target_team = TEAM_RED;
            else if (!strcmp(team, "blue") || !strcmp(team, "blu"))
                target_team = TEAM_BLU;

            if (target_team != 0)
            {
                // Use existing 2v2 team switch logic
                Handle2v2TeamSwitch(client, arena_index, target_team);
                return Plugin_Stop;
            }
        }

        // Block manual team joining for red/blue teams (default behavior)
        if (currentTeam == TFTeam_Spectator)
        {
            ShowMainMenu(client);
        }
        else
        {
            // Warn players who are already on a team that they can't manually switch
            MC_PrintToChat(client, "%t", "CannotJoinTeamsManually");

            // Spawn exploit prevention (moved from Event_PlayerTeam)
            if (arena_index == 0)
            {
                TF2_SetPlayerClass(client, view_as<TFClassType>(0));
            }
        }
        return Plugin_Stop;
    }
}

// Processes class change requests with arena-specific restrictions and penalties
Action Command_JoinClass(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;
        
    if (!args)
        return Plugin_Handled;
    
    // Parse class change request
    char s_class[64];
    GetCmdArg(1, s_class, sizeof(s_class));
    TFClassType new_class = TF2_GetClass(s_class);
    
    if (new_class == g_tfctPlayerClass[client])
        return Plugin_Handled;
    
    int arena_index = g_iPlayerArena[client];
    
    // Handle lobby class changes (not in arena)
    if (arena_index == 0)
        return HandleLobbyClassChange(client, new_class, arena_index);
    
    // Validate class change in current arena
    if (!CanPlayerChangeClassInArena(client, new_class, arena_index))
        return Plugin_Handled;
    
    // Handle Ultiduo class setting (special case)
    if (g_bArenaUltiduo[arena_index] && g_bFourPersonArena[arena_index])
    {
        TF2_SetPlayerClass(client, new_class);
        g_tfctPlayerClass[client] = new_class;
    }
    
    // Handle spectating players - just set class
    if (!IsPlayerInActiveSlot(client, arena_index))
    {
        g_tfctPlayerClass[client] = new_class;
        ChangeClientTeam(client, TEAM_SPEC);
        return Plugin_Handled;
    }
    
    // Check timing restrictions for active players
    if (g_bFourPersonArena[arena_index])
    {
        if (!CanPlayerChangeClassInTeamArena(client, arena_index))
            return Plugin_Handled;
    }
    else
    {
        if (!CanPlayerChangeClassIn1v1Arena(client, arena_index))
            return Plugin_Handled;
    }
    
    // Execute the class change
    return ExecuteArenaClassChange(client, new_class, arena_index);
}

// Manages player handicap system for health adjustments in duels
Action Command_Handicap(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];

    if (!arena_index || g_bArenaMidair[arena_index])
    {
        MC_PrintToChat(client, "%t", "MustJoinArena");
        g_iPlayerHandicap[client] = 0;
        return Plugin_Handled;
    }

    if (args == 0)
    {
        if (g_iPlayerHandicap[client] == 0)
            MC_PrintToChat(client, "%t", "NoCurrentHandicap", g_iPlayerHandicap[client]);
        else
            MC_PrintToChat(client, "%t", "CurrentHandicap", g_iPlayerHandicap[client]);
    } else {
        char argstr[64];
        GetCmdArgString(argstr, sizeof(argstr));
        int argint = StringToInt(argstr);

        if (StrEqual(argstr, "off", false))
        {
            MC_PrintToChat(client, "%t", "HandicapDisabled");
            g_iPlayerHandicap[client] = 0;
            return Plugin_Handled;
        }

        if (argint > GetArenaTargetHPForClient(client, arena_index, g_iPlayerMaxHP[client]))
        {
            MC_PrintToChat(client, "%t", "InvalidHandicap");
            g_iPlayerHandicap[client] = 0;
        } else if (argint <= 0) {
            MC_PrintToChat(client, "%t", "InvalidHandicap");
        } else {
            g_iPlayerHandicap[client] = argint;

            // If the client currently has more health than their handicap allows, lower it to the proper amount.
            if (IsPlayerAlive(client) && g_iPlayerHP[client] > g_iPlayerHandicap[client])
            {
                if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index])
                {
                    // Prevent an possible exploit where a player could restore their buff if it decayed naturally without them taking damage.
                    if (GetEntProp(client, Prop_Data, "m_iHealth") > g_iPlayerHandicap[client])
                    {
                        SetEntProp(client, Prop_Data, "m_iHealth", g_iPlayerHandicap[client]);
                        g_iPlayerHP[client] = g_iPlayerHandicap[client];
                    }
                } else {
                    g_iPlayerHP[client] = g_iPlayerHandicap[client];
                }

                // Update overlay huds to reflect health change.
                int
                    player_slot = g_iPlayerSlot[client],
                    foe_slot = player_slot == SLOT_ONE ? SLOT_TWO : SLOT_ONE,
                    foe = g_iArenaQueue[arena_index][foe_slot],
                    foe_teammate,
                    player_teammate;

                if (g_bFourPersonArena[arena_index])
                {
                    player_teammate = GetPlayerTeammate(player_slot, arena_index);
                    foe_teammate = GetPlayerTeammate(foe_slot, arena_index);

                    UpdateHud(player_teammate);
                    UpdateHud(foe_teammate);
                }

                UpdateHud(client);
                UpdateHud(foe);
                UpdateHudForArena(g_iPlayerArena[client]);
            }
        }
    }

    return Plugin_Handled;
}

// Blocks eureka effect teleportation to prevent arena exploitation
Action Command_EurekaTeleport(int client, int args)
{
    // Block eureka effect teleport
    return Plugin_Handled;
}

// Blocks automatic team assignment and shows arena selection menu instead
Action Command_AutoTeam(int client, int args)
{
    // Block autoteam command usage, and show add menu instead
    if (!IsValidClient(client))
        return Plugin_Handled;
    
    if (TF2_GetClientTeam(client) == TFTeam_Spectator)
    {
        ShowMainMenu(client);
    }
    return Plugin_Stop;
}


// ===== GAME EVENT HANDLERS =====

// Handles post-inventory updates (loadout/respawnroom) by re-applying arena teleports.
Action Event_PostInventoryApplication(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];
    if (arena_index <= 0)
        return Plugin_Continue;

    int player_slot = g_iPlayerSlot[client];
    if (player_slot <= 0)
        return Plugin_Continue;

    int max_active_slot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
    if (!g_bArenaNoFight[arena_index] && player_slot > max_active_slot)
        return Plugin_Continue;

    bool inRespawnNet = IsClientInRespawnroomByNetprop(client);
    bool inRespawnOutput = (g_iPlayerRespawnroomTouchDepth[client] > 0);
    bool inRespawn = (inRespawnNet || inRespawnOutput);
    if (g_bDebugTeleport)
    {
        LogMessage("[MGE tele][debug] post_inventory_application client=%N arena=%d slot=%d in_upgrade_zone=%d rr_depth=%d in_respawn=%d",
            client, arena_index, player_slot, inRespawnNet ? 1 : 0, g_iPlayerRespawnroomTouchDepth[client], inRespawn ? 1 : 0);
    }

    // Do not re-teleport on unrelated trigger/inventory updates outside respawnrooms.
    if (!inRespawn)
    {
        if (g_bDebugTeleport)
            LogMessage("[MGE tele][debug] post_inventory_application skip: not in respawn context client=%N", client);
        return Plugin_Continue;
    }

    if (g_bDebugTeleport)
        LogMessage("[MGE tele][debug] post_inventory_application: teleport suppressed (handled on player_spawn) client=%N", client);
    QueueApplyWeaponRules(client, 0.1);
    QueueApplyWeaponRules(client, 0.35);
    return Plugin_Continue;
}

// Handles player spawn events to set class, reset ammo, and manage team assignments
Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return Plugin_Continue;

    int arena_index = g_iPlayerArena[client];

    g_tfctPlayerClass[client] = TF2_GetPlayerClass(client);


    ResetClientAmmoCounts(client);

    if (!g_bArenaNoFight[arena_index] && !g_bFourPersonArena[arena_index] && g_iPlayerSlot[client] != SLOT_ONE && g_iPlayerSlot[client] != SLOT_TWO)
        ChangeClientTeam(client, TEAM_SPEC);

    else if (!g_bArenaNoFight[arena_index] && g_bFourPersonArena[arena_index] && g_iPlayerSlot[client] != SLOT_ONE && g_iPlayerSlot[client] != SLOT_TWO && (g_iPlayerSlot[client] != SLOT_THREE && g_iPlayerSlot[client] != SLOT_FOUR))
        ChangeClientTeam(client, TEAM_SPEC);

    if (g_bArenaMGE[arena_index])
    {
        g_iPlayerHP[client] = GetArenaTargetHPForClient(client, arena_index, g_iPlayerMaxHP[client]);
        UpdateHudForArena(arena_index);
    }

    if (g_bArenaBBall[arena_index])
    {
        g_bPlayerHasIntel[client] = false;
        RemoveBBallBackModel(client);
    }

    // post_inventory/loadout respawns should teleport from this hook; ResetPlayer-initiated spawns already queue teleports.
    if (arena_index > 0)
    {
        bool shouldTeleportOnSpawn = true;
        if (g_bSkipNextSpawnTeleport[client])
        {
            shouldTeleportOnSpawn = false;
            g_bSkipNextSpawnTeleport[client] = false;
            if (g_bDebugTeleport)
                LogMessage("[MGE tele][debug] player_spawn: skip teleport (already queued by ResetPlayer) client=%N", client);
        }

        int player_slot = g_iPlayerSlot[client];
        int max_active_slot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
        if (!g_bArenaNoFight[arena_index] && player_slot > max_active_slot)
            shouldTeleportOnSpawn = false;

        if (shouldTeleportOnSpawn)
        {
            QueueArenaTeleport(client, 0.05, "player_spawn");
            if (g_bDebugTeleport)
                LogMessage("[MGE tele][debug] player_spawn: queue teleport client=%N arena=%d slot=%d", client, arena_index, player_slot);
        }
    }

    QueueApplyWeaponRules(client, 0.15);

    return Plugin_Continue;
}

// Processes damage events for health tracking, airshot detection, and ammo management
Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(victim))
        return Plugin_Continue;

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int arena_index = g_iPlayerArena[victim];
    int iDamage = event.GetInt("damageamount");

    if (attacker > 0 && victim != attacker) // If the attacker wasn't the person being hurt, or the world (fall damage).
    {
        bool shootsRocketsOrPipes = ShootsRocketsOrPipes(attacker);
        if (g_bArenaEndif[arena_index])
        {
            if (shootsRocketsOrPipes)
                CreateTimer(0.1, BoostVectors, GetClientUserId(victim));
        }

        if (g_bPlayerTakenDirectHit[victim])
        {
            bool isVictimInAir = !(GetEntityFlags(victim) & (FL_ONGROUND));

            if (isVictimInAir)
            {
                // Airshot
                float dist = DistanceAboveGround(victim);
                if (dist >= g_iAirshotHeight)
                {
                    if (g_bArenaMidair[arena_index])
                        g_iPlayerHP[victim] -= 1;

                    if (g_bArenaEndif[arena_index] && dist >= 250)
                    {
                        g_iPlayerHP[victim] = -1;
                    }
                }
            }
        }
    }

    g_bPlayerTakenDirectHit[victim] = false;

    if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index])
        g_iPlayerHP[victim] = GetClientHealth(victim);
    else if (g_bArenaAmmomod[arena_index])
        g_iPlayerHP[victim] -= iDamage;

    if (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index] || g_bArenaEndif[arena_index])
    {
        if (g_iPlayerHP[victim] <= 0)
            SetEntityHealth(victim, 0);
        else
            SetEntityHealth(victim, g_iPlayerMaxHP[victim]);
    }

    UpdateHud(victim);
    UpdateHud(attacker);
    UpdateHudForArena(g_iPlayerArena[victim]);

    return Plugin_Continue;
}

// Manages player death events including scoring, ELO calculation, and respawn logic
Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));

    int arena_index = g_iPlayerArena[victim];
    int victim_slot = g_iPlayerSlot[victim];

    // Reset victim's velocity to prevent momentum carryover to respawn
    if (IsValidClient(victim) && arena_index > 0)
    {
        float vel[3] = { 0.0, 0.0, 0.0 };
        TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vel);
    }

    int killer_slot;
    int killer;
    int killer_teammate;
    int victim_teammate;
    
    // In 2v2: RED (slots 1,3) vs BLU (slots 2,4)
    // In 1v1: RED (slot 1) vs BLU (slot 2)
    if (g_bFourPersonArena[arena_index])
    {
        // 2v2 logic: find an alive enemy player
        if (victim_slot == SLOT_ONE || victim_slot == SLOT_THREE)
        {
            // Victim was RED, killer is BLU (slot 2 or 4)
            killer = g_iArenaQueue[arena_index][SLOT_TWO];
            killer_slot = SLOT_TWO;
            if (!IsValidClient(killer) || !IsPlayerAlive(killer))
            {
                killer = g_iArenaQueue[arena_index][SLOT_FOUR];
                killer_slot = SLOT_FOUR;
            }
        }
        else
        {
            // Victim was BLU, killer is RED (slot 1 or 3)  
            killer = g_iArenaQueue[arena_index][SLOT_ONE];
            killer_slot = SLOT_ONE;
            if (!IsValidClient(killer) || !IsPlayerAlive(killer))
            {
                killer = g_iArenaQueue[arena_index][SLOT_THREE];
                killer_slot = SLOT_THREE;
            }
        }
        
        victim_teammate = GetPlayerTeammate(victim_slot, arena_index);
        if (IsValidClient(killer))
            killer_teammate = GetPlayerTeammate(killer_slot, arena_index);
    }
    else
    {
        // 1v1 logic: simple slot mapping
        killer_slot = (victim_slot == SLOT_ONE) ? SLOT_TWO : SLOT_ONE;
        killer = g_iArenaQueue[arena_index][killer_slot];
    }

    // Gets the killer and victims team slot (red 1, blu 2)
    int killer_team_slot = GetTeamSlotFromPlayerSlot(killer_slot);
    int victim_team_slot = GetTeamSlotFromPlayerSlot(victim_slot);

    // Don't detect dead ringer deaths
    int victim_deathflags = event.GetInt("death_flags");
    if (victim_deathflags & 32)
    {
        return Plugin_Continue;
    }


    RemoveClientParticle(victim);

    if (!arena_index)
        ChangeClientTeam(victim, TEAM_SPEC);

    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    // AFK check removed - now handled by AFK plugin via forwards

    if (g_iArenaStatus[arena_index] < AS_FIGHT && IsValidClient(attacker) && IsPlayerAlive(attacker))
    {
        TF2_RegeneratePlayer(attacker);
        int raised_hp = GetArenaTargetHPForClient(attacker, arena_index, g_iPlayerMaxHP[attacker]);
        g_iPlayerHP[attacker] = raised_hp;
        SetEntProp(attacker, Prop_Data, "m_iHealth", raised_hp);
    }

    // Call arena player death forward
    if (arena_index > 0)
    {
        CallForward_OnArenaPlayerDeath(victim, attacker, arena_index);
    }

    if (g_iArenaStatus[arena_index] < AS_FIGHT || g_iArenaStatus[arena_index] > AS_FIGHT)
    {
        CreateTimer(0.1, Timer_ResetPlayer, GetClientUserId(victim));
        return Plugin_Handled;
    }

    if ((g_bFourPersonArena[arena_index] && !IsPlayerAlive(killer)) || (g_bFourPersonArena[arena_index] && !IsPlayerAlive(killer_teammate) && !IsPlayerAlive(killer)))
    {
        if (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index])
            return Plugin_Handled;
    }

    if (!g_bArenaBBall[arena_index] && !g_bArenaKoth[arena_index] && (!g_bFourPersonArena[arena_index] || (g_bFourPersonArena[arena_index] && !IsPlayerAlive(victim_teammate)))) // Kills shouldn't give points in bball. Or if only 1 player in a two person arena dies
    {
        // Call forward to allow blocking score awarding
        Action result = CallForward_OnPlayerScorePoint(killer, victim, arena_index);
        if (result == Plugin_Continue)
        {
            g_iArenaScore[arena_index][killer_team_slot] += 1;
            AddClassPointForPlayer(killer, victim);
            // Call forward after successful scoring
            CallForward_OnPlayerScoredPoint(killer, victim, arena_index, g_iArenaScore[arena_index][killer_team_slot]);
        }
    }

    if (!g_bArenaEndif[arena_index]) // Endif does not need to display health, since it is one-shot kills.
    {
        // We must get the player that shot you last in 4 player arenas
        // The valid client check shouldn't be necessary but I'm getting invalid clients here for some reason
        // This may be caused by players killing themselves in 1v1 arenas without being attacked, or dieing after
        // A player disconnects but before the arena status transitions out of fight mode?
        // TODO: check properly
        if (g_bFourPersonArena[arena_index] && IsValidClient(attacker) && IsPlayerAlive(attacker))
        {
            if ((g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index] || g_bArenaKoth[arena_index]) && (victim != attacker))
                MC_PrintToChat(victim, "%t", "HPLeft", GetClientHealth(attacker));
            else if (victim != attacker)
                MC_PrintToChat(victim, "%t", "HPLeft", g_iPlayerHP[attacker]);
        }
        // In 1v1 arenas we can assume the person who killed you is the other person in the arena
        else if (IsValidClient(killer) && IsPlayerAlive(killer))
        {
            if (g_bArenaMGE[arena_index] || g_bArenaBBall[arena_index] || g_bArenaKoth[arena_index])
                MC_PrintToChat(victim, "%t", "HPLeft", GetClientHealth(killer));
            else
                MC_PrintToChat(victim, "%t", "HPLeft", g_iPlayerHP[killer]);
        }
    }

    // Currently set up so that if its a 2v2 duel the round will reset after both players on one team die and a point will be added for that round to the other team
    // Another possibility is to make it like dm where its instant respawn for every player, killer gets hp, and a point is awarded for every kill

    int fraglimit = g_iArenaFraglimit[arena_index];

    if ((!g_bFourPersonArena[arena_index] && (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index])) ||
        (g_bFourPersonArena[arena_index] && !IsPlayerAlive(victim_teammate) && !g_bArenaBBall[arena_index] && !g_bArenaKoth[arena_index]))
    g_iArenaStatus[arena_index] = AS_AFTERFIGHT;

    if (ShouldProcessMatchCompletion(arena_index, killer_team_slot, fraglimit))
    {
        ProcessMatchCompletion(arena_index, killer, killer_teammate, victim, victim_teammate, killer_team_slot, victim_team_slot, fraglimit);
    }
    else if (g_bArenaAmmomod[arena_index] || g_bArenaMidair[arena_index])
    {
        if (!g_bFourPersonArena[arena_index])
            CreateTimer(3.0, Timer_NewRound, arena_index);

        else if (g_bFourPersonArena[arena_index] && !IsPlayerAlive(victim_teammate))
            CreateTimer(3.0, Timer_NewRound, arena_index);
        
        else if (g_bFourPersonArena[arena_index] && victim_teammate && IsPlayerAlive(victim_teammate))
        {
            // Set the player as waiting (same as other 2v2 modes)
            g_iPlayerWaiting[victim] = true;
            // Change the player to spec to keep him from respawning
            if (g_hPlayerWaitingSpecTimer[victim] != null)
            {
                delete g_hPlayerWaitingSpecTimer[victim];
                g_hPlayerWaitingSpecTimer[victim] = null;
            }
            g_hPlayerWaitingSpecTimer[victim] = CreateTimer(5.0, Timer_ChangePlayerSpec, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
        }

    }
    else
    {
        if (g_bArenaBBall[arena_index])
        {
            HandleBBallPlayerDeath(victim, killer, arena_index);
        } else {
            if (!g_bFourPersonArena[arena_index] && !g_bArenaKoth[arena_index])
            {
                ResetKiller(killer, arena_index);
            }
            // Handle 2v2 team reset when one team is eliminated
            Handle2v2TeamResetOnDeath(arena_index, victim, victim_teammate, killer_teammate, killer_team_slot);


        }


        // TODO: Check to see if its koth and apply a spawn penalty if needed depending on who's capping
        if (g_bArenaBBall[arena_index] || g_bArenaKoth[arena_index])
        {
            CreateTimer(g_fArenaRespawnTime[arena_index], Timer_ResetPlayer, GetClientUserId(victim));
        }
        else if (g_bFourPersonArena[arena_index] && victim_teammate && IsPlayerAlive(victim_teammate))
        {
            // Set the player as waiting
            g_iPlayerWaiting[victim] = true;
            // Change the player to spec to keep him from respawning
            if (g_hPlayerWaitingSpecTimer[victim] != null)
            {
                delete g_hPlayerWaitingSpecTimer[victim];
                g_hPlayerWaitingSpecTimer[victim] = null;
            }
            g_hPlayerWaitingSpecTimer[victim] = CreateTimer(5.0, Timer_ChangePlayerSpec, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
        }
        else
            CreateTimer(g_fArenaRespawnTime[arena_index], Timer_ResetPlayer, GetClientUserId(victim));

    }

    UpdateHud(victim);
    UpdateHud(killer);

    if (g_bFourPersonArena[arena_index])
    {
        UpdateHud(victim_teammate);
        UpdateHud(killer_teammate);
    }

    UpdateHudForArena(arena_index);

    return Plugin_Continue;
}


// ===== TIMER FUNCTIONS =====

// Displays welcome messages to new players with plugin information
Action Timer_WelcomePlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidClient(client))
    {
        return Plugin_Continue;
    }

    MC_PrintToChat(client, "%t", "Welcome1", PL_VERSION);
    if (StrContains(g_sMapName, "mge_", false) == 0)
        MC_PrintToChat(client, "%t", "Welcome2");
    MC_PrintToChat(client, "%t", "Welcome3");

    return Plugin_Continue;
}

bool IsClientRedSpawnSide(int client, int arena_index)
{
    int slot = g_iPlayerSlot[client];
    if (slot > 0)
    {
        if (g_bArenaNoFight[arena_index])
            return ((slot % 2) == 1);

        return (slot == SLOT_ONE || slot == SLOT_THREE);
    }

    TFTeam team = TF2_GetClientTeam(client);
    if (team == TFTeam_Red)
        return true;
    if (team == TFTeam_Blue)
        return false;
    
    return false;
}

int FindAliveTeammateTeamSpawnPoint(int client, int arena_index, bool isRedTeam)
{
    int slot = g_iPlayerSlot[client];
    if (g_bFourPersonArena[arena_index] && slot >= SLOT_ONE && slot <= SLOT_FOUR)
    {
        int teammate = GetPlayerTeammate(slot, arena_index);
        if (IsValidClient(teammate) && IsPlayerAlive(teammate))
            return GetPlayerCurrentTeamSpawnPoint(teammate, arena_index, isRedTeam);
    }

    int maxSlot = g_bArenaNoFight[arena_index] ? MaxClients : (g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO);
    for (int i = SLOT_ONE; i <= maxSlot; i++)
    {
        int teammate = g_iArenaQueue[arena_index][i];
        if (!IsValidClient(teammate) || teammate == client || !IsPlayerAlive(teammate))
            continue;
        if (IsClientRedSpawnSide(teammate, arena_index) != isRedTeam)
            continue;

        int teammateSpawn = GetPlayerCurrentTeamSpawnPoint(teammate, arena_index, isRedTeam);
        if (teammateSpawn > 0)
            return teammateSpawn;
    }

    return -1;
}

bool TeleportToConfiguredTeamSpawn(int client, int arena_index, float vel[3])
{
    if (!g_bArenaUseTeamSpawns[arena_index] || g_iArenaRedSpawns[arena_index] <= 0 || g_iArenaBluSpawns[arena_index] <= 0)
    {
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] team_spawns skip client=%N arena=%d use_team=%d red_count=%d blu_count=%d",
                client, arena_index, g_bArenaUseTeamSpawns[arena_index] ? 1 : 0, g_iArenaRedSpawns[arena_index], g_iArenaBluSpawns[arena_index]);
        }
        return false;
    }

    bool isRedTeam = IsClientRedSpawnSide(client, arena_index);
    int spawnCount = isRedTeam ? g_iArenaRedSpawns[arena_index] : g_iArenaBluSpawns[arena_index];
    if (spawnCount <= 0)
    {
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] team_spawns skip client=%N arena=%d side=%s spawn_count=%d",
                client, arena_index, isRedTeam ? "RED" : "BLU", spawnCount);
        }
        return false;
    }

    int teammateSpawn = FindAliveTeammateTeamSpawnPoint(client, arena_index, isRedTeam);
    bool useNearSpawn = g_bArenaNearSpawn[arena_index] && !g_bArenaNoFight[arena_index];
    int spawnIndex = SelectTeamSpawnForPlayer(arena_index, isRedTeam, useNearSpawn, teammateSpawn);
    if (spawnIndex <= 0 || spawnIndex > spawnCount)
        spawnIndex = 1;

    float pos[3];
    if (isRedTeam)
    {
        pos[0] = g_fArenaRedSpawnOrigin[arena_index][spawnIndex][0];
        pos[1] = g_fArenaRedSpawnOrigin[arena_index][spawnIndex][1];
        pos[2] = g_fArenaRedSpawnOrigin[arena_index][spawnIndex][2];
        TeleportEntity(client, g_fArenaRedSpawnOrigin[arena_index][spawnIndex], g_fArenaRedSpawnAngles[arena_index][spawnIndex], vel);
    }
    else
    {
        pos[0] = g_fArenaBluSpawnOrigin[arena_index][spawnIndex][0];
        pos[1] = g_fArenaBluSpawnOrigin[arena_index][spawnIndex][1];
        pos[2] = g_fArenaBluSpawnOrigin[arena_index][spawnIndex][2];
        TeleportEntity(client, g_fArenaBluSpawnOrigin[arena_index][spawnIndex], g_fArenaBluSpawnAngles[arena_index][spawnIndex], vel);
    }

    EmitAmbientSound("items/spawn_item.wav", pos, _, SNDLEVEL_NORMAL, _, 1.0);
    UpdateHud(client);
    if (g_bDebugTeleport)
    {
        LogMessage("[MGE tele][debug] team_spawns apply client=%N arena=%d side=%s spawn=%d near=%d teammate_spawn=%d",
            client, arena_index, isRedTeam ? "RED" : "BLU", spawnIndex, useNearSpawn ? 1 : 0, teammateSpawn);
    }
    return true;
}

// Handles player teleportation to appropriate spawn points based on arena type
Action Timer_Tele(Handle timer, int userid)
{
    #pragma unused timer
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client))
    {
        if (g_bDebugTeleport)
            LogMessage("[MGE tele][debug] Timer_Tele skip: invalid client userid=%d", userid);
        return Plugin_Continue;
    }

    int arena_index = g_iPlayerArena[client];

    if (!arena_index)
    {
        if (g_bDebugTeleport)
            LogMessage("[MGE tele][debug] Timer_Tele skip: no arena client=%N", client);
        return Plugin_Continue;
    }

    int player_slot = g_iPlayerSlot[client];
    if (!g_bArenaNoFight[arena_index] && ((!g_bFourPersonArena[arena_index] && player_slot > SLOT_TWO) || (g_bFourPersonArena[arena_index] && player_slot > SLOT_FOUR)))
    {
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] Timer_Tele skip: inactive slot client=%N arena=%d slot=%d four=%d nofight=%d",
                client, arena_index, player_slot, g_bFourPersonArena[arena_index] ? 1 : 0, g_bArenaNoFight[arena_index] ? 1 : 0);
        }
        return Plugin_Continue;
    }

    float vel[3] =  { 0.0, 0.0, 0.0 };

    // CHECK FOR MANNTREADS IN ENDIF
    if (g_bArenaEndif[arena_index])
    {
        // Loop thru client's wearable entities. not adding gamedata for this shiz
        int i = -1;
        while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
        {
            if (client != GetEntPropEnt(i, Prop_Send, "m_hOwnerEntity"))
            {
                continue;
            }
            int itemdef = GetEntProp(i, Prop_Send, "m_iItemDefinitionIndex");
            // Manntreads itemdef
            if (itemdef == 444)
            {
                // Just in case.
                RemoveEntity(i);
                MC_PrintToChat(client, "%t", "EndIfManntreadsRemoval");
                // Run elo calc so clients can't be cheeky if they're losing
                RemoveFromQueue(client, true);
            }
        }
    }


    // If arena defines team-specific spawns, always use them for every spawn cycle.
    if (TeleportToConfiguredTeamSpawn(client, arena_index, vel))
    {
        if (g_bDebugTeleport)
            LogMessage("[MGE tele][debug] Timer_Tele path=team_spawns client=%N arena=%d", client, arena_index);
        return Plugin_Continue;
    }

    // BBall and 2v2 arenas handle spawns differently, each team, has their own spawns.
    if (g_bArenaBBall[arena_index])
    {
        bool hasCustomBballNodes =
            g_bArenaBBallIntelSpawnSet[arena_index] ||
            g_bArenaBBallIntelSpawnRedSet[arena_index] ||
            g_bArenaBBallIntelSpawnBluSet[arena_index] ||
            g_bArenaBBallHoopSpawnSet[arena_index] ||
            g_bArenaBBallHoopSpawnRedSet[arena_index] ||
            g_bArenaBBallHoopSpawnBluSet[arena_index];

        int playerSpawnCount = g_iArenaSpawns[arena_index];
        if (!hasCustomBballNodes)
        {
            // Legacy BBall layout: last 5 points are hoop/intel helpers.
            playerSpawnCount = g_iArenaSpawns[arena_index] - 5;
        }

        // If map has only a few points (e.g. 2), use them directly for players.
        if (playerSpawnCount < 2)
            playerSpawnCount = g_iArenaSpawns[arena_index];
        if (playerSpawnCount < 1)
            playerSpawnCount = 1;

        int split = (playerSpawnCount / 2);
        if (split < 1)
            split = 1;

        int random_int;
        int offset_high, offset_low;
        if (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE)
        {
            offset_low = 1;
            offset_high = split;
            random_int = GetRandomInt(offset_low, offset_high); // RED side
        } else {
            offset_low = split + 1;
            offset_high = playerSpawnCount;
            if (offset_low > offset_high)
                offset_low = offset_high;
            random_int = GetRandomInt(offset_low, offset_high); // BLU side
        }

        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] Timer_Tele path=bball client=%N arena=%d spawn=%d range=[%d..%d] total=%d split=%d",
                client, arena_index, random_int, offset_low, offset_high, playerSpawnCount, split);
        }
        return Plugin_Continue;
    }
    else if (g_bArenaKoth[arena_index])
    {
        int random_int;
        int offset_high, offset_low;
        if (g_iPlayerSlot[client] == SLOT_ONE || g_iPlayerSlot[client] == SLOT_THREE)
        {
            offset_high = ((g_iArenaSpawns[arena_index] - 1) / 2);
            random_int = GetRandomInt(1, offset_high); // The first half of the player spawns are for slot one and three.
        } else {
            offset_high = (g_iArenaSpawns[arena_index] - 1);
            offset_low = (((g_iArenaSpawns[arena_index] + 1) / 2));
            random_int = GetRandomInt(offset_low, offset_high); // The last spawn is for the point
        }

        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] Timer_Tele path=koth client=%N arena=%d spawn=%d range=[%d..%d]",
                client, arena_index, random_int, offset_low, offset_high);
        }
        return Plugin_Continue;
    }
    else if (g_bFourPersonArena[arena_index])
    {
        int random_int;
        int offset_high, offset_low;
        bool is_red_team = IsClientRedSpawnSide(client, arena_index);

        if (is_red_team)
        {
            offset_high = ((g_iArenaSpawns[arena_index]) / 2);
            offset_low = 1;
        } else {
            offset_high = (g_iArenaSpawns[arena_index]);
            offset_low = (((g_iArenaSpawns[arena_index]) / 2) + 1);
        }

        // Get teammate and check if they're using a spawn point
        int teammate = GetPlayerTeammate(g_iPlayerSlot[client], arena_index);
        int teammate_spawn = -1;
        if (IsValidClient(teammate) && IsPlayerAlive(teammate)) {
            teammate_spawn = GetPlayerCurrentSpawnPoint(teammate, arena_index);
        }

        // Pick random spawn from team's pool, avoiding teammate's spawn
        int attempts = 0;
        do {
            random_int = GetRandomInt(offset_low, offset_high);
            attempts++;
        } while (random_int == teammate_spawn && attempts < 50); // Prevent infinite loop

        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] Timer_Tele path=2v2_legacy client=%N arena=%d spawn=%d range=[%d..%d] team=%d teammate_spawn=%d",
                client, arena_index, random_int, offset_low, offset_high, is_red_team ? TEAM_RED : TEAM_BLU, teammate_spawn);
        }
        return Plugin_Continue;
    }

    // Create an array that can hold all the arena's spawns.
    int[] RandomSpawn = new int[g_iArenaSpawns[arena_index] + 1];

    // Fill the array with the spawns.
    for (int i = 0; i < g_iArenaSpawns[arena_index]; i++)
    RandomSpawn[i] = i + 1;

    // Shuffle them into a random order.
    SortIntegers(RandomSpawn, g_iArenaSpawns[arena_index], Sort_Random);

    // Now when the array is gone through sequentially, it will still provide a random spawn.
    float besteffort_dist;
    int besteffort_spawn;
    for (int i = 0; i < g_iArenaSpawns[arena_index]; i++)
    {
        int client_slot = g_iPlayerSlot[client];
        int foe_slot = (client_slot == SLOT_ONE || client_slot == SLOT_THREE) ? SLOT_TWO : SLOT_ONE;
        if (foe_slot)
        {
            float distance;
            int foe = g_iArenaQueue[arena_index][foe_slot];
            if (IsValidClient(foe))
            {
                float foe_pos[3];
                GetClientAbsOrigin(foe, foe_pos);
                distance = GetVectorDistance(foe_pos, g_fArenaSpawnOrigin[arena_index][RandomSpawn[i]]);
                if (distance > g_fArenaMinSpawnDist[arena_index])
                {
                    TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][RandomSpawn[i]], g_fArenaSpawnAngles[arena_index][RandomSpawn[i]], vel);
                    EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][RandomSpawn[i]], _, SNDLEVEL_NORMAL, _, 1.0);
                    UpdateHud(client);
                    if (g_bDebugTeleport)
                    {
                        LogMessage("[MGE tele][debug] Timer_Tele path=random_dist_ok client=%N arena=%d spawn=%d distance=%.1f min=%.1f foe=%N",
                            client, arena_index, RandomSpawn[i], distance, g_fArenaMinSpawnDist[arena_index], foe);
                    }
                    return Plugin_Continue;
                } else if (distance > besteffort_dist) {
                    besteffort_dist = distance;
                    besteffort_spawn = RandomSpawn[i];
                }
            }
        }
    }

    if (besteffort_spawn)
    {
        // Couldn't find a spawn that was far enough away, so use the one that was the farthest.
        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][besteffort_spawn], g_fArenaSpawnAngles[arena_index][besteffort_spawn], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][besteffort_spawn], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] Timer_Tele path=random_best_effort client=%N arena=%d spawn=%d distance=%.1f min=%.1f",
                client, arena_index, besteffort_spawn, besteffort_dist, g_fArenaMinSpawnDist[arena_index]);
        }
        return Plugin_Continue;
    } else {
        // No foe, so just pick a random spawn.
        int random_int = GetRandomInt(1, g_iArenaSpawns[arena_index]);
        TeleportEntity(client, g_fArenaSpawnOrigin[arena_index][random_int], g_fArenaSpawnAngles[arena_index][random_int], vel);
        EmitAmbientSound("items/spawn_item.wav", g_fArenaSpawnOrigin[arena_index][random_int], _, SNDLEVEL_NORMAL, _, 1.0);
        UpdateHud(client);
        if (g_bDebugTeleport)
        {
            LogMessage("[MGE tele][debug] Timer_Tele path=random_no_foe client=%N arena=%d spawn=%d total=%d",
                client, arena_index, random_int, g_iArenaSpawns[arena_index]);
        }
        return Plugin_Continue;
    }
}

// Timer callback to reset player state after respawn delay
Action Timer_ResetPlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (IsValidClient(client))
    {
        ResetPlayer(client);
    }
    
    return Plugin_Continue;
}


// ===== CALCULATION AND ANALYSIS =====

// Calculates player's height above ground for airshot detection
float DistanceAboveGround(int victim)
{
    float vStart[3];
    float vEnd[3];
    float vAngles[3] =  { 90.0, 0.0, 0.0 };
    GetClientAbsOrigin(victim, vStart);
    Handle trace = TR_TraceRayFilterEx(vStart, vAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilterPlayer);

    float distance = -1.0;
    if (TR_DidHit(trace))
    {
        TR_GetEndPosition(vEnd, trace);
        distance = GetVectorDistance(vStart, vEnd, false);
    } else {
        LogError("trace error. victim %N(%d)", victim, victim);
    }

    delete trace;
    return distance;
}

// Calculates minimum ground distance around player for drop detection
float DistanceAboveGroundAroundPlayer(int client)
{
    static const float SAMPLE_OFFSET = 10.0;
    static const float INVALID_DISTANCE = -1.0;
    
    float playerPos[3];
    GetClientAbsOrigin(client, playerPos);
    
    // Define sample positions: center and 4 cardinal directions
    float samplePositions[5][3];
    samplePositions[0] = playerPos;                                    // Center
    samplePositions[1] = playerPos; samplePositions[1][0] += SAMPLE_OFFSET; // +X
    samplePositions[2] = playerPos; samplePositions[2][0] -= SAMPLE_OFFSET; // -X
    samplePositions[3] = playerPos; samplePositions[3][1] += SAMPLE_OFFSET; // +Y
    samplePositions[4] = playerPos; samplePositions[4][1] -= SAMPLE_OFFSET; // -Y
    
    float minDistance = INVALID_DISTANCE;
    float vEnd[3];
    float vAngles[3] = { 90.0, 0.0, 0.0 };
    
    for (int i = 0; i < sizeof(samplePositions); i++)
    {
        Handle trace = TR_TraceRayFilterEx(samplePositions[i], vAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceEntityFilterPlayer);
        
        if (TR_DidHit(trace))
        {
            TR_GetEndPosition(vEnd, trace);
            float distance = GetVectorDistance(samplePositions[i], vEnd, false);
            
            if (minDistance == INVALID_DISTANCE || distance < minDistance)
            {
                minDistance = distance;
            }
        }
        else
        {
            LogError("Ground trace failed for client %N(%d) at position [%.1f, %.1f, %.1f]", 
                     client, client, samplePositions[i][0], samplePositions[i][1], samplePositions[i][2]);
        }
        
        delete trace;
    }
    
    return minDistance;
}

// Determines which spawn point a player is currently closest to
int GetPlayerCurrentSpawnPoint(int client, int arena_index)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return -1;
    
    float client_pos[3];
    GetClientAbsOrigin(client, client_pos);
    
    // Find the closest spawn point to the player's current position
    int closest_spawn = -1;
    float closest_distance = 999999.0;
    
    for (int i = 1; i <= g_iArenaSpawns[arena_index]; i++)
    {
        float distance = GetVectorDistance(client_pos, g_fArenaSpawnOrigin[arena_index][i]);
        if (distance < closest_distance)
        {
            closest_distance = distance;
            closest_spawn = i;
        }
    }
    
    // Only return the spawn if the player is very close to it (within 100 units)
    if (closest_distance < 100.0)
        return closest_spawn;
    
    return -1;
}

int GetPlayerCurrentTeamSpawnPoint(int client, int arena_index, bool isRedTeam)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return -1;

    int spawnCount = isRedTeam ? g_iArenaRedSpawns[arena_index] : g_iArenaBluSpawns[arena_index];
    if (spawnCount <= 0)
        return -1;

    float client_pos[3];
    GetClientAbsOrigin(client, client_pos);

    int closest_spawn = -1;
    float closest_distance = 999999.0;

    for (int i = 1; i <= spawnCount; i++)
    {
        float distance;
        if (isRedTeam)
            distance = GetVectorDistance(client_pos, g_fArenaRedSpawnOrigin[arena_index][i]);
        else
            distance = GetVectorDistance(client_pos, g_fArenaBluSpawnOrigin[arena_index][i]);

        if (distance < closest_distance)
        {
            closest_distance = distance;
            closest_spawn = i;
        }
    }

    if (closest_distance < 100.0)
        return closest_spawn;

    return -1;
}

int FindClosestTeamSpawnIndexToPosition(int arena_index, bool isRedTeam, float targetPos[3], int avoidSpawn)
{
    int spawnCount = isRedTeam ? g_iArenaRedSpawns[arena_index] : g_iArenaBluSpawns[arena_index];
    if (spawnCount <= 0)
        return -1;

    int bestIndex = -1;
    float bestDistance = 99999999.0;

    for (int i = 1; i <= spawnCount; i++)
    {
        if (i == avoidSpawn)
            continue;

        float distance;
        if (isRedTeam)
            distance = GetVectorDistance(targetPos, g_fArenaRedSpawnOrigin[arena_index][i]);
        else
            distance = GetVectorDistance(targetPos, g_fArenaBluSpawnOrigin[arena_index][i]);

        if (distance < bestDistance)
        {
            bestDistance = distance;
            bestIndex = i;
        }
    }

    if (bestIndex != -1)
        return bestIndex;

    if (avoidSpawn != -1)
    {
        // Fallback: allow teammate spawn if no alternatives exist.
        for (int i = 1; i <= spawnCount; i++)
        {
            float distance;
            if (isRedTeam)
                distance = GetVectorDistance(targetPos, g_fArenaRedSpawnOrigin[arena_index][i]);
            else
                distance = GetVectorDistance(targetPos, g_fArenaBluSpawnOrigin[arena_index][i]);

            if (distance < bestDistance)
            {
                bestDistance = distance;
                bestIndex = i;
            }
        }
    }

    return bestIndex;
}

int SelectTeamSpawnForPlayer(int arena_index, bool isRedTeam, bool nearSpawn, int teammateSpawn)
{
    int spawnCount = isRedTeam ? g_iArenaRedSpawns[arena_index] : g_iArenaBluSpawns[arena_index];
    if (spawnCount <= 0)
        return -1;

    if (nearSpawn)
    {
        int opponentPrimary = isRedTeam ? g_iArenaQueue[arena_index][SLOT_TWO] : g_iArenaQueue[arena_index][SLOT_ONE];
        int opponentSecondary = isRedTeam ? g_iArenaQueue[arena_index][SLOT_FOUR] : g_iArenaQueue[arena_index][SLOT_THREE];
        int opponent = 0;

        if (IsValidClient(opponentPrimary) && g_iPlayerArena[opponentPrimary] == arena_index)
            opponent = opponentPrimary;
        else if (IsValidClient(opponentSecondary) && g_iPlayerArena[opponentSecondary] == arena_index)
            opponent = opponentSecondary;

        if (opponent != 0)
        {
            float opponentPos[3];
            GetClientAbsOrigin(opponent, opponentPos);
            int closest = FindClosestTeamSpawnIndexToPosition(arena_index, isRedTeam, opponentPos, teammateSpawn);
            if (closest != -1)
                return closest;
        }
    }

    if (spawnCount == 1)
        return 1;

    int randomIndex = 1;
    int attempts = 0;
    do
    {
        randomIndex = GetRandomInt(1, spawnCount);
        attempts++;
    }
    while (randomIndex == teammateSpawn && attempts < 30);

    return randomIndex;
}

// Filter function for ray tracing to exclude player entities
bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
    return entity > MaxClients || !entity;
}

// Formats player class information for database storage and display
void GetPlayerClassString(int client, int arena_index, char[] buffer, int maxlen)
{
    if (g_bArenaClassChange[arena_index] && g_alPlayerDuelClasses[client] != null && g_alPlayerDuelClasses[client].Length > 0)
    {
        // Build comma-separated list of all classes used
        buffer[0] = '\0';
        for (int i = 0; i < g_alPlayerDuelClasses[client].Length; i++)
        {
            char className[16];
            strcopy(className, sizeof(className), TFClassToString(view_as<TFClassType>(g_alPlayerDuelClasses[client].Get(i))));
            
            if (i > 0)
                StrCat(buffer, maxlen, ",");
            StrCat(buffer, maxlen, className);
        }
    }
    else
    {
        // Use single class from duel start
        strcopy(buffer, maxlen, TFClassToString(g_tfctPlayerDuelClass[client]));
    }
}

// Finds the online player with the highest rating
int FindTopRatedOnlinePlayer()
{
    int topPlayer = -1;
    int topRating = -1;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsFakeClient(i) && g_iPlayerRating[i] > 0)
        {
            if (g_iPlayerRating[i] > topRating)
            {
                topRating = g_iPlayerRating[i];
                topPlayer = i;
            }
        }
    }
    
    return topPlayer;
}

// Timer callback to display top rated online player
Action Timer_ShowTopRatedPlayer(Handle timer)
{
    int topPlayer = FindTopRatedOnlinePlayer();
    
    if (topPlayer != -1 && IsValidClient(topPlayer))
    {
        char playerName[MAX_NAME_LENGTH];
        GetClientName(topPlayer, playerName, sizeof(playerName));
        MC_PrintToChatAll("%t", "TopRatedOnlinePlayer", playerName, g_iPlayerRating[topPlayer]);
    }
    
    return Plugin_Continue;
}
