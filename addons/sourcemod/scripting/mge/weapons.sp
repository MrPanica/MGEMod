// ===== WEAPON RULES SYSTEM =====
//
// Shared rules file path:
//   addons/sourcemod/configs/mge/weapon_configs.cfg
//
// Arena keys:
//   "Weapon Config" "Profile A, Profile B"
//   "Weapon Block Indexes" "4, 5, 7"
//   "Weapon Whitelist Indexes" "30, 735"
//   "Weapon Block Class Names" "tf_weapon_invis, tf_weapon_builder"
//   "Weapon Whitelist Class Names" "tf_weapon_shotgun_primary"

#define MAX_WEAPON_PROFILES 128
#define MAX_WEAPON_PROFILE_NAME 96
#define MAX_WEAPON_RULE_DESC 192
#define MAX_WEAPON_CONFIG_LIST 256
#define MAX_WEAPON_CLASS_TOKEN 96
#define MAX_WEAPON_CSV_PARTS 64
#define WEAPON_CONFIG_DEFAULT "General Weapon Block"

enum WeaponRuleType
{
    WR_None = 0,
    WR_Block,
    WR_Replace
}

// TF2Items natives (declared locally so we don't require tf2items.inc at compile-time).
native Handle TF2Items_CreateItem(int flags = 0);
native void TF2Items_SetClassname(Handle item, const char[] classname);
native void TF2Items_SetItemIndex(Handle item, int itemdef);
native void TF2Items_SetLevel(Handle item, int level);
native void TF2Items_SetQuality(Handle item, int quality);
native void TF2Items_SetNumAttributes(Handle item, int num);
native int TF2Items_GiveNamedItem(int client, Handle item);

#define TF2ITEMS_OVERRIDE_CLASSNAME (1 << 0)
#define TF2ITEMS_OVERRIDE_ITEM_DEF  (1 << 1)
#define TF2ITEMS_OVERRIDE_ITEM_LEVEL (1 << 2)
#define TF2ITEMS_OVERRIDE_ITEM_QUALITY (1 << 3)
#define TF2ITEMS_OVERRIDE_ATTRIBUTES (1 << 4)
#define TF2ITEMS_PRESERVE_ATTRIBUTES (1 << 5)
#define TF2ITEMS_FORCE_GENERATION (1 << 6)

StringMap g_smWeaponProfileByName;
char g_sWeaponProfileName[MAX_WEAPON_PROFILES][MAX_WEAPON_PROFILE_NAME];
StringMap g_smWeaponProfileIndexRules[MAX_WEAPON_PROFILES];
StringMap g_smWeaponProfileClassRules[MAX_WEAPON_PROFILES];
int g_iWeaponProfileIndexRuleCount[MAX_WEAPON_PROFILES];
int g_iWeaponProfileClassRuleCount[MAX_WEAPON_PROFILES];
int g_iWeaponProfileCount;

ArrayList g_alArenaWeaponProfiles[MAXARENAS + 1];
StringMap g_smArenaWeaponWhitelist[MAXARENAS + 1];
StringMap g_smArenaWeaponForceBlock[MAXARENAS + 1];
StringMap g_smArenaWeaponClassWhitelist[MAXARENAS + 1];
StringMap g_smArenaWeaponClassForceBlock[MAXARENAS + 1];

bool g_bApplyingWeaponRules[MAXPLAYERS + 1];

void InitWeaponRuleSystem()
{
    if (g_smWeaponProfileByName == null)
        g_smWeaponProfileByName = new StringMap();

    g_iWeaponProfileCount = 0;

    for (int i = 0; i < MAX_WEAPON_PROFILES; i++)
    {
        g_sWeaponProfileName[i][0] = '\0';
        g_smWeaponProfileIndexRules[i] = null;
        g_smWeaponProfileClassRules[i] = null;
        g_iWeaponProfileIndexRuleCount[i] = 0;
        g_iWeaponProfileClassRuleCount[i] = 0;
    }

    for (int arena = 0; arena <= MAXARENAS; arena++)
    {
        g_alArenaWeaponProfiles[arena] = null;
        g_smArenaWeaponWhitelist[arena] = null;
        g_smArenaWeaponForceBlock[arena] = null;
        g_smArenaWeaponClassWhitelist[arena] = null;
        g_smArenaWeaponClassForceBlock[arena] = null;
    }
}

void CleanupWeaponRuleSystem()
{
    delete g_smWeaponProfileByName;
    g_smWeaponProfileByName = null;

    for (int i = 0; i < MAX_WEAPON_PROFILES; i++)
    {
        delete g_smWeaponProfileIndexRules[i];
        delete g_smWeaponProfileClassRules[i];
        g_smWeaponProfileIndexRules[i] = null;
        g_smWeaponProfileClassRules[i] = null;
        g_sWeaponProfileName[i][0] = '\0';
        g_iWeaponProfileIndexRuleCount[i] = 0;
        g_iWeaponProfileClassRuleCount[i] = 0;
    }

    for (int arena = 0; arena <= MAXARENAS; arena++)
    {
        delete g_alArenaWeaponProfiles[arena];
        delete g_smArenaWeaponWhitelist[arena];
        delete g_smArenaWeaponForceBlock[arena];
        delete g_smArenaWeaponClassWhitelist[arena];
        delete g_smArenaWeaponClassForceBlock[arena];
        g_alArenaWeaponProfiles[arena] = null;
        g_smArenaWeaponWhitelist[arena] = null;
        g_smArenaWeaponForceBlock[arena] = null;
        g_smArenaWeaponClassWhitelist[arena] = null;
        g_smArenaWeaponClassForceBlock[arena] = null;
    }

    g_iWeaponProfileCount = 0;
}

void ResetWeaponRuleProfiles()
{
    if (g_smWeaponProfileByName == null)
        g_smWeaponProfileByName = new StringMap();
    else
        g_smWeaponProfileByName.Clear();

    for (int i = 0; i < MAX_WEAPON_PROFILES; i++)
    {
        delete g_smWeaponProfileIndexRules[i];
        delete g_smWeaponProfileClassRules[i];
        g_smWeaponProfileIndexRules[i] = null;
        g_smWeaponProfileClassRules[i] = null;
        g_sWeaponProfileName[i][0] = '\0';
        g_iWeaponProfileIndexRuleCount[i] = 0;
        g_iWeaponProfileClassRuleCount[i] = 0;
    }

    g_iWeaponProfileCount = 0;
}

