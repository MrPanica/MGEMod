#pragma semicolon 1
#pragma newdecls required

// Hack for unrestricted maxplayers
#if defined (MAXPLAYERS)
    #undef MAXPLAYERS
    #define MAXPLAYERS 101
#endif

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>
#include <morecolors>
#include <clientprefs>
#include <convar_class>
#include <mge>

#define PL_VERSION "3.1.0-beta10"

#define MAXARENAS 63
#define MAXSPAWNS 15
#define HUDFADEOUTTIME 120.0
#define SPAWN_ANNOTATION_LIFETIME 999999.0
#define MAX_SPAWN_ANNOTATIONS 512
#define SPAWN_ANN_TYPE_NEUTRAL 0
#define SPAWN_ANN_TYPE_RED 1
#define SPAWN_ANN_TYPE_BLU 2
#define SPAWN_ANN_TYPE_BBALL_INTEL 3
#define SPAWN_ANN_TYPE_BBALL_INTEL_RED 4
#define SPAWN_ANN_TYPE_BBALL_INTEL_BLU 5
#define SPAWN_ANN_TYPE_BBALL_HOOP 6
#define SPAWN_ANN_TYPE_BBALL_HOOP_RED 7
#define SPAWN_ANN_TYPE_BBALL_HOOP_BLU 8
#define TV_KEY_OVERLAY_COUNT 8
#define MONITOR_HINT_COOLDOWN 5.0
#define QUEUE_KEYHINT_KEEPALIVE_SEC 0.25

#if !defined(IN_SCORE)
#define IN_SCORE (1 << 16)
#endif

#pragma newdecls required

// Globals
#include "mge/globals.sp"

Handle g_hSpawnAnnotationRefreshTimer[MAXPLAYERS + 1];
int g_iSpawnAnnotationCount[MAXPLAYERS + 1];
int g_iSpawnAnnotationArena[MAXPLAYERS + 1][MAX_SPAWN_ANNOTATIONS];
int g_iSpawnAnnotationType[MAXPLAYERS + 1][MAX_SPAWN_ANNOTATIONS];
int g_iSpawnAnnotationNumber[MAXPLAYERS + 1][MAX_SPAWN_ANNOTATIONS];
float g_fSpawnAnnotationOrigin[MAXPLAYERS + 1][MAX_SPAWN_ANNOTATIONS][3];
bool g_bShowSpawnAnnotationsActive[MAXPLAYERS + 1];

enum TvKeyOverlay
{
    TV_KEY_W = 0,
    TV_KEY_S,
    TV_KEY_A,
    TV_KEY_D,
    TV_KEY_JUMP,
    TV_KEY_CTRL,
    TV_KEY_LKM,
    TV_KEY_PKM
}

char g_sTvKeyTextTarget[TV_KEY_OVERLAY_COUNT][32] =
{
    "text_w",
    "text_s",
    "text_a",
    "text_d",
    "text_jump",
    "text_ztrl",
    "text_lkm",
    "text_pkm"
};

bool g_bTvKeysVisible;
bool g_bTvKeyPressed[TV_KEY_OVERLAY_COUNT];
int g_iTvBrushLkmEntRef;
int g_iTvBrushPkmEntRef;
int g_iTvBrushMouseEntRef;
char g_sLastQueueHintText[MAXPLAYERS + 1][512];
float g_fLastQueueHintSentAt[MAXPLAYERS + 1];
float g_fMonitorHintNextAt[MAXPLAYERS + 1];
float g_fQueueHintInterval = 0.5;
float g_fBBallSpinInterval = 0.03;
float g_fNextArenaActivityScanAt;
bool g_bHasActiveAmmomodFight;
bool g_bHasActiveKothFight;
bool g_bPerfDebug;
bool g_bCameraMonitorVolumeEnabled;
int g_iMonitorMicSpeaker1EntRef;
int g_iMonitorNoSoundBrush1EntRef;
int g_iMonitorNoSoundBrush2EntRef;
StringMap g_smNamedEntityCache;

// Modules
#include "mge/elo.sp"
#include "mge/sql.sp"
#include "mge/hud.sp"
#include "mge/weapons.sp"
#include "mge/arenas.sp"
#include "mge/match.sp"
#include "mge/player.sp"
#include "mge/spectator.sp"
#include "mge/statistics.sp"
#include "mge/migrations.sp"

#include "mge/gamemodes/bball.sp"
#include "mge/gamemodes/koth.sp"
#include "mge/gamemodes/2v2.sp"
#include "mge/gamemodes/ammomod.sp"
#include "mge/gamemodes/endif.sp"

// API
#include "mge/api/forwards.sp"
#include "mge/api/natives.sp"

public Plugin myinfo =
{
    name        = "MGE",
    author      = "Originally by Lange & Cprice; based on kAmmomod by Krolus - maintained by sappho.io, PepperKick, and others",
    description = "Duel mod for TF2 with realistic game situations.",
    version     =  PL_VERSION,
    url         = "https://github.com/sapphonie/MGEMod"
}


// ===== PLUGIN CORE LIFECYCLE =====

// Initialize all API forwards for other plugins to hook into
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();
    if (engine != Engine_TF2)
    {
        SetFailState("This plugin is for Team Fortress 2 only.");
    }

    // Store late loading flag for hot reload handling
    g_bLate = late;

    // Forward declarations
    RegisterForwards();
    
    // Register all natives
    RegisterNatives();
    
    // Register plugin library
    RegPluginLibrary("mge");
    
    return APLRes_Success;
}

