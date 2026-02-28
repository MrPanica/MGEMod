// ===== CLIENT MANAGEMENT =====

// Initialize and reset ammo tracking data for a client when they connect or change arenas
void ResetClientAmmoCounts(int client)
{
    // Crutch.
    g_iPlayerClip[client][SLOT_ONE] = -1;
    g_iPlayerClip[client][SLOT_TWO] = -1;

    // Check how much ammo each gun can hold in its clip and store it in a global variable so it can be set to that amount later.
    if (IsValidEntity(GetPlayerWeaponSlot(client, 0)))
        g_iPlayerClip[client][SLOT_ONE] = GetEntProp(GetPlayerWeaponSlot(client, 0), Prop_Data, "m_iClip1");
    if (IsValidEntity(GetPlayerWeaponSlot(client, 1)))
        g_iPlayerClip[client][SLOT_TWO] = GetEntProp(GetPlayerWeaponSlot(client, 1), Prop_Data, "m_iClip1");
}


// ===== GAME MECHANICS =====

// Continuously manage health values in ammomod arenas to prevent one-shot kills
void ProcessAmmomodHealthManagement()
{
    for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
    {
        if (g_iArenaStatus[arena_index] != AS_FIGHT)
            continue;

        if (g_bArenaBBall[arena_index] || g_bArenaMGE[arena_index] || g_bArenaKoth[arena_index])
            continue;

        int max_slot = g_bFourPersonArena[arena_index] ? SLOT_FOUR : SLOT_TWO;
        for (int slot = SLOT_ONE; slot <= max_slot; slot++)
        {
            int client = g_iArenaQueue[arena_index][slot];
            if (!IsValidClient(client) || !IsPlayerAlive(client))
                continue;

            /*  This is a hack that prevents people from getting one-shot by things
                like the direct hit in the Ammomod arenas. */
            int replacement_hp = (g_iPlayerMaxHP[client] + 512);
            SetEntProp(client, Prop_Send, "m_iHealth", replacement_hp, 1);
        }
    }
}


// ===== TIMER CALLBACKS =====

// Restore saved ammunition counts to player weapons after a brief delay
Action Timer_GiveAmmo(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!client || !IsValidEntity(client))
        return Plugin_Continue;

    g_bPlayerRestoringAmmo[client] = false;

    int weapon;

    if (g_iPlayerClip[client][SLOT_ONE] != -1)
    {
        weapon = GetPlayerWeaponSlot(client, 0);

        if (IsValidEntity(weapon))
            SetEntProp(weapon, Prop_Send, "m_iClip1", g_iPlayerClip[client][SLOT_ONE]);
    }

    if (g_iPlayerClip[client][SLOT_TWO] != -1)
    {
        weapon = GetPlayerWeaponSlot(client, 1);

        if (IsValidEntity(weapon))
            SetEntProp(weapon, Prop_Send, "m_iClip1", g_iPlayerClip[client][SLOT_TWO]);
    }

    return Plugin_Continue;
}