void ResetArenaWeaponRuleBindings()
{
    for (int arena = 0; arena <= MAXARENAS; arena++)
    {
        delete g_alArenaWeaponProfiles[arena];
        delete g_smArenaWeaponWhitelist[arena];
        delete g_smArenaWeaponForceBlock[arena];
        delete g_smArenaWeaponClassWhitelist[arena];
        delete g_smArenaWeaponClassForceBlock[arena];

        g_alArenaWeaponProfiles[arena] = new ArrayList();
        g_smArenaWeaponWhitelist[arena] = new StringMap();
        g_smArenaWeaponForceBlock[arena] = new StringMap();
        g_smArenaWeaponClassWhitelist[arena] = new StringMap();
        g_smArenaWeaponClassForceBlock[arena] = new StringMap();
    }
}

bool IsTF2ItemsAvailable()
{
    return (GetFeatureStatus(FeatureType_Native, "TF2Items_CreateItem") == FeatureStatus_Available &&
            GetFeatureStatus(FeatureType_Native, "TF2Items_SetItemIndex") == FeatureStatus_Available &&
            GetFeatureStatus(FeatureType_Native, "TF2Items_GiveNamedItem") == FeatureStatus_Available);
}

void ToUpperInPlace(char[] text)
{
    for (int i = 0; text[i] != '\0'; i++)
        text[i] = CharToUpper(text[i]);
}

void ToLowerInPlace(char[] text)
{
    for (int i = 0; text[i] != '\0'; i++)
        text[i] = CharToLower(text[i]);
}

void NormalizeProfileLookupKey(const char[] input, char[] output, int size)
{
    strcopy(output, size, input);
    TrimString(output);
    ToLowerInPlace(output);
}

void NormalizeWeaponClassRuleKey(const char[] input, char[] output, int size)
{
    strcopy(output, size, input);
    TrimString(output);
    ToUpperInPlace(output);
}

void BuildItemIndexKey(int itemdef, char[] key, int size)
{
    IntToString(itemdef, key, size);
}

void GetKvStringAny(KeyValues kv, char[] output, int size, const char[] key1, const char[] key2 = "", const char[] key3 = "", const char[] key4 = "", const char[] fallback = "")
{
    output[0] = '\0';
    kv.GetString(key1, output, size, "");
    if (output[0] == '\0' && key2[0] != '\0')
        kv.GetString(key2, output, size, "");
    if (output[0] == '\0' && key3[0] != '\0')
        kv.GetString(key3, output, size, "");
    if (output[0] == '\0' && key4[0] != '\0')
        kv.GetString(key4, output, size, "");
    if (output[0] == '\0')
        strcopy(output, size, fallback);
}

void ParseCsvIntSet(const char[] csv, StringMap target)
{
    if (target == null)
        return;

    char values[MAX_WEAPON_CSV_PARTS][24];
    int count = ExplodeString(csv, ",", values, sizeof(values), sizeof(values[]));

    for (int i = 0; i < count; i++)
    {
        TrimString(values[i]);
        if (values[i][0] == '\0')
            continue;

        int itemdef = StringToInt(values[i]);
        if (itemdef <= 0)
            continue;

        char itemKey[16];
        BuildItemIndexKey(itemdef, itemKey, sizeof(itemKey));
        target.SetValue(itemKey, 1, true);
    }
}

void ParseCsvClassSet(const char[] csv, StringMap target)
{
    if (target == null)
        return;

    char values[MAX_WEAPON_CSV_PARTS][MAX_WEAPON_CLASS_TOKEN];
    int count = ExplodeString(csv, ",", values, sizeof(values), sizeof(values[]));

    for (int i = 0; i < count; i++)
    {
        TrimString(values[i]);
        if (values[i][0] == '\0')
            continue;

        char classKey[MAX_WEAPON_CLASS_TOKEN];
        NormalizeWeaponClassRuleKey(values[i], classKey, sizeof(classKey));
        if (classKey[0] == '\0')
            continue;

        target.SetValue(classKey, 1, true);
    }
}

int RegisterWeaponProfile(const char[] profileName)
{
    if (g_iWeaponProfileCount >= MAX_WEAPON_PROFILES)
    {
        LogError("weapon config: too many profiles. Increase MAX_WEAPON_PROFILES.");
        return -1;
    }

    int id = g_iWeaponProfileCount;
    g_iWeaponProfileCount++;

    strcopy(g_sWeaponProfileName[id], sizeof(g_sWeaponProfileName[]), profileName);
    g_smWeaponProfileIndexRules[id] = new StringMap();
    g_smWeaponProfileClassRules[id] = new StringMap();

    char lookupKey[MAX_WEAPON_PROFILE_NAME];
    NormalizeProfileLookupKey(profileName, lookupKey, sizeof(lookupKey));
    g_smWeaponProfileByName.SetValue(lookupKey, id, true);

    return id;
}

void EncodeRuleDesc(WeaponRuleType ruleType, int replaceIndex, const char[] replaceClass, char[] output, int size)
{
    Format(output, size, "%d;%d;%s", view_as<int>(ruleType), replaceIndex, replaceClass);
}

bool DecodeRuleDesc(const char[] desc, WeaponRuleType &ruleType, int &replaceIndex, char[] replaceClass, int replaceClassSize)
{
    char parts[3][MAX_WEAPON_CLASS_TOKEN];
    int count = ExplodeString(desc, ";", parts, sizeof(parts), sizeof(parts[]));
    if (count < 2)
        return false;

    ruleType = view_as<WeaponRuleType>(StringToInt(parts[0]));
    replaceIndex = StringToInt(parts[1]);
    replaceClass[0] = '\0';
    if (count >= 3)
    {
        strcopy(replaceClass, replaceClassSize, parts[2]);
        TrimString(replaceClass);
    }
    return true;
}

void ParseProfileRuleEntry(KeyValues kv, int profileId, bool byIndex, const char[] entryName)
{
    char type[16];
    GetKvStringAny(kv, type, sizeof(type), "type", "type\"");
    TrimString(type);

    if (type[0] == '\0')
        return;

    WeaponRuleType ruleType = WR_None;
    if (StrEqual(type, "block", false))
    {
        ruleType = WR_Block;
    }
    else if (StrEqual(type, "replace", false))
    {
        ruleType = WR_Replace;
    }
    else
    {
        LogError("weapon config: profile '%s' has invalid type '%s' on key '%s'", g_sWeaponProfileName[profileId], type, entryName);
        return;
    }

        int replaceIndex = -1;
        char replaceClass[MAX_WEAPON_CLASS_TOKEN];
        replaceClass[0] = '\0';

    if (ruleType == WR_Replace)
    {
        char replaceIndexStr[16];
        GetKvStringAny(kv, replaceIndexStr, sizeof(replaceIndexStr), "replace index", "replace_index", "replace index\"", "replace_index\"");
        if (replaceIndexStr[0] != '\0')
            replaceIndex = StringToInt(replaceIndexStr);

        GetKvStringAny(kv, replaceClass, sizeof(replaceClass), "replace Class Name", "replace class name", "replace_class_name", "replace Class Name\"");
        TrimString(replaceClass);

        if (replaceIndex <= 0 && replaceClass[0] == '\0')
        {
            LogError("weapon config: profile '%s' replace rule on key '%s' has no replacement target", g_sWeaponProfileName[profileId], entryName);
            return;
        }
    }

    char desc[MAX_WEAPON_RULE_DESC];
    EncodeRuleDesc(ruleType, replaceIndex, replaceClass, desc, sizeof(desc));

    if (byIndex)
    {
        int itemdef = StringToInt(entryName);
        if (itemdef <= 0)
        {
            LogError("weapon config: profile '%s' has invalid item index key '%s'", g_sWeaponProfileName[profileId], entryName);
            return;
        }

        char itemKey[16];
        BuildItemIndexKey(itemdef, itemKey, sizeof(itemKey));
        g_smWeaponProfileIndexRules[profileId].SetString(itemKey, desc, true);
        g_iWeaponProfileIndexRuleCount[profileId]++;
    }
    else
    {
        char classKey[MAX_WEAPON_CLASS_TOKEN];
        NormalizeWeaponClassRuleKey(entryName, classKey, sizeof(classKey));
        if (classKey[0] == '\0')
            return;

        g_smWeaponProfileClassRules[profileId].SetString(classKey, desc, true);
        g_iWeaponProfileClassRuleCount[profileId]++;
    }
}