// Initialize the plugin, register commands, create convars, and set up core systems
public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("mgemod.phrases");

    // Initialize cookies
    g_hShowEloCookie = new Cookie("mgemod_showelo", "MGEMod ELO display preference", CookieAccess_Private);
    g_hShowQueueCookie = new Cookie("mgemod_showqueue", "MGEMod queue display in keyhint preference", CookieAccess_Private);
    InitWeaponRuleSystem();
    EnsureWeaponConfigTemplateExists();

    // ConVars
    CreateConVar("sm_mgemod_version", PL_VERSION, "MGEMod version", FCVAR_SPONLY | FCVAR_NOTIFY);
    gcvar_fragLimit = new Convar("mgemod_fraglimit", "1", "Default frag limit in duel", FCVAR_NONE, true, 1.0);
    gcvar_allowedClasses = new Convar("mgemod_allowed_classes", "soldier demoman scout", "Classes that players allowed to choose by default");
    gcvar_blockFallDamage = new Convar("mgemod_blockdmg_fall", "0", "Block falldamage? (0 = Disabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_dbConfig = new Convar("mgemod_dbconfig", "mgemod", "Name of database config");
    gcvar_stats = new Convar("mgemod_stats", "1", "Enable/Disable stats.");
    gcvar_airshotHeight = new Convar("mgemod_airshot_height", "80", "The minimum height at which it will count airshot", FCVAR_NONE, true, 10.0, true, 500.0);
    gcvar_RocketForceX = new Convar("mgemod_endif_force_x", "1.1", "The amount by which to multiply the X push force on Endif.", FCVAR_NONE, true, 1.0, true, 10.0);
    gcvar_RocketForceY = new Convar("mgemod_endif_force_y", "1.1", "The amount by which to multiply the Y push force on Endif.", FCVAR_NONE, true, 1.0, true, 10.0);
    gcvar_RocketForceZ = new Convar("mgemod_endif_force_z", "2.15", "The amount by which to multiply the Z push force on Endif.", FCVAR_NONE, true, 1.0, true, 10.0);
    gcvar_autoCvar = new Convar("mgemod_autocvar", "1", "Automatically set recommended game cvars? (0 = Disabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_bballParticle_red = new Convar("mgemod_bball_particle_red", "player_intel_trail_red", "Particle effect to attach to Red players in BBall.");
    gcvar_bballParticle_blue = new Convar("mgemod_bball_particle_blue", "player_intel_trail_blue", "Particle effect to attach to Blue players in BBall.");
    gcvar_midairHP = new Convar("mgemod_midair_hp", "5", "Minimum health for midair detection", FCVAR_NONE, true, 1.0);
    gcvar_noDisplayRating = new Convar("mgemod_hide_rating", "0", "Hide the in-game display of rating points. They will still be tracked in the database.");
    gcvar_reconnectInterval = new Convar("mgemod_reconnect_interval", "5", "How long (in minutes) to wait between database reconnection attempts.");
    gcvar_2v2SkipCountdown = new Convar("mgemod_2v2_skip_countdown", "0", "Skip countdown between 2v2 rounds? (0 = Normal countdown, 1 = Skip countdown)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_2v2Elo = new Convar("mgemod_2v2_elo", "1", "Enable ELO calculation and display for 2v2 matches? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_clearProjectiles = new Convar("mgemod_clear_projectiles", "0", "Clear projectiles when a new round starts? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_clearPlayerEntities = new Convar("mgemod_clear_player_entities", "0", "Clear player entities (projectiles and buildings) between duels? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_debugWadd = new Convar("mgemod_debug_wadd", "0", "Debug wadd logic to mgemod.log? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_debugTeleport = new Convar("mgemod_debug_teleport", "0", "Debug arena teleport reasons to logs? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_debugWeaponRules = new Convar("mgemod_debug_weaponrules", "0", "Debug weapon block/replace rule matches to logs? (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_perfDebug = new Convar("mgemod_perf_debug", "0", "Enable verbose performance/debug logs for hot paths. (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_allowUnverifiedPlayers = new Convar("mgemod_allow_unverified_players", "0", "Allow players with unverified ELO to play? ELO calculations will be skipped for them. (0 = Block unverified, 1 = Allow but skip ELO)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_vipQueuePriority = new Convar("mgemod_vip_queue_priority", "0", "Enable VIP queue priority? Players with 'a' or 'z' admin flags will be placed at the front of the queue. (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    gcvar_queueHintInterval = new Convar("mgemod_queuehint_interval", "0.5", "Queue KeyHint update interval in seconds.", FCVAR_NONE, true, 0.2, true, 2.0);
    gcvar_bballSpinInterval = new Convar("mgemod_bball_spin_interval", "0.03", "BBall intel spin timer interval in seconds.", FCVAR_NONE, true, 0.01, true, 0.2);
    gcvar_mapWorldText = new Convar("mgemod_map_worldtext", "0", "Enable map worldtext integration (top/MVP/camera arena text). (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);

    // Create config file
    Convar.CreateConfig("mge");

    // Populate global variables with their corresponding convar values.
    g_iDefaultFragLimit = gcvar_fragLimit.IntValue;
    g_bBlockFallDamage = gcvar_blockFallDamage.IntValue ? true : false;
    g_iAirshotHeight = gcvar_airshotHeight.IntValue;
    g_iMidairHP = gcvar_midairHP.IntValue;
    g_bAutoCvar = gcvar_autoCvar.IntValue ? true : false;
    g_bNoDisplayRating = gcvar_noDisplayRating.IntValue ? true : false;
    g_iReconnectInterval = gcvar_reconnectInterval.IntValue;
    g_b2v2SkipCountdown = gcvar_2v2SkipCountdown.IntValue ? true : false;
    g_b2v2Elo = gcvar_2v2Elo.IntValue ? true : false;
    g_bClearProjectiles = gcvar_clearProjectiles.IntValue ? true : false;
    g_bClearPlayerEntities = gcvar_clearPlayerEntities.IntValue ? true : false;
    g_bDebugWadd = gcvar_debugWadd.IntValue ? true : false;
    g_bDebugTeleport = gcvar_debugTeleport.IntValue ? true : false;
    g_bDebugWeaponRules = gcvar_debugWeaponRules.IntValue ? true : false;
    g_bPerfDebug = gcvar_perfDebug.IntValue ? true : false;
    g_bAllowUnverifiedPlayers = gcvar_allowUnverifiedPlayers.IntValue ? true : false;
    g_bVipQueuePriority = gcvar_vipQueuePriority.IntValue ? true : false;
    g_fQueueHintInterval = gcvar_queueHintInterval.FloatValue;
    g_fBBallSpinInterval = gcvar_bballSpinInterval.FloatValue;

    gcvar_dbConfig.GetString(g_sDBConfig, sizeof(g_sDBConfig));
    gcvar_bballParticle_red.GetString(g_sBBallParticleRed, sizeof(g_sBBallParticleRed));
    gcvar_bballParticle_blue.GetString(g_sBBallParticleBlue, sizeof(g_sBBallParticleBlue));

    g_bNoStats = gcvar_stats.BoolValue ? false : true;

    g_fRocketForceX = gcvar_RocketForceX.FloatValue;
    g_fRocketForceY = gcvar_RocketForceY.FloatValue;
    g_fRocketForceZ = gcvar_RocketForceZ.FloatValue;

    // Initialize sound setting with default value (will be updated after convar creation)
    g_bPlayArenaSound = true;

    for (int i = 0; i < MAXARENAS + 1; ++i)
    {
        g_bTimerRunning[i] = false;
        g_fCappedTime[i] = 0.0;
        g_fTotalTime[i] = 0.0;
    }

    // Parse default list of allowed classes.
    ParseAllowedClasses("", g_tfctClassAllowed);

    // Hook convar changes
    gcvar_fragLimit.AddChangeHook(handler_ConVarChange);
    gcvar_allowedClasses.AddChangeHook(handler_ConVarChange);
    gcvar_blockFallDamage.AddChangeHook(handler_ConVarChange);
    gcvar_dbConfig.AddChangeHook(handler_ConVarChange);
    gcvar_stats.AddChangeHook(handler_ConVarChange);
    gcvar_airshotHeight.AddChangeHook(handler_ConVarChange);
    gcvar_midairHP.AddChangeHook(handler_ConVarChange);
    gcvar_RocketForceX.AddChangeHook(handler_ConVarChange);
    gcvar_RocketForceY.AddChangeHook(handler_ConVarChange);
    gcvar_RocketForceZ.AddChangeHook(handler_ConVarChange);
    gcvar_autoCvar.AddChangeHook(handler_ConVarChange);
    gcvar_bballParticle_red.AddChangeHook(handler_ConVarChange);
    gcvar_bballParticle_blue.AddChangeHook(handler_ConVarChange);
    gcvar_noDisplayRating.AddChangeHook(handler_ConVarChange);
    gcvar_reconnectInterval.AddChangeHook(handler_ConVarChange);
    gcvar_2v2SkipCountdown.AddChangeHook(handler_ConVarChange);
    gcvar_2v2Elo.AddChangeHook(handler_ConVarChange);
    gcvar_clearProjectiles.AddChangeHook(handler_ConVarChange);
    gcvar_clearPlayerEntities.AddChangeHook(handler_ConVarChange);
    gcvar_debugWadd.AddChangeHook(handler_ConVarChange);
    gcvar_debugTeleport.AddChangeHook(handler_ConVarChange);
    gcvar_debugWeaponRules.AddChangeHook(handler_ConVarChange);
    gcvar_perfDebug.AddChangeHook(handler_ConVarChange);
    gcvar_allowUnverifiedPlayers.AddChangeHook(handler_ConVarChange);
    gcvar_vipQueuePriority.AddChangeHook(handler_ConVarChange);
    gcvar_queueHintInterval.AddChangeHook(handler_ConVarChange);
    gcvar_bballSpinInterval.AddChangeHook(handler_ConVarChange);
    gcvar_mapWorldText.AddChangeHook(handler_ConVarChange);

    // Sound control convar
    g_cvarPlayArenaSound = new Convar("mgemod_play_arena_sound", "1", "Play sound when player auto-joins arena from waiting list (0 = Disabled, 1 = Enabled)", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvarPlayArenaSound.AddChangeHook(handler_ConVarChange);

    // Initialize sound setting from convar
    g_bPlayArenaSound = g_cvarPlayArenaSound.BoolValue;

    // Client commands
    RegConsoleCmd("mgemod", Command_Menu, "MGEMod Menu");
    RegConsoleCmd("add", Command_Menu, "Usage: add <arena number/arena name/@player>. Add to an arena.");
    RegConsoleCmd("wadd", Command_Wadd, "Usage: wadd <arena number/arena name>. Add to waiting list for arena.");
    RegConsoleCmd("swap", Command_Swap, "Ask your teammate to swap classes with you in ultiduo");
    RegConsoleCmd("remove", Command_Remove, "Remove from current arena.");
    RegConsoleCmd("top5", Command_Top5, "Display the Top players.");
    RegConsoleCmd("hud", Command_ToggleHud, "Toggle text hud.");
    RegConsoleCmd("hidehud", Command_ToggleHud, "Toggle text hud. (alias)");
    RegConsoleCmd("elo", Command_ToggleElo, "Toggle ELO display.");
    RegConsoleCmd("rank", Command_Rank, "Usage: rank <player name>. Show that player's rank.");
    RegConsoleCmd("stats", Command_Rank, "Alias for \"rank\".");
    RegConsoleCmd("mgehelp", Command_Help);
    RegConsoleCmd("first", Command_First, "Join the first available arena.");
    RegConsoleCmd("handicap", Command_Handicap, "Reduce your maximum HP. Type '!handicap off' to disable.");
    RegConsoleCmd("spec_next", Command_Spec);
    RegConsoleCmd("spec_prev", Command_Spec);
    RegConsoleCmd("autoteam", Command_AutoTeam);
    RegConsoleCmd("jointeam", Command_JoinTeam);
    RegConsoleCmd("joinclass", Command_JoinClass);
    RegConsoleCmd("join_class", Command_JoinClass);
    RegConsoleCmd("eureka_teleport", Command_EurekaTeleport);
    RegConsoleCmd("1v1", Command_OneVsOne, "Change arena to 1v1");
    RegConsoleCmd("2v2", Command_TwoVsTwo, "Change arena to 2v2");
    RegConsoleCmd("invite", Command_Invite, "Invite a player to your arena. Usage: !invite [player name]");
    RegConsoleCmd("accept", Command_AcceptInvite, "Accept an arena invitation.");
    RegConsoleCmd("acc", Command_AcceptInvite, "Accept an arena invitation.");
    RegConsoleCmd("decline", Command_DeclineInvite, "Decline an arena invitation.");
    RegConsoleCmd("dec", Command_DeclineInvite, "Decline an arena invitation.");
    RegConsoleCmd("q", Command_ToggleQueue, "Toggle queue display in keyhint.");

    // Admin commands
    RegAdminCmd("koth", Command_Koth, ADMFLAG_BAN, "Change arena to KOTH Mode");
    RegAdminCmd("mge", Command_Mge, ADMFLAG_BAN, "Change arena to MGE Mode");
    RegAdminCmd("loc", Command_Loc, ADMFLAG_BAN, "Shows client origin and angle vectors");
    RegAdminCmd("botme", Command_AddBot, ADMFLAG_BAN, "Add bot to your arena");
    RegAdminCmd("conntest", Command_ConnectionTest, ADMFLAG_BAN, "MySQL connection test");
    RegAdminCmd("sm_mge_worldtext_debug", Command_MgeWorldTextDebug, ADMFLAG_BAN, "Print current worldtext values to your console");
    RegAdminCmd("sm_mge_worldtext_refresh", Command_MgeWorldTextRefresh, ADMFLAG_BAN, "Force refresh worldtext from DB and re-apply map text");
    RegAdminCmd("sm_mge_camera_debug", Command_MgeCameraDebug, ADMFLAG_BAN, "Print camera/POV debug state and arena players");
    RegAdminCmd("sm_mge_camera_set", Command_MgeCameraSet, ADMFLAG_BAN, "Force camera by targetname. Usage: sm_mge_camera_set <camera_targetname>");
    RegAdminCmd("sm_mge_camera_pov", Command_MgeCameraPov, ADMFLAG_BAN, "Run one POV cycle manually (same as sg_sm_camera_pov relay)");
    RegAdminCmd("sm_mge_camera_pov_off", Command_MgeCameraPovOff, ADMFLAG_BAN, "Force exit POV mode and restore arena camera");
    RegAdminCmd("sm_mge_camera_scan_relays", Command_MgeCameraScanRelays, ADMFLAG_BAN, "List sg_sm* logic_relay entities and disabled state");
    RegAdminCmd("sm_mge_camera_trigger_pov", Command_MgeCameraTriggerPov, ADMFLAG_BAN, "Force Trigger on logic_relay sg_sm_camera_pov");
    RegAdminCmd("sm_mge_show_spawns", Command_MgeShowSpawns, ADMFLAG_BAN, "Show nearby (3000u) arena spawns via show_annotation; persists until re-run");
    RegAdminCmd("sm_mge_bball_scoreboard_debug", Command_MgeBballScoreboardDebug, ADMFLAG_BAN, "Print BBall scoreboard entities and show markers near current/selected arena");
    RegAdminCmd("sm_mge_weapon_reload", Command_MgeWeaponReload, ADMFLAG_BAN, "Reload weapon profile config and arena weapon bindings without plugin reload");
    RegAdminCmd("sm_mge_map_reload", Command_MgeMapReload, ADMFLAG_BAN, "Reload the current map arena config without plugin reload");
    RegAdminCmd("sm_setspawn", Command_SetSpawn, ADMFLAG_BAN, "Edit player or BBall spawns in your current arena. Usage: sm_setspawn [red|blue|intel|hoop]");
    RegAdminCmd("arena_restart", Command_ArenaRestart, ADMFLAG_BAN, "Restart current arena fight");
    RegAdminCmd("sm_arena_restart", Command_ArenaRestart, ADMFLAG_BAN, "Restart current arena fight");
    RegAdminCmd("sm_force_remove", Command_ForceRemove, ADMFLAG_BAN, "Force remove a player from their arena. Usage: sm_force_remove <player>");
    RegAdminCmd("sm_force_add", Command_ForceAdd, ADMFLAG_BAN, "Force add a player to admin's arena. Usage: sm_force_add <player>");
    
    // 2v2 Ready System Commands
    RegConsoleCmd("ready", Command_Ready, "Mark yourself as ready for 2v2 match");
    RegConsoleCmd("r", Command_Ready, "Mark yourself as ready for 2v2 match");
    
    AddCommandListener(Command_DropItem, "dropitem");
    AddCommandListener(Command_SpecNavigation, "spec_next");
    AddCommandListener(Command_SpecNavigation, "spec_prev");
    AddCommandListener(Command_BlockSpectate, "spectate");
    AddCommandListener(Command_SetSpawnChatInput, "say");
    AddCommandListener(Command_SetSpawnChatInput, "say_team");
    HookEntityOutput("logic_relay", "OnTrigger", OnSgCameraSignal);
    HookEntityOutput("logic_relay", "OnTrigger", OnSgTvTextSignal);
    HookEntityOutput("logic_relay", "OnTrigger", OnSgTvTextShowKeysSignal);
    HookEntityOutput("logic_relay", "OnTrigger", OnSgCameraMonitorVolumeSignal);
    HookEntityOutput("logic_relay", "OnTrigger", OnSgCameraPovSignal);
    HookEntityOutput("logic_relay", "OnTrigger", OnSgRelayDebugTrace);
    HookEntityOutput("func_button", "OnPressed", OnFightButtonPressed);
    HookEntityOutput("trigger_multiple", "OnStartTouch", OnTriggerMultipleStartTouchOutput);
    HookEntityOutput("trigger_multiple", "OnStartTouchAll", OnTriggerMultipleStartTouchOutput);
    HookEntityOutput("func_respawnroom", "OnStartTouch", OnRespawnroomStartTouchOutput);
    HookEntityOutput("func_respawnroom", "OnEndTouch", OnRespawnroomEndTouchOutput);

    // HUD synchronizers
    hm_HP           = CreateHudSynchronizer();
    hm_Score        = CreateHudSynchronizer();
    hm_KothTimerBLU = CreateHudSynchronizer();
    hm_KothTimerRED = CreateHudSynchronizer();
    hm_KothCap      = CreateHudSynchronizer();
    hm_TeammateHP   = CreateHudSynchronizer();

    // Set up the log file for debug logging
    BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/mgemod.log");
    BuildPath(Path_SM, g_sStateFile, sizeof(g_sStateFile), "data/mgemod_state.cfg");
}

// Execute configuration after all configs are loaded
public void OnConfigsExecuted()
{
    if (!g_bNoStats)
    {
        PrepareSQL();
    }
}

// Handle plugin hot reload by reinitializing all connected clients and loading their stats
void HandleHotReload()
{
    MC_PrintToChatAll("%t", "PluginReloaded");

    if (RestoreHotReloadState())
    {
        if (!g_bNoStats && g_DB != null)
        {
            for (int i = 1; i <= MaxClients; i++)
            {
                if (!IsValidClient(i) || IsFakeClient(i))
                    continue;

                // Force stats refresh for all online players after plugin reload.
                TryLoadPlayerStats(i, true, true);
            }
        }

        EnsureHudTimers();
        g_bLate = false;
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            ForcePlayerSuicide(i);
            g_bCanPlayerSwap[i] = true;
            g_bCanPlayerGetIntel[i] = true;
            
            if (g_alPlayerDuelClasses[i] != null)
                delete g_alPlayerDuelClasses[i];
            g_alPlayerDuelClasses[i] = new ArrayList();
            
            // Reinitialize basic client state for hot reload
            if (!IsFakeClient(i))
            {
                ChangeClientTeam(i, TFTeam_Spectator);
                g_bShowHud[i] = true;
                g_bPlayerRestoringAmmo[i] = false;
                g_bPlayerEloVerified[i] = false;
                
                // Load stats from database if available
                if (!g_bNoStats && g_DB != null)
                {
                    char steamid_dirty[31], steamid[64], query[256];
                    
                    if (GetClientAuthId(i, AuthId_Steam2, steamid_dirty, sizeof(steamid_dirty)))
                    {
                        g_DB.Escape(steamid_dirty, steamid, sizeof(steamid));
                        strcopy(g_sPlayerSteamID[i], 32, steamid);
                        GetSelectPlayerStatsQuery(query, sizeof(query), steamid);
                        g_DB.Query(SQL_OnPlayerReceived, query, i);
                    }
                }
            }
        }
    }
    
    // Reset the late flag after handling hot reload
    g_bLate = false;
}

void RestartQueueHintTimer()
{
    delete g_hQueueKeyHintTimer;

    float interval = g_fQueueHintInterval;
    if (interval < 0.2)
        interval = 0.2;
    else if (interval > 2.0)
        interval = 2.0;

    g_hQueueKeyHintTimer = CreateTimer(interval, Timer_UpdateQueueKeyHint, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

void RefreshActiveArenaProcessingFlags(bool force = false)
{
    float now = GetGameTime();
    if (!force && now < g_fNextArenaActivityScanAt)
        return;

    g_fNextArenaActivityScanAt = now + 0.5;
    g_bHasActiveAmmomodFight = false;
    g_bHasActiveKothFight = false;

    for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
    {
        if (g_iArenaStatus[arena_index] != AS_FIGHT)
            continue;

        if (g_bArenaKoth[arena_index])
            g_bHasActiveKothFight = true;

        if (!g_bArenaBBall[arena_index] && !g_bArenaMGE[arena_index] && !g_bArenaKoth[arena_index])
            g_bHasActiveAmmomodFight = true;

        if (g_bHasActiveAmmomodFight && g_bHasActiveKothFight)
            break;
    }
}

// Ensure HUD and queue timers are running
void EnsureHudTimers()
{
    if (g_hSpecHudTimer == null)
        g_hSpecHudTimer = CreateTimer(1.0, Timer_SpecHudToAllArenas, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
    if (g_hQueueKeyHintTimer == null)
        RestartQueueHintTimer();

}

// Save arena and queue state for hot reload
void SaveHotReloadState()
{
    if (g_iArenaCount <= 0)
        return;

    KeyValues kv = new KeyValues("mgemod_state");
    kv.SetNum("arena_count", g_iArenaCount);

    kv.JumpToKey("arenas", true);
    for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
    {
        char arena_key[8];
        IntToString(arena_index, arena_key, sizeof(arena_key));
        kv.JumpToKey(arena_key, true);

        kv.SetNum("status", g_iArenaStatus[arena_index]);
        kv.SetNum("score_red", g_iArenaScore[arena_index][SLOT_ONE]);
        kv.SetNum("score_blu", g_iArenaScore[arena_index][SLOT_TWO]);
        kv.SetNum("duel_start", g_iArenaDuelStartTime[arena_index]);

        for (int slot = 1; slot < MAXPLAYERS; slot++)
        {
            int client = g_iArenaQueue[arena_index][slot];
            if (client > 0 && IsValidClient(client))
            {
                char slot_key[16];
                Format(slot_key, sizeof(slot_key), "slot_%d", slot);
                kv.SetNum(slot_key, GetClientUserId(client));
            }
        }

        kv.GoBack();
    }
    kv.GoBack();

    kv.JumpToKey("waiting", true);
    for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
    {
        char arena_key[8];
        IntToString(arena_index, arena_key, sizeof(arena_key));
        kv.JumpToKey(arena_key, true);

        int waiting_count = 0;
        if (g_alArenaWaitingList[arena_index] != null)
            waiting_count = g_alArenaWaitingList[arena_index].Length;

        kv.SetNum("count", waiting_count);
        for (int i = 0; i < waiting_count; i++)
        {
            int client = g_alArenaWaitingList[arena_index].Get(i);
            if (client > 0 && IsValidClient(client))
            {
                char wait_key[16];
                Format(wait_key, sizeof(wait_key), "w%d", i + 1);
                kv.SetNum(wait_key, GetClientUserId(client));
            }
        }

        kv.GoBack();
    }
    kv.GoBack();

    kv.JumpToKey("clients", true);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;

        char client_key[16];
        IntToString(GetClientUserId(client), client_key, sizeof(client_key));
        kv.JumpToKey(client_key, true);
        kv.SetNum("waiting", g_iPlayerWaiting[client] ? 1 : 0);
        kv.SetNum("class", view_as<int>(g_tfctPlayerClass[client]));
        kv.SetNum("wadd", g_bPlayerAddedViaWadd[client] ? 1 : 0);
        kv.SetNum("elo_verified", g_bPlayerEloVerified[client] ? 1 : 0);
        kv.SetNum("rating", g_iPlayerRating[client]);
        kv.SetNum("wins", g_iPlayerWins[client]);
        kv.SetNum("losses", g_iPlayerLosses[client]);
        kv.SetNum("arena", g_iPlayerArena[client]);
        kv.SetNum("slot", g_iPlayerSlot[client]);
        kv.SetNum("team", GetClientTeam(client));
        kv.SetNum("alive", IsPlayerAlive(client) ? 1 : 0);
        kv.SetNum("hp", GetClientHealth(client));
        kv.SetNum("mge_hp", g_iPlayerHP[client]);
        kv.SetNum("max_hp", g_iPlayerMaxHP[client]);

        float origin[3];
        float angles[3];
        GetClientAbsOrigin(client, origin);
        GetClientEyeAngles(client, angles);
        kv.SetFloat("pos_x", origin[0]);
        kv.SetFloat("pos_y", origin[1]);
        kv.SetFloat("pos_z", origin[2]);
        kv.SetFloat("ang_x", angles[0]);
        kv.SetFloat("ang_y", angles[1]);
        kv.SetFloat("ang_z", angles[2]);
        kv.GoBack();
    }
    kv.GoBack();

    kv.ExportToFile(g_sStateFile);
    delete kv;
}

// Restore arena and queue state after hot reload
bool RestoreHotReloadState()
{
    if (!FileExists(g_sStateFile))
        return false;

    KeyValues kv = new KeyValues("mgemod_state");
    if (!kv.ImportFromFile(g_sStateFile))
    {
        delete kv;
        return false;
    }

    if (g_iArenaCount <= 0)
    {
        delete kv;
        return false;
    }

    for (int i = 1; i <= g_iArenaCount; i++)
    {
        if (g_alArenaWaitingList[i] == null)
            g_alArenaWaitingList[i] = new ArrayList();
        else
            g_alArenaWaitingList[i].Clear();

        for (int slot = 1; slot < MAXPLAYERS; slot++)
            g_iArenaQueue[i][slot] = 0;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        g_iPlayerArena[client] = 0;
        g_iPlayerSlot[client] = 0;
        g_iTeleportRevision[client] = 0;
        g_iPlayerWaiting[client] = false;
        g_bPlayerAddedViaWadd[client] = false;
    }

    if (kv.JumpToKey("arenas", false))
    {
        for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
        {
            char arena_key[8];
            IntToString(arena_index, arena_key, sizeof(arena_key));
            if (!kv.JumpToKey(arena_key, false))
                continue;

            g_iArenaStatus[arena_index] = kv.GetNum("status", g_iArenaStatus[arena_index]);
            g_iArenaScore[arena_index][SLOT_ONE] = kv.GetNum("score_red", 0);
            g_iArenaScore[arena_index][SLOT_TWO] = kv.GetNum("score_blu", 0);
            g_iArenaDuelStartTime[arena_index] = kv.GetNum("duel_start", 0);

            for (int slot = 1; slot < MAXPLAYERS; slot++)
            {
                char slot_key[16];
                Format(slot_key, sizeof(slot_key), "slot_%d", slot);
                int userid = kv.GetNum(slot_key, 0);
                if (userid <= 0)
                    continue;

                int client = GetClientOfUserId(userid);
                if (!IsValidClient(client))
                    continue;

                g_iArenaQueue[arena_index][slot] = client;
                g_iPlayerArena[client] = arena_index;
                g_iPlayerSlot[client] = slot;
            }

            kv.GoBack();
        }
        kv.GoBack();
    }

    if (kv.JumpToKey("waiting", false))
    {
        for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
        {
            char arena_key[8];
            IntToString(arena_index, arena_key, sizeof(arena_key));
            if (!kv.JumpToKey(arena_key, false))
                continue;

            int waiting_count = kv.GetNum("count", 0);
            for (int i = 0; i < waiting_count; i++)
            {
                char wait_key[16];
                Format(wait_key, sizeof(wait_key), "w%d", i + 1);
                int userid = kv.GetNum(wait_key, 0);
                if (userid <= 0)
                    continue;

                int client = GetClientOfUserId(userid);
                if (!IsValidClient(client))
                    continue;

                g_alArenaWaitingList[arena_index].Push(client);
            }

            kv.GoBack();
        }
        kv.GoBack();
    }

    if (kv.JumpToKey("clients", false))
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsValidClient(client))
                continue;

            if (!IsFakeClient(client))
            {
                char steamid_dirty[31], steamid[64];
                if (GetClientAuthId(client, AuthId_Steam2, steamid_dirty, sizeof(steamid_dirty)))
                {
                    if (g_DB != null)
                        g_DB.Escape(steamid_dirty, steamid, sizeof(steamid));
                    else
                        strcopy(steamid, sizeof(steamid), steamid_dirty);

                    strcopy(g_sPlayerSteamID[client], sizeof(g_sPlayerSteamID[]), steamid);
                }
                else
                {
                    g_sPlayerSteamID[client][0] = '\0';
                    g_bPlayerEloVerified[client] = false;
                }
            }

            char client_key[16];
            IntToString(GetClientUserId(client), client_key, sizeof(client_key));
            if (!kv.JumpToKey(client_key, false))
                continue;

            g_iPlayerWaiting[client] = kv.GetNum("waiting", 0) != 0;
            int class_value = kv.GetNum("class", 0);
            if (class_value > 0)
                g_tfctPlayerClass[client] = view_as<TFClassType>(class_value);
            g_bPlayerAddedViaWadd[client] = kv.GetNum("wadd", 0) != 0;
            g_bPlayerEloVerified[client] = kv.GetNum("elo_verified", 0) != 0;
            g_iPlayerRating[client] = kv.GetNum("rating", g_iPlayerRating[client]);
            g_iPlayerWins[client] = kv.GetNum("wins", g_iPlayerWins[client]);
            g_iPlayerLosses[client] = kv.GetNum("losses", g_iPlayerLosses[client]);
            if (!IsFakeClient(client) && strlen(g_sPlayerSteamID[client]) == 0)
                g_bPlayerEloVerified[client] = false;

            int saved_arena = kv.GetNum("arena", 0);
            int saved_slot = kv.GetNum("slot", 0);
            int saved_hp = kv.GetNum("hp", 0);
            int saved_mge_hp = kv.GetNum("mge_hp", 0);
            int saved_max_hp = kv.GetNum("max_hp", 0);
            bool saved_alive = kv.GetNum("alive", 0) != 0;
            float origin[3];
            float angles[3];
            origin[0] = kv.GetFloat("pos_x", 0.0);
            origin[1] = kv.GetFloat("pos_y", 0.0);
            origin[2] = kv.GetFloat("pos_z", 0.0);
            angles[0] = kv.GetFloat("ang_x", 0.0);
            angles[1] = kv.GetFloat("ang_y", 0.0);
            angles[2] = kv.GetFloat("ang_z", 0.0);

            if (saved_arena > 0 && saved_slot > 0 && g_iPlayerArena[client] == saved_arena && g_iPlayerSlot[client] == saved_slot)
            {
                int max_active_slot = g_bFourPersonArena[saved_arena] ? SLOT_FOUR : SLOT_TWO;
                if (saved_slot <= max_active_slot && !g_iPlayerWaiting[client])
                {
                    int target_team = (saved_slot == SLOT_ONE || saved_slot == SLOT_THREE) ? TEAM_RED : TEAM_BLU;

                    if (GetClientTeam(client) != target_team)
                        ChangeClientTeam(client, target_team);

                    if (class_value > 0)
                        TF2_SetPlayerClass(client, view_as<TFClassType>(class_value));

                    if (!IsPlayerAlive(client) || !saved_alive)
                        TF2_RespawnPlayer(client);

                    TeleportEntity(client, origin, angles, NULL_VECTOR);

                    if (saved_max_hp > 0)
                        g_iPlayerMaxHP[client] = saved_max_hp;

                    if (saved_mge_hp > 0)
                        g_iPlayerHP[client] = saved_mge_hp;

                    if (saved_hp > 0)
                        SetEntProp(client, Prop_Data, "m_iHealth", saved_hp);
                }
            }

            kv.GoBack();
        }
        kv.GoBack();
    }

    delete kv;
    DeleteFile(g_sStateFile);

    UpdateHudForAll();
    for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
    {
        UpdateQueueKeyHintText(arena_index);
    }

    return true;
}

public void OnPluginEnd()
{
    delete g_hSpecHudTimer;
    delete g_hQueueKeyHintTimer;
    delete g_hTopRatingTimer;
    delete g_hMapWorldTextTimer;
    delete g_hMapWorldTextApplyTimer;
    delete g_hCameraPovFollowTimer;
    delete g_hBBallScoreboardTimer;

    for (int arena = 0; arena <= MAXARENAS; arena++)
        delete g_hBBallIntelSpinTimer[arena];

    delete g_smNamedEntityCache;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_hPlayerWaitingSpecTimer[client] != null)
        {
            delete g_hPlayerWaitingSpecTimer[client];
            g_hPlayerWaitingSpecTimer[client] = null;
        }
        ClearClientSpawnAnnotations(client, false);
        ClearBBallCarryState(client, true);
    }

    SaveHotReloadState();
}

// Initialize map-specific systems, precache models, hook events, and set up arenas
public void OnMapStart()
{
    if (g_smNamedEntityCache == null)
        g_smNamedEntityCache = new StringMap();
    else
        g_smNamedEntityCache.Clear();

    for (int i = 0; i < sizeof(stockSounds); i++) {
        PrecacheSound(stockSounds[i], true);
    }

    // Models. These are used for the artifical flag in BBall.
    PrecacheModel(MODEL_BRIEFCASE, true);
    PrecacheModel(MODEL_AMMOPACK, true);
    // Used for ultiduo/koth arenas
    PrecacheModel(MODEL_POINT, true);

    g_bNoStats = gcvar_stats.BoolValue ? false : true; /* Reset this variable, since it is forced to false during Event_WinPanel */
    g_sCurrentCameraName[0] = '\0';
    g_iCurrentCameraIndex = 0;
    g_iCurrentCameraArenaIndex = 0;
    g_bCameraMonitorVolumeEnabled = true;
    g_iMonitorMicSpeaker1EntRef = INVALID_ENT_REFERENCE;
    g_iMonitorNoSoundBrush1EntRef = INVALID_ENT_REFERENCE;
    g_iMonitorNoSoundBrush2EntRef = INVALID_ENT_REFERENCE;
    g_sLastTvText[0] = '\0';
    g_sLastTopMvpText[0] = '\0';
    g_fNextTopMvpWorldTextUpdate = 0.0;
    g_fNextArenaActivityScanAt = 0.0;
    g_bHasActiveAmmomodFight = false;
    g_bHasActiveKothFight = false;
    g_bMapWorldTextApplyPending = false;
    g_bTvTextVisible = true;
    g_bTvKeysVisible = false;
    g_bCameraPovMode = false;
    g_iCameraPovTarget = 0;
    g_iCameraPovArenaIndex = 0;
    g_iCameraPovListIndex = -1;
    g_iCameraSpectateEntity = -1;
    g_bCameraPovCameraPoseSaved = false;
    g_iCameraPovMovedCameraEnt = -1;
    g_iCameraPovAttachedTargetSpectate = 0;
    g_iCameraPovAttachedTargetArenaCam = 0;
    delete g_hCameraPovFollowTimer;
    delete g_hMapWorldTextApplyTimer;
    for (int i = 0; i < 10; i++)
        strcopy(g_sTop10WorldTextNames[i], sizeof(g_sTop10WorldTextNames[]), "---");
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iPlayerRespawnroomTouchDepth[i] = 0;
        g_fMonitorHintNextAt[i] = 0.0;
        g_sLastQueueHintText[i][0] = '\0';
        g_fLastQueueHintSentAt[i] = 0.0;
    }
    for (int i = 0; i < TV_KEY_OVERLAY_COUNT; i++)
        g_bTvKeyPressed[i] = false;
    g_iTvBrushLkmEntRef = INVALID_ENT_REFERENCE;
    g_iTvBrushPkmEntRef = INVALID_ENT_REFERENCE;
    g_iTvBrushMouseEntRef = INVALID_ENT_REFERENCE;

    LoadWeaponRuleProfiles();
    ResetArenaWeaponRuleBindings();

    // Spawns
    bool isMapAm = LoadSpawnPoints();
    if (isMapAm)
    {
        for (int i = 0; i <= g_iArenaCount; i++)
        {
            ResetBBallScoreboardCache(i);
            if (g_bArenaBBall[i])
            {
                g_iBBallHoop[i][SLOT_ONE] = -1;
                g_iBBallHoop[i][SLOT_TWO] = -1;
                g_iBBallHoopTrigger[i][SLOT_ONE] = INVALID_ENT_REFERENCE;
                g_iBBallHoopTrigger[i][SLOT_TWO] = INVALID_ENT_REFERENCE;
                g_iBBallIntel[i] = -1;
                g_iBBallIntelWorldParticle[i] = 0;
                g_iBBallIntelSkinTeam[i] = 0; // 0 = RED (default)
                delete g_hBBallIntelSpinTimer[i];
            }
            if (g_bArenaKoth[i])
            {
                g_iCapturePoint[i] = -1;
            }
        }

        CacheBBallScoreboardEntities();
        StartBBallScoreboardTimer();

        EnsureHudTimers();

        // Create timer to show top rated online player every 5 minutes
        g_hTopRatingTimer = CreateTimer(300.0, Timer_ShowTopRatedPlayer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
        if (g_hMapWorldTextTimer == null)
            g_hMapWorldTextTimer = CreateTimer(1.0, Timer_UpdateMapWorldText, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
        RequestMapTop10WorldTextData();
        ApplyTvKeyOverlayVisibility();
        UpdateMonitorMicrophonesPlacement();

        if (g_bAutoCvar)
        {
            FindConVar("mp_autoteambalance").SetInt(0);
            FindConVar("mp_teams_unbalance_limit").SetInt(101);
            FindConVar("mp_tournament").SetInt(0);
        }

        HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
        HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
        HookEvent("post_inventory_application", Event_PostInventoryApplication, EventHookMode_Post);
        HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
        HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Post);
        HookEvent("teamplay_win_panel", Event_WinPanel, EventHookMode_Post);
        HookEvent("player_team", Event_Suppress, EventHookMode_Pre);
        HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
        HookEvent("player_class", Event_Suppress, EventHookMode_Pre);

        AddNormalSoundHook(Sound_BlockSound);
    } else {
        SetFailState("Map not supported. MGEMod disabled.");
    }

    RefreshActiveArenaProcessingFlags(true);

    for (int i = 0; i < MAXPLAYERS; i++)
    {
        if (g_hPlayerWaitingSpecTimer[i] != null)
        {
            delete g_hPlayerWaitingSpecTimer[i];
            g_hPlayerWaitingSpecTimer[i] = null;
        }
        ClearClientSpawnAnnotations(i, false);
        g_bSetSpawnAwaitInput[i] = false;
        g_iSetSpawnArena[i] = 0;
        g_iSetSpawnMode[i] = 0;
        g_iPlayerWaiting[i] = false;
        g_bCanPlayerSwap[i] = true;
        g_bCanPlayerGetIntel[i] = true;
        g_iPlayerInviteFrom[i] = 0;
        g_iPlayerInviteTo[i] = 0;
        g_fPlayerInviteTime[i] = 0.0;
        g_fPlayerAddCooldown[i] = 0.0;
        g_iBBallBackModel[i] = 0;
        for (int classId = 1; classId <= 9; classId++)
        {
            g_iPlayerClassPoints[i][classId] = 0;
            for (int oppClassId = 1; oppClassId <= 9; oppClassId++)
            {
                g_iPlayerClassRating[i][classId][oppClassId] = 0;
                g_iPlayerMatchupCount[i][classId][oppClassId] = 0;
            }
        }
        // g_bShowQueue is initialized in globals.sp as { true, ... }
    }

    // Initialize waiting lists for arenas
    for (int i = 0; i <= MAXARENAS; i++)
    {
        if (g_alArenaWaitingList[i] == null)
        {
            g_alArenaWaitingList[i] = new ArrayList();
        }
        else
        {
            g_alArenaWaitingList[i].Clear();
        }
    }

    for (int i = 0; i < MAXARENAS; i++)
    {
        g_bTimerRunning[i] = false;
        g_fCappedTime[i] = 0.0;
        g_fTotalTime[i] = 0.0;
    }
}

// Clean up resources and unhook events when map ends
public void OnMapEnd()
{
    if (g_smNamedEntityCache != null)
        g_smNamedEntityCache.Clear();

    g_bCameraMonitorVolumeEnabled = true;
    g_iMonitorMicSpeaker1EntRef = INVALID_ENT_REFERENCE;
    g_iMonitorNoSoundBrush1EntRef = INVALID_ENT_REFERENCE;
    g_iMonitorNoSoundBrush2EntRef = INVALID_ENT_REFERENCE;
    CleanupWeaponRuleSystem();
    delete g_hDBReconnectTimer;
    delete g_hTopRatingTimer;
    delete g_hSpecHudTimer;
    delete g_hQueueKeyHintTimer;
    delete g_hMapWorldTextTimer;
    delete g_hMapWorldTextApplyTimer;
    delete g_hCameraPovFollowTimer;
    delete g_hBBallScoreboardTimer;
    for (int i = 0; i <= MAXARENAS; i++)
        delete g_hBBallIntelSpinTimer[i];
    g_bCameraPovCameraPoseSaved = false;
    g_iCameraPovMovedCameraEnt = -1;
    g_iCameraPovAttachedTargetSpectate = 0;
    g_iCameraPovAttachedTargetArenaCam = 0;
    g_bHasActiveAmmomodFight = false;
    g_bHasActiveKothFight = false;
    g_bNoStats = gcvar_stats.BoolValue ? false : true;

    UnhookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    UnhookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    UnhookEvent("post_inventory_application", Event_PostInventoryApplication, EventHookMode_Post);
    UnhookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
    UnhookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Post);
    UnhookEvent("teamplay_win_panel", Event_WinPanel, EventHookMode_Post);
    UnhookEvent("player_team", Event_Suppress, EventHookMode_Pre);
    UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
    UnhookEvent("player_class", Event_Suppress, EventHookMode_Pre);

    RemoveNormalSoundHook(Sound_BlockSound);

    for (int arena_index = 1; arena_index <= g_iArenaCount; arena_index++)
    {
        if (g_bTimerRunning[arena_index])
        {
            delete g_tKothTimer[arena_index];
            g_bTimerRunning[arena_index] = false;
        }
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_hPlayerWaitingSpecTimer[client] != null)
        {
            delete g_hPlayerWaitingSpecTimer[client];
            g_hPlayerWaitingSpecTimer[client] = null;
        }
        g_iPlayerWaiting[client] = false;
        ClearClientSpawnAnnotations(client, false);
        ClearBBallCarryState(client, true);
    }
}


// ===== ENTITY & PROJECTILE SYSTEM =====

// Hook projectiles for direct hit detection when entities are created
public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "tf_projectile_rocket") || StrEqual(classname, "tf_projectile_pipe"))
        SDKHook(entity, SDKHook_Touch, OnProjectileTouch);
}

// Track direct hits from projectiles for airshot calculations
void OnProjectileTouch(int entity, int other)
{
    if (other > 0 && other <= MaxClients)
        g_bPlayerTakenDirectHit[other] = true;
}


// ===== CLIENT LIFECYCLE MANAGEMENT =====

// Load client preferences from cookies when they become available
public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client))
        return;
    
    // Load ELO display preference from cookie
    char cookieValue[8];
    g_hShowEloCookie.Get(client, cookieValue, sizeof(cookieValue));
    if (strlen(cookieValue) > 0)
        g_bShowElo[client] = (StringToInt(cookieValue) == 1);
    else
        g_bShowElo[client] = true; // Default to enabled for new players

    // Load queue display preference from cookie
    g_hShowQueueCookie.Get(client, cookieValue, sizeof(cookieValue));
    if (strlen(cookieValue) > 0)
        g_bShowQueue[client] = (StringToInt(cookieValue) == 1);
    else
        g_bShowQueue[client] = true; // Default to enabled for new players
}