void ParseProfileIndexRules(KeyValues kv, int profileId)
{
    bool jumped = kv.JumpToKey("Index", false);
    if (!jumped)
        jumped = kv.JumpToKey("index", false);
    bool iteratedFallback = false;
    if (!jumped)
    {
        // tolerant fallback: locate section by normalized name
        if (kv.GotoFirstSubKey(false))
        {
            iteratedFallback = true;
            do
            {
                char secName[64];
                kv.GetSectionName(secName, sizeof(secName));
                TrimString(secName);
                ToLowerInPlace(secName);
                if (StrEqual(secName, "index", false))
                {
                    jumped = true;
                    break;
                }
            } while (kv.GotoNextKey(false));
        }
    }
    if (!jumped)
    {
        if (iteratedFallback)
            kv.GoBack();
        return;
    }

    if (kv.GotoFirstSubKey())
    {
        do
        {
            char entryName[32];
            kv.GetSectionName(entryName, sizeof(entryName));
            ParseProfileRuleEntry(kv, profileId, true, entryName);
        } while (kv.GotoNextKey());

        kv.GoBack();
    }
    kv.GoBack();
}

void ParseProfileClassRules(KeyValues kv, int profileId)
{
    bool jumped = kv.JumpToKey("Class Name", false);
    if (!jumped)
        jumped = kv.JumpToKey("class name", false);
    if (!jumped)
        jumped = kv.JumpToKey("ClassName", false);
    if (!jumped)
        jumped = kv.JumpToKey("classname", false);
    bool iteratedFallback = false;
    if (!jumped)
    {
        // tolerant fallback: locate section by normalized name
        if (kv.GotoFirstSubKey(false))
        {
            iteratedFallback = true;
            do
            {
                char secName[64];
                kv.GetSectionName(secName, sizeof(secName));
                TrimString(secName);
                ToLowerInPlace(secName);
                ReplaceString(secName, sizeof(secName), " ", "");
                ReplaceString(secName, sizeof(secName), "_", "");
                if (StrEqual(secName, "classname", false))
                {
                    jumped = true;
                    break;
                }
            } while (kv.GotoNextKey(false));
        }
    }
    if (!jumped)
    {
        if (iteratedFallback)
            kv.GoBack();
        return;
    }

    if (kv.GotoFirstSubKey())
    {
        do
        {
            char entryName[MAX_WEAPON_CLASS_TOKEN];
            kv.GetSectionName(entryName, sizeof(entryName));
            ParseProfileRuleEntry(kv, profileId, false, entryName);
        } while (kv.GotoNextKey());

        kv.GoBack();
    }

    kv.GoBack();
}

void ParseRulesFromCurrentSectionDirect(KeyValues kv, int profileId, bool byIndex)
{
    if (!kv.GotoFirstSubKey())
        return;

    do
    {
        char entryName[MAX_WEAPON_CLASS_TOKEN];
        kv.GetSectionName(entryName, sizeof(entryName));
        ParseProfileRuleEntry(kv, profileId, byIndex, entryName);
    } while (kv.GotoNextKey());

    kv.GoBack();
}

void EnsureWeaponConfigTemplateExists()
{
    char cfgDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, cfgDir, sizeof(cfgDir), "configs/mge");
    if (!DirExists(cfgDir))
    {
        if (!CreateDirectory(cfgDir, 511))
        {
            LogError("weapon config: failed to create directory: %s", cfgDir);
            return;
        }
    }

    char cfgPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, cfgPath, sizeof(cfgPath), "configs/mge/weapon_configs.cfg");
    if (FileExists(cfgPath))
        return;

    File f = OpenFile(cfgPath, "w");
    if (f == null)
    {
        LogError("weapon config: failed to create template: %s", cfgPath);
        return;
    }

    WriteFileLine(f, "// =============================================================================");
    WriteFileLine(f, "// MGEMod weapon rules template");
    WriteFileLine(f, "// This file is auto-created if missing.");
    WriteFileLine(f, "// Keep only structure here by default. Uncomment examples and edit as needed.");
    WriteFileLine(f, "// =============================================================================");
    WriteFileLine(f, "");
    WriteFileLine(f, "\"General Weapon Block\"");
    WriteFileLine(f, "{");
    WriteFileLine(f, "    \"Index\"");
    WriteFileLine(f, "    {");
    WriteFileLine(f, "        // \"444\"");
    WriteFileLine(f, "        // {");
    WriteFileLine(f, "        //     \"type\" \"block\"");
    WriteFileLine(f, "        // }");
    WriteFileLine(f, "");
    WriteFileLine(f, "        // \"5\"");
    WriteFileLine(f, "        // {");
    WriteFileLine(f, "        //     \"type\" \"replace\"");
    WriteFileLine(f, "        //     \"replace index\" \"30\"");
    WriteFileLine(f, "        // }");
    WriteFileLine(f, "");
    WriteFileLine(f, "        // \"7\"");
    WriteFileLine(f, "        // {");
    WriteFileLine(f, "        //     \"type\" \"replace\"");
    WriteFileLine(f, "        //     \"replace Class Name\" \"TF_WEAPON_PDA_ENGINEER_BUILD\"");
    WriteFileLine(f, "        // }");
    WriteFileLine(f, "    }");
    WriteFileLine(f, "");
    WriteFileLine(f, "    \"Class Name\"");
    WriteFileLine(f, "    {");
    WriteFileLine(f, "        // \"TF_WEAPON_INVIS\"");
    WriteFileLine(f, "        // {");
    WriteFileLine(f, "        //     \"type\" \"block\"");
    WriteFileLine(f, "        // }");
    WriteFileLine(f, "");
    WriteFileLine(f, "        // \"UPGRADEABLE TF_WEAPON_INVIS\"");
    WriteFileLine(f, "        // {");
    WriteFileLine(f, "        //     \"type\" \"replace\"");
    WriteFileLine(f, "        //     \"replace index\" \"30\"");
    WriteFileLine(f, "        // }");
    WriteFileLine(f, "");
    WriteFileLine(f, "        // \"UPGRADEABLE TF_WEAPON_PDA_ENGINEER_BUILD\"");
    WriteFileLine(f, "        // {");
    WriteFileLine(f, "        //     \"type\" \"replace\"");
    WriteFileLine(f, "        //     \"replace Class Name\" \"TF_WEAPON_PDA_ENGINEER_BUILD\"");
    WriteFileLine(f, "        // }");
    WriteFileLine(f, "    }");
    WriteFileLine(f, "}");
    WriteFileLine(f, "");
    WriteFileLine(f, "// Optional extra profile example:");
    WriteFileLine(f, "// \"Spy Scout Arnae Blocks\"");
    WriteFileLine(f, "// {");
    WriteFileLine(f, "//     \"Index\"");
    WriteFileLine(f, "//     {");
    WriteFileLine(f, "//         \"4\"");
    WriteFileLine(f, "//         {");
    WriteFileLine(f, "//             \"type\" \"block\"");
    WriteFileLine(f, "//         }");
    WriteFileLine(f, "//     }");
    WriteFileLine(f, "// }");

    delete f;
    LogMessage("weapon config: created template %s", cfgPath);
}

bool LoadWeaponRuleProfiles()
{
    ResetWeaponRuleProfiles();

    char cfgPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, cfgPath, sizeof(cfgPath), "configs/mge/weapon_configs.cfg");

    KeyValues kv = new KeyValues("WeaponConfigs");
    if (!kv.ImportFromFile(cfgPath))
    {
        LogMessage("weapon config: shared file not found: %s (weapon rules disabled)", cfgPath);
        delete kv;
        return false;
    }

    if (!kv.GotoFirstSubKey())
    {
        LogError("weapon config: no sections in %s", cfgPath);
        delete kv;
        return false;
    }

    do
    {
        char profileName[MAX_WEAPON_PROFILE_NAME];
        kv.GetSectionName(profileName, sizeof(profileName));
        TrimString(profileName);

        if (profileName[0] == '\0')
            continue;

        int profileId = RegisterWeaponProfile(profileName);
        if (profileId < 0)
            continue;

        ParseProfileIndexRules(kv, profileId);
        ParseProfileClassRules(kv, profileId);

        // Tolerant mode: if broken braces made "Index"/"Class Name" a top-level profile,
        // parse their direct children as rules for that profile.
        char normalizedProfileName[MAX_WEAPON_PROFILE_NAME];
        strcopy(normalizedProfileName, sizeof(normalizedProfileName), profileName);
        TrimString(normalizedProfileName);
        ToLowerInPlace(normalizedProfileName);
        ReplaceString(normalizedProfileName, sizeof(normalizedProfileName), " ", "");
        ReplaceString(normalizedProfileName, sizeof(normalizedProfileName), "_", "");

        if (StrEqual(normalizedProfileName, "index", false))
            ParseRulesFromCurrentSectionDirect(kv, profileId, true);
        else if (StrEqual(normalizedProfileName, "classname", false))
            ParseRulesFromCurrentSectionDirect(kv, profileId, false);

        if (g_bDebugWeaponRules)
        {
            LogMessage("[MGE weapons][debug] profile loaded id=%d name='%s' index_rules=%d class_rules=%d",
                profileId, g_sWeaponProfileName[profileId], g_iWeaponProfileIndexRuleCount[profileId], g_iWeaponProfileClassRuleCount[profileId]);
        }
    } while (kv.GotoNextKey());

    delete kv;

    LogMessage("weapon config: loaded %d profile(s) from configs/mge/weapon_configs.cfg", g_iWeaponProfileCount);
    return (g_iWeaponProfileCount > 0);
}

int FindArenaIndexByOriginalName(const char[] arenaName)
{
    for (int i = 1; i <= g_iArenaCount; i++)
    {
        if (StrEqual(g_sArenaOriginalName[i], arenaName, false))
            return i;
    }
    return 0;
}

bool BuildCurrentMapConfigPath(char[] output, int outputSize)
{
    char mapName[256];
    GetCurrentMap(mapName, sizeof(mapName));

    if (StrContains(mapName, "workshop/", false) != -1)
    {
        char nonWorkshopName[256];
        if (GetMapDisplayName(mapName, nonWorkshopName, sizeof(nonWorkshopName)))
            strcopy(mapName, sizeof(mapName), nonWorkshopName);
    }

    char rel[256];
    Format(rel, sizeof(rel), "configs/mge/%s.cfg", mapName);
    BuildPath(Path_SM, output, outputSize, rel);
    return true;
}

bool ReloadArenaWeaponRuleBindingsFromMapConfig()
{
    ResetArenaWeaponRuleBindings();

    char mapCfgPath[PLATFORM_MAX_PATH];
    BuildCurrentMapConfigPath(mapCfgPath, sizeof(mapCfgPath));

    KeyValues kv = new KeyValues("SpawnConfigs");
    if (!kv.ImportFromFile(mapCfgPath))
    {
        LogError("weapon config: cannot open map cfg for rebinding: %s", mapCfgPath);
        delete kv;
        return false;
    }

    if (!kv.GotoFirstSubKey())
    {
        LogError("weapon config: map cfg has no arenas: %s", mapCfgPath);
        delete kv;
        return false;
    }

    int bound = 0;
    do
    {
        char arenaName[64];
        kv.GetSectionName(arenaName, sizeof(arenaName));

        int arena = FindArenaIndexByOriginalName(arenaName);
        if (arena <= 0 || arena > g_iArenaCount)
            continue;

        ParseArenaWeaponRuleSettings(kv, arena);
        bound++;
    } while (kv.GotoNextKey());

    delete kv;
    LogMessage("weapon config: rebound arena weapon settings for %d arena(s)", bound);
    return true;
}

void ReapplyWeaponRulesToOnlineArenaPlayers()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;
        if (g_iPlayerArena[client] <= 0)
            continue;

        ApplyWeaponRulesAfterInventoryUpdate(client, "weapon_reload");
    }
}