// Initialize basic client data when they connect (regardless of Steam status)
public void OnClientPutInServer(int client)
{
    g_sLastQueueHintText[client][0] = '\0';
    g_fLastQueueHintSentAt[client] = 0.0;
    HandleClientConnection(client);
}

// Handle Steam-authenticated connections and retry ELO loading if needed
public void OnClientPostAdminCheck(int client)
{
    HandleClientAuthentication(client);
}

// Clean up client data, handle arena cleanup, and manage bot removal on disconnect
public void OnClientDisconnect(int client)
{
    ClearClientSpawnAnnotations(client, false);
    g_sLastQueueHintText[client][0] = '\0';
    g_fLastQueueHintSentAt[client] = 0.0;
    HandleClientDisconnection(client);
}


// ===== GAME MECHANICS & HOOKS =====

// Process continuous game mechanics like ammomod health and KOTH capture points
public void OnGameFrame()
{
    RefreshActiveArenaProcessingFlags();

    if (g_bHasActiveAmmomodFight)
        ProcessAmmomodHealthManagement();

    if (g_bHasActiveKothFight)
        ProcessKothCapturePoints();
}

// Handle damage modifications including fall damage blocking
Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if (!IsValidClient(victim) || !IsValidClient(attacker))
        return Plugin_Continue;

    // Fall damage negation.
    if ((damagetype & DMG_FALL) && g_bBlockFallDamage)
    {
        damage = 0.0;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// Process infinite ammo restoration for ammomod arenas
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    int arena_index = g_iPlayerArena[client];

    bool is_scoreboard_open = (buttons & IN_SCORE) != 0;
    if (is_scoreboard_open != g_bScoreboardOpen[client])
    {
        g_bScoreboardOpen[client] = is_scoreboard_open;
        if (!is_scoreboard_open)
        {
            UpdateHud(client);

            if (arena_index > 0 && arena_index <= g_iArenaCount && g_bShowQueue[client] && !g_bArenaNoFight[arena_index])
            {
                // Force immediate queue hint re-show after scoreboard closes.
                g_fLastQueueHintSentAt[client] = 0.0;
                ShowQueueInKeyHintText(client, arena_index);
            }
        }
    }

    if (g_bArenaInfAmmo[arena_index])
    {
        if (!g_bPlayerRestoringAmmo[client] && (buttons & IN_ATTACK))
        {
            g_bPlayerRestoringAmmo[client] = true;
            CreateTimer(0.4, Timer_GiveAmmo, GetClientUserId(client));
        }
    }

    UpdateTvKeyOverlayFromClientInput(client, buttons);
    return Plugin_Continue;
}