Action Command_MgeWeaponReload(int client, int args)
{
    EnsureWeaponConfigTemplateExists();
    bool loaded = LoadWeaponRuleProfiles();
    bool rebound = ReloadArenaWeaponRuleBindingsFromMapConfig();

    ReapplyWeaponRulesToOnlineArenaPlayers();

    if (client > 0 && IsValidClient(client))
    {
        MC_PrintToChat(client, "[MGE] Weapon config reloaded. profiles=%d loaded=%d rebound=%d",
            g_iWeaponProfileCount, loaded ? 1 : 0, rebound ? 1 : 0);
    }
    else
    {
        PrintToServer("[MGE] Weapon config reloaded. profiles=%d loaded=%d rebound=%d",
            g_iWeaponProfileCount, loaded ? 1 : 0, rebound ? 1 : 0);
    }

    return Plugin_Handled;
}

int ResolveWeaponProfileId(const char[] profileName)
{
    if (g_smWeaponProfileByName == null)
        return -1;

    char lookupKey[MAX_WEAPON_PROFILE_NAME];
    NormalizeProfileLookupKey(profileName, lookupKey, sizeof(lookupKey));
    if (lookupKey[0] == '\0')
        return -1;

    int profileId;
    if (!g_smWeaponProfileByName.GetValue(lookupKey, profileId))
        return -1;

    return profileId;
}

int ResolveDefaultWeaponProfileId()
{
    int defaultId = ResolveWeaponProfileId(WEAPON_CONFIG_DEFAULT);
    if (defaultId >= 0)
        return defaultId;

    if (g_iWeaponProfileCount > 0)
        return 0;

    return -1;
}

void ParseArenaWeaponRuleSettings(KeyValues kv, int arena)
{
    if (arena <= 0 || arena > MAXARENAS)
        return;

    delete g_alArenaWeaponProfiles[arena];
    delete g_smArenaWeaponWhitelist[arena];
    delete g_smArenaWeaponForceBlock[arena];
    delete g_smArenaWeaponClassWhitelist[arena];
    delete g_smArenaWeaponClassForceBlock[arena];
    g_alArenaWeaponProfiles[arena] = new ArrayList();
    g_smArenaWeaponWhitelist[arena] = new StringMap();
    g_smArenaWeaponForceBlock[arena] = new StringMap();
    g_smArenaWeaponClassWhitelist[arena] = new StringMap();
    g_smArenaWeaponClassForceBlock[arena] = new StringMap();

    char profilesCsv[MAX_WEAPON_CONFIG_LIST];
    GetKvStringAny(kv, profilesCsv, sizeof(profilesCsv), "Weapon Config", "weapon config", "weapon_config", "WeaponConfig", WEAPON_CONFIG_DEFAULT);
    TrimString(profilesCsv);
    if (profilesCsv[0] == '\0')
        strcopy(profilesCsv, sizeof(profilesCsv), WEAPON_CONFIG_DEFAULT);

    char profileParts[MAX_WEAPON_CSV_PARTS][MAX_WEAPON_PROFILE_NAME];
    int profileCount = ExplodeString(profilesCsv, ",", profileParts, sizeof(profileParts), sizeof(profileParts[]));
    int boundProfiles = 0;
    for (int i = 0; i < profileCount; i++)
    {
        TrimString(profileParts[i]);
        if (profileParts[i][0] == '\0')
            continue;

        int profileId = ResolveWeaponProfileId(profileParts[i]);
        if (profileId < 0)
        {
            LogMessage("weapon config: arena '%s' references unknown profile '%s'", g_sArenaOriginalName[arena], profileParts[i]);
            continue;
        }

        g_alArenaWeaponProfiles[arena].Push(profileId);
        boundProfiles++;
    }

    if (boundProfiles == 0)
    {
        int defaultId = ResolveDefaultWeaponProfileId();
        if (defaultId >= 0)
            g_alArenaWeaponProfiles[arena].Push(defaultId);
        else if (g_bDebugWeaponRules)
            LogMessage("[MGE weapons][debug] arena=%s: no bound profiles and default '%s' not found (global_profiles=%d)",
                g_sArenaOriginalName[arena], WEAPON_CONFIG_DEFAULT, g_iWeaponProfileCount);
    }

    char blockCsv[256];
    GetKvStringAny(kv, blockCsv, sizeof(blockCsv), "Weapon Block Indexes", "weapon block indexes", "weapon_block_indexes", "WeaponBlockIndexes");
    ParseCsvIntSet(blockCsv, g_smArenaWeaponForceBlock[arena]);

    char whitelistCsv[256];
    GetKvStringAny(kv, whitelistCsv, sizeof(whitelistCsv), "Weapon Whitelist Indexes", "weapon whitelist indexes", "weapon_whitelist_indexes", "WeaponWhitelistIndexes");
    ParseCsvIntSet(whitelistCsv, g_smArenaWeaponWhitelist[arena]);

    char blockClassCsv[512];
    GetKvStringAny(kv, blockClassCsv, sizeof(blockClassCsv), "Weapon Block Class Names", "weapon block class names", "weapon_block_class_names", "WeaponBlockClassNames");
    ParseCsvClassSet(blockClassCsv, g_smArenaWeaponClassForceBlock[arena]);

    char whitelistClassCsv[512];
    GetKvStringAny(kv, whitelistClassCsv, sizeof(whitelistClassCsv), "Weapon Whitelist Class Names", "weapon whitelist class names", "weapon_whitelist_class_names", "WeaponWhitelistClassNames");
    ParseCsvClassSet(whitelistClassCsv, g_smArenaWeaponClassWhitelist[arena]);
}

void EnsureWeaponProfilesReady()
{
    if (g_iWeaponProfileCount > 0)
        return;

    EnsureWeaponConfigTemplateExists();
    bool loaded = LoadWeaponRuleProfiles();
    bool rebound = ReloadArenaWeaponRuleBindingsFromMapConfig();

    if (g_bDebugWeaponRules)
    {
        LogMessage("[MGE weapons][debug] lazy bootstrap profiles loaded=%d rebound=%d global_profiles=%d",
            loaded ? 1 : 0, rebound ? 1 : 0, g_iWeaponProfileCount);
    }
}

bool BuildRuntimeClassAlias(const char[] canonicalUpper, char[] aliasUpper, int aliasSize)
{
    aliasUpper[0] = '\0';

    if (StrEqual(canonicalUpper, "TF_WEAPON_BUILDER", false))
    {
        strcopy(aliasUpper, aliasSize, "TF_WEAPON_PDA_ENGINEER_BUILD");
        return true;
    }

    return false;
}

void ConvertRuleClassToEntityClass(const char[] ruleClass, char[] entityClass, int entityClassSize)
{
    strcopy(entityClass, entityClassSize, ruleClass);
    TrimString(entityClass);

    if (entityClass[0] == '\0')
        return;

    if (StrContains(entityClass, "Upgradeable ", false) == 0)
    {
        char tmp[MAX_WEAPON_CLASS_TOKEN];
        strcopy(tmp, sizeof(tmp), entityClass[12]);
        strcopy(entityClass, entityClassSize, tmp);
    }

    ToLowerInPlace(entityClass);

    if (StrEqual(entityClass, "tf_weapon_pda_engineer_build", false))
    {
        strcopy(entityClass, entityClassSize, "tf_weapon_builder");
    }
}

bool IsArenaItemInSet(StringMap map, int itemdef)
{
    if (map == null || itemdef <= 0)
        return false;

    char itemKey[16];
    BuildItemIndexKey(itemdef, itemKey, sizeof(itemKey));
    int value;
    return map.GetValue(itemKey, value);
}

bool IsStringInSet(StringMap map, const char[] key)
{
    if (map == null || key[0] == '\0')
        return false;

    int value;
    return map.GetValue(key, value);
}

bool IsArenaWeaponClassInSet(StringMap map, int weaponEntity)
{
    if (map == null || !IsValidEntity(weaponEntity))
        return false;

    char entityClass[64];
    GetEntityClassname(weaponEntity, entityClass, sizeof(entityClass));

    char canonicalUpper[MAX_WEAPON_CLASS_TOKEN];
    NormalizeWeaponClassRuleKey(entityClass, canonicalUpper, sizeof(canonicalUpper));
    if (IsStringInSet(map, canonicalUpper))
        return true;

    char upgradableKey[MAX_WEAPON_CLASS_TOKEN];
    Format(upgradableKey, sizeof(upgradableKey), "UPGRADEABLE %s", canonicalUpper);
    if (IsStringInSet(map, upgradableKey))
        return true;

    char aliasUpper[MAX_WEAPON_CLASS_TOKEN];
    if (BuildRuntimeClassAlias(canonicalUpper, aliasUpper, sizeof(aliasUpper)))
    {
        if (IsStringInSet(map, aliasUpper))
            return true;

        Format(upgradableKey, sizeof(upgradableKey), "UPGRADEABLE %s", aliasUpper);
        if (IsStringInSet(map, upgradableKey))
            return true;
    }

    return false;
}

bool GetProfileRuleByIndex(int profileId, int itemdef, char[] ruleDesc, int ruleDescSize)
{
    if (profileId < 0 || profileId >= g_iWeaponProfileCount || g_smWeaponProfileIndexRules[profileId] == null || itemdef <= 0)
        return false;

    char itemKey[16];
    BuildItemIndexKey(itemdef, itemKey, sizeof(itemKey));
    return g_smWeaponProfileIndexRules[profileId].GetString(itemKey, ruleDesc, ruleDescSize);
}

bool GetProfileRuleByClass(int profileId, int weaponEntity, char[] ruleDesc, int ruleDescSize)
{
    if (profileId < 0 || profileId >= g_iWeaponProfileCount || g_smWeaponProfileClassRules[profileId] == null || !IsValidEntity(weaponEntity))
        return false;

    char entityClass[64];
    GetEntityClassname(weaponEntity, entityClass, sizeof(entityClass));

    char canonicalUpper[MAX_WEAPON_CLASS_TOKEN];
    NormalizeWeaponClassRuleKey(entityClass, canonicalUpper, sizeof(canonicalUpper));

    if (g_smWeaponProfileClassRules[profileId].GetString(canonicalUpper, ruleDesc, ruleDescSize))
        return true;

    char upgradableKey[MAX_WEAPON_CLASS_TOKEN];
    Format(upgradableKey, sizeof(upgradableKey), "UPGRADEABLE %s", canonicalUpper);
    if (g_smWeaponProfileClassRules[profileId].GetString(upgradableKey, ruleDesc, ruleDescSize))
        return true;

    char aliasUpper[MAX_WEAPON_CLASS_TOKEN];
    if (BuildRuntimeClassAlias(canonicalUpper, aliasUpper, sizeof(aliasUpper)))
    {
        if (g_smWeaponProfileClassRules[profileId].GetString(aliasUpper, ruleDesc, ruleDescSize))
            return true;

        Format(upgradableKey, sizeof(upgradableKey), "UPGRADEABLE %s", aliasUpper);
        if (g_smWeaponProfileClassRules[profileId].GetString(upgradableKey, ruleDesc, ruleDescSize))
            return true;
    }

    return false;
}