// ===== CONFIGURATION SYSTEM =====

// Update global variables when convars change
void handler_ConVarChange(Handle convar, const char[] oldValue, const char[] newValue)
{
    // Boolean conversion helper
    bool boolValue = view_as<bool>(StringToInt(newValue));
    
    // Integer conversion helper  
    int intValue = StringToInt(newValue);
    
    // Float conversion helper
    float floatValue = StringToFloat(newValue);
    
    // Handle each convar type
    if (convar == gcvar_fragLimit)
        g_iDefaultFragLimit = intValue;
    else if (convar == gcvar_allowedClasses)
        ParseAllowedClasses(newValue, g_tfctClassAllowed);
    else if (convar == gcvar_blockFallDamage)
        g_bBlockFallDamage = boolValue;
    else if (convar == gcvar_dbConfig)
        strcopy(g_sDBConfig, sizeof(g_sDBConfig), newValue);
    else if (convar == gcvar_stats)
        g_bNoStats = !boolValue;
    else if (convar == gcvar_airshotHeight)
        g_iAirshotHeight = intValue;
    else if (convar == gcvar_midairHP)
        g_iMidairHP = intValue;
    else if (convar == gcvar_RocketForceX)
        g_fRocketForceX = floatValue;
    else if (convar == gcvar_RocketForceY)
        g_fRocketForceY = floatValue;
    else if (convar == gcvar_RocketForceZ)
        g_fRocketForceZ = floatValue;
    else if (convar == gcvar_autoCvar)
        g_bAutoCvar = boolValue;
    else if (convar == gcvar_bballParticle_red)
        strcopy(g_sBBallParticleRed, sizeof(g_sBBallParticleRed), newValue);
    else if (convar == gcvar_bballParticle_blue)
        strcopy(g_sBBallParticleBlue, sizeof(g_sBBallParticleBlue), newValue);
    else if (convar == gcvar_noDisplayRating)
        g_bNoDisplayRating = boolValue;
    else if (convar == gcvar_reconnectInterval)
        g_iReconnectInterval = intValue;
    else if (convar == gcvar_2v2SkipCountdown)
        g_b2v2SkipCountdown = boolValue;
    else if (convar == gcvar_2v2Elo)
        g_b2v2Elo = boolValue;
    else if (convar == gcvar_clearProjectiles)
        g_bClearProjectiles = boolValue;
    else if (convar == gcvar_clearPlayerEntities)
        g_bClearPlayerEntities = boolValue;
    else if (convar == gcvar_debugWadd)
        g_bDebugWadd = boolValue;
    else if (convar == gcvar_debugTeleport)
        g_bDebugTeleport = boolValue;
    else if (convar == gcvar_debugWeaponRules)
        g_bDebugWeaponRules = boolValue;
    else if (convar == gcvar_perfDebug)
        g_bPerfDebug = boolValue;
    else if (convar == gcvar_allowUnverifiedPlayers)
        g_bAllowUnverifiedPlayers = boolValue;
    else if (convar == gcvar_vipQueuePriority)
        g_bVipQueuePriority = boolValue;
    else if (convar == gcvar_queueHintInterval)
    {
        g_fQueueHintInterval = floatValue;
        if (g_hQueueKeyHintTimer != null)
            RestartQueueHintTimer();
    }
    else if (convar == gcvar_bballSpinInterval)
        g_fBBallSpinInterval = floatValue;
    else if (convar == gcvar_mapWorldText)
    {
        if (boolValue)
        {
            RequestMapTop10WorldTextData();
            Timer_UpdateMapWorldText(null);
            RefreshTvKeyOverlayForCurrentPov();
        }
        else
        {
            g_bTvKeysVisible = false;
            for (int i = 0; i < TV_KEY_OVERLAY_COUNT; i++)
                g_bTvKeyPressed[i] = false;
            ApplyTvKeyOverlayVisibility();
        }
    }
    else if (convar == g_cvarPlayArenaSound)
        g_bPlayArenaSound = boolValue;
}

bool IsMapWorldTextEnabled()
{
    return (gcvar_mapWorldText != null && gcvar_mapWorldText.BoolValue);
}

Action Timer_UpdateMapWorldText(Handle timer)
{
    if (!IsMapWorldTextEnabled())
        return Plugin_Continue;

    if (UpdateTopMvpWorldTextIfNeeded())
        QueueApplyMapWorldText(0.4);
    else
        UpdateTvTextForCurrentCamera();

    return Plugin_Continue;
}

void RequestMapTop10WorldTextData()
{
    if (g_bNoStats || g_DB == null)
        return;

    char query[256];
    g_DB.Format(query, sizeof(query), "SELECT rating, name FROM mgemod_stats ORDER BY rating DESC LIMIT 10");
    g_DB.Query(SQL_OnMapTop10Received, query);
}

void SQL_OnMapTop10Received(Database db, DBResultSet results, const char[] error, any data)
{
    if (db == null || results == null || !StrEqual(error, ""))
        return;

    for (int i = 0; i < 10; i++)
        strcopy(g_sTop10WorldTextNames[i], sizeof(g_sTop10WorldTextNames[]), "---");

    int row = 0;
    while (results.FetchRow() && row < 10)
    {
        int rating = results.FetchInt(0);
        char nameRaw[MAX_NAME_LENGTH];
        char nameAscii[MAX_NAME_LENGTH * 2];
        results.FetchString(1, nameRaw, sizeof(nameRaw));
        TransliterateToAscii(nameRaw, nameAscii, sizeof(nameAscii));
        Format(g_sTop10WorldTextNames[row], sizeof(g_sTop10WorldTextNames[]), "%s (%d)", nameAscii, rating);
        row++;
    }

    if (IsMapWorldTextEnabled())
    {
        UpdateTopMvpWorldTextIfNeeded(true);
        QueueApplyMapWorldText(1.0);
    }
}

bool UpdateTopMvpWorldTextIfNeeded(bool force = false)
{
    float now = GetGameTime();
    if (!force && g_fNextTopMvpWorldTextUpdate > now)
        return false;

    g_fNextTopMvpWorldTextUpdate = now + 60.0;

    int topPlayer = FindTopRatedOnlinePlayer();
    char mvpRaw[MAX_NAME_LENGTH];
    char mvpAscii[MAX_NAME_LENGTH * 2];

    if (topPlayer != -1 && IsValidClient(topPlayer))
        GetClientName(topPlayer, mvpRaw, sizeof(mvpRaw));
    else
        strcopy(mvpRaw, sizeof(mvpRaw), "---");

    TransliterateToAscii(mvpRaw, mvpAscii, sizeof(mvpAscii));
    if (topPlayer != -1 && IsValidClient(topPlayer))
        Format(g_sLastTopMvpText, sizeof(g_sLastTopMvpText), "%s (%d)", mvpAscii, g_iPlayerRating[topPlayer]);
    else
        strcopy(g_sLastTopMvpText, sizeof(g_sLastTopMvpText), mvpAscii);

    return true;
}