bool ResolveArenaWeaponRule(int arena, int weaponEntity, int itemdef, char[] ruleDesc, int ruleDescSize, int client = 0)
{
    ruleDesc[0] = '\0';

    if (arena <= 0 || arena > MAXARENAS)
        return false;

    if (IsArenaItemInSet(g_smArenaWeaponWhitelist[arena], itemdef))
    {
        if (g_bDebugWeaponRules && IsValidClient(client))
            LogMessage("[MGE weapons][debug] whitelist allow client=%N arena=%s itemdef=%d", client, g_sArenaOriginalName[arena], itemdef);
        return false;
    }

    if (IsArenaWeaponClassInSet(g_smArenaWeaponClassWhitelist[arena], weaponEntity))
    {
        if (g_bDebugWeaponRules && IsValidClient(client))
        {
            char cls[64];
            GetEntityClassname(weaponEntity, cls, sizeof(cls));
            LogMessage("[MGE weapons][debug] class whitelist allow client=%N arena=%s itemdef=%d class=%s", client, g_sArenaOriginalName[arena], itemdef, cls);
        }
        return false;
    }

    if (IsArenaItemInSet(g_smArenaWeaponForceBlock[arena], itemdef))
    {
        EncodeRuleDesc(WR_Block, -1, "", ruleDesc, ruleDescSize);
        if (g_bDebugWeaponRules && IsValidClient(client))
            LogMessage("[MGE weapons][debug] arena forced block client=%N arena=%s itemdef=%d", client, g_sArenaOriginalName[arena], itemdef);
        return true;
    }

    if (IsArenaWeaponClassInSet(g_smArenaWeaponClassForceBlock[arena], weaponEntity))
    {
        EncodeRuleDesc(WR_Block, -1, "", ruleDesc, ruleDescSize);
        if (g_bDebugWeaponRules && IsValidClient(client))
        {
            char cls[64];
            GetEntityClassname(weaponEntity, cls, sizeof(cls));
            LogMessage("[MGE weapons][debug] arena forced class block client=%N arena=%s itemdef=%d class=%s", client, g_sArenaOriginalName[arena], itemdef, cls);
        }
        return true;
    }

    if (g_alArenaWeaponProfiles[arena] == null || g_alArenaWeaponProfiles[arena].Length <= 0)
    {
        int defaultId = ResolveDefaultWeaponProfileId();
        if (defaultId >= 0)
        {
            if (GetProfileRuleByIndex(defaultId, itemdef, ruleDesc, ruleDescSize))
            {
                if (g_bDebugWeaponRules && IsValidClient(client))
                    LogMessage("[MGE weapons][debug] implicit default index match client=%N arena=%s profile=%s itemdef=%d",
                        client, g_sArenaOriginalName[arena], g_sWeaponProfileName[defaultId], itemdef);
                return true;
            }
            if (GetProfileRuleByClass(defaultId, weaponEntity, ruleDesc, ruleDescSize))
            {
                if (g_bDebugWeaponRules && IsValidClient(client))
                {
                    char cls[64];
                    GetEntityClassname(weaponEntity, cls, sizeof(cls));
                    LogMessage("[MGE weapons][debug] implicit default class match client=%N arena=%s profile=%s itemdef=%d class=%s",
                        client, g_sArenaOriginalName[arena], g_sWeaponProfileName[defaultId], itemdef, cls);
                }
                return true;
            }
        }

        if (g_bDebugWeaponRules && IsValidClient(client))
            LogMessage("[MGE weapons][debug] no profiles bound and no implicit default rule client=%N arena=%s itemdef=%d", client, g_sArenaOriginalName[arena], itemdef);
        return false;
    }

    for (int i = 0; i < g_alArenaWeaponProfiles[arena].Length; i++)
    {
        int profileId = g_alArenaWeaponProfiles[arena].Get(i);

        if (GetProfileRuleByIndex(profileId, itemdef, ruleDesc, ruleDescSize))
        {
            if (g_bDebugWeaponRules && IsValidClient(client))
                LogMessage("[MGE weapons][debug] profile index match client=%N arena=%s profile=%s itemdef=%d",
                    client, g_sArenaOriginalName[arena], g_sWeaponProfileName[profileId], itemdef);
            return true;
        }
        if (GetProfileRuleByClass(profileId, weaponEntity, ruleDesc, ruleDescSize))
        {
            if (g_bDebugWeaponRules && IsValidClient(client))
            {
                char cls[64];
                GetEntityClassname(weaponEntity, cls, sizeof(cls));
                LogMessage("[MGE weapons][debug] profile class match client=%N arena=%s profile=%s itemdef=%d class=%s",
                    client, g_sArenaOriginalName[arena], g_sWeaponProfileName[profileId], itemdef, cls);
            }
            return true;
        }
    }

    // Safety fallback: if profile binding is malformed, scan all loaded profiles.
    for (int profileId = 0; profileId < g_iWeaponProfileCount; profileId++)
    {
        if (GetProfileRuleByIndex(profileId, itemdef, ruleDesc, ruleDescSize))
        {
            if (g_bDebugWeaponRules && IsValidClient(client))
                LogMessage("[MGE weapons][debug] fallback-any-profile index match client=%N arena=%s profile=%s itemdef=%d",
                    client, g_sArenaOriginalName[arena], g_sWeaponProfileName[profileId], itemdef);
            return true;
        }
        if (GetProfileRuleByClass(profileId, weaponEntity, ruleDesc, ruleDescSize))
        {
            if (g_bDebugWeaponRules && IsValidClient(client))
            {
                char cls[64];
                GetEntityClassname(weaponEntity, cls, sizeof(cls));
                LogMessage("[MGE weapons][debug] fallback-any-profile class match client=%N arena=%s profile=%s itemdef=%d class=%s",
                    client, g_sArenaOriginalName[arena], g_sWeaponProfileName[profileId], itemdef, cls);
            }
            return true;
        }
    }

    return false;
}

bool GiveReplacementByClass(int client, const char[] replacementClass, int &weaponEntity)
{
    weaponEntity = -1;

    char entityClass[MAX_WEAPON_CLASS_TOKEN];
    ConvertRuleClassToEntityClass(replacementClass, entityClass, sizeof(entityClass));
    if (entityClass[0] == '\0')
        return false;

    int newWeapon = GivePlayerItem(client, entityClass);
    if (!IsValidEntity(newWeapon))
        return false;

    EquipPlayerWeapon(client, newWeapon);
    weaponEntity = newWeapon;
    return true;
}

bool GiveReplacementByIndex(int client, int replacementIndex, const char[] preferredClass, int &weaponEntity)
{
    weaponEntity = -1;

    if (replacementIndex <= 0 || !IsTF2ItemsAvailable())
        return false;

    int flags = TF2ITEMS_OVERRIDE_ITEM_DEF | TF2ITEMS_OVERRIDE_ITEM_LEVEL | TF2ITEMS_OVERRIDE_ITEM_QUALITY | TF2ITEMS_OVERRIDE_ATTRIBUTES | TF2ITEMS_FORCE_GENERATION;
    if (preferredClass[0] != '\0')
        flags |= TF2ITEMS_OVERRIDE_CLASSNAME;

    Handle item = TF2Items_CreateItem(flags);
    if (item == null)
        return false;

    if (preferredClass[0] != '\0')
        TF2Items_SetClassname(item, preferredClass);

    TF2Items_SetItemIndex(item, replacementIndex);
    TF2Items_SetLevel(item, 1);
    TF2Items_SetQuality(item, 6);
    TF2Items_SetNumAttributes(item, 0);

    int newWeapon = TF2Items_GiveNamedItem(client, item);
    delete item;

    if (!IsValidEntity(newWeapon))
        return false;

    EquipPlayerWeapon(client, newWeapon);
    weaponEntity = newWeapon;
    return true;
}

void ApplyWeaponRuleToSlot(int client, int arena, int slot, int weaponEntity, WeaponRuleType ruleType, int replacementIndex, const char[] replacementClass)
{
    if (!IsValidClient(client) || !IsValidEntity(weaponEntity))
        return;

    char oldClass[64];
    GetEntityClassname(weaponEntity, oldClass, sizeof(oldClass));

    int oldItemDef = GetEntProp(weaponEntity, Prop_Send, "m_iItemDefinitionIndex");

    if (ruleType == WR_Block)
    {
        if (g_bDebugWeaponRules)
            LogMessage("[MGE weapons][debug] block client=%N arena=%s slot=%d itemdef=%d class=%s",
                client, g_sArenaOriginalName[arena], slot, oldItemDef, oldClass);
        TF2_RemoveWeaponSlot(client, slot);
        return;
    }

    if (ruleType != WR_Replace)
        return;

    TF2_RemoveWeaponSlot(client, slot);

    int replacementEntity = -1;
    bool replaced = false;

    char preferredClass[64];
    preferredClass[0] = '\0';
    if (replacementClass[0] != '\0')
    {
        ConvertRuleClassToEntityClass(replacementClass, preferredClass, sizeof(preferredClass));
    }
    else
    {
        strcopy(preferredClass, sizeof(preferredClass), oldClass);
    }

    if (replacementIndex > 0)
        replaced = GiveReplacementByIndex(client, replacementIndex, preferredClass, replacementEntity);

    if (!replaced && replacementClass[0] != '\0')
        replaced = GiveReplacementByClass(client, replacementClass, replacementEntity);

    if (!replaced)
    {
        LogMessage("weapon config: replacement failed for %N in arena '%s' (old index=%d, replace index=%d, replace class='%s'). Weapon removed.",
            client, g_sArenaOriginalName[arena], oldItemDef, replacementIndex, replacementClass);
    }
    else if (g_bDebugWeaponRules)
    {
        LogMessage("[MGE weapons][debug] replace client=%N arena=%s slot=%d old_itemdef=%d old_class=%s replace_index=%d replace_class=%s",
            client, g_sArenaOriginalName[arena], slot, oldItemDef, oldClass, replacementIndex, replacementClass);
    }
}

void ApplyArenaWeaponRulesForClient(int client)
{
    if (!IsValidClient(client))
        return;

    EnsureWeaponProfilesReady();

    if (g_bApplyingWeaponRules[client])
    {
        if (g_bDebugWeaponRules)
            LogMessage("[MGE weapons][debug] skip: already applying client=%N", client);
        return;
    }

    int arena = g_iPlayerArena[client];
    if (arena <= 0 || arena > g_iArenaCount)
    {
        if (g_bDebugWeaponRules)
            LogMessage("[MGE weapons][debug] skip: no/invalid arena client=%N arena=%d", client, arena);
        return;
    }

    int slot = g_iPlayerSlot[client];
    int maxActiveSlot = g_bFourPersonArena[arena] ? SLOT_FOUR : SLOT_TWO;
    if (!g_bArenaNoFight[arena] && slot > maxActiveSlot)
    {
        if (g_bDebugWeaponRules)
            LogMessage("[MGE weapons][debug] skip: inactive slot client=%N arena=%s slot=%d max_active=%d",
                client, g_sArenaOriginalName[arena], slot, maxActiveSlot);
        return;
    }

    g_bApplyingWeaponRules[client] = true;

    if (g_bDebugWeaponRules)
    {
        int defaultId = ResolveDefaultWeaponProfileId();
        LogMessage("[MGE weapons][debug] apply start client=%N arena=%s slot=%d alive=%d profiles=%d global_profiles=%d default_profile=%d",
            client, g_sArenaOriginalName[arena], slot, IsPlayerAlive(client) ? 1 : 0,
            (g_alArenaWeaponProfiles[arena] != null) ? g_alArenaWeaponProfiles[arena].Length : 0,
            g_iWeaponProfileCount, defaultId);
    }

    for (int i = 0; i <= 5; i++)
    {
        int weaponEntity = GetPlayerWeaponSlot(client, i);
        if (!IsValidEntity(weaponEntity))
        {
            if (g_bDebugWeaponRules)
                LogMessage("[MGE weapons][debug] slot empty client=%N arena=%s slot=%d", client, g_sArenaOriginalName[arena], i);
            continue;
        }

        int itemdef = GetEntProp(weaponEntity, Prop_Send, "m_iItemDefinitionIndex");
        if (g_bDebugWeaponRules)
        {
            char weaponClass[64];
            GetEntityClassname(weaponEntity, weaponClass, sizeof(weaponClass));
            LogMessage("[MGE weapons][debug] inspect client=%N arena=%s slot=%d itemdef=%d class=%s",
                client, g_sArenaOriginalName[arena], i, itemdef, weaponClass);
        }

        char ruleDesc[MAX_WEAPON_RULE_DESC];
        if (!ResolveArenaWeaponRule(arena, weaponEntity, itemdef, ruleDesc, sizeof(ruleDesc), client))
        {
            if (g_bDebugWeaponRules)
                LogMessage("[MGE weapons][debug] no rule client=%N arena=%s slot=%d itemdef=%d",
                    client, g_sArenaOriginalName[arena], i, itemdef);
            continue;
        }

        WeaponRuleType ruleType;
        int replacementIndex;
        char replacementClass[MAX_WEAPON_CLASS_TOKEN];
        if (!DecodeRuleDesc(ruleDesc, ruleType, replacementIndex, replacementClass, sizeof(replacementClass)))
        {
            if (g_bDebugWeaponRules)
                LogMessage("[MGE weapons][debug] decode failed client=%N arena=%s slot=%d rule='%s'",
                    client, g_sArenaOriginalName[arena], i, ruleDesc);
            continue;
        }

        ApplyWeaponRuleToSlot(client, arena, i, weaponEntity, ruleType, replacementIndex, replacementClass);
    }

    // Extra pass for blocked wearables (some items are not in weapon slots).
    int wearable = -1;
    while ((wearable = FindEntityByClassname(wearable, "tf_wearable*")) != -1)
    {
        if (!IsValidEntity(wearable))
            continue;
        if (!HasEntProp(wearable, Prop_Send, "m_iItemDefinitionIndex"))
            continue;
        if (!HasEntProp(wearable, Prop_Send, "m_hOwnerEntity"))
            continue;

        int owner = GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity");
        if (owner != client)
            continue;

        int itemdef = GetEntProp(wearable, Prop_Send, "m_iItemDefinitionIndex");
        char ruleDesc[MAX_WEAPON_RULE_DESC];
        if (!ResolveArenaWeaponRule(arena, wearable, itemdef, ruleDesc, sizeof(ruleDesc), client))
            continue;

        WeaponRuleType ruleType;
        int replacementIndex;
        char replacementClass[MAX_WEAPON_CLASS_TOKEN];
        if (!DecodeRuleDesc(ruleDesc, ruleType, replacementIndex, replacementClass, sizeof(replacementClass)))
            continue;

        if (ruleType == WR_Block)
        {
            if (g_bDebugWeaponRules)
            {
                char wearableClass[64];
                GetEntityClassname(wearable, wearableClass, sizeof(wearableClass));
                LogMessage("[MGE weapons][debug] wearable block client=%N arena=%s itemdef=%d class=%s ent=%d",
                    client, g_sArenaOriginalName[arena], itemdef, wearableClass, wearable);
            }

            if (GetFeatureStatus(FeatureType_Native, "TF2_RemoveWearable") == FeatureStatus_Available)
                TF2_RemoveWearable(client, wearable);
            else
                RemoveEntity(wearable);
        }
        else if (ruleType == WR_Replace && g_bDebugWeaponRules)
        {
            LogMessage("[MGE weapons][debug] wearable replace skipped (remove-only for wearables) client=%N arena=%s itemdef=%d",
                client, g_sArenaOriginalName[arena], itemdef);
        }
    }

    g_bApplyingWeaponRules[client] = false;

    if (g_bDebugWeaponRules)
        LogMessage("[MGE weapons][debug] apply done client=%N arena=%s", client, g_sArenaOriginalName[arena]);
}

void ApplyWeaponRulesAfterInventoryUpdate(int client, const char[] source)
{
    if (!IsValidClient(client))
        return;

    if (g_bDebugWeaponRules)
        LogMessage("[MGE weapons][debug] inventory_update source=%s client=%N", source, client);

    ApplyArenaWeaponRulesForClient(client);
}