void QueueApplyMapWorldText(float delay)
{
    if (!IsMapWorldTextEnabled())
        return;

    if (g_bMapWorldTextApplyPending)
        return;

    g_bMapWorldTextApplyPending = true;
    g_hMapWorldTextApplyTimer = CreateTimer(delay, Timer_ApplyMapWorldText, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_ApplyMapWorldText(Handle timer)
{
    g_hMapWorldTextApplyTimer = null;
    g_bMapWorldTextApplyPending = false;
    ApplyMapWorldTextNow();
    return Plugin_Stop;
}

void ApplyMapWorldTextNow()
{
    if (!IsMapWorldTextEnabled())
        return;

    SetMapTextByTargetName("text_mge_top", g_sLastTopMvpText[0] ? g_sLastTopMvpText : "---");

    for (int i = 0; i < 10; i++)
    {
        char line[192];
        Format(line, sizeof(line), "%d. %s", i + 1, g_sTop10WorldTextNames[i]);

        char targetName[32];
        Format(targetName, sizeof(targetName), "text_mge_top_%d", i + 1);
        SetMapTextByTargetName(targetName, line);
    }

    UpdateTvTextForCurrentCamera();
}

public void OnSgCameraSignal(const char[] output, int caller, int activator, float delay)
{
    int relayEnt = ResolveOutputEntity(caller);
    if (relayEnt == -1)
        return;

    char relayName[64];
    GetEntPropString(relayEnt, Prop_Data, "m_iName", relayName, sizeof(relayName));
    if (!StrEqual(relayName, "sg_sm_camera_signal", false))
        return;

    if (!IsValidEntity(activator))
    {
        LogMessage("[MGE camera][WARN] sg_sm_camera_signal trigger without valid activator");
        return;
    }

    char className[64];
    GetEntityClassname(activator, className, sizeof(className));
    if (!StrEqual(className, "point_camera", false))
    {
        LogMessage("[MGE camera][WARN] sg_sm_camera_signal activator is not point_camera (%s, ent=%d)", className, activator);
        return;
    }

    char camName[64];
    GetEntPropString(activator, Prop_Data, "m_iName", camName, sizeof(camName));
    if (camName[0] == '\0')
    {
        LogMessage("[MGE camera][WARN] sg_sm_camera_signal got camera without targetname");
        return;
    }

    if (StrEqual(camName, g_sCurrentCameraName, false))
        return;

    char prevCamera[64];
    strcopy(prevCamera, sizeof(prevCamera), g_sCurrentCameraName);
    strcopy(g_sCurrentCameraName, sizeof(g_sCurrentCameraName), camName);
    g_iCurrentCameraIndex = 0;
    g_iCurrentCameraArenaIndex = 0;

    if (g_bCameraPovMode)
        ExitCameraPovModeToCamera(camName);

    SetVariantString("1");
    AcceptEntityInput(activator, "SetOnAndTurnOthersOff");
    AcceptEntityInput(activator, "Enable");

    if (ParseCameraIndex(camName, g_iCurrentCameraIndex))
    {
        g_iCurrentCameraArenaIndex = ResolveCameraArenaIndexFromEntity(activator, g_iCurrentCameraIndex);
        LogMessage("[MGE camera] active camera changed: %s -> %s (idx=%d, arena=%d)", prevCamera[0] ? prevCamera : "---", camName, g_iCurrentCameraIndex, g_iCurrentCameraArenaIndex);
    }
    else
    {
        LogMessage("[MGE camera][WARN] invalid camera name format: %s (expected sg_camera_N)", camName);
    }

    if (IsMapWorldTextEnabled())
        UpdateTvTextForCurrentCamera();

    UpdateMonitorMicrophonesPlacement();
}

public void OnSgTvTextSignal(const char[] output, int caller, int activator, float delay)
{
    int relayEnt = ResolveOutputEntity(caller);
    if (relayEnt == -1)
        return;

    char relayName[64];
    GetEntPropString(relayEnt, Prop_Data, "m_iName", relayName, sizeof(relayName));
    if (!StrEqual(relayName, "sg_sm_tv_text", false))
        return;

    g_bTvTextVisible = !g_bTvTextVisible;
    ApplyTvTextVisibility();
}

public void OnSgTvTextShowKeysSignal(const char[] output, int caller, int activator, float delay)
{
    int relayEnt = ResolveOutputEntity(caller);
    if (relayEnt == -1)
        return;

    char relayName[64];
    GetEntPropString(relayEnt, Prop_Data, "m_iName", relayName, sizeof(relayName));
    if (!StrEqual(relayName, "sg_sm_tv_text_show_keys", false))
        return;

    if (!IsMapWorldTextEnabled())
        return;

    g_bTvKeysVisible = !g_bTvKeysVisible;
    if (!g_bTvKeysVisible)
    {
        for (int i = 0; i < TV_KEY_OVERLAY_COUNT; i++)
            g_bTvKeyPressed[i] = false;
    }

    ApplyTvKeyOverlayVisibility();
    RefreshTvKeyOverlayForCurrentPov();
}

public void OnSgCameraMonitorVolumeSignal(const char[] output, int caller, int activator, float delay)
{
    #pragma unused output
    #pragma unused activator
    #pragma unused delay

    int relayEnt = ResolveOutputEntity(caller);
    if (relayEnt == -1)
        return;

    char relayName[64];
    GetEntPropString(relayEnt, Prop_Data, "m_iName", relayName, sizeof(relayName));
    if (!StrEqual(relayName, "sg_sm_camera_monitor_volume", false))
        return;

    g_bCameraMonitorVolumeEnabled = !g_bCameraMonitorVolumeEnabled;
    UpdateMonitorMicrophonesPlacement();
    LogMessage("[MGE camera] monitor volume: %s", g_bCameraMonitorVolumeEnabled ? "enabled" : "disabled");
}

public void OnSgCameraPovSignal(const char[] output, int caller, int activator, float delay)
{
    int relayEnt = ResolveOutputEntity(caller);
    if (relayEnt == -1)
    {
        LogMessage("[MGE camera][WARN] OnSgCameraPovSignal with invalid caller=%d", caller);
        return;
    }

    char relayName[64];
    GetEntPropString(relayEnt, Prop_Data, "m_iName", relayName, sizeof(relayName));
    if (!StrEqual(relayName, "sg_sm_camera_pov", false) && !StrEqual(relayName, "sg_sm_camera_pov_signal", false))
        return;

    HandleCameraPovToggle("relay", activator);
}

public void OnSgRelayDebugTrace(const char[] output, int caller, int activator, float delay)
{
    #pragma unused output
    #pragma unused delay

    if (!g_bPerfDebug)
        return;

    int relayEnt = ResolveOutputEntity(caller);
    if (relayEnt == -1)
        return;

    char relayName[64];
    GetEntPropString(relayEnt, Prop_Data, "m_iName", relayName, sizeof(relayName));
    if (relayName[0] == '\0' || StrContains(relayName, "sg_sm_", false) != 0)
        return;

    char actClass[64];
    char actName[64];
    if (IsValidEntity(activator))
    {
        GetEntityClassname(activator, actClass, sizeof(actClass));
        GetEntPropString(activator, Prop_Data, "m_iName", actName, sizeof(actName));
    }
    else
    {
        strcopy(actClass, sizeof(actClass), "invalid");
        strcopy(actName, sizeof(actName), "");
    }

    LogMessage("[MGE relay] %s triggered (caller=%d->%d, activator=%d class=%s name=%s)", relayName, caller, relayEnt, activator, actClass, actName);
}

bool IsTvKeyPressedForButtons(int buttons, TvKeyOverlay key)
{
    switch (key)
    {
        case TV_KEY_W: return (buttons & IN_FORWARD) != 0;
        case TV_KEY_S: return (buttons & IN_BACK) != 0;
        case TV_KEY_A: return (buttons & IN_MOVELEFT) != 0;
        case TV_KEY_D: return (buttons & IN_MOVERIGHT) != 0;
        case TV_KEY_JUMP: return (buttons & IN_JUMP) != 0;
        case TV_KEY_CTRL: return (buttons & IN_DUCK) != 0;
        case TV_KEY_LKM: return (buttons & IN_ATTACK) != 0;
        case TV_KEY_PKM: return (buttons & IN_ATTACK2) != 0;
    }

    return false;
}

int GetTvBrushEntity(const char[] targetName, int &entRef)
{
    int cached = EntRefToEntIndex(entRef);
    if (cached > MaxClients && IsValidEntity(cached))
        return cached;

    int entity = FindEntityByTargetName("func_brush", targetName);
    entRef = (entity == -1) ? INVALID_ENT_REFERENCE : EntIndexToEntRef(entity);
    return entity;
}

void SetTvBrushColor(const char[] targetName, int &entRef, bool pressed, int alpha)
{
    int entity = GetTvBrushEntity(targetName, entRef);
    if (entity == -1)
        return;

    if (alpha > 0)
        AcceptEntityInput(entity, "Enable");
    else
        AcceptEntityInput(entity, "Disable");

    int green = pressed ? 0 : 255;
    int blue = pressed ? 0 : 255;

    SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
    SetEntityRenderColor(entity, 255, green, blue, alpha);
}

void ApplyTvKeyTextColor(TvKeyOverlay key, bool pressed, int alpha)
{
    int red = 255;
    int green = pressed ? 0 : 255;
    int blue = pressed ? 0 : 255;

    SetMapTextColorByTargetName(g_sTvKeyTextTarget[view_as<int>(key)], red, green, blue, alpha);

    if (key == TV_KEY_CTRL)
        SetMapTextColorByTargetName("text_ctrl", red, green, blue, alpha);
}

void ApplyTvKeyOverlayVisibility()
{
    int alpha = (IsMapWorldTextEnabled() && g_bTvKeysVisible) ? 255 : 0;

    for (int i = 0; i < TV_KEY_OVERLAY_COUNT; i++)
        ApplyTvKeyTextColor(view_as<TvKeyOverlay>(i), g_bTvKeyPressed[i], alpha);

    SetTvBrushColor("brush_button_lkm", g_iTvBrushLkmEntRef, g_bTvKeyPressed[TV_KEY_LKM], alpha);
    SetTvBrushColor("brush_button_pkm", g_iTvBrushPkmEntRef, g_bTvKeyPressed[TV_KEY_PKM], alpha);
    SetTvBrushColor("brush_button_mouse", g_iTvBrushMouseEntRef, false, alpha);
}

void RefreshTvKeyOverlayForCurrentPov()
{
    if (!IsMapWorldTextEnabled() || !g_bTvKeysVisible)
        return;

    bool hasTarget = g_bCameraPovMode && IsValidClient(g_iCameraPovTarget) && IsPovAttachTargetValid(g_iCameraPovTarget);
    int buttons = hasTarget ? GetClientButtons(g_iCameraPovTarget) : 0;

    for (int i = 0; i < TV_KEY_OVERLAY_COUNT; i++)
    {
        bool pressed = hasTarget ? IsTvKeyPressedForButtons(buttons, view_as<TvKeyOverlay>(i)) : false;
        g_bTvKeyPressed[i] = pressed;
    }

    ApplyTvKeyOverlayVisibility();
}

void UpdateTvKeyOverlayFromClientInput(int client, int buttons)
{
    if (!IsMapWorldTextEnabled() || !g_bTvKeysVisible)
        return;
    if (!g_bCameraPovMode || client != g_iCameraPovTarget)
        return;
    if (!IsPovAttachTargetValid(client))
        return;

    bool changed = false;
    for (int i = 0; i < TV_KEY_OVERLAY_COUNT; i++)
    {
        bool pressed = IsTvKeyPressedForButtons(buttons, view_as<TvKeyOverlay>(i));
        if (pressed == g_bTvKeyPressed[i])
            continue;

        g_bTvKeyPressed[i] = pressed;
        changed = true;
    }

    if (changed)
        ApplyTvKeyOverlayVisibility();
}

int GetMonitorMicrophoneEntity(const char[] targetName, int &entRef)
{
    int cached = EntRefToEntIndex(entRef);
    if (cached > MaxClients && IsValidEntity(cached))
        return cached;

    int entity = FindEntityByTargetName("env_microphone", targetName);
    entRef = (entity == -1) ? INVALID_ENT_REFERENCE : EntIndexToEntRef(entity);
    return entity;
}

int GetMonitorNoSoundBrushEntity(const char[] targetName, int &entRef)
{
    int cached = EntRefToEntIndex(entRef);
    if (cached > MaxClients && IsValidEntity(cached))
        return cached;

    int entity = FindEntityByTargetName("func_brush", targetName);
    entRef = (entity == -1) ? INVALID_ENT_REFERENCE : EntIndexToEntRef(entity);
    return entity;
}

void SetMonitorMicrophonesEnabled(bool enabled)
{
    int mic1 = GetMonitorMicrophoneEntity("speaker_1", g_iMonitorMicSpeaker1EntRef);

    if (mic1 != -1)
        AcceptEntityInput(mic1, enabled ? "Enable" : "Disable");
}

void ApplyMonitorNoSoundBrushState()
{
    int brush1 = GetMonitorNoSoundBrushEntity("brush_no_sound_1", g_iMonitorNoSoundBrush1EntRef);
    int brush2 = GetMonitorNoSoundBrushEntity("brush_no_sound_2", g_iMonitorNoSoundBrush2EntRef);

    if (brush1 != -1)
        AcceptEntityInput(brush1, g_bCameraMonitorVolumeEnabled ? "Disable" : "Enable");
    if (brush2 != -1)
        AcceptEntityInput(brush2, g_bCameraMonitorVolumeEnabled ? "Disable" : "Enable");
}

bool TryResolveMonitorAudioSource(float sourcePos[3], float sourceAng[3])
{
    if (g_bCameraPovMode && IsValidClient(g_iCameraPovTarget))
    {
        GetClientEyePosition(g_iCameraPovTarget, sourcePos);
        GetClientEyeAngles(g_iCameraPovTarget, sourceAng);
        return true;
    }

    if (g_sCurrentCameraName[0] == '\0')
        return false;

    int cameraEnt = GetCachedEntityByTargetName("point_camera", g_sCurrentCameraName);
    if (cameraEnt == -1 || !IsValidEntity(cameraEnt))
        return false;

    GetEntPropVector(cameraEnt, Prop_Data, "m_vecOrigin", sourcePos);
    GetEntPropVector(cameraEnt, Prop_Data, "m_angRotation", sourceAng);
    return true;
}

void UpdateMonitorMicrophonesPlacement()
{
    ApplyMonitorNoSoundBrushState();

    if (!g_bCameraMonitorVolumeEnabled)
    {
        SetMonitorMicrophonesEnabled(false);
        return;
    }

    int mic1 = GetMonitorMicrophoneEntity("speaker_1", g_iMonitorMicSpeaker1EntRef);
    if (mic1 == -1)
        return;

    float sourcePos[3];
    float sourceAng[3];
    if (!TryResolveMonitorAudioSource(sourcePos, sourceAng))
    {
        // Keep microphones enabled at their current map positions until camera source resolves.
        SetMonitorMicrophonesEnabled(true);
        return;
    }

    if (g_bCameraPovMode && IsValidClient(g_iCameraPovTarget))
    {
        sourcePos[2] += 10.0;
    }

    if (mic1 != -1)
    {
        TeleportEntity(mic1, sourcePos, sourceAng, NULL_VECTOR);
        AcceptEntityInput(mic1, "Enable");
    }
}

void HandleCameraPovToggle(const char[] source, int activator)
{
    int arenaIndex = g_iCurrentCameraArenaIndex;
    if (arenaIndex <= 0 && g_iCurrentCameraIndex > 0)
        arenaIndex = ResolveCameraArenaIndex(g_iCurrentCameraIndex);
    if (arenaIndex <= 0 && IsValidClient(activator))
        arenaIndex = g_iPlayerArena[activator];
    if (arenaIndex <= 0 || arenaIndex > g_iArenaCount)
    {
        LogMessage("[MGE camera][WARN] POV %s ignored: invalid arena (camera=%s idx=%d arena=%d)", source, g_sCurrentCameraName, g_iCurrentCameraIndex, g_iCurrentCameraArenaIndex);
        return;
    }

    int players[MAXPLAYERS + 1];
    int count = 0;
    CollectArenaPovPlayers(arenaIndex, players, count);
    LogMessage("[MGE camera] POV %s: arena=%d players=%d mode=%d", source, arenaIndex, count, g_bCameraPovMode ? 1 : 0);

    if (count <= 0)
    {
        ExitCameraPovModeToCamera(g_sCurrentCameraName);
        return;
    }

    int firstValid = FindNextValidPovTarget(players, count, -1);
    if (firstValid == -1)
    {
        LogMessage("[MGE camera][WARN] POV %s: no valid players with eyes attachment in arena=%d", source, arenaIndex);
        ExitCameraPovModeToCamera(g_sCurrentCameraName);
        return;
    }

    if (!g_bCameraPovMode || g_iCameraPovArenaIndex != arenaIndex)
    {
        EnterCameraPovMode(arenaIndex, players[firstValid], firstValid);
        return;
    }

    int nextIndex = FindNextValidPovTarget(players, count, g_iCameraPovListIndex);
    if (nextIndex == -1)
    {
        LogMessage("[MGE camera] POV relay: cycle end, returning to arena camera");
        ExitCameraPovModeToCamera(g_sCurrentCameraName);
        return;
    }

    g_iCameraPovListIndex = nextIndex;
    g_iCameraPovTarget = players[nextIndex];
    LogMessage("[MGE camera] POV relay: switch target to %N (index=%d/%d)", g_iCameraPovTarget, nextIndex, count - 1);
    UpdateCameraPovViewNow();
    UpdateTvTextForCurrentCamera();
    RefreshTvKeyOverlayForCurrentPov();
}

int FindNextValidPovTarget(const int players[MAXPLAYERS + 1], int count, int currentIndex)
{
    for (int i = currentIndex + 1; i < count; i++)
    {
        int player = players[i];
        if (IsPovAttachTargetValid(player))
            return i;
    }
    return -1;
}

bool IsPovAttachTargetValid(int client)
{
    if (!IsValidClient(client))
        return false;

    return (LookupEntityAttachment(client, "head") > 0);
}

public void OnFightButtonPressed(const char[] output, int caller, int activator, float delay)
{
    if (!IsValidEntity(caller))
        return;

    char buttonName[64];
    GetEntPropString(caller, Prop_Data, "m_iName", buttonName, sizeof(buttonName));
    if (!StrEqual(buttonName, "button_fight", false))
        return;

    if (!IsValidClient(activator) || IsFakeClient(activator))
        return;

    FakeClientCommand(activator, "add");
}

public void OnTriggerMultipleStartTouchOutput(const char[] output, int caller, int activator, float delay)
{
    int trigger = ResolveOutputEntity(caller);
    if (trigger == -1)
        return;
    if (!IsValidClient(activator) || IsFakeClient(activator))
        return;

    char triggerName[64];
    GetEntPropString(trigger, Prop_Data, "m_iName", triggerName, sizeof(triggerName));
    if (!StrEqual(triggerName, "trigger_monitor", false))
        return;

    float now = GetGameTime();
    if (g_fMonitorHintNextAt[activator] > now)
        return;
    g_fMonitorHintNextAt[activator] = now + MONITOR_HINT_COOLDOWN;

    QueryClientConVar(activator, "cl_drawmonitors", OnQueryClientDrawMonitors, GetClientUserId(activator));
}

public void OnQueryClientDrawMonitors(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
    #pragma unused cookie
    #pragma unused client
    #pragma unused cvarName

    int target = GetClientOfUserId(data);
    if (!IsValidClient(target) || IsFakeClient(target))
        return;
    if (result == ConVarQuery_Okay && StringToInt(cvarValue) != 0)
        return;

    SetHudTextParams(-1.0, 0.43, 3.0, 255, 80, 80, 255);
    ShowHudText(target, -1, "%t", "EnableDrawMonitorsCenter");
    PrintCenterText(target, "%t", "EnableDrawMonitorsCenter");
}

int ResolveCameraArenaIndex(int cameraIndex)
{
    if (cameraIndex >= 1 && cameraIndex <= g_iArenaCount)
        return cameraIndex;

    return 0;
}

int ResolveCameraArenaIndexFromEntity(int cameraEntity, int cameraIndex)
{
    // First try geometric mapping camera->closest arena spawn.
    if (IsValidEntity(cameraEntity))
    {
        float camOrigin[3];
        GetEntPropVector(cameraEntity, Prop_Data, "m_vecOrigin", camOrigin);

        int bestArena = 0;
        float bestDistance = 99999999.0;

        for (int arena = 1; arena <= g_iArenaCount; arena++)
        {
            for (int spawn = 1; spawn <= g_iArenaSpawns[arena]; spawn++)
            {
                float dist = GetVectorDistance(camOrigin, g_fArenaSpawnOrigin[arena][spawn]);
                if (dist < bestDistance)
                {
                    bestDistance = dist;
                    bestArena = arena;
                }
            }
        }

        if (bestArena > 0)
            return bestArena;
    }

    // Fallback to camera naming convention.
    int byIndex = ResolveCameraArenaIndex(cameraIndex);
    if (byIndex > 0)
        return byIndex;

    // Legacy fallback for maps that use sg_camera_0 for arena 1.
    if ((cameraIndex + 1) >= 1 && (cameraIndex + 1) <= g_iArenaCount)
        return cameraIndex + 1;

    return 0;
}

void CollectArenaPovPlayers(int arenaIndex, int players[MAXPLAYERS + 1], int &count)
{
    count = 0;

    int maxSlot = g_bArenaNoFight[arenaIndex] ? MAXPLAYERS : (g_bFourPersonArena[arenaIndex] ? SLOT_FOUR : SLOT_TWO);
    if (maxSlot > MAXPLAYERS)
        maxSlot = MAXPLAYERS;

    for (int slot = SLOT_ONE; slot <= maxSlot; slot++)
    {
        int player = g_iArenaQueue[arenaIndex][slot];
        if (!IsValidClient(player))
            continue;
        if (g_iPlayerArena[player] != arenaIndex)
            continue;

        players[count++] = player;
        if (count >= MAXPLAYERS)
            break;
    }
}

void ResetPovForArenaAfterMatch(int arenaIndex)
{
    if (!g_bCameraPovMode || g_iCameraPovArenaIndex != arenaIndex)
        return;

    int previousTarget = g_iCameraPovTarget;

    // Force a fresh reattach after duel transition.
    g_iCameraPovAttachedTargetSpectate = 0;
    g_iCameraPovAttachedTargetArenaCam = 0;

    int players[MAXPLAYERS + 1];
    int count = 0;
    CollectArenaPovPlayers(arenaIndex, players, count);

    if (count <= 0)
    {
        LogMessage("[MGE camera] POV reset after match: no players in arena=%d, restoring arena camera", arenaIndex);
        ExitCameraPovModeToCamera(g_sCurrentCameraName);
        return;
    }

    int selectedIndex = -1;
    if (IsValidClient(previousTarget) && g_iPlayerArena[previousTarget] == arenaIndex && IsPovAttachTargetValid(previousTarget))
    {
        for (int i = 0; i < count; i++)
        {
            if (players[i] == previousTarget)
            {
                selectedIndex = i;
                break;
            }
        }
    }

    if (selectedIndex == -1)
        selectedIndex = FindNextValidPovTarget(players, count, -1);

    if (selectedIndex == -1)
    {
        LogMessage("[MGE camera] POV reset after match: no valid POV target in arena=%d, restoring arena camera", arenaIndex);
        ExitCameraPovModeToCamera(g_sCurrentCameraName);
        return;
    }

    g_iCameraPovListIndex = selectedIndex;
    g_iCameraPovTarget = players[selectedIndex];

    UpdateCameraPovViewNow();
    UpdateTvTextForCurrentCamera();
    RefreshTvKeyOverlayForCurrentPov();
    UpdateMonitorMicrophonesPlacement();

    if (g_iCameraPovTarget != previousTarget)
        LogMessage("[MGE camera] POV reset after match: switched target to %N (arena=%d)", g_iCameraPovTarget, arenaIndex);
    else
        LogMessage("[MGE camera] POV reset after match: reattached target %N (arena=%d)", g_iCameraPovTarget, arenaIndex);
}

void EnterCameraPovMode(int arenaIndex, int target, int listIndex)
{
    g_bCameraPovMode = true;
    g_iCameraPovArenaIndex = arenaIndex;
    g_iCameraPovTarget = target;
    g_iCameraPovListIndex = listIndex;
    g_bCameraPovCameraPoseSaved = false;
    g_iCameraPovMovedCameraEnt = -1;
    g_iCameraPovAttachedTargetSpectate = 0;
    g_iCameraPovAttachedTargetArenaCam = 0;

    int activeArenaCam = GetCachedEntityByTargetName("point_camera", g_sCurrentCameraName);
    if (activeArenaCam != -1)
    {
        GetEntPropVector(activeArenaCam, Prop_Data, "m_vecOrigin", g_fCameraPovSavedOrigin);
        GetEntPropVector(activeArenaCam, Prop_Data, "m_angRotation", g_fCameraPovSavedAngles);
        g_iCameraPovMovedCameraEnt = activeArenaCam;
        g_bCameraPovCameraPoseSaved = true;
        AcceptEntityInput(activeArenaCam, "ClearParent");
        LogMessage("[MGE camera] POV ON: saved active camera pose (%s ent=%d)", g_sCurrentCameraName, activeArenaCam);
    }

    int spectateCam = GetCameraSpectateEntity();
    if (spectateCam != -1)
    {
        AcceptEntityInput(spectateCam, "ClearParent");
        SetVariantString("1");
        AcceptEntityInput(spectateCam, "SetOnAndTurnOthersOff");
        AcceptEntityInput(spectateCam, "Enable");
        LogMessage("[MGE camera] POV ON: arena=%d target=%N index=%d spectate_ent=%d", arenaIndex, target, listIndex, spectateCam);
    }
    else
    {
        LogMessage("[MGE camera][WARN] POV ON failed: point_camera camera_spectate not found");
    }

    delete g_hCameraPovFollowTimer;
    g_hCameraPovFollowTimer = CreateTimer(0.05, Timer_UpdateCameraPovFollow, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    UpdateCameraPovViewNow();
    UpdateTvTextForCurrentCamera();
    RefreshTvKeyOverlayForCurrentPov();
    UpdateMonitorMicrophonesPlacement();
}

void ExitCameraPovModeToCamera(const char[] restoreCameraName, bool fromPovFollowTimer = false)
{
    if (!g_bCameraPovMode && g_hCameraPovFollowTimer == null)
        return;

    g_bCameraPovMode = false;
    g_iCameraPovTarget = 0;
    g_iCameraPovArenaIndex = 0;
    g_iCameraPovListIndex = -1;
    if (g_hCameraPovFollowTimer != null)
    {
        if (fromPovFollowTimer)
            g_hCameraPovFollowTimer = null;
        else
            delete g_hCameraPovFollowTimer;
    }

    int spectateCam = GetCameraSpectateEntity();
    if (spectateCam != -1)
    {
        AcceptEntityInput(spectateCam, "ClearParent");
        AcceptEntityInput(spectateCam, "Disable");
    }

    if (g_bCameraPovCameraPoseSaved && g_iCameraPovMovedCameraEnt != -1 && IsValidEntity(g_iCameraPovMovedCameraEnt))
    {
        AcceptEntityInput(g_iCameraPovMovedCameraEnt, "ClearParent");
        TeleportEntity(g_iCameraPovMovedCameraEnt, g_fCameraPovSavedOrigin, g_fCameraPovSavedAngles, NULL_VECTOR);
        LogMessage("[MGE camera] POV OFF: restored saved pose for ent=%d", g_iCameraPovMovedCameraEnt);
    }
    g_bCameraPovCameraPoseSaved = false;
    g_iCameraPovMovedCameraEnt = -1;
    g_iCameraPovAttachedTargetSpectate = 0;
    g_iCameraPovAttachedTargetArenaCam = 0;

    int arenaCam = GetCachedEntityByTargetName("point_camera", restoreCameraName);
    if (arenaCam != -1)
    {
        SetVariantString("1");
        AcceptEntityInput(arenaCam, "SetOnAndTurnOthersOff");
        AcceptEntityInput(arenaCam, "Enable");
        LogMessage("[MGE camera] POV OFF: restored camera=%s ent=%d", restoreCameraName, arenaCam);
    }
    else
    {
        LogMessage("[MGE camera][WARN] POV OFF: restore camera not found (%s)", restoreCameraName);
    }

    UpdateTvTextForCurrentCamera();
    RefreshTvKeyOverlayForCurrentPov();
    UpdateMonitorMicrophonesPlacement();
}

Action Timer_UpdateCameraPovFollow(Handle timer)
{
    if (!g_bCameraPovMode)
    {
        if (g_hCameraPovFollowTimer == timer)
            g_hCameraPovFollowTimer = null;
        return Plugin_Stop;
    }

    if (!IsValidClient(g_iCameraPovTarget) || g_iPlayerArena[g_iCameraPovTarget] != g_iCameraPovArenaIndex || !IsPovAttachTargetValid(g_iCameraPovTarget))
    {
        int players[MAXPLAYERS + 1];
        int count = 0;
        CollectArenaPovPlayers(g_iCameraPovArenaIndex, players, count);
        int nextIndex = FindNextValidPovTarget(players, count, g_iCameraPovListIndex);
        if (nextIndex == -1)
        {
            LogMessage("[MGE camera] POV target invalid and no next valid target, exiting POV");
            ExitCameraPovModeToCamera(g_sCurrentCameraName, true);
            return Plugin_Stop;
        }

        g_iCameraPovListIndex = nextIndex;
        g_iCameraPovTarget = players[nextIndex];
        LogMessage("[MGE camera] POV auto-skip invalid target, switched to %N", g_iCameraPovTarget);
        UpdateTvTextForCurrentCamera();
        RefreshTvKeyOverlayForCurrentPov();
    }

    UpdateCameraPovViewNow();
    return Plugin_Continue;
}

void UpdateCameraPovViewNow()
{
    int spectateCam = GetCameraSpectateEntity();
    if (!IsValidClient(g_iCameraPovTarget) || !IsPovAttachTargetValid(g_iCameraPovTarget))
        return;

    // Keep spectate camera forced as active while POV mode is enabled.
    if (g_bCameraPovMode && spectateCam != -1)
    {
        EnsureCameraAttachedToEyes(spectateCam, g_iCameraPovTarget, g_iCameraPovAttachedTargetSpectate);
        SetVariantString("1");
        AcceptEntityInput(spectateCam, "SetOnAndTurnOthersOff");
        AcceptEntityInput(spectateCam, "Enable");
    }

    if (g_bCameraPovMode && g_iCameraPovMovedCameraEnt != -1 && IsValidEntity(g_iCameraPovMovedCameraEnt))
    {
        EnsureCameraAttachedToEyes(g_iCameraPovMovedCameraEnt, g_iCameraPovTarget, g_iCameraPovAttachedTargetArenaCam);
        // Compatibility path: some func_monitor setups are hard-bound to sg_camera_N.
        SetVariantString("1");
        AcceptEntityInput(g_iCameraPovMovedCameraEnt, "SetOnAndTurnOthersOff");
        AcceptEntityInput(g_iCameraPovMovedCameraEnt, "Enable");
    }

    UpdateMonitorMicrophonesPlacement();
}

void EnsureCameraAttachedToEyes(int cameraEnt, int target, int &attachedTarget)
{
    if (cameraEnt == -1 || !IsValidEntity(cameraEnt) || !IsValidClient(target))
        return;

    char className[64];
    GetEntityClassname(cameraEnt, className, sizeof(className));
    if (!StrEqual(className, "point_camera", false))
    {
        LogMessage("[MGE camera][WARN] POV attach skipped: ent=%d class=%s target=%N", cameraEnt, className, target);
        return;
    }

    if (attachedTarget == target)
        return;

    if (!IsPovAttachTargetValid(target))
    {
        LogMessage("[MGE camera][WARN] POV attach skipped: target=%N has no head attachment", target);
        return;
    }

    float headPos[3];
    float headAng[3];
    GetClientEyePosition(target, headPos);
    GetClientEyeAngles(target, headAng);
    TeleportEntity(cameraEnt, headPos, headAng, NULL_VECTOR);

    AcceptEntityInput(cameraEnt, "ClearParent");
    SetVariantString("!activator");
    AcceptEntityInput(cameraEnt, "SetParent", target, target);
    SetVariantString("head");
    AcceptEntityInput(cameraEnt, "SetParentAttachment", target, target);
    attachedTarget = target;
    LogMessage("[MGE camera] POV attach: cam_ent=%d -> target=%N attachment=head", cameraEnt, target);
}

int GetCameraSpectateEntity()
{
    if (g_iCameraSpectateEntity != -1 && IsValidEntity(g_iCameraSpectateEntity))
        return g_iCameraSpectateEntity;

    g_iCameraSpectateEntity = FindEntityByTargetName("point_camera", "camera_spectate");
    return g_iCameraSpectateEntity;
}

int ResolveOutputEntity(int entityOrRef)
{
    if (entityOrRef > 0 && IsValidEntity(entityOrRef))
        return entityOrRef;

    int ent = EntRefToEntIndex(entityOrRef);
    if (ent > 0 && IsValidEntity(ent))
        return ent;

    return -1;
}

bool ForceActivateCameraByName(const char[] cameraName, int &cameraEntity)
{
    cameraEntity = FindEntityByTargetName("point_camera", cameraName);
    if (cameraEntity == -1)
        return false;

    SetVariantString("1");
    AcceptEntityInput(cameraEntity, "SetOnAndTurnOthersOff");
    AcceptEntityInput(cameraEntity, "Enable");
    return true;
}

bool ParseCameraIndex(const char[] cameraName, int &cameraIndex)
{
    cameraIndex = 0;

    if (StrContains(cameraName, "sg_camera_", false) != 0)
        return false;

    int start = strlen("sg_camera_");
    if (cameraName[start] == '\0')
        return false;

    for (int i = start; cameraName[i] != '\0'; i++)
    {
        if (!IsCharNumeric(cameraName[i]))
            return false;
    }

    char indexBuf[16];
    strcopy(indexBuf, sizeof(indexBuf), cameraName[start]);
    cameraIndex = StringToInt(indexBuf);
    return true;
}

void UpdateTvTextForCurrentCamera()
{
    if (!IsMapWorldTextEnabled())
        return;

    if (ShouldSuppressTvTextForCurrentCamera())
    {
        ClearTvTextWorldtext();
        return;
    }

    int arenaIndex = g_iCurrentCameraArenaIndex;
    if (arenaIndex <= 0 || arenaIndex > g_iArenaCount)
        return;

    int red = 0;
    int blu = 0;
    GetTvPlayersForArena(arenaIndex, red, blu);

    char versusText[192];
    BuildTvArenaHeader(arenaIndex, versusText, sizeof(versusText));

    if (!StrEqual(versusText, g_sLastTvText))
    {
        SetMapTextByTargetName("tv_text", versusText);
        strcopy(g_sLastTvText, sizeof(g_sLastTvText), versusText);
    }

    char scoreLine1[192];
    char scoreLine2[192];
    BuildTvScoreLine(red, arenaIndex, g_iArenaScore[arenaIndex][SLOT_ONE], scoreLine1, sizeof(scoreLine1));
    BuildTvScoreLine(blu, arenaIndex, g_iArenaScore[arenaIndex][SLOT_TWO], scoreLine2, sizeof(scoreLine2));
    SetMapTextByTargetName("tv_text_score_1", scoreLine1);
    SetMapTextByTargetName("tv_text_score_2", scoreLine2);

    ApplyTvTextVisibility();
}

void ClearTvTextWorldtext()
{
    SetMapTextByTargetName("tv_text", "");
    SetMapTextByTargetName("tv_text_score_1", "");
    SetMapTextByTargetName("tv_text_score_2", "");
    g_sLastTvText[0] = '\0';
    ApplyTvTextVisibility();
}

bool ShouldSuppressTvTextForCurrentCamera()
{
    if (g_sCurrentCameraName[0] == '\0')
        return false;

    int cameraEnt = GetCachedEntityByTargetName("point_camera", g_sCurrentCameraName);
    if (cameraEnt == -1 || !IsValidEntity(cameraEnt))
        return false;

    float cameraOrigin[3];
    GetEntPropVector(cameraEnt, Prop_Data, "m_vecOrigin", cameraOrigin);

    const float maxDistance = 128.0;
    if (IsPointNearNamedEntity(cameraOrigin, "spawn_cam_1", maxDistance))
        return true;
    if (IsPointNearNamedEntity(cameraOrigin, "spawn_cam_2", maxDistance))
        return true;

    return false;
}

bool IsPointNearNamedEntity(float point[3], const char[] targetName, float maxDistance)
{
    int maxEntities = GetMaxEntities();
    char nameBuf[64];
    float entityOrigin[3];

    for (int entity = MaxClients + 1; entity <= maxEntities; entity++)
    {
        if (!IsValidEntity(entity))
            continue;

        GetEntPropString(entity, Prop_Data, "m_iName", nameBuf, sizeof(nameBuf));
        if (!StrEqual(nameBuf, targetName, false))
            continue;

        GetEntPropVector(entity, Prop_Data, "m_vecOrigin", entityOrigin);
        if (GetVectorDistance(point, entityOrigin) <= maxDistance)
            return true;
    }

    return false;
}

void BuildTvScoreLine(int player, int arenaIndex, int score, char[] output, int outputSize)
{
    if (!IsValidClient(player) || g_iPlayerArena[player] != arenaIndex)
    {
        strcopy(output, outputSize, "---");
        return;
    }

    int overall = g_iPlayerRating[player];
    int matchup = 1500;
    GetPlayerTvRatings(player, overall, matchup);

    char nameRaw[MAX_NAME_LENGTH];
    char nameAscii[MAX_NAME_LENGTH * 2];
    GetClientName(player, nameRaw, sizeof(nameRaw));
    TransliterateToAscii(nameRaw, nameAscii, sizeof(nameAscii));

    char povPrefix[8];
    povPrefix[0] = '\0';
    if (g_bCameraPovMode && player == g_iCameraPovTarget)
        strcopy(povPrefix, sizeof(povPrefix), "[POV] ");

    Format(output, outputSize, "%s%s (%d, CvC: %d): %d", povPrefix, nameAscii, overall, matchup, score);
}

void BuildTvArenaHeader(int arenaIndex, char[] output, int outputSize)
{
    char arenaName[64];
    int fraglimit;
    bool is2v2, isBball;
    GetArenaBasicInfo(arenaIndex, arenaName, sizeof(arenaName), fraglimit, is2v2, isBball);

    char header[192];
    FormatArenaHeader(arenaName, fraglimit, isBball, false, g_iArenaStatus[arenaIndex], header, sizeof(header));

    if (g_iArenaStatus[arenaIndex] == AS_FIGHT && g_iArenaDuelStartTime[arenaIndex] > 0)
    {
        int currentTime = GetTime();
        int elapsedTime = currentTime - g_iArenaDuelStartTime[arenaIndex];
        int minutes = elapsedTime / 60;
        int seconds = elapsedTime % 60;

        char timerText[32];
        Format(timerText, sizeof(timerText), " [%02d:%02d]", minutes, seconds);
        StrCat(header, sizeof(header), timerText);
    }

    TransliterateToAscii(header, output, outputSize);
}

void GetPlayerTvRatings(int player, int &overall, int &matchup)
{
    overall = g_iPlayerRating[player];
    matchup = 1500;

    int arenaIndex = g_iPlayerArena[player];
    if (arenaIndex <= 0)
        return;

    int classId = view_as<int>(g_tfctPlayerClass[player]);
    if (classId < 1 || classId > 9)
        classId = view_as<int>(TF2_GetPlayerClass(player));

    if (classId < 1 || classId > 9)
        return;

    int playerSlot = g_iPlayerSlot[player];
    int opponent = 0;
    if (playerSlot == SLOT_ONE || playerSlot == SLOT_THREE)
        opponent = g_iArenaQueue[arenaIndex][SLOT_TWO];
    else
        opponent = g_iArenaQueue[arenaIndex][SLOT_ONE];

    if (!IsValidClient(opponent) || g_iPlayerArena[opponent] != arenaIndex)
        return;

    int oppClassId = view_as<int>(g_tfctPlayerClass[opponent]);
    if (oppClassId < 1 || oppClassId > 9)
        oppClassId = view_as<int>(TF2_GetPlayerClass(opponent));

    if (oppClassId < 1 || oppClassId > 9)
        return;

    int stored = g_iPlayerClassRating[player][classId][oppClassId];
    matchup = (stored > 0) ? stored : 1500;
}

bool IsValidArenaPlayerForTv(int client, int arenaIndex)
{
    if (!IsValidClient(client))
        return false;
    if (g_iPlayerArena[client] != arenaIndex)
        return false;
    return true;
}

void GetTvPlayersForArena(int arenaIndex, int &red, int &blu)
{
    red = 0;
    blu = 0;

    int maxSlot = g_bArenaNoFight[arenaIndex] ? MaxClients : (g_bFourPersonArena[arenaIndex] ? SLOT_FOUR : SLOT_TWO);
    if (maxSlot > MAXPLAYERS)
        maxSlot = MAXPLAYERS;

    for (int slot = SLOT_ONE; slot <= maxSlot; slot++)
    {
        int player = g_iArenaQueue[arenaIndex][slot];
        if (!IsValidArenaPlayerForTv(player, arenaIndex))
            continue;

        bool isRed = (slot == SLOT_ONE || slot == SLOT_THREE);
        if (g_bArenaNoFight[arenaIndex])
            isRed = ((slot % 2) == 1);

        if (isRed)
        {
            if (red == 0)
                red = player;
        }
        else
        {
            if (blu == 0)
                blu = player;
        }

        if (red != 0 && blu != 0)
            return;
    }
}

void ApplyTvTextVisibility()
{
    int alpha = g_bTvTextVisible ? 255 : 0;
    SetMapTextAlphaByTargetName("tv_text", alpha);
    SetMapTextAlphaByTargetName("tv_text_score_1", alpha);
    SetMapTextAlphaByTargetName("tv_text_score_2", alpha);
}

void SetMapTextAlphaByTargetName(const char[] targetName, int alpha)
{
    SetMapTextColorByTargetName(targetName, 255, 255, 255, alpha);
}

void SetMapTextColorByTargetName(const char[] targetName, int red, int green, int blue, int alpha)
{
    int entity = GetCachedEntityByTargetName("point_worldtext", targetName);
    if (entity == -1)
        return;

    char color[32];
    Format(color, sizeof(color), "%d %d %d %d", red, green, blue, alpha);
    DispatchKeyValue(entity, "color", color);
    SetVariantString(color);
    AcceptEntityInput(entity, "SetColor");
}

int GetCachedEntityByTargetName(const char[] classname, const char[] targetName)
{
    if (targetName[0] == '\0')
        return -1;

    if (g_smNamedEntityCache == null)
        g_smNamedEntityCache = new StringMap();

    char cacheKey[128];
    Format(cacheKey, sizeof(cacheKey), "%s|%s", classname, targetName);

    int entRef = INVALID_ENT_REFERENCE;
    if (g_smNamedEntityCache.GetValue(cacheKey, entRef))
    {
        int cached = EntRefToEntIndex(entRef);
        if (cached > MaxClients && IsValidEntity(cached))
            return cached;

        g_smNamedEntityCache.Remove(cacheKey);
    }

    int entity = FindEntityByTargetName(classname, targetName);
    if (entity != -1)
        g_smNamedEntityCache.SetValue(cacheKey, EntIndexToEntRef(entity), true);

    return entity;
}

int FindEntityByTargetName(const char[] classname, const char[] targetName)
{
    int entity = -1;
    char nameBuf[64];

    while ((entity = FindEntityByClassname(entity, classname)) != -1)
    {
        if (!IsValidEntity(entity))
            continue;

        GetEntPropString(entity, Prop_Data, "m_iName", nameBuf, sizeof(nameBuf));
        if (StrEqual(nameBuf, targetName, false))
            return entity;
    }

    return -1;
}

void SetMapTextByTargetName(const char[] targetName, const char[] rawText)
{
    int entity = GetCachedEntityByTargetName("point_worldtext", targetName);
    if (entity == -1)
        return;

    DispatchKeyValue(entity, "message", rawText);
    SetVariantString(rawText);
    AcceptEntityInput(entity, "SetText");
    SetVariantString(rawText);
    AcceptEntityInput(entity, "SetMessage");
}

void AppendAsciiString(char[] output, int maxlen, int &outPos, const char[] repl)
{
    for (int j = 0; repl[j] != '\0' && outPos < maxlen - 1; j++)
        output[outPos++] = repl[j];
}

void TransliterateToAscii(const char[] input, char[] output, int maxlen)
{
    int outPos = 0;
    int inLen = strlen(input);

    for (int i = 0; i < inLen && outPos < maxlen - 1; i++)
    {
        int c = input[i] & 0xFF;

        if (c < 0x80)
        {
            output[outPos++] = c;
            continue;
        }

        if (i + 1 >= inLen)
            break;

        int n = input[i + 1] & 0xFF;
        bool mapped = true;

        if (c == 0xD0)
        {
            switch (n)
            {
                case 0x81: AppendAsciiString(output, maxlen, outPos, "Yo");
                case 0x84: AppendAsciiString(output, maxlen, outPos, "Ye");
                case 0x86: AppendAsciiString(output, maxlen, outPos, "I");
                case 0x87: AppendAsciiString(output, maxlen, outPos, "Yi");
                case 0x90: AppendAsciiString(output, maxlen, outPos, "A");
                case 0x91: AppendAsciiString(output, maxlen, outPos, "B");
                case 0x92: AppendAsciiString(output, maxlen, outPos, "V");
                case 0x93: AppendAsciiString(output, maxlen, outPos, "G");
                case 0x94: AppendAsciiString(output, maxlen, outPos, "D");
                case 0x95: AppendAsciiString(output, maxlen, outPos, "E");
                case 0x96: AppendAsciiString(output, maxlen, outPos, "Zh");
                case 0x97: AppendAsciiString(output, maxlen, outPos, "Z");
                case 0x98: AppendAsciiString(output, maxlen, outPos, "I");
                case 0x99: AppendAsciiString(output, maxlen, outPos, "Y");
                case 0x9A: AppendAsciiString(output, maxlen, outPos, "K");
                case 0x9B: AppendAsciiString(output, maxlen, outPos, "L");
                case 0x9C: AppendAsciiString(output, maxlen, outPos, "M");
                case 0x9D: AppendAsciiString(output, maxlen, outPos, "N");
                case 0x9E: AppendAsciiString(output, maxlen, outPos, "O");
                case 0x9F: AppendAsciiString(output, maxlen, outPos, "P");
                case 0xA0: AppendAsciiString(output, maxlen, outPos, "R");
                case 0xA1: AppendAsciiString(output, maxlen, outPos, "S");
                case 0xA2: AppendAsciiString(output, maxlen, outPos, "T");
                case 0xA3: AppendAsciiString(output, maxlen, outPos, "U");
                case 0xA4: AppendAsciiString(output, maxlen, outPos, "F");
                case 0xA5: AppendAsciiString(output, maxlen, outPos, "Kh");
                case 0xA6: AppendAsciiString(output, maxlen, outPos, "Ts");
                case 0xA7: AppendAsciiString(output, maxlen, outPos, "Ch");
                case 0xA8: AppendAsciiString(output, maxlen, outPos, "Sh");
                case 0xA9: AppendAsciiString(output, maxlen, outPos, "Sch");
                case 0xAA: AppendAsciiString(output, maxlen, outPos, "");
                case 0xAB: AppendAsciiString(output, maxlen, outPos, "Y");
                case 0xAC: AppendAsciiString(output, maxlen, outPos, "");
                case 0xAD: AppendAsciiString(output, maxlen, outPos, "E");
                case 0xAE: AppendAsciiString(output, maxlen, outPos, "Yu");
                case 0xAF: AppendAsciiString(output, maxlen, outPos, "Ya");
                case 0xB0: AppendAsciiString(output, maxlen, outPos, "a");
                case 0xB1: AppendAsciiString(output, maxlen, outPos, "b");
                case 0xB2: AppendAsciiString(output, maxlen, outPos, "v");
                case 0xB3: AppendAsciiString(output, maxlen, outPos, "g");
                case 0xB4: AppendAsciiString(output, maxlen, outPos, "d");
                case 0xB5: AppendAsciiString(output, maxlen, outPos, "e");
                case 0xB6: AppendAsciiString(output, maxlen, outPos, "zh");
                case 0xB7: AppendAsciiString(output, maxlen, outPos, "z");
                case 0xB8: AppendAsciiString(output, maxlen, outPos, "i");
                case 0xB9: AppendAsciiString(output, maxlen, outPos, "y");
                case 0xBA: AppendAsciiString(output, maxlen, outPos, "k");
                case 0xBB: AppendAsciiString(output, maxlen, outPos, "l");
                case 0xBC: AppendAsciiString(output, maxlen, outPos, "m");
                case 0xBD: AppendAsciiString(output, maxlen, outPos, "n");
                case 0xBE: AppendAsciiString(output, maxlen, outPos, "o");
                case 0xBF: AppendAsciiString(output, maxlen, outPos, "p");
                default: mapped = false;
            }
        }
        else if (c == 0xD1)
        {
            switch (n)
            {
                case 0x80: AppendAsciiString(output, maxlen, outPos, "r");
                case 0x81: AppendAsciiString(output, maxlen, outPos, "s");
                case 0x82: AppendAsciiString(output, maxlen, outPos, "t");
                case 0x83: AppendAsciiString(output, maxlen, outPos, "u");
                case 0x84: AppendAsciiString(output, maxlen, outPos, "f");
                case 0x85: AppendAsciiString(output, maxlen, outPos, "kh");
                case 0x86: AppendAsciiString(output, maxlen, outPos, "ts");
                case 0x87: AppendAsciiString(output, maxlen, outPos, "ch");
                case 0x88: AppendAsciiString(output, maxlen, outPos, "sh");
                case 0x89: AppendAsciiString(output, maxlen, outPos, "sch");
                case 0x8A: AppendAsciiString(output, maxlen, outPos, "");
                case 0x8B: AppendAsciiString(output, maxlen, outPos, "y");
                case 0x8C: AppendAsciiString(output, maxlen, outPos, "");
                case 0x8D: AppendAsciiString(output, maxlen, outPos, "e");
                case 0x8E: AppendAsciiString(output, maxlen, outPos, "yu");
                case 0x8F: AppendAsciiString(output, maxlen, outPos, "ya");
                case 0x91: AppendAsciiString(output, maxlen, outPos, "yo");
                case 0x94: AppendAsciiString(output, maxlen, outPos, "ye");
                case 0x96: AppendAsciiString(output, maxlen, outPos, "i");
                case 0x97: AppendAsciiString(output, maxlen, outPos, "yi");
                default: mapped = false;
            }
        }
        else if (c == 0xD2)
        {
            switch (n)
            {
                case 0x90: AppendAsciiString(output, maxlen, outPos, "G");
                case 0x91: AppendAsciiString(output, maxlen, outPos, "g");
                default: mapped = false;
            }
        }
        else
        {
            mapped = false;
        }

        if (!mapped && outPos < maxlen - 1)
            output[outPos++] = '?';

        i++;
    }

    output[outPos] = '\0';
}


// ===== UTILITY FUNCTIONS =====

// Convert TF2 class enum to readable string representation
char[] TFClassToString(TFClassType class)
{
    char className[16];
    switch (class)
    {
        case TFClass_Scout: strcopy(className, sizeof(className), "scout");
        case TFClass_Sniper: strcopy(className, sizeof(className), "sniper");
        case TFClass_Soldier: strcopy(className, sizeof(className), "soldier");
        case TFClass_DemoMan: strcopy(className, sizeof(className), "demoman");
        case TFClass_Medic: strcopy(className, sizeof(className), "medic");
        case TFClass_Heavy: strcopy(className, sizeof(className), "heavy");
        case TFClass_Pyro: strcopy(className, sizeof(className), "pyro");
        case TFClass_Spy: strcopy(className, sizeof(className), "spy");
        case TFClass_Engineer: strcopy(className, sizeof(className), "engineer");
        default: strcopy(className, sizeof(className), "unknown");
    }
    return className;
}


// ===== ADMIN COMMANDS =====

int GetSpawnAnnotationId(int client, int index)
{
    return 500000 + (client * 1000) + index;
}

void HideSpawnAnnotationForClient(int client, int annotationId)
{
    if (!IsValidClient(client))
        return;

    Event event = CreateEvent("hide_annotation", true);
    if (event == null)
        return;

    event.SetInt("id", annotationId);
    event.SetInt("visibilityBitfield", 0);
    event.FireToClient(client);
    delete event;
}

void SendSpawnAnnotationToClient(int client, int annotationId, const char[] text, const float origin[3], float lifetime = SPAWN_ANNOTATION_LIFETIME)
{
    if (!IsValidClient(client))
        return;

    Event event = CreateEvent("show_annotation", true);
    if (event == null)
        return;

    event.SetInt("id", annotationId);
    event.SetInt("follow_entindex", 0);
    event.SetInt("visibilityBitfield", 0);
    event.SetFloat("lifetime", lifetime);
    event.SetBool("show_effect", true);
    event.SetFloat("worldPosX", origin[0]);
    event.SetFloat("worldPosY", origin[1]);
    event.SetFloat("worldPosZ", origin[2]);
    event.SetString("text", text);
    event.SetString("play_sound", "");
    event.FireToClient(client);
    delete event;
}

void StopSpawnAnnotationRefresh(int client)
{
    if (g_hSpawnAnnotationRefreshTimer[client] != null)
    {
        delete g_hSpawnAnnotationRefreshTimer[client];
        g_hSpawnAnnotationRefreshTimer[client] = null;
    }
}

void ClearClientSpawnAnnotations(int client, bool hideCurrent)
{
    StopSpawnAnnotationRefresh(client);
    g_bShowSpawnAnnotationsActive[client] = false;

    if (hideCurrent && IsValidClient(client))
    {
        for (int i = 0; i < g_iSpawnAnnotationCount[client]; i++)
        {
            HideSpawnAnnotationForClient(client, GetSpawnAnnotationId(client, i));
        }
    }

    g_iSpawnAnnotationCount[client] = 0;
}

bool AddStoredSpawnAnnotation(int client, int arena, int spawnType, int spawnNumber, const float origin[3])
{
    int index = g_iSpawnAnnotationCount[client];
    if (index >= MAX_SPAWN_ANNOTATIONS)
        return false;

    g_iSpawnAnnotationArena[client][index] = arena;
    g_iSpawnAnnotationType[client][index] = spawnType;
    g_iSpawnAnnotationNumber[client][index] = spawnNumber;
    g_fSpawnAnnotationOrigin[client][index][0] = origin[0];
    g_fSpawnAnnotationOrigin[client][index][1] = origin[1];
    g_fSpawnAnnotationOrigin[client][index][2] = origin[2];
    g_iSpawnAnnotationCount[client] = index + 1;
    return true;
}

bool AddAndShowSpawnAnnotationMarker(int client, int arena, const char[] label, const float origin[3])
{
    int index = g_iSpawnAnnotationCount[client];
    if (index >= MAX_SPAWN_ANNOTATIONS)
        return false;

    g_iSpawnAnnotationArena[client][index] = arena;
    g_iSpawnAnnotationType[client][index] = SPAWN_ANN_TYPE_NEUTRAL;
    g_iSpawnAnnotationNumber[client][index] = 0;
    g_fSpawnAnnotationOrigin[client][index][0] = origin[0];
    g_fSpawnAnnotationOrigin[client][index][1] = origin[1];
    g_fSpawnAnnotationOrigin[client][index][2] = origin[2];
    g_iSpawnAnnotationCount[client] = index + 1;
    SendSpawnAnnotationToClient(client, GetSpawnAnnotationId(client, index), label, origin, SPAWN_ANNOTATION_LIFETIME);
    return true;
}

void BuildStoredSpawnAnnotationText(int client, int index, char[] text, int textLen)
{
    int spawnType = g_iSpawnAnnotationType[client][index];
    int spawnNumber = g_iSpawnAnnotationNumber[client][index];

    char typeName[24];
    switch (spawnType)
    {
        case SPAWN_ANN_TYPE_RED: strcopy(typeName, sizeof(typeName), "RED");
        case SPAWN_ANN_TYPE_BLU: strcopy(typeName, sizeof(typeName), "BLU");
        case SPAWN_ANN_TYPE_BBALL_INTEL: strcopy(typeName, sizeof(typeName), "INTEL");
        case SPAWN_ANN_TYPE_BBALL_INTEL_RED: strcopy(typeName, sizeof(typeName), "INTEL RED");
        case SPAWN_ANN_TYPE_BBALL_INTEL_BLU: strcopy(typeName, sizeof(typeName), "INTEL BLU");
        case SPAWN_ANN_TYPE_BBALL_HOOP: strcopy(typeName, sizeof(typeName), "HOOP");
        case SPAWN_ANN_TYPE_BBALL_HOOP_RED: strcopy(typeName, sizeof(typeName), "HOOP RED");
        case SPAWN_ANN_TYPE_BBALL_HOOP_BLU: strcopy(typeName, sizeof(typeName), "HOOP BLU");
        default: strcopy(typeName, sizeof(typeName), "NEUTRAL");
    }

    if (spawnNumber > 0)
        Format(text, textLen, "%s #%d", typeName, spawnNumber);
    else
        strcopy(text, textLen, typeName);
}

void RebuildArenaSpawnAnnotationsForClient(int client, int arena)
{
    ClearClientSpawnAnnotations(client, true);

    int shownNeutral = 0;
    int shownRed = 0;
    int shownBlu = 0;
    int shownBball = 0;
    int dropped = 0;
    float pos[3];

    for (int i = 1; i <= g_iArenaSpawns[arena]; i++)
    {
        pos[0] = g_fArenaSpawnOrigin[arena][i][0];
        pos[1] = g_fArenaSpawnOrigin[arena][i][1];
        pos[2] = g_fArenaSpawnOrigin[arena][i][2];
        if (!AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_NEUTRAL, i, pos))
        {
            dropped++;
            continue;
        }
        shownNeutral++;
    }

    for (int i = 1; i <= g_iArenaRedSpawns[arena]; i++)
    {
        pos[0] = g_fArenaRedSpawnOrigin[arena][i][0];
        pos[1] = g_fArenaRedSpawnOrigin[arena][i][1];
        pos[2] = g_fArenaRedSpawnOrigin[arena][i][2];
        if (!AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_RED, i, pos))
        {
            dropped++;
            continue;
        }
        shownRed++;
    }

    for (int i = 1; i <= g_iArenaBluSpawns[arena]; i++)
    {
        pos[0] = g_fArenaBluSpawnOrigin[arena][i][0];
        pos[1] = g_fArenaBluSpawnOrigin[arena][i][1];
        pos[2] = g_fArenaBluSpawnOrigin[arena][i][2];
        if (!AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BLU, i, pos))
        {
            dropped++;
            continue;
        }
        shownBlu++;
    }

    if (g_bArenaBBall[arena])
    {
        if (g_bArenaBBallIntelSpawnSet[arena])
        {
            pos[0] = g_fArenaBBallIntelSpawn[arena][0];
            pos[1] = g_fArenaBBallIntelSpawn[arena][1];
            pos[2] = g_fArenaBBallIntelSpawn[arena][2];
            if (AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BBALL_INTEL, 0, pos))
                shownBball++;
            else
                dropped++;
        }

        if (g_bArenaBBallIntelSpawnRedSet[arena])
        {
            pos[0] = g_fArenaBBallIntelSpawnRed[arena][0];
            pos[1] = g_fArenaBBallIntelSpawnRed[arena][1];
            pos[2] = g_fArenaBBallIntelSpawnRed[arena][2];
            if (AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BBALL_INTEL_RED, 0, pos))
                shownBball++;
            else
                dropped++;
        }

        if (g_bArenaBBallIntelSpawnBluSet[arena])
        {
            pos[0] = g_fArenaBBallIntelSpawnBlu[arena][0];
            pos[1] = g_fArenaBBallIntelSpawnBlu[arena][1];
            pos[2] = g_fArenaBBallIntelSpawnBlu[arena][2];
            if (AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BBALL_INTEL_BLU, 0, pos))
                shownBball++;
            else
                dropped++;
        }

        if (g_bArenaBBallHoopSpawnSet[arena])
        {
            pos[0] = g_fArenaBBallHoopSpawn[arena][0];
            pos[1] = g_fArenaBBallHoopSpawn[arena][1];
            pos[2] = g_fArenaBBallHoopSpawn[arena][2];
            if (AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BBALL_HOOP, 0, pos))
                shownBball++;
            else
                dropped++;
        }

        if (g_bArenaBBallHoopSpawnRedSet[arena])
        {
            pos[0] = g_fArenaBBallHoopSpawnRed[arena][0];
            pos[1] = g_fArenaBBallHoopSpawnRed[arena][1];
            pos[2] = g_fArenaBBallHoopSpawnRed[arena][2];
            if (AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BBALL_HOOP_RED, 0, pos))
                shownBball++;
            else
                dropped++;
        }

        if (g_bArenaBBallHoopSpawnBluSet[arena])
        {
            pos[0] = g_fArenaBBallHoopSpawnBlu[arena][0];
            pos[1] = g_fArenaBBallHoopSpawnBlu[arena][1];
            pos[2] = g_fArenaBBallHoopSpawnBlu[arena][2];
            if (AddStoredSpawnAnnotation(client, arena, SPAWN_ANN_TYPE_BBALL_HOOP_BLU, 0, pos))
                shownBball++;
            else
                dropped++;
        }
    }

    char text[128];
    for (int i = 0; i < g_iSpawnAnnotationCount[client]; i++)
    {
        BuildStoredSpawnAnnotationText(client, i, text, sizeof(text));
        SendSpawnAnnotationToClient(client, GetSpawnAnnotationId(client, i), text, g_fSpawnAnnotationOrigin[client][i], SPAWN_ANNOTATION_LIFETIME);
    }

    g_bShowSpawnAnnotationsActive[client] = true;

    int total = shownNeutral + shownRed + shownBlu + shownBball;
    PrintToConsole(client, "[MGE] Arena %d (%s) spawns shown: total=%d, neutral=%d, red=%d, blu=%d, bball=%d, dropped=%d",
        arena, g_sArenaOriginalName[arena], total, shownNeutral, shownRed, shownBlu, shownBball, dropped);
    PrintToChat(client, "[MGE] Arena spawns shown: %d (N %d / R %d / B %d / BB %d). Re-run to refresh/hide previous.",
        total, shownNeutral, shownRed, shownBlu, shownBball);
}

void RefreshArenaSpawnAnnotationsForViewers(int arena)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client) || !g_bShowSpawnAnnotationsActive[client] || g_iSpawnAnnotationCount[client] <= 0)
            continue;

        if (g_iSpawnAnnotationArena[client][0] != arena)
            continue;

        RebuildArenaSpawnAnnotationsForClient(client, arena);
    }
}

Action Command_MgeBballScoreboardDebug(int client, int args)
{
    if (!IsValidClient(client))
    {
        PrintToServer("[MGE] Command is in-game only: sm_mge_bball_scoreboard_debug");
        return Plugin_Handled;
    }

    int arena = 0;
    if (args >= 1)
    {
        char arg[16];
        GetCmdArg(1, arg, sizeof(arg));
        arena = StringToInt(arg);
    }
    else
    {
        arena = g_iPlayerArena[client];
    }

    if (arena <= 0 || arena > g_iArenaCount)
    {
        PrintToConsole(client, "[MGE] Usage: sm_mge_bball_scoreboard_debug <arena> (or join arena and run without args)");
        PrintToChat(client, "[MGE] Invalid arena. Join an arena or pass a valid arena index.");
        return Plugin_Handled;
    }

    if (!g_bArenaBBall[arena])
    {
        PrintToConsole(client, "[MGE] Arena %d (%s) is not BBall.", arena, g_sArenaName[arena]);
        PrintToChat(client, "[MGE] Arena %d is not BBall.", arena);
        return Plugin_Handled;
    }

    ClearClientSpawnAnnotations(client, true);
    CacheBBallScoreboardEntities();

    char mappedMode[4];
    GetBBallScoreboardModeForArena(arena, mappedMode, sizeof(mappedMode));
    PrintToConsole(client, "===== MGE BBall Scoreboard Debug =====");
    PrintToConsole(client, "arena=%d name=%s type=%s mapped_mode=%s", arena, g_sArenaName[arena], g_bFourPersonArena[arena] ? "2v2" : "1v1", mappedMode);

    static const char labels[][] =
    {
        "timer_m10",
        "timer_m1",
        "timer_s10",
        "timer_s1",
        "red_10",
        "red_1",
        "blue_10",
        "blue_1"
    };

    int foundCached = 0;
    int missingCached = 0;
    int dropped = 0;

    for (int i = 0; i < sizeof(labels); i++)
    {
        int entRef = INVALID_ENT_REFERENCE;
        switch (i)
        {
            case 0: entRef = g_iBBallTimerEntRef[arena][BBALL_TIMER_MIN_TENS];
            case 1: entRef = g_iBBallTimerEntRef[arena][BBALL_TIMER_MIN_ONES];
            case 2: entRef = g_iBBallTimerEntRef[arena][BBALL_TIMER_SEC_TENS];
            case 3: entRef = g_iBBallTimerEntRef[arena][BBALL_TIMER_SEC_ONES];
            case 4: entRef = g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_RED][BBALL_SCORE_TENS];
            case 5: entRef = g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_RED][BBALL_SCORE_ONES];
            case 6: entRef = g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_BLU][BBALL_SCORE_TENS];
            case 7: entRef = g_iBBallScoreEntRef[arena][BBALL_SCORE_TEAM_BLU][BBALL_SCORE_ONES];
        }

        int entity = EntRefToEntIndex(entRef);
        if (entity > MaxClients && IsValidEntity(entity))
        {
            char classname[64];
            char targetName[64];
            float pos[3];
            GetEntityClassname(entity, classname, sizeof(classname));
            GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
            GetEntPropVector(entity, Prop_Data, "m_vecOrigin", pos);

            float distSqr = GetArenaClosestSpawnDistSqr(arena, pos);
            float dist = (distSqr >= 0.0) ? SquareRoot(distSqr) : -1.0;

            PrintToConsole(client, "[cached] %s ent=%d class=%s target=%s dist=%.1f pos=(%.1f %.1f %.1f)",
                labels[i], entity, classname, targetName, dist, pos[0], pos[1], pos[2]);

            if (!AddAndShowSpawnAnnotationMarker(client, arena, labels[i], pos))
                dropped++;

            foundCached++;
        }
        else
        {
            PrintToConsole(client, "[cached] %s MISSING (entref=%d)", labels[i], entRef);
            missingCached++;
        }
    }

    int listedCandidates = 0;
    int markedCandidates = 0;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "env_texturetoggle")) != -1)
    {
        if (!IsValidEntity(entity))
            continue;

        char targetName[64];
        GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
        bool isTimer = (StrContains(targetName, "skin_bball_count_", false) == 0);
        bool isScore = (StrContains(targetName, "skin_count_bball_", false) == 0);
        if (!isTimer && !isScore)
            continue;

        char classname[64];
        float pos[3];
        GetEntityClassname(entity, classname, sizeof(classname));
        GetEntPropVector(entity, Prop_Data, "m_vecOrigin", pos);
        float distSqr = GetArenaClosestSpawnDistSqr(arena, pos);
        float dist = (distSqr >= 0.0) ? SquareRoot(distSqr) : -1.0;

        PrintToConsole(client, "[scan] ent=%d class=%s target=%s dist=%.1f pos=(%.1f %.1f %.1f)",
            entity, classname, targetName, dist, pos[0], pos[1], pos[2]);
        listedCandidates++;

        if (dist >= 0.0 && dist <= 3000.0)
        {
            if (AddAndShowSpawnAnnotationMarker(client, arena, targetName, pos))
                markedCandidates++;
            else
                dropped++;
        }
    }

    PrintToConsole(client, "[MGE] BBall scoreboard debug summary: cached_found=%d cached_missing=%d scanned=%d markers=%d dropped=%d",
        foundCached, missingCached, listedCandidates, g_iSpawnAnnotationCount[client], dropped);
    PrintToChat(client, "[MGE] BBall debug: cached %d/%d, scanned %d, markers %d. Re-run to refresh/hide.", foundCached, foundCached + missingCached, listedCandidates, g_iSpawnAnnotationCount[client]);
    return Plugin_Handled;
}

Action Command_MgeShowSpawns(int client, int args)
{
    if (!IsValidClient(client))
    {
        PrintToServer("[MGE] Command is in-game only: sm_mge_show_spawns");
        return Plugin_Handled;
    }

    int arena = g_iPlayerArena[client];
    if (arena <= 0 || arena > g_iArenaCount)
    {
        PrintToConsole(client, "[MGE] Join an arena first, then run sm_mge_show_spawns.");
        PrintToChat(client, "[MGE] Join an arena first, then run sm_mge_show_spawns.");
        return Plugin_Handled;
    }

    RebuildArenaSpawnAnnotationsForClient(client, arena);
    return Plugin_Handled;
}

// Display client's current position and angles for debugging
Action Command_Loc(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    float vec[3];
    float ang[3];
    GetClientAbsOrigin(client, vec);
    GetClientEyeAngles(client, ang);
    PrintToChat(client, "%.0f %.0f %.0f %.0f", vec[0], vec[1], vec[2], ang[1]);
    return Plugin_Handled;
}

// Test database connection for troubleshooting
Action Command_ConnectionTest(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    char query[256];
    g_DB.Format(query, sizeof(query), "SELECT rating FROM mgemod_stats LIMIT 1");
    g_DB.Query(SQL_OnTestReceived, query, client);

    return Plugin_Handled;
}

Action Command_MgeWorldTextDebug(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    PrintToConsole(client, "===== MGE WorldText Debug =====");
    PrintToConsole(client, "text_mge_top: %s", g_sLastTopMvpText[0] ? g_sLastTopMvpText : "---");

    for (int i = 0; i < 10; i++)
    {
        PrintToConsole(client, "text_mge_top_%d: %d. %s", i + 1, i + 1, g_sTop10WorldTextNames[i]);
    }

    PrintToConsole(client, "tv_text: %s", g_sLastTvText[0] ? g_sLastTvText : "---");
    PrintToConsole(client, "camera: %s (idx=%d, arena=%d)", g_sCurrentCameraName[0] ? g_sCurrentCameraName : "---", g_iCurrentCameraIndex, g_iCurrentCameraArenaIndex);
    PrintToConsole(client, "map_worldtext_enabled: %d", IsMapWorldTextEnabled() ? 1 : 0);

    return Plugin_Handled;
}

Action Command_MgeWorldTextRefresh(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    RequestMapTop10WorldTextData();
    UpdateTopMvpWorldTextIfNeeded(true);
    QueueApplyMapWorldText(1.0);

    PrintToConsole(client, "[MGE] WorldText refresh requested: DB top10 query + delayed apply.");
    return Plugin_Handled;
}

Action Command_MgeCameraDebug(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    PrintToConsole(client, "===== MGE Camera Debug =====");
    PrintToConsole(client, "camera: %s (idx=%d, arena=%d)", g_sCurrentCameraName[0] ? g_sCurrentCameraName : "---", g_iCurrentCameraIndex, g_iCurrentCameraArenaIndex);
    PrintToConsole(client, "pov_mode: %d, pov_target: %d, pov_arena: %d, pov_list_index: %d", g_bCameraPovMode ? 1 : 0, g_iCameraPovTarget, g_iCameraPovArenaIndex, g_iCameraPovListIndex);

    int arenaIndex = g_iCurrentCameraArenaIndex;
    if (arenaIndex <= 0 && g_iCurrentCameraIndex > 0)
        arenaIndex = ResolveCameraArenaIndex(g_iCurrentCameraIndex);

    if (arenaIndex <= 0 || arenaIndex > g_iArenaCount)
    {
        PrintToConsole(client, "arena_from_camera: invalid");
        return Plugin_Handled;
    }

    PrintToConsole(client, "arena_from_camera: %d (%s)", arenaIndex, g_sArenaName[arenaIndex]);

    int players[MAXPLAYERS + 1];
    int count = 0;
    CollectArenaPovPlayers(arenaIndex, players, count);
    PrintToConsole(client, "arena_players: %d", count);

    for (int i = 0; i < count; i++)
    {
        int p = players[i];
        if (!IsValidClient(p))
            continue;

        char pname[MAX_NAME_LENGTH];
        GetClientName(p, pname, sizeof(pname));
        PrintToConsole(client, "  #%d: %N (%s) slot=%d rating=%d", i + 1, p, pname, g_iPlayerSlot[p], g_iPlayerRating[p]);
    }

    return Plugin_Handled;
}

Action Command_MgeCameraSet(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    if (args < 1)
    {
        PrintToConsole(client, "Usage: sm_mge_camera_set <camera_targetname>");
        return Plugin_Handled;
    }

    char cameraName[64];
    GetCmdArg(1, cameraName, sizeof(cameraName));

    int cameraEntity = -1;
    if (!ForceActivateCameraByName(cameraName, cameraEntity))
    {
        PrintToConsole(client, "[MGE camera] Camera not found: %s", cameraName);
        return Plugin_Handled;
    }

    strcopy(g_sCurrentCameraName, sizeof(g_sCurrentCameraName), cameraName);
    g_iCurrentCameraIndex = 0;
    g_iCurrentCameraArenaIndex = 0;
    if (ParseCameraIndex(cameraName, g_iCurrentCameraIndex))
        g_iCurrentCameraArenaIndex = ResolveCameraArenaIndexFromEntity(cameraEntity, g_iCurrentCameraIndex);

    ExitCameraPovModeToCamera(cameraName);
    UpdateTvTextForCurrentCamera();
    UpdateMonitorMicrophonesPlacement();

    PrintToConsole(client, "[MGE camera] Forced camera: %s (ent=%d, idx=%d, arena=%d)", cameraName, cameraEntity, g_iCurrentCameraIndex, g_iCurrentCameraArenaIndex);
    LogMessage("[MGE camera] forced by admin %N: %s (ent=%d, idx=%d, arena=%d)", client, cameraName, cameraEntity, g_iCurrentCameraIndex, g_iCurrentCameraArenaIndex);
    return Plugin_Handled;
}

Action Command_MgeCameraPov(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    HandleCameraPovToggle("cmd", client);
    PrintToConsole(client, "[MGE camera] POV cycle requested.");
    return Plugin_Handled;
}

Action Command_MgeCameraPovOff(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    ExitCameraPovModeToCamera(g_sCurrentCameraName);
    UpdateMonitorMicrophonesPlacement();
    PrintToConsole(client, "[MGE camera] POV mode disabled; restored camera: %s", g_sCurrentCameraName[0] ? g_sCurrentCameraName : "---");
    return Plugin_Handled;
}

Action Command_MgeCameraScanRelays(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    PrintToConsole(client, "===== MGE Relay Scan (sg_sm*) =====");
    int ent = -1;
    int total = 0;
    while ((ent = FindEntityByClassname(ent, "logic_relay")) != -1)
    {
        if (!IsValidEntity(ent))
            continue;

        char relayName[64];
        GetEntPropString(ent, Prop_Data, "m_iName", relayName, sizeof(relayName));
        if (relayName[0] == '\0' || StrContains(relayName, "sg_sm_", false) != 0)
            continue;

        int disabled = 0;
        if (HasEntProp(ent, Prop_Data, "m_bDisabled"))
            disabled = GetEntProp(ent, Prop_Data, "m_bDisabled");

        PrintToConsole(client, "ent=%d name=%s disabled=%d", ent, relayName, disabled);
        total++;
    }

    PrintToConsole(client, "total sg_sm relays: %d", total);
    return Plugin_Handled;
}

Action Command_MgeCameraTriggerPov(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;

    int relay = FindEntityByTargetName("logic_relay", "sg_sm_camera_pov");
    if (relay == -1)
    {
        relay = FindEntityByTargetName("logic_relay", "sg_sm_camera_pov_signal");
    }

    if (relay == -1)
    {
        PrintToConsole(client, "[MGE camera] relay not found: sg_sm_camera_pov / sg_sm_camera_pov_signal");
        return Plugin_Handled;
    }

    AcceptEntityInput(relay, "Trigger", client, client);
    PrintToConsole(client, "[MGE camera] Trigger sent to relay ent=%d", relay);
    LogMessage("[MGE camera] admin %N triggered POV relay ent=%d", client, relay);
    return Plugin_Handled;
}


// ===== HELP SYSTEM =====

// Display available commands and usage information to players
// TODO: refactor to menu
Action Command_Help(int client, int args)
{
    if (!client || !IsValidClient(client))
        return Plugin_Continue;

    PrintToChat(client, "%t", "Cmd_SeeConsole");
    PrintToConsole(client, "\n\n----------------------------");
    PrintToConsole(client, "%t", "Cmd_MGECmds");
    PrintToConsole(client, "%t", "Cmd_MGEMod");
    PrintToConsole(client, "%t", "Cmd_Add");
    PrintToConsole(client, "%t", "Cmd_Remove");
    PrintToConsole(client, "%t", "Cmd_First");
    PrintToConsole(client, "%t", "Cmd_Top5");
    PrintToConsole(client, "%t", "Cmd_Rank");
    PrintToConsole(client, "%t", "Cmd_Hud");
    PrintToConsole(client, "%t", "Cmd_Elo");
    PrintToConsole(client, "%t", "Cmd_Handicap");
    PrintToConsole(client, "----------------------------\n\n");

    return Plugin_Handled;
}


// ===== SOUND SYSTEM =====

// Block unwanted sounds like fall damage and regeneration
Action Sound_BlockSound(int clients[MAXPLAYERS], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char soundEntry[PLATFORM_MAX_PATH], int& seed)
{
    if (StrContains(sample, "pl_fallpain") >= 0 && g_bBlockFallDamage)
    {
        return Plugin_Handled;
    }

    if (StrContains(sample, "regenerate") >= 0)
    {
        return Plugin_Handled;
    }

    if (StrContains(sample, "ambient_mp3/lair/crocs_hiss", false) >= 0)
    {
        return Plugin_Handled;
    }

    if (StrContains(sample, "ambient_mp3/lair/crocs_growl", false) >= 0)
    {
        return Plugin_Handled;
    }

    if (StrContains(sample, "common/null.wav", false) >= 0)
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}


// ===== GAME EVENTS =====

// Disable stats tracking when match ends to prevent point loss from leavers
Action Event_WinPanel(Event event, const char[] name, bool dontBroadcast)
{
    // Disable stats so people leaving at the end of the map don't lose points.
    g_bNoStats = true;
    return Plugin_Continue;
}

// Initialize BBall hoops and KOTH capture points when round starts
Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    FindConVar("mp_waitingforplayers_cancel").SetInt(1);

    // BBall
    SetupBBallHoops();
    CacheBBallScoreboardEntities();
    UpdateBBallScoreboards();

    // KOTH
    SetupKothCapturePoints();

    return Plugin_Continue;
}

// Suppress team and class change broadcasts
Action Event_Suppress(Event event, const char[] name, bool dontBroadcast)
{
    event.BroadcastDisabled = true;
    return Plugin_Continue;
}

Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int newTeam = event.GetInt("team");
    if (IsValidClient(client) && newTeam == TEAM_SPEC)
    {
        // Check if player is in an active arena slot before removing from queue
        int player_arena = g_iPlayerArena[client];
        int player_slot = g_iPlayerSlot[client];

        if (player_arena > 0 && player_slot > 0)
        {
            int max_active_slot = g_bFourPersonArena[player_arena] ? SLOT_FOUR : SLOT_TWO;
            bool is_active_slot = (player_slot <= max_active_slot);
            bool is_waiting_2v2_spec = false;
            if (g_bFourPersonArena[player_arena] && view_as<bool>(g_iPlayerWaiting[client]))
            {
                is_waiting_2v2_spec = true;
            }

            // In 2v2, dead players can be parked in spectator temporarily while waiting for the round to finish.
            if (is_active_slot && !is_waiting_2v2_spec)
            {
                RemoveFromQueue(client, true, true);
            }
        }

        CreateTimer(0.3, Timer_ChangeSpecTarget, GetClientUserId(client));
    }
    return Plugin_Continue;
}
